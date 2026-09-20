import { chmodSync, existsSync, lstatSync, mkdirSync } from "node:fs";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { randomUUID } from "node:crypto";
import type { Memory, Message, Session, WorkKind } from "./types.js";

interface SessionRow {
  id: string;
  scope_key: string;
  kind: WorkKind;
  cwd: string | null;
  title: string;
  summary: string;
  created_at: string;
  updated_at: string;
}

interface MessageRow {
  id: number;
  session_id: string;
  role: Message["role"];
  content: string;
  created_at: string;
}

interface MemoryRow {
  id: number;
  scope: string;
  content: string;
  source_session_id: string | null;
  created_at: string;
  updated_at: string;
}

const now = () => new Date().toISOString();

function toSession(row: SessionRow): Session {
  return {
    id: row.id,
    scopeKey: row.scope_key,
    kind: row.kind,
    cwd: row.cwd,
    title: row.title,
    summary: row.summary,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

function toMessage(row: MessageRow): Message {
  return {
    id: row.id,
    sessionId: row.session_id,
    role: row.role,
    content: row.content,
    createdAt: row.created_at,
  };
}

function toMemory(row: MemoryRow): Memory {
  return {
    id: row.id,
    scope: row.scope,
    content: row.content,
    sourceSessionId: row.source_session_id,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

export class Store {
  readonly db: DatabaseSync;

  constructor(homeDir: string, filename = "a1r.sqlite", options: { recoverRuns?: boolean } = {}) {
    mkdirSync(homeDir, { recursive: true, mode: 0o700 });
    const homeStat = lstatSync(homeDir);
    if (homeStat.isSymbolicLink()) throw new Error("A1R_HOME must not be a symbolic link.");
    if (typeof process.getuid === "function" && homeStat.uid !== process.getuid()) throw new Error("A1R_HOME is owned by another user.");
    chmodSync(homeDir, 0o700);
    const databasePath = join(homeDir, filename);
    if (existsSync(databasePath) && lstatSync(databasePath).isSymbolicLink()) throw new Error("A1R database must not be a symbolic link.");
    this.db = new DatabaseSync(databasePath);
    chmodSync(databasePath, 0o600);
    this.db.exec("PRAGMA journal_mode = WAL; PRAGMA foreign_keys = ON; PRAGMA busy_timeout = 5000;");
    this.migrate();
    if (options.recoverRuns !== false) this.recoverInterruptedRuns();
  }

  private migrate(): void {
    this.db.exec(`
      CREATE TABLE IF NOT EXISTS sessions (
        id TEXT PRIMARY KEY,
        scope_key TEXT NOT NULL UNIQUE,
        kind TEXT NOT NULL CHECK (kind IN ('personal', 'coding')),
        cwd TEXT,
        title TEXT NOT NULL,
        summary TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      );
      CREATE TABLE IF NOT EXISTS messages (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
        role TEXT NOT NULL CHECK (role IN ('user', 'assistant', 'tool')),
        content TEXT NOT NULL,
        created_at TEXT NOT NULL
      );
      CREATE INDEX IF NOT EXISTS messages_session_id ON messages(session_id, id);
      CREATE TABLE IF NOT EXISTS memories (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        scope TEXT NOT NULL,
        content TEXT NOT NULL,
        source_session_id TEXT REFERENCES sessions(id) ON DELETE SET NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        UNIQUE(scope, content)
      );
      CREATE INDEX IF NOT EXISTS memories_scope ON memories(scope, updated_at DESC);
      CREATE TABLE IF NOT EXISTS runs (
        id TEXT PRIMARY KEY,
        session_id TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
        state TEXT NOT NULL CHECK (state IN ('running', 'complete', 'interrupted', 'failed')),
        response_id TEXT,
        output TEXT NOT NULL DEFAULT '',
        error TEXT,
        started_at TEXT NOT NULL,
        finished_at TEXT
      );
      CREATE INDEX IF NOT EXISTS runs_session_id ON runs(session_id, started_at DESC);
      CREATE TABLE IF NOT EXISTS gateway_links (
        gateway TEXT NOT NULL,
        external_id TEXT NOT NULL,
        session_id TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
        created_at TEXT NOT NULL,
        PRIMARY KEY(gateway, external_id)
      );
      CREATE TABLE IF NOT EXISTS settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL,
        updated_at TEXT NOT NULL
      );
      CREATE TABLE IF NOT EXISTS backend_sessions (
        session_id TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
        backend TEXT NOT NULL,
        external_id TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        PRIMARY KEY(session_id, backend),
        UNIQUE(backend, external_id)
      );
    `);
    const runColumns = this.db.prepare("PRAGMA table_info(runs)").all() as unknown as Array<{ name: string }>;
    if (!runColumns.some((column) => column.name === "output")) {
      this.db.exec("ALTER TABLE runs ADD COLUMN output TEXT NOT NULL DEFAULT ''");
    }
  }

  private recoverInterruptedRuns(): void {
    this.db.prepare(`
      INSERT INTO messages (session_id, role, content, created_at)
      SELECT session_id, 'assistant', output || char(10) || char(10) || '[interrupted]', ?
      FROM runs WHERE state = 'running' AND output <> ''
    `).run(now());
    this.db.prepare("UPDATE runs SET state = 'interrupted', finished_at = ? WHERE state = 'running'").run(now());
  }

  resolveSession(input: {
    sessionId?: string;
    scopeKey: string;
    kind: WorkKind;
    cwd?: string;
    title?: string;
  }): Session {
    if (input.sessionId) {
      const exact = this.getSession(input.sessionId);
      if (exact) return exact;
    }

    const existing = this.db.prepare(`
      SELECT * FROM sessions
      WHERE scope_key = ? OR instr(scope_key, ? || ':') = 1
      ORDER BY updated_at DESC LIMIT 1
    `).get(input.scopeKey, input.scopeKey) as SessionRow | undefined;
    if (existing) {
      this.db.prepare("UPDATE sessions SET updated_at = ? WHERE id = ?").run(now(), existing.id);
      return toSession({ ...existing, updated_at: now() });
    }

    const timestamp = now();
    const id = randomUUID();
    this.db.prepare(`
      INSERT INTO sessions (id, scope_key, kind, cwd, title, summary, created_at, updated_at)
      VALUES (?, ?, ?, ?, ?, '', ?, ?)
    `).run(id, input.scopeKey, input.kind, input.cwd ?? null, input.title ?? "New conversation", timestamp, timestamp);
    return this.getSession(id)!;
  }

  getSession(id: string): Session | null {
    const row = this.db.prepare("SELECT * FROM sessions WHERE id = ?").get(id) as SessionRow | undefined;
    return row ? toSession(row) : null;
  }

  listSessions(limit = 20): Session[] {
    const rows = this.db.prepare("SELECT * FROM sessions ORDER BY updated_at DESC LIMIT ?").all(limit) as unknown as SessionRow[];
    return rows.map(toSession);
  }

  latestSession(kind: WorkKind): Session | null {
    const row = this.db.prepare("SELECT * FROM sessions WHERE kind = ? ORDER BY updated_at DESC LIMIT 1").get(kind) as SessionRow | undefined;
    return row ? toSession(row) : null;
  }

  addMessage(sessionId: string, role: Message["role"], content: string): Message {
    const timestamp = now();
    const result = this.db.prepare("INSERT INTO messages (session_id, role, content, created_at) VALUES (?, ?, ?, ?)")
      .run(sessionId, role, content, timestamp);
    this.db.prepare("UPDATE sessions SET updated_at = ? WHERE id = ?").run(timestamp, sessionId);
    return {
      id: Number(result.lastInsertRowid),
      sessionId,
      role,
      content,
      createdAt: timestamp,
    };
  }

  getMessages(sessionId: string, limit = 40): Message[] {
    const rows = this.db.prepare(`
      SELECT * FROM (
        SELECT * FROM messages WHERE session_id = ? ORDER BY id DESC LIMIT ?
      ) ORDER BY id ASC
    `).all(sessionId, limit) as unknown as MessageRow[];
    return rows.map(toMessage);
  }

  remember(scope: string, content: string, sourceSessionId?: string): Memory {
    const timestamp = now();
    this.db.prepare(`
      INSERT INTO memories (scope, content, source_session_id, created_at, updated_at)
      VALUES (?, ?, ?, ?, ?)
      ON CONFLICT(scope, content) DO UPDATE SET updated_at = excluded.updated_at
    `).run(scope, content.trim(), sourceSessionId ?? null, timestamp, timestamp);
    const row = this.db.prepare("SELECT * FROM memories WHERE scope = ? AND content = ?")
      .get(scope, content.trim()) as unknown as MemoryRow;
    return toMemory(row);
  }

  searchMemories(scope: string, query: string, limit = 8): Memory[] {
    const words = query.toLowerCase().split(/\W+/).filter((word) => word.length > 2).slice(0, 8);
    const rows = this.db.prepare("SELECT * FROM memories WHERE scope IN (?, 'global') ORDER BY updated_at DESC LIMIT 100")
      .all(scope) as unknown as MemoryRow[];
    const scored = rows.map((row) => ({
      row,
      score: words.reduce((sum, word) => sum + (row.content.toLowerCase().includes(word) ? 1 : 0), 0),
    })).filter((item) => words.length === 0 || item.score > 0);
    scored.sort((a, b) => b.score - a.score || b.row.updated_at.localeCompare(a.row.updated_at));
    return scored.slice(0, limit).map(({ row }) => toMemory(row));
  }

  startRun(sessionId: string): string {
    const id = randomUUID();
    this.db.prepare("INSERT INTO runs (id, session_id, state, started_at) VALUES (?, ?, 'running', ?)")
      .run(id, sessionId, now());
    return id;
  }

  checkpointRun(id: string, output: string, responseId?: string): void {
    this.db.prepare("UPDATE runs SET output = ?, response_id = COALESCE(?, response_id) WHERE id = ?")
      .run(output, responseId ?? null, id);
  }

  finishRun(id: string, state: "complete" | "failed" | "interrupted", responseId?: string, error?: string, output?: string): void {
    this.db.prepare("UPDATE runs SET state = ?, response_id = ?, error = ?, output = COALESCE(?, output), finished_at = ? WHERE id = ?")
      .run(state, responseId ?? null, error ?? null, output ?? null, now(), id);
  }

  linkGateway(gateway: string, externalId: string, sessionId: string): void {
    this.db.prepare(`
      INSERT INTO gateway_links (gateway, external_id, session_id, created_at) VALUES (?, ?, ?, ?)
      ON CONFLICT(gateway, external_id) DO UPDATE SET session_id = excluded.session_id
    `).run(gateway, externalId, sessionId, now());
  }

  gatewaySession(gateway: string, externalId: string): Session | null {
    const row = this.db.prepare(`
      SELECT sessions.* FROM gateway_links
      JOIN sessions ON sessions.id = gateway_links.session_id
      WHERE gateway_links.gateway = ? AND gateway_links.external_id = ?
    `).get(gateway, externalId) as SessionRow | undefined;
    return row ? toSession(row) : null;
  }

  getSetting(key: string): string | null {
    const row = this.db.prepare("SELECT value FROM settings WHERE key = ?").get(key) as { value: string } | undefined;
    return row?.value ?? null;
  }

  setSetting(key: string, value: string): void {
    this.db.prepare(`
      INSERT INTO settings (key, value, updated_at) VALUES (?, ?, ?)
      ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at
    `).run(key, value, now());
  }

  backendSession(sessionId: string, backend: string): string | null {
    const row = this.db.prepare("SELECT external_id FROM backend_sessions WHERE session_id = ? AND backend = ?")
      .get(sessionId, backend) as { external_id: string } | undefined;
    return row?.external_id ?? null;
  }

  bindBackendSession(sessionId: string, backend: string, externalId: string): void {
    this.db.prepare(`
      INSERT INTO backend_sessions (session_id, backend, external_id, updated_at) VALUES (?, ?, ?, ?)
      ON CONFLICT(session_id, backend) DO UPDATE SET external_id = excluded.external_id, updated_at = excluded.updated_at
    `).run(sessionId, backend, externalId, now());
  }

  removeBackendSession(sessionId: string, backend: string): void {
    this.db.prepare("DELETE FROM backend_sessions WHERE session_id = ? AND backend = ?").run(sessionId, backend);
  }

  close(): void {
    this.db.close();
  }
}
