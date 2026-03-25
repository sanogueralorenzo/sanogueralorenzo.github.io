mod cli;
mod manager;
mod models;
mod output;
mod process;
mod util;
mod watcher;

use anyhow::{Context, Result, bail};
use clap::Parser;
use cli::{Cli, Commands, WatchCommand};
use manager::ProfileManager;
use models::{ProfileSource, WatcherStatus};
use output::{masked, print_profiles, print_use_result};
use std::ffi::OsString;
use util::{expand_tilde, normalize_profile_name, resolve_home};
use watcher::AuthSyncWatcher;

pub fn run_from(args: Vec<OsString>) -> u8 {
    let mut normalized = Vec::with_capacity(args.len() + 1);
    normalized.push(OsString::from("codex-core auth"));
    if args.first().and_then(|value| value.to_str()) == Some("auth") {
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
    let home = resolve_home(cli.home)?;
    let manager = ProfileManager::new(home.clone());

    match cli.command {
        Commands::Save(args) => {
            let source = if let Some(path) = args.path {
                ProfileSource::Path(expand_tilde(path))
            } else {
                let _ = args.from_current;
                ProfileSource::Current
            };

            let before = manager.list_profiles()?;
            if before.is_empty() {
                println!("Existing profiles: (none)");
            } else {
                println!("Existing profiles: {}", before.join(", "));
            }

            let saved_name = manager.save_profile(&args.profile, source)?;
            println!("Saved profile '{saved_name}'");

            let after = manager.list_profiles()?;
            println!("Available profiles: {}", after.join(", "));
        }
        Commands::Use(args) => match (args.profile, args.path) {
            (Some(_), Some(_)) => {
                bail!("Use either <profile> or --path <auth.json>, not both")
            }
            (None, None) => {
                bail!("Missing profile name or --path option")
            }
            (Some(profile), None) => {
                let result = manager.apply_profile(&profile)?;
                print_use_result(result);
            }
            (None, Some(path)) => {
                let path = expand_tilde(path);
                let result = manager.apply_auth_file(&path)?;
                print_use_result(result);
            }
        },
        Commands::List(args) => {
            print_profiles(&manager, args.plain)?;
        }
        Commands::Current(args) => {
            if args.plain {
                if let Some(current_profile) = manager.current_profile_name()? {
                    println!("{current_profile}");
                }
            } else {
                let current_profile = manager
                    .current_profile_name()?
                    .unwrap_or_else(|| "(untracked)".to_string());
                println!("Current profile: {current_profile}");

                let document = manager.current_auth_document()?;
                println!("auth_mode: {}", document.auth_mode);
                println!("account_id: {}", masked(&document.account_id));
            }
        }
        Commands::Remove(args) => {
            let normalized = normalize_profile_name(&args.profile)?;
            manager.remove_profile(&args.profile)?;
            println!("Removed profile '{normalized}'");
            print_profiles(&manager, false)?;
        }
        Commands::Watch { action } => {
            let watcher = AuthSyncWatcher::new(home.clone());
            match action {
                WatchCommand::Start => {
                    let executable =
                        std::env::current_exe().context("failed to resolve current executable")?;
                    let pid = watcher.start_daemon(&executable, &home)?;
                    println!("Watcher running (PID {pid})");
                }
                WatchCommand::Stop => {
                    watcher.stop_daemon()?;
                    println!("Watcher stopped");
                }
                WatchCommand::Status => match watcher.status() {
                    WatcherStatus::Stopped => println!("Watcher stopped"),
                    WatcherStatus::Running(pid) => println!("Watcher running (PID {pid})"),
                },
                WatchCommand::Run => {
                    watcher.run_loop()?;
                }
            }
        }
    }

    Ok(())
}
