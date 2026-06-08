use std::collections::HashMap;
use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::{Arc, Mutex, OnceLock};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use anyhow::{Context, Result, anyhow, bail};
use base64::Engine;
use serde::Serialize;
use serde_json::{Value, json};

const DEFAULT_MAX_LINES: usize = 2000;
const DEFAULT_MAX_BYTES: usize = 50 * 1024;
const GREP_MAX_LINE_LENGTH: usize = 500;
const DEFAULT_FIND_LIMIT: usize = 1000;
const DEFAULT_GREP_LIMIT: usize = 100;
const DEFAULT_LS_LIMIT: usize = 500;
const IMAGE_INLINE_LIMIT_BYTES: u64 = 20 * 1024 * 1024;

#[derive(Debug, Clone)]
pub struct ToolSpec {
    pub name: String,
    pub description: String,
    pub parameters: Value,
}

#[derive(Debug, Clone, PartialEq)]
pub struct ToolOutput {
    pub content: String,
    pub details: Option<Value>,
    pub terminate: bool,
}

pub struct ToolRegistry {
    cwd: PathBuf,
    tools: Vec<Tool>,
}

struct Tool {
    spec: ToolSpec,
    run: fn(&ToolContext, &Value) -> Result<ToolOutput>,
}

struct ToolContext {
    cwd: PathBuf,
}

#[derive(Debug, Clone, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
struct Truncation {
    truncated: bool,
    truncated_by: Option<&'static str>,
    total_lines: usize,
    total_bytes: usize,
    output_lines: usize,
    output_bytes: usize,
    last_line_partial: bool,
    first_line_exceeds_limit: bool,
    max_lines: usize,
    max_bytes: usize,
}

struct TruncatedContent {
    content: String,
    truncation: Truncation,
}

struct TruncatedLine {
    text: String,
    was_truncated: bool,
}

impl ToolRegistry {
    pub fn coding(cwd: PathBuf) -> Self {
        Self {
            cwd,
            tools: vec![
                Tool {
                    spec: ToolSpec {
                        name: "read".to_owned(),
                        description: format!(
                            "Read a text file or supported image file. Text output is truncated to {DEFAULT_MAX_LINES} lines or {}KB. Use offset/limit for large files.",
                            DEFAULT_MAX_BYTES / 1024
                        ),
                        parameters: json!({
                            "type": "object",
                            "properties": {
                                "path": { "type": "string", "description": "Path to the file to read, relative or absolute" },
                                "offset": { "type": "number", "description": "Line number to start reading from, 1-indexed" },
                                "limit": { "type": "number", "description": "Maximum number of lines to read" }
                            },
                            "required": ["path"],
                            "additionalProperties": false
                        }),
                    },
                    run: read_tool,
                },
                Tool {
                    spec: ToolSpec {
                        name: "bash".to_owned(),
                        description: format!(
                            "Execute a shell command in the current working directory. Returns stdout and stderr, truncated to the last {DEFAULT_MAX_LINES} lines or {}KB. Optional timeout is in seconds.",
                            DEFAULT_MAX_BYTES / 1024
                        ),
                        parameters: json!({
                            "type": "object",
                            "properties": {
                                "command": { "type": "string", "description": "Shell command to execute" },
                                "timeout": { "type": "number", "description": "Timeout in seconds" }
                            },
                            "required": ["command"],
                            "additionalProperties": false
                        }),
                    },
                    run: bash_tool,
                },
                Tool {
                    spec: ToolSpec {
                        name: "edit".to_owned(),
                        description: "Edit a single file using exact text replacement. Each oldText must match exactly once in the original file and replacements must not overlap.".to_owned(),
                        parameters: json!({
                            "type": "object",
                            "properties": {
                                "path": { "type": "string", "description": "Path to the file to edit, relative or absolute" },
                                "edits": {
                                    "type": "array",
                                    "items": {
                                        "type": "object",
                                        "properties": {
                                            "oldText": { "type": "string" },
                                            "newText": { "type": "string" }
                                        },
                                        "required": ["oldText", "newText"],
                                        "additionalProperties": false
                                    }
                                }
                            },
                            "required": ["path", "edits"],
                            "additionalProperties": false
                        }),
                    },
                    run: edit_tool,
                },
                Tool {
                    spec: ToolSpec {
                        name: "write".to_owned(),
                        description: "Write content to a file. Creates parent directories and overwrites existing files.".to_owned(),
                        parameters: json!({
                            "type": "object",
                            "properties": {
                                "path": { "type": "string", "description": "Path to the file to write, relative or absolute" },
                                "content": { "type": "string", "description": "Content to write" }
                            },
                            "required": ["path", "content"],
                            "additionalProperties": false
                        }),
                    },
                    run: write_tool,
                },
                Tool {
                    spec: ToolSpec {
                        name: "grep".to_owned(),
                        description: format!(
                            "Search file contents with ripgrep. Respects .gitignore. Output is truncated to {DEFAULT_GREP_LIMIT} matches or {}KB. Long lines are truncated to {GREP_MAX_LINE_LENGTH} chars.",
                            DEFAULT_MAX_BYTES / 1024
                        ),
                        parameters: json!({
                            "type": "object",
                            "properties": {
                                "pattern": { "type": "string", "description": "Search pattern" },
                                "path": { "type": "string", "description": "Directory or file to search, default current directory" },
                                "glob": { "type": "string", "description": "Filter files by glob, for example '*.rs'" },
                                "ignoreCase": { "type": "boolean", "description": "Case-insensitive search" },
                                "literal": { "type": "boolean", "description": "Treat pattern as literal text" },
                                "context": { "type": "number", "description": "Lines before and after each match" },
                                "limit": { "type": "number", "description": "Maximum matches, default 100" }
                            },
                            "required": ["pattern"],
                            "additionalProperties": false
                        }),
                    },
                    run: grep_tool,
                },
                Tool {
                    spec: ToolSpec {
                        name: "find".to_owned(),
                        description: format!(
                            "Find files by glob pattern using fd. Respects .gitignore. Output is truncated to {DEFAULT_FIND_LIMIT} results or {}KB.",
                            DEFAULT_MAX_BYTES / 1024
                        ),
                        parameters: json!({
                            "type": "object",
                            "properties": {
                                "pattern": { "type": "string", "description": "Glob pattern, for example '*.rs' or 'src/**/*.rs'" },
                                "path": { "type": "string", "description": "Directory to search, default current directory" },
                                "limit": { "type": "number", "description": "Maximum results, default 1000" }
                            },
                            "required": ["pattern"],
                            "additionalProperties": false
                        }),
                    },
                    run: find_tool,
                },
                Tool {
                    spec: ToolSpec {
                        name: "ls".to_owned(),
                        description: format!(
                            "List directory contents alphabetically, including dotfiles. Directories have a '/' suffix. Output is truncated to {DEFAULT_LS_LIMIT} entries or {}KB.",
                            DEFAULT_MAX_BYTES / 1024
                        ),
                        parameters: json!({
                            "type": "object",
                            "properties": {
                                "path": { "type": "string", "description": "Directory to list, default current directory" },
                                "limit": { "type": "number", "description": "Maximum entries, default 500" }
                            },
                            "additionalProperties": false
                        }),
                    },
                    run: ls_tool,
                },
            ],
        }
    }

    #[cfg(test)]
    pub fn minimal() -> Self {
        Self::coding(std::env::current_dir().expect("current dir"))
    }

    pub fn specs(&self) -> Vec<ToolSpec> {
        self.tools.iter().map(|tool| tool.spec.clone()).collect()
    }

    pub fn run(&self, name: &str, arguments: &Value) -> Result<ToolOutput> {
        let Some(tool) = self.tools.iter().find(|tool| tool.spec.name == name) else {
            bail!("unknown tool: {name}");
        };
        let ctx = ToolContext {
            cwd: self.cwd.clone(),
        };
        (tool.run)(&ctx, arguments)
    }
}

fn read_tool(ctx: &ToolContext, arguments: &Value) -> Result<ToolOutput> {
    let path = string_arg(arguments, "path")?;
    let offset = optional_usize_arg(arguments, "offset")?.unwrap_or(1).max(1);
    let requested_limit = optional_usize_arg(arguments, "limit")?;
    let absolute_path = resolve_read_path(path, &ctx.cwd);
    if let Some(mime_type) = detect_image_mime_type(&absolute_path)? {
        let bytes = fs::read(&absolute_path)
            .with_context(|| format!("read {}", absolute_path.display()))?;
        let metadata = fs::metadata(&absolute_path)
            .with_context(|| format!("stat {}", absolute_path.display()))?;
        let mut content = format!("Read image file [{mime_type}]");
        if metadata.len() > IMAGE_INLINE_LIMIT_BYTES {
            content.push_str("\n[Image omitted: file exceeds inline image size limit.]");
        } else {
            content.push_str("\n[Image data recorded in tool details; current harness adapters return text tool results.]");
        }
        return Ok(ToolOutput {
            content,
            details: Some(json!({
                "image": {
                    "path": absolute_path.display().to_string(),
                    "mimeType": mime_type,
                    "bytes": metadata.len(),
                    "omitted": metadata.len() > IMAGE_INLINE_LIMIT_BYTES,
                    "data": if metadata.len() <= IMAGE_INLINE_LIMIT_BYTES {
                        json!(base64::engine::general_purpose::STANDARD.encode(bytes))
                    } else {
                        Value::Null
                    }
                }
            })),
            terminate: false,
        });
    }
    let content = fs::read_to_string(&absolute_path)
        .with_context(|| format!("read {}", absolute_path.display()))?;
    let selected = select_line_window(&content, offset, requested_limit);
    let max_lines = requested_limit.unwrap_or(DEFAULT_MAX_LINES);
    let truncated = truncate_head(&selected, max_lines, DEFAULT_MAX_BYTES);
    let mut output = truncated.content;
    let mut details = json!({ "truncation": truncated.truncation });
    if truncated.truncation.truncated {
        output.push_str(&format_truncation_notice(&truncated.truncation));
    } else {
        details = Value::Null;
    }

    Ok(ToolOutput {
        content: output,
        details: non_null(details),
        terminate: false,
    })
}

