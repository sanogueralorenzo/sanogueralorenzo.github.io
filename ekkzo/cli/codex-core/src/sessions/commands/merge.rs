use crate::sessions::adapters::session_store::{SessionStore, resolve_session_by_id};
use crate::sessions::cli::MergeArgs;
use crate::sessions::shared::models::{MergeResult, SessionResultStatus};
use anyhow::{Result, bail};

use super::codex_exec::{run_codex_exec_resume, run_codex_exec_resume_capture_last_message};
use super::output::emit_merge_output;
use super::prompts::{build_merger_summary_prompt, build_target_apply_prompt};

pub(crate) fn cmd_merge(args: MergeArgs) -> Result<()> {
    let target_id = args.target.trim().to_string();
    let merge_id = args.merge.trim().to_string();
    if target_id.is_empty() {
        bail!("--target cannot be empty");
    }
    if merge_id.is_empty() {
        bail!("--merge cannot be empty");
    }
    if target_id == merge_id {
        bail!("--target and --merge must be different sessions");
    }

    let store = SessionStore::new(args.home)?;
    let sessions = store.collect_sessions()?;
    let target = resolve_session_by_id(&sessions, &target_id)?.clone();
    let merge = resolve_session_by_id(&sessions, &merge_id)?.clone();

    let summary_prompt = build_merger_summary_prompt(&target, &merge);
    let transfer_summary = run_codex_exec_resume_capture_last_message(&merge, &summary_prompt)?;
    let apply_prompt = build_target_apply_prompt(&merge, &transfer_summary);
    run_codex_exec_resume(&target, &apply_prompt)?;

    let deleted = store.delete_session_hard(&merge)?;
    emit_merge_output(
        MergeResult {
            target_id: target.id,
            merged_id: merge.id,
            merged_deleted: deleted.status == SessionResultStatus::Succeeded,
            merged_file_path: deleted.file_path,
        },
        args.json,
        args.plain,
    )
}
