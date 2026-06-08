use anyhow::{Result, bail};

use crate::agent::model::{ModelClient, ModelStep};
use crate::agent::session::Event;
use crate::agent::tools::ToolSpec;

pub struct OpenAiResponsesModel {
    _api_key: String,
}

impl OpenAiResponsesModel {
    pub fn new(api_key: String) -> Self {
        Self { _api_key: api_key }
    }
}

impl ModelClient for OpenAiResponsesModel {
    fn next_step(&mut self, _events: &[Event], _tools: &[ToolSpec]) -> Result<ModelStep> {
        bail!("openai-responses adapter is not implemented yet")
    }
}
