pub mod config;
mod errors;
mod process;
mod runtime;
mod storage;

use crate::server::{ApiResult, fail};
use axum::http::{Method, StatusCode};
use config::Config;
use regex::Regex;
use runtime::Runtime;
use serde_json::{Value, json};
use std::{
    fs,
    os::unix::fs::PermissionsExt,
    path::Path,
    sync::{Arc, LazyLock},
};
use tokio::sync::broadcast;

pub struct Slack {
    runtime: Arc<Runtime>,
}
impl Slack {
    pub fn new(home: &Path) -> Result<Self, String> {
        let folder = home.join("hooks/slack");
        let config = Config::load(&folder.join("config.json"))?;
        let runtime = Runtime::new(config, &folder)?;
        for (path, mode) in [(&folder, 0o700), (&folder.join("sessions.sqlite3"), 0o600)] {
            fs::set_permissions(path, fs::Permissions::from_mode(mode))
                .map_err(|_| "Cannot secure Slack state")?;
        }
        Ok(Self { runtime })
    }
    pub fn config(&self) -> Value {
        json!({"keywords":self.runtime.config.commands.keys().collect::<Vec<_>>()})
    }
    pub fn error(&self) -> Value {
        self.runtime.last_error()
    }
    pub fn events(&self) -> broadcast::Receiver<Value> {
        self.runtime.events.subscribe()
    }
    pub fn resume(&self) -> Result<(), String> {
        self.runtime.resume()
    }
    pub async fn close(&self) {
        self.runtime.close().await;
    }
    pub fn request(&self, method: Method, path: &str, body: Value) -> ApiResult<Value> {
        let action = if method == Method::GET && path.starts_with("/jobs/") {
            return self
                .runtime
                .status(path.strip_prefix("/jobs/").unwrap())
                .map_err(|_| {
                    (
                        StatusCode::INTERNAL_SERVER_ERROR,
                        "Local bridge storage failed",
                    )
                })?
                .ok_or((StatusCode::NOT_FOUND, "Unknown job"));
        } else if method == Method::POST && path == "/run" {
            self.runtime.submit(body)
        } else if method == Method::POST && path == "/recover" {
            self.runtime.recover(body)
        } else if method == Method::POST && ["/claim", "/cancel", "/delivered"].contains(&path) {
            static JOB: LazyLock<Regex> =
                LazyLock::new(|| Regex::new(r"\A[a-f0-9]{64}\z").unwrap());
            let job = body["job"]
                .as_str()
                .filter(|j| JOB.is_match(j))
                .ok_or(fail("Invalid job"))?;
            match path {
                "/claim" => self.runtime.claim(job),
                "/cancel" => self.runtime.cancel(job),
                _ => self.runtime.delivered(
                    job,
                    body["ts"].as_str().ok_or(fail("Invalid reply timestamp"))?,
                ),
            }
        } else {
            return Err((StatusCode::NOT_FOUND, "Unknown endpoint"));
        };
        action.map_err(|message| {
            if message.starts_with("Local bridge") || message == "Bridge is stopping" {
                (StatusCode::INTERNAL_SERVER_ERROR, "Local bridge failed")
            } else {
                fail("Invalid request or configuration")
            }
        })
    }
}
