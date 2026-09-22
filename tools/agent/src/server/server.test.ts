import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it, vi } from "vitest";
import { AgentRuntime } from "../conversation/runtime.js";
import type { AgentBackend } from "../conversation/backend.js";
import { Store } from "../conversation/store.js";
import type { RuntimeConfig, RuntimeEvent } from "../conversation/types.js";
import { cleanup, temporary } from "../test-support.js";
import { RuntimeClient } from "../client/client.js";
import { MAX_EVENT_BUFFER_BYTES } from "../conversation/runs.js";
import { RuntimeServer, type RuntimeSetup } from "./server.js";
import type { RunEnvelope } from "../conversation/types.js";

function setupStub(overrides: Partial<RuntimeSetup> = {}): RuntimeSetup {
  return {
    status: async () => ({
      configured: false,
      authMode: null,
      codex: { installed: false, connected: false },
    }),
    connectApiKey: async () => undefined,
    startCodexLogin: async () => ({ type: "chatgpt", loginId: "login", authUrl: "https://auth.openai.com/fake" }),
    waitForCodexLogin: async () => ({ state: "complete" }),
    ...overrides,
  };
}

const tokenAt = (homeDir: string) => JSON.parse(readFileSync(join(homeDir, "runtime.json"), "utf8")).token as string;

async function serve(runtime: AgentRuntime | ((store: Store) => AgentRuntime), setup = setupStub()) {
  const homeDir = temporary("agent-server-");
  const store = new Store(homeDir);
  const config: RuntimeConfig = { homeDir, port: 0, codexCommand: "codex" };
  const value = typeof runtime === "function" ? runtime(store) : runtime;
  if (!value.prepareTurn) {
    const preparer = new AgentRuntime(store, {} as AgentBackend);
    value.prepareTurn = preparer.prepareTurn.bind(preparer);
    value.openSession = preparer.openSession.bind(preparer);
  }
  const server = new RuntimeServer(config, value, store, setup);
  const port = await server.listen();
  const token = tokenAt(homeDir);
  const headers = { authorization: `Bearer ${token}`, "content-type": "application/json" };
  cleanup(async () => { await server.close(); store.close(); });
  const request = (path: string, method = "GET", body?: unknown) => fetch(`http://127.0.0.1:${port}${path}`, {
    method, headers, ...(body === undefined ? {} : { body: JSON.stringify(body) }),
  });
  return { port, token, headers, request, client: new RuntimeClient(homeDir) };
}

async function collectRun(events: AsyncIterable<RunEnvelope>): Promise<RunEnvelope[]> {
  const result: RunEnvelope[] = [];
  for await (const event of events) {
    result.push(event);
    if (event.event.type === "done" || event.event.type === "error") break;
  }
  return result;
}

