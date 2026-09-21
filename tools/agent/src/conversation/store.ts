import { chmodSync, existsSync, lstatSync } from "node:fs";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { randomUUID } from "node:crypto";
import type { Attachment, Message, Session, SessionCard } from "./types.js";
import { ensurePrivateDirectory } from "../local/files.js";

const now = () => new Date().toISOString();
const SESSION_COLUMNS = `id, scope_key AS "scopeKey", cwd, title, updated_at AS "updatedAt"`;
const ATTACHMENT_COLUMNS = `id, name, mime_type AS "mimeType", size, path`;

export class Store {
  readonly db: DatabaseSync;

  constructor(homeDir: string, filename = "agent.sqlite", options: { recoverRuns?: boolean } = {}) {
    ensurePrivateDirectory(homeDir);
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
        cwd TEXT,
        title TEXT NOT NULL,
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
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        UNIQUE(scope, content)
      );
      CREATE INDEX IF NOT EXISTS memories_scope ON memories(scope, updated_at DESC);
      CREATE TABLE IF NOT EXISTS runs (
        id TEXT PRIMARY KEY,
        session_id TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
        state TEXT NOT NULL CHECK (state IN ('running', 'complete', 'interrupted', 'failed')),
        output TEXT NOT NULL DEFAULT '',
        started_at TEXT NOT NULL
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
      CREATE TABLE IF NOT EXISTS backend_context (
        session_id TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
        backend TEXT NOT NULL,
        compactions INTEGER NOT NULL DEFAULT 0 CHECK (compactions >= 0),
        PRIMARY KEY(session_id, backend)
      );
      CREATE TABLE IF NOT EXISTS session_handoffs (
        session_id TEXT PRIMARY KEY REFERENCES sessions(id) ON DELETE CASCADE,
        content TEXT NOT NULL,
        updated_at TEXT NOT NULL
      );
      CREATE TABLE IF NOT EXISTS attachments (
        id TEXT PRIMARY KEY,
        kind TEXT NOT NULL CHECK (kind = 'audio'),
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
    this.db.prepare("DELETE FROM runs WHERE state = 'running'").run();
  }

  resolveSession(input: {
    sessionId?: string;
    scopeKey: string;
    cwd?: string;
    title?: string;
  }): Session {
    if (input.sessionId) {
      const exact = this.getSession(input.sessionId);
      if (exact) {
        const timestamp = now();
        this.db.prepare("UPDATE sessions SET cwd = COALESCE(?, cwd), updated_at = ? WHERE id = ?")
          .run(input.cwd ?? null, timestamp, exact.id);
        return this.getSession(exact.id)!;
      }
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
      INSERT INTO sessions (id, scope_key, cwd, title, created_at, updated_at)
      VALUES (?, ?, ?, ?, ?, ?)
    `).run(id, input.scopeKey, input.cwd ?? null, input.title ?? "New conversation", timestamp, timestamp);
    return this.getSession(id)!;
  }

  getSession(id: string): Session | null {
    return this.db.prepare(`SELECT ${SESSION_COLUMNS} FROM sessions WHERE id = ?`).get(id) as unknown as Session ?? null;
  }

  listSessions(limit = 20): Session[] {
    return this.db.prepare(`SELECT ${SESSION_COLUMNS} FROM sessions ORDER BY updated_at DESC LIMIT ?`).all(limit) as unknown as Session[];
  }

  latestSession(): Session | null {
    return this.db.prepare(`SELECT ${SESSION_COLUMNS} FROM sessions ORDER BY updated_at DESC LIMIT 1`).get() as unknown as Session ?? null;
  }

  sessionCards(limit = 50): SessionCard[] {
    return this.listSessions(limit).map((session) => {
      const handoff = this.db.prepare("SELECT content FROM session_handoffs WHERE session_id = ?")
        .get(session.id) as { content: string } | undefined;
      const recent = this.getMessages(session.id, 4)
        .filter((message) => message.role !== "tool")
        .map((message) => `${message.role}: ${message.content.replace(/\s+/g, " ").slice(0, 300)}`)
        .join("\n");
      return {
        id: session.id,
        title: session.title,
        updatedAt: session.updatedAt,
        context: [handoff?.content.slice(0, 800), recent].filter(Boolean).join("\n"),
      };
    });
  }

  activateSession(id: string): Session | null {
    if (!this.getSession(id)) return null;
    this.db.prepare("UPDATE sessions SET updated_at = ? WHERE id = ?").run(now(), id);
    return this.getSession(id);
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

  remember(scope: string, content: string): void {
    const timestamp = now();
    this.db.prepare(`
      INSERT INTO memories (scope, content, created_at, updated_at)
      VALUES (?, ?, ?, ?)
      ON CONFLICT(scope, content) DO UPDATE SET updated_at = excluded.updated_at
    `).run(scope, content.trim(), timestamp, timestamp);
  }

  searchMemories(scope: string, query: string, limit = 8): string[] {
    const words = query.toLowerCase().split(/\W+/).filter((word) => word.length > 2).slice(0, 8);
    const rows = this.db.prepare("SELECT content FROM memories WHERE scope = ? ORDER BY updated_at DESC LIMIT 100")
      .all(scope) as unknown as Array<{ content: string }>;
    return rows.filter(({ content }) => words.length === 0 || words.some((word) => content.toLowerCase().includes(word)))
      .slice(0, limit).map(({ content }) => content);
  }

  startRun(sessionId: string): string {
    const id = randomUUID();
    this.db.prepare("INSERT INTO runs (id, session_id, state, started_at) VALUES (?, ?, 'running', ?)")
      .run(id, sessionId, now());
    return id;
  }

  checkpointRun(id: string, output: string): void {
    this.db.prepare("UPDATE runs SET output = ? WHERE id = ?").run(output, id);
  }

  finishRun(id: string): void {
    this.db.prepare("DELETE FROM runs WHERE id = ?").run(id);
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

  deleteSetting(key: string): void {
    this.db.prepare("DELETE FROM settings WHERE key = ?").run(key);
  }

  backendSession(sessionId: string, backend: string): string | null {
    const row = this.db.prepare("SELECT external_id FROM backend_sessions WHERE session_id = ? AND backend = ?")
      .get(sessionId, backend) as { external_id: string } | undefined;
    return row?.external_id ?? null;
  }

  bindBackendSession(sessionId: string, backend: string, externalId: string): void {
    this.db.exec("BEGIN IMMEDIATE");
    try {
      this.db.prepare(`
        INSERT INTO backend_sessions (session_id, backend, external_id, updated_at) VALUES (?, ?, ?, ?)
        ON CONFLICT(session_id, backend) DO UPDATE SET external_id = excluded.external_id, updated_at = excluded.updated_at
      `).run(sessionId, backend, externalId, now());
      this.db.prepare(`
        INSERT INTO backend_context (session_id, backend, compactions) VALUES (?, ?, 0)
        ON CONFLICT(session_id, backend) DO UPDATE SET compactions = 0
      `).run(sessionId, backend);
      this.db.exec("COMMIT");
    } catch (error) {
      this.db.exec("ROLLBACK");
      throw error;
    }
  }

  addBackendCompactions(sessionId: string, backend: string, count: number): void {
    if (count < 1) return;
    this.db.prepare(`
      INSERT INTO backend_context (session_id, backend, compactions) VALUES (?, ?, ?)
      ON CONFLICT(session_id, backend) DO UPDATE SET compactions = compactions + excluded.compactions
    `).run(sessionId, backend, count);
  }

  backendCompactions(sessionId: string, backend: string): number {
    const row = this.db.prepare("SELECT compactions FROM backend_context WHERE session_id = ? AND backend = ?")
      .get(sessionId, backend) as { compactions: number } | undefined;
    return row?.compactions ?? 0;
  }

  rotateBackendSession(sessionId: string, backend: string, previousId: string, nextId: string, handoff: string): boolean {
    this.db.exec("BEGIN IMMEDIATE");
    try {
      const result = this.db.prepare(`
        UPDATE backend_sessions SET external_id = ?, updated_at = ?
        WHERE session_id = ? AND backend = ? AND external_id = ?
      `).run(nextId, now(), sessionId, backend, previousId);
      if (result.changes !== 1) {
        this.db.exec("ROLLBACK");
        return false;
      }
      this.db.prepare(`
        INSERT INTO backend_context (session_id, backend, compactions) VALUES (?, ?, 0)
        ON CONFLICT(session_id, backend) DO UPDATE SET compactions = 0
      `).run(sessionId, backend);
      this.db.prepare(`
        INSERT INTO session_handoffs (session_id, content, updated_at) VALUES (?, ?, ?)
        ON CONFLICT(session_id) DO UPDATE SET content = excluded.content, updated_at = excluded.updated_at
      `).run(sessionId, handoff, now());
      this.db.exec("COMMIT");
      return true;
    } catch (error) {
      this.db.exec("ROLLBACK");
      throw error;
    }
  }

  addAttachment(input: Attachment): Attachment {
    const timestamp = now();
    this.db.prepare(`
      INSERT INTO attachments (id, kind, name, mime_type, size, path, created_at)
      VALUES (?, ?, ?, ?, ?, ?, ?)
    `).run(input.id, "audio", input.name, input.mimeType, input.size, input.path, timestamp);
    return input;
  }

  getAttachment(id: string): Attachment | null {
    return this.db.prepare(`SELECT ${ATTACHMENT_COLUMNS} FROM attachments WHERE id = ?`).get(id) as unknown as Attachment ?? null;
  }

  close(): void {
    this.db.close();
  }
}
