import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it, vi } from "vitest";
import type { AgentBackend } from "../conversation/backend.js";
import { AgentRuntime } from "../conversation/runtime.js";
import { RunCoordinator } from "../conversation/runs.js";
import { Store } from "../conversation/store.js";
import { HOME_SESSION_ID, type RuntimeConfig } from "../conversation/types.js";
import { CodexAppServer } from "../codex/app-server.js";
import { cleanup, temporary } from "../test-support.js";
import type { HomeBackend } from "./backend.js";
import { CodexHomeBackend } from "./codex.js";

function worker(run: AgentBackend["run"], steer: AgentBackend["steer"] = async () => false): AgentBackend {
  return { async route() { return null; }, steer, async transcribeAudio() { return ""; }, run };
}

describe("Agent Home", () => {
  it("keeps a greeting in one clickable entry through its final outcome", async () => {
    const store = new Store(temporary("agent-home-"));
    cleanup(() => store.close());
    let release!: () => void;
    const work = new Promise<void>((resolve) => { release = resolve; });
    const backend = worker(async function* () {
      await work;
      yield { type: "text_delta", delta: "Completed the work." };
      yield { type: "done" };
    });
    const home: HomeBackend = {
      async compose() { return [{ type: "start", source: "How are you?", title: "How are you?", text: "Answer the greeting." }]; },
      async summarize() { return { state: "ready", summary: "Work complete." }; },
    };
    const runs = new RunCoordinator(new AgentRuntime(store, backend, home), store);
    const controller = new AbortController();
    const stream = runs.events(controller.signal, undefined, undefined, HOME_SESSION_ID)[Symbol.asyncIterator]();
    const pending = stream.next();
    const requestId = "00000000-0000-4000-8000-000000000001";
    runs.start({ text: "How are you?", requestId, sessionId: store.homeSession().id, channel: "macos" });
    const first = (await pending).value!;
    await vi.waitFor(() => expect(store.home.entries()).toMatchObject([
      { id: requestId, body: "How are you?", state: "working" },
    ]));
    release();
    await vi.waitFor(() => expect(store.home.entries()[0]).toMatchObject({ state: "ready", summary: "Work complete." }));
    expect(first.event).toMatchObject({ type: "home_entry", entry: { id: requestId, body: "How are you?", state: "routing" } });
    controller.abort();
    await stream.return?.();
    await runs.close();
  });

  it("opens separate parallel tasks for independent requests in one message", async () => {
    const store = new Store(temporary("agent-home-multiple-"));
    cleanup(() => store.close());
    let release!: () => void;
    const work = new Promise<void>((resolve) => { release = resolve; });
    const requests: string[] = [];
    const backend = worker(async function* ({ request }) {
      requests.push(request.text);
      await work;
      yield { type: "done" };
    });
    const home: HomeBackend = {
      async compose() { return [
        { type: "start", source: "restaurants in Taipei", title: "Taipei restaurants", text: "Find popular Taipei restaurants." },
        { type: "start", source: "a good air fryer", title: "Air fryer picks", text: "Recommend a good air fryer." },
      ]; },
      async summarize() { return { state: "ready", summary: "Done." }; },
    };
    const runs = new RunCoordinator(new AgentRuntime(store, backend, home), store);
    const requestId = "00000000-0000-4000-8000-000000000002";
    store.homeSession();
    runs.start({ text: "Find restaurants in Taipei and a good air fryer", requestId, sessionId: HOME_SESSION_ID });
    await vi.waitFor(() => expect(store.home.entries()).toHaveLength(2));
    expect(store.home.entries()).toMatchObject([
      { id: requestId, body: "Find restaurants in Taipei and a good air fryer", state: "working" },
      { body: "Find restaurants in Taipei and a good air fryer", state: "working" },
    ]);
    expect(new Set(store.home.entries().map((entry) => entry.sessionId)).size).toBe(2);
    await vi.waitFor(() => expect(requests).toHaveLength(2));
    release();
    await vi.waitFor(() => expect(store.home.entries().map((entry) => entry.state)).toEqual(["ready", "ready"]));
    await runs.close();
  });

  it("keeps source messages on the same task card and starts a new card for separate work", async () => {
    const store = new Store(temporary("agent-home-sources-"));
    cleanup(() => store.close());
    let sessionId = "";
    const firstId = "00000000-0000-4000-8000-000000000031";
    const home: HomeBackend = {
      async compose(request) {
        if (request.text === "First task") return [{ type: "start", source: request.text, title: "First task", text: request.text }];
        return [{ type: "continue", source: request.text, title: request.text, text: request.text,
          sessionId, ...(request.text === "Follow up" ? { entryId: firstId } : {}) }];
      },
      async summarize() { return { state: "ready", summary: "Done." }; },
    };
    const runs = new RunCoordinator(new AgentRuntime(store, worker(async function* () { yield { type: "done" }; }), home), store);
    store.homeSession();
    runs.start({ text: "First task", requestId: firstId, sessionId: HOME_SESSION_ID });
    await vi.waitFor(() => expect(store.home.entry(firstId)?.state).toBe("ready"));
    sessionId = store.home.entry(firstId)!.sessionId!;
    const controller = new AbortController();
    const events = runs.events(controller.signal, undefined, undefined, HOME_SESSION_ID)[Symbol.asyncIterator]();
    const removed = (async () => {
      while (true) {
        const next = await events.next();
        if (next.value?.event.type === "home_entry_removed") return next.value.event.id;
      }
    })();
    const followUpRun = runs.start({ text: "Follow up", sessionId: HOME_SESSION_ID });
    expect(await removed).toBe(followUpRun.id);
    await vi.waitFor(() => expect(store.home.entry(firstId)?.requests.map(({ text }) => text)).toEqual(["First task", "Follow up"]));
    expect(store.home.entries()).toHaveLength(1);
    expect(store.home.entry(firstId)?.body).toBe("Follow up");
    runs.start({ text: "Separate task", sessionId: HOME_SESSION_ID });
    await vi.waitFor(() => expect(store.home.entries().find((entry) => entry.id !== firstId)?.requests.map(({ text }) => text))
      .toEqual(["Separate task"]));
    const entries = store.home.entries();
    const separate = entries.find((entry) => entry.id !== firstId)!;
    expect(separate.requests.map(({ text }) => text)).toEqual(["Separate task"]);
    await vi.waitFor(() => expect(store.home.entry(separate.id)?.state).toBe("ready"));
    runs.start({ text: "Direct follow-up", sessionId });
    await vi.waitFor(() => expect(store.home.entry(separate.id)?.requests.map(({ text }) => text))
      .toEqual(["Separate task", "Direct follow-up"]));
    expect(store.home.entry(firstId)?.requests.map(({ text }) => text)).toEqual(["First task", "Follow up"]);
    controller.abort();
    await events.return?.();
    await runs.close();
  });

  it("keeps Home responsive and commits routed entries in submission order", async () => {
    const store = new Store(temporary("agent-home-order-"));
    cleanup(() => store.close());
    let releaseFirst!: () => void;
    let secondComposed!: () => void;
    const firstRoute = new Promise<void>((resolve) => { releaseFirst = resolve; });
    const secondRoute = new Promise<void>((resolve) => { secondComposed = resolve; });
    const backend = worker(async function* () { yield { type: "done" }; });
    const home: HomeBackend = {
      async compose(request) {
        if (request.text === "First") await firstRoute;
        else secondComposed();
        return [{ type: "start", source: request.text, title: request.text, text: `Clear ${request.text}` }];
      },
      async summarize() { return { state: "ready", summary: "Finished." }; },
    };
    const runs = new RunCoordinator(new AgentRuntime(store, backend, home), store);
    store.homeSession();
    runs.start({ text: "First", sessionId: HOME_SESSION_ID });
    runs.start({ text: "Second", sessionId: HOME_SESSION_ID });
    await secondRoute;
    expect(store.home.entries().map((entry) => entry.body)).toEqual(["First", "Second"]);
    releaseFirst();
    await vi.waitFor(() => expect(store.home.entries().map((entry) => entry.body)).toEqual(["First", "Second"]));
    await runs.close();
  });

  it("queues follow-ups and gives live status only to the latest entry", async () => {
    const store = new Store(temporary("agent-home-queue-"));
    cleanup(() => store.close());
    let release!: () => void;
    const work = new Promise<void>((resolve) => { release = resolve; });
    const backend = worker(async function* () { await work; yield { type: "done" }; });
    const session = store.createSession({ title: "Existing work" });
    const home: HomeBackend = {
      async compose(request) { return [{ type: "continue", source: request.text, sessionId: session.id, title: "Follow up", text: request.text }]; },
      async summarize() { return { state: "ready", summary: "Done." }; },
    };
    const runs = new RunCoordinator(new AgentRuntime(store, backend, home), store);
    store.homeSession();
    runs.start({ text: "Original work", sessionId: session.id });
    runs.start({ text: "First follow-up", sessionId: HOME_SESSION_ID });
    runs.start({ text: "Second follow-up", sessionId: HOME_SESSION_ID });
    await vi.waitFor(() => expect(store.home.entries().map((entry) => entry.state)).toEqual([null, "working"]));
    expect(store.home.entries().map((entry) => entry.state)).toEqual([null, "working"]);
    expect(store.home.queuedTask(session.id)?.text).toBe("First follow-up");
    release();
    await vi.waitFor(() => expect(store.home.queuedTask(session.id)).toBeNull());
    expect(store.getMessages(session.id).filter((message) => message.role === "user").map((message) => message.content))
      .toEqual(["Original work", "First follow-up", "Second follow-up"]);
    await runs.close();
  });

  it("steers active work immediately", async () => {
    const store = new Store(temporary("agent-home-steer-"));
    cleanup(() => store.close());
    let release!: () => void;
    const work = new Promise<void>((resolve) => { release = resolve; });
    const steered: string[] = [];
    const backend = worker(
      async function* () { await work; yield { type: "done" }; },
      async (_sessionId, text) => { steered.push(text); return true; },
    );
    const session = store.createSession({ title: "Active task" });
    const home: HomeBackend = {
      async compose(request) { return [{ type: "steer", source: request.text, sessionId: session.id, title: "Refocus task", text: request.text }]; },
      async summarize() { return { state: "ready", summary: "Updated work finished." }; },
    };
    const runs = new RunCoordinator(new AgentRuntime(store, backend, home), store);
    store.homeSession();
    runs.start({ text: "Original", sessionId: session.id });
    await vi.waitFor(() => expect(runs.activeInfos()).toHaveLength(1));
    runs.start({ text: "Focus on tests first", sessionId: HOME_SESSION_ID });
    await vi.waitFor(() => expect(steered).toEqual(["Focus on tests first"]));
    expect(store.home.queuedTask(session.id)).toBeNull();
    release();
    await vi.waitFor(() => expect(store.home.entries()[0]?.state).toBe("ready"));
    await runs.close();
  });

  it("recovers durable queued work and its Home entry after restart", async () => {
    const directory = temporary("agent-home-recovery-");
    const original = new Store(directory);
    const session = original.createSession({ title: "Saved task" });
    const entry = original.home.createEntry("entry", "Finish this");
    original.home.dispatchEntry(entry.id, session.id, "Finish this", true);
    original.home.enqueueTask(session.id, "Finish this", "macos");
    original.close();
    const store = new Store(directory);
    cleanup(() => store.close());
    const backend = worker(async function* () { yield { type: "text_delta", delta: "Recovered." }; yield { type: "done" }; });
    const home: HomeBackend = {
      async compose() { throw new Error("Unexpected Home route"); },
      async summarize() { return { state: "ready", summary: "Recovered." }; },
    };
    const runs = new RunCoordinator(new AgentRuntime(store, backend, home), store);
    await vi.waitFor(() => expect(store.home.queuedTask(session.id)).toBeNull());
    await vi.waitFor(() => expect(store.home.entries()[0]).toMatchObject({ state: "ready", summary: "Recovered." }));
    await runs.close();
  });

  it("runs routing and separate reporting on low effort without work instructions", async () => {
    const homeDir = temporary("agent-home-model-");
    const store = new Store(homeDir);
    cleanup(() => store.close());
    const log = join(homeDir, "rpc.log");
    const config: RuntimeConfig = { homeDir, codexHome: join(homeDir, ".codex"), port: 0, codexCommand: "codex" };
    const fixture = join(process.cwd(), "src/codex/test-fixtures/fake-app-server.mjs");
    const working = store.createSession({ title: "Existing task" });
    store.startRun(working.id);
    for (const scenario of ["home-compose", "home-report"]) {
      const client = new CodexAppServer({ command: process.execPath, args: [fixture], env: {
        ...process.env, AGENT_FAKE_SCENARIO: scenario, AGENT_FAKE_LOG: log,
      } });
      const backend = new CodexHomeBackend(config, store, client);
      if (scenario === "home-compose") {
        expect(await backend.compose({ text: "Fix the tests" }, store.sessionCards(), [])).toEqual([
          { type: "start", source: "Fix the tests", text: "Fix the tests", title: "Fix tests" },
        ]);
      } else {
        expect(await backend.summarize({ title: "Fix tests", request: "Fix the tests", output: "Done.", state: "complete" }))
          .toMatchObject({ state: "ready" });
      }
      client.stop();
    }
    const calls = readFileSync(log, "utf8").trim().split("\n").map((line) => JSON.parse(line) as { method: string; params: Record<string, unknown> });
    const threads = calls.filter((call) => call.method === "thread/start").map((call) => call.params);
    expect(threads).toMatchObject([
      { model: "gpt-6-luna", ephemeral: true, sandbox: "danger-full-access", baseInstructions: expect.stringContaining("continue to queue a follow-up") },
      { model: "gpt-6-luna", ephemeral: true, sandbox: "danger-full-access", baseInstructions: expect.stringContaining("usually a few sentences") },
    ]);
    expect(threads.map((thread) => thread.config)).toEqual([
      { model_instructions_file: join(homeDir, "utility-instructions.md") },
      { model_instructions_file: join(homeDir, "utility-instructions.md") },
    ]);
    expect(threads.every((thread) => !String(thread.baseInstructions).includes("You are Agent, a direct, concise assistant"))).toBe(true);
    expect(threads.every((thread) => thread.developerInstructions === undefined)).toBe(true);
    expect(calls.filter((call) => call.method === "turn/start").map((call) => call.params.effort)).toEqual(["low", "low"]);
    expect(calls.filter((call) => call.method === "turn/start").map((call) => call.params.model)).toEqual(["gpt-6-luna", "gpt-6-luna"]);
    const routeInput = calls.find((call) => call.method === "turn/start")?.params.input as { text: string }[];
    expect(routeInput[0]?.text).toContain('"state":"working"');
  });

  it("accepts only one complete plan when Luna repeats a routing tool call", async () => {
    const homeDir = temporary("agent-home-duplicate-");
    const store = new Store(homeDir);
    cleanup(() => store.close());
    const log = join(homeDir, "rpc.log");
    const fixture = join(process.cwd(), "src/codex/test-fixtures/fake-app-server.mjs");
    const client = new CodexAppServer({ command: process.execPath, args: [fixture], env: {
      ...process.env, AGENT_FAKE_SCENARIO: "home-compose-duplicate", AGENT_FAKE_LOG: log,
    } });
    const backend = new CodexHomeBackend({ homeDir, codexHome: join(homeDir, ".codex"), port: 0, codexCommand: "codex" }, store, client);
    expect(await backend.compose({ text: "Fix the tests" }, [], [])).toEqual([
      { type: "start", source: "Fix the tests", text: "Fix the tests", title: "Fix tests" },
    ]);
    client.stop();
    const calls = readFileSync(log, "utf8").trim().split("\n").map((line) => JSON.parse(line) as {
      id?: string; result?: { success?: boolean };
    });
    expect(calls.find((call) => call.id === "home-tool-duplicate")?.result?.success).toBe(false);
  });

  it("routes separate restaurant and air fryer requests to two tasks", async () => {
    const homeDir = temporary("agent-home-multiple-plan-");
    const store = new Store(homeDir);
    cleanup(() => store.close());
    const fixture = join(process.cwd(), "src/codex/test-fixtures/fake-app-server.mjs");
    const client = new CodexAppServer({ command: process.execPath, args: [fixture], env: {
      ...process.env, AGENT_FAKE_SCENARIO: "home-compose-multiple",
    } });
    const backend = new CodexHomeBackend({ homeDir, codexHome: join(homeDir, ".codex"), port: 0, codexCommand: "codex" }, store, client);
    expect(await backend.compose({ text: "Find restaurants in Taipei and a good air fryer" }, [], []))
      .toMatchObject([{ type: "start", title: "Taipei restaurants" }, { type: "start", title: "Air fryer picks" }]);
    client.stop();
  });

  it("accepts a follow-up linked to an existing task card", async () => {
    const homeDir = temporary("agent-home-reuse-plan-");
    const store = new Store(homeDir);
    cleanup(() => store.close());
    const session = store.createSession({ title: "Current task" });
    store.home.createEntry("current-card", "Build the feature");
    store.home.dispatchEntry("current-card", session.id, "Build the feature", true);
    const fixture = join(process.cwd(), "src/codex/test-fixtures/fake-app-server.mjs");
    const client = new CodexAppServer({ command: process.execPath, args: [fixture], env: {
      ...process.env, AGENT_FAKE_SCENARIO: "home-compose-reuse",
      AGENT_FAKE_SESSION_ID: session.id, AGENT_FAKE_ENTRY_ID: "current-card",
    } });
    const backend = new CodexHomeBackend({ homeDir, codexHome: join(homeDir, ".codex"), port: 0, codexCommand: "codex" }, store, client);
    expect(await backend.compose({ text: "Please also add tests" }, [], store.home.entries())).toEqual([
      { type: "continue", source: "Please also add tests", title: "Add tests",
        text: "Add tests for the current task.", sessionId: session.id, entryId: "current-card" },
    ]);
    client.stop();
  });

  it("rejects two routes for the same greeting", async () => {
    const homeDir = temporary("agent-home-overlap-");
    const store = new Store(homeDir);
    cleanup(() => store.close());
    const fixture = join(process.cwd(), "src/codex/test-fixtures/fake-app-server.mjs");
    const client = new CodexAppServer({ command: process.execPath, args: [fixture], env: {
      ...process.env, AGENT_FAKE_SCENARIO: "home-compose-overlap",
    } });
    const backend = new CodexHomeBackend({ homeDir, codexHome: join(homeDir, ".codex"), port: 0, codexCommand: "codex" }, store, client);
    await expect(backend.compose({ text: "How are you?" }, [], []))
      .rejects.toThrow("Home could not route this request. Try again.");
    client.stop();
  });

  it("does not invent a destination when Home returns no tool call", async () => {
    const homeDir = temporary("agent-home-no-tool-");
    const store = new Store(homeDir);
    cleanup(() => store.close());
    const fixture = join(process.cwd(), "src/codex/test-fixtures/fake-app-server.mjs");
    const client = new CodexAppServer({ command: process.execPath, args: [fixture] });
    const backend = new CodexHomeBackend({ homeDir, codexHome: join(homeDir, ".codex"), port: 0, codexCommand: "codex" }, store, client);
    await expect(backend.compose({ text: "Resume Tonal Android" }, [], []))
      .rejects.toThrow("Home could not route this request. Try again.");
    client.stop();
  });

  it("finds and reads older conversations without opening them", async () => {
    const homeDir = temporary("agent-home-read-");
    const store = new Store(homeDir);
    cleanup(() => store.close());
    const saved = store.createSession({ title: "Reconnect investigation", cwd: homeDir });
    store.addMessage(saved.id, "user", "Investigate why Agent reconnects twice.");
    store.addMessage(saved.id, "assistant", "The gateway has two reconnect paths.");
    const seed = store.home.createEntry("seed", "Investigate reconnects");
    store.home.dispatchEntry(seed.id, saved.id, seed.body, false);
    store.home.updateEntry(saved.id, "ready", "Duplicate reconnect paths identified.");
    const log = join(homeDir, "rpc.log");
    const fixture = join(process.cwd(), "src/codex/test-fixtures/fake-app-server.mjs");
    const client = new CodexAppServer({ command: process.execPath, args: [fixture], env: {
      ...process.env, AGENT_FAKE_SCENARIO: "home-read", AGENT_FAKE_LOG: log,
    } });
    const backend = new CodexHomeBackend({ homeDir, codexHome: join(homeDir, ".codex"), port: 0, codexCommand: "codex" }, store, client);
    expect(await backend.compose({ text: "Resume the reconnect investigation and add these logs" }, [], []))
      .toEqual([{ type: "continue", source: "Resume the reconnect investigation and add these logs",
        sessionId: saved.id, title: "Continue reconnect investigation",
        text: "Continue the reconnect investigation with the additional logs." }]);
    expect(store.getMessages(saved.id)).toHaveLength(2);

    const calls = readFileSync(log, "utf8").trim().split("\n").map((line) => JSON.parse(line) as {
      id?: string; method?: string; params?: Record<string, unknown>; result?: { contentItems?: { text: string }[] };
    });
    expect(calls.find((call) => call.method === "thread/start")?.params?.dynamicTools).toEqual(expect.arrayContaining([
      expect.objectContaining({ name: "find_conversations" }),
      expect.objectContaining({ name: "read_conversation" }),
      expect.objectContaining({ name: "route_tasks" }),
    ]));
    expect(JSON.parse(calls.find((call) => call.id === "home-find")?.result?.contentItems?.[0]?.text ?? "[]")[0])
      .toMatchObject({ id: saved.id, state: "ready", preview: "The gateway has two reconnect paths." });
    expect(JSON.parse(calls.find((call) => call.id === "home-read")?.result?.contentItems?.[0]?.text ?? "{}"))
      .toMatchObject({ conversation: { id: saved.id, state: "ready" }, messages: [
        { role: "user", content: "Investigate why Agent reconnects twice." },
        { role: "assistant", content: "The gateway has two reconnect paths." },
      ] });
    client.stop();
  });

  it("plans a saved-conversation follow-up and a new task with carried context", async () => {
    const homeDir = temporary("agent-home-mixed-plan-");
    const store = new Store(homeDir);
    cleanup(() => store.close());
    const saved = store.createSession({ title: "Reconnect investigation" });
    store.addMessage(saved.id, "assistant", "The gateway has two reconnect paths.");
    const fixture = join(process.cwd(), "src/codex/test-fixtures/fake-app-server.mjs");
    const client = new CodexAppServer({ command: process.execPath, args: [fixture], env: {
      ...process.env, AGENT_FAKE_SCENARIO: "home-compose-mixed",
    } });
    const backend = new CodexHomeBackend({ homeDir, codexHome: join(homeDir, ".codex"), port: 0, codexCommand: "codex" }, store, client);
    const actions = await backend.compose({
      text: "Resume the reconnect investigation and create a new task about Madrid restaurants",
    }, [], []);
    expect(actions).toMatchObject([
      { type: "continue", sessionId: saved.id, source: "Resume the reconnect investigation" },
      { type: "start", source: "create a new task about Madrid restaurants", title: "Madrid restaurants" },
    ]);
    expect(actions[1]?.text).toContain("The gateway has two reconnect paths.");
    expect(store.sessionCards()).toHaveLength(1);
    client.stop();
  });
});
