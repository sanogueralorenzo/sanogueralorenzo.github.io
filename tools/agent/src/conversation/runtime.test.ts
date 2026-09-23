import { writeFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import type { AgentBackend, BackendEvent, BackendTurn, Handoff, RouteTurn } from "./backend.js";
import { AgentRuntime } from "./runtime.js";
import { Store } from "./store.js";
import type { Attachment, RuntimeEvent } from "./types.js";
import { cleanup, temporary } from "../test-support.js";

class RecordingBackend implements AgentBackend {
  readonly turns: BackendTurn[] = [];
  readonly routes: RouteTurn[] = [];
  readonly transcriptions: string[] = [];
  navigateTo: string | null = null;
  handoffTask: string | null = null;
  failNext = false;
  failTranscription = false;
  transcription = "Fix the TypeScript test";

  async transcribeAudio(attachment: Attachment): Promise<string> {
    this.transcriptions.push(attachment.path);
    if (this.failTranscription) throw new Error("Could not transcribe the voice note.");
    return this.transcription;
  }

  async route(turn: RouteTurn): Promise<Handoff | null> {
    this.routes.push(turn);
    if (!this.navigateTo) return null;
    return { destination: { sessionId: this.navigateTo }, task: this.handoffTask };
  }

  async steer(): Promise<boolean> { return false; }

  async *run(turn: BackendTurn): AsyncGenerator<BackendEvent> {
    this.turns.push(turn);
    if (this.failNext) {
      this.failNext = false;
      throw new DOMException("Interrupted", "AbortError");
    }
    yield { type: "text_delta", delta: "Done." };
    yield { type: "done" };
  }
}

function testRuntime() {
  const homeDir = temporary("agent-runtime-");
  const store = new Store(homeDir);
  const backend = new RecordingBackend();
  cleanup(() => store.close());
  return { homeDir, store, backend, runtime: new AgentRuntime(store, backend) };
}

async function collect(runtime: AgentRuntime, request: Parameters<AgentRuntime["run"]>[0]): Promise<RuntimeEvent[]> {
  const selected = request.sessionId ?? lastSession.get(runtime) ?? runtime.openSession({ fresh: true }).id;
  const events: RuntimeEvent[] = [];
  for await (const event of runtime.run({ ...request, sessionId: selected })) events.push(event);
  lastSession.set(runtime, events.find((event) => event.type === "session")?.session.id ?? selected);
  return events;
}

const lastSession = new WeakMap<AgentRuntime, string>();

describe("AgentRuntime", () => {
  it("persists explicit memory and supplies it to the shared backend", async () => {
    const { store, backend, runtime } = testRuntime();
    const events = await collect(runtime, { text: "Please remember that Mario likes short answers", channel: "api" });
    const session = events.find((event) => event.type === "session")?.session;
    expect(session && store.getMessages(session.id).map((message) => message.role)).toEqual(["user", "assistant"]);
    expect(store.searchMemories("personal", "short answers")).toEqual(["Mario likes short answers"]);
    expect(backend.turns[0]?.instructions).toContain("Mario likes short answers");
    expect(backend.routes).toEqual([]);
  });

  it("uses the public run ID for the persisted last-turn snapshot", async () => {
    const { store, runtime } = testRuntime();
    const events: RuntimeEvent[] = [];
    const sessionId = runtime.openSession({ fresh: true }).id;
    for await (const event of runtime.run({ text: "hello", channel: "macos", sessionId }, { runId: "public-run" })) events.push(event);
    const session = events.find((event) => event.type === "session")?.session;
    expect(store.latestRun()).toMatchObject({
      id: "public-run", sessionId: session?.id, state: "complete", output: "",
    });
  });

  it("uses one coordinator instruction without modes, workers, or duplicated project context", async () => {
    const { homeDir, backend, runtime } = testRuntime();
    const session = runtime.openSession({ fresh: true, cwd: homeDir });
    await collect(runtime, { text: "Fix the failing test", sessionId: session.id, cwd: homeDir, channel: "macos" });
    expect(backend.turns[0]?.instructions).toContain("Use read_history for requested saved messages.");
    expect(backend.turns[0]?.instructions).not.toMatch(/worker|coding session|model|AGENTS\.md|working directory/i);
  });

  it("reuses the selected session across macOS turns", async () => {
    const { runtime } = testRuntime();
    const first = await collect(runtime, { text: "hello", channel: "macos" });
    const sessionId = first.find((event) => event.type === "session")?.session.id;
    const next = await collect(runtime, { text: "continue", channel: "macos", sessionId });
    expect(next.find((event) => event.type === "session")?.session.id).toBe(sessionId);
  });

  it("does not replace an unknown requested session with a new one", () => {
    const { runtime, store } = testRuntime();
    expect(() => runtime.prepareTurn({ text: "continue", channel: "api", sessionId: "missing" }))
      .toThrow("Conversation not found.");
    expect(store.listSessions()).toEqual([]);
  });

  it("continues the latest session regardless of inactivity", async () => {
    const { store, runtime } = testRuntime();
    const first = await collect(runtime, { text: "old topic", channel: "macos" });
    const firstSession = first.find((event) => event.type === "session")?.session.id;
    store.db.prepare("UPDATE sessions SET updated_at = ? WHERE id = ?")
      .run(new Date(0).toISOString(), firstSession);

    const next = await collect(runtime, { text: "continue", channel: "macos" });
    const nextSession = next.find((event) => event.type === "session")?.session.id;

    expect(nextSession).toBe(firstSession);
    expect(firstSession && store.getMessages(firstSession).map((message) => message.content))
      .toEqual(["old topic", "Done.", "continue", "Done."]);
  });

  it("keeps a client's selected session even when another is newer", () => {
    const { store, runtime } = testRuntime();
    const first = runtime.openSession({ fresh: true });
    runtime.openSession({ fresh: true });
    store.db.prepare("UPDATE sessions SET updated_at = ? WHERE id = ?")
      .run(new Date(0).toISOString(), first.id);
    expect(runtime.openSession({ preferredSessionId: first.id }).id).toBe(first.id);
  });

  it("opens Home by default while allowing a specific workspace", () => {
    const { store, runtime } = testRuntime();
    const older = runtime.openSession({ fresh: true, cwd: "/tmp/older" });
    const latest = runtime.openSession({ fresh: true, cwd: "/tmp/latest" });
    store.db.prepare("UPDATE sessions SET updated_at = ? WHERE id = ?")
      .run(new Date(0).toISOString(), older.id);
    expect(runtime.openSession().id).toBe("home");
    expect(runtime.openSession({ cwd: "/tmp/older" }).id).toBe(older.id);
    expect(latest.id).not.toBe("home");
  });

  it("does not create a conversation for an unknown explicit selection", () => {
    const { store, runtime } = testRuntime();
    expect(() => runtime.openSession({ preferredSessionId: "missing" })).toThrow("Conversation not found.");
    expect(store.listSessions()).toEqual([]);
  });

  it("starts a separate session when the user requests a new conversation", async () => {
    const { runtime } = testRuntime();
    const first = await collect(runtime, { text: "first", channel: "macos" });
    const firstSession = first.find((event) => event.type === "session")?.session.id;
    const fresh = runtime.openSession({ fresh: true });
    const next = await collect(runtime, { text: "second", sessionId: fresh.id, channel: "macos" });
    expect(next.find((event) => event.type === "session")?.session.id).not.toBe(firstSession);
  });

  it("navigates to a matching session without storing the lookup conversation", async () => {
    const { store, backend, runtime } = testRuntime();
    const first = await collect(runtime, { text: "Simplify runtime reconnects", channel: "macos" });
    const firstSession = first.find((event) => event.type === "session")?.session.id;
    backend.navigateTo = firstSession ?? null;

    const fresh = runtime.openSession({ fresh: true });
    const lookup = await collect(runtime, { text: "take me back to the bot restart work", sessionId: fresh.id, channel: "macos" });

    expect(backend.routes.at(-1)?.sessionTools[0]?.id).toBe(firstSession);
    expect(backend.routes.map((turn) => turn.request.text)).toEqual(["take me back to the bot restart work"]);
    expect(lookup).toContainEqual(expect.objectContaining({
      type: "navigate",
      url: `agent://sessions/${firstSession}`,
    }));
    expect(lookup.at(-1)).toEqual({ type: "done", sessionId: firstSession });
    expect(store.listSessions()).toHaveLength(1);
    expect(firstSession && store.getMessages(firstSession).map((message) => message.content))
      .toEqual(["Simplify runtime reconnects", "Done."]);
  });

  it("binds the workspace only when a provisional macOS turn does not navigate", async () => {
    const { homeDir, store, backend, runtime } = testRuntime();
    const source = runtime.openSession({ fresh: true });
    expect(source.cwd).toBeNull();

    const events = await collect(runtime, {
      text: "Inspect this project", sessionId: source.id, cwd: homeDir, channel: "macos",
    });

    expect(events.find((event) => event.type === "session")?.session.cwd).toBe(homeDir);
    expect(backend.turns.at(-1)?.session.cwd).toBe(homeDir);
    expect(store.getSession(source.id)?.cwd).toBe(homeDir);
  });

  it("does not bind the workspace when a provisional macOS turn switches sessions", async () => {
    const { homeDir, store, backend, runtime } = testRuntime();
    const target = runtime.openSession({ fresh: true, cwd: "/tmp/target-project" });
    const source = runtime.openSession({ fresh: true });
    backend.navigateTo = target.id;
    backend.handoffTask = "Fix the test";

    const events = await collect(runtime, {
      text: "Resume the target project and fix the test", sessionId: source.id, cwd: homeDir, channel: "macos",
    });

    expect(backend.routes[0]?.session.cwd).toBeNull();
    expect(backend.turns.at(-1)?.session.cwd).toBe("/tmp/target-project");
    expect(events.find((event) => event.type === "navigate")?.session.id).toBe(target.id);
    expect(store.getSession(source.id)).toBeNull();
    expect(store.getSession(target.id)?.cwd).toBe("/tmp/target-project");
  });

  it("leaves a populated source conversation untouched when switching without a task", async () => {
    const { store, backend, runtime } = testRuntime();
    const source = store.createSession({ title: "Current work" });
    store.addMessage(source.id, "user", "Original topic");
    const target = store.createSession({ title: "Older work" });
    backend.navigateTo = target.id;

    const events = await collect(runtime, { text: "Resume the older work conversation", sessionId: source.id });
    expect(events).toContainEqual(expect.objectContaining({ type: "navigate", continues: false }));
    expect(store.getMessages(source.id)).toEqual([{ role: "user", content: "Original topic" }]);
    expect(store.getSession(source.id)).not.toBeNull();
    expect(store.getMessages(target.id)).toEqual([]);
  });

  it("keeps the session resumable after interruption", async () => {
    const { backend, runtime } = testRuntime();
    backend.failNext = true;
    const interrupted = await collect(runtime, { text: "Fix the test", channel: "macos" });
    const session = interrupted.find((event) => event.type === "session")?.session;
    expect(interrupted.at(-1)).toEqual({ type: "error", message: "Interrupted. Your session is saved." });
    const resumed = await collect(runtime, { text: "continue", channel: "macos", sessionId: session?.id });
    expect(resumed.find((event) => event.type === "session")?.session.id).toBe(session?.id);
    expect(resumed.at(-1)?.type).toBe("done");
  });

  it("transcribes runtime-owned audio before the turn and persists the transcript", async () => {
    const { homeDir, store, backend, runtime } = testRuntime();
    const audioPath = join(homeDir, "voice.ogg");
    writeFileSync(audioPath, "audio");
    const events = await collect(runtime, {
      text: "",
      channel: "macos",
      attachments: [{ id: "voice-1", name: "voice.ogg", mimeType: "audio/ogg", size: 5, path: audioPath }],
    });
    expect(events[0]).toEqual({ type: "status", message: "Listening…" });
    const session = events.find((event) => event.type === "session")?.session;
    expect(session?.cwd).toBeNull();
    expect(session && store.getMessages(session.id)[0]?.content).toBe("Fix the TypeScript test");
    expect(backend.transcriptions).toEqual([audioPath]);
    expect(backend.routes).toEqual([]);
  });

  it("routes a transcribed voice request and keeps the transcript in the destination", async () => {
    const { homeDir, store, backend, runtime } = testRuntime();
    const target = store.createSession({ title: "Saved project" });
    backend.navigateTo = target.id;
    backend.handoffTask = "Fix the test";
    backend.transcription = "Resume the saved project conversation and fix the test";
    const source = runtime.openSession({ fresh: true });
    const events = await collect(runtime, {
      text: "", sessionId: source.id, channel: "macos",
      attachments: [{ id: "voice-1", name: "voice.ogg", mimeType: "audio/ogg", size: 5, path: join(homeDir, "voice.ogg") }],
    });

    expect(events).toContainEqual(expect.objectContaining({ type: "navigate", continues: true, session: expect.objectContaining({ id: target.id }) }));
    expect(store.getMessages(target.id)[0]).toEqual({ role: "user", content: backend.transcription });
    expect(backend.routes.map((turn) => turn.request.text)).toEqual([backend.transcription]);
    expect(store.getSession(source.id)).toBeNull();
  });

  it("persists an early voice failure under the public run ID", async () => {
    const { homeDir, store, backend, runtime } = testRuntime();
    backend.failTranscription = true;
    const attachment = { id: "voice-1", name: "voice.ogg", mimeType: "audio/ogg", size: 5, path: join(homeDir, "voice.ogg") };
    const events: RuntimeEvent[] = [];
    for await (const event of runtime.run({ text: "", channel: "macos", attachments: [attachment] }, { runId: "failed-voice" })) events.push(event);
    expect(events.at(-1)).toEqual({ type: "error", message: "Could not transcribe the voice note." });
    expect(store.latestRun()).toMatchObject({ id: "failed-voice", state: "failed" });
    const sessionId = store.latestRun()?.sessionId;
    expect(sessionId && store.getMessages(sessionId).map((message) => message.content))
      .toEqual(["Voice message", "Could not transcribe the voice note."]);
  });

  it("keeps an empty voice transcription attached to its user turn", async () => {
    const { homeDir, store, backend, runtime } = testRuntime();
    backend.transcription = "";
    const attachment = { id: "voice-1", name: "voice.ogg", mimeType: "audio/ogg", size: 5, path: join(homeDir, "voice.ogg") };
    const events = await collect(runtime, { text: "", channel: "macos", attachments: [attachment] });
    expect(events.at(-1)).toEqual({ type: "error", message: "The message is empty." });
    const sessionId = store.latestRun()?.sessionId;
    expect(sessionId && store.getMessages(sessionId).map((message) => message.content))
      .toEqual(["Voice message", "The message is empty."]);
  });

  it("carries the selected workspace across macOS turns", async () => {
    const { homeDir, backend, runtime } = testRuntime();
    const first = await collect(runtime, { text: "Inspect this project", cwd: homeDir, channel: "macos" });
    const sessionId = first.find((event) => event.type === "session")?.session.id;
    await collect(runtime, { text: "Now fix it", channel: "macos", sessionId });
    expect(backend.turns.map((turn) => turn.session.cwd)).toEqual([homeDir, homeDir]);
  });
});
