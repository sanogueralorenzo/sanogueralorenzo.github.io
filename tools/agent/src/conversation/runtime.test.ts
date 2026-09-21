import { writeFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import type { AgentBackend, BackendEvent, BackendTurn } from "./backend.js";
import { AgentRuntime } from "./runtime.js";
import { Store } from "./store.js";
import type { Attachment, RuntimeEvent } from "./types.js";
import { cleanup, temporary } from "../test-support.js";

class RecordingBackend implements AgentBackend {
  readonly turns: BackendTurn[] = [];
  readonly transcriptions: string[] = [];
  readonly routes: string[] = [];
  routeTo: string | null = null;
  failNext = false;

  async transcribeAudio(attachment: Attachment): Promise<string> {
    this.transcriptions.push(attachment.path);
    return "Fix the TypeScript test";
  }

  async routeSession(text: string): Promise<string | null> {
    this.routes.push(text);
    return this.routeTo;
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

  it("uses one coordinator instruction without modes, workers, or duplicated project context", async () => {
    const { homeDir, backend, runtime } = testRuntime();
    await collect(runtime, { text: "Fix the failing test", cwd: homeDir, channel: "cli", fresh: true });
    expect(backend.turns[0]?.instructions).toBe("Act on clear requests and persist until complete. Treat new messages as steering unless they clearly cancel or replace the task. Reuse existing authorization and complete reversible preparation before asking. Ask only when a material choice or unapproved irreversible or external action blocks progress.");
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

  it("starts a separate session after eight hours of inactivity", async () => {
    const { store, runtime } = testRuntime();
    const first = await collect(runtime, { text: "old topic", channel: "cli" });
    const firstSession = first.find((event) => event.type === "session")?.session.id;
    store.db.prepare("UPDATE sessions SET updated_at = ? WHERE id = ?")
      .run(new Date(Date.now() - 8 * 60 * 60 * 1_000).toISOString(), firstSession);

    const next = await collect(runtime, { text: "new topic", channel: "telegram", sessionId: firstSession });
    const nextSession = next.find((event) => event.type === "session")?.session.id;

    expect(nextSession).not.toBe(firstSession);
    expect(firstSession && store.getMessages(firstSession).map((message) => message.content)).toEqual(["old topic", "Done."]);
    expect(nextSession && store.getMessages(nextSession).map((message) => message.content)).toEqual(["new topic", "Done."]);
  });

  it("starts a separate session when the user requests a new conversation", async () => {
    const { runtime } = testRuntime();
    const first = await collect(runtime, { text: "first", channel: "cli" });
    const firstSession = first.find((event) => event.type === "session")?.session.id;
    const next = await collect(runtime, { text: "second", channel: "macos", fresh: true });
    expect(next.find((event) => event.type === "session")?.session.id).not.toBe(firstSession);
  });

  it("navigates to a matching session without storing the lookup conversation", async () => {
    const { store, backend, runtime } = testRuntime();
    const first = await collect(runtime, { text: "Simplify Telegram reconnects", channel: "cli" });
    const firstSession = first.find((event) => event.type === "session")?.session.id;
    backend.routeTo = firstSession ?? null;

    const lookup = await collect(runtime, { text: "take me back to the bot restart work", channel: "macos", fresh: true });

    expect(backend.routes).toEqual(["take me back to the bot restart work"]);
    expect(lookup).toContainEqual(expect.objectContaining({
      type: "navigate",
      url: `agent://sessions/${firstSession}`,
    }));
    expect(lookup.at(-1)).toEqual({ type: "done", sessionId: firstSession });
    expect(store.listSessions()).toHaveLength(1);
    expect(firstSession && store.getMessages(firstSession).map((message) => message.content))
      .toEqual(["Simplify Telegram reconnects", "Done."]);
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

  it("carries a CLI-established workspace across clients without classifying the request", async () => {
    const { homeDir, backend, runtime } = testRuntime();
    const cli = await collect(runtime, { text: "Inspect this project", cwd: homeDir, channel: "cli" });
    const sessionId = cli.find((event) => event.type === "session")?.session.id;
    await collect(runtime, { text: "Now fix it", channel: "telegram", sessionId });
    expect(backend.turns.map((turn) => turn.session.cwd)).toEqual([homeDir, homeDir]);
  });
});
