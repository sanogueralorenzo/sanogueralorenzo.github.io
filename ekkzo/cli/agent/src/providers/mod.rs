mod anthropic;
mod google;
mod openai;

pub trait Provider: Send + Sync {
    fn name(&self) -> &'static str;
}

pub const DEFAULT_PROVIDER: &str = "openai";
const AVAILABLE_PROVIDERS: [&str; 3] = ["openai", "anthropic", "google"];

pub fn available_provider_names() -> Vec<&'static str> {
    AVAILABLE_PROVIDERS.to_vec()
}

pub fn create_provider(name: &str) -> Option<Box<dyn Provider>> {
    match name {
        "openai" => Some(Box::new(openai::OpenAiProvider)),
        "anthropic" => Some(Box::new(anthropic::AnthropicProvider)),
        "google" => Some(Box::new(google::GoogleProvider)),
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use super::{AVAILABLE_PROVIDERS, create_provider};

    #[test]
    fn all_supported_providers_can_be_created() {
        for provider_name in AVAILABLE_PROVIDERS {
            assert!(
                create_provider(provider_name).is_some(),
                "provider should exist: {provider_name}"
            );
        }
    }

    #[test]
    fn unknown_provider_is_rejected() {
        assert!(create_provider("unknown").is_none());
    }
}
