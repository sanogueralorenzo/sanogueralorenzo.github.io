use super::{
    config::Command,
    errors::{HookError, WorkResult},
};
use serde_json::Value;
use std::{
    io::{Seek, Write},
    path::Path,
    process::Stdio,
    time::Duration,
};
use tokio::{
    io::{AsyncRead, AsyncReadExt},
    process::Command as Process,
    sync::watch,
};

pub type Cancel = watch::Sender<bool>;
pub struct Reply {
    pub session: String,
    pub answer: String,
    pub chat_url: Option<String>,
}
pub async fn cancelled(cancel: &Cancel) {
    let mut receiver = cancel.subscribe();
    if !*receiver.borrow_and_update() {
        let _ = receiver.changed().await;
    }
}
struct Group(Option<u32>);
impl Group {
    fn kill(&mut self) {
        if let Some(pid) = self.0.take() {
            unsafe {
                libc::kill(-(pid as i32), libc::SIGKILL);
            }
        }
    }
}
impl Drop for Group {
    fn drop(&mut self) {
        self.kill();
    }
}
async fn bounded(mut stream: impl AsyncRead + Unpin) -> WorkResult<Vec<u8>> {
    let mut bytes = Vec::new();
    let mut chunk = [0u8; 8192];
    loop {
        let n = stream
            .read(&mut chunk)
            .await
            .map_err(|_| HookError::new("command_failed"))?;
        if n == 0 {
            return Ok(bytes);
        }
        if bytes.len() + n > 1024 * 1024 {
            return Err(HookError::new("output_limit"));
        }
        bytes.extend_from_slice(&chunk[..n]);
    }
}
pub async fn execute(
    command: &Command,
    prompt: &str,
    workspace: &Path,
    session: Option<&str>,
    seconds: f64,
    cancel: &Cancel,
) -> WorkResult<Reply> {
    let args = if session.is_some() {
        &command.resume
    } else {
        &command.start
    };
    let args: Vec<_> = args
        .iter()
        .map(|a| {
            if a == "{session_id}" {
                session.unwrap_or("")
            } else {
                a.as_str()
            }
        })
        .collect();
    let mut input = tempfile::tempfile().map_err(|_| HookError::new("command_failed"))?;
    input
        .write_all(prompt.as_bytes())
        .map_err(|_| HookError::new("command_failed"))?;
    input
        .rewind()
        .map_err(|_| HookError::new("command_failed"))?;
    let mut cmd = Process::new(args[0]);
    cmd.args(&args[1..])
        .current_dir(workspace)
        .stdin(Stdio::from(input))
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .kill_on_drop(true);
    for (key, _) in std::env::vars_os() {
        if key.to_str().is_some_and(|k| {
            k.starts_with("SLACK_")
                || k.starts_with("AGENT_SLACK_")
                || k.starts_with("BROWSER_HOOKS_")
        }) {
            cmd.env_remove(key);
        }
    }
    unsafe {
        cmd.pre_exec(|| {
            if libc::setsid() < 0 {
                Err(std::io::Error::last_os_error())
            } else {
                Ok(())
            }
        });
    }
    let mut child = cmd.spawn().map_err(|e| {
        HookError::new(if e.kind() == std::io::ErrorKind::NotFound {
            "missing_cli"
        } else {
            "command_failed"
        })
    })?;
    let mut group = Group(Some(
        child.id().ok_or_else(|| HookError::new("command_failed"))?,
    ));
    let stdout = child.stdout.take().unwrap();
    let stderr = child.stderr.take().unwrap();
    let result = {
        let work = async {
            let wait = async {
                let result = child
                    .wait()
                    .await
                    .map_err(|_| HookError::new("command_failed"));
                group.kill();
                result
            };
            let (stdout, _stderr, status) =
                tokio::try_join!(bounded(stdout), bounded(stderr), wait)?;
            Ok::<_, HookError>((stdout, status))
        };
        tokio::select! {
            biased;
            _=cancelled(cancel)=>Err(HookError::new("cancelled")),
            result=tokio::time::timeout(Duration::from_secs_f64(seconds),work)=>result.unwrap_or_else(|_|Err(HookError::new("timeout"))),
        }
    };
    // Kill descendants on every outcome, including when the group leader exits first.
    drop(group);
    let _ = child.wait().await;
    let (stdout, status) = result?;
    let value: Value = serde_json::from_slice(&stdout).map_err(|_| {
        HookError::new(if status.success() {
            "invalid_response"
        } else {
            "command_failed"
        })
    })?;
    if let Some(error) = HookError::from_value(&value) {
        return Err(error);
    }
    if !status.success() {
        return Err(HookError::new("command_failed"));
    }
    let returned = value["session_id"]
        .as_str()
        .ok_or_else(|| HookError::new("invalid_response"))?;
    let answer = value["answer"]
        .as_str()
        .ok_or_else(|| HookError::new("invalid_response"))?;
    if !(1..=200).contains(&returned.chars().count())
        || returned.trim().is_empty()
        || answer.trim().is_empty()
        || answer.chars().count() > 12000
    {
        return Err(HookError::new("invalid_response"));
    }
    if session.is_some_and(|s| s != returned) {
        return Err(HookError::new("session_invalid"));
    }
    let chat_url = match value.get("chat_url") {
        None => None,
        Some(Value::String(url))
            if url.len() <= 2048
                && !url
                    .chars()
                    .any(|c| c.is_whitespace() || c.is_control() || "()[]<>\\\"".contains(c))
                && url.parse::<axum::http::Uri>().is_ok_and(|uri| {
                    matches!(uri.scheme_str(), Some("http" | "https" | "codex"))
                        && uri.authority().is_some()
                }) =>
        {
            Some(url.clone())
        }
        _ => return Err(HookError::new("invalid_response")),
    };
    Ok(Reply {
        session: returned.into(),
        answer: answer.trim().into(),
        chat_url,
    })
}
