mod engine;
mod providers;

use engine::AgentEngine;
use providers::create_provider;
use std::env;
use std::process::ExitCode;

fn main() -> ExitCode {
    let provider_name = env::args().nth(1).unwrap_or_else(|| String::from("mock"));

    let Some(provider) = create_provider(&provider_name) else {
        eprintln!(
            "unknown provider '{provider_name}', available providers: {}",
            providers::available_provider_names().join(", ")
        );
        return ExitCode::from(1);
    };

    let engine = AgentEngine::new(provider);
    println!("{}", engine.describe());
    ExitCode::SUCCESS
}
