use std::collections::VecDeque;
use std::thread;
use std::time::Duration;

use anyhow::{Error, Result, bail};

use crate::agent::model::{ModelClient, ModelStep};
use crate::agent::session::{Event, SessionLog};
use crate::agent::tools::ToolRegistry;

const MAX_TURNS_PER_JOB: usize = 16;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RuntimeOptions {
    pub max_turns_per_job: usize,
    pub retry_policy: RetryPolicy,
    pub auto_compact_after_events: Option<usize>,
}

impl Default for RuntimeOptions {
    fn default() -> Self {
        Self {
            max_turns_per_job: MAX_TURNS_PER_JOB,
            retry_policy: RetryPolicy::default(),
            auto_compact_after_events: None,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RetryPolicy {
    pub max_attempts: usize,
    pub base_delay_ms: u64,
}

impl Default for RetryPolicy {
    fn default() -> Self {
        Self {
            max_attempts: 0,
            base_delay_ms: 250,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RuntimeState {
    pub is_running: bool,
    pub cancel_requested: bool,
    pub retry_attempt: usize,
    pub turn_index: usize,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum RuntimeEvent {
    QueueUpdated {
        steering: Vec<String>,
        follow_up: Vec<String>,
    },
    AgentStarted,
    AgentFinished {
        will_retry: bool,
    },
    TurnStarted {
        index: usize,
    },
    TurnFinished {
        index: usize,
    },
    MessageStarted {
        role: &'static str,
    },
    MessageFinished {
        role: &'static str,
    },
    ToolExecutionStarted {
        id: String,
        name: String,
    },
    ToolExecutionFinished {
        id: String,
        name: String,
        is_error: bool,
    },
    AutoRetryStarted {
        attempt: usize,
        max_attempts: usize,
        delay_ms: u64,
        error_message: String,
    },
    AutoRetryFinished {
        success: bool,
        attempt: usize,
        final_error: Option<String>,
    },
    CompactionCheckStarted {
        reason: &'static str,
    },
    CompactionCheckFinished {
        reason: &'static str,
        ran: bool,
        will_retry: bool,
        error_message: Option<String>,
    },
    Cancelled,
}

pub struct Runtime<M: ModelClient> {
    log: SessionLog,
    tools: ToolRegistry,
    model: M,
    steering_queue: VecDeque<String>,
    follow_up_queue: VecDeque<String>,
    state: RuntimeState,
    events: Vec<RuntimeEvent>,
    options: RuntimeOptions,
}

#[allow(dead_code)]
impl<M: ModelClient> Runtime<M> {
    pub fn new(log: SessionLog, tools: ToolRegistry, model: M) -> Self {
        Self::with_options(log, tools, model, RuntimeOptions::default())
    }

    pub fn with_options(
        log: SessionLog,
        tools: ToolRegistry,
        model: M,
        options: RuntimeOptions,
    ) -> Self {
        Self {
            log,
            tools,
            model,
            steering_queue: VecDeque::new(),
            follow_up_queue: VecDeque::new(),
            state: RuntimeState {
                is_running: false,
                cancel_requested: false,
                retry_attempt: 0,
                turn_index: 0,
            },
            events: Vec::new(),
            options,
        }
    }

    pub fn state(&self) -> &RuntimeState {
        &self.state
    }

    pub fn runtime_events(&self) -> &[RuntimeEvent] {
        &self.events
    }

    pub fn queue_steer(&mut self, message: String) {
        self.steering_queue.push_back(message);
        self.emit_queue_update();
    }

    pub fn queue_follow_up(&mut self, message: String) {
        self.follow_up_queue.push_back(message);
        self.emit_queue_update();
    }

    pub fn clear_queue(&mut self) -> (Vec<String>, Vec<String>) {
        let steering = self.steering_queue.drain(..).collect::<Vec<_>>();
        let follow_up = self.follow_up_queue.drain(..).collect::<Vec<_>>();
        self.emit_queue_update();
        (steering, follow_up)
    }

    pub fn pending_message_count(&self) -> usize {
        self.steering_queue.len() + self.follow_up_queue.len()
    }

    pub fn abort(&mut self) {
        if self.state.is_running {
            self.state.cancel_requested = true;
        } else {
            self.clear_queue();
            self.emit(RuntimeEvent::Cancelled);
        }
    }

    pub fn run_message(&mut self, message: String) -> Result<String> {
        self.follow_up_queue.push_front(message);
        self.emit_queue_update();
        self.drain_queued()
    }

    fn drain_queued(&mut self) -> Result<String> {
        self.state.is_running = true;
        self.state.cancel_requested = false;
        self.emit(RuntimeEvent::AgentStarted);

        let result = self.drain_queued_inner();

        self.state.is_running = false;
        self.state.turn_index = 0;
        if result.is_ok() {
            self.emit(RuntimeEvent::AgentFinished { will_retry: false });
        }
        result
    }

    fn drain_queued_inner(&mut self) -> Result<String> {
        let mut latest_reply = None;

        while let Some(message) = self.next_queued_message() {
            self.emit_queue_update();
            latest_reply = Some(self.run_single_message(message)?);
        }

        latest_reply.ok_or_else(|| anyhow::anyhow!("no queued job"))
    }

    fn run_single_message(&mut self, message: String) -> Result<String> {
        self.ensure_not_cancelled()?;
        self.log.append(Event::JobStarted)?;
        self.emit(RuntimeEvent::MessageStarted { role: "user" });
        self.log.append(Event::UserMessage { content: message })?;
        self.emit(RuntimeEvent::MessageFinished { role: "user" });

        for turn_index in 1..=self.options.max_turns_per_job {
            self.ensure_not_cancelled()?;
            self.state.turn_index = turn_index;
            self.emit(RuntimeEvent::TurnStarted { index: turn_index });
            self.log.append(Event::TurnStarted { index: turn_index })?;

            self.append_queued_steering_messages()?;
            let events = self.log.context_events();
            let tool_specs = self.tools.specs();

            match self.next_step_with_retry(&events, &tool_specs)? {
                ModelStep::Final(content) => {
                    self.emit(RuntimeEvent::MessageStarted { role: "assistant" });
                    self.log.append(Event::AssistantMessage {
                        content: content.clone(),
                    })?;
                    self.emit(RuntimeEvent::MessageFinished { role: "assistant" });
                    self.log.append(Event::TurnFinished { index: turn_index })?;
                    self.emit(RuntimeEvent::TurnFinished { index: turn_index });
                    self.log.append(Event::JobFinished)?;
                    self.check_auto_compaction_hook(false)?;
                    return Ok(content);
                }
                ModelStep::ToolCall {
                    id,
                    name,
                    arguments,
                } => {
                    self.emit(RuntimeEvent::MessageStarted { role: "assistant" });
                    self.log.append(Event::ToolCall {
                        id: id.clone(),
                        name: name.clone(),
                        arguments: arguments.clone(),
                    })?;
                    self.emit(RuntimeEvent::MessageFinished { role: "assistant" });
                    self.emit(RuntimeEvent::ToolExecutionStarted {
                        id: id.clone(),
                        name: name.clone(),
                    });
                    let output = self.tools.run(&name, &arguments)?;
                    self.emit(RuntimeEvent::ToolExecutionFinished {
                        id: id.clone(),
                        name: name.clone(),
                        is_error: false,
                    });
                    self.emit(RuntimeEvent::MessageStarted { role: "toolResult" });
                    self.log.append(Event::ToolResult {
                        tool_call_id: id,
                        name,
                        output: output.content,
                        details: output.details,
                    })?;
                    self.emit(RuntimeEvent::MessageFinished { role: "toolResult" });
                    self.log.append(Event::TurnFinished { index: turn_index })?;
                    self.emit(RuntimeEvent::TurnFinished { index: turn_index });
                }
            }
        }

        bail!(
            "agent loop exceeded {} turns",
            self.options.max_turns_per_job
        )
    }

    fn next_queued_message(&mut self) -> Option<String> {
        self.steering_queue
            .pop_front()
            .or_else(|| self.follow_up_queue.pop_front())
    }

    fn append_queued_steering_messages(&mut self) -> Result<()> {
        while let Some(message) = self.steering_queue.pop_front() {
            self.emit_queue_update();
            self.emit(RuntimeEvent::MessageStarted { role: "user" });
            self.log.append(Event::UserMessage { content: message })?;
            self.emit(RuntimeEvent::MessageFinished { role: "user" });
        }
        Ok(())
    }

    fn next_step_with_retry(
        &mut self,
        events: &[Event],
        tool_specs: &[crate::agent::tools::ToolSpec],
    ) -> Result<ModelStep> {
        let mut retry_attempt = 0;
        loop {
            self.ensure_not_cancelled()?;
            match self.model.next_step(events, tool_specs) {
                Ok(step) => {
                    if retry_attempt > 0 {
                        self.emit(RuntimeEvent::AutoRetryFinished {
                            success: true,
                            attempt: retry_attempt,
                            final_error: None,
                        });
                    }
                    self.state.retry_attempt = 0;
                    return Ok(step);
                }
                Err(error)
                    if retry_attempt < self.options.retry_policy.max_attempts
                        && is_retryable_error(&error) =>
                {
                    retry_attempt += 1;
                    self.state.retry_attempt = retry_attempt;
                    let delay_ms = retry_delay_ms(&self.options.retry_policy, retry_attempt);
                    self.emit(RuntimeEvent::AutoRetryStarted {
                        attempt: retry_attempt,
                        max_attempts: self.options.retry_policy.max_attempts,
                        delay_ms,
                        error_message: error.to_string(),
                    });
                    if delay_ms > 0 {
                        thread::sleep(Duration::from_millis(delay_ms));
                    }
                }
                Err(error) => {
                    if retry_attempt > 0 {
                        self.emit(RuntimeEvent::AutoRetryFinished {
                            success: false,
                            attempt: retry_attempt,
                            final_error: Some(error.to_string()),
                        });
                    }
                    self.state.retry_attempt = 0;
                    return Err(error);
                }
            }
        }
    }

    fn check_auto_compaction_hook(&mut self, will_retry: bool) -> Result<()> {
        let Some(threshold) = self.options.auto_compact_after_events else {
            return Ok(());
        };
        if self.log.events().len() < threshold {
            return Ok(());
        }

        self.emit(RuntimeEvent::CompactionCheckStarted {
            reason: "threshold",
        });
        self.emit(RuntimeEvent::CompactionCheckFinished {
            reason: "threshold",
            ran: false,
            will_retry,
            error_message: Some(
                "session compaction is not implemented until session-log compaction entries exist"
                    .to_owned(),
            ),
        });
        Ok(())
    }

    fn ensure_not_cancelled(&mut self) -> Result<()> {
        if self.state.cancel_requested {
            self.emit(RuntimeEvent::Cancelled);
            bail!("agent run cancelled");
        }
        Ok(())
    }

    fn emit_queue_update(&mut self) {
        self.emit(RuntimeEvent::QueueUpdated {
            steering: self.steering_queue.iter().cloned().collect(),
            follow_up: self.follow_up_queue.iter().cloned().collect(),
        });
    }

    fn emit(&mut self, event: RuntimeEvent) {
        self.events.push(event);
    }
}

fn retry_delay_ms(policy: &RetryPolicy, attempt: usize) -> u64 {
    policy
        .base_delay_ms
        .saturating_mul(2_u64.saturating_pow(attempt.saturating_sub(1) as u32))
}

fn is_retryable_error(error: &Error) -> bool {
    let message = error.to_string().to_ascii_lowercase();
    [
        "overloaded",
        "rate limit",
        "too many requests",
        "429",
        "500",
        "502",
        "503",
        "504",
        "service unavailable",
        "server error",
        "internal error",
        "network",
        "connection",
        "timeout",
        "timed out",
        "fetch failed",
        "terminated",
    ]
    .iter()
    .any(|needle| message.contains(needle))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::agent::model::{ModelClient, ModelStep};
    use crate::agent::session::SessionLog;
    use crate::agent::tools::ToolRegistry;
    use crate::agent::{DryRunModel, OpenAiCompletionsModel, OpenAiResponsesModel};
    use anyhow::anyhow;
    use serde_json::{Value, json};
    use std::io::{Read, Write};
    use std::net::{TcpListener, TcpStream};
    use std::sync::mpsc;
    use std::thread;

    #[test]
    fn finishes_simple_message() {
        let log = SessionLog::memory();
        let mut runtime = Runtime::new(log, ToolRegistry::minimal(), DryRunModel);

        let reply = runtime.run_message("hello".to_owned()).unwrap();

        assert_eq!(reply, "echo: hello");
    }

    #[test]
    fn runs_tool_before_final_reply() {
        let log = SessionLog::memory();
        let mut runtime = Runtime::new(log, ToolRegistry::minimal(), DryRunModel);

        let reply = runtime.run_message("what is pwd".to_owned()).unwrap();

        assert!(reply.starts_with("tool result: "));
        assert!(reply.contains("/"));
    }

    #[test]
    fn does_not_reuse_previous_tool_result() {
        let log = SessionLog::memory();
        let mut runtime = Runtime::new(log, ToolRegistry::minimal(), DryRunModel);

        runtime.run_message("what is pwd".to_owned()).unwrap();
        let reply = runtime.run_message("hello".to_owned()).unwrap();

        assert_eq!(reply, "echo: hello");
    }

    #[test]
    fn persists_turn_boundaries_and_tool_call_ids() {
        let log = SessionLog::memory();
        let mut runtime = Runtime::new(log, ToolRegistry::minimal(), DryRunModel);

        runtime.run_message("what is pwd".to_owned()).unwrap();

        let events = runtime.log.events();
        assert!(matches!(events[2], Event::TurnStarted { index: 1 }));
        assert!(
            events
                .iter()
                .any(|event| matches!(event, Event::ToolCall { id, name, .. } if id == "dry-run-tool-call-1" && name == "bash"))
        );
        assert!(
            events
                .iter()
                .any(|event| matches!(event, Event::ToolResult { tool_call_id, name, .. } if tool_call_id == "dry-run-tool-call-1" && name == "bash"))
        );
    }

    #[test]
    fn emits_pi_style_runtime_lifecycle_events() {
        let log = SessionLog::memory();
        let mut runtime = Runtime::new(log, ToolRegistry::minimal(), DryRunModel);

        runtime.run_message("what is pwd".to_owned()).unwrap();

        assert!(!runtime.state().is_running);
        assert_eq!(runtime.state().retry_attempt, 0);
        assert!(
            runtime
                .runtime_events()
                .iter()
                .any(|event| matches!(event, RuntimeEvent::AgentStarted))
        );
        assert!(
            runtime
                .runtime_events()
                .iter()
                .any(|event| matches!(event, RuntimeEvent::MessageStarted { role: "user" }))
        );
        assert!(runtime.runtime_events().iter().any(|event| {
            matches!(event, RuntimeEvent::ToolExecutionStarted { id, name }
                    if id == "dry-run-tool-call-1" && name == "bash")
        }));
        assert!(
            runtime
                .runtime_events()
                .iter()
                .any(|event| matches!(event, RuntimeEvent::AgentFinished { will_retry: false }))
        );
    }

    #[test]
    fn drains_direct_prompt_before_follow_up_queue() {
        let log = SessionLog::memory();
        let mut runtime = Runtime::new(log, ToolRegistry::minimal(), DryRunModel);

        runtime.queue_follow_up("second".to_owned());
        let reply = runtime.run_message("first".to_owned()).unwrap();

        let user_messages = runtime
            .log
            .events()
            .iter()
            .filter_map(|event| match event {
                Event::UserMessage { content } => Some(content.as_str()),
                _ => None,
            })
            .collect::<Vec<_>>();

        assert_eq!(reply, "echo: second");
        assert_eq!(user_messages, vec!["first", "second"]);
        assert_eq!(runtime.pending_message_count(), 0);
    }

    #[test]
    fn prioritizes_steering_queue_over_follow_up_queue() {
        let log = SessionLog::memory();
        let mut runtime = Runtime::new(log, ToolRegistry::minimal(), DryRunModel);

        runtime.queue_follow_up("follow up".to_owned());
        runtime.queue_steer("steer now".to_owned());
        let reply = runtime.run_message("first".to_owned()).unwrap();

        let user_messages = runtime
            .log
            .events()
            .iter()
            .filter_map(|event| match event {
                Event::UserMessage { content } => Some(content.as_str()),
                _ => None,
            })
            .collect::<Vec<_>>();

        assert_eq!(reply, "echo: follow up");
        assert_eq!(user_messages, vec!["steer now", "first", "follow up"]);
    }

    #[test]
    fn retries_retryable_model_errors_with_events() {
        let log = SessionLog::memory();
        let options = RuntimeOptions {
            retry_policy: RetryPolicy {
                max_attempts: 1,
                base_delay_ms: 0,
            },
            ..RuntimeOptions::default()
        };
        let mut runtime = Runtime::with_options(
            log,
            ToolRegistry::minimal(),
            FailsOnceModel::default(),
            options,
        );

        let reply = runtime.run_message("hello".to_owned()).unwrap();

        assert_eq!(reply, "recovered");
        assert!(runtime.runtime_events().iter().any(|event| {
            matches!(
                event,
                RuntimeEvent::AutoRetryStarted {
                    attempt: 1,
                    max_attempts: 1,
                    ..
                }
            )
        }));
        assert!(runtime.runtime_events().iter().any(|event| {
            matches!(
                event,
                RuntimeEvent::AutoRetryFinished {
                    success: true,
                    attempt: 1,
                    ..
                }
            )
        }));
    }

    #[test]
    fn emits_auto_compaction_hook_events_without_session_compaction() {
        let log = SessionLog::memory();
        let options = RuntimeOptions {
            auto_compact_after_events: Some(1),
            ..RuntimeOptions::default()
        };
        let mut runtime = Runtime::with_options(log, ToolRegistry::minimal(), DryRunModel, options);

        runtime.run_message("hello".to_owned()).unwrap();

        assert!(runtime.runtime_events().iter().any(|event| matches!(
            event,
            RuntimeEvent::CompactionCheckStarted {
                reason: "threshold"
            }
        )));
        assert!(runtime.runtime_events().iter().any(|event| {
            matches!(
                event,
                RuntimeEvent::CompactionCheckFinished {
                    reason: "threshold",
                    ran: false,
                    will_retry: false,
                    error_message: Some(_)
                }
            )
        }));
    }

    #[test]
    fn abort_when_idle_clears_queues() {
        let log = SessionLog::memory();
        let mut runtime = Runtime::new(log, ToolRegistry::minimal(), DryRunModel);

        runtime.queue_steer("steer".to_owned());
        runtime.queue_follow_up("follow".to_owned());
        runtime.abort();

        assert_eq!(runtime.pending_message_count(), 0);
        assert!(
            runtime
                .runtime_events()
                .iter()
                .any(|event| matches!(event, RuntimeEvent::Cancelled))
        );
    }

    #[test]
    fn openai_completions_adapter_continues_after_tool_result() {
        let server = TestProvider::start(vec![
            json!({
                "choices": [{
                    "message": {
                        "content": null,
                        "tool_calls": [{
                            "id": "call_pwd",
                            "type": "function",
                            "function": {
                                "name": "bash",
                                "arguments": "{\"command\":\"pwd\"}"
                            }
                        }]
                    }
                }]
            }),
            json!({
                "choices": [{
                    "message": {
                        "content": "I checked the current directory."
                    }
                }]
            }),
        ]);
        let log = SessionLog::memory();
        let model = OpenAiCompletionsModel::new(
            server.base_url(),
            "test-key".to_owned(),
            "test-model".to_owned(),
        );
        let mut runtime = Runtime::new(log, ToolRegistry::minimal(), model);

        let reply = runtime.run_message("use pwd".to_owned()).unwrap();
        let requests = server.requests();

        assert_eq!(reply, "I checked the current directory.");
        assert_eq!(requests.len(), 2);
        assert_eq!(requests[0]["model"], "test-model");
        assert_eq!(requests[0]["tools"][1]["function"]["name"], "bash");
        assert_eq!(
            requests[1]["messages"][2]["tool_calls"][0]["id"],
            "call_pwd"
        );
        assert_eq!(requests[1]["messages"][3]["role"], "tool");
        assert_eq!(requests[1]["messages"][3]["tool_call_id"], "call_pwd");
    }

    #[test]
    fn openai_responses_adapter_continues_after_tool_result() {
        let server = TestProvider::start(vec![
            json!({
                "output": [{
                    "type": "function_call",
                    "id": "fc_pwd",
                    "call_id": "call_pwd",
                    "name": "bash",
                    "arguments": "{\"command\":\"pwd\"}"
                }]
            }),
            json!({
                "output": [{
                    "type": "message",
                    "role": "assistant",
                    "content": [{
                        "type": "output_text",
                        "text": "I checked the current directory.",
                        "annotations": []
                    }]
                }]
            }),
        ]);
        let log = SessionLog::memory();
        let model = OpenAiResponsesModel::new(
            server.base_url(),
            "test-key".to_owned(),
            "test-model".to_owned(),
        );
        let mut runtime = Runtime::new(log, ToolRegistry::minimal(), model);

        let reply = runtime.run_message("use pwd".to_owned()).unwrap();
        let requests = server.requests();

        assert_eq!(reply, "I checked the current directory.");
        assert_eq!(requests.len(), 2);
        assert_eq!(requests[0]["model"], "test-model");
        assert_eq!(requests[0]["store"], false);
        assert_eq!(requests[0]["tools"][0]["type"], "function");
        assert_eq!(requests[0]["tools"][1]["name"], "bash");
        assert_eq!(requests[1]["input"][2]["type"], "function_call");
        assert_eq!(requests[1]["input"][2]["call_id"], "call_pwd");
        assert_eq!(requests[1]["input"][2]["id"], "fc_pwd");
        assert_eq!(requests[1]["input"][3]["type"], "function_call_output");
        assert_eq!(requests[1]["input"][3]["call_id"], "call_pwd");
    }

    #[derive(Default)]
    struct FailsOnceModel {
        calls: usize,
    }

    impl ModelClient for FailsOnceModel {
        fn next_step(
            &mut self,
            _events: &[Event],
            _tools: &[crate::agent::tools::ToolSpec],
        ) -> Result<ModelStep> {
            self.calls += 1;
            if self.calls == 1 {
                return Err(anyhow!("provider returned 503: service unavailable"));
            }
            Ok(ModelStep::Final("recovered".to_owned()))
        }
    }

    struct TestProvider {
        base_url: String,
        requests: mpsc::Receiver<Value>,
        handle: thread::JoinHandle<()>,
    }

    impl TestProvider {
        fn start(responses: Vec<Value>) -> Self {
            let listener = TcpListener::bind("127.0.0.1:0").unwrap();
            let base_url = format!("http://{}", listener.local_addr().unwrap());
            let (tx, rx) = mpsc::channel();
            let handle = thread::spawn(move || {
                for response in responses {
                    let (mut stream, _) = listener.accept().unwrap();
                    let body = read_http_body(&mut stream);
                    tx.send(serde_json::from_str(&body).unwrap()).unwrap();
                    write_http_json(&mut stream, &response);
                }
            });

            Self {
                base_url,
                requests: rx,
                handle,
            }
        }

        fn base_url(&self) -> String {
            self.base_url.clone()
        }

        fn requests(self) -> Vec<Value> {
            let _ = self.handle.join();
            self.requests.try_iter().collect()
        }
    }

    fn read_http_body(stream: &mut TcpStream) -> String {
        let mut buffer = Vec::new();
        let mut chunk = [0; 4096];
        loop {
            let count = stream.read(&mut chunk).unwrap();
            assert!(count > 0);
            buffer.extend_from_slice(&chunk[..count]);
            if let Some(length) = content_length(&buffer) {
                let header_end = find_header_end(&buffer).unwrap();
                let body_len = buffer.len() - header_end;
                if body_len >= length {
                    return String::from_utf8(buffer[header_end..header_end + length].to_vec())
                        .unwrap();
                }
            }
        }
    }

    fn content_length(buffer: &[u8]) -> Option<usize> {
        let headers = String::from_utf8_lossy(buffer);
        let header_text = headers.split("\r\n\r\n").next()?;
        for line in header_text.lines() {
            let Some((name, value)) = line.split_once(':') else {
                continue;
            };
            if name.eq_ignore_ascii_case("content-length") {
                return value.trim().parse().ok();
            }
        }
        None
    }

    fn find_header_end(buffer: &[u8]) -> Option<usize> {
        buffer
            .windows(4)
            .position(|window| window == b"\r\n\r\n")
            .map(|index| index + 4)
    }

    fn write_http_json(stream: &mut TcpStream, value: &Value) {
        let body = value.to_string();
        write!(
            stream,
            "HTTP/1.1 200 OK\r\ncontent-type: application/json\r\ncontent-length: {}\r\nconnection: close\r\n\r\n{}",
            body.len(),
            body
        )
        .unwrap();
        stream.flush().unwrap();
    }
}
