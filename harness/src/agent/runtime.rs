use std::collections::VecDeque;

use anyhow::{Result, bail};

use crate::agent::model::{Model, ModelStep};
use crate::agent::session::{Event, SessionLog};
use crate::agent::tools::ToolRegistry;

const MAX_MODEL_STEPS: usize = 16;

pub struct Runtime<M: Model> {
    log: SessionLog,
    tools: ToolRegistry,
    model: M,
    queue: VecDeque<String>,
}

impl<M: Model> Runtime<M> {
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

        for _ in 0..MAX_MODEL_STEPS {
            let events = self.log.events().to_vec();
            match self.model.next_step(&events) {
                ModelStep::Final(content) => {
                    self.log.append(Event::AssistantMessage {
                        content: content.clone(),
                    })?;
                    self.log.append(Event::JobFinished)?;
                    return Ok(content);
                }
                ModelStep::ToolCall { name, input } => {
                    self.log.append(Event::ToolCall {
                        name: name.clone(),
                        input: input.clone(),
                    })?;
                    let output = self.tools.run(&name, &input)?;
                    self.log.append(Event::ToolResult { name, output })?;
                }
            }
        }

        bail!("agent loop exceeded {MAX_MODEL_STEPS} model steps")
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
}
