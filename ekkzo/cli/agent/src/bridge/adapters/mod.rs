mod google;
mod openai;

use google::GoogleBridgeAdapter;
use openai::OpenAiBridgeAdapter;

pub trait BridgeAdapter {
    fn run(&self, args: &[String]) -> Result<(), String>;
}

pub fn run_with_provider(provider_name: &str, args: &[String]) -> Result<(), String> {
    match provider_name {
        "openai" => OpenAiBridgeAdapter.run(args),
        "google" => GoogleBridgeAdapter.run(args),
        "anthropic" => Err(format!(
            "provider '{provider_name}' does not have a bridge adapter yet"
        )),
        _ => Err(format!("unknown provider '{provider_name}'")),
    }
}
