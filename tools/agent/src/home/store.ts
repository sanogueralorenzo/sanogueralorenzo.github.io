import { randomUUID } from "node:crypto";
import type { DatabaseSync } from "node:sqlite";
import type { Channel, HomeEntry, QueuedTask } from "../conversation/types.js";

const now = () => new Date().toISOString();
type HomeEntryRow = Omit<HomeEntry, "url" | "requests">;

export class HomeStore {
  constructor(private readonly db: DatabaseSync) {}

  private nextUpdate(id: string): string {
    const previous = this.db.prepare("SELECT updated_at AS updatedAt FROM home_entries WHERE id = ?")
      .get(id) as { updatedAt: string } | undefined;
    return new Date(Math.max(Date.now(), previous ? Date.parse(previous.updatedAt) + 1 : 0)).toISOString();
  }

  hasEntry(sessionId: string): boolean {
    return Boolean(this.db.prepare("SELECT 1 FROM home_entries WHERE session_id = ?").get(sessionId));
  }

  createEntry(id: string, body: string): HomeEntry {
    const timestamp = now();
    this.db.prepare(`
      INSERT INTO home_entries (id, body, state, created_at, updated_at) VALUES (?, ?, 'routing', ?, ?)
    `).run(id, body, timestamp, timestamp);
    return this.entry(id)!;
  }

  linkMessage(entryId: string, messageId: number): HomeEntry {
    this.db.prepare("INSERT OR IGNORE INTO home_entry_messages (entry_id, message_id) VALUES (?, ?)").run(entryId, messageId);
    return this.entry(entryId)!;
  }

  linkLatestMessage(sessionId: string, messageId: number): HomeEntry | null {
    const row = this.db.prepare("SELECT id FROM home_entries WHERE session_id = ? AND state IS NOT NULL ORDER BY updated_at DESC, rowid DESC LIMIT 1")
      .get(sessionId) as { id: string } | undefined;
    if (!row) return null;
    this.db.prepare("INSERT OR IGNORE INTO home_entry_messages (entry_id, message_id) VALUES (?, ?)").run(row.id, messageId);
    this.db.prepare("UPDATE home_entries SET state = 'working', summary = NULL, updated_at = ? WHERE id = ?")
      .run(this.nextUpdate(row.id), row.id);
    return this.entry(row.id);
  }

  private withRequests(row: HomeEntryRow): HomeEntry {
    const requests = this.db.prepare(`
      SELECT messages.content AS text, messages.created_at AS createdAt
      FROM home_entry_messages JOIN messages ON messages.id = home_entry_messages.message_id
      WHERE home_entry_messages.entry_id = ? ORDER BY messages.id
    `).all(row.id) as HomeEntry["requests"];
    return { ...row, requests, url: row.sessionId ? `agent://sessions/${row.sessionId}` : null };
  }

  dispatchEntry(id: string, sessionId: string, title: string, body: string, working: boolean): {
    entry: HomeEntry;
    superseded: HomeEntry[];
  } {
    const timestamp = this.nextUpdate(id);
    const previous = this.db.prepare("SELECT id FROM home_entries WHERE session_id = ? AND id != ? AND state IS NOT NULL ORDER BY rowid DESC")
      .all(sessionId, id) as { id: string }[];
    this.db.exec("BEGIN IMMEDIATE");
    try {
      for (const entry of previous) this.db.prepare("UPDATE home_entries SET state = NULL WHERE id = ?")
        .run(entry.id);
      this.db.prepare(`
        UPDATE home_entries SET session_id = ?, title = ?, body = ?, summary = NULL, state = ?, updated_at = ? WHERE id = ?
      `).run(sessionId, title, body, working ? "working" : "ready", timestamp, id);
      this.db.exec("COMMIT");
    } catch (error) {
      this.db.exec("ROLLBACK");
      throw error;
    }
    return { entry: this.entry(id)!, superseded: previous.map((entry) => this.entry(entry.id)!) };
  }

