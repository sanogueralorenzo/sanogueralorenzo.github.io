use crate::shared::models::{DeleteResult, SessionMeta};
use anyhow::{Context, Result, anyhow, bail};
use chrono::{DateTime, SecondsFormat, TimeZone, Utc};
use rusqlite::{Connection, OptionalExtension, params};
use serde_json::Value;
use std::collections::{BTreeMap, HashMap, HashSet};
use std::fs::{self, File, OpenOptions};
use std::io::{BufRead, BufReader, Write};
use std::os::fd::AsRawFd;
use std::path::{Path, PathBuf};
use std::thread;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};
use uuid::Uuid;
use walkdir::WalkDir;

pub struct SessionStore {
    codex_home: PathBuf,
}

#[derive(Debug, Clone)]
pub struct UntitledThreadCandidate {
    pub id: String,
    pub updated_at: i64,
}

const TITLE_WRITE_LOCK_PATH: &str = ".locks/title-write.lock";
const TITLE_WRITE_LOCK_TIMEOUT: Duration = Duration::from_secs(10);
const TITLE_WRITE_LOCK_POLL_INTERVAL: Duration = Duration::from_millis(50);

#[derive(Debug)]
struct TitleWriteLock {
    file: File,
    lock_path: PathBuf,
}

impl Drop for TitleWriteLock {
    fn drop(&mut self) {
        let result = unsafe { libc::flock(self.file.as_raw_fd(), libc::LOCK_UN) };
        if result != 0 {
            let error = std::io::Error::last_os_error();
            eprintln!(
                "[codex-sessions:title-lock] release failed path={} error={}",
                self.lock_path.display(),
                error
            );
            return;
        }

        eprintln!(
            "[codex-sessions:title-lock] released path={}",
            self.lock_path.display()
        );
    }
}

include!("session_store/impl.rs");
include!("session_store/helpers.rs");
include!("session_store/tests.rs");
