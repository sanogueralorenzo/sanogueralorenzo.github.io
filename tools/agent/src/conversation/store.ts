import { chmodSync, existsSync, lstatSync } from "node:fs";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { randomUUID } from "node:crypto";
import type { Attachment, LastRun, Message, Session, SessionCard } from "./types.js";
import { ensurePrivateDirectory } from "../local/files.js";

const now = () => new Date().toISOString();
const SESSION_COLUMNS = `id, cwd, title, updated_at AS "updatedAt"`;
const ATTACHMENT_COLUMNS = `id, name, mime_type AS "mimeType", size, path`;

export class Store {
  readonly db: DatabaseSync;

  constructor(homeDir: string) {
    ensurePrivateDirectory(homeDir);
    const databasePath = join(homeDir, "agent.sqlite");
    if (existsSync(databasePath) && lstatSync(databasePath).isSymbolicLink()) throw new Error("Agent database must not be a symbolic link.");
    this.db = new DatabaseSync(databasePath);
    chmodSync(databasePath, 0o600);
    this.db.exec("PRAGMA journal_mode = WAL; PRAGMA foreign_keys = ON; PRAGMA busy_timeout = 5000;");
    this.initializeSchema();
    this.recoverInterruptedRuns();
  }

  private initializeSchema(): void {
    this.db.exec(`
      CREATE TABLE IF NOT EXISTS sessions (
        id TEXT PRIMARY KEY,
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
      CREATE TABLE IF NOT EXISTS codex_threads (
        session_id TEXT PRIMARY KEY REFERENCES sessions(id) ON DELETE CASCADE,
        thread_id TEXT NOT NULL UNIQUE,
        updated_at TEXT NOT NULL
      );
      CREATE TABLE IF NOT EXISTS telegram_sessions (
        owner_id TEXT PRIMARY KEY,
        session_id TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE
      );
      CREATE TABLE IF NOT EXISTS session_redirects (
        source_id TEXT PRIMARY KEY,
        target_id TEXT NOT NULL
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
    this.db.exec("BEGIN IMMEDIATE");
    try {
      this.db.prepare(`
        INSERT INTO messages (session_id, role, content, created_at)
        SELECT session_id, 'assistant', output || char(10) || char(10) || '[interrupted]', ?
        FROM runs WHERE state = 'running' AND output <> ''
      `).run(now());
      this.db.prepare("UPDATE runs SET state = 'interrupted', output = '' WHERE state = 'running'").run();
      this.db.exec("COMMIT");
    } catch (error) {
      this.db.exec("ROLLBACK");
      throw error;
    }
  }

  createSession(input: { cwd?: string; title?: string } = {}): Session {
    const timestamp = now();
    const id = randomUUID();
    this.db.prepare(`
      INSERT INTO sessions (id, cwd, title, created_at, updated_at)
      VALUES (?, ?, ?, ?, ?)
    `).run(id, input.cwd ?? null, input.title ?? "New conversation", timestamp, timestamp);
    return this.getSession(id)!;
  }

  setSessionWorkspace(id: string, cwd: string): Session {
    this.db.prepare("UPDATE sessions SET cwd = ?, updated_at = ? WHERE id = ? AND cwd IS NULL").run(cwd, now(), id);
    return this.getSession(id)!;
  }

  telegramSession(ownerId: string): string | null {
    const row = this.db.prepare("SELECT session_id AS sessionId FROM telegram_sessions WHERE owner_id = ?")
      .get(ownerId) as { sessionId: string } | undefined;
    return row?.sessionId ?? null;
  }

  bindTelegramSession(ownerId: string, sessionId: string): void {
    this.db.prepare(`
      INSERT INTO telegram_sessions (owner_id, session_id) VALUES (?, ?)
      ON CONFLICT(owner_id) DO UPDATE SET session_id = excluded.session_id
    `).run(ownerId, sessionId);
  }

  getSession(id: string): Session | null {
    return this.db.prepare(`SELECT ${SESSION_COLUMNS} FROM sessions WHERE id = ?`).get(id) as unknown as Session ?? null;
  }

  renameSession(id: string, title: string): Session {
    this.db.prepare("UPDATE sessions SET title = ? WHERE id = ?").run(title, id);
    return this.getSession(id)!;
  }

  listSessions(limit = 20): Session[] {
    return this.db.prepare(`SELECT ${SESSION_COLUMNS} FROM sessions ORDER BY updated_at DESC LIMIT ?`).all(limit) as unknown as Session[];
  }

  latestSession(cwd?: string): Session | null {
    return this.db.prepare(`SELECT ${SESSION_COLUMNS} FROM sessions WHERE (? IS NULL OR cwd = ?) ORDER BY updated_at DESC LIMIT 1`)
      .get(cwd ?? null, cwd ?? null) as unknown as Session ?? null;
  }

  sessionCards(limit = 50): SessionCard[] {
    const cards = this.db.prepare(`
      SELECT id, title, updated_at AS "updatedAt",
        COALESCE((SELECT content FROM messages WHERE session_id = sessions.id AND role = 'user' ORDER BY id DESC LIMIT 1), '') AS preview
      FROM sessions ORDER BY updated_at DESC LIMIT ?
    `).all(limit) as unknown as SessionCard[];
    return cards.map((card) => ({ ...card, preview: card.preview.replace(/\s+/g, " ").slice(0, 200) }));
  }

  readConversation(id: string, before?: number) {
    const rows = this.db.prepare(`
      SELECT id, role, content FROM messages
      WHERE session_id = ? AND role != 'tool' AND (? IS NULL OR id < ?)
      ORDER BY id DESC LIMIT 9
    `).all(id, before ?? null, before ?? null) as { id: number; role: Message["role"]; content: string }[];
    const page = rows.slice(0, 8);
    return {
      messages: page.reverse().map(({ role, content }) => ({ role, content: content.slice(0, 2_000) })),
      nextBefore: rows.length > 8 ? page[0]!.id : null,
    };
  }

  activateSession(id: string): Session | null {
    if (!this.getSession(id)) return null;
    this.db.prepare("UPDATE sessions SET updated_at = ? WHERE id = ?").run(now(), id);
    return this.getSession(id);
  }

  redirectSession(sourceId: string, targetId: string): void {
    this.db.exec("BEGIN IMMEDIATE");
    try {
      this.db.prepare("INSERT INTO session_redirects (source_id, target_id) VALUES (?, ?)").run(sourceId, targetId);
      this.db.prepare("UPDATE telegram_sessions SET session_id = ? WHERE session_id = ?").run(targetId, sourceId);
      this.db.prepare("DELETE FROM sessions WHERE id = ?").run(sourceId);
      this.db.exec("COMMIT");
    } catch (error) {
      this.db.exec("ROLLBACK");
      throw error;
    }
  }

  redirectedSession(id: string): Session | null {
    let current = id;
    while (true) {
      const next = this.db.prepare("SELECT target_id AS targetId FROM session_redirects WHERE source_id = ?")
        .get(current) as { targetId: string } | undefined;
      if (!next) return current === id ? null : this.getSession(current);
      current = next.targetId;
    }
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

  startRun(sessionId: string, id: string = randomUUID()): string {
    this.db.exec("BEGIN IMMEDIATE");
    try {
      this.db.prepare("DELETE FROM runs WHERE session_id = ? AND state != 'running'").run(sessionId);
      this.db.prepare("INSERT INTO runs (id, session_id, state, started_at) VALUES (?, ?, 'running', ?)")
        .run(id, sessionId, now());
      this.db.exec("COMMIT");
    } catch (error) {
      this.db.exec("ROLLBACK");
      throw error;
    }
    return id;
  }

  checkpointRun(id: string, output: string): void {
    this.db.prepare("UPDATE runs SET output = ? WHERE id = ?").run(output, id);
  }

  finishRun(id: string, state: LastRun["state"] = "complete", message?: string): void {
    this.db.exec("BEGIN IMMEDIATE");
    try {
      const run = this.db.prepare("SELECT session_id AS sessionId FROM runs WHERE id = ?")
        .get(id) as { sessionId: string } | undefined;
      if (run && message) this.addMessage(run.sessionId, "assistant", message);
      this.db.prepare("UPDATE runs SET state = ?, output = '' WHERE id = ?").run(state, id);
      this.db.exec("COMMIT");
    } catch (error) {
      this.db.exec("ROLLBACK");
      throw error;
    }
  }

  latestRun(sessionId?: string): LastRun | null {
    return this.db.prepare(`
      SELECT id, session_id AS "sessionId", state, output FROM runs
      WHERE (? IS NULL OR session_id = ?) ORDER BY started_at DESC LIMIT 1
    `).get(sessionId ?? null, sessionId ?? null) as unknown as LastRun ?? null;
  }

  codexThread(sessionId: string): string | null {
    const row = this.db.prepare("SELECT thread_id AS threadId FROM codex_threads WHERE session_id = ?")
      .get(sessionId) as { threadId: string } | undefined;
    return row?.threadId ?? null;
  }

  bindCodexThread(sessionId: string, threadId: string): void {
    this.db.prepare(`
      INSERT INTO codex_threads (session_id, thread_id, updated_at) VALUES (?, ?, ?)
      ON CONFLICT(session_id) DO UPDATE SET thread_id = excluded.thread_id, updated_at = excluded.updated_at
    `).run(sessionId, threadId, now());
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
