use crate::shared::models::{
    MergeResult, OperationBatchResult, PruneResult, SessionResultReason, SessionResultStatus,
    TitleResult,
};
use crate::shared::output::OutputFormat;
use anyhow::Result;

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
            result.operation,
            result.processed,
            result.succeeded,
            result.failed,
            result.skipped,
            result.dry_run
        );
        for item in result.sessions {
            let message = item.message.unwrap_or_default();
            println!(
                "{}\t{}\t{}\t{}\t{}",
                item.id,
                status_label(item.status),
                reason_label(item.reason),
                item.file_path,
                message
            );
        }
        return Ok(());
    }

    let verb = if result.dry_run {
        format!("Would {}", result.operation)
    } else if result.failed > 0 || result.skipped > 0 {
        format!("Processed {} for", result.operation)
    } else {
        past_tense_operation(&result.operation).to_string()
    };
    println!(
        "{} {} session(s). Succeeded: {}. Failed: {}. Skipped: {}.",
        verb, result.processed, result.succeeded, result.failed, result.skipped
    );
    for item in result.sessions {
        if let Some(message) = item.message {
            println!(
                "- {} [{} {}] ({}) message={}",
                item.id,
                status_label(item.status),
                reason_label(item.reason),
                item.file_path,
                message
            );
        } else {
            println!(
                "- {} [{} {}] ({})",
                item.id,
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
                report.scanned, report.pruned, report.dry_run, report.mode
            );
            for session in &report.sessions {
                let message = session.message.clone().unwrap_or_default();
                println!(
                    "{}\t{}\t{}\t{}\t{}",
                    session.id,
                    status_label(session.status),
                    reason_label(session.reason),
                    session.file_path,
                    message
                );
            }
        }
        OutputFormat::Human => {
            let action = report.mode.as_str();
            let verb = if report.dry_run {
                format!("Would {action}")
            } else if action == "delete" {
                "Deleted".to_string()
            } else if action == "archive" {
                "Archived".to_string()
            } else {
                "Processed".to_string()
            };
            println!(
                "{} {} of {} active session(s) older than {} day(s).",
                verb, report.pruned, report.scanned, report.older_than_days
            );
            for session in &report.sessions {
                if let Some(message) = &session.message {
                    println!(
                        "- {} [{} {}] ({}) message={}",
                        session.id,
                        status_label(session.status),
                        reason_label(session.reason),
                        session.file_path,
                        message
                    );
                } else {
                    println!(
                        "- {} [{} {}] ({})",
                        session.id,
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

fn past_tense_operation(operation: &str) -> &'static str {
    match operation {
        "delete" => "Deleted",
        "archive" => "Archived",
        "unarchive" => "Unarchived",
        _ => "Processed",
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
        SessionResultReason::Error => "error",
    }
}
