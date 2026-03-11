use crate::shared::models::{
    DeleteResult, MergeResult, OperationBatchResult, PruneResult, SessionOperation,
    SessionResultReason, SessionResultStatus, TitleResult,
};
use crate::shared::output::OutputFormat;
use anyhow::Result;

pub(crate) fn emit_delete_output(result: DeleteResult, json: bool, plain: bool) -> Result<()> {
    if json {
        println!("{}", serde_json::to_string_pretty(&result)?);
    } else if plain {
        let message = result.message.clone().unwrap_or_default();
        println!(
            "{}\t{}\t{}\t{}\t{}\t{}",
            result.id,
            operation_label(result.operation),
            status_label(result.status),
            reason_label(result.reason),
            result.file_path,
            message
        );
    } else {
        match result.status {
            SessionResultStatus::Succeeded => {
                println!(
                    "{} session {}",
                    operation_past_tense(result.operation),
                    result.id
                );
            }
            SessionResultStatus::Skipped => {
                println!(
                    "Skipped {} for session {}",
                    operation_infinitive(result.operation),
                    result.id
                );
            }
            SessionResultStatus::Failed => {
                println!(
                    "Failed to {} session {}",
                    operation_infinitive(result.operation),
                    result.id
                );
            }
        }
        println!("Path: {}", result.file_path);
        println!("Status: {}", status_label(result.status));
        println!("Reason: {}", reason_label(result.reason));
        if let Some(message) = result.message {
            println!("Message: {}", message);
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
            operation_label(result.operation),
            result.processed,
            result.succeeded,
            result.failed,
            result.skipped,
            result.dry_run
        );
        for item in result.sessions {
            let message = item.message.unwrap_or_default();
            println!(
                "{}\t{}\t{}\t{}\t{}\t{}",
                item.id,
                operation_label(item.operation),
                status_label(item.status),
                reason_label(item.reason),
                item.file_path,
                message
            );
        }
        return Ok(());
    }

    let verb = if result.dry_run {
        format!("Would {}", operation_infinitive(result.operation))
    } else if result.failed > 0 || result.skipped > 0 {
        format!("Processed {} for", operation_infinitive(result.operation))
    } else {
        operation_past_tense(result.operation).to_string()
    };
    println!(
        "{} {} session(s). Succeeded: {}. Failed: {}. Skipped: {}.",
        verb, result.processed, result.succeeded, result.failed, result.skipped
    );
    for item in result.sessions {
        if let Some(message) = item.message {
            println!(
                "- {} [{} {} {}] ({}) message={}",
                item.id,
                operation_label(item.operation),
                status_label(item.status),
                reason_label(item.reason),
                item.file_path,
                message
            );
        } else {
            println!(
                "- {} [{} {} {}] ({})",
                item.id,
                operation_label(item.operation),
                status_label(item.status),
                reason_label(item.reason),
                item.file_path
            );
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
                let message = session.message.clone().unwrap_or_default();
                println!(
                    "{}\t{}\t{}\t{}\t{}\t{}",
                    session.id,
                    operation_label(session.operation),
                    status_label(session.status),
                    reason_label(session.reason),
                    session.file_path,
                    message
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
                if let Some(message) = &session.message {
                    println!(
                        "- {} [{} {} {}] ({}) message={}",
                        session.id,
                        operation_label(session.operation),
                        status_label(session.status),
                        reason_label(session.reason),
                        session.file_path,
                        message
                    );
                } else {
                    println!(
                        "- {} [{} {} {}] ({})",
                        session.id,
                        operation_label(session.operation),
                        status_label(session.status),
                        reason_label(session.reason),
                        session.file_path
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

fn operation_label(operation: SessionOperation) -> &'static str {
    match operation {
        SessionOperation::Delete => "delete",
        SessionOperation::Archive => "archive",
        SessionOperation::Unarchive => "unarchive",
    }
}

fn operation_infinitive(operation: SessionOperation) -> &'static str {
    match operation {
        SessionOperation::Delete => "delete",
        SessionOperation::Archive => "archive",
        SessionOperation::Unarchive => "unarchive",
    }
}

fn operation_past_tense(operation: SessionOperation) -> &'static str {
    match operation {
        SessionOperation::Delete => "Deleted",
        SessionOperation::Archive => "Archived",
        SessionOperation::Unarchive => "Unarchived",
    }
}

fn status_label(status: SessionResultStatus) -> &'static str {
    match status {
        SessionResultStatus::Succeeded => "succeeded",
        SessionResultStatus::Skipped => "skipped",
        SessionResultStatus::Failed => "failed",
    }
}

fn reason_label(reason: SessionResultReason) -> &'static str {
    match reason {
        SessionResultReason::Completed => "completed",
        SessionResultReason::DryRun => "dry_run",
        SessionResultReason::Pinned => "pinned",
        SessionResultReason::FileDeleteFailed => "file_delete_failed",
        SessionResultReason::DbDeleteFailed => "db_delete_failed",
        SessionResultReason::TitleCleanupFailed => "title_cleanup_failed",
        SessionResultReason::InternalError => "internal_error",
    }
}
