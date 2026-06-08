mod agent;

use std::env;
use std::path::PathBuf;

use anyhow::{Context, Result, bail};

use agent::{DemoModel, OpenAiCompatibleModel, Runtime, SessionLog, ToolRegistry};

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
    let reply = match provider.as_str() {
        "demo" => {
            let mut runtime = Runtime::new(log, tools, DemoModel);
            runtime.run_message(message)?
        }
        "openai" => {
            let api_key = env::var("OPENAI_API_KEY").context("OPENAI_API_KEY is required")?;
            let model = env::var("HARNESS_MODEL").unwrap_or_else(|_| "gpt-4o-mini".to_owned());
            let base_url = env::var("HARNESS_BASE_URL")
                .unwrap_or_else(|_| "https://api.openai.com/v1".to_owned());
            let model = OpenAiCompatibleModel::new(base_url, api_key, model);
            let mut runtime = Runtime::new(log, tools, model);
            runtime.run_message(message)?
        }
        other => bail!("unknown provider: {other}"),
    };

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
