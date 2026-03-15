use clap::{ArgAction, Args, Parser, Subcommand, ValueEnum};
use std::path::PathBuf;

#[derive(Parser, Debug)]
#[command(name = "codex-noninteractive")]
#[command(about = "Script and CI wrapper for codex exec non-interactive runs")]
pub struct Cli {
    #[command(subcommand)]
    pub command: Command,
}

#[derive(Subcommand, Debug)]
pub enum Command {
    /// Start a new non-interactive Codex exec turn.
    Run(RunArgs),
    /// Resume an existing Codex exec thread non-interactively.
    Resume(ResumeArgs),
    /// Run codex exec review.
    Review(ReviewArgs),
}

#[derive(Copy, Clone, Debug, Eq, PartialEq, ValueEnum)]
#[value(rename_all = "kebab-case")]
pub enum SandboxMode {
    ReadOnly,
    WorkspaceWrite,
    DangerFullAccess,
}

impl SandboxMode {
    pub fn as_cli_flag(self) -> &'static str {
        match self {
            Self::ReadOnly => "read-only",
            Self::WorkspaceWrite => "workspace-write",
            Self::DangerFullAccess => "danger-full-access",
        }
    }
}

#[derive(Copy, Clone, Debug, Eq, PartialEq, ValueEnum)]
#[value(rename_all = "kebab-case")]
pub enum ApprovalPolicy {
    Untrusted,
    OnFailure,
    OnRequest,
    Never,
}

impl ApprovalPolicy {
    pub fn as_cli_flag(self) -> &'static str {
        match self {
            Self::Untrusted => "untrusted",
            Self::OnFailure => "on-failure",
            Self::OnRequest => "on-request",
            Self::Never => "never",
        }
    }
}

#[derive(Copy, Clone, Debug, Eq, PartialEq, ValueEnum)]
#[value(rename_all = "kebab-case")]
pub enum ColorMode {
    Always,
    Never,
    Auto,
}

impl ColorMode {
    pub fn as_cli_flag(self) -> &'static str {
        match self {
            Self::Always => "always",
            Self::Never => "never",
            Self::Auto => "auto",
        }
    }
}

#[derive(Copy, Clone, Debug, Eq, PartialEq, ValueEnum)]
#[value(rename_all = "lowercase")]
pub enum OssProvider {
    Lmstudio,
    Ollama,
}

impl OssProvider {
    pub fn as_cli_flag(self) -> &'static str {
        match self {
            Self::Lmstudio => "lmstudio",
            Self::Ollama => "ollama",
        }
    }
}

#[derive(Args, Debug, Clone)]
pub struct PromptArgs {
    /// Prompt text. Mutually exclusive with --prompt-file/--prompt-stdin.
    #[arg(long)]
    pub prompt: Option<String>,

    /// Read prompt text from file.
    #[arg(long, value_name = "PATH", conflicts_with_all = ["prompt", "prompt_stdin"])]
    pub prompt_file: Option<PathBuf>,

    /// Read prompt text from stdin.
    #[arg(long, conflicts_with_all = ["prompt", "prompt_file"])]
    pub prompt_stdin: bool,
}

#[derive(Args, Debug, Clone)]
pub struct ConfigFlagArgs {
    /// Config override value (`key=value`). Repeatable.
    #[arg(short = 'c', long = "config", value_name = "KEY=VALUE", action = ArgAction::Append)]
    pub config: Vec<String>,

    /// Enable feature flags. Repeatable.
    #[arg(long = "enable", value_name = "FEATURE", action = ArgAction::Append)]
    pub enable: Vec<String>,

    /// Disable feature flags. Repeatable.
    #[arg(long = "disable", value_name = "FEATURE", action = ArgAction::Append)]
    pub disable: Vec<String>,
}

#[derive(Args, Debug, Clone)]
pub struct WrapperOutputArgs {
    /// Write final assistant message to this file.
    #[arg(short = 'o', long, value_name = "PATH")]
    pub output_last_message: Option<PathBuf>,

    /// Mirror parsed JSON events to stderr.
    #[arg(long)]
    pub emit_events: bool,

    /// Print raw codex JSONL events to stdout instead of final message output.
    #[arg(long)]
    pub raw_jsonl: bool,

    /// Write machine-readable result JSON to this file.
    #[arg(long, value_name = "PATH")]
    pub result_json: Option<PathBuf>,
}

#[derive(Args, Debug, Clone)]
pub struct RunArgs {
    #[command(flatten)]
    pub prompt: PromptArgs,

    #[command(flatten)]
    pub output: WrapperOutputArgs,

    #[command(flatten)]
    pub config: ConfigFlagArgs,

