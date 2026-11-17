use super::errors::HookError;
use rusqlite::Connection;
use std::{
    fs::File,
    os::{fd::AsRawFd, unix::fs::OpenOptionsExt},
    path::Path,
};

pub fn error(_: rusqlite::Error) -> String {
    "Local bridge storage failed".into()
}

pub fn open(folder: &Path) -> Result<(Connection, File), String> {
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
         CREATE TABLE IF NOT EXISTS replies (thread TEXT, ts TEXT, session TEXT, PRIMARY KEY(thread, ts));",
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
