mod bridge;
mod config;
mod engine;
mod providers;

use engine::AgentEngine;
use providers::{DEFAULT_PROVIDER, available_provider_names, create_provider};
use std::env;
use std::process::ExitCode;

fn main() -> ExitCode {
    let mut args = env::args().skip(1);
    match args.next().as_deref() {
        Some("providers") => providers_command(args.collect()),
        Some("bridge") => bridge_command(args.collect()),
        Some("run") => run_command(),
        Some(cmd) => {
            eprintln!("unknown command '{cmd}', available commands: providers, bridge, run");
            ExitCode::from(1)
        }
        None => run_command(),
    }
}

fn bridge_command(args: Vec<String>) -> ExitCode {
    let provider_name = configured_provider_name();
    match bridge::run(&provider_name, &args) {
        Ok(()) => ExitCode::SUCCESS,
        Err(err) => {
            eprintln!("{err}");
            ExitCode::from(1)
        }
    }
}

fn run_command() -> ExitCode {
    let provider_name = configured_provider_name();
    let Some(provider) = create_provider(&provider_name) else {
        eprintln!(
            "configured provider '{}' is not supported, available providers: {}",
            provider_name,
            available_provider_names().join(", ")
        );
        return ExitCode::from(1);
    };

    let engine = AgentEngine::new(provider);
    println!("{}", engine.describe());
    ExitCode::SUCCESS
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

fn configured_provider_name() -> String {
    match config::load_provider_name() {
        Ok(Some(value)) if create_provider(&value).is_some() => value,
        _ => DEFAULT_PROVIDER.to_string(),
    }
}
