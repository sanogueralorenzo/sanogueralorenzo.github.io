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
        "compact" => compact_command(&args[1..]),
        "help" | "--help" | "-h" => {
            print_help();
            Ok(())
        }
        other => bail!("unknown command: {other}"),
    }
}

fn run_command(args: &[String]) -> Result<()> {
    let mut session_path = PathBuf::from("harness/.state/default.jsonl");
    let mut provider = "dry-run".to_owned();
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
                    .context("--provider requires dry-run or openai")?
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
    let session_id = log.session_id().map(str::to_owned);
    let tools =
        ToolRegistry::coding(env::current_dir().context("resolve current working directory")?);
    let model = build_provider(&provider, session_id)?;
    let mut runtime = Runtime::new(log, tools, model);
    let reply = runtime.run_message(message)?;

    println!("{reply}");
    Ok(())
}

fn compact_command(args: &[String]) -> Result<()> {
    let mut session_path = PathBuf::from("harness/.state/default.jsonl");
    let mut instruction_parts = Vec::new();
    let mut index = 0;

    while index < args.len() {
        match args[index].as_str() {
            "--session" => {
                let value = args.get(index + 1).context("--session requires a path")?;
                session_path = PathBuf::from(value);
                index += 2;
            }
            value => {
                instruction_parts.push(value.to_owned());
                index += 1;
            }
        }
    }

    let log = SessionLog::open(session_path)?;
    let session_id = log.session_id().map(str::to_owned);
    let tools =
        ToolRegistry::coding(env::current_dir().context("resolve current working directory")?);
    let model = build_provider("dry-run", session_id)?;
    let mut runtime = Runtime::new(log, tools, model);
    let focus = instruction_parts.join(" ").trim().to_owned();
    let custom_instructions = if focus.is_empty() { None } else { Some(focus) };
    let outcome = runtime.compact_manual(custom_instructions)?;

    println!("{}", outcome.summary);
    Ok(())
}

fn print_help() {
    println!("harness - minimal Rust agent runtime loop");
    println!();
    println!("USAGE:");
    println!("  harness run [--provider dry-run|openai] [--session <path>] <message>");
    println!("  harness compact [--session <path>] [focus text]");
    println!();
    println!("OPENAI PROVIDER ENV:");
    println!("  OPENAI_API_KEY      required");
    println!("  HARNESS_MODEL       default: gpt-4o-mini");
    println!("  HARNESS_OPENAI_API  default: openai-completions");
    println!("  HARNESS_BASE_URL    default: https://api.openai.com/v1");
    println!("  HARNESS_CACHE_RETENTION default: short; values: short|long|none");
}
