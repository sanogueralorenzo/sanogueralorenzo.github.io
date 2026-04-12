mod ask;
mod chat;
mod config;
mod conversations;
mod health;
mod providers;

use providers::{DEFAULT_PROVIDER, available_provider_names, create_provider};
use std::env;
use std::process::ExitCode;

fn main() -> ExitCode {
    let mut args = env::args().skip(1);
    match args.next().as_deref() {
        Some("providers") => providers_command(args.collect()),
        Some("ask") => ask_command(args.collect()),
        Some("chat") => chat_command(args.collect()),
        Some("health") => health::health_command(args.collect()),
        Some("conversations") => conversations::conversations_command(args.collect()),
        Some(cmd) => {
            eprintln!(
                "unknown command '{cmd}', available commands: providers, ask, chat, health, conversations"
            );
            ExitCode::from(1)
        }
        None => usage(),
    }
}

fn ask_command(args: Vec<String>) -> ExitCode {
    let provider_name = configured_provider_name();
    ask::ask_command(&provider_name, args)
}

fn chat_command(args: Vec<String>) -> ExitCode {
    let provider_name = configured_provider_name();
    match chat::run(&provider_name, &args) {
        Ok(()) => ExitCode::SUCCESS,
        Err(err) => {
            eprintln!("{err}");
            ExitCode::from(1)
        }
    }
}

fn providers_command(args: Vec<String>) -> ExitCode {
    match args.as_slice() {
        [] => {
            let selected_provider = configured_provider_name();
            println!("current: {selected_provider}");
            println!("available:");
            for provider_name in available_provider_names() {
                let marker = if provider_name == selected_provider {
                    "*"
                } else {
                    "-"
                };
                println!("{marker} {provider_name}");
            }
            ExitCode::SUCCESS
        }
        [single] if single == "list" => {
            let selected_provider = configured_provider_name();
            println!("current: {selected_provider}");
            println!("available:");
            for provider_name in available_provider_names() {
                let marker = if provider_name == selected_provider {
                    "*"
                } else {
                    "-"
                };
                println!("{marker} {provider_name}");
            }
            ExitCode::SUCCESS
        }
        [single] if single == "current" || single == "get" => {
            println!("{}", configured_provider_name());
            ExitCode::SUCCESS
        }
        [action, provider_name] if action == "set" || action == "use" => {
            if create_provider(provider_name).is_none() {
                eprintln!(
                    "unknown provider '{provider_name}', available providers: {}",
                    available_provider_names().join(", ")
                );
                return ExitCode::from(1);
            }

            if let Err(err) = config::save_provider_name(provider_name) {
                eprintln!("failed to persist provider '{provider_name}': {err}");
                return ExitCode::from(1);
            }

            println!("provider set to '{provider_name}'");
            ExitCode::SUCCESS
        }
        _ => {
            eprintln!("usage:");
            eprintln!("  agent providers");
            eprintln!("  agent providers list");
            eprintln!("  agent providers current");
            eprintln!("  agent providers set <provider>");
            ExitCode::from(1)
        }
    }
}

fn usage() -> ExitCode {
    eprintln!("usage:");
    eprintln!("  agent providers");
    eprintln!("  agent ask [--json] <prompt>");
    eprintln!("  agent chat");
    eprintln!("  agent health");
    eprintln!("  agent conversations <list|resume|delete|deleteAll>");
    ExitCode::from(1)
}

fn configured_provider_name() -> String {
    match config::load_provider_name() {
        Ok(Some(value)) if create_provider(&value).is_some() => value,
        _ => DEFAULT_PROVIDER.to_string(),
    }
}
