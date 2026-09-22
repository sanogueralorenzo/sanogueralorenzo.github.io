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
  it("turns one submission into one clickable task entry and final concise outcome", async () => {
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
      async compose() { return { type: "start", title: "Combined task", text: "Do both tasks carefully." }; },
      async summarize() { return { state: "ready", summary: "Work complete." }; },
    };
    const runs = new RunCoordinator(new AgentRuntime(store, backend, home), store);
    const controller = new AbortController();
    const stream = runs.events(controller.signal, undefined, undefined, HOME_SESSION_ID)[Symbol.asyncIterator]();
    const pending = stream.next();
    const requestId = "00000000-0000-4000-8000-000000000001";
    runs.start({ text: "Do both", requestId, sessionId: store.homeSession().id, channel: "macos" });
    const first = (await pending).value!;
    await vi.waitFor(() => expect(store.homeEntries()).toHaveLength(1));
    expect(store.homeEntries()).toMatchObject([
      { id: requestId, title: "Combined task", body: "Do both", state: "working" },
    ]);
    release();
    await vi.waitFor(() => expect(store.homeEntries()[0]).toMatchObject({ state: "ready", summary: "Work complete." }));
    expect(first.event).toMatchObject({ type: "home_entry", entry: { id: requestId, body: "Do both", state: "routing" } });
    controller.abort();
    await stream.return?.();
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
        return { type: "start", title: request.text, text: `Clear ${request.text}` };
      },
      async summarize() { return { state: "ready", summary: "Finished." }; },
    };
    const runs = new RunCoordinator(new AgentRuntime(store, backend, home), store);
    store.homeSession();
    runs.start({ text: "First", sessionId: HOME_SESSION_ID });
    runs.start({ text: "Second", sessionId: HOME_SESSION_ID });
    await secondRoute;
    expect(store.homeEntries().map((entry) => entry.body)).toEqual(["First", "Second"]);
    releaseFirst();
    await vi.waitFor(() => expect(store.homeEntries().map((entry) => entry.title)).toEqual(["First", "Second"]));
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
      async compose(request) { return { type: "continue", sessionId: session.id, title: "Follow up", text: request.text }; },
      async summarize() { return { state: "ready", summary: "Done." }; },
    };
    const runs = new RunCoordinator(new AgentRuntime(store, backend, home), store);
    store.homeSession();
    runs.start({ text: "Original work", sessionId: session.id });
    runs.start({ text: "First follow-up", sessionId: HOME_SESSION_ID });
    runs.start({ text: "Second follow-up", sessionId: HOME_SESSION_ID });
    await vi.waitFor(() => expect(store.homeEntries().map((entry) => entry.state)).toEqual([null, "working"]));
    expect(store.homeEntries().map((entry) => entry.state)).toEqual([null, "working"]);
    expect(store.queuedTask(session.id)?.text).toBe("First follow-up");
    release();
    await vi.waitFor(() => expect(store.queuedTask(session.id)).toBeNull());
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
      async compose(request) { return { type: "steer", sessionId: session.id, title: "Refocus task", text: request.text }; },
      async summarize() { return { state: "ready", summary: "Updated work finished." }; },
    };
    const runs = new RunCoordinator(new AgentRuntime(store, backend, home), store);
    store.homeSession();
    runs.start({ text: "Original", sessionId: session.id });
    await vi.waitFor(() => expect(runs.activeInfos()).toHaveLength(1));
    runs.start({ text: "Focus on tests first", sessionId: HOME_SESSION_ID });
    await vi.waitFor(() => expect(steered).toEqual(["Focus on tests first"]));
    expect(store.queuedTask(session.id)).toBeNull();
    release();
    await vi.waitFor(() => expect(store.homeEntries()[0]?.state).toBe("ready"));
    await runs.close();
  });

  it("recovers durable queued work and its Home entry after restart", async () => {
    const directory = temporary("agent-home-recovery-");
    const original = new Store(directory);
    const session = original.createSession({ title: "Saved task" });
    const entry = original.createHomeEntry("entry", "Finish this");
    original.dispatchHomeEntry(entry.id, session.id, session.title, "Finish this", true);
    original.enqueueTask(session.id, "Finish this", "cli");
    original.close();
    const store = new Store(directory);
    cleanup(() => store.close());
    const backend = worker(async function* () { yield { type: "text_delta", delta: "Recovered." }; yield { type: "done" }; });
    const home: HomeBackend = {
      async compose() { throw new Error("Unexpected Home route"); },
      async summarize() { return { state: "ready", summary: "Recovered." }; },
    };
    const runs = new RunCoordinator(new AgentRuntime(store, backend, home), store);
    await vi.waitFor(() => expect(store.queuedTask(session.id)).toBeNull());
    await vi.waitFor(() => expect(store.homeEntries()[0]).toMatchObject({ state: "ready", summary: "Recovered." }));
    await runs.close();
  });

  it("runs Home routing and summaries on Luna without reasoning", async () => {
    const homeDir = temporary("agent-home-model-");
    const store = new Store(homeDir);
    cleanup(() => store.close());
    const log = join(homeDir, "rpc.log");
    const config: RuntimeConfig = { homeDir, port: 0, codexCommand: "codex" };
    const fixture = join(process.cwd(), "src/codex/test-fixtures/fake-app-server.mjs");
    for (const scenario of ["home-compose", "home-report"]) {
      const client = new CodexAppServer({ command: process.execPath, args: [fixture], env: {
        ...process.env, AGENT_FAKE_SCENARIO: scenario, AGENT_FAKE_LOG: log,
      } });
      const backend = new CodexHomeBackend(config, store, client);
      if (scenario === "home-compose") {
        expect(await backend.compose({ text: "Fix the tests" }, [], [])).toEqual(
          { type: "start", text: "Fix the tests", title: "Fix tests" },
        );
      } else {
        expect(await backend.summarize({ title: "Fix tests", request: "Fix the tests", output: "Done.", state: "complete" }))
          .toMatchObject({ state: "ready" });
      }
      client.stop();
    }
    const calls = readFileSync(log, "utf8").trim().split("\n").map((line) => JSON.parse(line) as { method: string; params: Record<string, unknown> });
    expect(calls.filter((call) => call.method === "thread/start").map((call) => call.params)).toMatchObject([
      { model: "gpt-6-luna", ephemeral: true, sandbox: "read-only" },
      { model: "gpt-6-luna", ephemeral: true, sandbox: "read-only" },
    ]);
    expect(calls.filter((call) => call.method === "turn/start").map((call) => call.params.effort)).toEqual(["none", "none"]);
    expect(calls.filter((call) => call.method === "turn/start").map((call) => call.params.model)).toEqual(["gpt-6-luna", "gpt-6-luna"]);
  });

  it("accepts only one routing action when Luna repeats a tool call", async () => {
    const homeDir = temporary("agent-home-duplicate-");
    const store = new Store(homeDir);
    cleanup(() => store.close());
    const log = join(homeDir, "rpc.log");
    const fixture = join(process.cwd(), "src/codex/test-fixtures/fake-app-server.mjs");
    const client = new CodexAppServer({ command: process.execPath, args: [fixture], env: {
      ...process.env, AGENT_FAKE_SCENARIO: "home-compose-duplicate", AGENT_FAKE_LOG: log,
    } });
    const backend = new CodexHomeBackend({ homeDir, port: 0, codexCommand: "codex" }, store, client);
    expect(await backend.compose({ text: "Fix the tests" }, [], [])).toEqual(
      { type: "start", text: "Fix the tests", title: "Fix tests" },
    );
    client.stop();
    const calls = readFileSync(log, "utf8").trim().split("\n").map((line) => JSON.parse(line) as {
      id?: string; result?: { success?: boolean };
    });
    expect(calls.find((call) => call.id === "home-tool-duplicate")?.result?.success).toBe(false);
  });

  it("does not invent a destination when Home returns no tool call", async () => {
    const homeDir = temporary("agent-home-no-tool-");
    const store = new Store(homeDir);
    cleanup(() => store.close());
    const fixture = join(process.cwd(), "src/codex/test-fixtures/fake-app-server.mjs");
    const client = new CodexAppServer({ command: process.execPath, args: [fixture] });
    const backend = new CodexHomeBackend({ homeDir, port: 0, codexCommand: "codex" }, store, client);
    await expect(backend.compose({ text: "Resume Tonal Android" }, [], []))
      .rejects.toThrow("Home could not route this request. Try again.");
    client.stop();
  });

  it("finds and reads older conversations without opening them", async () => {
    const homeDir = temporary("agent-home-read-");
    const store = new Store(homeDir);
    cleanup(() => store.close());
    const saved = store.createSession({ title: "Reconnect investigation", cwd: homeDir });
    store.addMessage(saved.id, "user", "Investigate why Telegram reconnects twice.");
    store.addMessage(saved.id, "assistant", "The gateway has two reconnect paths.");
    const seed = store.createHomeEntry("seed", "Investigate reconnects");
    store.dispatchHomeEntry(seed.id, saved.id, saved.title, seed.body, false);
    store.updateHomeEntry(saved.id, "ready", "Duplicate reconnect paths identified.");
    const log = join(homeDir, "rpc.log");
    const fixture = join(process.cwd(), "src/codex/test-fixtures/fake-app-server.mjs");
    const client = new CodexAppServer({ command: process.execPath, args: [fixture], env: {
      ...process.env, AGENT_FAKE_SCENARIO: "home-read", AGENT_FAKE_LOG: log,
    } });
    const backend = new CodexHomeBackend({ homeDir, port: 0, codexCommand: "codex" }, store, client);
    expect(await backend.compose({ text: "Resume the reconnect investigation and add these logs" }, [], []))
      .toEqual({ type: "continue", sessionId: saved.id, title: "Continue reconnect investigation",
        text: "Continue the reconnect investigation with the additional logs." });
    expect(store.getMessages(saved.id)).toHaveLength(2);

    const calls = readFileSync(log, "utf8").trim().split("\n").map((line) => JSON.parse(line) as {
      id?: string; method?: string; params?: Record<string, unknown>; result?: { contentItems?: { text: string }[] };
    });
    expect(calls.find((call) => call.method === "thread/start")?.params?.dynamicTools).toEqual(expect.arrayContaining([
      expect.objectContaining({ name: "find_conversations" }),
      expect.objectContaining({ name: "read_conversation" }),
      expect.objectContaining({ name: "start_task" }),
      expect.objectContaining({ name: "continue_task" }),
      expect.objectContaining({ name: "steer_task" }),
    ]));
    expect(JSON.parse(calls.find((call) => call.id === "home-find")?.result?.contentItems?.[0]?.text ?? "[]")[0])
      .toMatchObject({ id: saved.id, state: "ready", preview: "The gateway has two reconnect paths." });
    expect(JSON.parse(calls.find((call) => call.id === "home-read")?.result?.contentItems?.[0]?.text ?? "{}"))
      .toMatchObject({ conversation: { id: saved.id, state: "ready" }, messages: [
        { role: "user", content: "Investigate why Telegram reconnects twice." },
        { role: "assistant", content: "The gateway has two reconnect paths." },
      ] });
    client.stop();
  });
});