fn write_tool(ctx: &ToolContext, arguments: &Value) -> Result<ToolOutput> {
    let path = string_arg(arguments, "path")?;
    let content = string_arg(arguments, "content")?;
    let absolute_path = resolve_to_cwd(path, &ctx.cwd);
    with_file_mutation_lock(&absolute_path, || {
        if let Some(parent) = absolute_path.parent() {
            fs::create_dir_all(parent).with_context(|| format!("create {}", parent.display()))?;
        }
        fs::write(&absolute_path, content)
            .with_context(|| format!("write {}", absolute_path.display()))?;
        Ok(ToolOutput {
            content: format!("Successfully wrote {} bytes to {path}", content.len()),
            details: None,
            terminate: false,
        })
    })
}

fn edit_tool(ctx: &ToolContext, arguments: &Value) -> Result<ToolOutput> {
    let path = string_arg(arguments, "path")?;
    let edits = parse_edits(arguments)?;
    let absolute_path = resolve_to_cwd(path, &ctx.cwd);
    with_file_mutation_lock(&absolute_path, || {
        let raw_content = fs::read_to_string(&absolute_path)
            .with_context(|| format!("read {}", absolute_path.display()))?;
        let (bom, content) = strip_bom(&raw_content);
        let line_ending = detect_line_ending(content);
        let normalized = normalize_to_lf(content);
        let AppliedEdits {
            base_content,
            new_content,
            replacements,
            used_fuzzy_match,
        } = apply_edits_to_normalized_content(&normalized, &edits, path)?;
        let final_content = format!("{bom}{}", restore_line_endings(&new_content, line_ending));
        fs::write(&absolute_path, final_content)
            .with_context(|| format!("write {}", absolute_path.display()))?;

        let diff = display_diff(&base_content, &new_content, 4);
        let patch = unified_patch(path, &base_content, &new_content, 4);
        Ok(ToolOutput {
            content: format!("Successfully replaced {} block(s) in {path}.", replacements),
            details: Some(json!({
                "diff": diff.content,
                "patch": patch,
                "firstChangedLine": diff.first_changed_line,
                "usedFuzzyMatch": used_fuzzy_match
            })),
            terminate: false,
        })
    })
}

fn bash_tool(ctx: &ToolContext, arguments: &Value) -> Result<ToolOutput> {
    let command = string_arg(arguments, "command")?;
    let timeout = optional_u64_arg(arguments, "timeout")?;
    let mut shell = Command::new("/bin/sh");
    shell
        .arg("-lc")
        .arg(command)
        .current_dir(&ctx.cwd)
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());
    configure_process_group(&mut shell);
    let mut child = shell
        .spawn()
        .with_context(|| format!("spawn shell command: {command}"))?;
    let child_id = child.id();

    let started = Instant::now();
    let mut timed_out = false;
    loop {
        if let Some(_status) = child.try_wait()? {
            break;
        }
        if let Some(seconds) = timeout
            && started.elapsed() >= Duration::from_secs(seconds)
        {
            timed_out = true;
            kill_process_tree(child_id);
            let _ = child.kill();
            break;
        }
        std::thread::sleep(Duration::from_millis(25));
    }

    let output = child
        .wait_with_output()
        .with_context(|| format!("wait for shell command: {command}"))?;
    let mut combined = String::new();
    combined.push_str(&String::from_utf8_lossy(&output.stdout));
    combined.push_str(&String::from_utf8_lossy(&output.stderr));
    let truncated = truncate_tail(&combined, DEFAULT_MAX_LINES, DEFAULT_MAX_BYTES);
    let full_output_path = if truncated.truncation.truncated {
        Some(write_temp_output("harness-bash", combined.as_bytes())?)
    } else {
        None
    };

    let mut content = truncated.content;
    if timed_out {
        append_notice(
            &mut content,
            &format!("timeout: command exceeded {}s", timeout.unwrap_or_default()),
        );
    }
    if !output.status.success() {
        let code = output
            .status
            .code()
            .map_or("signal".to_owned(), |value| value.to_string());
        append_notice(&mut content, &format!("exit code: {code}"));
    }
    if let Some(path) = &full_output_path {
        append_notice(&mut content, &format!("full output: {}", path.display()));
    }
    if truncated.truncation.truncated {
        content.push_str(&format_truncation_notice(&truncated.truncation));
    }

    let details = json!({
        "exitCode": output.status.code(),
        "timedOut": timed_out,
        "truncation": if truncated.truncation.truncated { json!(truncated.truncation) } else { Value::Null },
        "fullOutputPath": full_output_path.map(|path| path.display().to_string())
    });
    Ok(ToolOutput {
        content,
        details: Some(details),
        terminate: false,
    })
}

fn grep_tool(ctx: &ToolContext, arguments: &Value) -> Result<ToolOutput> {
    let pattern = string_arg(arguments, "pattern")?;
    let search_path = resolve_to_cwd(
        optional_string_arg(arguments, "path")?.unwrap_or("."),
        &ctx.cwd,
    );
    let limit = optional_usize_arg(arguments, "limit")?
        .unwrap_or(DEFAULT_GREP_LIMIT)
        .max(1);
    let context = optional_usize_arg(arguments, "context")?.unwrap_or(0);
    let rg = ensure_executable("rg")?;
    let mut args = vec![
        "--json".to_owned(),
        "--line-number".to_owned(),
        "--color=never".to_owned(),
        "--hidden".to_owned(),
    ];
    if bool_arg(arguments, "ignoreCase") {
        args.push("--ignore-case".to_owned());
    }
    if bool_arg(arguments, "literal") {
        args.push("--fixed-strings".to_owned());
    }
    if let Some(glob) = optional_string_arg(arguments, "glob")? {
        args.push("--glob".to_owned());
        args.push(glob.to_owned());
    }
    args.push("--".to_owned());
    args.push(pattern.to_owned());
    args.push(search_path.display().to_string());
    let output = Command::new(rg).args(args).output().context("run rg")?;
    if !output.status.success() && output.status.code() != Some(1) {
        bail!(
            "{}",
            String::from_utf8_lossy(&output.stderr).trim().to_owned()
        );
    }

    let is_dir = search_path.is_dir();
    let mut matches = Vec::new();
    for line in String::from_utf8_lossy(&output.stdout).lines() {
        if matches.len() >= limit {
            break;
        }
        let Ok(event) = serde_json::from_str::<Value>(line) else {
            continue;
        };
        if event.get("type").and_then(Value::as_str) != Some("match") {
            continue;
        }
        let Some(file_path) = event.pointer("/data/path/text").and_then(Value::as_str) else {
            continue;
        };
        let Some(line_number) = event.pointer("/data/line_number").and_then(Value::as_u64) else {
            continue;
        };
        let line_text = event
            .pointer("/data/lines/text")
            .and_then(Value::as_str)
            .unwrap_or("");
        matches.push((
            PathBuf::from(file_path),
            line_number as usize,
            line_text.to_owned(),
        ));
    }

    if matches.is_empty() {
        return Ok(text_output("No matches found"));
    }

    let mut output_lines = Vec::new();
    let mut lines_truncated = false;
    for (file_path, line_number, line_text) in &matches {
        if context == 0 {
            let TruncatedLine {
                text,
                was_truncated,
            } = truncate_line(line_text.trim_end_matches('\n'), GREP_MAX_LINE_LENGTH);
            lines_truncated |= was_truncated;
            output_lines.push(format!(
                "{}:{line_number}: {text}",
                format_search_path(&search_path, file_path, is_dir)
            ));
        } else {
            output_lines.extend(format_grep_context(
                &search_path,
                file_path,
                *line_number,
                context,
                is_dir,
                &mut lines_truncated,
            ));
        }
    }
    let limit_reached = matches.len() >= limit;
    let truncated = truncate_head(&output_lines.join("\n"), usize::MAX, DEFAULT_MAX_BYTES);
    let mut content = truncated.content;
    if limit_reached {
        append_notice(
            &mut content,
            &format!(
                "{limit} matches limit reached. Use limit={} for more, or refine pattern",
                limit * 2
            ),
        );
    }
    if truncated.truncation.truncated {
        content.push_str(&format_truncation_notice(&truncated.truncation));
    }
    if lines_truncated {
        append_notice(
            &mut content,
            &format!(
                "Some lines truncated to {GREP_MAX_LINE_LENGTH} chars. Use read to see full lines"
            ),
        );
    }

    Ok(ToolOutput {
        content,
        details: Some(json!({
            "matchLimitReached": if limit_reached { json!(limit) } else { Value::Null },
            "linesTruncated": lines_truncated,
            "truncation": if truncated.truncation.truncated { json!(truncated.truncation) } else { Value::Null }
        })),
        terminate: false,
    })
}

