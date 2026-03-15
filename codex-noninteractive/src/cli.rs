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
pub struct SharedExecArgs {
    /// Working directory for Codex run.
    #[arg(long, value_name = "DIR")]
    pub cd: Option<PathBuf>,

    /// Model name for Codex.
    #[arg(long)]
    pub model: Option<String>,

    /// Codex sandbox mode.
    #[arg(long, value_enum)]
    pub sandbox: Option<SandboxMode>,

    /// Codex approval policy.
    #[arg(long = "ask-for-approval", value_enum)]
    pub approval: Option<ApprovalPolicy>,

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

    /// Output schema file passed to codex exec.
    #[arg(long, value_name = "PATH")]
    pub output_schema: Option<PathBuf>,

    /// Write final assistant message to this file.
    #[arg(long, value_name = "PATH")]
    pub output_last_message: Option<PathBuf>,

    /// Color mode forwarded to codex exec.
    #[arg(long, value_enum)]
    pub color: Option<ColorMode>,

    /// Mirror raw codex --json events to stderr.
    #[arg(long)]
    pub emit_events: bool,

    /// Write machine-readable result JSON to this file.
    #[arg(long, value_name = "PATH")]
    pub result_json: Option<PathBuf>,

    /// Extra arguments forwarded to codex exec. Repeat for each token.
    #[arg(long = "extra-arg", action = ArgAction::Append)]
    pub extra_args: Vec<String>,
}

#[derive(Args, Debug, Clone)]
pub struct RunArgs {
    #[command(flatten)]
    pub prompt: PromptArgs,

    #[command(flatten)]
    pub shared: SharedExecArgs,
}

#[derive(Args, Debug, Clone)]
pub struct ResumeArgs {
    /// Thread id to resume.
    pub thread_id: Option<String>,

    /// Resume the most recent session.
    #[arg(long)]
    pub last: bool,

    #[command(flatten)]
    pub prompt: PromptArgs,

    #[command(flatten)]
    pub shared: SharedExecArgs,
}
