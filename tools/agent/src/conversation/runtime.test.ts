import { writeFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import type { AgentBackend, BackendEvent, BackendTurn, Handoff } from "./backend.js";
import { AgentRuntime } from "./runtime.js";
import { Store } from "./store.js";
import type { Attachment, RuntimeEvent } from "./types.js";
import { cleanup, temporary } from "../test-support.js";

class RecordingBackend implements AgentBackend {
  readonly turns: BackendTurn[] = [];
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

  async route(turn: BackendTurn): Promise<Handoff | null> {
    if (!this.navigateTo) return null;
    this.turns.push(turn);
    return { destination: { sessionId: this.navigateTo }, task: this.handoffTask };
  }

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
  const events: RuntimeEvent[] = [];
  for await (const event of runtime.run(request)) events.push(event);
  return events;
}

describe("AgentRuntime", () => {
  it("persists explicit memory and supplies it to the shared backend", async () => {
    const { store, backend, runtime } = testRuntime();
    const events = await collect(runtime, { text: "Please remember that Mario likes short answers", channel: "api" });
    const session = events.find((event) => event.type === "session")?.session;
    expect(session && store.getMessages(session.id).map((message) => message.role)).toEqual(["user", "assistant"]);
    expect(store.searchMemories("personal", "short answers")).toEqual(["Mario likes short answers"]);
    expect(backend.turns[0]?.instructions).toContain("Mario likes short answers");
  });

  it("uses the public run ID for the persisted last-turn snapshot", async () => {
    const { store, runtime } = testRuntime();
    const events: RuntimeEvent[] = [];
    for await (const event of runtime.run({ text: "hello", channel: "cli" }, { runId: "public-run" })) events.push(event);
    const session = events.find((event) => event.type === "session")?.session;
    expect(store.latestRun()).toMatchObject({
      id: "public-run", sessionId: session?.id, state: "complete", output: "",
    });
  });

  it("uses one coordinator instruction without modes, workers, or duplicated project context", async () => {
    const { homeDir, backend, runtime } = testRuntime();
    const session = runtime.openSession({ fresh: true, cwd: homeDir });
    await collect(runtime, { text: "Fix the failing test", sessionId: session.id, cwd: homeDir, channel: "cli" });
    expect(backend.turns[0]?.instructions).toContain("When asked to show earlier messages, use read_history for the saved text.");
    expect(backend.turns[0]?.instructions).not.toMatch(/worker|coding session|model|AGENTS\.md|working directory/i);
  });

  it("reuses one session across CLI, Telegram, and macOS", async () => {
    const { runtime } = testRuntime();
    const cli = await collect(runtime, { text: "hello", channel: "cli" });
    const cliSession = cli.find((event) => event.type === "session")?.session.id;
    const telegram = await collect(runtime, { text: "summarize this note", channel: "telegram" });
    const macos = await collect(runtime, { text: "continue", channel: "macos", sessionId: cliSession });
    expect(telegram.find((event) => event.type === "session")?.session.id).toBe(cliSession);
    expect(macos.find((event) => event.type === "session")?.session.id).toBe(cliSession);
  });

  it("does not replace an unknown requested session with a new one", () => {
    const { runtime, store } = testRuntime();
    expect(() => runtime.prepareTurn({ text: "continue", channel: "api", sessionId: "missing" }))
      .toThrow("Conversation not found.");
    expect(store.listSessions()).toEqual([]);
  });

  it("continues the latest session regardless of inactivity", async () => {
    const { store, runtime } = testRuntime();
    const first = await collect(runtime, { text: "old topic", channel: "cli" });
    const firstSession = first.find((event) => event.type === "session")?.session.id;
    store.db.prepare("UPDATE sessions SET updated_at = ? WHERE id = ?")
      .run(new Date(0).toISOString(), firstSession);

    const next = await collect(runtime, { text: "continue", channel: "telegram" });
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

  it("opens the globally latest session when no selection is supplied", () => {
    const { store, runtime } = testRuntime();
    const older = runtime.openSession({ fresh: true, cwd: "/tmp/older" });
    const latest = runtime.openSession({ fresh: true, cwd: "/tmp/latest" });
    store.db.prepare("UPDATE sessions SET updated_at = ? WHERE id = ?")
      .run(new Date(0).toISOString(), older.id);
    expect(runtime.openSession().id).toBe(latest.id);
    expect(runtime.openSession({ cwd: "/tmp/older" }).id).toBe(older.id);
  });

  it("does not create a conversation for an unknown explicit selection", () => {
    const { store, runtime } = testRuntime();
    expect(() => runtime.openSession({ preferredSessionId: "missing" })).toThrow("Conversation not found.");
    expect(store.listSessions()).toEqual([]);
  });

  it("keeps Telegram's selected session until /new", () => {
    const { store, runtime } = testRuntime();
    const telegram = runtime.openTelegramSession("42");
    runtime.openSession({ fresh: true });
    store.db.prepare("UPDATE sessions SET updated_at = ? WHERE id = ?")
      .run(new Date(0).toISOString(), telegram.id);
    expect(runtime.openTelegramSession("42").id).toBe(telegram.id);
    const fresh = runtime.openTelegramSession("42", { fresh: true });
    expect(fresh.id).not.toBe(telegram.id);
    expect(store.telegramSession("42")).toBe(fresh.id);
    expect(runtime.openTelegramSession("42").id).toBe(fresh.id);
  });

  it("starts a separate session when the user requests a new conversation", async () => {
    const { runtime } = testRuntime();
    const first = await collect(runtime, { text: "first", channel: "cli" });
    const firstSession = first.find((event) => event.type === "session")?.session.id;
    const fresh = runtime.openSession({ fresh: true });
    const next = await collect(runtime, { text: "second", sessionId: fresh.id, channel: "macos" });
    expect(next.find((event) => event.type === "session")?.session.id).not.toBe(firstSession);
  });

  it("navigates to a matching session without storing the lookup conversation", async () => {
    const { store, backend, runtime } = testRuntime();
    const first = await collect(runtime, { text: "Simplify Telegram reconnects", channel: "cli" });
    const firstSession = first.find((event) => event.type === "session")?.session.id;
    backend.navigateTo = firstSession ?? null;

    const fresh = runtime.openSession({ fresh: true });
    const lookup = await collect(runtime, { text: "take me back to the bot restart work", sessionId: fresh.id, channel: "macos" });

    expect(backend.turns.at(-1)?.sessionTools?.[0]?.id).toBe(firstSession);
    expect(lookup).toContainEqual(expect.objectContaining({
      type: "navigate",
      url: `agent://sessions/${firstSession}`,
    }));
    expect(lookup.at(-1)).toEqual({ type: "done", sessionId: firstSession });
    expect(store.listSessions()).toHaveLength(1);
    expect(firstSession && store.getMessages(firstSession).map((message) => message.content))
      .toEqual(["Simplify Telegram reconnects", "Done."]);
  });

  it("binds the terminal directory only when a provisional CLI turn does not navigate", async () => {
    const { homeDir, store, backend, runtime } = testRuntime();
    const source = runtime.openSession({ fresh: true });
    expect(source.cwd).toBeNull();

    const events = await collect(runtime, {
      text: "Inspect this project", sessionId: source.id, cwd: homeDir, channel: "cli",
    });

    expect(events.find((event) => event.type === "session")?.session.cwd).toBe(homeDir);
    expect(backend.turns.at(-1)?.session.cwd).toBe(homeDir);
    expect(store.getSession(source.id)?.cwd).toBe(homeDir);
  });

  it("does not bind the terminal directory when a provisional CLI turn switches sessions", async () => {
    const { homeDir, store, backend, runtime } = testRuntime();
    const target = runtime.openSession({ fresh: true, cwd: "/tmp/target-project" });
    const source = runtime.openSession({ fresh: true });
    backend.navigateTo = target.id;
    backend.handoffTask = "Fix the test";

    const events = await collect(runtime, {
      text: "Resume the target project and fix the test", sessionId: source.id, cwd: homeDir, channel: "cli",
    });

    expect(backend.turns[0]?.session.cwd).toBeNull();
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
    const interrupted = await collect(runtime, { text: "Fix the test", channel: "cli" });
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
      channel: "telegram",
      attachments: [{ id: "voice-1", name: "voice.ogg", mimeType: "audio/ogg", size: 5, path: audioPath }],
    });
    expect(events[0]).toEqual({ type: "status", message: "Listening…" });
    const session = events.find((event) => event.type === "session")?.session;
    expect(session?.cwd).toBeNull();
    expect(session && store.getMessages(session.id)[0]?.content).toBe("Fix the TypeScript test");
    expect(backend.transcriptions).toEqual([audioPath]);
  });

  it("routes a transcribed voice request and keeps the transcript in the destination", async () => {
    const { homeDir, store, backend, runtime } = testRuntime();
    const target = store.createSession({ title: "Saved project" });
    backend.navigateTo = target.id;
    backend.handoffTask = "Fix the test";
    backend.transcription = "Resume the saved project conversation and fix the test";
    const source = runtime.openSession({ fresh: true });
    const events = await collect(runtime, {
      text: "", sessionId: source.id, channel: "telegram",
      attachments: [{ id: "voice-1", name: "voice.ogg", mimeType: "audio/ogg", size: 5, path: join(homeDir, "voice.ogg") }],
    });

    expect(events).toContainEqual(expect.objectContaining({ type: "navigate", continues: true, session: expect.objectContaining({ id: target.id }) }));
    expect(store.getMessages(target.id)[0]).toEqual({ role: "user", content: backend.transcription });
    expect(store.getSession(source.id)).toBeNull();
  });

  it("persists an early voice failure under the public run ID", async () => {
    const { homeDir, store, backend, runtime } = testRuntime();
    backend.failTranscription = true;
    const attachment = { id: "voice-1", name: "voice.ogg", mimeType: "audio/ogg", size: 5, path: join(homeDir, "voice.ogg") };
    const events: RuntimeEvent[] = [];
    for await (const event of runtime.run({ text: "", channel: "telegram", attachments: [attachment] }, { runId: "failed-voice" })) events.push(event);
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
    const events = await collect(runtime, { text: "", channel: "telegram", attachments: [attachment] });
    expect(events.at(-1)).toEqual({ type: "error", message: "The message is empty." });
    const sessionId = store.latestRun()?.sessionId;
    expect(sessionId && store.getMessages(sessionId).map((message) => message.content))
      .toEqual(["Voice message", "The message is empty."]);
  });

  it("carries a CLI-established workspace across clients without classifying the request", async () => {
    const { homeDir, backend, runtime } = testRuntime();
    const cli = await collect(runtime, { text: "Inspect this project", cwd: homeDir, channel: "cli" });
    const sessionId = cli.find((event) => event.type === "session")?.session.id;
    await collect(runtime, { text: "Now fix it", channel: "telegram", sessionId });
    expect(backend.turns.map((turn) => turn.session.cwd)).toEqual([homeDir, homeDir]);
  });
});
