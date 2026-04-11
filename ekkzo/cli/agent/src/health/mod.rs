pub mod adapters;
pub mod contracts;

use std::process::ExitCode;

pub fn health_command(args: Vec<String>) -> ExitCode {
    match args.as_slice() {
        [] => {
            let report = adapters::collect_health_report();
            println!(
                "{}",
                serde_json::to_string_pretty(&report).expect("health output should serialize")
            );
            ExitCode::SUCCESS
        }
        [single] if single == "check" || single == "status" => {
            let report = adapters::collect_health_report();
            println!(
                "{}",
                serde_json::to_string_pretty(&report).expect("health output should serialize")
            );
            ExitCode::SUCCESS
        }
        _ => {
            eprintln!("usage:");
            eprintln!("  agent health");
            eprintln!("  agent health check");
            ExitCode::from(1)
        }
    }
}
