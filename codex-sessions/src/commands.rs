use crate::cli::Cli;
use anyhow::Result;
use clap::Parser;

mod codex_exec;
mod handlers;
mod output;
mod prompts;
mod selection;
mod title_generation;
mod watcher;

pub fn run() -> Result<()> {
    let cli = Cli::parse();
    handlers::dispatch(cli.command)
}
