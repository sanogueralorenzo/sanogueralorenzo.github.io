"""Persistent thread sessions and Slack message ownership."""

import sqlite3
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class Session:
    command_key: str
    session_id: str
    workspace: Path
    context_ts: str


class State:
    def __init__(self, directory: Path):
        directory.mkdir(parents=True, exist_ok=True, mode=0o700)
        directory.chmod(0o700)
        path = directory / "sessions.sqlite3"
        self._db = sqlite3.connect(path)
        self._db.row_factory = sqlite3.Row
        path.chmod(0o600)
        self._db.executescript(
            """
            CREATE TABLE IF NOT EXISTS sessions (
                team TEXT NOT NULL, channel TEXT NOT NULL, thread_ts TEXT NOT NULL,
                command_key TEXT NOT NULL,
                session_id TEXT NOT NULL,
                workspace TEXT NOT NULL,
                context_ts TEXT NOT NULL,
                PRIMARY KEY (team, channel, thread_ts)
            );
            CREATE TABLE IF NOT EXISTS posted (
                team TEXT NOT NULL, channel TEXT NOT NULL, ts TEXT NOT NULL,
                command_key TEXT NOT NULL, session_id TEXT NOT NULL,
                PRIMARY KEY (team, channel, ts)
            );
            CREATE TABLE IF NOT EXISTS handled (
                team TEXT NOT NULL, channel TEXT NOT NULL, ts TEXT NOT NULL,
                PRIMARY KEY (team, channel, ts)
            );
            """
        )

    def seen(self, table, team, channel, ts):
        return self._db.execute(
            f"SELECT 1 FROM {table} WHERE team=? AND channel=? AND ts=?",
            (team, channel, ts),
        ).fetchone() is not None

    def session(self, team, channel, thread_ts) -> Session | None:
        row = self._db.execute(
            "SELECT command_key, session_id, workspace, context_ts FROM sessions WHERE team=? AND channel=? AND thread_ts=?",
            (team, channel, thread_ts),
        ).fetchone()
        if row is None:
            return None
        return Session(
            command_key=row["command_key"], session_id=row["session_id"],
            workspace=Path(row["workspace"]), context_ts=row["context_ts"],
        )

    def save_session(self, team, channel, thread_ts, session: Session):
        self._db.execute(
            "INSERT OR REPLACE INTO sessions (team, channel, thread_ts, command_key, session_id, workspace, context_ts) "
            "VALUES (?, ?, ?, ?, ?, ?, ?)",
            (team, channel, thread_ts, session.command_key, session.session_id, str(session.workspace), session.context_ts),
        )
        self._db.commit()

    def record_reply(self, team, channel, ts, command_key, session_id):
        self._db.execute(
            "INSERT INTO posted (team, channel, ts, command_key, session_id) VALUES (?, ?, ?, ?, ?)",
            (team, channel, ts, command_key, session_id),
        )
        self._db.commit()

    def knows_reply(self, team, channel, ts, command_key, session_id):
        return self._db.execute(
            "SELECT 1 FROM posted WHERE team=? AND channel=? AND ts=? AND command_key=? AND session_id=?",
            (team, channel, ts, command_key, session_id),
        ).fetchone() is not None

    def mark_handled(self, team, channel, ts):
        self._db.execute(
            "INSERT OR IGNORE INTO handled VALUES (?, ?, ?)",
            (team, channel, ts),
        )
        self._db.commit()

    def close(self):
        self._db.close()
