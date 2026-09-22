import { existsSync, readFileSync, realpathSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it, vi } from "vitest";
import type { BackendTurn } from "../conversation/backend.js";
import { AgentRuntime } from "../conversation/runtime.js";
import { Store } from "../conversation/store.js";
import type { RuntimeConfig } from "../conversation/types.js";
import { cleanup, temporary } from "../test-support.js";
import { CodexAppServer } from "./app-server.js";
import { CodexBackend } from "./backend.js";

const fixture = join(dirname(fileURLToPath(import.meta.url)), "test-fixtures", "fake-app-server.mjs");

function client(scenario: string, extra: NodeJS.ProcessEnv = {}): CodexAppServer {
  const appServer = new CodexAppServer({
    command: process.execPath,
    args: [fixture],
    env: { ...process.env, AGENT_FAKE_SCENARIO: scenario, ...extra },
  });
  cleanup(() => appServer.stop());
  return appServer;
}

function trackedStore(homeDir: string): Store {
  const value = new Store(homeDir);
  cleanup(() => value.close());
  return value;
}

const requests = (log: string) => readFileSync(log, "utf8").trim().split("\n")
  .map((line) => JSON.parse(line) as {
    method: string;
    params: Record<string, unknown>;
    id?: number | string;
    result?: Record<string, unknown>;
  });

const config = (homeDir: string): RuntimeConfig => ({ homeDir, port: 0, codexCommand: "codex" });

function turn(store: Store, homeDir: string, workspace = true): BackendTurn {
  const session = store.createSession({ ...(workspace ? { cwd: homeDir } : {}), title: "test" });
  return {
    request: { text: "Fix the test", cwd: homeDir, channel: "api" },
    session,
    instructions: "Act as Agent. Use the supplied memory.",
  };
}

async function collect(backend: CodexBackend, input: BackendTurn) {
  const events = [];
  for await (const event of backend.run(input)) events.push(event);
  return events;
}

function backendFixture(scenario = "normal", extra: NodeJS.ProcessEnv = {}) {
  const homeDir = temporary("agent-codex-");
  const log = join(homeDir, "rpc.log");
  const store = trackedStore(homeDir);
  const backend = new CodexBackend(config(homeDir), store, client(scenario, { AGENT_FAKE_LOG: log, ...extra }));
  return { homeDir, log, store, backend, input: turn(store, homeDir) };
}

