use crate::shared::models::SessionMeta;

pub(crate) fn build_merger_summary_prompt(target: &SessionMeta, merge: &SessionMeta) -> String {
    let merge_title = merge.title.as_deref().unwrap_or("(no title)");
    let merge_cwd = merge.cwd.as_deref().unwrap_or("(unknown cwd)");
    let merge_source = merge.source.as_deref().unwrap_or("(unknown source)");
    let target_title = target.title.as_deref().unwrap_or("(no title)");

    format!(
        "You are resuming merger session {merge_id}.\n\
         \n\
         Task: build a compact context-transfer summary that will be injected into target session {target_id} ({target_title}).\n\
         \n\
         Merger session metadata:\n\
         - id: {merge_id}\n\
         - title: {merge_title}\n\
         - cwd: {merge_cwd}\n\
         - source: {merge_source}\n\
         - file_path: {merge_path}\n\
         \n\
         Requirements:\n\
         - Produce a compact context-transfer summary from this merger session.\n\
         - Include only non-actionable context: decisions, constraints, preferences, resolved facts.\n\
         - Exclude pending tasks, TODO lists, and execution instructions.\n\
         - If merger context conflicts with existing target context, include a short note in the summary without trying to resolve or overwrite facts.\n\
         - Keep the summary concise and transferable.\n\
         - Do not run tools or modify files.\n\
         \n\
         Output format (exact headings, in this order):\n\
         ## Decisions\n\
         ## Constraints\n\
         ## Preferences\n\
         ## Resolved Facts\n\
         ## Relevant Open Questions\n\
         \n\
         Open-questions rule:\n\
         - Include this section only if a question is still needed to interpret context.\n\
         - If none apply, write: None.",
        target_id = target.id,
        target_title = target_title,
        merge_id = merge.id,
        merge_title = merge_title,
        merge_cwd = merge_cwd,
        merge_source = merge_source,
        merge_path = merge.file_path.display(),
    )
}

pub(crate) fn build_target_apply_prompt(merge: &SessionMeta, transfer_summary: &str) -> String {
    let merge_title = merge.title.as_deref().unwrap_or("(no title)");
    let summary = truncate_chars(transfer_summary.trim(), 12000);

    format!(
        "Merge context into this target session.\n\
         \n\
         Context merger session metadata:\n\
         - merger_id: {merge_id}\n\
         - merger_title: {merge_title}\n\
         - merger_cwd: {merge_cwd}\n\
         - merger_file_path: {merge_path}\n\
         \n\
         Context transfer summary:\n\
         {summary}\n\
         \n\
         Instructions:\n\
         - Preserve this context for future reasoning in this target session.\n\
         - If incoming context conflicts with existing target context, note the conflict internally and prefer existing target context unless explicitly asked to change it.\n\
         - Do not run tools or modify files.\n\
         - Respond with exactly: Thread merged",
        merge_id = merge.id,
        merge_title = merge_title,
        merge_cwd = merge.cwd.as_deref().unwrap_or("(unknown cwd)"),
        merge_path = merge.file_path.display(),
        summary = summary,
    )
}

pub(crate) fn truncate_chars(value: &str, max_chars: usize) -> String {
    if value.chars().count() <= max_chars {
        return value.to_string();
    }
    let truncated: String = value.chars().take(max_chars).collect();
    format!("{truncated}...")
}

pub(crate) fn truncate_chars_exact(value: &str, max_chars: usize) -> String {
    if value.chars().count() <= max_chars {
        return value.to_string();
    }
    value.chars().take(max_chars).collect()
}
