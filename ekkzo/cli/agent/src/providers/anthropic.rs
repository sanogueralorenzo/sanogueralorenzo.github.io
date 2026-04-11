use super::Provider;

pub struct AnthropicProvider;

impl Provider for AnthropicProvider {
    fn name(&self) -> &'static str {
        "anthropic"
    }
}
