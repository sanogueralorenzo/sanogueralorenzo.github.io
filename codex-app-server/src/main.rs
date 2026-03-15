mod adapters;
mod cli;
mod commands;
mod services;
mod shared;

use std::env;
use std::os::unix::process::ExitStatusExt;
use std::ffi::OsString;
use std::process::{Command, ExitCode, Stdio};

fn main() -> ExitCode {
    let args: Vec<OsString> = env::args_os().collect();
    let forwarded_args: Vec<OsString> = args.iter().skip(1).cloned().collect();

    if should_route_to_sessions(&forwarded_args) {
        let sessions_args = normalize_sessions_args(forwarded_args);
        return ExitCode::from(commands::run_from(sessions_args));
    }

    let app_server_args = normalize_app_server_args(forwarded_args);

    let status = match Command::new("codex")
        .arg("app-server")
        .args(app_server_args)
        .stdin(Stdio::inherit())
        .stdout(Stdio::inherit())
        .stderr(Stdio::inherit())
        .status()
    {
        Ok(status) => status,
        Err(error) => {
            eprintln!("failed to launch codex app-server: {error}");
            return ExitCode::from(1);
        }
    };

    if let Some(code) = status.code() {
        return ExitCode::from(u8::try_from(code).unwrap_or(1));
    }

    if let Some(signal) = status.signal() {
        let code = (128 + signal).clamp(0, 255) as u8;
        return ExitCode::from(code);
    }

    ExitCode::from(1)
}

fn should_route_to_sessions(args: &[OsString]) -> bool {
    args.first().and_then(|value| value.to_str()) == Some("sessions")
}

fn normalize_sessions_args(args: Vec<OsString>) -> Vec<OsString> {
    let mut normalized = Vec::with_capacity(args.len() + 1);
    normalized.push(OsString::from("codex-app-server sessions"));
    if args.first().and_then(|value| value.to_str()) == Some("sessions") {
        normalized.extend(args.into_iter().skip(1));
    } else {
        normalized.extend(args);
    }

    normalized
}

fn normalize_app_server_args(args: Vec<OsString>) -> Vec<OsString> {
    let mut iter = args.into_iter();
    match iter.next() {
        Some(first) if first.to_str() == Some("app-server") => iter.collect(),
        Some(first) => {
            let mut passthrough = Vec::new();
            passthrough.push(first);
            passthrough.extend(iter);
            passthrough
        }
        None => Vec::new(),
    }
}
