use crate::agent::session::Event;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ModelStep {
    Final(String),
    ToolCall { name: String, input: String },
}

pub trait Model {
    fn next_step(&mut self, events: &[Event]) -> ModelStep;
}

#[derive(Default)]
pub struct DemoModel;

impl Model for DemoModel {
    fn next_step(&mut self, events: &[Event]) -> ModelStep {
        if let Some(result) = latest_tool_result(events) {
            return ModelStep::Final(format!("tool result: {}", result.trim()));
        }

        let message = latest_user_message(events).unwrap_or_default();
        if message.to_ascii_lowercase().contains("pwd") {
            return ModelStep::ToolCall {
                name: "pwd".to_owned(),
                input: String::new(),
            };
        }

        ModelStep::Final(format!("echo: {}", message.trim()))
    }
}

fn latest_user_message(events: &[Event]) -> Option<&str> {
    events.iter().rev().find_map(|event| match event {
        Event::UserMessage { content, .. } => Some(content.as_str()),
        _ => None,
    })
}

fn latest_tool_result(events: &[Event]) -> Option<&str> {
    for event in events.iter().rev() {
        match event {
            Event::ToolResult { output, .. } => return Some(output.as_str()),
            Event::UserMessage { .. } => return None,
            _ => {}
        }
    }
    None
}
