use super::{
    config::{Command, Event},
    errors::HookError,
};
use rusqlite::{Connection, OptionalExtension, Params, params};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use std::{
    collections::HashSet,
    fs::File,
    os::{fd::AsRawFd, unix::fs::OpenOptionsExt},
    path::{Path, PathBuf},
};

fn error(_: rusqlite::Error) -> String {
    "Local bridge storage failed".into()
}

fn timestamp_key(ts: &str) -> String {
    // Pad validated Slack timestamps so text comparisons preserve microsecond order.
    let (seconds, fraction) = ts.split_once('.').unwrap();
    format!("{seconds:0>15}.{fraction:0<6}")
}

fn open_db(folder: &Path) -> Result<(Connection, File), String> {
    std::fs::create_dir_all(folder).map_err(|_| "Cannot create private state")?;
    let path = folder.join("sessions.sqlite3");
    let owner = File::options()
        .read(true)
        .write(true)
        .create(true)
        .truncate(false)
        .mode(0o600)
        .open(folder.join("sessions.lock"))
        .map_err(|_| "Cannot open private state")?;
    if unsafe { libc::flock(owner.as_raw_fd(), libc::LOCK_EX | libc::LOCK_NB) } != 0 {
        return Err("Browser Hooks is already running for this data folder".into());
    }
    let mut db = Connection::open(path).map_err(error)?;
    let tx = db.transaction().map_err(error)?;
    tx.execute_batch(
        "CREATE TABLE IF NOT EXISTS jobs (id TEXT PRIMARY KEY, thread TEXT, status TEXT, answer TEXT, request TEXT, session TEXT);
         CREATE TABLE IF NOT EXISTS sessions (thread TEXT PRIMARY KEY, command TEXT, workspace TEXT, session TEXT, context_ts TEXT, answered INTEGER NOT NULL DEFAULT 0);
         CREATE TABLE IF NOT EXISTS replies (thread TEXT, ts TEXT, session TEXT, PRIMARY KEY(thread, ts));
         CREATE TABLE IF NOT EXISTS stops (thread TEXT NOT NULL, keyword TEXT NOT NULL, ts TEXT NOT NULL, PRIMARY KEY(thread, keyword));",
    ).map_err(error)?;
    for (table, name, declaration) in [
        ("sessions", "answered", "INTEGER NOT NULL DEFAULT 1"),
        ("jobs", "request", "TEXT"),
        ("jobs", "session", "TEXT"),
    ] {
        let exists = tx
            .prepare(&format!("PRAGMA table_info({table})"))
            .map_err(error)?
            .query_map([], |r| r.get::<_, String>(1))
            .map_err(error)?
            .collect::<Result<Vec<_>, _>>()
            .map_err(error)?
            .iter()
            .any(|column| column == name);
        if !exists {
            tx.execute(
                &format!("ALTER TABLE {table} ADD COLUMN {name} {declaration}"),
                [],
            )
            .map_err(error)?;
        }
    }
    // Native CLI calls may already have changed files. Recover their session, never replay the call.
    tx.execute(
        "UPDATE jobs SET status='failed',answer=?1 WHERE status='running' OR (status='queued' AND request IS NULL)",
        [HookError::new("interrupted").public().to_string()],
    ).map_err(error)?;
    tx.commit().map_err(error)?;
    Ok((db, owner))
}

