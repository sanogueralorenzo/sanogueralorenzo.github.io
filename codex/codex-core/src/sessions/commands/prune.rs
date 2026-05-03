use crate::sessions::adapters::session_store::SessionStore;
use crate::sessions::cli::{PruneArgs, PruneMode, WatchPruneArgs};
use crate::sessions::services::session_service::{prune_sessions, validate_days};
use crate::sessions::shared::output::OutputFormat;
use anyhow::{Result, bail};
use std::thread;
use std::time::Duration;

use super::output::emit_prune_output;

pub(crate) fn cmd_prune(args: PruneArgs) -> Result<()> {
    let store = SessionStore::new(args.home)?;
    let format = OutputFormat::from_flags(args.json, args.plain);
    let hard = matches!(args.mode, PruneMode::Delete);
    let mode = if hard { "delete" } else { "archive" };
    let report = prune_sessions(&store, args.older_than_days, args.dry_run, hard, mode)?;
    emit_prune_output(&report, format)
}

pub(crate) fn cmd_watch_prune(args: WatchPruneArgs) -> Result<()> {
    validate_days(args.older_than_days)?;
    if args.interval_minutes == 0 {
        bail!("--interval-minutes must be >= 1");
    }

    let store = SessionStore::new(args.home)?;
    let format = OutputFormat::from_flags(args.json, args.plain);
    let interval = Duration::from_secs(args.interval_minutes * 60);
    let hard = matches!(args.mode, PruneMode::Delete);
    let mode = if hard { "delete" } else { "archive" };

    loop {
        let report = prune_sessions(&store, args.older_than_days, args.dry_run, hard, mode)?;
        emit_prune_output(&report, format)?;

        if args.once {
            break;
        }

        if !args.json && !args.plain {
            println!(
                "Waiting {} minute(s) before next prune...",
                args.interval_minutes
            );
        }

        thread::sleep(interval);
    }

    Ok(())
}
