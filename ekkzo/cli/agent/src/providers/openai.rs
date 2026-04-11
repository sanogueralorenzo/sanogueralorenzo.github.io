use super::Provider;

pub struct OpenAiProvider;

impl Provider for OpenAiProvider {
    fn name(&self) -> &'static str {
        "openai"
    }
}
