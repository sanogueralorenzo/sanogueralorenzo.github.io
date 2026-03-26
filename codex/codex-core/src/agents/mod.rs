mod config;
mod review;
mod task;
mod worker;

use anyhow::{Context, Result};
use chrono::Utc;
use clap::{Parser, Subcommand, ValueEnum};
use serde::{Deserialize, Serialize};
use std::env;
use std::ffi::OsString;
use std::fs;
use std::path::PathBuf;

#[derive(Parser, Debug)]
#[command(name = "codex-core agents")]
#[command(about = "Track local tasks and run a basic worker loop")]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand, Debug)]
enum Commands {
    /// Initialize local agent configuration
    Config {
        #[command(subcommand)]
        action: config::ConfigCommand,
    },
    /// Create/list/show tasks
    Task {
        #[command(subcommand)]
        action: task::TaskCommand,
    },
    /// Start autonomous worker loop
    Worker {
        #[command(subcommand)]
        action: worker::WorkerCommand,
    },
    /// Review GitHub pull requests with Codex and post inline findings
    Review {
        #[command(subcommand)]
        action: review::ReviewCommand,
    },
}

#[derive(Clone, Debug)]
struct StateLayout {
    root: PathBuf,
    tasks_dir: PathBuf,
    config_file: PathBuf,
}

impl StateLayout {
    fn repos_dir(&self) -> PathBuf {
        self.root.join("repos")
    }

    fn worktrees_dir(&self) -> PathBuf {
        self.root.join("worktrees")
    }

    fn reviews_dir(&self) -> PathBuf {
        self.root.join("reviews")
    }
}

#[derive(Clone, Copy, Debug, Default, Serialize, Deserialize, PartialEq, Eq, ValueEnum)]
#[serde(rename_all = "snake_case")]
pub enum ReviewPublishMode {
    #[default]
    Publish,
    Pending,
}

impl ReviewPublishMode {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Publish => "publish",
            Self::Pending => "pending",
        }
    }
}

#[derive(Clone, Debug, Default, Serialize, Deserialize, PartialEq, Eq)]
struct AgentsConfig {
    state_version: u32,
    initialized_at: String,
    #[serde(default)]
    review_mode: ReviewPublishMode,
    allowed_repos: Vec<String>,
    #[serde(default)]
    allowed_boards: Vec<u64>,
}

impl AgentsConfig {
    fn new() -> Self {
        Self {
            state_version: 3,
            initialized_at: now_utc(),
            review_mode: ReviewPublishMode::Publish,
            allowed_repos: Vec::new(),
            allowed_boards: Vec::new(),
        }
    }
}

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, Eq)]
struct AvailableRepo {
    full_name: String,
}

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, Eq)]
struct AvailableBoard {
    id: u64,
    key: String,
}

#[derive(Debug, Deserialize)]
struct RepoOwner {
    login: String,
}

pub fn run_from(args: Vec<OsString>) -> u8 {
    let mut normalized = Vec::with_capacity(args.len() + 1);
    normalized.push(OsString::from("codex-core agents"));
    if args.first().and_then(|value| value.to_str()) == Some("agents") {
        normalized.extend(args.into_iter().skip(1));
    } else {
        normalized.extend(args);
    }

    let cli = match Cli::try_parse_from(normalized) {
        Ok(cli) => cli,
        Err(error) => {
            let code = error.exit_code();
            let _ = error.print();
            return code as u8;
        }
    };

    match run(cli) {
        Ok(()) => 0,
        Err(error) => {
            eprintln!("Error: {error}");
            1
        }
    }
}

fn run(cli: Cli) -> Result<()> {
    let layout = resolve_state_layout()?;

    match cli.command {
        Commands::Config { action } => config::handle_config(action, &layout),
        Commands::Task { action } => task::handle_task(action, &layout),
        Commands::Worker { action } => worker::handle_worker(action, &layout),
        Commands::Review { action } => review::handle_review(action, &layout),
    }
}

fn ensure_state_layout(layout: &StateLayout) -> Result<()> {
    let state_directories = [
        layout.tasks_dir.clone(),
        layout.repos_dir(),
        layout.worktrees_dir(),
        layout.reviews_dir(),
    ];

    for directory in state_directories {
        fs::create_dir_all(&directory)
            .with_context(|| format!("failed to create {}", directory.display()))?;
    }

    if !layout.config_file.exists() {
        let config = AgentsConfig::new();
        save_agents_config(layout, &config)?;
    }
    Ok(())
}

fn resolve_state_layout() -> Result<StateLayout> {
    let root = if let Some(path) = env::var_os("CODEX_AGENTS_HOME") {
        let trimmed = path.to_string_lossy().trim().to_string();
        if trimmed.is_empty() {
            default_state_home()?
        } else {
            PathBuf::from(trimmed)
        }
    } else {
        default_state_home()?
    };

    Ok(StateLayout {
        tasks_dir: root.join("tasks"),
        config_file: root.join("config.json"),
        root,
    })
}

fn load_agents_config(layout: &StateLayout) -> Result<AgentsConfig> {
    let content = fs::read_to_string(&layout.config_file)
        .with_context(|| format!("failed to read {}", layout.config_file.display()))?;
    serde_json::from_str(&content)
        .with_context(|| format!("failed to parse {}", layout.config_file.display()))
}

fn save_agents_config(layout: &StateLayout, config: &AgentsConfig) -> Result<()> {
    let payload =
        serde_json::to_string_pretty(config).context("failed to serialize agents config")?;
    fs::write(&layout.config_file, payload)
        .with_context(|| format!("failed to write {}", layout.config_file.display()))?;
    Ok(())
}

fn default_state_home() -> Result<PathBuf> {
    let home = env::var_os("HOME").context("HOME is not set")?;
    Ok(PathBuf::from(home).join(".codex").join("agents"))
}

fn now_utc() -> String {
    Utc::now().format("%Y-%m-%dT%H:%M:%SZ").to_string()
}
