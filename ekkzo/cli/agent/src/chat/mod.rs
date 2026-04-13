pub mod adapters;
pub mod contracts;

use adapters::{ChatInvocation, ChatPromptTarget};

pub fn run(provider_name: &str, args: &[String]) -> Result<(), String> {
    let invocation = parse_chat_invocation(args)?;
    adapters::run_with_provider(provider_name, &invocation)
}

fn parse_chat_invocation(args: &[String]) -> Result<ChatInvocation, String> {
    if args.is_empty() {
        return Ok(ChatInvocation::Passthrough {
            provider_args: Vec::new(),
        });
    }

    match args[0].as_str() {
        "--new" => {
            let prompt = parse_prompt_tokens(args, 1)?;
            Ok(ChatInvocation::Prompt {
                target: ChatPromptTarget::New,
                prompt,
            })
        }
        "--id" => {
            if args.len() < 3 {
                return Err(chat_usage());
            }
            let id = args[1].trim().to_string();
            if id.is_empty() {
                return Err(chat_usage());
            }
            let prompt = parse_prompt_tokens(args, 2)?;
            Ok(ChatInvocation::Prompt {
                target: ChatPromptTarget::Existing(id),
                prompt,
            })
        }
        _ => Ok(ChatInvocation::Passthrough {
            provider_args: args.to_vec(),
        }),
    }
}

fn parse_prompt_tokens(args: &[String], start_index: usize) -> Result<String, String> {
    let prompt_tokens = args[start_index..]
        .iter()
        .map(|value| value.trim())
        .filter(|value| !value.is_empty())
        .collect::<Vec<_>>();

    if prompt_tokens.is_empty() {
        return Err(chat_usage());
    }

    Ok(prompt_tokens.join(" "))
}

fn chat_usage() -> String {
    "usage:\n  agent chat\n  agent chat --new <prompt>\n  agent chat --id <conversation-id> <prompt>".to_string()
}

#[cfg(test)]
mod tests {
    use super::{parse_chat_invocation, parse_prompt_tokens};
    use crate::chat::adapters::{ChatInvocation, ChatPromptTarget};

    #[test]
    fn parse_empty_args_defaults_to_passthrough() {
        let args: Vec<String> = Vec::new();
        let invocation = parse_chat_invocation(&args).expect("parse should succeed");
        assert!(matches!(
            invocation,
            ChatInvocation::Passthrough { provider_args } if provider_args.is_empty()
        ));
    }

    #[test]
    fn parse_new_prompt_mode() {
        let args = vec!["--new".to_string(), "hello".to_string()];
        let invocation = parse_chat_invocation(&args).expect("parse should succeed");
        match invocation {
            ChatInvocation::Prompt { target, prompt } => {
                assert_eq!(prompt, "hello");
                assert!(matches!(target, ChatPromptTarget::New));
            }
            _ => panic!("expected prompt invocation"),
        }
    }

    #[test]
    fn parse_id_prompt_mode() {
        let args = vec![
            "--id".to_string(),
            "conv-1".to_string(),
            "hello".to_string(),
        ];
        let invocation = parse_chat_invocation(&args).expect("parse should succeed");
        match invocation {
            ChatInvocation::Prompt { target, prompt } => {
                assert_eq!(prompt, "hello");
                match target {
                    ChatPromptTarget::Existing(id) => assert_eq!(id, "conv-1"),
                    _ => panic!("expected existing conversation target"),
                }
            }
            _ => panic!("expected prompt invocation"),
        }
    }

    #[test]
    fn parse_unrecognized_flags_passthrough_for_provider_specific_modes() {
        let args = vec!["--listen".to_string(), "stdio://".to_string()];
        let invocation = parse_chat_invocation(&args).expect("parse should succeed");
        assert!(matches!(
            invocation,
            ChatInvocation::Passthrough { provider_args } if provider_args == args
        ));
    }

    #[test]
    fn parse_new_requires_prompt() {
        let args = vec!["--new".to_string()];
        let err = parse_chat_invocation(&args).expect_err("parse should fail");
        assert!(err.contains("agent chat --new <prompt>"));
    }

    #[test]
    fn parse_id_requires_identifier_and_prompt() {
        let args = vec!["--id".to_string(), "conv-1".to_string()];
        let err = parse_chat_invocation(&args).expect_err("parse should fail");
        assert!(err.contains("agent chat --id <conversation-id> <prompt>"));
    }

    #[test]
    fn parse_prompt_tokens_joins_and_trims() {
        let args = vec![
            "--new".to_string(),
            "  hello ".to_string(),
            "world".to_string(),
        ];
        let prompt = parse_prompt_tokens(&args, 1).expect("prompt should parse");
        assert_eq!(prompt, "hello world");
    }
}
