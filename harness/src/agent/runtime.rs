use std::collections::VecDeque;

use anyhow::{Result, bail};

use crate::agent::model::{ModelClient, ModelStep};
use crate::agent::session::{Event, SessionLog};
use crate::agent::tools::ToolRegistry;

const MAX_TURNS_PER_JOB: usize = 16;

pub struct Runtime<M: ModelClient> {
    log: SessionLog,
    tools: ToolRegistry,
    model: M,
    queue: VecDeque<String>,
}

impl<M: ModelClient> Runtime<M> {
    pub fn new(log: SessionLog, tools: ToolRegistry, model: M) -> Self {
        Self {
            log,
            tools,
            model,
            queue: VecDeque::new(),
        }
    }

    pub fn run_message(&mut self, message: String) -> Result<String> {
        self.queue.push_back(message);
        self.drain_next()
    }

    fn drain_next(&mut self) -> Result<String> {
        let message = self
            .queue
            .pop_front()
            .ok_or_else(|| anyhow::anyhow!("no queued job"))?;

        self.log.append(Event::JobStarted)?;
        self.log.append(Event::UserMessage { content: message })?;

        for turn_index in 1..=MAX_TURNS_PER_JOB {
            self.log.append(Event::TurnStarted { index: turn_index })?;
            let events = self.log.events().to_vec();
            let tool_specs = self.tools.specs();

            match self.model.next_step(&events, &tool_specs)? {
                ModelStep::Final(content) => {
                    self.log.append(Event::AssistantMessage {
                        content: content.clone(),
                    })?;
                    self.log.append(Event::TurnFinished { index: turn_index })?;
                    self.log.append(Event::JobFinished)?;
                    return Ok(content);
                }
                ModelStep::ToolCall {
                    id,
                    name,
                    arguments,
                } => {
                    self.log.append(Event::ToolCall {
                        id: id.clone(),
                        name: name.clone(),
                        arguments: arguments.clone(),
                    })?;
                    let output = self.tools.run(&name, &arguments)?;
                    self.log.append(Event::ToolResult {
                        tool_call_id: id,
                        name,
                        output,
                    })?;
                    self.log.append(Event::TurnFinished { index: turn_index })?;
                }
            }
        }

        bail!("agent loop exceeded {MAX_TURNS_PER_JOB} turns")
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::agent::session::SessionLog;
    use crate::agent::tools::ToolRegistry;
    use crate::agent::{DryRunModel, OpenAiCompatibleModel};
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
                .any(|event| matches!(event, Event::ToolCall { id, name, .. } if id == "dry-run-tool-call-1" && name == "pwd"))
        );
        assert!(
            events
                .iter()
                .any(|event| matches!(event, Event::ToolResult { tool_call_id, name, .. } if tool_call_id == "dry-run-tool-call-1" && name == "pwd"))
        );
    }

    #[test]
    fn openai_compatible_provider_continues_after_tool_result() {
        let server = TestProvider::start(vec![
            json!({
                "choices": [{
                    "message": {
                        "content": null,
                        "tool_calls": [{
                            "id": "call_pwd",
                            "type": "function",
                            "function": {
                                "name": "pwd",
                                "arguments": "{}"
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
        let model = OpenAiCompatibleModel::new(
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
        assert_eq!(requests[0]["tools"][0]["function"]["name"], "pwd");
        assert_eq!(
            requests[1]["messages"][2]["tool_calls"][0]["id"],
            "call_pwd"
        );
        assert_eq!(requests[1]["messages"][3]["role"], "tool");
        assert_eq!(requests[1]["messages"][3]["tool_call_id"], "call_pwd");
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