fn find_tool(ctx: &ToolContext, arguments: &Value) -> Result<ToolOutput> {
    let pattern = string_arg(arguments, "pattern")?;
    let search_path = resolve_to_cwd(
        optional_string_arg(arguments, "path")?.unwrap_or("."),
        &ctx.cwd,
    );
    let limit = optional_usize_arg(arguments, "limit")?
        .unwrap_or(DEFAULT_FIND_LIMIT)
        .max(1);
    let fd = ensure_executable("fd")?;
    let mut args = vec![
        "--glob".to_owned(),
        "--color=never".to_owned(),
        "--hidden".to_owned(),
        "--no-require-git".to_owned(),
        "--max-results".to_owned(),
        limit.to_string(),
    ];
    let mut effective_pattern = pattern.to_owned();
    if pattern.contains('/') {
        args.push("--full-path".to_owned());
        if !pattern.starts_with('/') && !pattern.starts_with("**/") && pattern != "**" {
            effective_pattern = format!("**/{pattern}");
        }
    }
    args.push("--".to_owned());
    args.push(effective_pattern);
    args.push(search_path.display().to_string());
    let output = Command::new(fd).args(args).output().context("run fd")?;
    if !output.status.success() && output.stdout.is_empty() {
        bail!(
            "{}",
            String::from_utf8_lossy(&output.stderr).trim().to_owned()
        );
    }
    let mut results = Vec::new();
    for raw_line in String::from_utf8_lossy(&output.stdout).lines() {
        let line = raw_line.trim();
        if line.is_empty() {
            continue;
        }
        let had_trailing_slash = line.ends_with('/') || line.ends_with('\\');
        let mut relative = Path::new(line).strip_prefix(&search_path).map_or_else(
            |_| relative_path(&search_path, Path::new(line)),
            PathBuf::from,
        );
        if had_trailing_slash {
            relative.push("");
        }
        results.push(to_posix(&relative));
    }
    if results.is_empty() {
        return Ok(text_output("No files found matching pattern"));
    }
    let limit_reached = results.len() >= limit;
    let truncated = truncate_head(&results.join("\n"), usize::MAX, DEFAULT_MAX_BYTES);
    let mut content = truncated.content;
    if limit_reached {
        append_notice(
            &mut content,
            &format!(
                "{limit} results limit reached. Use limit={} for more, or refine pattern",
                limit * 2
            ),
        );
    }
    if truncated.truncation.truncated {
        content.push_str(&format_truncation_notice(&truncated.truncation));
    }

    Ok(ToolOutput {
        content,
        details: Some(json!({
            "resultLimitReached": if limit_reached { json!(limit) } else { Value::Null },
            "truncation": if truncated.truncation.truncated { json!(truncated.truncation) } else { Value::Null }
        })),
        terminate: false,
    })
}

fn ls_tool(ctx: &ToolContext, arguments: &Value) -> Result<ToolOutput> {
    let dir_path = resolve_to_cwd(
        optional_string_arg(arguments, "path")?.unwrap_or("."),
        &ctx.cwd,
    );
    let limit = optional_usize_arg(arguments, "limit")?
        .unwrap_or(DEFAULT_LS_LIMIT)
        .max(1);
    if !dir_path.exists() {
        bail!("Path not found: {}", dir_path.display());
    }
    if !dir_path.is_dir() {
        bail!("Not a directory: {}", dir_path.display());
    }
    let mut entries = fs::read_dir(&dir_path)
        .with_context(|| format!("read directory {}", dir_path.display()))?
        .filter_map(|entry| entry.ok())
        .collect::<Vec<_>>();
    entries.sort_by_key(|entry| entry.file_name().to_string_lossy().to_lowercase());

    let mut names = Vec::new();
    let mut entry_limit_reached = false;
    for entry in entries {
        if names.len() >= limit {
            entry_limit_reached = true;
            break;
        }
        let mut name = entry.file_name().to_string_lossy().to_string();
        if entry
            .file_type()
            .map(|file_type| file_type.is_dir())
            .unwrap_or(false)
        {
            name.push('/');
        }
        names.push(name);
    }
    if names.is_empty() {
        return Ok(text_output("(empty directory)"));
    }

    let truncated = truncate_head(&names.join("\n"), usize::MAX, DEFAULT_MAX_BYTES);
    let mut content = truncated.content;
    if entry_limit_reached {
        append_notice(
            &mut content,
            &format!(
                "{limit} entries limit reached. Use limit={} for more",
                limit * 2
            ),
        );
    }
    if truncated.truncation.truncated {
        content.push_str(&format_truncation_notice(&truncated.truncation));
    }
    Ok(ToolOutput {
        content,
        details: Some(json!({
            "entryLimitReached": if entry_limit_reached { json!(limit) } else { Value::Null },
            "truncation": if truncated.truncation.truncated { json!(truncated.truncation) } else { Value::Null }
        })),
        terminate: false,
    })
}

fn string_arg<'a>(arguments: &'a Value, name: &str) -> Result<&'a str> {
    arguments
        .get(name)
        .and_then(Value::as_str)
        .ok_or_else(|| anyhow!("{name} requires string argument"))
}

fn optional_string_arg<'a>(arguments: &'a Value, name: &str) -> Result<Option<&'a str>> {
    match arguments.get(name) {
        None | Some(Value::Null) => Ok(None),
        Some(value) => value
            .as_str()
            .map(Some)
            .ok_or_else(|| anyhow!("{name} must be a string")),
    }
}

fn optional_usize_arg(arguments: &Value, name: &str) -> Result<Option<usize>> {
    match arguments.get(name) {
        None | Some(Value::Null) => Ok(None),
        Some(value) => value
            .as_u64()
            .map(|value| value as usize)
            .map(Some)
            .ok_or_else(|| anyhow!("{name} must be a non-negative number")),
    }
}

fn optional_u64_arg(arguments: &Value, name: &str) -> Result<Option<u64>> {
    match arguments.get(name) {
        None | Some(Value::Null) => Ok(None),
        Some(value) => value
            .as_u64()
            .ok_or_else(|| anyhow!("{name} must be a non-negative number"))
            .map(Some),
    }
}

fn bool_arg(arguments: &Value, name: &str) -> bool {
    arguments
        .get(name)
        .and_then(Value::as_bool)
        .unwrap_or(false)
}

fn resolve_to_cwd(path: &str, cwd: &Path) -> PathBuf {
    let path = normalize_input_path(path);
    let expanded = path.strip_prefix("~/").map_or_else(
        || PathBuf::from(path),
        |rest| home_dir().map_or_else(|| PathBuf::from(path), |home| home.join(rest)),
    );
    if expanded.is_absolute() {
        expanded
    } else {
        cwd.join(expanded)
    }
}

fn resolve_read_path(path: &str, cwd: &Path) -> PathBuf {
    let resolved = resolve_to_cwd(path, cwd);
    if resolved.exists() {
        return resolved;
    }
    let am_pm = resolved
        .to_string_lossy()
        .replace(" AM.", "\u{202f}AM.")
        .replace(" PM.", "\u{202f}PM.");
    let am_pm_path = PathBuf::from(am_pm);
    if am_pm_path.exists() {
        return am_pm_path;
    }
    let nfd = resolved.to_string_lossy().replace('\'', "\u{2019}");
    let nfd_path = PathBuf::from(nfd);
    if nfd_path.exists() {
        return nfd_path;
    }
    resolved
}

fn home_dir() -> Option<PathBuf> {
    std::env::var_os("HOME").map(PathBuf::from)
}

fn normalize_input_path(path: &str) -> &str {
    path.trim()
        .strip_prefix('@')
        .unwrap_or(path.trim())
        .trim_matches('\u{feff}')
}

fn select_line_window(content: &str, offset: usize, limit: Option<usize>) -> String {
    let lines = content.lines().collect::<Vec<_>>();
    if lines.is_empty() {
        return String::new();
    }
    let start = offset.saturating_sub(1).min(lines.len());
    let end = limit.map_or(lines.len(), |limit| (start + limit).min(lines.len()));
    lines[start..end].join("\n")
}

fn truncate_head(content: &str, max_lines: usize, max_bytes: usize) -> TruncatedContent {
    truncate_lines(content, max_lines, max_bytes, false)
}

fn truncate_tail(content: &str, max_lines: usize, max_bytes: usize) -> TruncatedContent {
    truncate_lines(content, max_lines, max_bytes, true)
}

