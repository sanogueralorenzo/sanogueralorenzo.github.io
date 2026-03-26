mod agents;
mod appserver;
mod auth;
mod core;
mod noninteractive;
mod sessions;

use std::env;
use std::ffi::OsString;
use std::process::ExitCode;

fn main() -> ExitCode {
    let args: Vec<OsString> = env::args_os().collect();
    let forwarded_args: Vec<OsString> = args.iter().skip(1).cloned().collect();

    match forwarded_args.first().and_then(|value| value.to_str()) {
        Some("app-server") => ExitCode::from(appserver::run_from(forwarded_args)),
        Some("auth") => ExitCode::from(auth::run_from(forwarded_args)),
        Some("agents") => ExitCode::from(agents::run_from(forwarded_args)),
        Some("sessions") => ExitCode::from(sessions::run_from(forwarded_args)),
        Some("noninteractive") => ExitCode::from(noninteractive::run_from(forwarded_args)),
        Some("help") | Some("--help") | Some("-h") | None => {
            print_help();
            ExitCode::from(0)
        }
        Some(unknown) => {
            eprintln!("Unknown command: {unknown}");
            eprintln!();
            print_help();
            ExitCode::from(2)
        }
    }
}

fn print_help() {
    println!("Usage:");
    println!("  codex-core app-server [-- app-server-options]");
    println!("  codex-core auth <command> [options]");
    println!("  codex-core agents <command> [options]");
    println!("  codex-core sessions <command> [options]");
    println!("  codex-core noninteractive run|resume|review [wrapper-options]");
    println!();
    println!("Commands:");
    println!("  app-server      Run codex app-server passthrough.");
    println!("  auth            Manage Codex auth profiles.");
    println!("  agents          Run local Codex agent workflows.");
    println!("  sessions        Manage local Codex session files.");
    println!("  noninteractive  Run standardized non-interactive Codex wrappers.");
    println!("  help            Print this help output.");
}
