mod anthropic;
mod google;
mod openai;

use anthropic::AnthropicChatAdapter;
use google::GoogleChatAdapter;
use openai::OpenAiChatAdapter;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ChatPromptTarget {
    New,
    Existing(String),
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ChatInvocation {
    Passthrough {
        provider_args: Vec<String>,
    },
    Prompt {
        target: ChatPromptTarget,
        prompt: String,
    },
}

pub trait ChatAdapter {
    fn run(&self, invocation: &ChatInvocation) -> Result<(), String>;
}

pub fn run_with_provider(provider_name: &str, invocation: &ChatInvocation) -> Result<(), String> {
    match provider_name {
        "openai" => OpenAiChatAdapter.run(invocation),
        "google" => GoogleChatAdapter.run(invocation),
        "anthropic" => AnthropicChatAdapter.run(invocation),
        _ => Err(format!("unknown provider '{provider_name}'")),
    }
}
