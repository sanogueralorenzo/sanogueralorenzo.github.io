use std::collections::{HashMap, HashSet};
use std::fs::{File, OpenOptions};
use std::io::Write;
use std::path::{Path, PathBuf};

use anyhow::{Context, Result, bail};
use chrono::Utc;
use serde::{Deserialize, Serialize};
use serde_json::Value;

const CURRENT_SESSION_VERSION: u32 = 3;
#[cfg(test)]
const DEFAULT_THINKING_LEVEL: &str = "off";
const COMPACTION_SUMMARY_PREFIX: &str = "The conversation history before this point was compacted into the following summary:\n\n<summary>\n";
const COMPACTION_SUMMARY_SUFFIX: &str = "\n</summary>";
const BRANCH_SUMMARY_PREFIX: &str =
    "The following is a summary of a branch that this conversation came back from:\n\n<summary>\n";
const BRANCH_SUMMARY_SUFFIX: &str = "</summary>";

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(tag = "type")]
pub enum Event {
    JobStarted,
    TurnStarted {
        index: usize,
    },
    UserMessage {
        content: String,
    },
    AssistantMessage {
        content: String,
    },
    ToolCall {
        id: String,
        name: String,
        arguments: Value,
    },
    ToolCalls {
        calls: Vec<ToolCallEvent>,
    },
    ToolResult {
        tool_call_id: String,
        name: String,
        output: String,
        #[serde(skip_serializing_if = "Option::is_none")]
        details: Option<Value>,
    },
    TurnFinished {
        index: usize,
    },
    JobFinished,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct ToolCallEvent {
    pub id: String,
    pub name: String,
    pub arguments: Value,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct SessionHeader {
    pub version: u32,
    pub id: String,
    pub timestamp: String,
    pub cwd: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub parent_session: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(tag = "type")]
pub enum FileEntry {
    #[serde(rename = "session", rename_all = "camelCase")]
    Session {
        version: u32,
        id: String,
        timestamp: String,
        cwd: String,
        #[serde(skip_serializing_if = "Option::is_none")]
        parent_session: Option<String>,
    },
    #[serde(rename = "message", rename_all = "camelCase")]
    Message {
        id: String,
        parent_id: Option<String>,
        timestamp: String,
        message: AgentMessage,
    },
    #[serde(rename = "thinking_level_change", rename_all = "camelCase")]
    ThinkingLevelChange {
        id: String,
        parent_id: Option<String>,
        timestamp: String,
        thinking_level: String,
    },
    #[serde(rename = "model_change", rename_all = "camelCase")]
    ModelChange {
        id: String,
        parent_id: Option<String>,
        timestamp: String,
        provider: String,
        model_id: String,
    },
    #[serde(rename = "compaction", rename_all = "camelCase")]
    Compaction {
        id: String,
        parent_id: Option<String>,
        timestamp: String,
        summary: String,
        first_kept_entry_id: String,
        tokens_before: usize,
        #[serde(skip_serializing_if = "Option::is_none")]
        details: Option<Value>,
        #[serde(skip_serializing_if = "Option::is_none")]
        from_hook: Option<bool>,
    },
    #[serde(rename = "branch_summary", rename_all = "camelCase")]
    BranchSummary {
        id: String,
        parent_id: Option<String>,
        timestamp: String,
        from_id: String,
        summary: String,
        #[serde(skip_serializing_if = "Option::is_none")]
        details: Option<Value>,
        #[serde(skip_serializing_if = "Option::is_none")]
        from_hook: Option<bool>,
    },
    #[serde(rename = "custom", rename_all = "camelCase")]
    Custom {
        id: String,
        parent_id: Option<String>,
        timestamp: String,
        custom_type: String,
        #[serde(skip_serializing_if = "Option::is_none")]
        data: Option<Value>,
    },
    #[serde(rename = "custom_message", rename_all = "camelCase")]
    CustomMessage {
        id: String,
        parent_id: Option<String>,
        timestamp: String,
        custom_type: String,
        content: MessageContent,
        #[serde(skip_serializing_if = "Option::is_none")]
        details: Option<Value>,
        display: bool,
    },
    #[serde(rename = "label", rename_all = "camelCase")]
    Label {
        id: String,
        parent_id: Option<String>,
        timestamp: String,
        target_id: String,
        #[serde(skip_serializing_if = "Option::is_none")]
        label: Option<String>,
    },
    #[serde(rename = "session_info", rename_all = "camelCase")]
    SessionInfo {
        id: String,
        parent_id: Option<String>,
        timestamp: String,
        #[serde(skip_serializing_if = "Option::is_none")]
        name: Option<String>,
    },
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(tag = "role")]
pub enum AgentMessage {
    #[serde(rename = "user")]
    User {
        content: MessageContent,
        timestamp: i64,
    },
    #[serde(rename = "assistant", rename_all = "camelCase")]
    Assistant {
        content: Vec<AssistantContent>,
        api: String,
        provider: String,
        model: String,
        usage: Usage,
        stop_reason: String,
        timestamp: i64,
    },
    #[serde(rename = "toolResult", rename_all = "camelCase")]
    ToolResult {
        tool_call_id: String,
        tool_name: String,
        content: Vec<MessagePart>,
        #[serde(skip_serializing_if = "Option::is_none")]
        details: Option<Value>,
        is_error: bool,
        timestamp: i64,
    },
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(untagged)]
pub enum MessageContent {
    Text(String),
    Parts(Vec<MessagePart>),
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(tag = "type")]
pub enum MessagePart {
    #[serde(rename = "text")]
    Text { text: String },
    #[serde(rename = "image", rename_all = "camelCase")]
    Image { data: String, mime_type: String },
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(tag = "type")]
pub enum AssistantContent {
    #[serde(rename = "text")]
    Text { text: String },
    #[serde(rename = "toolCall")]
    ToolCall {
        id: String,
        name: String,
        arguments: Value,
    },
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, Default)]
#[serde(rename_all = "camelCase")]
pub struct Usage {
    input: usize,
    output: usize,
    cache_read: usize,
    cache_write: usize,
    total_tokens: usize,
    cost: UsageCost,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, Default)]
#[serde(rename_all = "camelCase")]
pub struct UsageCost {
    input: usize,
    output: usize,
    cache_read: usize,
    cache_write: usize,
    total: usize,
}