  reuseEntry(provisionalId: string, id: string, sessionId: string, title: string, body: string, working: boolean, messageId: number): {
    entry: HomeEntry;
    superseded: HomeEntry[];
  } {
    const existing = this.entry(id);
    if (!existing || existing.sessionId !== sessionId || id === provisionalId) throw new Error("Home entry does not match this conversation.");
    const previous = this.db.prepare("SELECT id FROM home_entries WHERE session_id = ? AND id != ? AND state IS NOT NULL")
      .all(sessionId, id) as { id: string }[];
    this.db.exec("BEGIN IMMEDIATE");
    try {
      this.db.prepare("INSERT OR IGNORE INTO home_entry_messages (entry_id, message_id) VALUES (?, ?)").run(id, messageId);
      if (provisionalId) this.db.prepare("DELETE FROM home_entries WHERE id = ? AND session_id IS NULL").run(provisionalId);
      for (const entry of previous) this.db.prepare("UPDATE home_entries SET state = NULL WHERE id = ?").run(entry.id);
      this.db.prepare(`
        UPDATE home_entries SET title = ?, body = ?, summary = NULL, state = ?, updated_at = ? WHERE id = ?
      `).run(title, body, working ? "working" : "ready", this.nextUpdate(id), id);
      this.db.exec("COMMIT");
    } catch (error) {
      this.db.exec("ROLLBACK");
      throw error;
    }
    return { entry: this.entry(id)!, superseded: previous.map((entry) => this.entry(entry.id)!) };
  }

  updateEntry(sessionId: string, state: Exclude<HomeEntry["state"], "routing" | null>, summary: string | null): HomeEntry | null {
    const current = this.db.prepare("SELECT id FROM home_entries WHERE session_id = ? AND state IS NOT NULL ORDER BY updated_at DESC, rowid DESC LIMIT 1")
      .get(sessionId) as { id: string } | undefined;
    if (!current) return null;
    this.db.prepare("UPDATE home_entries SET state = ?, summary = ?, updated_at = ? WHERE id = ?")
      .run(state, summary, this.nextUpdate(current.id), current.id);
    return this.entry(current.id);
  }

  failEntry(id: string, summary: string): HomeEntry {
    this.db.prepare("UPDATE home_entries SET state = 'failed', summary = ?, updated_at = ? WHERE id = ?")
      .run(summary, this.nextUpdate(id), id);
    return this.entry(id)!;
  }

  entry(id: string): HomeEntry | null {
    const row = this.db.prepare(`
      SELECT id, session_id AS sessionId, title, body, summary, state, updated_at AS updatedAt
      FROM home_entries WHERE id = ?
    `).get(id) as HomeEntryRow | undefined;
    return row ? this.withRequests(row) : null;
  }

  entries(limit = 100): HomeEntry[] {
    const rows = this.db.prepare(`
      SELECT id, session_id AS sessionId, title, body, summary, state, updated_at AS updatedAt
      FROM (SELECT rowid, * FROM home_entries ORDER BY updated_at DESC, rowid DESC LIMIT ?) ORDER BY updated_at ASC, rowid ASC
    `).all(limit) as unknown as HomeEntryRow[];
    return rows.map((row) => this.withRequests(row));
  }

  enqueueTask(sessionId: string, text: string, channel: Channel, homeEntryId?: string): QueuedTask {
    const task: QueuedTask = { id: randomUUID(), sessionId, text, channel, createdAt: now() };
    this.db.prepare("INSERT INTO queued_tasks (id, session_id, text, channel, created_at) VALUES (?, ?, ?, ?, ?)")
      .run(task.id, sessionId, text, channel, task.createdAt);
    if (homeEntryId) this.db.prepare("INSERT INTO home_queued_tasks (task_id, entry_id) VALUES (?, ?)").run(task.id, homeEntryId);
    return task;
  }

  queuedTasks(sessionId: string): QueuedTask[] {
    return this.db.prepare(`
      SELECT id, session_id AS sessionId, text, channel, created_at AS createdAt
      FROM queued_tasks WHERE session_id = ? ORDER BY rowid
    `).all(sessionId) as unknown as QueuedTask[];
  }

  removeQueuedTask(sessionId: string, id: string): QueuedTask | null {
    const task = this.db.prepare(`
      DELETE FROM queued_tasks WHERE id = ? AND session_id = ?
      RETURNING id, session_id AS sessionId, text, channel, created_at AS createdAt
    `).get(id, sessionId) as QueuedTask | undefined;
    return task ?? null;
  }

  queuedTask(sessionId: string): { id: string; text: string; channel: Channel; homeEntryId: string | null } | null {
    const row = this.db.prepare(`
      SELECT queued_tasks.id, text, channel, home_queued_tasks.entry_id AS homeEntryId
      FROM queued_tasks LEFT JOIN home_queued_tasks ON home_queued_tasks.task_id = queued_tasks.id
      WHERE session_id = ? ORDER BY queued_tasks.rowid LIMIT 1
    `).get(sessionId) as { id: string; text: string; channel: Channel; homeEntryId: string | null } | undefined;
    return row ?? null;
  }

  queuedSessionIds(): string[] {
    const rows = this.db.prepare("SELECT session_id AS id FROM queued_tasks GROUP BY session_id ORDER BY MIN(rowid)")
      .all() as { id: string }[];
    return rows.map((row) => row.id);
  }
}
