mod agent;

use std::env;
use std::path::PathBuf;

use anyhow::{Context, Result, bail};

use agent::{Runtime, SessionLog, ToolRegistry, build_provider};

fn main() -> Result<()> {
    let args = env::args().skip(1).collect::<Vec<_>>();
    let command = args.first().map(String::as_str).unwrap_or("help");

    match command {
        "run" => run_command(&args[1..]),
        "help" | "--help" | "-h" => {
            print_help();
            Ok(())
        }
        other => bail!("unknown command: {other}"),
    }
}

fn run_command(args: &[String]) -> Result<()> {
    let mut session_path = PathBuf::from("harness/.state/default.jsonl");
    let mut provider = "demo".to_owned();
    let mut message_parts = Vec::new();
    let mut index = 0;

    while index < args.len() {
        match args[index].as_str() {
            "--session" => {
                let value = args.get(index + 1).context("--session requires a path")?;
                session_path = PathBuf::from(value);
                index += 2;
            }
            "--provider" => {
                provider = args
                    .get(index + 1)
                    .context("--provider requires demo or openai")?
                    .to_owned();
                index += 2;
            }
            value => {
                message_parts.push(value.to_owned());
                index += 1;
            }
        }
    }

    let message = message_parts.join(" ").trim().to_owned();
    if message.is_empty() {
        bail!("run requires a message");
    }

    let log = SessionLog::open(session_path)?;
    let tools = ToolRegistry::minimal();
    let model = build_provider(&provider)?;
    let mut runtime = Runtime::new(log, tools, model);
    let reply = runtime.run_message(message)?;

    println!("{reply}");
    Ok(())
}

fn print_help() {
    println!("harness - minimal Rust agent runtime loop");
    println!();
    println!("USAGE:");
    println!("  harness run [--provider demo|openai] [--session <path>] <message>");
    println!();
    println!("OPENAI PROVIDER ENV:");
    println!("  OPENAI_API_KEY      required");
    println!("  HARNESS_MODEL       default: gpt-4o-mini");
    println!("  HARNESS_BASE_URL    default: https://api.openai.com/v1");
}