#[derive(Debug, Clone, PartialEq)]
pub struct SessionTreeNode {
    pub entry: FileEntry,
    pub children: Vec<SessionTreeNode>,
    pub label: Option<String>,
    pub label_timestamp: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SessionStats {
    pub session_file: Option<PathBuf>,
    pub session_id: String,
    pub user_messages: usize,
    pub assistant_messages: usize,
    pub tool_calls: usize,
    pub tool_results: usize,
    pub total_messages: usize,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SessionInfo {
    pub path: PathBuf,
    pub id: String,
    pub cwd: String,
    pub name: Option<String>,
    pub parent_session_path: Option<String>,
    pub created: String,
    pub modified: String,
    pub message_count: usize,
    pub first_message: Option<String>,
    pub all_messages_text: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CompactionPlan {
    pub first_kept_entry_id: String,
    pub tokens_before: usize,
    pub compacted_entry_count: usize,
    pub previous_summary: Option<String>,
}

pub struct SessionLog {
    header: SessionHeader,
    entries: Vec<FileEntry>,
    events: Vec<Event>,
    file: Option<File>,
    file_path: Option<PathBuf>,
    flushed: bool,
    by_id: HashMap<String, FileEntry>,
    labels_by_id: HashMap<String, String>,
    label_timestamps_by_id: HashMap<String, String>,
    leaf_id: Option<String>,
}

#[allow(dead_code)]
impl SessionLog {
    pub fn open(path: PathBuf) -> Result<Self> {
        ensure_parent_dir(&path)?;
        let path_existed = path.exists();
        let cwd = std::env::current_dir()
            .context("resolve current working directory")?
            .display()
            .to_string();
        let (header, entries, needs_rewrite) = load_or_create_file_entries(&path, cwd, None)?;
        if needs_rewrite {
            rewrite_file(&path, &header, &entries)?;
        }
        let (file, flushed) = if path_existed || needs_rewrite {
            let file = OpenOptions::new()
                .create(true)
                .append(true)
                .open(&path)
                .with_context(|| format!("open session log {}", path.display()))?;
            (Some(file), true)
        } else {
            (None, false)
        };

        Ok(Self::from_parts(header, entries, file, Some(path), flushed))
    }

    pub fn create(cwd: PathBuf, session_dir: Option<PathBuf>) -> Result<Self> {
        let cwd = resolved_display_path(&cwd)?;
        let session_dir = match session_dir {
            Some(path) => path,
            None => default_session_dir(Path::new(&cwd))?,
        };
        std::fs::create_dir_all(&session_dir)
            .with_context(|| format!("create session directory {}", session_dir.display()))?;
        let path = timestamped_session_path(&session_dir, &cwd);
        ensure_parent_dir(&path)?;
        let header = new_header(&path, cwd, None);
        Ok(Self::from_parts(
            header,
            Vec::new(),
            None,
            Some(path),
            false,
        ))
    }

    pub fn continue_recent(cwd: PathBuf, session_dir: Option<PathBuf>) -> Result<Self> {
        let cwd = resolved_display_path(&cwd)?;
        let session_dir = match session_dir {
            Some(path) => path,
            None => default_session_dir(Path::new(&cwd))?,
        };
        let sessions = list_sessions_in_dir(&session_dir, Some(&cwd))?;
        if let Some(info) = sessions.first() {
            return Self::open(info.path.clone());
        }
        Self::create(PathBuf::from(cwd), Some(session_dir))
    }

    pub fn default_session_dir(cwd: &Path) -> Result<PathBuf> {
        default_session_dir(cwd)
    }

    pub fn list(cwd: PathBuf, session_dir: Option<PathBuf>) -> Result<Vec<SessionInfo>> {
        let cwd = resolved_display_path(&cwd)?;
        let session_dir = match session_dir {
            Some(path) => path,
            None => default_session_dir(Path::new(&cwd))?,
        };
        list_sessions_in_dir(&session_dir, Some(&cwd))
    }

    pub fn list_all(agent_dir: Option<PathBuf>) -> Result<Vec<SessionInfo>> {
        let sessions_root = agent_dir.unwrap_or_else(harness_agent_dir).join("sessions");
        if !sessions_root.exists() {
            return Ok(Vec::new());
        }
        let mut sessions = Vec::new();
        for entry in std::fs::read_dir(&sessions_root)
            .with_context(|| format!("read sessions directory {}", sessions_root.display()))?
        {
            let path = entry?.path();
            if path.is_dir() {
                sessions.extend(list_sessions_in_dir(&path, None)?);
            }
        }
        sessions.sort_by(|a, b| b.modified.cmp(&a.modified));
        Ok(sessions)
    }

    pub fn fork_from(source_path: &Path, target_path: PathBuf) -> Result<Self> {
        ensure_parent_dir(&target_path)?;
        let (source_header, source_entries) = load_existing_session(source_path)?;
        let header = new_header(
            &target_path,
            source_header.cwd.clone(),
            Some(source_path.display().to_string()),
        );
        rewrite_file(&target_path, &header, &source_entries)?;
        let file = OpenOptions::new()
            .append(true)
            .open(&target_path)
            .with_context(|| format!("open forked session log {}", target_path.display()))?;
        Ok(Self::from_parts(
            header,
            source_entries,
            Some(file),
            Some(target_path),
            true,
        ))
    }

    #[cfg(test)]
    pub fn memory() -> Self {
        let header = new_header(
            Path::new("memory"),
            std::env::current_dir().unwrap().display().to_string(),
            None,
        );
        Self::from_parts(header, Vec::new(), None, None, false)
    }

    pub fn events(&self) -> &[Event] {
        &self.events
    }

    pub fn context_events(&self) -> Vec<Event> {
        build_context_events(
            &self.get_branch(self.leaf_id.as_deref()),
            self.leaf_id.as_deref(),
        )
    }

    pub fn session_id(&self) -> Option<&str> {
        Some(&self.header.id)
    }

    pub fn header(&self) -> &SessionHeader {
        &self.header
    }

    pub fn entries(&self) -> &[FileEntry] {
        &self.entries
    }

    pub fn leaf_id(&self) -> Option<&str> {
        self.leaf_id.as_deref()
    }

    pub fn session_file(&self) -> Option<&Path> {
        self.file_path.as_deref()
    }

    pub fn append(&mut self, event: Event) -> Result<String> {
        let entry = self.entry_from_event(event)?;
        self.append_entry(entry)
    }

    pub fn append_model_change(&mut self, provider: String, model_id: String) -> Result<String> {
        let entry = FileEntry::ModelChange {
            id: self.generate_entry_id(),
            parent_id: self.leaf_id.clone(),
            timestamp: timestamp(),
            provider,
            model_id,
        };
        self.append_entry(entry)
    }

    pub fn append_thinking_level_change(&mut self, thinking_level: String) -> Result<String> {
        let entry = FileEntry::ThinkingLevelChange {
            id: self.generate_entry_id(),
            parent_id: self.leaf_id.clone(),
            timestamp: timestamp(),
            thinking_level,
        };
        self.append_entry(entry)
    }

    pub fn append_session_info(&mut self, name: Option<String>) -> Result<String> {
        let entry = FileEntry::SessionInfo {
            id: self.generate_entry_id(),
            parent_id: self.leaf_id.clone(),
            timestamp: timestamp(),
            name: name
                .map(|value| value.trim().to_owned())
                .filter(|value| !value.is_empty()),
        };
        self.append_entry(entry)
    }

    pub fn append_label_change(
        &mut self,
        target_id: String,
        label: Option<String>,
    ) -> Result<String> {
        if !self.by_id.contains_key(&target_id) {
            bail!("entry {target_id} not found");
        }
        let entry = FileEntry::Label {
            id: self.generate_entry_id(),
            parent_id: self.leaf_id.clone(),
            timestamp: timestamp(),
            target_id,
            label: label.filter(|value| !value.trim().is_empty()),
        };
        self.append_entry(entry)
    }

    pub fn append_compaction(
        &mut self,
        summary: String,
        first_kept_entry_id: String,
        tokens_before: usize,
        details: Option<Value>,
        from_hook: Option<bool>,
    ) -> Result<String> {
        if !self.by_id.contains_key(&first_kept_entry_id) {
            bail!("entry {first_kept_entry_id} not found");
        }
        let entry = FileEntry::Compaction {
            id: self.generate_entry_id(),
            parent_id: self.leaf_id.clone(),
            timestamp: timestamp(),
            summary,
            first_kept_entry_id,
            tokens_before,
            details,
            from_hook,
        };
        self.append_entry(entry)
    }

    pub fn prepare_compaction(&self, keep_recent_messages: usize) -> Option<CompactionPlan> {
        let branch = self.get_branch(self.leaf_id.as_deref());
        if branch.is_empty() || matches!(branch.last(), Some(FileEntry::Compaction { .. })) {
            return None;
        }

        let latest_compaction_index = branch
            .iter()
            .rposition(|entry| matches!(entry, FileEntry::Compaction { .. }));
        let boundary_start = latest_compaction_index.map_or(0, |index| index + 1);
        let previous_summary = latest_compaction_index.and_then(|index| match &branch[index] {
            FileEntry::Compaction { summary, .. } => Some(summary.clone()),
            _ => None,
        });
        let context_indices = branch
            .iter()
            .enumerate()
            .skip(boundary_start)
            .filter_map(|(index, entry)| is_compaction_cut_entry(entry).then_some(index))
            .collect::<Vec<_>>();

        let keep_recent_messages = keep_recent_messages.max(1);
        if context_indices.len() <= keep_recent_messages {
            return None;
        }

        let first_kept_index = context_indices[context_indices.len() - keep_recent_messages];
        let first_kept_entry_id = entry_id(&branch[first_kept_index])?;
        let compacted_entry_count = context_indices
            .iter()
            .filter(|index| **index < first_kept_index)
            .count();
        if compacted_entry_count == 0 {
            return None;
        }

        Some(CompactionPlan {
            first_kept_entry_id,
            tokens_before: estimate_context_tokens(&branch),
            compacted_entry_count,
            previous_summary,
        })
    }

    pub fn branch_with_summary(
        &mut self,
        branch_from_id: Option<String>,
        summary: String,
        details: Option<Value>,
        from_hook: Option<bool>,
    ) -> Result<String> {
        if let Some(id) = branch_from_id.as_deref()
            && !self.by_id.contains_key(id)
        {
            bail!("entry {id} not found");
        }
        self.leaf_id = branch_from_id.clone();
        let entry = FileEntry::BranchSummary {
            id: self.generate_entry_id(),
            parent_id: branch_from_id.clone(),
            timestamp: timestamp(),
            from_id: branch_from_id.unwrap_or_else(|| "root".to_owned()),
            summary,
            details,
            from_hook,
        };
        self.append_entry(entry)
    }

    pub fn branch(&mut self, branch_from_id: &str) -> Result<()> {
        if !self.by_id.contains_key(branch_from_id) {
            bail!("entry {branch_from_id} not found");
        }
        self.leaf_id = Some(branch_from_id.to_owned());
        self.rebuild_events();
        Ok(())
    }

    pub fn reset_leaf(&mut self) {
        self.leaf_id = None;
        self.rebuild_events();
    }

    pub fn get_entry(&self, id: &str) -> Option<&FileEntry> {
        self.by_id.get(id)
    }

    pub fn get_label(&self, id: &str) -> Option<&str> {
        self.labels_by_id.get(id).map(String::as_str)
    }

    pub fn get_children(&self, parent: Option<&str>) -> Vec<&FileEntry> {
        let mut children = self
            .entries
            .iter()
            .filter(|entry| parent_id(entry).as_deref() == parent)
            .collect::<Vec<_>>();
        children.sort_by_key(|entry| entry_timestamp(entry));
        children
    }

    pub fn get_session_name(&self) -> Option<&str> {
        self.entries.iter().rev().find_map(|entry| match entry {
            FileEntry::SessionInfo { name, .. } => name.as_deref(),
            _ => None,
        })
    }

    pub fn get_branch(&self, from_id: Option<&str>) -> Vec<FileEntry> {
        let mut branch = Vec::new();
        let mut current_id = from_id.map(str::to_owned).or_else(|| self.leaf_id.clone());
        let mut visited = HashSet::new();
        while let Some(id) = current_id {
            if !visited.insert(id.clone()) {
                break;
            }
            let Some(entry) = self.by_id.get(&id).cloned() else {
                break;
            };
            current_id = parent_id(&entry);
            branch.push(entry);
        }
        branch.reverse();
        branch
    }

    pub fn get_tree(&self) -> Vec<SessionTreeNode> {
        let mut children_by_parent: HashMap<Option<String>, Vec<FileEntry>> = HashMap::new();
        let entry_ids = self
            .entries
            .iter()
            .filter_map(entry_id)
            .collect::<HashSet<_>>();
        for entry in &self.entries {
            let parent = match (entry_id(entry), parent_id(entry)) {
                (Some(id), Some(parent)) if id == parent => None,
                (_, Some(parent)) if !entry_ids.contains(&parent) => None,
                (_, parent) => parent,
            };
            children_by_parent
                .entry(parent)
                .or_default()
                .push(entry.clone());
        }
        for children in children_by_parent.values_mut() {
            children.sort_by_key(entry_timestamp);
        }
        build_tree_nodes(
            None,
            &children_by_parent,
            &self.labels_by_id,
            &self.label_timestamps_by_id,
        )
    }

    pub fn create_branched_session(&self, leaf_id: &str, target_path: PathBuf) -> Result<Self> {
        if !self.by_id.contains_key(leaf_id) {
            bail!("entry {leaf_id} not found");
        }
        ensure_parent_dir(&target_path)?;
        let branch = self
            .get_branch(Some(leaf_id))
            .into_iter()
            .filter(|entry| !matches!(entry, FileEntry::Label { .. }))
            .collect::<Vec<_>>();
        let branch_ids = branch.iter().filter_map(entry_id).collect::<HashSet<_>>();
        let mut copied = branch;
        let mut parent = copied.last().and_then(entry_id);
        for entry in &self.entries {
            let FileEntry::Label {
                target_id,
                label,
                timestamp,
                ..
            } = entry
            else {
                continue;
            };
            if !branch_ids.contains(target_id) {
                continue;
            }
            let label_entry = FileEntry::Label {
                id: generate_entry_id_from_entries(&copied, &self.header.id),
                parent_id: parent.clone(),
                timestamp: timestamp.clone(),
                target_id: target_id.clone(),
                label: label.clone(),
            };
            parent = entry_id(&label_entry);
            copied.push(label_entry);
        }
        let header = new_header(
            &target_path,
            self.header.cwd.clone(),
            self.file_path
                .as_ref()
                .map(|path| path.display().to_string()),
        );
        let has_assistant = copied.iter().any(is_assistant_message_entry);
        let (file, flushed) = if has_assistant {
            rewrite_file(&target_path, &header, &copied)?;
            let file = OpenOptions::new()
                .append(true)
                .open(&target_path)
                .with_context(|| format!("open branched session log {}", target_path.display()))?;
            (Some(file), true)
        } else {
            (None, false)
        };
        Ok(Self::from_parts(
            header,
            copied,
            file,
            Some(target_path),
            flushed,
        ))
    }

    pub fn stats(&self) -> SessionStats {
        let mut user_messages = 0;
        let mut assistant_messages = 0;
        let mut tool_calls = 0;
        let mut tool_results = 0;
        for entry in &self.entries {
            let FileEntry::Message { message, .. } = entry else {
                continue;
            };
            match message {
                AgentMessage::User { .. } => user_messages += 1,
                AgentMessage::Assistant { content, .. } => {
                    assistant_messages += 1;
                    tool_calls += content
                        .iter()
                        .filter(|part| matches!(part, AssistantContent::ToolCall { .. }))
                        .count();
                }
                AgentMessage::ToolResult { .. } => tool_results += 1,
            }
        }
        SessionStats {
            session_file: self.file_path.clone(),
            session_id: self.header.id.clone(),
            user_messages,
            assistant_messages,
            tool_calls,
            tool_results,
            total_messages: user_messages + assistant_messages + tool_results,
        }
    }

    pub fn latest_compaction(&self) -> Option<&FileEntry> {
        self.entries
            .iter()
            .rev()
            .find(|entry| matches!(entry, FileEntry::Compaction { .. }))
    }

    fn from_parts(
        header: SessionHeader,
        entries: Vec<FileEntry>,
        file: Option<File>,
        file_path: Option<PathBuf>,
        flushed: bool,
    ) -> Self {
        let mut log = Self {
            header,
            entries,
            events: Vec::new(),
            file,
            file_path,
            flushed,
            by_id: HashMap::new(),
            labels_by_id: HashMap::new(),
            label_timestamps_by_id: HashMap::new(),
            leaf_id: None,
        };
        log.rebuild_index();
        log.rebuild_events();
        log
    }

    fn append_entry(&mut self, entry: FileEntry) -> Result<String> {
        let id = entry_id(&entry).context("session entries must have ids")?;
        self.entries.push(entry.clone());
        self.persist_entry(&entry)?;
        self.rebuild_index();
        self.rebuild_events();
        Ok(id)
    }

    fn persist_entry(&mut self, entry: &FileEntry) -> Result<()> {
        let Some(path) = self.file_path.as_ref() else {
            return Ok(());
        };

        let has_assistant = self.entries.iter().any(is_assistant_message_entry);
        if !has_assistant {
            if self.flushed {
                append_entry_line(self.file.as_mut(), path, entry)?;
            }
            return Ok(());
        }

        if !self.flushed {
            rewrite_file(path, &self.header, &self.entries)?;
            let file = OpenOptions::new()
                .append(true)
                .open(path)
                .with_context(|| format!("open session log {}", path.display()))?;
            self.file = Some(file);
            self.flushed = true;
        } else {
            append_entry_line(self.file.as_mut(), path, entry)?;
        }
        Ok(())
    }

    fn entry_from_event(&self, event: Event) -> Result<FileEntry> {
        let id = self.generate_entry_id();
        let parent_id = self.leaf_id.clone();
        let timestamp = timestamp();
        let message_timestamp = unix_millis();
        Ok(match event {
            Event::UserMessage { content } => FileEntry::Message {
                id,
                parent_id,
                timestamp,
                message: AgentMessage::User {
                    content: MessageContent::Text(content),
                    timestamp: message_timestamp,
                },
            },
            Event::AssistantMessage { content } => FileEntry::Message {
                id,
                parent_id,
                timestamp,
                message: AgentMessage::Assistant {
                    content: vec![AssistantContent::Text { text: content }],
                    api: "harness".to_owned(),
                    provider: "harness".to_owned(),
                    model: "unknown".to_owned(),
                    usage: Usage::default(),
                    stop_reason: "stop".to_owned(),
                    timestamp: message_timestamp,
                },
            },
            Event::ToolCall {
                id: tool_call_id,
                name,
                arguments,
            } => FileEntry::Message {
                id,
                parent_id,
                timestamp,
                message: AgentMessage::Assistant {
                    content: vec![AssistantContent::ToolCall {
                        id: tool_call_id,
                        name,
                        arguments,
                    }],
                    api: "harness".to_owned(),
                    provider: "harness".to_owned(),
                    model: "unknown".to_owned(),
                    usage: Usage::default(),
                    stop_reason: "toolUse".to_owned(),
                    timestamp: message_timestamp,
                },
            },
            Event::ToolCalls { calls } => FileEntry::Message {
                id,
                parent_id,
                timestamp,
                message: AgentMessage::Assistant {
                    content: calls
                        .into_iter()
                        .map(|call| AssistantContent::ToolCall {
                            id: call.id,
                            name: call.name,
                            arguments: call.arguments,
                        })
                        .collect(),
                    api: "harness".to_owned(),
                    provider: "harness".to_owned(),
                    model: "unknown".to_owned(),
                    usage: Usage::default(),
                    stop_reason: "toolUse".to_owned(),
                    timestamp: message_timestamp,
                },
            },
            Event::ToolResult {
                tool_call_id,
                name,
                output,
                details,
            } => FileEntry::Message {
                id,
                parent_id,
                timestamp,
                message: AgentMessage::ToolResult {
                    tool_call_id,
                    tool_name: name,
                    content: tool_result_content(&output, details.as_ref()),
                    details,
                    is_error: false,
                    timestamp: message_timestamp,
                },
            },
            event => FileEntry::Custom {
                id,
                parent_id,
                timestamp,
                custom_type: "runtime_event".to_owned(),
                data: Some(serde_json::to_value(event)?),
            },
        })
    }

    fn rebuild_index(&mut self) {
        self.by_id.clear();
        self.labels_by_id.clear();
        self.label_timestamps_by_id.clear();
        self.leaf_id = None;
        for entry in &self.entries {
            let Some(id) = entry_id(entry) else {
                continue;
            };
            self.by_id.insert(id.clone(), entry.clone());
            self.leaf_id = Some(id);
            if let FileEntry::Label {
                target_id,
                label,
                timestamp,
                ..
            } = entry
            {
                if let Some(label) = label {
                    self.labels_by_id.insert(target_id.clone(), label.clone());
                    self.label_timestamps_by_id
                        .insert(target_id.clone(), timestamp.clone());
                } else {
                    self.labels_by_id.remove(target_id);
                    self.label_timestamps_by_id.remove(target_id);
                }
            }
        }
    }

    fn rebuild_events(&mut self) {
        self.events = self
            .get_branch(self.leaf_id.as_deref())
            .iter()
            .filter_map(event_from_entry)
            .collect();
    }

    fn generate_entry_id(&self) -> String {
        generate_entry_id_from_entries(&self.entries, &self.header.id)
    }
}

fn load_or_create_file_entries(
    path: &Path,
    cwd: String,
    parent_session: Option<String>,
) -> Result<(SessionHeader, Vec<FileEntry>, bool)> {
    if !path.exists() {
        return Ok((new_header(path, cwd, parent_session), Vec::new(), false));
    }

    match load_existing_session(path) {
        Ok((header, entries)) => Ok((header, entries, false)),
        Err(_) => Ok((new_header(path, cwd, parent_session), Vec::new(), true)),
    }
}

fn load_existing_session(path: &Path) -> Result<(SessionHeader, Vec<FileEntry>)> {
    let content = std::fs::read_to_string(path)
        .with_context(|| format!("read session log {}", path.display()))?;
    let mut lines = content.lines().filter(|line| !line.trim().is_empty());
    let Some(header_line) = lines.next() else {
        bail!("session log {} is empty", path.display());
    };
    let header_entry: FileEntry = serde_json::from_str(header_line)
        .with_context(|| format!("parse session header {}", path.display()))?;
    let FileEntry::Session {
        version,
        id,
        timestamp,
        cwd,
        parent_session,
    } = header_entry
    else {
        bail!("session log {} is missing session header", path.display());
    };
    let mut entries = Vec::new();
    for line in lines {
        let Ok(entry) = serde_json::from_str::<FileEntry>(line) else {
            continue;
        };
        if !matches!(entry, FileEntry::Session { .. }) {
            entries.push(entry);
        }
    }
    Ok((
        SessionHeader {
            version,
            id,
            timestamp,
            cwd,
            parent_session,
        },
        entries,
    ))
}

fn list_sessions_in_dir(session_dir: &Path, cwd: Option<&str>) -> Result<Vec<SessionInfo>> {
    if !session_dir.exists() {
        return Ok(Vec::new());
    }

    let mut sessions = Vec::new();
    for entry in std::fs::read_dir(session_dir)
        .with_context(|| format!("read session directory {}", session_dir.display()))?
    {
        let path = entry?.path();
        if path.extension().and_then(|extension| extension.to_str()) != Some("jsonl") {
            continue;
        }
        let Ok((header, entries)) = load_existing_session(&path) else {
            continue;
        };
        if let Some(cwd) = cwd
            && header.cwd != cwd
        {
            continue;
        }
        sessions.push(build_session_info(path, header, &entries));
    }
    sessions.sort_by(|a, b| b.modified.cmp(&a.modified));
    Ok(sessions)
}

fn build_session_info(path: PathBuf, header: SessionHeader, entries: &[FileEntry]) -> SessionInfo {
    let mut name = None;
    let mut message_count = 0;
    let mut first_message = None;
    let mut all_messages = Vec::new();
    let mut modified = header.timestamp.clone();

    for entry in entries {
        match entry {
            FileEntry::SessionInfo {
                name: entry_name, ..
            } => {
                name = entry_name.clone();
            }
            FileEntry::Message {
                timestamp, message, ..
            } => {
                modified = timestamp.clone();
                message_count += 1;
                match message {
                    AgentMessage::User { content, .. } => {
                        let text = text_from_message_content(content);
                        if first_message.is_none() {
                            first_message = Some(text.clone());
                        }
                        all_messages.push(text);
                    }
                    AgentMessage::Assistant { content, .. } => {
                        let text = text_from_assistant_content(content);
                        if !text.is_empty() {
                            all_messages.push(text);
                        }
                    }
                    AgentMessage::ToolResult { .. } => {}
                }
            }
            _ => {
                modified = entry_timestamp(entry);
            }
        }
    }

    SessionInfo {
        path,
        id: header.id,
        cwd: header.cwd,
        name,
        parent_session_path: header.parent_session,
        created: header.timestamp,
        modified,
        message_count,
        first_message,
        all_messages_text: all_messages.join("\n"),
    }
}

fn rewrite_file(path: &Path, header: &SessionHeader, entries: &[FileEntry]) -> Result<()> {
    ensure_parent_dir(path)?;
    let mut file = OpenOptions::new()
        .create(true)
        .write(true)
        .truncate(true)
        .open(path)
        .with_context(|| format!("rewrite session log {}", path.display()))?;
    writeln!(
        file,
        "{}",
        serde_json::to_string(&FileEntry::Session {
            version: header.version,
            id: header.id.clone(),
            timestamp: header.timestamp.clone(),
            cwd: header.cwd.clone(),
            parent_session: header.parent_session.clone(),
        })?
    )?;
    for entry in entries {
        writeln!(file, "{}", serde_json::to_string(entry)?)?;
    }
    file.flush()?;
    Ok(())
}

fn append_entry_line(file: Option<&mut File>, path: &Path, entry: &FileEntry) -> Result<()> {
    match file {
        Some(file) => {
            writeln!(file, "{}", serde_json::to_string(entry)?)?;
            file.flush()?;
        }
        None => {
            let mut file = OpenOptions::new()
                .create(true)
                .append(true)
                .open(path)
                .with_context(|| format!("open session log {}", path.display()))?;
            writeln!(file, "{}", serde_json::to_string(entry)?)?;
            file.flush()?;
        }
    }
    Ok(())
}

fn new_header(path: &Path, cwd: String, parent_session: Option<String>) -> SessionHeader {
    SessionHeader {
        version: CURRENT_SESSION_VERSION,
        id: session_id(path),
        timestamp: timestamp(),
        cwd,
        parent_session,
    }
}

fn default_session_dir(cwd: &Path) -> Result<PathBuf> {
    let resolved = resolved_display_path(cwd)?;
    let encoded = encode_cwd_for_session_dir(&resolved);
    let session_dir = harness_agent_dir().join("sessions").join(encoded);
    std::fs::create_dir_all(&session_dir)
        .with_context(|| format!("create session directory {}", session_dir.display()))?;
    Ok(session_dir)
}

fn harness_agent_dir() -> PathBuf {
    std::env::var_os("HARNESS_CODING_AGENT_DIR")
        .map(PathBuf::from)
        .or_else(|| {
            std::env::var_os("HOME")
                .map(PathBuf::from)
                .map(|home| home.join(".harness").join("agent"))
        })
        .unwrap_or_else(|| PathBuf::from(".harness/agent"))
}

fn encode_cwd_for_session_dir(cwd: &str) -> String {
    let trimmed = cwd
        .trim_start_matches('/')
        .trim_start_matches('\\')
        .replace(['/', '\\', ':'], "-");
    if trimmed.is_empty() {
        "--root--".to_owned()
    } else {
        format!("--{trimmed}--")
    }
}

fn resolved_display_path(path: &Path) -> Result<String> {
    let absolute = if path.is_absolute() {
        path.to_path_buf()
    } else {
        std::env::current_dir()
            .context("resolve current working directory")?
            .join(path)
    };
    Ok(std::fs::canonicalize(&absolute)
        .unwrap_or(absolute)
        .display()
        .to_string())
}

fn timestamped_session_path(session_dir: &Path, cwd: &str) -> PathBuf {
    let file_timestamp = timestamp().replace([':', '.'], "-");
    for attempt in 0..100 {
        let seed = format!("{}:{cwd}:{file_timestamp}:{attempt}", session_dir.display());
        let suffix = format!("{:08x}", fnv1a64(&seed) as u32);
        let path = session_dir.join(format!("{file_timestamp}_{suffix}.jsonl"));
        if !path.exists() {
            return path;
        }
    }
    session_dir.join(format!(
        "{file_timestamp}_{:016x}.jsonl",
        fnv1a64(&format!("{cwd}:{}", unix_millis()))
    ))
}

fn session_id(path: &Path) -> String {
    let stable_path = std::fs::canonicalize(path).unwrap_or_else(|_| path.to_path_buf());
    format!(
        "harness_{:016x}",
        fnv1a64(&stable_path.display().to_string())
    )
}

fn timestamp() -> String {
    Utc::now().to_rfc3339_opts(chrono::SecondsFormat::Millis, true)
}

fn unix_millis() -> i64 {
    Utc::now().timestamp_millis()
}

fn fnv1a64(value: &str) -> u64 {
    const OFFSET: u64 = 0xcbf29ce484222325;
    const PRIME: u64 = 0x100000001b3;

    let mut hash = OFFSET;
    for byte in value.as_bytes() {
        hash ^= u64::from(*byte);
        hash = hash.wrapping_mul(PRIME);
    }
    hash
}

fn ensure_parent_dir(path: &Path) -> Result<()> {
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent)
            .with_context(|| format!("create session directory {}", parent.display()))?;
    }
    Ok(())
}

fn generate_entry_id_from_entries(entries: &[FileEntry], session_id: &str) -> String {
    let existing = entries.iter().filter_map(entry_id).collect::<HashSet<_>>();
    for attempt in 0..100 {
        let seed = format!("{session_id}:{}:{}:{attempt}", entries.len(), timestamp());
        let id = format!("{:08x}", fnv1a64(&seed) as u32);
        if !existing.contains(&id) {
            return id;
        }
    }
    format!(
        "{:016x}",
        fnv1a64(&format!("{session_id}:{}", unix_millis()))
    )
}

fn entry_id(entry: &FileEntry) -> Option<String> {
    Some(
        match entry {
            FileEntry::Session { .. } => return None,
            FileEntry::Message { id, .. }
            | FileEntry::ThinkingLevelChange { id, .. }
            | FileEntry::ModelChange { id, .. }
            | FileEntry::Compaction { id, .. }
            | FileEntry::BranchSummary { id, .. }
            | FileEntry::Custom { id, .. }
            | FileEntry::CustomMessage { id, .. }
            | FileEntry::Label { id, .. }
            | FileEntry::SessionInfo { id, .. } => id,
        }
        .clone(),
    )
}

fn parent_id(entry: &FileEntry) -> Option<String> {
    match entry {
        FileEntry::Session { .. } => None,
        FileEntry::Message { parent_id, .. }
        | FileEntry::ThinkingLevelChange { parent_id, .. }
        | FileEntry::ModelChange { parent_id, .. }
        | FileEntry::Compaction { parent_id, .. }
        | FileEntry::BranchSummary { parent_id, .. }
        | FileEntry::Custom { parent_id, .. }
        | FileEntry::CustomMessage { parent_id, .. }
        | FileEntry::Label { parent_id, .. }
        | FileEntry::SessionInfo { parent_id, .. } => parent_id.clone(),
    }
}

fn entry_timestamp(entry: &FileEntry) -> String {
    match entry {
        FileEntry::Session { timestamp, .. }
        | FileEntry::Message { timestamp, .. }
        | FileEntry::ThinkingLevelChange { timestamp, .. }
        | FileEntry::ModelChange { timestamp, .. }
        | FileEntry::Compaction { timestamp, .. }
        | FileEntry::BranchSummary { timestamp, .. }
        | FileEntry::Custom { timestamp, .. }
        | FileEntry::CustomMessage { timestamp, .. }
        | FileEntry::Label { timestamp, .. }
        | FileEntry::SessionInfo { timestamp, .. } => timestamp.clone(),
    }
}

fn event_from_entry(entry: &FileEntry) -> Option<Event> {
    match entry {
        FileEntry::Message { message, .. } => event_from_message(message),
        FileEntry::BranchSummary { summary, .. } => Some(Event::UserMessage {
            content: format!("{BRANCH_SUMMARY_PREFIX}{summary}{BRANCH_SUMMARY_SUFFIX}"),
        }),
        FileEntry::Compaction {
            summary,
            tokens_before,
            ..
        } => Some(Event::UserMessage {
            content: format!(
                "{COMPACTION_SUMMARY_PREFIX}{summary}{COMPACTION_SUMMARY_SUFFIX}\n\n[tokens before compaction: {tokens_before}]"
            ),
        }),
        FileEntry::Custom {
            custom_type, data, ..
        } if custom_type == "runtime_event" => data
            .as_ref()
            .and_then(|value| serde_json::from_value(value.clone()).ok()),
        FileEntry::CustomMessage { content, .. } => Some(Event::UserMessage {
            content: text_from_message_content(content),
        }),
        _ => None,
    }
}

fn is_compaction_cut_entry(entry: &FileEntry) -> bool {
    matches!(
        entry,
        FileEntry::Message { .. }
            | FileEntry::BranchSummary { .. }
            | FileEntry::CustomMessage { .. }
    )
}

fn estimate_context_tokens(entries: &[FileEntry]) -> usize {
    let chars = entries
        .iter()
        .filter_map(event_from_entry)
        .map(|event| estimate_event_chars(&event))
        .sum::<usize>();
    chars.div_ceil(4)
}

fn estimate_event_chars(event: &Event) -> usize {
    match event {
        Event::UserMessage { content } | Event::AssistantMessage { content } => content.len(),
        Event::ToolCall {
            id,
            name,
            arguments,
        } => id.len() + name.len() + arguments.to_string().len(),
        Event::ToolCalls { calls } => calls
            .iter()
            .map(|call| call.id.len() + call.name.len() + call.arguments.to_string().len())
            .sum(),
        Event::ToolResult {
            tool_call_id,
            name,
            output,
            details,
        } => {
            tool_call_id.len()
                + name.len()
                + output.len()
                + details
                    .as_ref()
                    .map(|value| value.to_string().len())
                    .unwrap_or(0)
        }
        Event::JobStarted
        | Event::TurnStarted { .. }
        | Event::TurnFinished { .. }
        | Event::JobFinished => 0,
    }
}

fn event_from_message(message: &AgentMessage) -> Option<Event> {
    match message {
        AgentMessage::User { content, .. } => Some(Event::UserMessage {
            content: text_from_message_content(content),
        }),
        AgentMessage::Assistant { content, .. } => {
            let tool_calls = content
                .iter()
                .filter_map(|part| match part {
                    AssistantContent::ToolCall {
                        id,
                        name,
                        arguments,
                    } => Some(ToolCallEvent {
                        id: id.clone(),
                        name: name.clone(),
                        arguments: arguments.clone(),
                    }),
                    AssistantContent::Text { .. } => None,
                })
                .collect::<Vec<_>>();
            if tool_calls.len() > 1 {
                return Some(Event::ToolCalls { calls: tool_calls });
            }
            for part in content {
                if let AssistantContent::ToolCall {
                    id,
                    name,
                    arguments,
                } = part
                {
                    return Some(Event::ToolCall {
                        id: id.clone(),
                        name: name.clone(),
                        arguments: arguments.clone(),
                    });
                }
            }
            Some(Event::AssistantMessage {
                content: content
                    .iter()
                    .filter_map(|part| match part {
                        AssistantContent::Text { text } => Some(text.as_str()),
                        AssistantContent::ToolCall { .. } => None,
                    })
                    .collect::<Vec<_>>()
                    .join(""),
            })
        }
        AgentMessage::ToolResult {
            tool_call_id,
            tool_name,
            content,
            details,
            ..
        } => Some(Event::ToolResult {
            tool_call_id: tool_call_id.clone(),
            name: tool_name.clone(),
            output: text_from_parts(content),
            details: details.clone(),
        }),
    }
}

fn build_context_events(entries: &[FileEntry], leaf_id: Option<&str>) -> Vec<Event> {
    if leaf_id.is_none() {
        return Vec::new();
    }

    let compaction_index = entries
        .iter()
        .rposition(|entry| matches!(entry, FileEntry::Compaction { .. }));
    let Some(index) = compaction_index else {
        return entries
            .iter()
            .filter(|entry| is_context_entry(entry))
            .filter_map(event_from_entry)
            .collect();
    };

    let mut events = Vec::new();
    if let Some(event) = event_from_entry(&entries[index]) {
        events.push(event);
    }

    let first_kept = match &entries[index] {
        FileEntry::Compaction {
            first_kept_entry_id,
            ..
        } => first_kept_entry_id,
        _ => unreachable!(),
    };
    let mut keep = false;
    for entry in &entries[..index] {
        if entry_id(entry).as_deref() == Some(first_kept.as_str()) {
            keep = true;
        }
        if keep
            && is_context_entry(entry)
            && let Some(event) = event_from_entry(entry)
        {
            events.push(event);
        }
    }
    for entry in &entries[index + 1..] {
        if is_context_entry(entry)
            && let Some(event) = event_from_entry(entry)
        {
            events.push(event);
        }
    }
    events
}

fn is_context_entry(entry: &FileEntry) -> bool {
    matches!(
        entry,
        FileEntry::Message { .. }
            | FileEntry::BranchSummary { .. }
            | FileEntry::CustomMessage { .. }
    )
}

fn is_assistant_message_entry(entry: &FileEntry) -> bool {
    matches!(
        entry,
        FileEntry::Message {
            message: AgentMessage::Assistant { .. },
            ..
        }
    )
}

fn text_from_message_content(content: &MessageContent) -> String {
    match content {
        MessageContent::Text(text) => text.clone(),
        MessageContent::Parts(parts) => text_from_parts(parts),
    }
}

fn text_from_assistant_content(content: &[AssistantContent]) -> String {
    content
        .iter()
        .filter_map(|part| match part {
            AssistantContent::Text { text } => Some(text.as_str()),
            AssistantContent::ToolCall { .. } => None,
        })
        .collect::<Vec<_>>()
        .join("")
}

fn text_from_parts(parts: &[MessagePart]) -> String {
    parts
        .iter()
        .filter_map(|part| match part {
            MessagePart::Text { text } => Some(text.as_str()),
            MessagePart::Image { .. } => None,
        })
        .collect::<Vec<_>>()
        .join("")
}

fn tool_result_content(output: &str, details: Option<&Value>) -> Vec<MessagePart> {
    let mut parts = vec![MessagePart::Text {
        text: output.to_owned(),
    }];
    if let Some(image) = details.and_then(|details| details.get("image")) {
        let omitted = image
            .get("omitted")
            .and_then(Value::as_bool)
            .unwrap_or(false);
        if !omitted
            && let (Some(mime_type), Some(data)) = (
                image.get("mimeType").and_then(Value::as_str),
                image.get("data").and_then(Value::as_str),
            )
        {
            parts.push(MessagePart::Image {
                data: data.to_owned(),
                mime_type: mime_type.to_owned(),
            });
        }
    }
    parts
}

fn build_tree_nodes(
    parent_id: Option<String>,
    children_by_parent: &HashMap<Option<String>, Vec<FileEntry>>,
    labels_by_id: &HashMap<String, String>,
    label_timestamps_by_id: &HashMap<String, String>,
) -> Vec<SessionTreeNode> {
    children_by_parent
        .get(&parent_id)
        .into_iter()
        .flatten()
        .map(|entry| {
            let id = entry_id(entry);
            let children = build_tree_nodes(
                id.clone(),
                children_by_parent,
                labels_by_id,
                label_timestamps_by_id,
            );
            let label = id.as_ref().and_then(|id| labels_by_id.get(id).cloned());
            let label_timestamp = id
                .as_ref()
                .and_then(|id| label_timestamps_by_id.get(id).cloned());
            SessionTreeNode {
                entry: entry.clone(),
                children,
                label,
                label_timestamp,
            }
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn appends_memory_events_as_pi_shaped_entries() {
        let mut log = SessionLog::memory();

        log.append(Event::JobStarted).unwrap();
        let user_id = log
            .append(Event::UserMessage {
                content: "hello".to_owned(),
            })
            .unwrap();

        assert_eq!(log.header().version, CURRENT_SESSION_VERSION);
        assert_eq!(log.events().len(), 2);
        assert_eq!(log.entries().len(), 2);
        assert!(matches!(log.entries()[0], FileEntry::Custom { .. }));
        assert!(matches!(log.entries()[1], FileEntry::Message { .. }));
        assert_eq!(log.leaf_id(), Some(user_id.as_str()));
    }

    #[test]
    fn writes_and_resumes_session_header_and_entries() {
        let path = temp_session_path("resume");
        {
            let mut log = SessionLog::open(path.clone()).unwrap();
            log.append(Event::UserMessage {
                content: "hello".to_owned(),
            })
            .unwrap();
            log.append(Event::AssistantMessage {
                content: "hi".to_owned(),
            })
            .unwrap();
        }

        let log = SessionLog::open(path.clone()).unwrap();
        let content = std::fs::read_to_string(path).unwrap();
        let first_line: Value = serde_json::from_str(content.lines().next().unwrap()).unwrap();

        assert_eq!(first_line["type"], "session");
        assert_eq!(first_line["version"], CURRENT_SESSION_VERSION);
        assert!(
            first_line["cwd"]
                .as_str()
                .unwrap()
                .contains("sanogueralorenzo")
        );
        assert_eq!(log.events().len(), 2);
        assert_eq!(log.session_id(), first_line["id"].as_str());
    }

    #[test]
    fn branches_without_rewriting_history() {
        let mut log = SessionLog::memory();
        let first = log
            .append(Event::UserMessage {
                content: "first".to_owned(),
            })
            .unwrap();
        log.append(Event::AssistantMessage {
            content: "old branch".to_owned(),
        })
        .unwrap();

        log.branch(&first).unwrap();
        log.append(Event::UserMessage {
            content: "new branch".to_owned(),
        })
        .unwrap();

        let events = log.events();
        assert_eq!(log.entries().len(), 3);
        assert_eq!(
            events,
            &[
                Event::UserMessage {
                    content: "first".to_owned()
                },
                Event::UserMessage {
                    content: "new branch".to_owned()
                }
            ]
        );
        assert_eq!(log.get_tree().len(), 1);
        assert_eq!(log.get_tree()[0].children.len(), 2);
    }

    #[test]
    fn compaction_context_matches_pi_summary_then_kept_messages() {
        let mut log = SessionLog::memory();
        log.append(Event::UserMessage {
            content: "old".to_owned(),
        })
        .unwrap();
        log.append(Event::AssistantMessage {
            content: "drop me".to_owned(),
        })
        .unwrap();
        let kept = log
            .append(Event::UserMessage {
                content: "keep me".to_owned(),
            })
            .unwrap();
        log.append_compaction(
            "summary".to_owned(),
            kept,
            42,
            Some(json!({"kind": "test"})),
            None,
        )
        .unwrap();
        log.append(Event::AssistantMessage {
            content: "after".to_owned(),
        })
        .unwrap();

        let events = log.context_events();
        assert_eq!(events.len(), 3);
        assert!(
            matches!(&events[0], Event::UserMessage { content } if content.contains("summary"))
        );
        assert_eq!(
            events[1],
            Event::UserMessage {
                content: "keep me".to_owned()
            }
        );
        assert_eq!(
            events[2],
            Event::AssistantMessage {
                content: "after".to_owned()
            }
        );
        assert!(matches!(
            log.latest_compaction(),
            Some(FileEntry::Compaction { .. })
        ));
    }

    #[test]
    fn branch_summary_participates_in_context() {
        let mut log = SessionLog::memory();
        let first = log
            .append(Event::UserMessage {
                content: "first".to_owned(),
            })
            .unwrap();
        log.branch_with_summary(Some(first), "abandoned path".to_owned(), None, None)
            .unwrap();

        let events = log.context_events();
        assert_eq!(events.len(), 2);
        assert!(
            matches!(&events[1], Event::UserMessage { content } if content.contains("abandoned path"))
        );
    }

    #[test]
    fn metadata_labels_and_stats_match_pi_session_manager_shape() {
        let mut log = SessionLog::memory();
        let user = log
            .append(Event::UserMessage {
                content: "hello".to_owned(),
            })
            .unwrap();
        log.append(Event::ToolCall {
            id: "call_1".to_owned(),
            name: "bash".to_owned(),
            arguments: json!({ "command": "pwd" }),
        })
        .unwrap();
        log.append(Event::ToolResult {
            tool_call_id: "call_1".to_owned(),
            name: "bash".to_owned(),
            output: "/tmp".to_owned(),
            details: None,
        })
        .unwrap();
        log.append_session_info(Some("Work".to_owned())).unwrap();
        log.append_label_change(user.clone(), Some("start".to_owned()))
            .unwrap();
        log.append_model_change("openai".to_owned(), "gpt-4o-mini".to_owned())
            .unwrap();
        log.append_thinking_level_change(DEFAULT_THINKING_LEVEL.to_owned())
            .unwrap();

        let stats = log.stats();
        assert_eq!(log.get_session_name(), Some("Work"));
        assert_eq!(log.get_label(&user), Some("start"));
        assert_eq!(stats.user_messages, 1);
        assert_eq!(stats.assistant_messages, 1);
        assert_eq!(stats.tool_calls, 1);
        assert_eq!(stats.tool_results, 1);
    }

    #[test]
    fn forks_session_with_parent_header() {
        let source = temp_session_path("fork-source");
        let target = temp_session_path("fork-target");
        {
            let mut log = SessionLog::open(source.clone()).unwrap();
            log.append(Event::UserMessage {
                content: "hello".to_owned(),
            })
            .unwrap();
            log.append(Event::AssistantMessage {
                content: "hi".to_owned(),
            })
            .unwrap();
        }

        let fork = SessionLog::fork_from(&source, target).unwrap();

        assert_eq!(
            fork.header().parent_session.as_deref(),
            Some(source.display().to_string().as_str())
        );
        assert_eq!(fork.events().len(), 2);
    }

    #[test]
    fn creates_branched_session_from_selected_leaf() {
        let target = temp_session_path("branch-file");
        let mut log = SessionLog::memory();
        let first = log
            .append(Event::UserMessage {
                content: "first".to_owned(),
            })
            .unwrap();
        log.append(Event::AssistantMessage {
            content: "second".to_owned(),
        })
        .unwrap();

        let branched = log.create_branched_session(&first, target).unwrap();

        assert_eq!(branched.header().parent_session, None);
        assert_eq!(branched.entries().len(), 1);
        assert_eq!(
            branched.events(),
            &[Event::UserMessage {
                content: "first".to_owned()
            }]
        );
    }

    #[test]
    fn creates_continues_and_lists_session_summaries() {
        let session_dir = temp_session_dir("manager");
        let cwd = std::env::current_dir().unwrap();
        let session_path;
        {
            let mut log = SessionLog::create(cwd.clone(), Some(session_dir.clone())).unwrap();
            session_path = log.session_file().unwrap().to_path_buf();
            log.append_session_info(Some("Work".to_owned())).unwrap();
            log.append(Event::UserMessage {
                content: "first request".to_owned(),
            })
            .unwrap();
            log.append(Event::AssistantMessage {
                content: "first reply".to_owned(),
            })
            .unwrap();
        }

        let listed = SessionLog::list(cwd.clone(), Some(session_dir.clone())).unwrap();
        assert_eq!(listed.len(), 1);
        assert_eq!(listed[0].path, session_path);
        assert_eq!(listed[0].name.as_deref(), Some("Work"));
        assert_eq!(listed[0].message_count, 2);
        assert_eq!(listed[0].first_message.as_deref(), Some("first request"));
        assert!(listed[0].all_messages_text.contains("first reply"));

        let continued = SessionLog::continue_recent(cwd, Some(session_dir)).unwrap();
        assert_eq!(continued.session_file(), Some(session_path.as_path()));
        assert_eq!(continued.events().len(), 2);
    }

    #[test]
    fn defers_new_session_file_until_assistant_message_like_pi() {
        let session_dir = temp_session_dir("deferred");
        let cwd = std::env::current_dir().unwrap();
        let mut log = SessionLog::create(cwd, Some(session_dir)).unwrap();
        let session_path = log.session_file().unwrap().to_path_buf();

        assert!(!session_path.exists());

        log.append(Event::UserMessage {
            content: "prompt only".to_owned(),
        })
        .unwrap();
        assert!(!session_path.exists());

        log.append(Event::AssistantMessage {
            content: "reply".to_owned(),
        })
        .unwrap();

        let content = std::fs::read_to_string(session_path).unwrap();
        assert_eq!(content.lines().count(), 3);
        assert_eq!(
            serde_json::from_str::<Value>(content.lines().next().unwrap()).unwrap()["type"],
            "session"
        );
    }

    #[test]
    fn defers_prompt_only_branched_session_until_assistant_message_like_pi() {
        let target = temp_session_path("deferred-branch");
        let mut log = SessionLog::memory();
        let first = log
            .append(Event::UserMessage {
                content: "first".to_owned(),
            })
            .unwrap();

        let mut branched = log.create_branched_session(&first, target.clone()).unwrap();

        assert!(!target.exists());
        branched
            .append(Event::AssistantMessage {
                content: "reply".to_owned(),
            })
            .unwrap();
        assert!(target.exists());
    }

    #[test]
    fn lists_all_sessions_under_agent_sessions_root() {
        let agent_dir = temp_session_dir("agent-dir");
        let cwd = std::env::current_dir().unwrap();
        let session_dir = agent_dir.join("sessions").join(encode_cwd_for_session_dir(
            &resolved_display_path(&cwd).unwrap(),
        ));
        let mut log = SessionLog::create(cwd, Some(session_dir)).unwrap();
        log.append(Event::UserMessage {
            content: "hello".to_owned(),
        })
        .unwrap();
        log.append(Event::AssistantMessage {
            content: "hi".to_owned(),
        })
        .unwrap();

        let listed = SessionLog::list_all(Some(agent_dir)).unwrap();

        assert_eq!(listed.len(), 1);
        assert_eq!(listed[0].message_count, 2);
        assert_eq!(listed[0].first_message.as_deref(), Some("hello"));
    }

    #[test]
    fn tree_keeps_orphan_and_self_parent_entries_as_roots() {
        let header = new_header(
            Path::new("memory"),
            std::env::current_dir().unwrap().display().to_string(),
            None,
        );
        let entries = vec![
            FileEntry::Custom {
                id: "orphan".to_owned(),
                parent_id: Some("missing".to_owned()),
                timestamp: "2026-01-01T00:00:00.000Z".to_owned(),
                custom_type: "test".to_owned(),
                data: None,
            },
            FileEntry::Custom {
                id: "self".to_owned(),
                parent_id: Some("self".to_owned()),
                timestamp: "2026-01-01T00:00:01.000Z".to_owned(),
                custom_type: "test".to_owned(),
                data: None,
            },
        ];
        let log = SessionLog::from_parts(header, entries, None, None, false);

        let tree = log.get_tree();

        assert_eq!(tree.len(), 2);
        assert_eq!(entry_id(&tree[0].entry).as_deref(), Some("orphan"));
        assert_eq!(entry_id(&tree[1].entry).as_deref(), Some("self"));
    }

    #[test]
    fn builds_stable_bounded_session_ids() {
        let first = session_id(Path::new("/tmp/harness/session.jsonl"));
        let second = session_id(Path::new("/tmp/harness/session.jsonl"));

        assert_eq!(first, second);
        assert!(first.starts_with("harness_"));
        assert!(first.len() <= 64);
    }

    fn temp_session_path(name: &str) -> PathBuf {
        let path = std::env::temp_dir().join(format!(
            "harness-session-{name}-{}-{}.jsonl",
            std::process::id(),
            unix_millis()
        ));
        let _ = std::fs::remove_file(&path);
        path
    }

    fn temp_session_dir(name: &str) -> PathBuf {
        let path = std::env::temp_dir().join(format!(
            "harness-session-dir-{name}-{}-{}",
            std::process::id(),
            unix_millis()
        ));
        let _ = std::fs::remove_dir_all(&path);
        path
    }
}
