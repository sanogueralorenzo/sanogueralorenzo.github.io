use crate::shared::models::{
    DeleteResult, MergeResult, OperationBatchResult, PruneResult, TitleResult,
};
use crate::shared::output::OutputFormat;
use anyhow::Result;

pub(crate) fn emit_delete_output(result: DeleteResult, json: bool, plain: bool) -> Result<()> {
    if json {
        println!("{}", serde_json::to_string_pretty(&result)?);
    } else if plain {
        let error = result.error.clone().unwrap_or_default();
        println!(
            "{}\t{}\t{}\t{}",
            result.id, result.action, result.file_path, error
        );
    } else {
        let is_failed = result.error.is_some();
        match result.action.as_str() {
            "archived" => println!("Archived session {}", result.id),
            "unarchived" => println!("Unarchived session {}", result.id),
            "deleted" if is_failed => println!("Delete incomplete for session {}", result.id),
            _ => println!("Deleted session {}", result.id),
        }
        println!("Path: {}", result.file_path);
        if let Some(error) = result.error {
            println!("Error: {}", error);
        }
    }

    Ok(())
}

pub(crate) fn emit_operation_batch_output(
    result: OperationBatchResult,
    json: bool,
    plain: bool,
) -> Result<()> {
    if json {
        println!("{}", serde_json::to_string_pretty(&result)?);
        return Ok(());
    }

    if plain {
        println!(
            "{}\t{}\t{}\t{}\t{}\t{}",
            result.action,
            result.processed,
            result.succeeded,
            result.failed,
            result.skipped,
            result.dry_run
        );
        for item in result.sessions {
            let error = item.error.unwrap_or_default();
            println!(
                "{}\t{}\t{}\t{}",
                item.id, item.action, item.file_path, error
            );
        }
        return Ok(());
    }

    let verb = match result.action.as_str() {
        "delete" if result.dry_run => "Would delete",
        "delete" if result.failed > 0 || result.skipped > 0 => "Processed delete for",
        "delete" => "Deleted",
        "archive" if result.dry_run => "Would archive",
        "archive" if result.failed > 0 || result.skipped > 0 => "Processed archive for",
        "archive" => "Archived",
        "unarchive" if result.dry_run => "Would unarchive",
        "unarchive" if result.failed > 0 || result.skipped > 0 => "Processed unarchive for",
        "unarchive" => "Unarchived",
        _ => "Processed",
    };
    println!(
        "{} {} session(s). Succeeded: {}. Failed: {}. Skipped: {}.",
        verb, result.processed, result.succeeded, result.failed, result.skipped
    );
    for item in result.sessions {
        if let Some(error) = item.error {
            println!(
                "- {} [{}] ({}) error={}",
                item.id, item.action, item.file_path, error
            );
        } else {
            println!("- {} [{}] ({})", item.id, item.action, item.file_path);
        }
    }
    Ok(())
}

pub(crate) fn emit_prune_output(report: &PruneResult, format: OutputFormat) -> Result<()> {
    match format {
        OutputFormat::Json => {
            println!("{}", serde_json::to_string_pretty(report)?);
        }
        OutputFormat::Plain => {
            println!(
                "{}\t{}\t{}\t{}",
                report.scanned, report.pruned, report.dry_run, report.hard
            );
            for session in &report.sessions {
                let error = session.error.clone().unwrap_or_default();
                println!(
                    "{}\t{}\t{}\t{}",
                    session.id, session.action, session.file_path, error
                );
            }
        }
        OutputFormat::Human => {
            let action = if report.hard { "delete" } else { "archive" };
            let verb = if report.dry_run {
                format!("Would {action}")
            } else if report.hard {
                "Deleted".to_string()
            } else {
                "Archived".to_string()
            };
            println!(
                "{} {} of {} active session(s) older than {} day(s).",
                verb, report.pruned, report.scanned, report.older_than_days
            );
            for session in &report.sessions {
                if let Some(error) = &session.error {
                    println!(
                        "- {} [{}] ({}) error={}",
                        session.id, session.action, session.file_path, error
                    );
                } else {
                    println!(
                        "- {} [{}] ({})",
                        session.id, session.action, session.file_path
                    );
                }
            }
        }
    }

    Ok(())
}

pub(crate) fn emit_merge_output(result: MergeResult, json: bool, plain: bool) -> Result<()> {
    if json {
        println!("{}", serde_json::to_string_pretty(&result)?);
        return Ok(());
    }

    if plain {
        println!(
            "{}\t{}\t{}\t{}",
            result.target_id, result.merged_id, result.merged_deleted, result.merged_file_path
        );
        return Ok(());
    }

    println!(
        "Merged session {} into session {}.",
        result.merged_id, result.target_id
    );
    println!("Deleted merged session file: {}", result.merged_file_path);
    Ok(())
}

pub(crate) fn emit_title_output(result: TitleResult, json: bool, plain: bool) -> Result<()> {
    if json {
        println!("{}", serde_json::to_string_pretty(&result)?);
        return Ok(());
    }

    if plain {
        println!("{}\t{}", result.id, result.title);
        return Ok(());
    }

    println!("Updated session title for {}", result.id);
    println!("Title: {}", result.title);
    Ok(())
}
