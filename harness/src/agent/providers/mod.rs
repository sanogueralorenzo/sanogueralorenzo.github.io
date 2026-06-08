mod dry_run;
use std::env;

use anyhow::{Context, Result, bail};

use crate::agent::apis::{CacheRetention, OpenAiCompletionsModel, OpenAiResponsesModel};
use crate::agent::model::ModelClient;

pub use dry_run::DryRunModel;

const OPENAI_PROVIDER: &str = "openai";
const DEFAULT_OPENAI_MODEL: &str = "gpt-4o-mini";
const DEFAULT_OPENAI_BASE_URL: &str = "https://api.openai.com/v1";

pub fn build_provider(name: &str, session_id: Option<String>) -> Result<Box<dyn ModelClient>> {
    match name {
        "dry-run" => Ok(Box::new(DryRunModel)),
        OPENAI_PROVIDER => OpenAiProviderConfig::from_env()?.build_client(session_id),
        other => bail!("unknown provider: {other}"),
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum OpenAiApi {
    Completions,
    Responses,
}

impl OpenAiApi {
    fn from_env() -> Result<Self> {
        Self::parse(
            &env::var("HARNESS_OPENAI_API")
                .unwrap_or_else(|_| Self::Completions.as_str().to_owned()),
        )
    }

    fn parse(value: &str) -> Result<Self> {
        match value {
            "openai-completions" => Ok(Self::Completions),
            "openai-responses" => Ok(Self::Responses),
            other => bail!("unknown OpenAI API adapter: {other}"),
        }
    }

    fn as_str(self) -> &'static str {
        match self {
            Self::Completions => "openai-completions",
            Self::Responses => "openai-responses",
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum ModelInput {
    Text,
    Image,
}

impl ModelInput {
    fn parse(value: &str) -> Result<Self> {
        match value.trim() {
            "text" => Ok(Self::Text),
            "image" => Ok(Self::Image),
            other => bail!("HARNESS_MODEL_INPUTS values must be text or image; got {other}"),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct OpenAiModelConfig {
    id: String,
    api: OpenAiApi,
    provider: &'static str,
    base_url: String,
    reasoning: bool,
    input: Vec<ModelInput>,
}

impl OpenAiModelConfig {
    fn from_env(api: OpenAiApi) -> Result<Self> {
        let id = env::var("HARNESS_MODEL").unwrap_or_else(|_| DEFAULT_OPENAI_MODEL.to_owned());
        let base_url =
            env::var("HARNESS_BASE_URL").unwrap_or_else(|_| DEFAULT_OPENAI_BASE_URL.to_owned());
        let input = match env::var("HARNESS_MODEL_INPUTS") {
            Ok(value) => Some(parse_model_inputs(&value)?),
            Err(_) => None,
        };
        let reasoning = match env::var("HARNESS_MODEL_REASONING") {
            Ok(value) => parse_bool_env("HARNESS_MODEL_REASONING", &value)?,
            Err(_) => infer_reasoning_model(&id),
        };
        Self::resolve(id, api, base_url, input, reasoning)
    }

    fn resolve(
        id: String,
        api: OpenAiApi,
        base_url: String,
        input: Option<Vec<ModelInput>>,
        reasoning: bool,
    ) -> Result<Self> {
        let input = input.unwrap_or_else(|| infer_model_inputs(&id));
        if !input.contains(&ModelInput::Text) {
            bail!("HARNESS_MODEL_INPUTS must include text for the coding harness");
        }

        Ok(Self {
            id,
            api,
            provider: OPENAI_PROVIDER,
            base_url,
            reasoning,
            input,
        })
    }

    #[cfg(test)]
    fn supports_image_input(&self) -> bool {
        self.input.contains(&ModelInput::Image)
    }
}

struct OpenAiProviderConfig {
    model: OpenAiModelConfig,
    api_key: String,
    cache_retention: CacheRetention,
}

impl OpenAiProviderConfig {
    fn from_env() -> Result<Self> {
        let api = OpenAiApi::from_env()?;
        Ok(Self {
            model: OpenAiModelConfig::from_env(api)?,
            api_key: env::var("OPENAI_API_KEY").context("OPENAI_API_KEY is required")?,
            cache_retention: CacheRetention::from_env()?,
        })
    }

    fn build_client(self, session_id: Option<String>) -> Result<Box<dyn ModelClient>> {
        if self.model.provider != OPENAI_PROVIDER {
            bail!("unsupported OpenAI model provider: {}", self.model.provider);
        }

        match self.model.api {
            OpenAiApi::Completions => Ok(Box::new(OpenAiCompletionsModel::with_cache(
                self.model.base_url,
                self.api_key,
                self.model.id,
                session_id,
                self.cache_retention,
            ))),
            OpenAiApi::Responses => Ok(Box::new(OpenAiResponsesModel::with_cache(
                self.model.base_url,
                self.api_key,
                self.model.id,
                session_id,
                self.cache_retention,
            ))),
        }
    }
}

fn parse_model_inputs(value: &str) -> Result<Vec<ModelInput>> {
    let mut input = Vec::new();
    for part in value.split(',') {
        let parsed = ModelInput::parse(part)?;
        if !input.contains(&parsed) {
            input.push(parsed);
        }
    }
    if input.is_empty() {
        bail!("HARNESS_MODEL_INPUTS must include text and may include image");
    }
    Ok(input)
}

fn infer_model_inputs(model_id: &str) -> Vec<ModelInput> {
    let id = model_id.to_ascii_lowercase();
    if id.starts_with("gpt-4.1")
        || id.starts_with("gpt-4o")
        || id.starts_with("gpt-5")
        || id.contains("vision")
    {
        vec![ModelInput::Text, ModelInput::Image]
    } else {
        vec![ModelInput::Text]
    }
}

fn infer_reasoning_model(model_id: &str) -> bool {
    let id = model_id.to_ascii_lowercase();
    (id.starts_with("gpt-5") && id != "gpt-5-chat-latest")
        || id.starts_with("o1")
        || id.starts_with("o3")
        || id.starts_with("o4")
}

fn parse_bool_env(name: &str, value: &str) -> Result<bool> {
    match value {
        "1" | "true" | "yes" => Ok(true),
        "0" | "false" | "no" => Ok(false),
        other => bail!("{name} must be true or false; got {other}"),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_openai_api_adapter_names() {
        assert_eq!(
            OpenAiApi::parse("openai-completions").unwrap(),
            OpenAiApi::Completions
        );
        assert_eq!(
            OpenAiApi::parse("openai-responses").unwrap(),
            OpenAiApi::Responses
        );
        assert!(OpenAiApi::parse("anthropic-messages").is_err());
    }

    #[test]
    fn resolves_pi_shaped_openai_model_metadata() {
        let model = OpenAiModelConfig::resolve(
            "gpt-5".to_owned(),
            OpenAiApi::Responses,
            DEFAULT_OPENAI_BASE_URL.to_owned(),
            None,
            infer_reasoning_model("gpt-5"),
        )
        .unwrap();

        assert_eq!(model.provider, OPENAI_PROVIDER);
        assert_eq!(model.api, OpenAiApi::Responses);
        assert_eq!(model.base_url, DEFAULT_OPENAI_BASE_URL);
        assert!(model.reasoning);
        assert!(model.supports_image_input());
    }

    #[test]
    fn keeps_chat_latest_as_non_reasoning_like_pi() {
        let model = OpenAiModelConfig::resolve(
            "gpt-5-chat-latest".to_owned(),
            OpenAiApi::Responses,
            DEFAULT_OPENAI_BASE_URL.to_owned(),
            None,
            infer_reasoning_model("gpt-5-chat-latest"),
        )
        .unwrap();

        assert!(!model.reasoning);
        assert!(model.supports_image_input());
    }

    #[test]
    fn parses_deduplicated_model_inputs() {
        assert_eq!(
            parse_model_inputs("text,image,image").unwrap(),
            vec![ModelInput::Text, ModelInput::Image]
        );
        assert!(parse_model_inputs("").is_err());
        assert!(parse_model_inputs("audio").is_err());
    }

    #[test]
    fn parses_bool_overrides() {
        assert!(parse_bool_env("TEST", "true").unwrap());
        assert!(parse_bool_env("TEST", "1").unwrap());
        assert!(!parse_bool_env("TEST", "false").unwrap());
        assert!(!parse_bool_env("TEST", "0").unwrap());
        assert!(parse_bool_env("TEST", "maybe").is_err());
    }
}