    /// Optional image(s) to attach to the initial prompt.
    #[arg(short = 'i', long = "image", value_name = "FILE", action = ArgAction::Append)]
    pub image: Vec<PathBuf>,

    /// Model name for Codex.
    #[arg(short = 'm', long)]
    pub model: Option<String>,

    /// Use open-source provider.
    #[arg(long)]
    pub oss: bool,

    /// Local provider to use when --oss is enabled.
    #[arg(long = "local-provider", value_enum)]
    pub local_provider: Option<OssProvider>,

    /// Codex sandbox mode.
    #[arg(short = 's', long, value_enum)]
    pub sandbox: Option<SandboxMode>,

    /// Config profile name from codex config.
    #[arg(short = 'p', long)]
    pub profile: Option<String>,

    /// Codex approval policy.
    #[arg(short = 'a', long = "ask-for-approval", value_enum)]
    pub approval: Option<ApprovalPolicy>,

    /// Enable Codex full-auto shorthand.
    #[arg(long)]
    pub full_auto: bool,

    /// Bypass Codex approvals and sandbox.
    #[arg(long)]
    pub dangerously_bypass_approvals_and_sandbox: bool,

    /// Working directory for Codex run.
    #[arg(short = 'C', long = "cd", value_name = "DIR")]
    pub cd: Option<PathBuf>,

    /// Allow running outside git repo.
    #[arg(long)]
    pub skip_git_repo_check: bool,

    /// Additional writable directories. Repeatable.
    #[arg(long = "add-dir", value_name = "DIR", action = ArgAction::Append)]
    pub add_dir: Vec<PathBuf>,

    /// Run without persisted Codex session files.
    #[arg(long)]
    pub ephemeral: bool,

    /// Output schema file passed to codex exec.
    #[arg(long = "output-schema", value_name = "PATH")]
    pub output_schema: Option<PathBuf>,

    /// Color mode forwarded to codex exec.
    #[arg(long, value_enum)]
    pub color: Option<ColorMode>,

    /// Force cursor-based progress updates in exec mode.
    #[arg(long)]
    pub progress_cursor: bool,
}

#[derive(Args, Debug, Clone)]
pub struct ResumeArgs {
    /// Thread/session id to resume.
    pub thread_id: Option<String>,

    /// Resume the most recent session.
    #[arg(long)]
    pub last: bool,

    /// Show all sessions (disables cwd filtering).
    #[arg(long)]
    pub all: bool,

    #[command(flatten)]
    pub prompt: PromptArgs,

    #[command(flatten)]
    pub output: WrapperOutputArgs,

    #[command(flatten)]
    pub config: ConfigFlagArgs,

    /// Optional image(s) to attach to the resume prompt.
    #[arg(short = 'i', long = "image", value_name = "FILE", action = ArgAction::Append)]
    pub image: Vec<PathBuf>,

    /// Model name for Codex.
    #[arg(short = 'm', long)]
    pub model: Option<String>,

    /// Enable Codex full-auto shorthand.
    #[arg(long)]
    pub full_auto: bool,

    /// Bypass Codex approvals and sandbox.
    #[arg(long)]
    pub dangerously_bypass_approvals_and_sandbox: bool,

    /// Allow running outside git repo.
    #[arg(long)]
    pub skip_git_repo_check: bool,

    /// Run without persisted Codex session files.
    #[arg(long)]
    pub ephemeral: bool,
}

#[derive(Args, Debug, Clone)]
pub struct ReviewArgs {
    #[command(flatten)]
    pub prompt: PromptArgs,

    #[command(flatten)]
    pub output: WrapperOutputArgs,

    #[command(flatten)]
    pub config: ConfigFlagArgs,

    /// Review staged, unstaged, and untracked changes.
    #[arg(long)]
    pub uncommitted: bool,

    /// Review changes against this base branch.
    #[arg(long)]
    pub base: Option<String>,

    /// Review changes introduced by a commit.
    #[arg(long)]
    pub commit: Option<String>,

    /// Model name for Codex.
    #[arg(short = 'm', long)]
    pub model: Option<String>,

    /// Optional commit title shown in summary.
    #[arg(long)]
    pub title: Option<String>,

    /// Enable Codex full-auto shorthand.
    #[arg(long)]
    pub full_auto: bool,

    /// Bypass Codex approvals and sandbox.
    #[arg(long)]
    pub dangerously_bypass_approvals_and_sandbox: bool,

    /// Allow running outside git repo.
    #[arg(long)]
    pub skip_git_repo_check: bool,

    /// Run without persisted Codex session files.
    #[arg(long)]
    pub ephemeral: bool,
}