fn truncate_lines(
    content: &str,
    max_lines: usize,
    max_bytes: usize,
    tail: bool,
) -> TruncatedContent {
    let lines = split_lines_for_counting(content);
    let total_lines = lines.len();
    let total_bytes = content.len();
    if total_lines <= max_lines && total_bytes <= max_bytes {
        return TruncatedContent {
            content: content.to_owned(),
            truncation: Truncation {
                truncated: false,
                truncated_by: None,
                total_lines,
                total_bytes,
                output_lines: total_lines,
                output_bytes: total_bytes,
                last_line_partial: false,
                first_line_exceeds_limit: false,
                max_lines,
                max_bytes,
            },
        };
    }

    if !tail && lines.first().map_or(0, |line| line.len()) > max_bytes {
        return TruncatedContent {
            content: String::new(),
            truncation: Truncation {
                truncated: true,
                truncated_by: Some("bytes"),
                total_lines,
                total_bytes,
                output_lines: 0,
                output_bytes: 0,
                last_line_partial: false,
                first_line_exceeds_limit: true,
                max_lines,
                max_bytes,
            },
        };
    }

    let selected = if tail {
        collect_tail_lines(&lines, max_lines, max_bytes)
    } else {
        collect_head_lines(&lines, max_lines, max_bytes)
    };
    let content = selected.join("\n");
    let output_bytes = content.len();
    let output_lines = selected.len();
    TruncatedContent {
        content,
        truncation: Truncation {
            truncated: true,
            truncated_by: Some(if output_lines >= max_lines {
                "lines"
            } else {
                "bytes"
            }),
            total_lines,
            total_bytes,
            output_lines,
            output_bytes,
            last_line_partial: false,
            first_line_exceeds_limit: false,
            max_lines,
            max_bytes,
        },
    }
}

fn split_lines_for_counting(content: &str) -> Vec<&str> {
    if content.is_empty() {
        return Vec::new();
    }
    let mut lines = content.split('\n').collect::<Vec<_>>();
    if content.ends_with('\n') {
        lines.pop();
    }
    lines
}

fn collect_head_lines<'a>(lines: &[&'a str], max_lines: usize, max_bytes: usize) -> Vec<&'a str> {
    let mut selected = Vec::new();
    let mut bytes = 0;
    for line in lines.iter().take(max_lines) {
        let line_bytes = line.len() + usize::from(!selected.is_empty());
        if bytes + line_bytes > max_bytes {
            break;
        }
        selected.push(*line);
        bytes += line_bytes;
    }
    selected
}

fn collect_tail_lines<'a>(lines: &[&'a str], max_lines: usize, max_bytes: usize) -> Vec<&'a str> {
    let mut selected = Vec::new();
    let mut bytes = 0;
    for line in lines.iter().rev().take(max_lines) {
        let line_bytes = line.len() + usize::from(!selected.is_empty());
        if bytes + line_bytes > max_bytes {
            break;
        }
        selected.push(*line);
        bytes += line_bytes;
    }
    selected.reverse();
    selected
}

fn truncate_line(line: &str, max_chars: usize) -> TruncatedLine {
    if line.chars().count() <= max_chars {
        return TruncatedLine {
            text: line.to_owned(),
            was_truncated: false,
        };
    }
    let text = line.chars().take(max_chars).collect::<String>();
    TruncatedLine {
        text: format!("{text}..."),
        was_truncated: true,
    }
}

fn format_truncation_notice(truncation: &Truncation) -> String {
    if !truncation.truncated {
        return String::new();
    }
    if truncation.first_line_exceeds_limit {
        return format!(
            "\n\n[First line exceeds {} limit]",
            format_size(truncation.max_bytes)
        );
    }
    match truncation.truncated_by {
        Some("lines") => format!(
            "\n\n[Truncated: showing {} of {} lines ({} line limit)]",
            truncation.output_lines, truncation.total_lines, truncation.max_lines
        ),
        _ => format!(
            "\n\n[Truncated: {} lines shown ({} limit)]",
            truncation.output_lines,
            format_size(truncation.max_bytes)
        ),
    }
}

fn format_size(bytes: usize) -> String {
    if bytes < 1024 {
        format!("{bytes}B")
    } else if bytes < 1024 * 1024 {
        format!("{:.1}KB", bytes as f64 / 1024.0)
    } else {
        format!("{:.1}MB", bytes as f64 / (1024.0 * 1024.0))
    }
}

#[derive(Debug)]
struct Edit {
    old_text: String,
    new_text: String,
}

#[derive(Debug)]
struct AppliedEdits {
    base_content: String,
    new_content: String,
    replacements: usize,
    used_fuzzy_match: bool,
}

#[derive(Debug)]
struct MatchedEdit {
    index: usize,
    start: usize,
    end: usize,
    new_text: String,
}

struct DisplayDiff {
    content: String,
    first_changed_line: Option<usize>,
}

fn parse_edits(arguments: &Value) -> Result<Vec<Edit>> {
    if let (Some(old_text), Some(new_text)) = (
        arguments.get("oldText").and_then(Value::as_str),
        arguments.get("newText").and_then(Value::as_str),
    ) {
        let mut edits = parse_edits_value(arguments.get("edits"))?;
        edits.push(Edit {
            old_text: old_text.to_owned(),
            new_text: new_text.to_owned(),
        });
        return Ok(edits);
    }
    parse_edits_value(arguments.get("edits"))
}

fn parse_edits_value(value: Option<&Value>) -> Result<Vec<Edit>> {
    let raw_edits = match value {
        Some(Value::String(text)) => serde_json::from_str::<Value>(text)
            .ok()
            .and_then(|value| value.as_array().cloned())
            .ok_or_else(|| anyhow!("edits string must contain a JSON array"))?,
        Some(Value::Array(raw_edits)) => raw_edits.clone(),
        _ => bail!("edits must be a non-empty array"),
    };
    if raw_edits.is_empty() {
        bail!("edits must be a non-empty array");
    }
    raw_edits
        .iter()
        .map(|edit| {
            Ok(Edit {
                old_text: string_arg(edit, "oldText")?.to_owned(),
                new_text: string_arg(edit, "newText")?.to_owned(),
            })
        })
        .collect()
}

fn apply_edits_to_normalized_content(
    normalized_content: &str,
    edits: &[Edit],
    path: &str,
) -> Result<AppliedEdits> {
    let normalized_edits = edits
        .iter()
        .map(|edit| Edit {
            old_text: normalize_to_lf(&edit.old_text),
            new_text: normalize_to_lf(&edit.new_text),
        })
        .collect::<Vec<_>>();
    for (index, edit) in normalized_edits.iter().enumerate() {
        if edit.old_text.is_empty() {
            bail!(
                "{}",
                empty_old_text_error(path, index, normalized_edits.len())
            );
        }
    }

    let exact_base = normalized_content.to_owned();
    let fuzzy_base = normalize_for_fuzzy_match(normalized_content);
    let used_fuzzy_match = normalized_edits.iter().any(|edit| {
        !exact_base.contains(&edit.old_text)
            && fuzzy_base.contains(&normalize_for_fuzzy_match(&edit.old_text))
    });
    let base_content = if used_fuzzy_match {
        fuzzy_base
    } else {
        exact_base
    };

    let mut matches = Vec::new();
    for (index, edit) in normalized_edits.iter().enumerate() {
        let old_text = if used_fuzzy_match {
            normalize_for_fuzzy_match(&edit.old_text)
        } else {
            edit.old_text.clone()
        };
        let occurrences = count_occurrences(&base_content, &old_text);
        if occurrences == 0 {
            bail!("{}", not_found_error(path, index, normalized_edits.len()));
        }
        if occurrences > 1 {
            bail!(
                "{}",
                duplicate_error(path, index, normalized_edits.len(), occurrences)
            );
        }
        let start = base_content.find(&old_text).expect("occurrence checked");
        matches.push(MatchedEdit {
            index,
            start,
            end: start + old_text.len(),
            new_text: edit.new_text.clone(),
        });
    }
    matches.sort_by_key(|replacement| replacement.start);
    for pair in matches.windows(2) {
        if pair[0].end > pair[1].start {
            bail!(
                "edits[{}] and edits[{}] overlap in {path}. Merge them into one edit or target disjoint regions.",
                pair[0].index,
                pair[1].index
            );
        }
    }
    let mut new_content = base_content.clone();
    for matched in matches.iter().rev() {
        new_content.replace_range(matched.start..matched.end, &matched.new_text);
    }
    if base_content == new_content {
        bail!("{}", no_change_error(path, normalized_edits.len()));
    }
    Ok(AppliedEdits {
        base_content,
        new_content,
        replacements: matches.len(),
        used_fuzzy_match,
    })
}

fn strip_bom(content: &str) -> (&str, &str) {
    content
        .strip_prefix('\u{feff}')
        .map_or(("", content), |rest| ("\u{feff}", rest))
}

fn detect_line_ending(content: &str) -> &'static str {
    if content.contains("\r\n") {
        "\r\n"
    } else if content.contains('\r') {
        "\r"
    } else {
        "\n"
    }
}

fn normalize_to_lf(content: &str) -> String {
    content.replace("\r\n", "\n").replace('\r', "\n")
}

