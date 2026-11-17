use regex::Regex;
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::{
    collections::BTreeMap,
    env, fs,
    os::unix::fs::PermissionsExt,
    path::{Path, PathBuf},
    sync::LazyLock,
};
use unicode_casefold::UnicodeCaseFold;

pub fn folded(text: &str) -> String {
    text.case_fold().collect()
}
pub fn storage_json(value: &Value) -> String {
    match value {
        Value::String(s) => {
            let escaped = serde_json::to_string(s).unwrap();
            escaped
                .chars()
                .map(|c| {
                    if c as u32 >= 127 {
                        c.encode_utf16(&mut [0; 2])
                            .iter()
                            .map(|u| format!("\\u{u:04x}"))
                            .collect::<String>()
                    } else {
                        c.to_string()
                    }
                })
                .collect()
        }
        Value::Array(items) => format!(
            "[{}]",
            items
                .iter()
                .map(storage_json)
                .collect::<Vec<_>>()
                .join(", ")
        ),
        Value::Object(items) => {
            let mut keys: Vec<_> = items.keys().collect();
            keys.sort();
            format!(
                "{{{}}}",
                keys.into_iter()
                    .map(|k| format!(
                        "{}: {}",
                        storage_json(&Value::String(k.clone())),
                        storage_json(&items[k])
                    ))
                    .collect::<Vec<_>>()
                    .join(", ")
            )
        }
        _ => value.to_string(),
    }
}
#[derive(Clone, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct Command {
    pub start: Vec<String>,
    pub resume: Vec<String>,
}
#[derive(Deserialize)]
struct Raw {
    workspace: String,
    #[serde(default)]
    projects: BTreeMap<String, String>,
    commands: BTreeMap<String, Command>,
}
#[derive(Clone)]
pub struct Config {
    pub workspace: PathBuf,
    pub projects: Vec<(Regex, PathBuf)>,
    pub commands: BTreeMap<String, Command>,
}
fn path(text: &str) -> Result<PathBuf, String> {
    let p = if text == "~" || text.starts_with("~/") {
        PathBuf::from(env::var_os("HOME").ok_or("HOME is missing")?)
            .join(text.strip_prefix("~/").unwrap_or(""))
    } else {
        PathBuf::from(text)
    };
    let p = fs::canonicalize(p).map_err(|_| "Configured directories must exist")?;
    if !p.is_dir() {
        return Err("Configured directories must exist".into());
    }
    Ok(p)
}
fn executable(name: &str) -> Result<String, String> {
    let paths = if name.contains('/') {
        vec![PathBuf::from(name)]
    } else {
        env::split_paths(&env::var_os("PATH").unwrap_or_default())
            .map(|dir| dir.join(name))
            .collect()
    };
    paths
        .into_iter()
        .find(|p| {
            p.is_file()
                && p.metadata()
                    .is_ok_and(|m| m.permissions().mode() & 0o111 != 0)
        })
        .and_then(|p| fs::canonicalize(p).ok())
        .map(|p| p.to_string_lossy().into_owned())
        .ok_or_else(|| "Configured executable not found".into())
}
impl Config {
    pub fn load(file: &Path) -> Result<Self, String> {
        let raw: Raw =
            serde_json::from_slice(&fs::read(file).map_err(|_| "Configuration is missing")?)
                .map_err(|_| "Invalid configuration JSON")?;
        static KEYWORD: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"[\s\pC\pZ]").unwrap());
        static ALIAS: LazyLock<Regex> =
            LazyLock::new(|| Regex::new(r"\A[a-z][a-z0-9_-]*\z").unwrap());
        if raw.commands.is_empty() {
            return Err("Commands must not be empty".into());
        }
        let workspace = path(&raw.workspace)?;
        let mut commands = BTreeMap::new();
        for (key, mut command) in raw.commands {
            if !(1..=40).contains(&key.chars().count()) || KEYWORD.is_match(&key) {
                return Err("Keywords must be printable words".into());
            }
            let key = folded(&key);
            for (args, resume) in [(&mut command.start, false), (&mut command.resume, true)] {
                if args.is_empty()
                    || args.iter().any(|arg| arg.contains('\0'))
                    || args.iter().any(|a| a == "{session_id}") != resume
                {
                    return Err("Commands need start and resume argument arrays".into());
                }
                args[0] = executable(&args[0])?;
            }
            if commands.insert(key, command).is_some() {
                return Err("Duplicate keywords".into());
            }
        }
        let mut projects = Vec::new();
        for (alias, directory) in raw.projects {
            if !ALIAS.is_match(&alias) {
                return Err("Invalid project alias".into());
            }
            // Capture the whole word, checking boundaries separately (Rust regex has no look-around).
            let regex = Regex::new(&format!("(?i){}", regex::escape(&alias)))
                .map_err(|_| "Invalid alias")?;
            projects.push((regex, path(&directory)?));
        }
        Ok(Self {
            workspace,
            commands,
            projects,
        })
    }
    pub fn route(&self, text: &str) -> Result<(Command, Option<PathBuf>, String), String> {
        if text.is_empty() || text.starts_with(char::is_whitespace) || text.chars().count() > 12000
        {
            return Err("Invalid request".into());
        }
        let (key, request) = text
            .split_once(char::is_whitespace)
            .ok_or("Request needs a keyword and text")?;
        let request = request.trim();
        if request.is_empty() {
            return Err("Request is empty".into());
        }
        let command = self
            .commands
            .get(&folded(key))
            .ok_or("Unknown keyword")?
            .clone();
        static WORD: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"[\w-]").unwrap());
        let mut first = usize::MAX;
        let mut project = None;
        for (regex, directory) in &self.projects {
            for found in regex.find_iter(request) {
                let left = request[..found.start()].chars().next_back();
                let right = request[found.end()..].chars().next();
                if left.is_some_and(|c| WORD.is_match(&c.to_string()))
                    || right.is_some_and(|c| WORD.is_match(&c.to_string()))
                {
                    continue;
                }
                if found.start() < first {
                    first = found.start();
                    project = Some(directory.clone());
                }
                break;
            }
        }
        Ok((command, project, request.to_owned()))
    }
}
#[derive(Clone, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct Message {
    pub ts: String,
    pub user: String,
    pub text: String,
}
#[derive(Clone, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct Event {
    pub team: String,
    pub user: String,
    pub channel: String,
    pub ts: String,
    pub thread_ts: String,
    pub text: String,
    pub messages: Vec<Message>,
    pub history_after: Option<String>,
}
pub fn timestamp(text: &str) -> bool {
    static TS: LazyLock<Regex> =
        LazyLock::new(|| Regex::new(r"\A[0-9]{1,15}\.[0-9]{1,6}\z").unwrap());
    TS.is_match(text)
}
impl Event {
    pub fn validate(&self) -> Result<(), String> {
        static TEAM: LazyLock<Regex> =
            LazyLock::new(|| Regex::new(r"\A[A-Z][A-Z0-9]{1,30}\z").unwrap());
        static USER: LazyLock<Regex> =
            LazyLock::new(|| Regex::new(r"\A[UW][A-Z0-9]{1,30}\z").unwrap());
        static CHANNEL: LazyLock<Regex> =
            LazyLock::new(|| Regex::new(r"\A[CDG][A-Z0-9]{1,30}\z").unwrap());
        if !TEAM.is_match(&self.team)
            || !USER.is_match(&self.user)
            || !CHANNEL.is_match(&self.channel)
            || !timestamp(&self.ts)
            || !timestamp(&self.thread_ts)
            || self.history_after.as_ref().is_some_and(|ts| !timestamp(ts))
            || self.messages.len() > 1000
            || self
                .messages
                .iter()
                .any(|m| !timestamp(&m.ts) || m.text.chars().count() > 12000)
        {
            return Err("Invalid message envelope".into());
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn storage_identifiers_keep_the_persisted_json_format() {
        assert_eq!(
            storage_json(&json!(["ETEST", "🧪", "\u{7f}"])),
            r#"["ETEST", "\ud83e\uddea", "\u007f"]"#
        );
        assert_eq!(
            storage_json(&json!({"start":["cli"],"resume":["cli","{session_id}"]})),
            r#"{"resume": ["cli", "{session_id}"], "start": ["cli"]}"#
        );
    }
}
