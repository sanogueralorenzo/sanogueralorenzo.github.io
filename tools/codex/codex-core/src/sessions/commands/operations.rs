use crate::sessions::adapters::session_store::SessionStore;
use crate::sessions::cli::{ArchiveArgs, DeleteArgs, RestoreArgs};
use crate::sessions::shared::models::{
    DeleteResult, OperationBatchResult, SessionMeta, SessionResultReason, SessionResultStatus,
};
use anyhow::Result;
use std::collections::HashMap;

use super::output::emit_operation_batch_output;
use super::selection::{resolve_delete_targets, resolve_targets_for_inputs, validate_delete_args};

pub(crate) fn cmd_rm(args: DeleteArgs) -> Result<()> {
    validate_delete_args(&args)?;
    let store = SessionStore::new(args.home.clone())?;
    let sessions = store.collect_sessions()?;
    let targets = resolve_delete_targets(&sessions, &args)?;
    let pinned_ids = store.load_pinned_thread_ids()?;
    let unpinned_targets: Vec<&SessionMeta> = targets
        .iter()
        .copied()
        .filter(|target| !pinned_ids.contains(&target.id))
        .collect();

    let operation = "delete";
    let mut result_by_id: HashMap<String, DeleteResult> = if args.dry_run {
        unpinned_targets
            .iter()
            .map(|target| {
                let result = DeleteResult {
                    id: target.id.clone(),
                    file_path: target.file_path.display().to_string(),
                    status: SessionResultStatus::Skipped,
                    reason: SessionResultReason::DryRun,
                    message: None,
                };
                (result.id.clone(), result)
            })
            .collect()
    } else {
        store
            .delete_sessions_hard(&unpinned_targets)?
            .into_iter()
            .map(|result| (result.id.clone(), result))
            .collect()
    };

    let mut results = Vec::with_capacity(targets.len());
    for target in targets {
        if pinned_ids.contains(&target.id) {
            results.push(build_pinned_skip_result(target));
            continue;
        }

        let Some(result) = result_by_id.remove(&target.id) else {
            results.push(DeleteResult {
                id: target.id.clone(),
                file_path: target.file_path.display().to_string(),
                status: SessionResultStatus::Failed,
                reason: SessionResultReason::Error,
                message: Some("internal error: missing result for resolved target".to_string()),
            });
            continue;
        };

        results.push(result);
    }

    emit_operation_batch_output(
        build_operation_batch_result(operation, args.dry_run, results),
        args.json,
        args.plain,
    )
}

pub(crate) fn cmd_archive(args: ArchiveArgs) -> Result<()> {
    let store = SessionStore::new(args.home.clone())?;
    let sessions = store.collect_sessions()?;
    let targets = resolve_targets_for_inputs(&sessions, &args.ids)?;

    let mut results = Vec::with_capacity(targets.len());
    for target in targets {
        results.push(store.archive_session(target)?);
    }

    emit_operation_batch_output(
        build_operation_batch_result("archive", false, results),
        args.json,
        args.plain,
    )
}

pub(crate) fn cmd_restore(args: RestoreArgs) -> Result<()> {
    let store = SessionStore::new(args.home.clone())?;
    let sessions = store.collect_sessions()?;
    let targets = resolve_targets_for_inputs(&sessions, &args.ids)?;

    let mut results = Vec::with_capacity(targets.len());
    for target in targets {
        results.push(store.unarchive_session(target)?);
    }

    emit_operation_batch_output(
        build_operation_batch_result("restore", false, results),
        args.json,
        args.plain,
    )
}

fn build_operation_batch_result(
    operation: &str,
    dry_run: bool,
    sessions: Vec<DeleteResult>,
) -> OperationBatchResult {
    let processed = sessions.len();
    let failed = sessions
        .iter()
        .filter(|session| session.status == SessionResultStatus::Failed)
        .count();
    let succeeded = sessions
        .iter()
        .filter(|session| session.status == SessionResultStatus::Succeeded)
        .count();
    let skipped = sessions
        .iter()
        .filter(|session| session.status == SessionResultStatus::Skipped)
        .count();

    OperationBatchResult {
        operation: operation.to_string(),
        dry_run,
        processed,
        succeeded,
        failed,
        skipped,
        sessions,
    }
}

fn build_pinned_skip_result(target: &SessionMeta) -> DeleteResult {
    DeleteResult {
        id: target.id.clone(),
        file_path: target.file_path.display().to_string(),
        status: SessionResultStatus::Skipped,
        reason: SessionResultReason::Pinned,
        message: None,
    }
}

#[cfg(test)]
mod tests {
    use super::build_operation_batch_result;
    use crate::sessions::shared::models::{DeleteResult, SessionResultReason, SessionResultStatus};

    #[test]
    fn batch_result_counts_by_status() {
        let result = build_operation_batch_result(
            "delete",
            false,
            vec![
                DeleteResult {
                    id: "a".to_string(),
                    file_path: "/tmp/a".to_string(),
                    status: SessionResultStatus::Succeeded,
                    reason: SessionResultReason::Completed,
                    message: None,
                },
                DeleteResult {
                    id: "b".to_string(),
                    file_path: "/tmp/b".to_string(),
                    status: SessionResultStatus::Skipped,
                    reason: SessionResultReason::Pinned,
                    message: None,
                },
                DeleteResult {
                    id: "c".to_string(),
                    file_path: "/tmp/c".to_string(),
                    status: SessionResultStatus::Failed,
                    reason: SessionResultReason::Error,
                    message: None,
                },
            ],
        );

        assert_eq!(result.processed, 3);
        assert_eq!(result.succeeded, 1);
        assert_eq!(result.skipped, 1);
        assert_eq!(result.failed, 1);
    }
}