describe("Codex turn transport", () => {
  it("normalizes streamed agent and tool events", async () => {
    const { store, backend, input } = backendFixture();
    const events = await collect(backend, input);
    expect(events.map((event) => event.type)).toEqual(["tool_start", "tool_end", "text_delta", "done"]);
    expect(events.find((event) => event.type === "text_delta")).toMatchObject({ delta: "Hello from Codex." });
    expect(store.codexThread(input.session.id)).toBe("thread-1");
  });

  it("steers the active Codex turn and persists the added user instruction", async () => {
    const fixture = backendFixture("cancel");
    const controller = new AbortController();
    const running = collect(fixture.backend, { ...fixture.input, signal: controller.signal }).catch(() => []);
    await vi.waitFor(() => expect(requests(fixture.log).some((request) => request.method === "turn/start")).toBe(true));

    await expect(fixture.backend.steer(fixture.input.session.id, "Focus on the failing tests first.")).resolves.toBe(true);
    expect(fixture.store.getMessages(fixture.input.session.id)).toContainEqual({
      role: "user", content: "Focus on the failing tests first.",
    });
    expect(requests(fixture.log).find((request) => request.method === "turn/steer")?.params).toMatchObject({
      threadId: "thread-1", expectedTurnId: "turn-1",
    });
    controller.abort();
    await running;
  });

  it("lets Codex compact context without changing the shared event contract", async () => {
    const { backend, input, store } = backendFixture("context-compaction");
    const events = await collect(backend, input);
    expect(events.map((event) => event.type)).toEqual(["tool_start", "tool_end", "text_delta", "done"]);
    expect(store.codexThread(input.session.id)).toBe("thread-1");
  });

  it("keeps using the same Codex thread after repeated native compactions", async () => {
    const fixture = backendFixture("context-compaction");
    for (const text of ["First", "Second", "Third", "Continue"]) {
      await collect(fixture.backend, { ...fixture.input, request: { ...fixture.input.request, text } });
    }

    expect(fixture.store.codexThread(fixture.input.session.id)).toBe("thread-1");
    const rpc = requests(fixture.log);
    expect(rpc.filter((request) => request.method === "thread/start")).toHaveLength(1);
    expect(rpc.filter((request) => request.method === "thread/resume")).toHaveLength(3);
    expect(rpc.filter((request) => request.method === "turn/start").map((request) => request.params.threadId))
      .toEqual(["thread-1", "thread-1", "thread-1", "thread-1"]);
  });

  it("streams Opus through private Codex realtime for runtime-owned transcription", async () => {
    const homeDir = temporary("agent-codex-voice-");
    const log = join(homeDir, "rpc.log");
    const audioPath = join(homeDir, "voice.ogg");
    writeFileSync(audioPath, Buffer.from("T2dnUwACAAAAAAAAAAA4TQibAAAAABbLz/IBE09wdXNIZWFkAQE4AYC7AAAAAABPZ2dTAAAAAAAAAAAAADhNCJsBAAAACYU5GQE8T3B1c1RhZ3MMAAAATGF2ZjYzLjEuMTAyAQAAABwAAABlbmNvZGVyPUxhdmM2My4xLjEwMiBsaWJvcHVzT2dnUwAEuAgAAAAAAAA4TQibAgAAAASvZ7YDDRYOCINtgtAc/epJ/gE/wAinGl2KmC5fbwXLShrtt/PI1gXBXsAIBm0zkArsfUCzkSIpxA==", "base64"));
    const store = trackedStore(homeDir);
    const accepted: string[] = [];
    const sent: number[] = [];
    const backend = new CodexBackend(config(homeDir), store, client("normal", { AGENT_FAKE_LOG: log }), () => ({
      offer: async () => "fake-offer",
      accept: async (sdp) => { accepted.push(sdp); },
      sendAudio: async (audio) => { sent.push(audio.frames.length); },
      close: async () => undefined,
    }));
    await expect(backend.transcribeAudio({
      id: "voice-1", name: "voice.ogg", mimeType: "audio/ogg", size: 214, path: audioPath,
    })).resolves.toBe("Hello from Codex.");
    const rpc = requests(log);
    expect(rpc.some((request) => request.method === "turn/start")).toBe(false);
    expect(rpc.find((request) => request.method === "thread/realtime/start")?.params).toMatchObject({
      outputModality: "audio",
      includeStartupContext: false,
      clientManagedHandoffs: true,
      version: "v3",
      transport: { type: "webrtc", sdp: "fake-offer" },
    });
    expect(accepted).toEqual(["fake-answer"]);
    expect(sent[0]).toBeGreaterThan(0);
    expect(rpc.some((request) => request.method === "thread/realtime/appendAudio")).toBe(false);
    expect(rpc.at(-1)?.method).toBe("thread/realtime/stop");
    expect(readFileSync(log, "utf8")).not.toContain("OPENAI_API_KEY");
  });

  it("copies generated images into one backend-neutral artifact event", async () => {
    const homeDir = temporary("agent-codex-artifact-");
    const generated = join(homeDir, "generated.png");
    writeFileSync(generated, "png-data");
    const store = trackedStore(homeDir);
    const backend = new CodexBackend(config(homeDir), store, client("image", { AGENT_FAKE_ARTIFACT: generated }));
    const events = await collect(backend, turn(store, homeDir));
    const event = events.find((candidate) => candidate.type === "artifact");
    expect(event).toMatchObject({ type: "artifact", artifact: { kind: "image", name: "generated.png", mimeType: "image/png" } });
    expect(event?.type === "artifact" && event.artifact.path).not.toBe(generated);
    expect(event?.type === "artifact" && existsSync(event.artifact.path)).toBe(true);
  });

  it("uses one Luna turn with a workspace boundary instead of routing through workers", async () => {
    const { backend, input, log } = backendFixture();
    await collect(backend, input);
    const rpc = requests(log);
    const threads = rpc.filter((request) => request.method === "thread/start");
    expect(threads.map((request) => request.params.model)).toEqual(["gpt-5.6-luna"]);
    expect(threads.map((request) => request.params.sandbox)).toEqual(["workspace-write"]);
    expect(threads.map((request) => request.params.ephemeral)).toEqual([false]);
    expect(rpc.filter((request) => request.method === "turn/start").map((request) => request.params.effort)).toEqual(["high"]);
  });

  it("keeps sessions without a selected workspace read-only", async () => {
    const homeDir = temporary("agent-codex-personal-");
    const log = join(homeDir, "rpc.log");
    const store = trackedStore(homeDir);
    const backend = new CodexBackend(config(homeDir), store, client("normal", { AGENT_FAKE_LOG: log }));
    await collect(backend, turn(store, homeDir, false));
    expect(requests(log).find((request) => request.method === "thread/start")?.params.sandbox).toBe("read-only");
  });

  it("reads saved messages from the active conversation on demand", async () => {
    const { backend, input, log, store } = backendFixture("history");
    store.addMessage(input.session.id, "user", "Earlier question");
    store.addMessage(input.session.id, "assistant", "Earlier answer");
    await collect(backend, { ...input, request: { ...input.request, text: "Show earlier messages" } });
    await collect(backend, { ...input, request: { ...input.request, text: "Show them again" } });
    const rpc = requests(log);
    expect(rpc.find((request) => request.method === "thread/start")?.params.dynamicTools)
      .toEqual([expect.objectContaining({ name: "read_history" })]);
    expect(rpc.find((request) => request.method === "thread/resume")?.params.dynamicTools)
      .toEqual([expect.objectContaining({ name: "read_history" })]);
    const result = rpc.find((request) => request.id === "read-history")?.result;
    expect(result?.success).toBe(true);
    expect(JSON.parse((result?.contentItems as { text: string }[])[0]!.text).messages)
      .toEqual([{ role: "user", content: "Earlier question" }, { role: "assistant", content: "Earlier answer" }]);
  });

  it("routes a folder request through an ephemeral turn and opens a new project session", async () => {
    const project = temporary("agent-open-project-");
    const cwd = realpathSync(project);
    const { backend, homeDir, log, store } = backendFixture("workspace-open", { AGENT_FAKE_WORKSPACE: project });
    const runtime = new AgentRuntime(store, backend);
    const session = runtime.openSession({ fresh: true });
    const opened = [];
    for await (const event of runtime.run({ text: "Open this project", sessionId: session.id, channel: "telegram" })) opened.push(event);

    expect(opened).toContainEqual(expect.objectContaining({ type: "navigate", session: expect.objectContaining({ cwd }), continues: false }));
    expect(opened).not.toContainEqual({ type: "text_delta", delta: "Stale turn text." });
    const destination = opened.find((event) => event.type === "navigate")?.session;
    expect(destination?.id).not.toBe(session.id);
    expect(store.getSession(session.id)).toBeNull();
    expect(destination && store.getMessages(destination.id)).toEqual([]);

    for await (const _event of runtime.run({ text: "Now fix it", sessionId: destination?.id, channel: "macos" })) { /* consume */ }
    const rpc = requests(log);
    const started = rpc.find((request) => request.method === "thread/start")?.params;
    expect(started).toMatchObject({ cwd: homeDir, sandbox: "read-only", ephemeral: true });
    expect(started?.dynamicTools).toEqual(expect.arrayContaining([expect.objectContaining({ name: "open_folder" })]));
    expect(rpc.find((request) => request.id === "open-folder")?.result).toMatchObject({ success: true });
    expect(rpc.filter((request) => request.method === "thread/start").at(-1)?.params).toMatchObject({
      cwd,
      sandbox: "workspace-write",
      ephemeral: false,
    });
  });

  it("runs follow-on work only in the new project conversation", async () => {
    const project = temporary("agent-open-project-task-");
    const cwd = realpathSync(project);
    const { backend, log, store } = backendFixture("workspace-open-task", { AGENT_FAKE_WORKSPACE: project });
    const runtime = new AgentRuntime(store, backend);
    const source = store.createSession({ title: "Earlier discussion" });
    store.addMessage(source.id, "user", "Discuss another topic");
    const prompt = "Go to this project and fix the tests";
    const events = [];
    for await (const event of runtime.run({ text: prompt, sessionId: source.id, channel: "macos" })) events.push(event);

    const navigation = events.find((event) => event.type === "navigate");
    expect(navigation).toMatchObject({ type: "navigate", continues: true, session: { cwd } });
    const target = navigation?.type === "navigate" ? navigation.session : null;
    expect(target?.id).not.toBe(source.id);
    expect(events.map((event) => event.type)).toEqual([
      "navigate", "session", "turn", "tool_start", "tool_end", "text_delta", "done",
    ]);
    expect(store.getMessages(source.id)).toEqual([{ role: "user", content: "Discuss another topic" }]);
    expect(target && store.getMessages(target.id).map((message) => message.role)).toEqual(["user", "tool", "assistant"]);
    expect(target && store.getMessages(target.id)[0]?.content).toBe(prompt);
    const rpc = requests(log);
    expect(rpc.filter((request) => request.method === "thread/start").map((request) => request.params)).toMatchObject([
      { ephemeral: true, sandbox: "read-only" },
      { ephemeral: false, cwd, sandbox: "workspace-write" },
    ]);
    expect(rpc.filter((request) => request.method === "turn/start").at(-1)?.params.input).toMatchObject([{ text: prompt }]);
  });

  it("selects a saved conversation in a temporary turn", async () => {
    const { backend, input, log, store } = backendFixture("session-navigation");
    const saved = store.createSession({ title: "Telegram reconnects" });
    store.addMessage(saved.id, "user", "Simplify the Telegram reconnect flow");
    const sessionTools = store.sessionCards().filter((session) => session.id === saved.id);

    const handoff = await backend.route({ ...input, request: { ...input.request, text: "Resume the conversation about Telegram reconnects" }, sessionTools });

    expect(handoff).toEqual({ destination: { sessionId: saved.id }, task: null });
    const rpc = requests(log);
    expect(rpc.find((request) => request.method === "thread/start")?.params).toMatchObject({
      ephemeral: true,
      dynamicTools: [
        expect.objectContaining({ name: "open_folder" }),
        expect.objectContaining({ name: "list_conversations" }),
        expect.objectContaining({ name: "read_conversation" }),
        expect.objectContaining({ name: "open_conversation" }),
      ],
    });
    expect(rpc.find((request) => request.id === "list-conversations")?.result).toMatchObject({ success: true });
    expect(rpc.find((request) => request.id === "read-conversation")?.result).toMatchObject({ success: true });
    const listed = JSON.parse((rpc.find((request) => request.id === "list-conversations")?.result?.contentItems as { text: string }[])[0]!.text);
    const read = JSON.parse((rpc.find((request) => request.id === "read-conversation")?.result?.contentItems as { text: string }[])[0]!.text);
    expect(listed).toEqual(sessionTools);
    expect(read.messages).toContainEqual({ role: "user", content: "Simplify the Telegram reconnect flow" });
    expect(rpc.find((request) => request.id === "open-conversation")?.result).toMatchObject({ success: true });

    expect(rpc.some((request) => request.method === "thread/unsubscribe")).toBe(true);
    expect(rpc.some((request) => request.method === "thread/delete")).toBe(false);
  });

  it("does not expose the temporary turn's assistant text", async () => {
    const { backend, input, store } = backendFixture("session-navigation-completed");
    const saved = store.createSession({ title: "Telegram reconnects" });
    const handoff = await backend.route({
      ...input,
      request: { ...input.request, text: "Resume the conversation about Telegram reconnects" },
      sessionTools: store.sessionCards().filter((session) => session.id === saved.id),
    });

    expect(handoff).toEqual({ destination: { sessionId: saved.id }, task: null });
  });

  it("resumes an existing conversation and forwards follow-on work without altering the source", async () => {
    const { backend, log, store } = backendFixture("session-navigation-task");
    const runtime = new AgentRuntime(store, backend);
    const source = store.createSession({ title: "Current discussion" });
    store.addMessage(source.id, "user", "Earlier source topic");
    const saved = store.createSession({ title: "Telegram reconnects" });
    store.addMessage(saved.id, "user", "Simplify the Telegram reconnect flow");
    store.bindCodexThread(saved.id, "saved-thread");
    const prompt = "Resume the conversation about Telegram reconnects and fix the reconnect flow";
    const events = [];
    for await (const event of runtime.run({ text: prompt, sessionId: source.id, channel: "cli" })) events.push(event);

    expect(events).toContainEqual(expect.objectContaining({
      type: "navigate", continues: true, session: expect.objectContaining({ id: saved.id }),
    }));
    expect(events.at(-1)).toEqual({ type: "done", sessionId: saved.id });
    expect(store.getMessages(source.id)).toEqual([{ role: "user", content: "Earlier source topic" }]);
    expect(store.getMessages(saved.id).map((message) => message.role)).toEqual(["user", "user", "tool", "assistant"]);
    expect(requests(log).find((request) => request.method === "thread/resume")?.params.threadId).toBe("saved-thread");
  });

  it("does not run follow-on work in the old folder when routing cannot choose a destination", async () => {
    const { backend, log, store } = backendFixture("normal");
    const runtime = new AgentRuntime(store, backend);
    const source = store.createSession({ cwd: "/tmp/old-project" });
    const events = [];
    for await (const event of runtime.run({ text: "Go to project X and fix the tests", sessionId: source.id })) events.push(event);

    expect(events.at(-1)).toEqual({ type: "error", message: "Could not identify the project or conversation to open." });
    expect(requests(log).filter((request) => request.method === "thread/start").map((request) => request.params.ephemeral))
      .toEqual([true]);
    expect(store.getMessages(source.id).map((message) => message.role)).toEqual(["user", "assistant"]);
  });

  it("preserves the runtime session and event contract", async () => {
    const homeDir = temporary("agent-codex-runtime-");
    const store = trackedStore(homeDir);
    const codex = new CodexBackend(config(homeDir), store, client("normal"));
    const runtime = new AgentRuntime(store, codex);
    const events = [];
    for await (const event of runtime.run({ text: "Fix the test", cwd: homeDir, channel: "api" })) events.push(event);
    expect(events.map((event) => event.type)).toEqual(["session", "tool_start", "tool_end", "text_delta", "done"]);
    const session = events[0]?.type === "session" ? events[0].session : null;
    expect(session && store.getMessages(session.id).map((message) => message.role)).toEqual(["user", "tool", "assistant"]);
  });

  it("interrupts an active turn through turn/interrupt", async () => {
    const { backend, input, log } = backendFixture("cancel");
    const controller = new AbortController();
    const running = collect(backend, { ...input, signal: controller.signal });
    setTimeout(() => controller.abort(), 50);
    await expect(running).rejects.toMatchObject({ name: "AbortError" });
    await new Promise((resolve) => setTimeout(resolve, 30));
    expect(readFileSync(log, "utf8")).toContain("turn/interrupt");
  });

  it("restarts app-server and resumes the opaque Codex thread", async () => {
    const homeDir = temporary("agent-codex-reconnect-marker-");
    const marker = join(homeDir, "restart.marker");
    const fixture = backendFixture("reconnect", { AGENT_FAKE_MARKER: marker });
    const events = await collect(fixture.backend, fixture.input);
    expect(events).toContainEqual({ type: "text_delta", delta: "Hello from Codex." });
    expect(requests(fixture.log).filter((request) => request.method.startsWith("thread/")).map((request) => request.method))
      .toEqual(["thread/start", "thread/resume"]);
  });

  it("resumes the same persistent thread on later turns", async () => {
    const fixture = backendFixture();
    await collect(fixture.backend, fixture.input);
    await collect(fixture.backend, { ...fixture.input, request: { ...fixture.input.request, text: "Continue" } });
    expect(requests(fixture.log).filter((request) => request.method.startsWith("thread/"))
      .map((request) => [request.method, request.params.threadId])).toEqual([
        ["thread/start", undefined],
        ["thread/resume", "thread-1"],
      ]);
  });

  it("does not replace a missing Codex thread", async () => {
    const { backend, input, store, log } = backendFixture("missing-thread");
    store.bindCodexThread(input.session.id, "missing-thread-id");
    await expect(collect(backend, input)).rejects.toThrow("thread not found");
    expect(readFileSync(log, "utf8")).toContain("thread/resume");
    expect(readFileSync(log, "utf8")).not.toContain("thread/start");
    expect(store.codexThread(input.session.id)).toBe("missing-thread-id");
  });

  it.each([
    ["expired", /connection has expired/],
    ["exhausted", /allowance or credits are exhausted/],
  ])("classifies %s account failures", async (scenario, message) => {
    const { backend, input } = backendFixture(scenario);
    await expect(collect(backend, input)).rejects.toThrow(message);
  });
});
