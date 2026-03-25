use clap::{Args, Parser, Subcommand};
use std::path::PathBuf;

#[derive(Parser, Debug)]
#[command(name = "codex-core auth")]
#[command(about = "Manage Codex auth profiles")]
pub struct Cli {
    #[arg(long, global = true, value_name = "dir")]
    pub home: Option<PathBuf>,

    #[command(subcommand)]
    pub command: Commands,
}

#[derive(Subcommand, Debug)]
pub enum Commands {
    /// Save a profile from current auth.json or explicit --path
    #[command(alias = "add")]
    Save(SaveArgs),

    /// Apply a saved profile or explicit --path to auth.json
    Use(UseArgs),

    /// List saved profiles
    List(PlainArgs),

    /// Print current profile and auth metadata
    Current(PlainArgs),

    /// Delete a saved profile
    #[command(alias = "rm", alias = "delete")]
    Remove(RemoveArgs),

    /// Manage auth sync watcher (start|stop|status|run)
    Watch {
        #[command(subcommand)]
        action: WatchCommand,
    },
}

#[derive(Args, Debug)]
pub struct SaveArgs {
    pub profile: String,

    #[arg(long, value_name = "auth.json", conflicts_with = "from_current")]
    pub path: Option<PathBuf>,

    #[arg(long)]
    pub from_current: bool,
}

#[derive(Args, Debug)]
pub struct UseArgs {
    pub profile: Option<String>,

    #[arg(long, value_name = "auth.json")]
    pub path: Option<PathBuf>,
}

#[derive(Args, Debug)]
pub struct PlainArgs {
    #[arg(long)]
    pub plain: bool,
}

#[derive(Args, Debug)]
pub struct RemoveArgs {
    pub profile: String,
}

#[derive(Subcommand, Debug)]
pub enum WatchCommand {
    /// Start auth sync watcher in background
    Start,

    /// Stop background auth sync watcher
    Stop,

    /// Print watcher status
    Status,

    /// Run watcher loop in foreground
    Run,
}
