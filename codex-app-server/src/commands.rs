use crate::cli::Cli;
use clap::{Parser, error::ErrorKind};
use std::ffi::OsString;

mod codex_exec;
mod handlers;
mod output;
mod prompts;
mod selection;
mod title_generation;
mod watcher;

pub fn run_from<I, T>(args: I) -> u8
where
    I: IntoIterator<Item = T>,
    T: Into<OsString> + Clone,
{
    let cli = match Cli::try_parse_from(args) {
        Ok(cli) => cli,
        Err(error) => {
            let kind = error.kind();
            let is_help_or_version =
                matches!(kind, ErrorKind::DisplayHelp | ErrorKind::DisplayVersion);
            let _ = error.print();
            return if is_help_or_version { 0 } else { 2 };
        }
    };

    match handlers::dispatch(cli.command) {
        Ok(()) => 0,
        Err(error) => {
            eprintln!("Error: {error:#}");
            1
        }
    }
}
