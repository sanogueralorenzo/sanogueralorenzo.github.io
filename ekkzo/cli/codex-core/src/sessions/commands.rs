use crate::sessions::cli::Cli;
use crate::sessions::cli::{Commands, WatchCommand};
use clap::{Parser, error::ErrorKind};
use std::ffi::OsString;

mod codex_exec;
mod merge;
mod operations;
mod output;
mod prompts;
mod prune;
mod query;
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

    match dispatch(cli.command) {
        Ok(()) => 0,
        Err(error) => {
            eprintln!("Error: {error:#}");
            1
        }
    }
}

fn dispatch(command: Commands) -> anyhow::Result<()> {
    match command {
        Commands::Ls(args) => query::cmd_list(args),
        Commands::Titles(args) => query::cmd_titles(args),
        Commands::GenerateThreadTitle(args) => query::cmd_generate_thread_title(args),
        Commands::Show(args) => query::cmd_show(args),
        Commands::Message(args) => query::cmd_message(args),
        Commands::Rm(args) => operations::cmd_rm(args),
        Commands::Archive(args) => operations::cmd_archive(args),
        Commands::Restore(args) => operations::cmd_restore(args),
        Commands::Merge(args) => merge::cmd_merge(args),
        Commands::Prune(args) => prune::cmd_prune(args),
        Commands::Watch { action } => dispatch_watch(action),
    }
}

fn dispatch_watch(action: WatchCommand) -> anyhow::Result<()> {
    match action {
        WatchCommand::Prune(args) => prune::cmd_watch_prune(args),
        WatchCommand::ThreadTitles { action } => watcher::cmd_watch_thread_titles(action),
    }
}
