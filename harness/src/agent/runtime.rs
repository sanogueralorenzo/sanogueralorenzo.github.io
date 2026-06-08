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
    use crate::agent::model::DemoModel;
    use crate::agent::session::SessionLog;
    use crate::agent::tools::ToolRegistry;

    #[test]
    fn finishes_simple_message() {
        let log = SessionLog::memory();
        let mut runtime = Runtime::new(log, ToolRegistry::minimal(), DemoModel);

        let reply = runtime.run_message("hello".to_owned()).unwrap();

        assert_eq!(reply, "echo: hello");
    }

    #[test]
    fn runs_tool_before_final_reply() {
        let log = SessionLog::memory();
        let mut runtime = Runtime::new(log, ToolRegistry::minimal(), DemoModel);

        let reply = runtime.run_message("what is pwd".to_owned()).unwrap();

        assert!(reply.starts_with("tool result: "));
        assert!(reply.contains("/"));
    }

    #[test]
    fn does_not_reuse_previous_tool_result() {
        let log = SessionLog::memory();
        let mut runtime = Runtime::new(log, ToolRegistry::minimal(), DemoModel);

        runtime.run_message("what is pwd".to_owned()).unwrap();
        let reply = runtime.run_message("hello".to_owned()).unwrap();

        assert_eq!(reply, "echo: hello");
    }

    #[test]
    fn persists_turn_boundaries_and_tool_call_ids() {
        let log = SessionLog::memory();
        let mut runtime = Runtime::new(log, ToolRegistry::minimal(), DemoModel);

        runtime.run_message("what is pwd".to_owned()).unwrap();

        let events = runtime.log.events();
        assert!(matches!(events[2], Event::TurnStarted { index: 1 }));
        assert!(
            events
                .iter()
                .any(|event| matches!(event, Event::ToolCall { id, name, .. } if id == "demo-tool-call-1" && name == "pwd"))
        );
        assert!(
            events
                .iter()
                .any(|event| matches!(event, Event::ToolResult { tool_call_id, name, .. } if tool_call_id == "demo-tool-call-1" && name == "pwd"))
        );
    }
}
