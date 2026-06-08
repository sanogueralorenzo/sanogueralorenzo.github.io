mod dry_run;
mod openai_compatible;

use std::env;

use anyhow::{Context, Result, bail};

use crate::agent::model::ModelClient;

pub use dry_run::DryRunModel;
pub use openai_compatible::OpenAiCompatibleModel;

pub fn build_provider(name: &str) -> Result<Box<dyn ModelClient>> {
    match name {
        "dry-run" => Ok(Box::new(DryRunModel)),
        "openai" => {
            let api_key = env::var("OPENAI_API_KEY").context("OPENAI_API_KEY is required")?;
            let model = env::var("HARNESS_MODEL").unwrap_or_else(|_| "gpt-4o-mini".to_owned());
            let base_url = env::var("HARNESS_BASE_URL")
                .unwrap_or_else(|_| "https://api.openai.com/v1".to_owned());
            Ok(Box::new(OpenAiCompatibleModel::new(
                base_url, api_key, model,
            )))
        }
        other => bail!("unknown provider: {other}"),
    }
}
