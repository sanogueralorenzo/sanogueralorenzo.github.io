use anyhow::Result;
use serde_json::Value;

use crate::agent::session::Event;
use crate::agent::tools::ToolSpec;

#[derive(Debug, Clone, PartialEq)]
pub enum ModelStep {
    Final(String),
    ToolCall {
        id: String,
        name: String,
        arguments: Value,
    },
}

pub trait ModelClient {
    fn next_step(&mut self, events: &[Event], tools: &[ToolSpec]) -> Result<ModelStep>;
}

impl<T: ModelClient + ?Sized> ModelClient for Box<T> {
    fn next_step(&mut self, events: &[Event], tools: &[ToolSpec]) -> Result<ModelStep> {
        (**self).next_step(events, tools)
    }
}
