pub mod adapters;
pub mod contracts;

use contracts::{AskError, AskEvent, AskStatus, ProviderName};
use std::process::ExitCode;
use std::time::{SystemTime, UNIX_EPOCH};

pub fn ask_command(provider_name: &str, args: Vec<String>) -> ExitCode {
    if args.is_empty() {
        eprintln!("usage:");
        eprintln!("  agent ask <prompt>");
        return ExitCode::from(1);
    }

    let Some(provider) = ProviderName::from_provider_name(provider_name) else {
        eprintln!("unknown provider '{provider_name}'");
        return ExitCode::from(1);
    };

    let prompt = args.join(" ");
    let id = new_ask_id();

    if let Err(err) = print_event(&AskEvent::thinking(provider, id.clone())) {
        eprintln!("{err}");
        return ExitCode::from(1);
    }

    let final_event = match adapters::ask_with_provider(provider_name, &prompt) {
        Ok(result) => AskEvent::new(provider, id, result.status, result.answer, result.error),
        Err(err) => AskEvent::new(
            provider,
            id,
            AskStatus::Failed,
            None,
            Some(AskError::new(err, Some("adapter_error".to_string()))),
        ),
    };

    if let Err(err) = print_event(&final_event) {
        eprintln!("{err}");
        return ExitCode::from(1);
    }

    match final_event.status {
        AskStatus::Completed => ExitCode::SUCCESS,
        AskStatus::Interrupted => ExitCode::from(130),
        AskStatus::Failed | AskStatus::Thinking => ExitCode::from(1),
    }
}

fn print_event(event: &AskEvent) -> Result<(), String> {
    let serialized = serde_json::to_string(event)
        .map_err(|err| format!("failed to serialize ask event: {err}"))?;
    println!("{serialized}");
    Ok(())
}

fn new_ask_id() -> String {
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|value| value.as_nanos())
        .unwrap_or_default();
    format!("ask-{nanos}")
}
