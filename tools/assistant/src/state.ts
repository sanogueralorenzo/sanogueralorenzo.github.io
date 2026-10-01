import { randomUUID } from "node:crypto";
import { chmodSync, closeSync, mkdirSync, openSync } from "node:fs";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";

export type EntryStatus = "routing" | "queued" | "working" | "ready" | "failed" | "interrupted";
export type HomeMessage = { id: string; text: string; createdAt: string; entryId: string | null; replyToId?: string; editOfId?: string; status: "routing" | "routed" | "failed" };
export type Update = { id: string; text: string; kind: "progress" | "result" | "error"; sourceId?: string; quoteSource?: boolean; createdAt: string };
export type HomeEntry = { id: string; sourceId: string; title: string; sessionId: string | null; status: EntryStatus; interruptedText?: string; interruptedSourceId?: string; updates: Update[]; createdAt: string; updatedAt: string };
export type SessionRecord = { id: string; title: string; cwd: string; file: string; status: "idle" | "running" | "interrupted"; createdAt: string };
export type Turn = { id: string; sessionId: string; entryId: string | null; sourceId?: string; replyToId?: string; text: string; status: "queued" | "running"; createdAt: string };
export type Data = { version: 1; messages: HomeMessage[]; entries: HomeEntry[]; sessions: SessionRecord[]; turns: Turn[] };
export const now = () => new Date().toISOString();

type Table = "messages" | "entries" | "sessions" | "turns";
type Row = { id: string; value: string };
const tables: Table[] = ["messages", "entries", "sessions", "turns"];
export class State {
  readonly db: DatabaseSync;
  private readonly changed: () => void;
  private persisted: Record<Table, Map<string, string>>;
  data: Data;
  constructor(dir: string, changed: () => void) {
    this.changed = changed;
    mkdirSync(dir, { recursive: true, mode: 0o700 });
    const file = join(dir, "sessions.db");
    closeSync(openSync(file, "a", 0o600));
    chmodSync(file, 0o600);
    this.db = new DatabaseSync(file);
    this.db.exec("PRAGMA journal_mode = WAL");
    this.db.exec(`
      CREATE TABLE IF NOT EXISTS messages (id TEXT PRIMARY KEY, value TEXT NOT NULL);
      CREATE TABLE IF NOT EXISTS entries (id TEXT PRIMARY KEY, value TEXT NOT NULL);
      CREATE TABLE IF NOT EXISTS sessions (id TEXT PRIMARY KEY, value TEXT NOT NULL);
      CREATE TABLE IF NOT EXISTS turns (id TEXT PRIMARY KEY, value TEXT NOT NULL);
    `);
    const read = (table: Table) => this.db.prepare(`SELECT id, value FROM ${table} ORDER BY rowid`).all() as Row[];
    const messages = read("messages");
    const entries = read("entries");
    const sessions = read("sessions");
    const turns = read("turns");
    this.persisted = { messages: new Map(messages.map((row) => [row.id, row.value])),
      entries: new Map(entries.map((row) => [row.id, row.value])),
      sessions: new Map(sessions.map((row) => [row.id, row.value])),
      turns: new Map(turns.map((row) => [row.id, row.value])) };
    this.data = { version: 1, messages: messages.map((row) => JSON.parse(row.value) as HomeMessage),
      entries: entries.map((row) => JSON.parse(row.value) as HomeEntry),
      sessions: sessions.map((row) => JSON.parse(row.value) as SessionRecord),
      turns: turns.map((row) => JSON.parse(row.value) as Turn) };
    // A restarted service never silently replays an in-flight turn. Queued work remains queued.
    for (const session of this.data.sessions) if (session.status === "running") session.status = "interrupted";
    for (const turn of this.data.turns) if (turn.status === "running") {
      const entry = this.data.entries.find((item) => item.id === turn.entryId);
      if (entry) { entry.status = "interrupted"; entry.interruptedText = turn.text; entry.interruptedSourceId = turn.sourceId; }
    }
    this.data.turns = this.data.turns.filter((turn) => turn.status !== "running");
    this.save();
  }
  save() {
    const next = { messages: new Map(this.data.messages.map((item) => [item.id, JSON.stringify(item)])),
      entries: new Map(this.data.entries.map((item) => [item.id, JSON.stringify(item)])),
      sessions: new Map(this.data.sessions.map((item) => [item.id, JSON.stringify(item)])),
      turns: new Map(this.data.turns.map((item) => [item.id, JSON.stringify(item)])) };
    this.db.exec("BEGIN IMMEDIATE");
    try {
      for (const table of tables) {
        const previous = this.persisted[table];
        const current = next[table];
        const savedOrder = [...previous.keys()].filter((id) => current.has(id));
        savedOrder.push(...[...current.keys()].filter((id) => !previous.has(id)));
        const reordered = [...current.keys()].some((id, index) => id !== savedOrder[index]);
        if (reordered) this.db.exec(`DELETE FROM ${table}`);
        else {
          const remove = this.db.prepare(`DELETE FROM ${table} WHERE id = ?`);
          for (const id of previous.keys()) if (!current.has(id)) remove.run(id);
        }
        const upsert = this.db.prepare(`INSERT INTO ${table} (id, value) VALUES (?, ?) ON CONFLICT(id) DO UPDATE SET value = excluded.value`);
        for (const [id, value] of current) if (reordered || previous.get(id) !== value) upsert.run(id, value);
      }
      this.db.exec("COMMIT");
    } catch (error) { this.db.exec("ROLLBACK"); throw error; }
    this.persisted = next;
    this.changed();
  }
  message(text: string, id: string = randomUUID(), context: Pick<HomeMessage, "replyToId" | "editOfId"> = {}) {
    if (this.data.messages.some((message) => message.id === id)) throw new Error("Request ID already exists");
    const message: HomeMessage = { id, text, createdAt: now(), entryId: null, ...context, status: "routing" };
    this.data.messages.push(message);
    this.save();
    return message;
  }
  entry(source: HomeMessage, title: string, sessionId: string | null, id: string = randomUUID()) {
    const entry: HomeEntry = { id, sourceId: source.id, title, sessionId, status: sessionId ? "queued" : "routing", updates: [], createdAt: now(), updatedAt: now() };
    this.data.entries.push(entry);
    source.entryId = id;
    this.save();
    return entry;
  }
  update(entry: HomeEntry, text: string, kind: Update["kind"], status?: EntryStatus, sourceId?: string, id: string = randomUUID()) {
    entry.updates = entry.updates.filter((update) => update.kind !== "progress");
    entry.updates.push({ id, text, kind, sourceId,
      ...(kind !== "progress" && { quoteSource: this.data.messages.at(-1)?.id !== (sourceId || entry.sourceId) }), createdAt: now() });
    if (status) entry.status = status;
    entry.updatedAt = now();
    this.save();
  }
}