#[derive(Deserialize, Serialize)]
pub struct Request {
    pub event: Event,
    pub command: Command,
    pub project: Option<PathBuf>,
    pub request: String,
    pub workspace: PathBuf,
}
pub struct Session {
    pub command_key: String,
    pub workspace: PathBuf,
    pub session_id: String,
    pub context_ts: String,
    pub answered: bool,
}
pub struct Job {
    pub id: String,
    pub thread: String,
    pub input: Request,
}
pub struct Storage {
    db: Connection,
    _owner: File,
}
impl Storage {
    pub fn open(folder: &Path) -> Result<Self, String> {
        let (db, owner) = open_db(folder)?;
        Ok(Self { db, _owner: owner })
    }
    fn jobs(db: &Connection, sql: &str, args: impl Params) -> Result<Vec<Job>, String> {
        let mut statement = db.prepare(sql).map_err(error)?;
        let rows = statement
            .query_map(args, |r| {
                Ok((
                    r.get::<_, String>(0)?,
                    r.get::<_, String>(1)?,
                    r.get::<_, String>(2)?,
                ))
            })
            .map_err(error)?;
        rows.map(|row| {
            let (id, thread, input) = row.map_err(error)?;
            let input = serde_json::from_str(&input)
                .map_err(|_| "Local bridge saved request is invalid")?;
            Ok(Job { id, thread, input })
        })
        .collect()
    }
    pub fn queued(&self) -> Result<Vec<Job>, String> {
        Self::jobs(
            &self.db,
            "SELECT id,thread,request FROM jobs WHERE status='queued' ORDER BY rowid",
            [],
        )
    }
    pub fn pending(&self, thread: &str) -> Result<Vec<Job>, String> {
        Self::jobs(
            &self.db,
            "SELECT id,thread,request FROM jobs WHERE thread=?1 AND status IN ('queued','running')",
            [thread],
        )
    }
    pub fn recover(&self, team: &str, user: &str) -> Result<Vec<Job>, String> {
        Self::jobs(
            &self.db,
            "SELECT id,thread,request FROM jobs WHERE request IS NOT NULL AND status IN ('queued','running','ready','failed') AND json_extract(thread,'$[0]')=?1 AND json_extract(thread,'$[1]')=?2 ORDER BY rowid",
            [team, user],
        )
    }
    pub fn session(&self, thread: &str) -> Result<Option<Session>, String> {
        self.db.query_row(
            "SELECT command,workspace,session,context_ts,answered FROM sessions WHERE thread=?1",
            [thread], |r| Ok(Session {
                command_key:r.get(0)?, workspace:PathBuf::from(r.get::<_,String>(1)?),
                session_id:r.get(2)?, context_ts:r.get(3)?, answered:r.get(4)?,
            }),
        ).optional().map_err(error)
    }
    pub fn known_replies(
        &self,
        thread: &str,
        session: Option<&str>,
    ) -> Result<HashSet<String>, String> {
        let mut statement = self
            .db
            .prepare("SELECT ts FROM replies WHERE thread=?1 AND session=?2")
            .map_err(error)?;
        statement
            .query_map(params![thread, session], |r| r.get(0))
            .map_err(error)?
            .collect::<Result<_, _>>()
            .map_err(error)
    }
    pub fn status(&self, job: &str) -> Result<Option<Value>, String> {
        let row = self
            .db
            .query_row("SELECT status,answer FROM jobs WHERE id=?1", [job], |r| {
                Ok((r.get::<_, String>(0)?, r.get::<_, Option<String>>(1)?))
            })
            .optional()
            .map_err(error)?;
        Ok(row.map(|(status, answer)| {
            let mut value = json!({"job":job,"status":status});
            if status == "ready" {
                value["answer"] = json!(answer);
            }
            if status == "failed" {
                let stored: Value = answer
                    .and_then(|a| serde_json::from_str(&a).ok())
                    .unwrap_or(Value::Null);
                value["error"] = HookError::from_parts(
                    stored["code"].as_str().unwrap_or(""),
                    stored["provider"].as_str().unwrap_or(""),
                )
                .public();
            }
            value
        }))
    }
    pub fn admit(&self, job: &str, thread: &str, input: &Request) -> Result<bool, String> {
        // An in-flight request can reach the bridge after the stop that covers it.
        let cancelled: bool = self
            .db
            .query_row(
                "SELECT EXISTS(SELECT 1 FROM stops WHERE thread=?1 AND keyword=?2 AND ts>?3)",
                params![
                    thread,
                    input.event.keyword(),
                    timestamp_key(&input.event.ts)
                ],
                |row| row.get(0),
            )
            .map_err(error)?;
        if cancelled {
            self.db
                .execute(
                    "INSERT INTO jobs (id,thread,status) VALUES (?1,?2,'cancelled')",
                    params![job, thread],
                )
                .map_err(error)?;
            return Ok(false);
        }
        let count: i64 = self.db.query_row("SELECT count(*) FROM jobs WHERE status IN ('queued','running','ready','failed') AND request IS NOT NULL", [], |r| r.get(0)).map_err(error)?;
        if count >= 100 {
            return Err("Command queue is full".into());
        }
        self.db
            .execute(
                "INSERT INTO jobs (id,thread,status,request) VALUES (?1,?2,'queued',?3)",
                params![job, thread, serde_json::to_string(input).unwrap()],
            )
            .map_err(error)?;
        Ok(true)
    }
    pub fn stop(
        &mut self,
        job: &str,
        thread: &str,
        input: &Request,
    ) -> Result<Vec<String>, String> {
        let keyword = input.event.keyword();
        let cutoff = timestamp_key(&input.event.ts);
        let tx = self.db.transaction().map_err(error)?;
        tx.execute(
            "INSERT INTO stops (thread,keyword,ts) VALUES (?1,?2,?3)
             ON CONFLICT(thread,keyword) DO UPDATE SET ts=MAX(stops.ts,excluded.ts)",
            params![thread, keyword, cutoff],
        )
        .map_err(error)?;
        let stopped: Vec<_> = Self::jobs(
            &tx,
            "SELECT id,thread,request FROM jobs WHERE thread=?1 AND request IS NOT NULL AND status IN ('queued','running','ready','failed')",
            [thread],
        )?
        .into_iter()
        .filter(|job| {
            job.input.event.keyword() == keyword && timestamp_key(&job.input.event.ts) < cutoff
        })
        .map(|job| job.id)
        .collect();
        for id in &stopped {
            tx.execute(
                "UPDATE jobs SET status='cancelled',answer=NULL,request=NULL WHERE id=?1",
                [id],
            )
            .map_err(error)?;
        }
        let answer = if stopped.is_empty() {
            format!("No pending {keyword} requests in this thread.")
        } else {
            format!("Stopping {keyword} requests in this thread.")
        };
        tx.execute(
            "INSERT INTO jobs (id,thread,status,answer,request,session) VALUES (?1,?2,'ready',?3,?4,(SELECT session FROM sessions WHERE thread=?2))",
            params![job,thread,answer,serde_json::to_string(input).unwrap()],
        ).map_err(error)?;
        tx.commit().map_err(error)?;
        Ok(stopped)
    }
    pub fn start(&self, job: &str) -> Result<bool, String> {
        self.db
            .execute(
                "UPDATE jobs SET status='running' WHERE id=?1 AND status='queued'",
                [job],
            )
            .map(|n| n == 1)
            .map_err(error)
    }
    pub fn fail(&self, job: &str, failure: &HookError) -> Result<(), String> {
        self.db
            .execute(
                "UPDATE jobs SET status='failed',answer=?1 WHERE id=?2 AND status='running'",
                params![failure.public().to_string(), job],
            )
            .map_err(error)?;
        Ok(())
    }
    fn save_session(db: &Connection, thread: &str, session: &Session) -> rusqlite::Result<()> {
        db.execute(
            "INSERT OR REPLACE INTO sessions (thread,command,workspace,session,context_ts,answered) VALUES (?1,?2,?3,?4,?5,?6)",
            params![thread,session.command_key,session.workspace.to_string_lossy(),session.session_id,session.context_ts,session.answered],
        )?;
        Ok(())
    }
    pub fn checkpoint(&mut self, job: &str, thread: &str, session: &Session) -> Result<(), String> {
        let tx = self.db.transaction().map_err(error)?;
        Self::save_session(&tx, thread, session).map_err(error)?;
        tx.execute(
            "UPDATE jobs SET session=?1 WHERE id=?2",
            params![session.session_id, job],
        )
        .map_err(error)?;
        tx.commit().map_err(error)
    }
    pub fn complete(
        &mut self,
        job: &str,
        thread: &str,
        session: &Session,
        answer: &str,
    ) -> Result<(), String> {
        let tx = self.db.transaction().map_err(error)?;
        Self::save_session(&tx, thread, session).map_err(error)?;
        tx.execute(
            "UPDATE jobs SET status='ready',answer=?1 WHERE id=?2",
            params![answer, job],
        )
        .map_err(error)?;
        tx.commit().map_err(error)
    }
    pub fn claim(&self, job: &str) -> Result<bool, String> {
        self.db
            .execute(
                "UPDATE jobs SET status='sending' WHERE id=?1 AND status IN ('ready','failed')",
                [job],
            )
            .map(|n| n == 1)
            .map_err(error)
    }
    pub fn delivered(&mut self, job: &str, ts: &str) -> Result<bool, String> {
        let tx = self.db.transaction().map_err(error)?;
        let delivered: Option<(String, Option<String>)> = tx
            .query_row(
                "SELECT thread,session FROM jobs WHERE id=?1 AND status='sending'",
                [job],
                |r| Ok((r.get(0)?, r.get(1)?)),
            )
            .optional()
            .map_err(error)?;
        if let Some((thread, session)) = &delivered {
            if let Some(session) = session {
                tx.execute(
                    "INSERT OR IGNORE INTO replies VALUES (?1,?2,?3)",
                    params![thread, ts, session],
                )
                .map_err(error)?;
            }
            tx.execute(
                "UPDATE jobs SET status='delivered',answer=NULL,request=NULL WHERE id=?1",
                [job],
            )
            .map_err(error)?;
        }
        tx.commit().map_err(error)?;
        Ok(delivered.is_some())
    }
}
pub fn thread_key(event: &Event) -> String {
    storage_json(&json!([
        event.team,
        event.user,
        event.channel,
        event.thread_ts
    ]))
}
pub fn job_id(event: &Event) -> String {
    format!(
        "{:x}",
        Sha256::digest(
            storage_json(&json!([event.team, event.user, event.channel, event.ts])).as_bytes()
        )
    )
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
