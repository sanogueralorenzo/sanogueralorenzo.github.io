import { chmodSync, existsSync, lstatSync, mkdirSync } from "node:fs";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { randomUUID } from "node:crypto";
import type { Attachment, Memory, Message, Session, WorkKind } from "./types.js";

const now = () => new Date().toISOString();
const SESSION_COLUMNS = `id, scope_key AS "scopeKey", kind, cwd, title, updated_at AS "updatedAt"`;
const ATTACHMENT_COLUMNS = `id, kind, name, mime_type AS "mimeType", size, path`;

export class Store {
  readonly db: DatabaseSync;

  constructor(homeDir: string, filename = "agent.sqlite", options: { recoverRuns?: boolean } = {}) {
    mkdirSync(homeDir, { recursive: true, mode: 0o700 });
    const homeStat = lstatSync(homeDir);
    if (homeStat.isSymbolicLink()) throw new Error("AGENT_HOME must not be a symbolic link.");
    if (typeof process.getuid === "function" && homeStat.uid !== process.getuid()) throw new Error("AGENT_HOME is owned by another user.");
    chmodSync(homeDir, 0o700);
    const databasePath = join(homeDir, filename);
    if (existsSync(databasePath) && lstatSync(databasePath).isSymbolicLink()) throw new Error("Agent database must not be a symbolic link.");
    this.db = new DatabaseSync(databasePath);
    chmodSync(databasePath, 0o600);
    this.db.exec("PRAGMA journal_mode = WAL; PRAGMA foreign_keys = ON; PRAGMA busy_timeout = 5000;");
    this.initializeSchema();
    if (options.recoverRuns !== false) this.recoverInterruptedRuns();
  }

  private initializeSchema(): void {
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
      CREATE TABLE IF NOT EXISTS attachments (
        id TEXT PRIMARY KEY,
        kind TEXT NOT NULL CHECK (kind IN ('audio', 'image', 'file')),
        name TEXT NOT NULL,
        mime_type TEXT NOT NULL,
        size INTEGER NOT NULL,
        path TEXT NOT NULL UNIQUE,
        created_at TEXT NOT NULL
      );
    `);
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
      SELECT ${SESSION_COLUMNS} FROM sessions
      WHERE scope_key = ? OR instr(scope_key, ? || ':') = 1
      ORDER BY updated_at DESC LIMIT 1
    `).get(input.scopeKey, input.scopeKey) as unknown as Session | undefined;
    if (existing) {
      const timestamp = now();
      this.db.prepare("UPDATE sessions SET updated_at = ? WHERE id = ?").run(timestamp, existing.id);
      return { ...existing, updatedAt: timestamp };
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
    return this.db.prepare(`SELECT ${SESSION_COLUMNS} FROM sessions WHERE id = ?`).get(id) as unknown as Session ?? null;
  }

  listSessions(limit = 20): Session[] {
    return this.db.prepare(`SELECT ${SESSION_COLUMNS} FROM sessions ORDER BY updated_at DESC LIMIT ?`).all(limit) as unknown as Session[];
  }

  latestSession(kind: WorkKind): Session | null {
    return this.db.prepare(`SELECT ${SESSION_COLUMNS} FROM sessions WHERE kind = ? ORDER BY updated_at DESC LIMIT 1`).get(kind) as unknown as Session ?? null;
  }

  addMessage(sessionId: string, role: Message["role"], content: string): void {
    const timestamp = now();
    this.db.prepare("INSERT INTO messages (session_id, role, content, created_at) VALUES (?, ?, ?, ?)")
      .run(sessionId, role, content, timestamp);
    this.db.prepare("UPDATE sessions SET updated_at = ? WHERE id = ?").run(timestamp, sessionId);
  }

  getMessages(sessionId: string, limit = 40): Message[] {
    return this.db.prepare(`
      SELECT role, content FROM (
        SELECT role, content, id FROM messages WHERE session_id = ? ORDER BY id DESC LIMIT ?
      ) ORDER BY id ASC
    `).all(sessionId, limit) as unknown as Message[];
  }

  remember(scope: string, content: string, sourceSessionId?: string): void {
    const timestamp = now();
    this.db.prepare(`
      INSERT INTO memories (scope, content, source_session_id, created_at, updated_at)
      VALUES (?, ?, ?, ?, ?)
      ON CONFLICT(scope, content) DO UPDATE SET updated_at = excluded.updated_at
    `).run(scope, content.trim(), sourceSessionId ?? null, timestamp, timestamp);
  }

  searchMemories(scope: string, query: string, limit = 8): Memory[] {
    const words = query.toLowerCase().split(/\W+/).filter((word) => word.length > 2).slice(0, 8);
    const rows = this.db.prepare(`SELECT content, updated_at AS "updatedAt" FROM memories WHERE scope IN (?, 'global') ORDER BY updated_at DESC LIMIT 100`)
      .all(scope) as unknown as Array<Memory & { updatedAt: string }>;
    const scored = rows.map((row) => ({
      row,
      score: words.reduce((sum, word) => sum + (row.content.toLowerCase().includes(word) ? 1 : 0), 0),
    })).filter((item) => words.length === 0 || item.score > 0);
    scored.sort((a, b) => b.score - a.score || b.row.updatedAt.localeCompare(a.row.updatedAt));
    return scored.slice(0, limit).map(({ row }) => ({ content: row.content }));
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
      SELECT sessions.id, sessions.scope_key AS "scopeKey", sessions.kind, sessions.cwd,
        sessions.title, sessions.updated_at AS "updatedAt"
      FROM gateway_links
      JOIN sessions ON sessions.id = gateway_links.session_id
      WHERE gateway_links.gateway = ? AND gateway_links.external_id = ?
    `).get(gateway, externalId) as unknown as Session | undefined;
    return row ?? null;
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

  addAttachment(input: Attachment): Attachment {
    const timestamp = now();
    this.db.prepare(`
      INSERT INTO attachments (id, kind, name, mime_type, size, path, created_at)
      VALUES (?, ?, ?, ?, ?, ?, ?)
    `).run(input.id, input.kind, input.name, input.mimeType, input.size, input.path, timestamp);
    return input;
  }

  getAttachment(id: string): Attachment | null {
    return this.db.prepare(`SELECT ${ATTACHMENT_COLUMNS} FROM attachments WHERE id = ?`).get(id) as unknown as Attachment ?? null;
  }

  close(): void {
    this.db.close();
  }
}
