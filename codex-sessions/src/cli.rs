use clap::{ArgAction, Args, Parser, Subcommand, ValueEnum};
use std::path::PathBuf;

#[derive(Parser, Debug)]
#[command(name = "codex-sessions")]
#[command(about = "Manage local Codex session files")]
pub struct Cli {
    #[command(subcommand)]
    pub command: Commands,
}

#[derive(Subcommand, Debug)]
pub enum Commands {
    /// List sessions with optional filters/pagination.
    List(ListArgs),
    /// List resolved conversation titles by session id.
    Titles(TitlesArgs),
    /// Generate and persist a session title from first user input.
    GenerateThreadTitle(GenerateThreadTitleArgs),
    /// Show one session by id or unique id prefix.
    Show(ShowArgs),
    /// Print latest assistant message for a session.
    Message(MessageArgs),
    /// Archive by default, or hard delete sessions with --hard.
    Delete(DeleteArgs),
    /// Move one or more sessions to archived storage.
    Archive(ArchiveArgs),
    /// Move one or more sessions from archived storage to active storage.
    Unarchive(UnarchiveArgs),
    /// Summarize one session into another and delete the merged session.
    Merge(MergeArgs),
    /// Prune old active sessions once.
    Prune(PruneArgs),
    /// Run prune repeatedly on an interval.
    Watch(WatchArgs),
    /// Manage title watcher (start|stop|status|run).
    WatchTitle {
        #[command(subcommand)]
        action: WatchTitleCommand,
    },
}

#[derive(Subcommand, Debug)]
pub enum WatchTitleCommand {
    /// Start title watcher in background.
    Start(WatchTitleCommonArgs),
    /// Stop background title watcher.
    Stop(WatchTitleCommonArgs),
    /// Print title watcher status.
    Status(WatchTitleCommonArgs),
    /// Run title watcher loop in foreground.
    Run(WatchTitleRunArgs),
}

#[derive(Copy, Clone, Debug, ValueEnum)]
#[value(rename_all = "snake_case")]
pub enum SortBy {
    CreatedAt,
    UpdatedAt,
}

#[derive(Clone, Debug, ValueEnum)]
#[value(rename_all = "kebab-case")]
pub enum SourceKind {
    Cli,
    Vscode,
    Exec,
    AppServer,
    SubAgent,
    SubAgentReview,
    SubAgentCompact,
    SubAgentThreadSpawn,
    SubAgentOther,
    Unknown,
}

impl SourceKind {
    pub fn as_stored(&self) -> &'static str {
        match self {
            Self::Cli => "cli",
            Self::Vscode => "vscode",
            Self::Exec => "exec",
            Self::AppServer => "appServer",
            Self::SubAgent => "subAgent",
            Self::SubAgentReview => "subAgentReview",
            Self::SubAgentCompact => "subAgentCompact",
            Self::SubAgentThreadSpawn => "subAgentThreadSpawn",
            Self::SubAgentOther => "subAgentOther",
            Self::Unknown => "unknown",
        }
    }
}

#[derive(Args, Debug)]
pub struct ListArgs {
    #[arg(long)]
    pub home: Option<PathBuf>,

    #[arg(long)]
    pub limit: Option<usize>,

    #[arg(long)]
    pub cursor: Option<String>,

    #[arg(long = "older-than-days")]
    pub older_than_days: Option<i64>,

    #[arg(long)]
    pub archived: bool,

    #[arg(long)]
    pub all: bool,

    #[arg(long)]
    pub cwd: Option<PathBuf>,

    #[arg(long = "source-kind", value_enum, value_delimiter = ',', action = ArgAction::Append)]
    pub source_kinds: Vec<SourceKind>,

    #[arg(long = "sort-by", value_enum, default_value = "updated_at")]
    pub sort_by: SortBy,

    #[arg(long)]
    pub folders: bool,

    #[arg(long)]
    pub search: Option<String>,

    #[arg(long)]
    pub json: bool,

    #[arg(long)]
    pub plain: bool,
}

#[derive(Args, Debug)]
pub struct TitlesArgs {
    #[arg(long)]
    pub home: Option<PathBuf>,

    #[arg(long)]
    pub json: bool,

    #[arg(long)]
    pub plain: bool,
}

#[derive(Args, Debug)]
pub struct GenerateThreadTitleArgs {
    /// Full thread id or unique thread id prefix
    pub id: String,

