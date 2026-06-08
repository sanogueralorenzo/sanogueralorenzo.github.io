mod dry_run;
use std::env;

use anyhow::{Context, Result, bail};

use crate::agent::apis::{OpenAiCompletionsModel, OpenAiResponsesModel};
use crate::agent::model::ModelClient;

pub use dry_run::DryRunModel;

pub fn build_provider(name: &str) -> Result<Box<dyn ModelClient>> {
    match name {
        "dry-run" => Ok(Box::new(DryRunModel)),
        "openai" => build_openai_provider(),
        other => bail!("unknown provider: {other}"),
    }
}

fn build_openai_provider() -> Result<Box<dyn ModelClient>> {
    let api = env::var("HARNESS_OPENAI_API").unwrap_or_else(|_| "openai-completions".to_owned());
    match api.as_str() {
        "openai-completions" => {
            let api_key = env::var("OPENAI_API_KEY").context("OPENAI_API_KEY is required")?;
            let model = env::var("HARNESS_MODEL").unwrap_or_else(|_| "gpt-4o-mini".to_owned());
            let base_url = env::var("HARNESS_BASE_URL")
                .unwrap_or_else(|_| "https://api.openai.com/v1".to_owned());
            Ok(Box::new(OpenAiCompletionsModel::new(
                base_url, api_key, model,
            )))
        }
        "openai-responses" => {
            let api_key = env::var("OPENAI_API_KEY").context("OPENAI_API_KEY is required")?;
            Ok(Box::new(OpenAiResponsesModel::new(api_key)))
        }
        other => bail!("unknown OpenAI API adapter: {other}"),
    }
}