fn restore_line_endings(content: &str, line_ending: &str) -> String {
    if line_ending == "\n" {
        content.to_owned()
    } else {
        content.replace('\n', line_ending)
    }
}

fn display_diff(old: &str, new: &str, context_lines: usize) -> DisplayDiff {
    let old_lines = split_lines_for_counting(old);
    let new_lines = split_lines_for_counting(new);
    let first_changed = first_changed_line(old, new);
    let Some(first_changed_line) = first_changed else {
        return DisplayDiff {
            content: String::new(),
            first_changed_line: None,
        };
    };
    let last_changed = last_changed_line(&old_lines, &new_lines);
    let start = first_changed_line.saturating_sub(context_lines + 1);
    let end = (last_changed + context_lines).min(old_lines.len().max(new_lines.len()));
    let width = old_lines.len().max(new_lines.len()).to_string().len();
    let mut lines = Vec::new();
    if start > 0 {
        lines.push(format!(" {} ...", " ".repeat(width)));
    }
    for index in start..end {
        match (old_lines.get(index), new_lines.get(index)) {
            (Some(old), Some(new)) if old == new => {
                lines.push(format!(" {:>width$} {old}", index + 1, width = width));
            }
            (Some(old), Some(new)) => {
                lines.push(format!("-{:>width$} {old}", index + 1, width = width));
                lines.push(format!("+{:>width$} {new}", index + 1, width = width));
            }
            (Some(old), None) => {
                lines.push(format!("-{:>width$} {old}", index + 1, width = width));
            }
            (None, Some(new)) => {
                lines.push(format!("+{:>width$} {new}", index + 1, width = width));
            }
            (None, None) => {}
        }
    }
    if end < old_lines.len().max(new_lines.len()) {
        lines.push(format!(" {} ...", " ".repeat(width)));
    }
    DisplayDiff {
        content: lines.join("\n"),
        first_changed_line: first_changed,
    }
}

fn unified_patch(path: &str, old: &str, new: &str, context_lines: usize) -> String {
    let old_lines = split_lines_for_counting(old);
    let new_lines = split_lines_for_counting(new);
    let Some(first_changed) = first_changed_line(old, new) else {
        return format!("--- {path}\n+++ {path}\n");
    };
    let last_changed = last_changed_line(&old_lines, &new_lines);
    let start = first_changed.saturating_sub(context_lines + 1);
    let end = (last_changed + context_lines).min(old_lines.len().max(new_lines.len()));
    let old_count = end
        .saturating_sub(start)
        .min(old_lines.len().saturating_sub(start));
    let new_count = end
        .saturating_sub(start)
        .min(new_lines.len().saturating_sub(start));
    let mut lines = vec![
        format!("--- {path}"),
        format!("+++ {path}"),
        format!(
            "@@ -{},{} +{},{} @@",
            start + 1,
            old_count,
            start + 1,
            new_count
        ),
    ];
    for index in start..end {
        match (old_lines.get(index), new_lines.get(index)) {
            (Some(old), Some(new)) if old == new => lines.push(format!(" {old}")),
            (Some(old), Some(new)) => {
                lines.push(format!("-{old}"));
                lines.push(format!("+{new}"));
            }
            (Some(old), None) => lines.push(format!("-{old}")),
            (None, Some(new)) => lines.push(format!("+{new}")),
            (None, None) => {}
        }
    }
    lines.join("\n")
}

fn first_changed_line(old: &str, new: &str) -> Option<usize> {
    let old_lines = split_lines_for_counting(old);
    let new_lines = split_lines_for_counting(new);
    old_lines
        .iter()
        .zip(new_lines.iter())
        .position(|(left, right)| left != right)
        .map(|index| index + 1)
        .or_else(|| {
            if old_lines.len() != new_lines.len() {
                Some(old_lines.len().min(new_lines.len()) + 1)
            } else {
                None
            }
        })
}

fn last_changed_line(old_lines: &[&str], new_lines: &[&str]) -> usize {
    let mut old_index = old_lines.len();
    let mut new_index = new_lines.len();
    while old_index > 0 && new_index > 0 && old_lines[old_index - 1] == new_lines[new_index - 1] {
        old_index -= 1;
        new_index -= 1;
    }
    old_index.max(new_index)
}

fn normalize_for_fuzzy_match(text: &str) -> String {
    text.split('\n')
        .map(str::trim_end)
        .collect::<Vec<_>>()
        .join("\n")
        .chars()
        .map(normalize_fuzzy_char)
        .collect()
}

fn normalize_fuzzy_char(ch: char) -> char {
    match ch {
        '\u{2018}' | '\u{2019}' | '\u{201a}' | '\u{201b}' => '\'',
        '\u{201c}' | '\u{201d}' | '\u{201e}' | '\u{201f}' => '"',
        '\u{2010}' | '\u{2011}' | '\u{2012}' | '\u{2013}' | '\u{2014}' | '\u{2015}'
        | '\u{2212}' => '-',
        '\u{00a0}' | '\u{2002}'..='\u{200a}' | '\u{202f}' | '\u{205f}' | '\u{3000}' => ' ',
        _ => ch,
    }
}

fn count_occurrences(content: &str, needle: &str) -> usize {
    if needle.is_empty() {
        return 0;
    }
    content.match_indices(needle).count()
}

fn not_found_error(path: &str, index: usize, total: usize) -> String {
    if total == 1 {
        format!(
            "Could not find the exact text in {path}. The old text must match exactly including all whitespace and newlines."
        )
    } else {
        format!(
            "Could not find edits[{index}] in {path}. The oldText must match exactly including all whitespace and newlines."
        )
    }
}

fn duplicate_error(path: &str, index: usize, total: usize, occurrences: usize) -> String {
    if total == 1 {
        format!(
            "Found {occurrences} occurrences of the text in {path}. The text must be unique. Please provide more context to make it unique."
        )
    } else {
        format!(
            "Found {occurrences} occurrences of edits[{index}] in {path}. Each oldText must be unique. Please provide more context to make it unique."
        )
    }
}

fn empty_old_text_error(path: &str, index: usize, total: usize) -> String {
    if total == 1 {
        format!("oldText must not be empty in {path}.")
    } else {
        format!("edits[{index}].oldText must not be empty in {path}.")
    }
}

fn no_change_error(path: &str, total: usize) -> String {
    if total == 1 {
        format!(
            "No changes made to {path}. The replacement produced identical content. This might indicate an issue with special characters or the text not existing as expected."
        )
    } else {
        format!("No changes made to {path}. The replacements produced identical content.")
    }
}

fn ensure_executable(name: &str) -> Result<String> {
    if let Some(path) = find_executable(name) {
        return Ok(path);
    }
    if offline_mode() {
        bail!("{name} is not available and offline mode is enabled");
    }
    if std::env::consts::OS == "android" {
        let package = match name {
            "rg" => "ripgrep",
            "fd" => "fd",
            _ => name,
        };
        bail!("{name} is not available. On Android/Termux, install it with: pkg install {package}");
    }
    provision_tool(name).with_context(|| format!("provision {name}"))
}

fn find_executable(name: &str) -> Option<String> {
    if let Some(candidate) = cached_tool_path(name)
        && candidate.is_file()
    {
        return Some(candidate.display().to_string());
    }

    let env_key = format!("HARNESS_{}_PATH", name.to_ascii_uppercase());
    if let Some(path) = std::env::var_os(&env_key) {
        let candidate = PathBuf::from(path);
        if candidate.is_file() {
            return Some(candidate.display().to_string());
        }
    }
    if name == "fd"
        && let Some(path) = std::env::var_os("HARNESS_FDFIND_PATH")
    {
        let candidate = PathBuf::from(path);
        if candidate.is_file() {
            return Some(candidate.display().to_string());
        }
    }

    let aliases = if name == "fd" {
        vec!["fd", "fdfind"]
    } else {
        vec![name]
    };
    for alias in &aliases {
        if command_exists(alias) {
            return Some((*alias).to_owned());
        }
    }
    None
}

fn command_exists(command: &str) -> bool {
    Command::new(command)
        .arg("--version")
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .is_ok()
}

fn provision_tool(name: &str) -> Result<String> {
    let config = ToolDownload::for_name(name)?;
    let cache_dir = tools_cache_dir();
    fs::create_dir_all(&cache_dir).with_context(|| format!("create {}", cache_dir.display()))?;
    let binary_path = cached_tool_path(name).expect("supported tool has cache path");
    if binary_path.is_file() {
        return Ok(binary_path.display().to_string());
    }

    let mut version = latest_github_release(config.repo, config.tag_prefix)?;
    if config.binary_name == "fd"
        && std::env::consts::OS == "macos"
        && std::env::consts::ARCH == "x86_64"
    {
        version = "10.3.0".to_owned();
    }
    let asset_name = config.asset_name(&version)?;
    let archive_path = cache_dir.join(&asset_name);
    let extract_dir = cache_dir.join(format!(
        "extract-{}-{}-{}",
        config.binary_name,
        std::process::id(),
        current_millis()
    ));
    fs::create_dir_all(&extract_dir)
        .with_context(|| format!("create {}", extract_dir.display()))?;
    let url = format!(
        "https://github.com/{}/releases/download/{}{}/{}",
        config.repo, config.tag_prefix, version, asset_name
    );

    let result = (|| -> Result<String> {
        download_file(&url, &archive_path)?;
        extract_archive(&archive_path, &extract_dir, &asset_name)?;
        let extracted_binary = find_binary_recursively(&extract_dir, config.binary_file_name())
            .ok_or_else(|| anyhow!("binary {} not found in {}", config.binary_name, asset_name))?;
        fs::rename(&extracted_binary, &binary_path).with_context(|| {
            format!(
                "install {} to {}",
                extracted_binary.display(),
                binary_path.display()
            )
        })?;
        mark_executable(&binary_path)?;
        Ok(binary_path.display().to_string())
    })();

    let _ = fs::remove_file(&archive_path);
    let _ = fs::remove_dir_all(&extract_dir);
    result
}

