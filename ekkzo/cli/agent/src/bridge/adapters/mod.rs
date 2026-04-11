mod anthropic;
mod google;
mod openai;

use anthropic::AnthropicBridgeAdapter;
use google::GoogleBridgeAdapter;
use openai::OpenAiBridgeAdapter;

pub trait BridgeAdapter {
    fn run(&self, args: &[String]) -> Result<(), String>;
}

pub fn run_with_provider(provider_name: &str, args: &[String]) -> Result<(), String> {
    match provider_name {
        "openai" => OpenAiBridgeAdapter.run(args),
        "google" => GoogleBridgeAdapter.run(args),
        "anthropic" => AnthropicBridgeAdapter.run(args),
        _ => Err(format!("unknown provider '{provider_name}'")),
    }
}
