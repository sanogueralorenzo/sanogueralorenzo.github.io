import { randomUUID } from "node:crypto";
import type { DatabaseSync } from "node:sqlite";
import type { Channel, HomeEntry } from "../conversation/types.js";

const now = () => new Date().toISOString();
type HomeEntryRow = Omit<HomeEntry, "url">;

function withUrl(row: HomeEntryRow): HomeEntry {
  return { ...row, url: row.sessionId ? `agent://sessions/${row.sessionId}` : null };
}

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

  dispatchEntry(id: string, sessionId: string, title: string, body: string, working: boolean): {
    entry: HomeEntry;
    superseded: HomeEntry[];
  } {
    const timestamp = this.nextUpdate(id);
    const previous = this.db.prepare("SELECT id FROM home_entries WHERE session_id = ? AND id != ? AND state IS NOT NULL ORDER BY rowid DESC")
      .all(sessionId, id) as { id: string }[];
    this.db.exec("BEGIN IMMEDIATE");
    try {
      for (const entry of previous) this.db.prepare("UPDATE home_entries SET state = NULL, updated_at = ? WHERE id = ?")
        .run(this.nextUpdate(entry.id), entry.id);
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

  updateEntry(sessionId: string, state: Exclude<HomeEntry["state"], "routing" | null>, summary: string | null): HomeEntry | null {
    const current = this.db.prepare("SELECT id FROM home_entries WHERE session_id = ? ORDER BY rowid DESC LIMIT 1")
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
    return row ? withUrl(row) : null;
  }

  entries(limit = 100): HomeEntry[] {
    const rows = this.db.prepare(`
      SELECT id, session_id AS sessionId, title, body, summary, state, updated_at AS updatedAt
      FROM (SELECT rowid, * FROM home_entries ORDER BY rowid DESC LIMIT ?) ORDER BY rowid ASC
    `).all(limit) as unknown as HomeEntryRow[];
    return rows.map(withUrl);
  }

  enqueueTask(sessionId: string, text: string, channel: Channel): void {
    this.db.prepare("INSERT INTO queued_tasks (id, session_id, text, channel, created_at) VALUES (?, ?, ?, ?, ?)")
      .run(randomUUID(), sessionId, text, channel, now());
  }

  queuedTask(sessionId: string): { id: string; text: string; channel: Channel } | null {
    const row = this.db.prepare("SELECT id, text, channel FROM queued_tasks WHERE session_id = ? ORDER BY rowid LIMIT 1")
      .get(sessionId) as { id: string; text: string; channel: Channel } | undefined;
    return row ?? null;
  }

  queuedSessionIds(): string[] {
    const rows = this.db.prepare("SELECT session_id AS id FROM queued_tasks GROUP BY session_id ORDER BY MIN(rowid)")
      .all() as { id: string }[];
    return rows.map((row) => row.id);
  }
}
