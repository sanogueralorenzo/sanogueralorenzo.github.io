import { chmodSync, existsSync, lstatSync } from "node:fs";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { randomUUID } from "node:crypto";
import { HOME_SESSION_ID, type Attachment, type LastRun, type Message, type Session, type SessionCard } from "./types.js";
import { ensurePrivateDirectory } from "../local/files.js";
import { HomeStore } from "../home/store.js";

const now = () => new Date().toISOString();
const SESSION_COLUMNS = `id, cwd, title, updated_at AS "updatedAt"`;
const ATTACHMENT_COLUMNS = `id, name, mime_type AS "mimeType", size, path`;

export class Store {
  readonly db: DatabaseSync;
  readonly home: HomeStore;

  constructor(homeDir: string) {
    ensurePrivateDirectory(homeDir);
    const databasePath = join(homeDir, "agent.sqlite");
    if (existsSync(databasePath) && lstatSync(databasePath).isSymbolicLink()) throw new Error("Agent database must not be a symbolic link.");
    this.db = new DatabaseSync(databasePath);
    chmodSync(databasePath, 0o600);
    this.db.exec("PRAGMA journal_mode = WAL; PRAGMA foreign_keys = ON; PRAGMA busy_timeout = 5000;");
    this.initializeSchema();
    this.recoverInterruptedRuns();
    this.home = new HomeStore(this.db);
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
      CREATE TABLE IF NOT EXISTS run_inputs (
        run_id TEXT PRIMARY KEY REFERENCES runs(id) ON DELETE CASCADE,
        content TEXT NOT NULL,
        delivered INTEGER NOT NULL DEFAULT 0
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
      CREATE TABLE IF NOT EXISTS run_handoffs (
        run_id TEXT PRIMARY KEY REFERENCES runs(id) ON DELETE CASCADE,
        source_id TEXT NOT NULL,
        target_id TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
        continues INTEGER NOT NULL
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
      CREATE TABLE IF NOT EXISTS home_entries (
        id TEXT PRIMARY KEY,
        session_id TEXT REFERENCES sessions(id) ON DELETE CASCADE,
        title TEXT,
        body TEXT NOT NULL,
        summary TEXT,
        state TEXT CHECK (state IS NULL OR state IN ('routing', 'working', 'ready', 'needs_input', 'failed')),
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      );
      CREATE TABLE IF NOT EXISTS home_entry_messages (
        entry_id TEXT NOT NULL REFERENCES home_entries(id) ON DELETE CASCADE,
        message_id INTEGER NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
        PRIMARY KEY (entry_id, message_id)
      );
      CREATE TABLE IF NOT EXISTS queued_tasks (
        id TEXT PRIMARY KEY,
        session_id TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
        text TEXT NOT NULL,
        channel TEXT NOT NULL,
        created_at TEXT NOT NULL
      );
      CREATE INDEX IF NOT EXISTS queued_tasks_session ON queued_tasks(session_id, created_at);
      CREATE TABLE IF NOT EXISTS home_queued_tasks (
        task_id TEXT PRIMARY KEY REFERENCES queued_tasks(id) ON DELETE CASCADE,
        entry_id TEXT NOT NULL REFERENCES home_entries(id) ON DELETE CASCADE
      );
    `);
  }

  private recoverInterruptedRuns(): void {
    this.db.exec("BEGIN IMMEDIATE");
    try {
      this.db.prepare(`
        INSERT INTO messages (session_id, role, content, created_at)
        SELECT runs.session_id, 'user', run_inputs.content, ?
        FROM runs JOIN run_inputs ON run_inputs.run_id = runs.id
        WHERE runs.state = 'running' AND run_inputs.delivered = 0
      `).run(now());
      this.db.exec("UPDATE run_inputs SET delivered = 1 WHERE delivered = 0 AND run_id IN (SELECT id FROM runs WHERE state = 'running')");
      this.db.prepare(`
        INSERT INTO messages (session_id, role, content, created_at)
        SELECT session_id, 'assistant', output || char(10) || char(10) || '[interrupted]', ?
        FROM runs WHERE state = 'running' AND output <> ''
      `).run(now());
      this.db.prepare("UPDATE sessions SET updated_at = ? WHERE id IN (SELECT session_id FROM runs WHERE state = 'running')").run(now());
      this.db.prepare("UPDATE runs SET state = 'interrupted', output = '' WHERE state = 'running'").run();
      this.db.prepare(`
        UPDATE home_entries SET
          state = CASE WHEN session_id IS NULL THEN 'failed'
            WHEN EXISTS (SELECT 1 FROM queued_tasks WHERE session_id = home_entries.session_id) THEN 'working'
            ELSE 'failed' END,
          summary = CASE WHEN session_id IS NULL THEN 'Could not dispatch before restart.'
            WHEN EXISTS (SELECT 1 FROM queued_tasks WHERE session_id = home_entries.session_id) THEN NULL
            ELSE 'Interrupted. Open the task to continue.' END,
          updated_at = ?
        WHERE state IN ('routing', 'working')
      `).run(now());
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

  homeSession(): Session {
    const existing = this.getSession(HOME_SESSION_ID);
    if (existing) return existing;
    const timestamp = now();
    this.db.prepare("INSERT INTO sessions (id, cwd, title, created_at, updated_at) VALUES (?, NULL, 'Home', ?, ?)")
      .run(HOME_SESSION_ID, timestamp, timestamp);
    return this.getSession(HOME_SESSION_ID)!;
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
      SELECT id, cwd, title, updated_at AS "updatedAt",
        COALESCE((SELECT content FROM messages WHERE session_id = sessions.id AND role = 'user' ORDER BY id DESC LIMIT 1), '') AS preview
      FROM sessions WHERE id != ? ORDER BY updated_at DESC LIMIT ?
    `).all(HOME_SESSION_ID, limit) as unknown as SessionCard[];
    return cards.map((card) => ({ ...card, preview: card.preview.replace(/\s+/g, " ").slice(0, 200) }));
  }

  findConversations(query: string, limit = 10): SessionCard[] {
    const pattern = `%${query.trim().slice(0, 100)}%`;
    const cards = this.db.prepare(`
      SELECT id, cwd, title, updated_at AS "updatedAt",
        COALESCE(
          (SELECT content FROM messages WHERE session_id = sessions.id AND role != 'tool' AND content LIKE ? ORDER BY id DESC LIMIT 1),
          (SELECT content FROM messages WHERE session_id = sessions.id AND role != 'tool' ORDER BY id DESC LIMIT 1),
          ''
        ) AS preview
      FROM sessions WHERE id != ? AND (
        title LIKE ? OR cwd LIKE ? OR EXISTS (
          SELECT 1 FROM messages WHERE session_id = sessions.id AND role != 'tool' AND content LIKE ?
        )
      ) ORDER BY updated_at DESC LIMIT ?
    `).all(pattern, HOME_SESSION_ID, pattern, pattern, pattern, limit) as unknown as SessionCard[];
    return cards.map((card) => ({ ...card, preview: card.preview.replace(/\s+/g, " ").slice(0, 200) }));
  }

  readConversation(id: string, before?: number, limit = 8, maxChars = 2_000) {
    const rows = this.db.prepare(`
      SELECT id, role, content FROM messages
      WHERE session_id = ? AND role != 'tool' AND (? IS NULL OR id < ?)
      ORDER BY id DESC LIMIT ?
    `).all(id, before ?? null, before ?? null, limit + 1) as { id: number; role: Message["role"]; content: string }[];
    const page = rows.slice(0, limit);
    return {
      messages: page.reverse().map(({ role, content }) => ({ role, content: content.slice(0, maxChars) })),
      nextBefore: rows.length > limit ? page[0]!.id : null,
    };
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

  startRun(sessionId: string, id: string = randomUUID(), input?: string, queuedTaskId?: string): string {
    this.db.exec("BEGIN IMMEDIATE");
    try {
      if (queuedTaskId) {
        const consumed = this.db.prepare("DELETE FROM queued_tasks WHERE id = ? AND session_id = ?")
          .run(queuedTaskId, sessionId);
        if (consumed.changes !== 1) throw new Error("Queued task was not found.");
      }
      this.db.prepare("DELETE FROM runs WHERE session_id = ? AND state != 'running'").run(sessionId);
      this.db.prepare("INSERT INTO runs (id, session_id, state, started_at) VALUES (?, ?, 'running', ?)")
        .run(id, sessionId, now());
      if (input !== undefined) this.db.prepare("INSERT INTO run_inputs (run_id, content) VALUES (?, ?)").run(id, input);
      this.db.exec("COMMIT");
    } catch (error) {
      this.db.exec("ROLLBACK");
      throw error;
    }
    return id;
  }

  handoffRun(input: {
    runId: string;
    sourceId: string;
    destination: { sessionId: string } | { cwd: string; title: string };
    sourceEmpty: boolean;
    continues: boolean;
  }): Session {
    const { runId, sourceId, sourceEmpty, continues } = input;
    let targetId = "";
    this.db.exec("BEGIN IMMEDIATE");
    try {
      if ("sessionId" in input.destination) {
        if (!this.getSession(input.destination.sessionId)) throw new Error("That conversation is no longer available.");
        targetId = input.destination.sessionId;
      } else targetId = this.createSession(input.destination).id;
      if (targetId === sourceId) throw new Error("That conversation is already open.");
      this.db.prepare("DELETE FROM runs WHERE session_id = ? AND state != 'running'").run(targetId);
      this.db.prepare("UPDATE runs SET session_id = ? WHERE id = ?").run(targetId, runId);
      this.db.prepare("INSERT INTO run_handoffs (run_id, source_id, target_id, continues) VALUES (?, ?, ?, ?)")
        .run(runId, sourceId, targetId, continues ? 1 : 0);
      this.db.prepare("UPDATE telegram_sessions SET session_id = ? WHERE session_id = ?").run(targetId, sourceId);
      if (sourceEmpty) {
        this.db.prepare("INSERT INTO session_redirects (source_id, target_id) VALUES (?, ?)").run(sourceId, targetId);
        this.db.prepare("DELETE FROM sessions WHERE id = ?").run(sourceId);
      }
      if (!continues) this.db.prepare("DELETE FROM run_inputs WHERE run_id = ?").run(runId);
      this.db.prepare("UPDATE sessions SET updated_at = ? WHERE id = ?").run(now(), targetId);
      this.db.exec("COMMIT");
    } catch (error) {
      this.db.exec("ROLLBACK");
      throw error;
    }
    return this.getSession(targetId)!;
  }

  stageRunInput(id: string, content: string): void {
    this.db.prepare(`
      INSERT INTO run_inputs (run_id, content) VALUES (?, ?)
      ON CONFLICT(run_id) DO UPDATE SET content = excluded.content
    `).run(id, content);
  }

  deliverRunInput(id: string): number | null {
    const row = this.db.prepare(`
      SELECT runs.session_id AS sessionId, run_inputs.content
      FROM runs JOIN run_inputs ON run_inputs.run_id = runs.id
      WHERE runs.id = ? AND run_inputs.delivered = 0
    `).get(id) as { sessionId: string; content: string } | undefined;
    if (!row) return null;
    this.db.exec("BEGIN IMMEDIATE");
    try {
      const timestamp = now();
      const message = this.db.prepare("INSERT INTO messages (session_id, role, content, created_at) VALUES (?, 'user', ?, ?)")
        .run(row.sessionId, row.content, timestamp);
      this.db.prepare("UPDATE sessions SET updated_at = ? WHERE id = ?").run(timestamp, row.sessionId);
      this.db.prepare("UPDATE run_inputs SET delivered = 1 WHERE run_id = ?").run(id);
      this.db.exec("COMMIT");
      return Number(message.lastInsertRowid);
    } catch (error) {
      this.db.exec("ROLLBACK");
      throw error;
    }
  }

  handoffFor(runId: string, sourceId: string): { targetId: string; continues: boolean } | null {
    const row = this.db.prepare("SELECT target_id AS targetId, continues FROM run_handoffs WHERE run_id = ? AND source_id = ?")
      .get(runId, sourceId) as { targetId: string; continues: number } | undefined;
    return row ? { targetId: row.targetId, continues: Boolean(row.continues) } : null;
  }

  checkpointRun(id: string, output: string): void {
    this.db.prepare("UPDATE runs SET output = ? WHERE id = ?").run(output, id);
  }

  finishRun(id: string, state: LastRun["state"] = "complete", message?: string): void {
    this.deliverRunInput(id);
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
