import { mkdir, readFile, rm, rename, writeFile, open } from "node:fs/promises";
import { dirname, join } from "node:path";
import { randomUUID } from "node:crypto";
import type { CodexEvent, CodexEventType, CodexSession, CreateSessionBody, StoreSnapshot } from "./types.js";

export class FileStore {
  readonly root: string;
  private readonly sessionsPath: string;
  private readonly eventsDir: string;
  private sessions = new Map<string, CodexSession>();
  private queue = Promise.resolve();

  constructor(root: string) {
    this.root = root;
    this.sessionsPath = join(root, "sessions.json");
    this.eventsDir = join(root, "events");
  }

  async load(): Promise<void> {
    await mkdir(this.eventsDir, { recursive: true });
    try {
      const parsed = JSON.parse(await readFile(this.sessionsPath, "utf8")) as StoreSnapshot;
      this.sessions = new Map(parsed.sessions.map((session) => [session.id, session]));
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code !== "ENOENT") throw error;
    }
  }

  listSessions(): CodexSession[] {
    return [...this.sessions.values()].sort((left, right) => right.updatedAt.localeCompare(left.updatedAt));
  }

  getSession(id: string): CodexSession {
    const session = this.sessions.get(id);
    if (!session) throw new NotFoundError("Session not found.");
    return session;
  }

  async createSession(body: CreateSessionBody): Promise<{ session: CodexSession; event: CodexEvent }> {
    return this.withLock(async () => {
      const now = new Date().toISOString();
      const session: CodexSession = {
        id: randomUUID(),
        title: body.title?.trim() || "Untitled session",
        cwd: body.cwd?.trim() || process.cwd(),
        codexThreadId: body.codexThreadId?.trim() || null,
        status: "idle",
        createdAt: now,
        updatedAt: now,
        lastEventId: 0,
      };
      this.sessions.set(session.id, session);
      const event = await this.appendEventUnlocked(session.id, "session.created", { session });
      await this.saveUnlocked();
      return { session, event };
    });
  }

  async updateSession(id: string, patch: Partial<CodexSession>): Promise<{ session: CodexSession; event: CodexEvent }> {
    return this.withLock(async () => {
      const current = this.getSession(id);
      const session: CodexSession = {
        ...current,
        ...patch,
        updatedAt: new Date().toISOString(),
      };
      this.sessions.set(id, session);
      const event = await this.appendEventUnlocked(id, "session.updated", { session });
      await this.saveUnlocked();
      return { session, event };
    });
  }

  async deleteSession(id: string): Promise<CodexEvent> {
    return this.withLock(async () => {
      this.getSession(id);
      const event = await this.appendEventUnlocked(id, "session.deleted", { sessionId: id });
      this.sessions.delete(id);
      await this.saveUnlocked();
      await rm(this.eventPath(id), { force: true });
      return event;
    });
  }

  async appendEvent(
    sessionId: string,
    type: CodexEventType,
    data?: Record<string, unknown>,
    raw?: Record<string, unknown>,
  ): Promise<CodexEvent> {
    return this.withLock(() => this.appendEventUnlocked(sessionId, type, data, raw));
  }

  private async appendEventUnlocked(
    sessionId: string,
    type: CodexEventType,
    data?: Record<string, unknown>,
    raw?: Record<string, unknown>,
  ): Promise<CodexEvent> {
    const session = this.getSession(sessionId);
    const nextSession = {
      ...session,
      lastEventId: session.lastEventId + 1,
      updatedAt: new Date().toISOString(),
    };
    this.sessions.set(sessionId, nextSession);
    const event: CodexEvent = {
      id: nextSession.lastEventId,
      sessionId,
      type,
      createdAt: nextSession.updatedAt,
      ...(data ? { data } : {}),
      ...(raw ? { raw } : {}),
    };
    await mkdir(dirname(this.eventPath(sessionId)), { recursive: true });
    const file = await open(this.eventPath(sessionId), "a");
    try {
      await file.appendFile(`${JSON.stringify(event)}\n`);
    } finally {
      await file.close();
    }
    return event;
  }

  async eventsAfter(sessionId: string, lastEventId: number): Promise<CodexEvent[]> {
    this.getSession(sessionId);
    try {
      const lines = (await readFile(this.eventPath(sessionId), "utf8")).split("\n").filter(Boolean);
      return lines
        .map((line) => JSON.parse(line) as CodexEvent)
        .filter((event) => event.id > lastEventId);
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code === "ENOENT") return [];
      throw error;
    }
  }

  async save(): Promise<void> {
    await this.withLock(() => this.saveUnlocked());
  }

  private async saveUnlocked(): Promise<void> {
    await mkdir(this.root, { recursive: true });
    const snapshot: StoreSnapshot = { sessions: this.listSessions() };
    const tmp = `${this.sessionsPath}.${randomUUID()}.tmp`;
    await writeFile(tmp, `${JSON.stringify(snapshot, null, 2)}\n`);
    await rename(tmp, this.sessionsPath);
  }

  private async withLock<T>(task: () => Promise<T>): Promise<T> {
    const run = this.queue.then(task, task);
    this.queue = run.then(
      () => undefined,
      () => undefined,
    );
    return run;
  }

  private eventPath(sessionId: string): string {
    return join(this.eventsDir, `${sessionId}.jsonl`);
  }
}

export class NotFoundError extends Error {}
