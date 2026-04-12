mod anthropic;
mod google;
mod openai;

use anthropic::AnthropicChatAdapter;
use google::GoogleChatAdapter;
use openai::OpenAiChatAdapter;

pub trait ChatAdapter {
    fn run(&self, args: &[String]) -> Result<(), String>;
}

pub fn run_with_provider(provider_name: &str, args: &[String]) -> Result<(), String> {
    match provider_name {
        "openai" => OpenAiChatAdapter.run(args),
        "google" => GoogleChatAdapter.run(args),
        "anthropic" => AnthropicChatAdapter.run(args),
        _ => Err(format!("unknown provider '{provider_name}'")),
    }
}
