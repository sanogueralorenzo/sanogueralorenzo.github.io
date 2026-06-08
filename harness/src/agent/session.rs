use std::fs::{File, OpenOptions};
use std::io::Write;
use std::path::{Path, PathBuf};

use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};
use serde_json::Value;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
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
    ToolResult {
        tool_call_id: String,
        name: String,
        output: String,
    },
    TurnFinished {
        index: usize,
    },
    JobFinished,
}

pub struct SessionLog {
    events: Vec<Event>,
    file: Option<File>,
}

impl SessionLog {
    pub fn open(path: PathBuf) -> Result<Self> {
        ensure_parent_dir(&path)?;
        let events = read_events(&path)?;
        let file = OpenOptions::new()
            .create(true)
            .append(true)
            .open(&path)
            .with_context(|| format!("open session log {}", path.display()))?;

        Ok(Self {
            events,
            file: Some(file),
        })
    }

    #[cfg(test)]
    pub fn memory() -> Self {
        Self {
            events: Vec::new(),
            file: None,
        }
    }

    pub fn events(&self) -> &[Event] {
        &self.events
    }

    pub fn append(&mut self, event: Event) -> Result<()> {
        if let Some(file) = self.file.as_mut() {
            let line = serde_json::to_string(&event)?;
            writeln!(file, "{line}")?;
            file.flush()?;
        }
        self.events.push(event);
        Ok(())
    }
}

fn ensure_parent_dir(path: &Path) -> Result<()> {
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent)
            .with_context(|| format!("create session directory {}", parent.display()))?;
    }
    Ok(())
}

fn read_events(path: &Path) -> Result<Vec<Event>> {
    if !path.exists() {
        return Ok(Vec::new());
    }

    let content = std::fs::read_to_string(path)
        .with_context(|| format!("read session log {}", path.display()))?;
    let mut events = Vec::new();
    for (index, line) in content.lines().enumerate() {
        if line.trim().is_empty() {
            continue;
        }
        let event = serde_json::from_str(line)
            .with_context(|| format!("parse {} line {}", path.display(), index + 1))?;
        events.push(event);
    }
    Ok(events)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn appends_memory_events() {
        let mut log = SessionLog::memory();

        log.append(Event::JobStarted).unwrap();
        log.append(Event::UserMessage {
            content: "hello".to_owned(),
        })
        .unwrap();

        assert_eq!(log.events().len(), 2);
    }
}
