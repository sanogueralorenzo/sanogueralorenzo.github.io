use anyhow::Result;
use serde_json::Value;

use crate::agent::session::Event;
use crate::agent::tools::ToolSpec;

#[derive(Debug, Clone, PartialEq)]
pub struct ToolCallRequest {
    pub id: String,
    pub name: String,
    pub arguments: Value,
}

#[derive(Debug, Clone, PartialEq)]
pub enum ModelStep {
    Final(String),
    ToolCall {
        id: String,
        name: String,
        arguments: Value,
    },
    ToolCalls(Vec<ToolCallRequest>),
}

#[derive(Debug, Clone, PartialEq)]
#[allow(dead_code)]
pub enum ModelUpdate {
    MessageDelta {
        role: &'static str,
        delta: String,
    },
    ToolCallDelta {
        id: String,
        name: String,
        arguments_delta: String,
    },
}

pub trait ModelClient {
    fn next_step(&mut self, events: &[Event], tools: &[ToolSpec]) -> Result<ModelStep>;

    fn next_step_with_updates(
        &mut self,
        events: &[Event],
        tools: &[ToolSpec],
        updates: &mut dyn FnMut(ModelUpdate),
    ) -> Result<ModelStep> {
        let _ = updates;
        self.next_step(events, tools)
    }
}

impl<T: ModelClient + ?Sized> ModelClient for Box<T> {
    fn next_step(&mut self, events: &[Event], tools: &[ToolSpec]) -> Result<ModelStep> {
        (**self).next_step(events, tools)
    }

    fn next_step_with_updates(
        &mut self,
        events: &[Event],
        tools: &[ToolSpec],
        updates: &mut dyn FnMut(ModelUpdate),
    ) -> Result<ModelStep> {
        (**self).next_step_with_updates(events, tools, updates)
    }
}