struct ToolDownload {
    repo: &'static str,
    binary_name: &'static str,
    tag_prefix: &'static str,
}

impl ToolDownload {
    fn for_name(name: &str) -> Result<Self> {
        match name {
            "rg" => Ok(Self {
                repo: "BurntSushi/ripgrep",
                binary_name: "rg",
                tag_prefix: "",
            }),
            "fd" => Ok(Self {
                repo: "sharkdp/fd",
                binary_name: "fd",
                tag_prefix: "v",
            }),
            other => bail!("automatic provisioning is not configured for {other}"),
        }
    }

    fn binary_file_name(&self) -> String {
        if cfg!(windows) {
            format!("{}.exe", self.binary_name)
        } else {
            self.binary_name.to_owned()
        }
    }

    fn asset_name(&self, version: &str) -> Result<String> {
        self.asset_name_for(version, std::env::consts::OS, std::env::consts::ARCH)
    }

    fn asset_name_for(&self, version: &str, os: &str, arch: &str) -> Result<String> {
        let cpu = match arch {
            "aarch64" => "aarch64",
            "x86_64" => "x86_64",
            other => bail!("unsupported architecture for {}: {other}", self.binary_name),
        };
        match (self.binary_name, os, cpu) {
            ("fd", "macos", "aarch64") => Ok(format!("fd-v{version}-aarch64-apple-darwin.tar.gz")),
            ("fd", "macos", "x86_64") => Ok(format!("fd-v{version}-x86_64-apple-darwin.tar.gz")),
            ("fd", "linux", "aarch64") => {
                Ok(format!("fd-v{version}-aarch64-unknown-linux-gnu.tar.gz"))
            }
            ("fd", "linux", "x86_64") => {
                Ok(format!("fd-v{version}-x86_64-unknown-linux-gnu.tar.gz"))
            }
            ("fd", "windows", "aarch64") => {
                Ok(format!("fd-v{version}-aarch64-pc-windows-msvc.zip"))
            }
            ("fd", "windows", "x86_64") => Ok(format!("fd-v{version}-x86_64-pc-windows-msvc.zip")),
            ("rg", "macos", "aarch64") => {
                Ok(format!("ripgrep-{version}-aarch64-apple-darwin.tar.gz"))
            }
            ("rg", "macos", "x86_64") => {
                Ok(format!("ripgrep-{version}-x86_64-apple-darwin.tar.gz"))
            }
            ("rg", "linux", "aarch64") => Ok(format!(
                "ripgrep-{version}-aarch64-unknown-linux-gnu.tar.gz"
            )),
            ("rg", "linux", "x86_64") => Ok(format!(
                "ripgrep-{version}-x86_64-unknown-linux-musl.tar.gz"
            )),
            ("rg", "windows", "aarch64") => {
                Ok(format!("ripgrep-{version}-aarch64-pc-windows-msvc.zip"))
            }
            ("rg", "windows", "x86_64") => {
                Ok(format!("ripgrep-{version}-x86_64-pc-windows-msvc.zip"))
            }
            _ => bail!("unsupported platform for {}: {os}/{arch}", self.binary_name),
        }
    }
}

fn latest_github_release(repo: &str, tag_prefix: &str) -> Result<String> {
    let url = format!("https://api.github.com/repos/{repo}/releases/latest");
    let client = reqwest::blocking::Client::builder()
        .timeout(Duration::from_secs(10))
        .user_agent("harness-agent")
        .build()?;
    let value = client
        .get(url)
        .send()
        .context("request GitHub release metadata")?
        .error_for_status()
        .context("GitHub release metadata status")?
        .json::<Value>()
        .context("parse GitHub release metadata")?;
    let tag = value
        .get("tag_name")
        .and_then(Value::as_str)
        .ok_or_else(|| anyhow!("GitHub release metadata missing tag_name"))?;
    Ok(tag.strip_prefix(tag_prefix).unwrap_or(tag).to_owned())
}

fn download_file(url: &str, destination: &Path) -> Result<()> {
    let client = reqwest::blocking::Client::builder()
        .timeout(Duration::from_secs(120))
        .user_agent("harness-agent")
        .build()?;
    let mut response = client
        .get(url)
        .send()
        .with_context(|| format!("download {url}"))?
        .error_for_status()
        .with_context(|| format!("download status {url}"))?;
    let mut file = fs::File::create(destination)
        .with_context(|| format!("create {}", destination.display()))?;
    response
        .copy_to(&mut file)
        .with_context(|| format!("write {}", destination.display()))?;
    Ok(())
}

fn extract_archive(archive_path: &Path, extract_dir: &Path, asset_name: &str) -> Result<()> {
    if asset_name.ends_with(".tar.gz") {
        run_extraction(
            "tar",
            &["xzf", path_str(archive_path)?, "-C", path_str(extract_dir)?],
        )
    } else if asset_name.ends_with(".zip") {
        run_extraction(
            "unzip",
            &["-q", path_str(archive_path)?, "-d", path_str(extract_dir)?],
        )
        .or_else(|_| {
            #[cfg(windows)]
            if let Some(system_tar) = windows_system_tar() {
                if run_extraction(
                    &system_tar,
                    &["xf", path_str(archive_path)?, "-C", path_str(extract_dir)?],
                )
                .is_ok()
                {
                    return Ok(());
                }
            }
            run_extraction(
                "tar",
                &["xf", path_str(archive_path)?, "-C", path_str(extract_dir)?],
            )
            .or_else(|_| {
                #[cfg(windows)]
                {
                    let script =
                        "& { param($archive, $destination) $ErrorActionPreference = 'Stop'; Expand-Archive -LiteralPath $archive -DestinationPath $destination -Force }";
                    return run_extraction(
                        "powershell.exe",
                        &[
                            "-NoLogo",
                            "-NoProfile",
                            "-NonInteractive",
                            "-ExecutionPolicy",
                            "Bypass",
                            "-Command",
                            script,
                            path_str(archive_path)?,
                            path_str(extract_dir)?,
                        ],
                    );
                }
                #[cfg(not(windows))]
                bail!("failed to extract zip archive with unzip or tar")
            })
        })
    } else {
        bail!("unsupported archive format: {asset_name}")
    }
}

#[cfg(windows)]
fn windows_system_tar() -> Option<String> {
    std::env::var_os("SystemRoot")
        .or_else(|| std::env::var_os("WINDIR"))
        .map(PathBuf::from)
        .map(|root| root.join("System32").join("tar.exe"))
        .filter(|path| path.is_file())
        .map(|path| path.display().to_string())
}

fn run_extraction(command: &str, args: &[&str]) -> Result<()> {
    let output = Command::new(command)
        .args(args)
        .output()
        .with_context(|| format!("run {command}"))?;
    if output.status.success() {
        return Ok(());
    }
    let stderr = String::from_utf8_lossy(&output.stderr).trim().to_owned();
    bail!(
        "{}",
        if stderr.is_empty() {
            format!("{command} exited with {}", output.status)
        } else {
            stderr
        }
    )
}

fn path_str(path: &Path) -> Result<&str> {
    path.to_str()
        .ok_or_else(|| anyhow!("path is not valid UTF-8: {}", path.display()))
}

fn find_binary_recursively(root: &Path, binary_file_name: String) -> Option<PathBuf> {
    let mut stack = vec![root.to_path_buf()];
    while let Some(dir) = stack.pop() {
        let entries = fs::read_dir(dir).ok()?;
        for entry in entries.flatten() {
            let path = entry.path();
            if path.is_file()
                && path
                    .file_name()
                    .is_some_and(|name| name == binary_file_name.as_str())
            {
                return Some(path);
            }
            if path.is_dir() {
                stack.push(path);
            }
        }
    }
    None
}

fn cached_tool_path(name: &str) -> Option<PathBuf> {
    match name {
        "rg" => Some(tools_cache_dir().join(if cfg!(windows) { "rg.exe" } else { "rg" })),
        "fd" => Some(tools_cache_dir().join(if cfg!(windows) { "fd.exe" } else { "fd" })),
        _ => None,
    }
}

fn tools_cache_dir() -> PathBuf {
    std::env::var_os("HARNESS_TOOLS_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|| harness_agent_dir().join("bin"))
}

fn harness_agent_dir() -> PathBuf {
    std::env::var_os("HARNESS_CODING_AGENT_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|| {
            home_dir()
                .map(|home| home.join(".harness").join("agent"))
                .unwrap_or_else(|| PathBuf::from("harness/.state/agent"))
        })
}