    #[arg(long)]
    pub home: Option<PathBuf>,

    #[arg(long)]
    pub json: bool,

    #[arg(long)]
    pub plain: bool,
}

#[derive(Args, Debug)]
pub struct ShowArgs {
    /// Full thread id or unique thread id prefix
    pub id: String,

    #[arg(long)]
    pub home: Option<PathBuf>,

    #[arg(long)]
    pub json: bool,

    #[arg(long)]
    pub plain: bool,
}

#[derive(Args, Debug)]
pub struct MessageArgs {
    /// Full thread id or unique thread id prefix
    pub id: String,

    #[arg(long)]
    pub home: Option<PathBuf>,

    #[arg(long)]
    pub json: bool,

    #[arg(long)]
    pub plain: bool,
}

#[derive(Args, Debug)]
pub struct DeleteArgs {
    /// One or more full thread ids or unique thread id prefixes
    #[arg(num_args = 1..)]
    pub ids: Vec<String>,

    /// Select all active sessions (useful with selector flags)
    #[arg(long)]
    pub all: bool,

    /// Select sessions older than N days by last update time
    #[arg(long = "older-than-days")]
    pub older_than_days: Option<i64>,

    /// Select sessions by folder label (same value shown in list --folders)
    #[arg(long)]
    pub folder: Option<String>,

    /// Select sessions by title/id/cwd substring (case-insensitive)
    #[arg(long)]
    pub search: Option<String>,

    #[arg(long)]
    pub home: Option<PathBuf>,

    #[arg(long)]
    pub hard: bool,

    #[arg(long)]
    pub dry_run: bool,

    /// Required for selector-based destructive runs (non dry-run) without explicit IDs
    #[arg(long)]
    pub yes: bool,

    #[arg(long)]
    pub json: bool,

    #[arg(long)]
    pub plain: bool,
}

#[derive(Args, Debug)]
pub struct ArchiveArgs {
    /// One or more full thread ids or unique thread id prefixes
    #[arg(required = true, num_args = 1..)]
    pub ids: Vec<String>,

    #[arg(long)]
    pub home: Option<PathBuf>,

    #[arg(long)]
    pub json: bool,

    #[arg(long)]
    pub plain: bool,
}

#[derive(Args, Debug)]
pub struct UnarchiveArgs {
    /// One or more full thread ids or unique thread id prefixes
    #[arg(required = true, num_args = 1..)]
    pub ids: Vec<String>,

    #[arg(long)]
    pub home: Option<PathBuf>,

    #[arg(long)]
    pub json: bool,

    #[arg(long)]
    pub plain: bool,
}

#[derive(Args, Debug)]
pub struct MergeArgs {
    #[arg(long)]
    pub target: String,

    #[arg(long)]
    pub merge: String,

    #[arg(long)]
    pub home: Option<PathBuf>,

    #[arg(long)]
    pub json: bool,

    #[arg(long)]
    pub plain: bool,
}

#[derive(Args, Debug)]
pub struct PruneArgs {
    #[arg(long = "older-than-days")]
    pub older_than_days: i64,

    #[arg(long)]
    pub home: Option<PathBuf>,

    #[arg(long)]
    pub dry_run: bool,

    #[arg(long)]
    pub hard: bool,

    #[arg(long)]
    pub json: bool,

    #[arg(long)]
    pub plain: bool,
}

#[derive(Args, Debug)]
pub struct WatchArgs {
    #[arg(long = "older-than-days")]
    pub older_than_days: i64,

    #[arg(long = "interval-minutes", default_value_t = 60)]
    pub interval_minutes: u64,

    #[arg(long)]
    pub home: Option<PathBuf>,

    #[arg(long)]
    pub dry_run: bool,

    #[arg(long)]
    pub hard: bool,

    #[arg(long)]
    pub once: bool,

    #[arg(long)]
    pub json: bool,

    #[arg(long)]
    pub plain: bool,
}

#[derive(Args, Debug)]
pub struct WatchTitleCommonArgs {
    #[arg(long)]
    pub home: Option<PathBuf>,
}

#[derive(Args, Debug)]
pub struct WatchTitleRunArgs {
    #[arg(long)]
    pub home: Option<PathBuf>,

    #[arg(long)]
    pub once: bool,
}