describe("RuntimeServer", () => {
  it("opens an idle event stream immediately", async () => {
    const runtime = { async *run() {} } as unknown as AgentRuntime;
    const { request } = await serve(runtime);
    const response = await request("/v1/events");
    const first = await response.body!.getReader().read();
    expect(new TextDecoder().decode(first.value)).toBe(": connected\n\n");
  });

  it("authenticates clients and publishes one shared run stream", async () => {
    let receivedTurn: Record<string, unknown> | undefined;
    const runtime = {
      async *run(turn: Record<string, unknown>): AsyncGenerator<RuntimeEvent> {
        receivedTurn = turn;
        yield { type: "turn", text: "hello", channel: "api", hasAttachments: true };
        yield { type: "status", message: "ready" };
        yield { type: "text_delta", delta: "hello" };
        yield { type: "done", sessionId: "session" };
      },
    } as unknown as AgentRuntime;
    const { port, token, client } = await serve(runtime);
    const unauthorized = await fetch(`http://127.0.0.1:${port}/v1/sessions`);
    expect(unauthorized.status).toBe(401);
    const uploaded = await fetch(`http://127.0.0.1:${port}/v1/attachments`, {
      method: "POST",
      headers: {
        authorization: `Bearer ${token}`,
        "content-type": "audio/ogg",
        "x-agent-filename": encodeURIComponent("voice note.ogg"),
      },
      body: Buffer.from("voice-data"),
    });
    expect(uploaded.status).toBe(201);
    const attachment = await uploaded.json() as { id: string; path?: string };
    expect(attachment.path).toBeUndefined();
    const session = await client.openSession({ fresh: true });
    const [firstFeed, secondFeed] = await Promise.all([client.events(), client.events()]);
    const firstEvents = collectRun(firstFeed);
    const secondEvents = collectRun(secondFeed);
    const run = await client.submit({
      text: "hello", sessionId: session.id, attachmentIds: [attachment.id], channel: "api",
    });
    const [firstStream, secondStream] = await Promise.all([firstEvents, secondEvents]);
    expect(run).not.toBeNull();
    expect(firstStream).toEqual(secondStream);
    expect(firstStream.map(({ event }) => event.type)).toEqual(["snapshot", "session_activity", "turn", "status", "text_delta", "done"]);
    expect(firstStream.slice(1).every((event) => event.runId === run?.id)).toBe(true);
    expect(receivedTurn).toMatchObject({
      text: "hello",
      attachmentIds: [attachment.id],
      attachments: [{ id: attachment.id, name: "voice note.ogg", mimeType: "audio/ogg" }],
    });
  });

  it("keeps a run alive when a subscriber disconnects and stops it explicitly", async () => {
    let interrupted!: () => void;
    const interruption = new Promise<void>((resolve) => { interrupted = resolve; });
    const runtime = {
      async *run(_turn: unknown, options: { signal: AbortSignal }): AsyncGenerator<RuntimeEvent> {
        options.signal.addEventListener("abort", () => interrupted(), { once: true });
        yield { type: "status", message: "working" };
        await new Promise<void>((resolve) => options.signal.addEventListener("abort", () => resolve(), { once: true }));
      },
    } as unknown as AgentRuntime;
    const { client } = await serve(runtime);
    const session = await client.openSession({ fresh: true });
    const observer = (await client.events())[Symbol.asyncIterator]();
    const run = await client.submit({ text: "hello", sessionId: session.id, channel: "api" });
    await observer.next();
    await observer.return?.();
    expect(await client.submit({ text: "second", sessionId: session.id, channel: "telegram" })).toBeNull();
    expect(await client.stop(run!.id)).toBe(true);
    await expect(interruption).resolves.toBeUndefined();
  });

  it("runs two sessions independently and stops only the selected run", async () => {
    const release = new Map<string, () => void>();
    const { client } = await serve((store) => new AgentRuntime(store, {
      async route() { return null; },
      async *run({ session, signal }) {
        await new Promise<void>((resolve) => {
          release.set(session.id, resolve);
          signal?.addEventListener("abort", resolve, { once: true });
        });
        if (signal?.aborted) throw new Error("aborted");
        yield { type: "text_delta", delta: `Answer for ${session.id}` };
        yield { type: "done" };
      },
      async transcribeAudio() { return ""; },
    } as AgentBackend));
    const first = await client.openSession({ fresh: true });
    const second = await client.openSession({ fresh: true });
    const firstRun = await client.submit({ text: "first", sessionId: first.id, channel: "cli" });
    const secondRun = await client.submit({ text: "second", sessionId: second.id, channel: "macos" });
    await vi.waitFor(() => expect(release.size).toBe(2));
    expect(await client.submit({ text: "overlap", sessionId: first.id, channel: "telegram" })).toBeNull();
    const statuses = (await client.sessions()).sessions;
    expect(statuses.find((item) => item.id === first.id)?.activeRunId).toBe(firstRun?.id);
    expect(statuses.find((item) => item.id === second.id)?.activeRunId).toBe(secondRun?.id);
    expect(await client.stop(firstRun!.id)).toBe(true);
    await vi.waitFor(async () => expect((await client.sessions()).sessions.find((item) => item.id === first.id)?.activeRunId).toBeNull());
    expect((await client.sessions()).sessions.find((item) => item.id === second.id)?.activeRunId).toBe(secondRun?.id);
    release.get(second.id)!();
    await vi.waitFor(async () => expect((await client.transcript(second.id)).messages.at(-1)?.content).toBe(`Answer for ${second.id}`));
    expect((await client.transcript(first.id)).messages).toMatchObject([{ role: "user", content: "first" }]);
  });

  it("keeps Telegram on its persisted conversation across other clients and /new", async () => {
    const { client } = await serve((store) => new AgentRuntime(store, {
      async route() { return null; },
      async *run() { yield { type: "text_delta", delta: "Done." }; yield { type: "done" }; },
      async transcribeAudio() { return ""; },
    } as AgentBackend));
    const cli = await client.openSession({ fresh: true });
    expect((await client.telegramSession("42")).id).toBe(cli.id);
    const other = await client.openSession({ fresh: true });
    expect((await client.telegramSession("42")).id).toBe(cli.id);
    const stream = (await client.events(undefined, cli.id))[Symbol.asyncIterator]();
    expect((await stream.next()).value).toMatchObject({ sessionId: cli.id, event: { type: "snapshot" } });
    await client.submit({ text: "other work", sessionId: other.id, channel: "macos" });
    expect((await stream.next()).value?.event.type).toBe("session_activity");
    const fresh = await client.telegramSession("42", { fresh: true });
    expect(fresh.id).not.toBe(cli.id);
    expect((await client.telegramSession("42")).id).toBe(fresh.id);
    await stream.return?.();
  });

  it("keeps session content off other sessions' streams while signaling list changes", async () => {
    const { client } = await serve((store) => new AgentRuntime(store, {
      async route() { return null; },
      async *run() { yield { type: "text_delta", delta: "private answer" }; yield { type: "done" }; },
      async transcribeAudio() { return ""; },
    } as AgentBackend));
    const first = await client.openSession({ fresh: true });
    const second = await client.openSession({ fresh: true });
    const stream = (await client.events(undefined, first.id))[Symbol.asyncIterator]();
    expect((await stream.next()).value).toMatchObject({ sessionId: first.id, event: { type: "snapshot" } });
    await client.submit({ text: "second session", sessionId: second.id, channel: "macos" });
    expect((await stream.next()).value).toMatchObject({ sessionId: second.id, event: { type: "session_activity" } });
    expect((await stream.next()).value).toMatchObject({ sessionId: second.id, event: { type: "session_activity", runId: null } });
    await stream.return?.();
    expect((await client.transcript(first.id)).messages).toEqual([]);
    expect((await client.transcript(second.id)).messages.at(-1)?.content).toBe("private answer");
  });

  it("redirects a scoped client that missed conversation navigation", async () => {
    let destination = "";
    const { client } = await serve((store) => {
      const saved = store.createSession({ title: "Saved work" });
      store.addMessage(saved.id, "user", "Earlier work");
      destination = saved.id;
      return new AgentRuntime(store, {
        async route() { return { destination: { sessionId: destination }, task: null }; },
        async *run() { yield { type: "done" }; },
        async transcribeAudio() { return ""; },
      } as AgentBackend);
    });
    const temporarySession = await client.openSession({ fresh: true });
    const live = collectRun(await client.events());
    await client.submit({ text: "resume the conversation about earlier work", sessionId: temporarySession.id, channel: "cli" });
    await live;

    const reconnect = (await client.events(undefined, temporarySession.id))[Symbol.asyncIterator]();
    expect((await reconnect.next()).value).toMatchObject({
      sessionId: temporarySession.id,
      event: { type: "navigate", session: { id: destination, title: "Saved work" } },
    });
    await reconnect.return?.();
    expect((await client.openSession({ preferredSessionId: temporarySession.id })).id).toBe(destination);
    expect(await client.transcript(temporarySession.id)).toMatchObject({
      session: { id: destination },
      messages: [{ role: "user", content: "Earlier work" }],
    });
    expect((await client.sessions()).sessions.map((item) => item.id)).not.toContain(temporarySession.id);
  });

  it("recovers an in-progress handoff from an existing conversation by run ID", async () => {
    let targetId = "";
    let release!: () => void;
    let turns = 0;
    const waiting = new Promise<void>((resolve) => { release = resolve; });
    const { client } = await serve((store) => {
      const target = store.createSession({ title: "Saved project" });
      targetId = target.id;
      return new AgentRuntime(store, {
        async route({ request }) { return request.text.startsWith("Resume")
          ? { destination: { sessionId: targetId }, task: "Finish the work" } : null; },
        async *run() { if (++turns > 1) await waiting; yield { type: "text_delta", delta: "Finished." }; yield { type: "done" }; },
        async transcribeAudio() { return ""; },
      } as AgentBackend);
    });
    const source = await client.openSession({ fresh: true });
    await client.submit({ text: "Earlier topic", sessionId: source.id, channel: "cli" });
    await vi.waitFor(async () => expect((await client.transcript(source.id)).messages.at(-1)?.content).toBe("Finished."));
    const run = await client.submit({ text: "Resume the conversation about the saved project and finish the work", sessionId: source.id, channel: "cli" });
    await vi.waitFor(async () => expect((await client.sessions()).sessions.find((item) => item.id === targetId)?.activeRunId).toBe(run?.id));

    const reconnect = (await client.events(undefined, source.id, run?.id))[Symbol.asyncIterator]();
    expect((await reconnect.next()).value).toMatchObject({
      sessionId: source.id, runId: run?.id,
      event: { type: "navigate", continues: true, session: { id: targetId } },
    });
    await reconnect.return?.();
    const target = (await client.events(undefined, targetId))[Symbol.asyncIterator]();
    expect((await target.next()).value).toMatchObject({ event: { type: "snapshot", snapshot: {
      activeRuns: [{ run: { id: run?.id } }],
    } } });
    await target.return?.();
    release();
    await vi.waitFor(async () => expect((await client.transcript(targetId)).messages.at(-1)?.content).toBe("Finished."));
    expect((await client.transcript(source.id)).messages.map((message) => message.content)).toEqual(["Earlier topic", "Finished."]);
  });

  it("does not forward work into a conversation that is already busy", async () => {
    let targetId = "";
    let release!: () => void;
    const waiting = new Promise<void>((resolve) => { release = resolve; });
    const { client } = await serve((store) => {
      targetId = store.createSession({ title: "Busy project" }).id;
      return new AgentRuntime(store, {
        async route({ request }) { return request.text.startsWith("Resume")
          ? { destination: { sessionId: targetId }, task: "Do more work" } : null; },
        async *run({ session }) {
          if (session.id === targetId) await waiting;
          yield { type: "text_delta", delta: "Done." };
          yield { type: "done" };
        },
        async transcribeAudio() { return ""; },
      } as AgentBackend);
    });
    const source = await client.openSession({ fresh: true });
    await client.submit({ text: "Current topic", sessionId: source.id, channel: "cli" });
    await vi.waitFor(async () => expect((await client.transcript(source.id)).messages.at(-1)?.content).toBe("Done."));
    const active = await client.submit({ text: "Stay busy", sessionId: targetId, channel: "macos" });
    await vi.waitFor(async () => expect((await client.sessions()).sessions.find((item) => item.id === targetId)?.activeRunId).toBe(active?.id));
    await client.submit({ text: "Resume the busy project conversation and do more work", sessionId: source.id, channel: "cli" });
    await vi.waitFor(async () => expect((await client.transcript(source.id)).messages.at(-1)?.content).toBe("Agent is already working in this conversation."));
    expect((await client.transcript(source.id)).messages[0]?.content).toBe("Current topic");
    expect((await client.transcript(targetId)).messages.map((message) => message.content)).toEqual(["Stay busy"]);
    release();
    await vi.waitFor(async () => expect((await client.transcript(targetId)).messages.at(-1)?.content).toBe("Done."));
  });

  it("hydrates a late connection with the current output before live updates", async () => {
    let release!: () => void;
    let reached!: () => void;
    const paused = new Promise<void>((resolve) => { release = resolve; });
    const reachedPause = new Promise<void>((resolve) => { reached = resolve; });
    const runtime = {
      async *run(): AsyncGenerator<RuntimeEvent> {
        yield { type: "text_delta", delta: "first" };
        reached();
        await paused;
        yield { type: "text_delta", delta: " second" };
        yield { type: "done", sessionId: "s1" };
      },
    } as unknown as AgentRuntime;
    const { client } = await serve(runtime);
    const session = await client.openSession({ fresh: true });
    const run = await client.submit({ text: "hello", sessionId: session.id, channel: "cli" });
    await reachedPause;
    const feed = (await client.events())[Symbol.asyncIterator]();
    expect((await feed.next()).value).toMatchObject({ event: { type: "snapshot", snapshot: {
      activeRuns: [{ run: { id: run?.id }, output: "first" }],
    } } });
    release();
    expect((await feed.next()).value).toMatchObject({ runId: run?.id, event: { type: "text_delta", delta: " second" } });
    expect((await feed.next()).value?.event.type).toBe("done");
    await feed.return?.();
  });

  it("recovers a missed completion from the saved transcript and matching run ID", async () => {
    const { client } = await serve((store) => new AgentRuntime(store, {
      async route() { return null; },
      async *run() { yield { type: "text_delta", delta: "saved answer" }; yield { type: "done" }; },
      async transcribeAudio() { return ""; },
    } as AgentBackend));
    const session = await client.openSession({ fresh: true });
    const observed = collectRun(await client.events());
    const run = await client.submit({ text: "hello", sessionId: session.id, channel: "cli" });
    await observed;
    const late = (await client.events())[Symbol.asyncIterator]();
    const snapshot = (await late.next()).value;
    expect(snapshot).toMatchObject({ event: { type: "snapshot", snapshot: {
      transcript: { messages: [{ role: "user", content: "hello" }, { role: "assistant", content: "saved answer" }] },
      activeRuns: [],
      lastRuns: [{ id: run?.id, state: "complete" }],
    } } });
    await late.return?.();
  });

  it("closes an oversized event stream without stopping the runtime", async () => {
    let completed = false;
    const runtime = {
      async *run(): AsyncGenerator<RuntimeEvent> {
        yield { type: "text_delta", delta: "x".repeat(MAX_EVENT_BUFFER_BYTES) };
        completed = true;
        yield { type: "done", sessionId: "s1" };
      },
    } as unknown as AgentRuntime;
    const { client } = await serve(runtime);
    const session = await client.openSession({ fresh: true });
    const events = await client.events();
    await client.submit({ text: "hi", sessionId: session.id, channel: "api" });
    await expect(collectRun(events)).rejects.toThrow();
    expect(completed).toBe(true);
    expect(await client.healthy()).toBe(true);
  });

  it("exposes shared guided setup endpoints", async () => {
    const runtime = { async *run() {} } as unknown as AgentRuntime;
    let apiKey = "";
    const loginModes: string[] = [];
    const setup = setupStub({
      status: async () => ({
        configured: false,
        authMode: null,
        codex: { installed: true, connected: false },
      }),
      connectApiKey: async (key) => { apiKey = key; },
      startCodexLogin: async (mode) => {
        loginModes.push(mode);
        return mode === "headless"
          ? { type: "chatgptDeviceCode", loginId: "login-2", verificationUrl: "https://auth.openai.com/codex/device", userCode: "Agent-TEST" }
          : { type: "chatgpt", loginId: "login-1", authUrl: "https://auth.openai.com/fake" };
      },
    });
    const { request } = await serve(runtime, setup);

    const status = await request("/v1/setup");
    await expect(status.json()).resolves.toMatchObject({ codex: { installed: true } });
    const missingMode = await request("/v1/setup/codex/login", "POST", {});
    expect(missingMode.status).toBe(400);
    expect(loginModes).toEqual([]);
    expect((await request("/v1/setup/codex/login", "POST", { mode: "browser" })).status).toBe(200);
    expect((await request("/v1/setup/codex/login", "POST", { mode: "headless" })).status).toBe(200);
    expect(loginModes).toEqual(["browser", "headless"]);
    const invalidMode = await request("/v1/setup/codex/login", "POST", { mode: "device" });
    expect(invalidMode.status).toBe(400);
    await expect(invalidMode.json()).resolves.toMatchObject({ error: "login mode must be browser or headless" });
    expect(loginModes).toEqual(["browser", "headless"]);
    const completed = await request("/v1/setup/codex/login/login-1/wait", "POST");
    await expect(completed.json()).resolves.toEqual({ state: "complete" });
    expect((await request("/v1/setup/openai", "POST", { apiKey: "sk-test" })).status).toBe(200);
    expect(apiKey).toBe("sk-test");
  });
});