fn offline_mode() -> bool {
    let value = std::env::var("HARNESS_OFFLINE")
        .or_else(|_| std::env::var("PI_OFFLINE"))
        .unwrap_or_default();
    matches!(value.to_ascii_lowercase().as_str(), "1" | "true" | "yes")
}

fn current_millis() -> u128 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis()
}

#[cfg(unix)]
fn mark_executable(path: &Path) -> Result<()> {
    use std::os::unix::fs::PermissionsExt;
    let mut permissions = fs::metadata(path)?.permissions();
    permissions.set_mode(0o755);
    fs::set_permissions(path, permissions)?;
    Ok(())
}

#[cfg(not(unix))]
fn mark_executable(_path: &Path) -> Result<()> {
    Ok(())
}

fn detect_image_mime_type(path: &Path) -> Result<Option<&'static str>> {
    let bytes = fs::read(path).with_context(|| format!("read {}", path.display()))?;
    if bytes.starts_with(b"\x89PNG\r\n\x1a\n") {
        return Ok(Some("image/png"));
    }
    if bytes.starts_with(&[0xff, 0xd8, 0xff]) {
        return Ok(Some("image/jpeg"));
    }
    if bytes.starts_with(b"GIF87a") || bytes.starts_with(b"GIF89a") {
        return Ok(Some("image/gif"));
    }
    if bytes.len() >= 12 && bytes.starts_with(b"RIFF") && bytes[8..12] == *b"WEBP" {
        return Ok(Some("image/webp"));
    }
    Ok(None)
}

fn with_file_mutation_lock<T>(path: &Path, operation: impl FnOnce() -> Result<T>) -> Result<T> {
    static LOCKS: OnceLock<Mutex<HashMap<PathBuf, Arc<Mutex<()>>>>> = OnceLock::new();
    let stable_path = path.canonicalize().unwrap_or_else(|_| path.to_path_buf());
    let lock = {
        let locks = LOCKS.get_or_init(|| Mutex::new(HashMap::new()));
        let mut locks = locks.lock().expect("mutation lock registry poisoned");
        locks
            .entry(stable_path)
            .or_insert_with(|| Arc::new(Mutex::new(())))
            .clone()
    };
    let _guard = lock.lock().expect("file mutation lock poisoned");
    operation()
}

#[cfg(unix)]
fn configure_process_group(command: &mut Command) {
    use std::os::unix::process::CommandExt;
    unsafe {
        command.pre_exec(|| {
            unsafe extern "C" {
                fn setpgid(pid: i32, pgid: i32) -> i32;
            }
            if setpgid(0, 0) == 0 {
                Ok(())
            } else {
                Err(std::io::Error::last_os_error())
            }
        });
    }
}

#[cfg(not(unix))]
fn configure_process_group(_command: &mut Command) {}

#[cfg(unix)]
fn kill_process_tree(process_id: u32) {
    unsafe extern "C" {
        fn kill(pid: i32, sig: i32) -> i32;
    }
    const SIGTERM: i32 = 15;
    const SIGKILL: i32 = 9;
    let process_group = -(process_id as i32);
    unsafe {
        kill(process_group, SIGTERM);
    }
    std::thread::sleep(Duration::from_millis(100));
    unsafe {
        kill(process_group, SIGKILL);
    }
}

#[cfg(not(unix))]
fn kill_process_tree(_process_id: u32) {}

fn format_search_path(root: &Path, file_path: &Path, is_dir: bool) -> String {
    if is_dir {
        return file_path
            .strip_prefix(root)
            .map_or_else(|_| file_path.to_path_buf(), PathBuf::from)
            .display()
            .to_string()
            .replace('\\', "/");
    }
    file_path.file_name().map_or_else(
        || file_path.display().to_string(),
        |name| name.to_string_lossy().to_string(),
    )
}

fn format_grep_context(
    root: &Path,
    file_path: &Path,
    line_number: usize,
    context: usize,
    is_dir: bool,
    lines_truncated: &mut bool,
) -> Vec<String> {
    let Ok(content) = fs::read_to_string(file_path) else {
        return vec![format!(
            "{}:{line_number}: (unable to read file)",
            format_search_path(root, file_path, is_dir)
        )];
    };
    let lines = normalize_to_lf(&content);
    let lines = lines.split('\n').collect::<Vec<_>>();
    let start = line_number.saturating_sub(context).max(1);
    let end = (line_number + context).min(lines.len());
    let display_path = format_search_path(root, file_path, is_dir);
    (start..=end)
        .map(|current| {
            let TruncatedLine {
                text,
                was_truncated,
            } = truncate_line(lines[current - 1], GREP_MAX_LINE_LENGTH);
            *lines_truncated |= was_truncated;
            if current == line_number {
                format!("{display_path}:{current}: {text}")
            } else {
                format!("{display_path}-{current}- {text}")
            }
        })
        .collect()
}

fn relative_path(root: &Path, path: &Path) -> PathBuf {
    path.strip_prefix(root)
        .map_or_else(|_| path.to_path_buf(), PathBuf::from)
}

fn to_posix(path: &Path) -> String {
    path.display().to_string().replace('\\', "/")
}

fn write_temp_output(prefix: &str, bytes: &[u8]) -> Result<PathBuf> {
    let timestamp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis();
    let path =
        std::env::temp_dir().join(format!("{prefix}-{}-{timestamp}.log", std::process::id()));
    let mut file = fs::File::create(&path).with_context(|| format!("create {}", path.display()))?;
    file.write_all(bytes)?;
    Ok(path)
}

fn append_notice(content: &mut String, notice: &str) {
    if !content.is_empty() {
        content.push_str("\n\n");
    }
    content.push('[');
    content.push_str(notice);
    content.push(']');
}

fn text_output(content: &str) -> ToolOutput {
    ToolOutput {
        content: content.to_owned(),
        details: None,
        terminate: false,
    }
}

