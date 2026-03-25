use crate::core::process::exit_code_from_status;
use std::ffi::OsString;
use std::process::{Command, Stdio};

pub fn run_from(args: Vec<OsString>) -> u8 {
    let mut iter = args.into_iter();
    let Some(command) = iter.next() else {
        print_rpc_help();
        return 0;
    };

    if command.to_string_lossy() != "rpc" {
        eprintln!("Internal error: expected 'rpc' route.");
        return 1;
    }

    let app_server_args: Vec<OsString> = iter.collect();
    if app_server_args.first().and_then(|value| value.to_str()) == Some("app-server") {
        eprintln!("Do not include 'app-server' after 'codexhub rpc'.");
        eprintln!("Use: codexhub rpc --listen stdio://");
        return 2;
    }

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
            return 1;
        }
    };

    exit_code_from_status(&status)
}

fn print_rpc_help() {
    println!("Usage:");
    println!("  codexhub rpc [-- app-server-options]");
    println!();
    println!("Description:");
    println!("  Runs 'codex app-server' as a passthrough command.");
}
