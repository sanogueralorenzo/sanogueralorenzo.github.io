import { randomUUID } from "node:crypto";
import { existsSync, mkdirSync, readFileSync, renameSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";

export type EntryStatus = "routing" | "queued" | "working" | "ready" | "failed" | "interrupted";
export type TaskRole = "personal" | "code" | "scout" | "reviewer";
export type HomeMessage = { id: string; text: string; createdAt: string; entryId: string | null; replyToId?: string; editOfId?: string; status: "routing" | "routed" | "failed" };
export type Update = { id: string; text: string; kind: "progress" | "result" | "error"; sourceId?: string; createdAt: string };
export type HomeEntry = { id: string; sourceId: string; title: string; sessionId: string | null; status: EntryStatus; interruptedText?: string; interruptedSourceId?: string; updates: Update[]; createdAt: string; updatedAt: string };
export type SessionRecord = { id: string; title: string; role?: TaskRole; cwd: string; file: string; status: "idle" | "running" | "interrupted"; createdAt: string };
export type Turn = { id: string; sessionId: string; entryId: string | null; sourceId?: string; replyToId?: string; text: string; status: "queued" | "running"; createdAt: string };
export type Data = { version: 1; messages: HomeMessage[]; entries: HomeEntry[]; sessions: SessionRecord[]; turns: Turn[] };
const empty = (): Data => ({ version: 1, messages: [], entries: [], sessions: [], turns: [] });
export const now = () => new Date().toISOString();

export class State {
  readonly file: string;
  readonly dir: string;
  private readonly changed: () => void;
  data: Data;
  constructor(dir: string, changed: () => void) {
    this.dir = dir;
    this.changed = changed;
    mkdirSync(dir, { recursive: true });
    this.file = join(dir, "state.json");
    this.data = existsSync(this.file) ? JSON.parse(readFileSync(this.file, "utf8")) as Data : empty();
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
    const temp = join(dirname(this.file), `.state-${randomUUID()}.tmp`);
    writeFileSync(temp, JSON.stringify(this.data, null, 2), { mode: 0o600 });
    renameSync(temp, this.file);
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
  update(entry: HomeEntry, text: string, kind: Update["kind"], status?: EntryStatus, sourceId?: string) {
    entry.updates = entry.updates.filter((update) => update.kind !== "progress");
    entry.updates.push({ id: randomUUID(), text, kind, sourceId, createdAt: now() });
    if (status) entry.status = status;
    entry.updatedAt = now();
    this.save();
  }
}