fn non_null(value: Value) -> Option<Value> {
    if value.is_null() { None } else { Some(value) }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn exposes_pi_coding_tool_names() {
        let tools = ToolRegistry::minimal();
        let names = tools
            .specs()
            .into_iter()
            .map(|spec| spec.name)
            .collect::<Vec<_>>();

        assert_eq!(
            names,
            ["read", "bash", "edit", "write", "grep", "find", "ls"]
        );
    }

    #[test]
    fn writes_reads_and_edits_files_relative_to_cwd() {
        let dir = temp_dir("tools-edit");
        let tools = ToolRegistry::coding(dir.clone());

        tools
            .run(
                "write",
                &json!({ "path": "nested/file.txt", "content": "one\ntwo\n" }),
            )
            .unwrap();
        let read = tools
            .run(
                "read",
                &json!({ "path": "nested/file.txt", "offset": 2, "limit": 1 }),
            )
            .unwrap();
        let edited = tools
            .run(
                "edit",
                &json!({
                    "path": "nested/file.txt",
                    "edits": [{ "oldText": "two", "newText": "three" }]
                }),
            )
            .unwrap();

        assert_eq!(read.content, "two");
        assert_eq!(
            fs::read_to_string(dir.join("nested/file.txt")).unwrap(),
            "one\nthree\n"
        );
        assert!(edited.details.unwrap().get("patch").is_some());
    }

    #[test]
    fn edit_rejects_ambiguous_matches() {
        let dir = temp_dir("tools-ambiguous");
        fs::write(dir.join("file.txt"), "same\nsame\n").unwrap();
        let tools = ToolRegistry::coding(dir);

        let error = tools
            .run(
                "edit",
                &json!({
                    "path": "file.txt",
                    "edits": [{ "oldText": "same", "newText": "changed" }]
                }),
            )
            .unwrap_err()
            .to_string();

        assert!(error.contains("must be unique"));
    }

    #[test]
    fn edit_accepts_legacy_and_json_string_inputs() {
        let dir = temp_dir("tools-edit-compat");
        fs::write(dir.join("file.txt"), "one\ntwo\nthree\n").unwrap();
        let tools = ToolRegistry::coding(dir.clone());

        tools
            .run(
                "edit",
                &json!({
                    "path": "file.txt",
                    "oldText": "one",
                    "newText": "ONE",
                    "edits": "[{\"oldText\":\"three\",\"newText\":\"THREE\"}]"
                }),
            )
            .unwrap();

        assert_eq!(
            fs::read_to_string(dir.join("file.txt")).unwrap(),
            "ONE\ntwo\nTHREE\n"
        );
    }

    #[test]
    fn edit_uses_fuzzy_matching_like_pi() {
        let dir = temp_dir("tools-edit-fuzzy");
        fs::write(dir.join("file.txt"), "quote: \u{201c}hello\u{201d}\n").unwrap();
        let tools = ToolRegistry::coding(dir.clone());

        let output = tools
            .run(
                "edit",
                &json!({
                    "path": "file.txt",
                    "edits": [{ "oldText": "quote: \"hello\"", "newText": "quote: \"bye\"" }]
                }),
            )
            .unwrap();

        assert_eq!(
            fs::read_to_string(dir.join("file.txt")).unwrap(),
            "quote: \"bye\"\n"
        );
        assert_eq!(output.details.unwrap()["usedFuzzyMatch"], true);
    }

    #[test]
    fn read_detects_supported_images() {
        let dir = temp_dir("tools-read-image");
        fs::write(dir.join("image.png"), b"\x89PNG\r\n\x1a\nrest").unwrap();
        let tools = ToolRegistry::coding(dir);

        let output = tools.run("read", &json!({ "path": "image.png" })).unwrap();

        assert!(output.content.contains("Read image file [image/png]"));
        let details = output.details.unwrap();
        assert_eq!(details["image"]["mimeType"], "image/png");
        assert!(
            details["image"]["data"]
                .as_str()
                .unwrap()
                .starts_with("iVBOR")
        );
    }

    #[test]
    fn resolves_at_prefixed_paths() {
        let dir = temp_dir("tools-at-path");
        fs::write(dir.join("file.txt"), "hello").unwrap();
        let tools = ToolRegistry::coding(dir);

        let output = tools.run("read", &json!({ "path": "@file.txt" })).unwrap();

        assert_eq!(output.content, "hello");
    }

    #[test]
    fn bash_timeout_records_timeout_details() {
        let dir = temp_dir("tools-bash-timeout");
        let tools = ToolRegistry::coding(dir);

        let output = tools
            .run("bash", &json!({ "command": "sleep 2", "timeout": 1 }))
            .unwrap();

        assert!(output.content.contains("timeout"));
        assert_eq!(output.details.unwrap()["timedOut"], true);
    }

    #[test]
    fn ls_marks_directories_and_limits_entries() {
        let dir = temp_dir("tools-ls");
        fs::create_dir(dir.join("a_dir")).unwrap();
        fs::write(dir.join("b.txt"), "").unwrap();
        let tools = ToolRegistry::coding(dir);

        let output = tools.run("ls", &json!({ "limit": 1 })).unwrap();

        assert!(output.content.contains("a_dir/"));
        assert!(output.content.contains("entries limit reached"));
    }

    #[test]
    fn truncates_read_output() {
        let dir = temp_dir("tools-read-truncate");
        fs::write(dir.join("file.txt"), "one\ntwo\nthree\n").unwrap();
        let tools = ToolRegistry::coding(dir);

        let output = tools
            .run("read", &json!({ "path": "file.txt", "limit": 2 }))
            .unwrap();

        assert_eq!(output.content, "one\ntwo");
    }

    #[test]
    fn grep_searches_with_rg_when_available() {
        let _guard = test_env_lock();
        if find_executable("rg").is_none() {
            return;
        }
        let dir = temp_dir("tools-grep");
        fs::write(dir.join("file.txt"), "needle\nother\n").unwrap();
        let tools = ToolRegistry::coding(dir);

        let output = tools
            .run("grep", &json!({ "pattern": "needle", "limit": 5 }))
            .unwrap();

        assert!(output.content.contains("file.txt:1: needle"));
    }

    #[test]
    fn find_searches_with_fd_when_available() {
        let _guard = test_env_lock();
        if find_executable("fd").is_none() {
            return;
        }
        let dir = temp_dir("tools-find");
        fs::create_dir(dir.join("src")).unwrap();
        fs::write(dir.join("src/main.rs"), "").unwrap();
        let tools = ToolRegistry::coding(dir);

        let output = tools
            .run("find", &json!({ "pattern": "src/**/*.rs", "limit": 5 }))
            .unwrap();

        assert!(output.content.contains("src/main.rs"));
    }

    #[test]
    fn finds_cached_tool_before_env_and_path_lookup() {
        let _guard = test_env_lock();
        let dir = temp_dir("tools-cache");
        let env_dir = temp_dir("tools-env");
        let previous_tools_dir = std::env::var_os("HARNESS_TOOLS_DIR");
        let previous_fd_path = std::env::var_os("HARNESS_FD_PATH");
        let tool_name = if cfg!(windows) { "fd.exe" } else { "fd" };
        let tool_path = dir.join(tool_name);
        let env_path = env_dir.join(tool_name);
        fs::write(&tool_path, "#!/bin/sh\n").unwrap();
        fs::write(&env_path, "#!/bin/sh\n").unwrap();
        unsafe {
            std::env::set_var("HARNESS_TOOLS_DIR", &dir);
            std::env::set_var("HARNESS_FD_PATH", &env_path);
        }

        let found = find_executable("fd").unwrap();

        restore_env_var("HARNESS_TOOLS_DIR", previous_tools_dir);
        restore_env_var("HARNESS_FD_PATH", previous_fd_path);
        assert_eq!(found, tool_path.display().to_string());
    }

    #[test]
    fn tools_cache_dir_uses_product_agent_bin_like_pi() {
        let _guard = test_env_lock();
        let agent_dir = temp_dir("tools-agent-dir");
        let previous_tools_dir = std::env::var_os("HARNESS_TOOLS_DIR");
        let previous_agent_dir = std::env::var_os("HARNESS_CODING_AGENT_DIR");
        unsafe {
            std::env::remove_var("HARNESS_TOOLS_DIR");
            std::env::set_var("HARNESS_CODING_AGENT_DIR", &agent_dir);
        }

        let dir = tools_cache_dir();

        restore_env_var("HARNESS_TOOLS_DIR", previous_tools_dir);
        restore_env_var("HARNESS_CODING_AGENT_DIR", previous_agent_dir);
        assert_eq!(dir, agent_dir.join("bin"));
    }

    #[test]
    fn tools_dir_override_wins_over_agent_dir() {
        let _guard = test_env_lock();
        let tools_dir = temp_dir("tools-dir-override");
        let agent_dir = temp_dir("tools-agent-ignored");
        let previous_tools_dir = std::env::var_os("HARNESS_TOOLS_DIR");
        let previous_agent_dir = std::env::var_os("HARNESS_CODING_AGENT_DIR");
        unsafe {
            std::env::set_var("HARNESS_TOOLS_DIR", &tools_dir);
            std::env::set_var("HARNESS_CODING_AGENT_DIR", &agent_dir);
        }

        let dir = tools_cache_dir();

        restore_env_var("HARNESS_TOOLS_DIR", previous_tools_dir);
        restore_env_var("HARNESS_CODING_AGENT_DIR", previous_agent_dir);
        assert_eq!(dir, tools_dir);
    }

    #[test]
    fn offline_mode_reports_missing_tool_without_download() {
        let _guard = test_env_lock();
        let dir = temp_dir("tools-offline");
        let previous_tools_dir = std::env::var_os("HARNESS_TOOLS_DIR");
        let previous_offline = std::env::var_os("HARNESS_OFFLINE");
        let previous_pi_offline = std::env::var_os("PI_OFFLINE");
        unsafe {
            std::env::set_var("HARNESS_TOOLS_DIR", &dir);
            std::env::remove_var("HARNESS_OFFLINE");
            std::env::set_var("PI_OFFLINE", "yes");
        }

        let error = ensure_executable("definitely-missing-harness-tool")
            .unwrap_err()
            .to_string();

        restore_env_var("HARNESS_TOOLS_DIR", previous_tools_dir);
        restore_env_var("HARNESS_OFFLINE", previous_offline);
        restore_env_var("PI_OFFLINE", previous_pi_offline);
        assert!(error.contains("offline mode"));
    }

    #[test]
    fn tool_asset_names_match_pi_manager() {
        let fd = ToolDownload::for_name("fd").unwrap();
        let rg = ToolDownload::for_name("rg").unwrap();

        assert_eq!(
            fd.asset_name_for("10.3.0", "macos", "x86_64").unwrap(),
            "fd-v10.3.0-x86_64-apple-darwin.tar.gz"
        );
        assert_eq!(
            fd.asset_name_for("10.3.0", "windows", "aarch64").unwrap(),
            "fd-v10.3.0-aarch64-pc-windows-msvc.zip"
        );
        assert_eq!(
            rg.asset_name_for("14.1.1", "linux", "x86_64").unwrap(),
            "ripgrep-14.1.1-x86_64-unknown-linux-musl.tar.gz"
        );
        assert_eq!(
            rg.asset_name_for("14.1.1", "linux", "aarch64").unwrap(),
            "ripgrep-14.1.1-aarch64-unknown-linux-gnu.tar.gz"
        );
    }

    fn test_env_lock() -> std::sync::MutexGuard<'static, ()> {
        static LOCK: OnceLock<Mutex<()>> = OnceLock::new();
        LOCK.get_or_init(|| Mutex::new(())).lock().unwrap()
    }

    fn restore_env_var(name: &str, value: Option<std::ffi::OsString>) {
        unsafe {
            if let Some(value) = value {
                std::env::set_var(name, value);
            } else {
                std::env::remove_var(name);
            }
        }
    }

    fn temp_dir(name: &str) -> PathBuf {
        let path = std::env::temp_dir().join(format!(
            "harness-{name}-{}-{}",
            std::process::id(),
            SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        fs::create_dir_all(&path).unwrap();
        path
    }
}
