use std::collections::VecDeque;
use std::thread;
use std::time::Duration;

use anyhow::{Error, Result, bail};

use crate::agent::model::{ModelClient, ModelStep, ModelUpdate, ToolCallRequest};
use crate::agent::session::{Event, SessionLog, ToolCallEvent};
use crate::agent::tools::{ToolOutput, ToolRegistry};

const MAX_TURNS_PER_JOB: usize = 16;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RuntimeOptions {
    pub max_turns_per_job: usize,
    pub retry_policy: RetryPolicy,
    pub auto_compact_after_events: Option<usize>,
    pub steering_mode: QueueMode,
    pub follow_up_mode: QueueMode,
}

impl Default for RuntimeOptions {
    fn default() -> Self {
        Self {
            max_turns_per_job: MAX_TURNS_PER_JOB,
            retry_policy: RetryPolicy::default(),
            auto_compact_after_events: None,
            steering_mode: QueueMode::OneAtATime,
            follow_up_mode: QueueMode::OneAtATime,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[allow(dead_code)]
pub enum QueueMode {
    All,
    OneAtATime,
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
    pub is_streaming: bool,
    pub streaming_role: Option<&'static str>,
    pub pending_tool_calls: Vec<String>,
    pub error_message: Option<String>,
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
    MessageUpdated {
        role: &'static str,
        delta: String,
    },
    ToolExecutionStarted {
        id: String,
        name: String,
    },
    ToolExecutionUpdated {
        id: String,
        name: String,
        partial_output: String,
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

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BeforeToolCallResult {
    pub block: bool,
    pub reason: Option<String>,
}

#[derive(Clone, Copy, Default)]
pub struct RuntimeHooks {
    pub before_tool_call: Option<fn(&ToolCallRequest) -> BeforeToolCallResult>,
    pub after_tool_call: Option<fn(&ToolCallRequest, ToolOutput, bool) -> (ToolOutput, bool)>,
    pub should_stop_after_turn: Option<fn(&RuntimeTurnSnapshot) -> bool>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RuntimeTurnSnapshot {
    pub index: usize,
    pub assistant_message: Option<String>,
    pub tool_results: Vec<String>,
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
    hooks: RuntimeHooks,
    stop_after_turn_requested: bool,
    skip_next_steering_poll: bool,
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
        Self::with_options_and_hooks(log, tools, model, options, RuntimeHooks::default())
    }

    pub fn with_options_and_hooks(
        log: SessionLog,
        tools: ToolRegistry,
        model: M,
        options: RuntimeOptions,
        hooks: RuntimeHooks,
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
                is_streaming: false,
                streaming_role: None,
                pending_tool_calls: Vec::new(),
                error_message: None,
            },
            events: Vec::new(),
            options,
            hooks,
            stop_after_turn_requested: false,
            skip_next_steering_poll: false,
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
        self.clear_queue();
        if self.state.is_running {
            self.state.cancel_requested = true;
        } else {
            self.emit(RuntimeEvent::Cancelled);
        }
    }

    pub fn run_message(&mut self, message: String) -> Result<String> {
        self.run_prompt(message)
    }

    pub fn continue_run(&mut self) -> Result<String> {
        if self.state.is_running {
            bail!("agent is already running");
        }
        let events = self.log.context_events();
        let Some(last) = events.last() else {
            bail!("no messages to continue from");
        };
        if matches!(
            last,
            Event::AssistantMessage { .. } | Event::ToolCall { .. } | Event::ToolCalls { .. }
        ) {
            if !self.steering_queue.is_empty() {
                let messages = self.drain_steering_messages();
                self.skip_next_steering_poll = true;
                return self.run_prompt_messages(messages);
            }
            if !self.follow_up_queue.is_empty() {
                let messages = self.drain_follow_up_messages();
                return self.run_prompt_messages(messages);
            }
            bail!("cannot continue from assistant message");
        }
        self.run_continuation()
    }

    fn run_prompt(&mut self, message: String) -> Result<String> {
        self.run_prompt_messages(vec![message])
    }

    fn run_prompt_messages(&mut self, messages: Vec<String>) -> Result<String> {
        self.state.is_running = true;
        self.state.cancel_requested = false;
        self.state.error_message = None;
        self.stop_after_turn_requested = false;
        self.emit(RuntimeEvent::AgentStarted);

        let result = self.run_prompt_inner(messages);

        self.state.is_running = false;
        self.state.turn_index = 0;
        match &result {
            Ok(_) => self.emit(RuntimeEvent::AgentFinished { will_retry: false }),
            Err(error) => {
                self.state.error_message = Some(error.to_string());
                self.emit(RuntimeEvent::AgentFinished { will_retry: false });
            }
        }
        result
    }

    fn run_continuation(&mut self) -> Result<String> {
        self.state.is_running = true;
        self.state.cancel_requested = false;
        self.state.error_message = None;
        self.stop_after_turn_requested = false;
        self.emit(RuntimeEvent::AgentStarted);

        let result = self.run_from_context();

        self.state.is_running = false;
        self.state.turn_index = 0;
        match &result {
            Ok(_) => self.emit(RuntimeEvent::AgentFinished { will_retry: false }),
            Err(error) => {
                self.state.error_message = Some(error.to_string());
                self.emit(RuntimeEvent::AgentFinished { will_retry: false });
            }
        }
        result
    }

    fn run_prompt_inner(&mut self, messages: Vec<String>) -> Result<String> {
        let mut latest_reply = self.run_single_messages(messages)?;
        if self.stop_after_turn_requested {
            self.stop_after_turn_requested = false;
            return Ok(latest_reply);
        }

        while !self.follow_up_queue.is_empty() {
            let messages = self.drain_follow_up_messages();
            latest_reply = self.run_single_messages(messages)?;
            if self.stop_after_turn_requested {
                self.stop_after_turn_requested = false;
                return Ok(latest_reply);
            }
        }

        Ok(latest_reply)
    }

    fn run_single_messages(&mut self, messages: Vec<String>) -> Result<String> {
        self.ensure_not_cancelled()?;
        self.log.append(Event::JobStarted)?;
        for message in messages {
            self.emit(RuntimeEvent::MessageStarted { role: "user" });
            self.log.append(Event::UserMessage { content: message })?;
            self.emit(RuntimeEvent::MessageFinished { role: "user" });
        }

        self.run_from_context()
    }

    fn run_from_context(&mut self) -> Result<String> {
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
                    let should_stop =
                        self.should_stop_after_turn(turn_index, Some(content.clone()), Vec::new());
                    if should_stop || self.steering_queue.is_empty() {
                        if should_stop {
                            self.stop_after_turn_requested = true;
                        }
                        self.log.append(Event::JobFinished)?;
                        self.check_auto_compaction_hook(false)?;
                        return Ok(content);
                    }
                }
                ModelStep::ToolCall {
                    id,
                    name,
                    arguments,
                } => {
                    let results = self.execute_tool_batch(vec![ToolCallRequest {
                        id,
                        name,
                        arguments,
                    }])?;
                    let latest_reply = results
                        .last()
                        .map(|result| result.output.content.clone())
                        .unwrap_or_default();
                    self.log.append(Event::TurnFinished { index: turn_index })?;
                    self.emit(RuntimeEvent::TurnFinished { index: turn_index });
                    let should_stop = self.should_stop_after_turn(
                        turn_index,
                        None,
                        results
                            .iter()
                            .map(|result| result.output.content.clone())
                            .collect(),
                    );
                    if should_stop || should_terminate_tool_batch(&results) {
                        if should_stop {
                            self.stop_after_turn_requested = true;
                        }
                        self.log.append(Event::JobFinished)?;
                        self.check_auto_compaction_hook(false)?;
                        return Ok(latest_reply);
                    }
                }
                ModelStep::ToolCalls(calls) => {
                    let results = self.execute_tool_batch(calls)?;
                    let latest_reply = results
                        .last()
                        .map(|result| result.output.content.clone())
                        .unwrap_or_default();
                    self.log.append(Event::TurnFinished { index: turn_index })?;
                    self.emit(RuntimeEvent::TurnFinished { index: turn_index });
                    let should_stop = self.should_stop_after_turn(
                        turn_index,
                        None,
                        results
                            .iter()
                            .map(|result| result.output.content.clone())
                            .collect(),
                    );
                    if should_stop || should_terminate_tool_batch(&results) {
                        if should_stop {
                            self.stop_after_turn_requested = true;
                        }
                        self.log.append(Event::JobFinished)?;
                        self.check_auto_compaction_hook(false)?;
                        return Ok(latest_reply);
                    }
                }
            }
        }

        bail!(
            "agent loop exceeded {} turns",
            self.options.max_turns_per_job
        )
    }

    fn execute_tool_batch(&mut self, calls: Vec<ToolCallRequest>) -> Result<Vec<ExecutedToolCall>> {
        self.emit(RuntimeEvent::MessageStarted { role: "assistant" });
        if let [call] = calls.as_slice() {
            self.log.append(Event::ToolCall {
                id: call.id.clone(),
                name: call.name.clone(),
                arguments: call.arguments.clone(),
            })?;
        } else {
            self.log.append(Event::ToolCalls {
                calls: calls
                    .iter()
                    .map(|call| ToolCallEvent {
                        id: call.id.clone(),
                        name: call.name.clone(),
                        arguments: call.arguments.clone(),
                    })
                    .collect(),
            })?;
        }
        self.emit(RuntimeEvent::MessageFinished { role: "assistant" });

        let mut results = Vec::new();
        for call in calls {
            let executed = self.execute_tool_call(call)?;
            self.emit(RuntimeEvent::MessageStarted { role: "toolResult" });
            self.log.append(Event::ToolResult {
                tool_call_id: executed.call.id.clone(),
                name: executed.call.name.clone(),
                output: executed.output.content.clone(),
                details: executed.output.details.clone(),
            })?;
            self.emit(RuntimeEvent::MessageFinished { role: "toolResult" });
            results.push(executed);
            self.ensure_not_cancelled()?;
        }
        Ok(results)
    }

    fn execute_tool_call(&mut self, call: ToolCallRequest) -> Result<ExecutedToolCall> {
        self.emit(RuntimeEvent::ToolExecutionStarted {
            id: call.id.clone(),
            name: call.name.clone(),
        });

        let mut output;
        let mut is_error = false;
        if let Some(before_tool_call) = self.hooks.before_tool_call
            && let BeforeToolCallResult {
                block: true,
                reason,
            } = before_tool_call(&call)
        {
            output = ToolOutput {
                content: reason.unwrap_or_else(|| "Tool execution was blocked".to_owned()),
                details: None,
                terminate: false,
            };
            is_error = true;
        } else {
            match self.tools.run(&call.name, &call.arguments) {
                Ok(result) => {
                    output = result;
                }
                Err(error) => {
                    output = ToolOutput {
                        content: error.to_string(),
                        details: None,
                        terminate: false,
                    };
                    is_error = true;
                }
            }
        }

        if let Some(after_tool_call) = self.hooks.after_tool_call {
            (output, is_error) = after_tool_call(&call, output, is_error);
        }

        self.emit(RuntimeEvent::ToolExecutionUpdated {
            id: call.id.clone(),
            name: call.name.clone(),
            partial_output: output.content.clone(),
        });
        self.emit(RuntimeEvent::ToolExecutionFinished {
            id: call.id.clone(),
            name: call.name.clone(),
            is_error,
        });
        Ok(ExecutedToolCall { call, output })
    }

    fn should_stop_after_turn(
        &self,
        index: usize,
        assistant_message: Option<String>,
        tool_results: Vec<String>,
    ) -> bool {
        self.hooks
            .should_stop_after_turn
            .map(|hook| {
                hook(&RuntimeTurnSnapshot {
                    index,
                    assistant_message,
                    tool_results,
                })
            })
            .unwrap_or(false)
    }

    fn append_queued_steering_messages(&mut self) -> Result<()> {
        if self.skip_next_steering_poll {
            self.skip_next_steering_poll = false;
            return Ok(());
        }
        for message in self.drain_steering_messages() {
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
            let mut emitted_updates = Vec::new();
            let result = self
                .model
                .next_step_with_updates(events, tool_specs, &mut |update| {
                    emitted_updates.push(update)
                });
            for update in emitted_updates {
                self.emit_model_update(update);
            }
            match result {
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

    fn drain_steering_messages(&mut self) -> Vec<String> {
        let messages = drain_queue(&mut self.steering_queue, self.options.steering_mode);
        if !messages.is_empty() {
            self.emit_queue_update();
        }
        messages
    }

    fn drain_follow_up_messages(&mut self) -> Vec<String> {
        let messages = drain_queue(&mut self.follow_up_queue, self.options.follow_up_mode);
        if !messages.is_empty() {
            self.emit_queue_update();
        }
        messages
    }

    fn emit_model_update(&mut self, update: ModelUpdate) {
        match update {
            ModelUpdate::MessageDelta { role, delta } => {
                self.emit(RuntimeEvent::MessageUpdated { role, delta });
            }
            ModelUpdate::ToolCallDelta {
                id,
                name,
                arguments_delta,
            } => {
                self.emit(RuntimeEvent::MessageUpdated {
                    role: "assistant",
                    delta: arguments_delta.clone(),
                });
                self.emit(RuntimeEvent::ToolExecutionUpdated {
                    id,
                    name,
                    partial_output: arguments_delta,
                });
            }
        }
    }

    fn emit(&mut self, event: RuntimeEvent) {
        match &event {
            RuntimeEvent::MessageStarted { role } => {
                self.state.is_streaming = true;
                self.state.streaming_role = Some(role);
            }
            RuntimeEvent::MessageUpdated { role, .. } => {
                self.state.is_streaming = true;
                self.state.streaming_role = Some(role);
            }
            RuntimeEvent::MessageFinished { .. } => {
                self.state.is_streaming = false;
                self.state.streaming_role = None;
            }
            RuntimeEvent::ToolExecutionStarted { id, .. } => {
                if !self
                    .state
                    .pending_tool_calls
                    .iter()
                    .any(|pending| pending == id)
                {
                    self.state.pending_tool_calls.push(id.clone());
                }
            }
            RuntimeEvent::ToolExecutionFinished { id, .. } => {
                self.state
                    .pending_tool_calls
                    .retain(|pending| pending != id);
            }
            RuntimeEvent::Cancelled => {
                self.state.cancel_requested = true;
            }
            RuntimeEvent::AgentFinished { .. } => {
                self.state.is_streaming = false;
                self.state.streaming_role = None;
                self.state.pending_tool_calls.clear();
            }
            RuntimeEvent::QueueUpdated { .. }
            | RuntimeEvent::AgentStarted
            | RuntimeEvent::TurnStarted { .. }
            | RuntimeEvent::TurnFinished { .. }
            | RuntimeEvent::AutoRetryStarted { .. }
            | RuntimeEvent::AutoRetryFinished { .. }
            | RuntimeEvent::ToolExecutionUpdated { .. }
            | RuntimeEvent::CompactionCheckStarted { .. }
            | RuntimeEvent::CompactionCheckFinished { .. } => {}
        }
        self.events.push(event);
    }
}

struct ExecutedToolCall {
    call: ToolCallRequest,
    output: ToolOutput,
}

fn should_terminate_tool_batch(results: &[ExecutedToolCall]) -> bool {
    !results.is_empty() && results.iter().all(|result| result.output.terminate)
}

fn drain_queue(queue: &mut VecDeque<String>, mode: QueueMode) -> Vec<String> {
    match mode {
        QueueMode::All => queue.drain(..).collect(),
        QueueMode::OneAtATime => queue.pop_front().into_iter().collect(),
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
    use crate::agent::model::{ModelClient, ModelStep, ModelUpdate};
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
        assert_eq!(user_messages, vec!["first", "steer now", "follow up"]);
    }

    #[test]
    fn drains_all_steering_messages_when_configured_like_pi() {
        let log = SessionLog::memory();
        let options = RuntimeOptions {
            steering_mode: QueueMode::All,
            ..RuntimeOptions::default()
        };
        let mut runtime = Runtime::with_options(log, ToolRegistry::minimal(), DryRunModel, options);

        runtime.queue_steer("steer one".to_owned());
        runtime.queue_steer("steer two".to_owned());
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

        assert_eq!(reply, "echo: steer two");
        assert_eq!(user_messages, vec!["first", "steer one", "steer two"]);
        assert_eq!(runtime.pending_message_count(), 0);
    }

    #[test]
    fn emits_streaming_model_updates_before_message_end() {
        let log = SessionLog::memory();
        let mut runtime = Runtime::new(log, ToolRegistry::minimal(), StreamingModel);

        let reply = runtime.run_message("hello".to_owned()).unwrap();

        assert_eq!(reply, "streamed");
        assert!(runtime.runtime_events().iter().any(|event| {
            matches!(
                event,
                RuntimeEvent::MessageUpdated {
                    role: "assistant",
                    delta
                } if delta == "stream"
            )
        }));
        assert!(runtime.runtime_events().iter().any(|event| {
            matches!(
                event,
                RuntimeEvent::ToolExecutionUpdated {
                    id,
                    name,
                    partial_output
                } if id == "call_stream" && name == "bash" && partial_output == "{}"
            )
        }));
    }

    #[test]
    fn executes_multiple_tool_calls_from_one_assistant_message() {
        let log = SessionLog::memory();
        let mut runtime = Runtime::new(log, ToolRegistry::minimal(), BatchToolModel);

        let reply = runtime.run_message("run both".to_owned()).unwrap();

        assert_eq!(reply, "saw 2 tool results");
        assert!(
            runtime
                .log
                .events()
                .iter()
                .any(|event| { matches!(event, Event::ToolCalls { calls } if calls.len() == 2) })
        );
        assert_eq!(
            runtime
                .log
                .events()
                .iter()
                .filter(|event| matches!(event, Event::ToolResult { .. }))
                .count(),
            2
        );
        assert!(runtime.state().pending_tool_calls.is_empty());
        assert!(!runtime.state().is_streaming);
    }

    #[test]
    fn continues_from_existing_tool_result_context() {
        let mut log = SessionLog::memory();
        log.append(Event::UserMessage {
            content: "continue".to_owned(),
        })
        .unwrap();
        log.append(Event::ToolResult {
            tool_call_id: "call_1".to_owned(),
            name: "bash".to_owned(),
            output: "done".to_owned(),
            details: None,
        })
        .unwrap();
        let mut runtime = Runtime::new(log, ToolRegistry::minimal(), DryRunModel);

        let reply = runtime.continue_run().unwrap();

        assert_eq!(reply, "tool result: done");
    }

    #[test]
    fn continue_from_assistant_uses_queued_steering_without_draining_next_item() {
        let mut log = SessionLog::memory();
        log.append(Event::UserMessage {
            content: "first".to_owned(),
        })
        .unwrap();
        log.append(Event::AssistantMessage {
            content: "done".to_owned(),
        })
        .unwrap();
        let mut runtime = Runtime::new(log, ToolRegistry::minimal(), DryRunModel);

        runtime.queue_steer("steer one".to_owned());
        runtime.queue_steer("steer two".to_owned());
        let reply = runtime.continue_run().unwrap();

        assert_eq!(reply, "echo: steer two");
        assert_eq!(runtime.pending_message_count(), 0);
        assert_eq!(
            runtime
                .runtime_events()
                .iter()
                .filter(|event| matches!(event, RuntimeEvent::TurnStarted { .. }))
                .count(),
            2
        );
    }

    #[test]
    fn before_tool_call_hook_blocks_execution_as_error_tool_result() {
        let log = SessionLog::memory();
        let hooks = RuntimeHooks {
            before_tool_call: Some(block_bash_tool),
            ..RuntimeHooks::default()
        };
        let mut runtime = Runtime::with_options_and_hooks(
            log,
            ToolRegistry::minimal(),
            DryRunModel,
            RuntimeOptions::default(),
            hooks,
        );

        let reply = runtime.run_message("what is pwd".to_owned()).unwrap();

        assert_eq!(reply, "tool result: blocked by test hook");
        assert!(runtime.runtime_events().iter().any(|event| {
            matches!(
                event,
                RuntimeEvent::ToolExecutionFinished { is_error: true, .. }
            )
        }));
    }

    #[test]
    fn after_tool_call_hook_can_override_and_terminate_batch() {
        let log = SessionLog::memory();
        let hooks = RuntimeHooks {
            after_tool_call: Some(terminate_after_tool_call),
            ..RuntimeHooks::default()
        };
        let mut runtime = Runtime::with_options_and_hooks(
            log,
            ToolRegistry::minimal(),
            AlwaysToolModel,
            RuntimeOptions::default(),
            hooks,
        );

        let reply = runtime.run_message("stop after tool".to_owned()).unwrap();

        assert_eq!(reply, "stop now");
        assert_eq!(
            runtime
                .log
                .events()
                .iter()
                .filter(|event| matches!(event, Event::ToolCall { .. }))
                .count(),
            1
        );
    }

    #[test]
    fn should_stop_after_turn_hook_prevents_follow_up_polling() {
        let log = SessionLog::memory();
        let hooks = RuntimeHooks {
            should_stop_after_turn: Some(stop_after_first_turn),
            ..RuntimeHooks::default()
        };
        let mut runtime = Runtime::with_options_and_hooks(
            log,
            ToolRegistry::minimal(),
            DryRunModel,
            RuntimeOptions::default(),
            hooks,
        );

        runtime.queue_follow_up("follow up".to_owned());
        let reply = runtime.run_message("first".to_owned()).unwrap();

        assert_eq!(reply, "echo: first");
        assert_eq!(runtime.pending_message_count(), 1);
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

    struct StreamingModel;

    impl ModelClient for StreamingModel {
        fn next_step(
            &mut self,
            _events: &[Event],
            _tools: &[crate::agent::tools::ToolSpec],
        ) -> Result<ModelStep> {
            Ok(ModelStep::Final("streamed".to_owned()))
        }

        fn next_step_with_updates(
            &mut self,
            events: &[Event],
            tools: &[crate::agent::tools::ToolSpec],
            updates: &mut dyn FnMut(ModelUpdate),
        ) -> Result<ModelStep> {
            let _ = events;
            let _ = tools;
            updates(ModelUpdate::MessageDelta {
                role: "assistant",
                delta: "stream".to_owned(),
            });
            updates(ModelUpdate::ToolCallDelta {
                id: "call_stream".to_owned(),
                name: "bash".to_owned(),
                arguments_delta: "{}".to_owned(),
            });
            self.next_step(events, tools)
        }
    }

    struct BatchToolModel;

    impl ModelClient for BatchToolModel {
        fn next_step(
            &mut self,
            events: &[Event],
            _tools: &[crate::agent::tools::ToolSpec],
        ) -> Result<ModelStep> {
            let tool_results = events
                .iter()
                .filter(|event| matches!(event, Event::ToolResult { .. }))
                .count();
            if tool_results > 0 {
                return Ok(ModelStep::Final(format!("saw {tool_results} tool results")));
            }
            Ok(ModelStep::ToolCalls(vec![
                ToolCallRequest {
                    id: "call_one".to_owned(),
                    name: "bash".to_owned(),
                    arguments: json!({ "command": "printf one" }),
                },
                ToolCallRequest {
                    id: "call_two".to_owned(),
                    name: "bash".to_owned(),
                    arguments: json!({ "command": "printf two" }),
                },
            ]))
        }
    }

    struct AlwaysToolModel;

    impl ModelClient for AlwaysToolModel {
        fn next_step(
            &mut self,
            _events: &[Event],
            _tools: &[crate::agent::tools::ToolSpec],
        ) -> Result<ModelStep> {
            Ok(ModelStep::ToolCall {
                id: "call_stop".to_owned(),
                name: "bash".to_owned(),
                arguments: json!({ "command": "printf ignored" }),
            })
        }
    }

    fn block_bash_tool(call: &ToolCallRequest) -> BeforeToolCallResult {
        BeforeToolCallResult {
            block: call.name == "bash",
            reason: Some("blocked by test hook".to_owned()),
        }
    }

    fn terminate_after_tool_call(
        _call: &ToolCallRequest,
        mut output: ToolOutput,
        is_error: bool,
    ) -> (ToolOutput, bool) {
        output.content = "stop now".to_owned();
        output.terminate = true;
        (output, is_error)
    }

    fn stop_after_first_turn(snapshot: &RuntimeTurnSnapshot) -> bool {
        snapshot.index == 1
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
