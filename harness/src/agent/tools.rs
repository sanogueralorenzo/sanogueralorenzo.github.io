use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use anyhow::{Context, Result, anyhow, bail};
use serde::Serialize;
use serde_json::{Value, json};

const DEFAULT_MAX_LINES: usize = 2000;
const DEFAULT_MAX_BYTES: usize = 50 * 1024;
const GREP_MAX_LINE_LENGTH: usize = 500;
const DEFAULT_FIND_LIMIT: usize = 1000;
const DEFAULT_GREP_LIMIT: usize = 100;
const DEFAULT_LS_LIMIT: usize = 500;

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
                            "Read a text file. Output is truncated to {DEFAULT_MAX_LINES} lines or {}KB. Use offset/limit for large files.",
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
    })
}

fn write_tool(ctx: &ToolContext, arguments: &Value) -> Result<ToolOutput> {
    let path = string_arg(arguments, "path")?;
    let content = string_arg(arguments, "content")?;
    let absolute_path = resolve_to_cwd(path, &ctx.cwd);
    if let Some(parent) = absolute_path.parent() {
        fs::create_dir_all(parent).with_context(|| format!("create {}", parent.display()))?;
    }
    fs::write(&absolute_path, content)
        .with_context(|| format!("write {}", absolute_path.display()))?;
    Ok(ToolOutput {
        content: format!("Successfully wrote {} bytes to {path}", content.len()),
        details: None,
    })
}

fn edit_tool(ctx: &ToolContext, arguments: &Value) -> Result<ToolOutput> {
    let path = string_arg(arguments, "path")?;
    let edits = parse_edits(arguments.get("edits"))?;
    let absolute_path = resolve_to_cwd(path, &ctx.cwd);
    let raw_content = fs::read_to_string(&absolute_path)
        .with_context(|| format!("read {}", absolute_path.display()))?;
    let (bom, content) = strip_bom(&raw_content);
    let line_ending = detect_line_ending(content);
    let normalized = normalize_to_lf(content);
    let replacements = plan_replacements(&normalized, &edits, path)?;
    let mut new_content = String::with_capacity(normalized.len());
    let mut cursor = 0;
    for replacement in &replacements {
        new_content.push_str(&normalized[cursor..replacement.start]);
        new_content.push_str(&replacement.new_text);
        cursor = replacement.end;
    }
    new_content.push_str(&normalized[cursor..]);
    let final_content = format!("{bom}{}", restore_line_endings(&new_content, line_ending));
    fs::write(&absolute_path, final_content)
        .with_context(|| format!("write {}", absolute_path.display()))?;

    let diff = simple_diff(&normalized, &new_content);
    let patch = simple_patch(path, &normalized, &new_content);
    Ok(ToolOutput {
        content: format!(
            "Successfully replaced {} block(s) in {path}.",
            replacements.len()
        ),
        details: Some(json!({
            "diff": diff,
            "patch": patch,
            "firstChangedLine": first_changed_line(&normalized, &new_content)
        })),
    })
}

fn bash_tool(ctx: &ToolContext, arguments: &Value) -> Result<ToolOutput> {
    let command = string_arg(arguments, "command")?;
    let timeout = optional_u64_arg(arguments, "timeout")?;
    let mut child = Command::new("/bin/sh")
        .arg("-lc")
        .arg(command)
        .current_dir(&ctx.cwd)
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .with_context(|| format!("spawn shell command: {command}"))?;

    let started = Instant::now();
    loop {
        if let Some(_status) = child.try_wait()? {
            break;
        }
        if let Some(seconds) = timeout
            && started.elapsed() >= Duration::from_secs(seconds)
        {
            let _ = child.kill();
            let _ = child.wait();
            bail!("command timed out after {seconds}s");
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
        "truncation": if truncated.truncation.truncated { json!(truncated.truncation) } else { Value::Null },
        "fullOutputPath": full_output_path.map(|path| path.display().to_string())
    });
    Ok(ToolOutput {
        content,
        details: Some(details),
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
    let rg = executable("rg")?;
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
    let fd = executable("fd")?;
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
struct Replacement {
    start: usize,
    end: usize,
    new_text: String,
}

fn parse_edits(value: Option<&Value>) -> Result<Vec<Edit>> {
    let Some(Value::Array(raw_edits)) = value else {
        bail!("edits must be a non-empty array");
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

fn plan_replacements(content: &str, edits: &[Edit], path: &str) -> Result<Vec<Replacement>> {
    let mut replacements = Vec::new();
    for edit in edits {
        if edit.old_text.is_empty() {
            bail!("Could not edit file: {path}. oldText cannot be empty.");
        }
        let mut matches = content.match_indices(&edit.old_text).collect::<Vec<_>>();
        if matches.len() != 1 {
            bail!(
                "Could not edit file: {path}. oldText must match exactly once; found {} matches.",
                matches.len()
            );
        }
        let (start, _) = matches.remove(0);
        replacements.push(Replacement {
            start,
            end: start + edit.old_text.len(),
            new_text: edit.new_text.clone(),
        });
    }
    replacements.sort_by_key(|replacement| replacement.start);
    for pair in replacements.windows(2) {
        if pair[0].end > pair[1].start {
            bail!("Could not edit file: {path}. edits must not overlap.");
        }
    }
    Ok(replacements)
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

fn simple_diff(old: &str, new: &str) -> String {
    let old_lines = split_lines_for_counting(old);
    let new_lines = split_lines_for_counting(new);
    let mut lines = Vec::new();
    for line in old_lines.iter().filter(|line| !new_lines.contains(line)) {
        lines.push(format!("-{line}"));
    }
    for line in new_lines.iter().filter(|line| !old_lines.contains(line)) {
        lines.push(format!("+{line}"));
    }
    lines.join("\n")
}

fn simple_patch(path: &str, old: &str, new: &str) -> String {
    format!("--- {path}\n+++ {path}\n@@\n{}", simple_diff(old, new))
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

fn executable(name: &str) -> Result<String> {
    let path = std::env::var_os("PATH").unwrap_or_default();
    for dir in std::env::split_paths(&path) {
        let candidate = dir.join(name);
        if candidate.is_file() {
            return Ok(candidate.display().to_string());
        }
    }
    bail!("{name} is not available on PATH")
}

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

        assert!(error.contains("exactly once"));
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
        if executable("rg").is_err() {
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
        if executable("fd").is_err() {
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
