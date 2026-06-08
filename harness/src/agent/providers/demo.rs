use anyhow::Result;
use serde_json::json;

use crate::agent::model::{ModelClient, ModelStep};
use crate::agent::session::Event;
use crate::agent::tools::ToolSpec;

#[derive(Default)]
pub struct DemoModel;

impl ModelClient for DemoModel {
    fn next_step(&mut self, events: &[Event], _tools: &[ToolSpec]) -> Result<ModelStep> {
        if let Some(result) = latest_tool_result(events) {
            return Ok(ModelStep::Final(format!("tool result: {}", result.trim())));
        }

        let message = latest_user_message(events).unwrap_or_default();
        if message.to_ascii_lowercase().contains("pwd") {
            return Ok(ModelStep::ToolCall {
                id: "demo-tool-call-1".to_owned(),
                name: "pwd".to_owned(),
                arguments: json!({}),
            });
        }

        Ok(ModelStep::Final(format!("echo: {}", message.trim())))
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
