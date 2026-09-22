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

describe("Agent Home", () => {
  it("dispatches durable tasks before they finish and reports only lifecycle updates", async () => {
    const store = new Store(temporary("agent-home-"));
    cleanup(() => store.close());
    let release!: () => void;
    const work = new Promise<void>((resolve) => { release = resolve; });
    const backend: AgentBackend = {
      async route() { return null; },
      async transcribeAudio() { return ""; },
      async *run() {
        yield { type: "status", message: "Working" };
        await work;
        yield { type: "text_delta", delta: "Completed the work." };
        yield { type: "done" };
      },
    };
    const home: HomeBackend = {
      async compose() { return [
        { type: "start", title: "First task", text: "Do the first task" },
        { type: "start", title: "Second task", text: "Do the second task" },
      ]; },
      async summarize() { return { state: "ready", summary: "The work is complete and all requested checks pass without any remaining issues" }; },
    };
    const runtime = new AgentRuntime(store, backend, home);
    const runs = new RunCoordinator(runtime, store);
    const controller = new AbortController();
    const stream = runs.events(controller.signal, undefined, undefined, HOME_SESSION_ID)[Symbol.asyncIterator]();
    const firstEvent = stream.next();
    const run = runs.start({ text: "Do both", sessionId: runtime.openSession().id, channel: "macos" });
    const events = [(await firstEvent).value!];
    while (events.filter((event) => event.runId === run.id && event.event.type === "task_report").length < 2) {
      events.push((await stream.next()).value!);
    }
    expect(runs.activeInfos().filter((item) => item.sessionId !== HOME_SESSION_ID)).toHaveLength(2);
    expect(store.taskReports().map((report) => report.state)).toEqual(["working", "working"]);
    expect(events.some((event) => event.event.type === "status" && event.sessionId !== HOME_SESSION_ID)).toBe(false);
    expect(events.filter((event) => event.sessionId === HOME_SESSION_ID).every((event) => event.event.type === "task_report")).toBe(true);
    release();
    while (events.filter((event) => event.event.type === "task_report" && event.event.report.state === "ready").length < 2) {
      events.push((await stream.next()).value!);
    }
    expect(store.taskReports()).toHaveLength(2);
    expect(store.taskReports().every((report) => report.summary.split(" ").length <= 12)).toBe(true);
    for (const report of store.taskReports()) {
      expect(store.getMessages(report.sessionId).map((message) => message.role)).toEqual(["user", "assistant"]);
    }
    controller.abort();
    await stream.return?.();
    await runs.close();
  });

  it("dispatches consecutive Home requests without holding the composer busy", async () => {
    const store = new Store(temporary("agent-home-parallel-"));
    cleanup(() => store.close());
    let release!: () => void;
    const work = new Promise<void>((resolve) => { release = resolve; });
    const backend: AgentBackend = {
      async route() { return null; },
      async transcribeAudio() { return ""; },
      async *run() { await work; yield { type: "text_delta", delta: "Done." }; yield { type: "done" }; },
    };
    const home: HomeBackend = {
      async compose(request) { return [{ type: "start", title: request.text, text: request.text }]; },
      async summarize() { return { state: "ready", summary: "Done." }; },
    };
    const runs = new RunCoordinator(new AgentRuntime(store, backend, home), store);
    store.homeSession();
    const controller = new AbortController();
    const stream = runs.events(controller.signal, undefined, undefined, HOME_SESSION_ID)[Symbol.asyncIterator]();
    const firstEvent = stream.next();
    const first = runs.start({ text: "First", sessionId: HOME_SESSION_ID });
    const second = runs.start({ text: "Second", sessionId: HOME_SESSION_ID });
    const events = [(await firstEvent).value!];
    while (events.filter((event) => event.event.type === "task_report").length < 2) events.push((await stream.next()).value!);
    expect(first.id).not.toBe(second.id);
    expect(store.taskReports().map((report) => report.title).sort()).toEqual(["First", "Second"]);
    while (runs.activeInfos().length < 2) events.push((await stream.next()).value!);
    expect(runs.activeInfos()).toHaveLength(2);
    expect(runs.activeSnapshots(HOME_SESSION_ID)).toHaveLength(0);
    release();
    while (events.filter((event) => event.event.type === "task_report" && event.event.report.state === "ready").length < 2) {
      events.push((await stream.next()).value!);
    }
    expect(store.getMessages(HOME_SESSION_ID).map((message) => message.role)).toEqual(["user", "user"]);
    controller.abort();
    await stream.return?.();
    await runs.close();
  });

  it("keeps submitted card order when later routing finishes first", async () => {
    const store = new Store(temporary("agent-home-order-"));
    cleanup(() => store.close());
    let releaseFirst!: () => void;
    let secondComposed!: () => void;
    const firstRoute = new Promise<void>((resolve) => { releaseFirst = resolve; });
    const secondRoute = new Promise<void>((resolve) => { secondComposed = resolve; });
    const backend: AgentBackend = {
      async route() { return null; },
      async transcribeAudio() { return ""; },
      async *run() { yield { type: "done" }; },
    };
    const home: HomeBackend = {
      async compose(request) {
        if (request.text === "First") await firstRoute;
        else secondComposed();
        return [{ type: "start", title: request.text, text: request.text }];
      },
      async summarize() { return { state: "ready", summary: "Finished." }; },
    };
    const runs = new RunCoordinator(new AgentRuntime(store, backend, home), store);
    store.homeSession();
    runs.start({ text: "First", sessionId: HOME_SESSION_ID });
    runs.start({ text: "Second", sessionId: HOME_SESSION_ID });
    await secondRoute;
    expect(store.taskReports()).toEqual([]);
    releaseFirst();
    await vi.waitFor(() => expect(store.taskReports().map((report) => report.title)).toEqual(["First", "Second"]));
    await runs.close();
  });

  it("queues a Home follow-up in the same session while the earlier turn is working", async () => {
    const store = new Store(temporary("agent-home-followup-"));
    cleanup(() => store.close());
    let release!: () => void;
    const work = new Promise<void>((resolve) => { release = resolve; });
    const backend: AgentBackend = {
      async route() { return null; },
      async transcribeAudio() { return ""; },
      async *run() { await work; yield { type: "done" }; },
    };
    const prior = store.createSession({ title: "First task" });
    store.addMessage(prior.id, "user", "First");
    store.setTaskReport(prior.id, "working", "Started.");
    const home: HomeBackend = {
      async compose(request) { return [{ type: "continue", sessionId: prior.id, text: request.text }]; },
      async summarize() { return { state: "ready", summary: "Done." }; },
    };
    const runs = new RunCoordinator(new AgentRuntime(store, backend, home), store);
    store.homeSession();
    runs.start({ text: "First", sessionId: prior.id });
    const controller = new AbortController();
    const stream = runs.events(controller.signal, undefined, undefined, HOME_SESSION_ID)[Symbol.asyncIterator]();
    const second = stream.next();
    runs.start({ text: "Also check the tests", sessionId: HOME_SESSION_ID });
    const third = runs.start({ text: "And the docs", sessionId: HOME_SESSION_ID });
    let event = (await second).value!;
    while (event.runId !== third.id || event.event.type !== "task_report") event = (await stream.next()).value!;
    expect(event.event.report.sessionId).toBe(prior.id);
    expect(store.taskReports()).toHaveLength(1);
    expect(store.queuedTask(prior.id)?.text).toBe("Also check the tests");
    release();
    while (event.event.type !== "task_report" || event.event.report.state !== "ready") event = (await stream.next()).value!;
    expect(store.queuedTask(prior.id)).toBeNull();
    expect(store.getMessages(prior.id).filter((message) => message.role === "user").map((message) => message.content))
      .toEqual(["First", "First", "Also check the tests", "And the docs"]);
    controller.abort();
    await stream.return?.();
    await runs.close();
  });

  it("opens two new sessions, resumes one, and updates the resumed card in place", async () => {
    const store = new Store(temporary("agent-home-mixed-"));
    cleanup(() => store.close());
    const saved = store.createSession({ title: "Journal" });
    store.addMessage(saved.id, "user", "Write a note");
    store.addMessage(saved.id, "assistant", "The note is saved.");
    let release!: () => void;
    const work = new Promise<void>((resolve) => { release = resolve; });
    const backend: AgentBackend = {
      async route() { return null; },
      async transcribeAudio() { return ""; },
      async *run() { await work; yield { type: "text_delta", delta: "Finished." }; yield { type: "done" }; },
    };
    const home: HomeBackend = {
      async compose(request) {
        if (request.text === "Resume Journal") return [{ type: "continue", sessionId: saved.id }];
        if (request.text === "Update Journal") return [{ type: "continue", sessionId: saved.id, text: "Add a date" }];
        return [{ type: "start", title: request.text, text: request.text }];
      },
      async summarize(input) { return input.request === "Add a date"
        ? { state: "needs_input", summary: "Which date should I use?" }
        : { state: "ready", summary: "Finished." }; },
    };
    const runs = new RunCoordinator(new AgentRuntime(store, backend, home), store);
    store.homeSession();
    const controller = new AbortController();
    const stream = runs.events(controller.signal, undefined, undefined, HOME_SESSION_ID)[Symbol.asyncIterator]();
    const firstEvent = stream.next();
    const requests = ["Resume Journal", "Design", "Code", "Update Journal"];
    const homeRuns = requests.map((text) => runs.start({ text, sessionId: HOME_SESSION_ID }).id);
    const events = [(await firstEvent).value!];
    while (events.filter((event) => homeRuns.includes(event.runId) && event.event.type === "task_report").length < 4) {
      events.push((await stream.next()).value!);
    }
    expect(store.taskReports().map((report) => report.title)).toEqual(["Journal", "Design", "Code"]);
    expect(store.taskReports().find((report) => report.sessionId === saved.id)?.state).toBe("working");
    while (runs.activeInfos().length < 3) events.push((await stream.next()).value!);
    expect(runs.activeInfos()).toHaveLength(3);
    release();
    while (store.taskReports().some((report) => report.state === "working")) {
      events.push((await stream.next()).value!);
    }
    expect(store.taskReports().map((report) => report.title)).toEqual(["Journal", "Design", "Code"]);
    expect(store.taskReports()[0]).toMatchObject({ sessionId: saved.id, state: "needs_input", summary: "Which date should I use?" });
    controller.abort();
    await stream.return?.();
    await runs.close();
  });

  it("opens a new Home card without launching work when no task context is supplied", async () => {
    const store = new Store(temporary("agent-home-idle-card-"));
    cleanup(() => store.close());
    let workerRuns = 0;
    const backend: AgentBackend = {
      async route() { return null; },
      async transcribeAudio() { return ""; },
      async *run() { workerRuns += 1; yield { type: "done" }; },
    };
    const home: HomeBackend = {
      async compose() { return [{ type: "start", title: "Ideas" }]; },
      async summarize() { return { state: "ready", summary: "Ready." }; },
    };
    const runs = new RunCoordinator(new AgentRuntime(store, backend, home), store);
    store.homeSession();
    const controller = new AbortController();
    const stream = runs.events(controller.signal, undefined, undefined, HOME_SESSION_ID)[Symbol.asyncIterator]();
    const firstEvent = stream.next();
    runs.start({ text: "Open an ideas conversation", sessionId: HOME_SESSION_ID });
    let event = (await firstEvent).value!;
    while (event.event.type !== "task_report") event = (await stream.next()).value!;
    expect(event.event.report).toMatchObject({ title: "Ideas", state: "ready", summary: "Ready for your request." });
    expect(workerRuns).toBe(0);
    expect(store.queuedSessionIds()).toEqual([]);
    controller.abort();
    await stream.return?.();
    await runs.close();
  });

  it("starts saved queued work after a runtime restart", async () => {
    const directory = temporary("agent-home-queued-recovery-");
    const original = new Store(directory);
    const task = original.createSession({ title: "Saved task" });
    original.enqueueTask(task.id, "Finish the saved request", "cli");
    original.setTaskReport(task.id, "working", "Queued.");
    original.close();
    const store = new Store(directory);
    cleanup(() => store.close());
    const backend: AgentBackend = {
      async route() { return null; },
      async transcribeAudio() { return ""; },
      async *run() { yield { type: "text_delta", delta: "Recovered and finished." }; yield { type: "done" }; },
    };
    const home: HomeBackend = {
      async compose() { return []; },
      async summarize() { return { state: "ready", summary: "Recovered and finished." }; },
    };
    const runs = new RunCoordinator(new AgentRuntime(store, backend, home), store);
    const controller = new AbortController();
    const stream = runs.events(controller.signal, undefined, undefined, HOME_SESSION_ID)[Symbol.asyncIterator]();
    let event = (await stream.next()).value!;
    while (event.event.type !== "task_report" || event.event.report.state !== "ready") event = (await stream.next()).value!;
    expect(event.event.report.sessionId).toBe(task.id);
    expect(store.queuedTask(task.id)).toBeNull();
    expect(store.getMessages(task.id).map((message) => message.role)).toEqual(["user", "assistant"]);
    controller.abort();
    await stream.return?.();
    await runs.close();
  });

  it("recovers unfinished reports from saved task runs", () => {
    const homeDir = temporary("agent-home-recovery-");
    const store = new Store(homeDir);
    const task = store.createSession({ title: "Interrupted task" });
    store.setTaskReport(task.id, "working", "Started.");
    store.startRun(task.id, "pending", "User request");
    store.close();
    const recovered = new Store(homeDir);
    cleanup(() => recovered.close());
    expect(recovered.taskReports()[0]).toMatchObject({ state: "failed", summary: "Interrupted. Open task to continue." });
    expect(recovered.getMessages(task.id)[0]).toMatchObject({ role: "user", content: "User request" });
  });

  it("runs Home's compose and report turns on Luna without reasoning", async () => {
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
        expect(await backend.compose({ text: "Fix the tests" }, [], [])).toEqual([
          { type: "start", text: "Fix the tests", title: "Fix tests" },
        ]);
      } else {
        expect(await backend.summarize({ title: "Fix tests", request: "Fix the tests", output: "Done.", state: "complete" }))
          .toMatchObject({ state: "ready" });
      }
      client.stop();
    }
    const calls = readFileSync(log, "utf8").trim().split("\n").map((line) => JSON.parse(line) as { method: string; params: Record<string, unknown> });
    expect(calls.filter((call) => call.method === "thread/start").map((call) => call.params)).toMatchObject([
      { model: "gpt-5.6-luna", ephemeral: true, sandbox: "read-only" },
      { model: "gpt-5.6-luna", ephemeral: true, sandbox: "read-only" },
    ]);
    expect(calls.filter((call) => call.method === "turn/start").map((call) => call.params.effort)).toEqual(["none", "none"]);
  });

  it("does not silently start a new session if Home returns no tool call", async () => {
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

  it("resumes an older saved conversation through Home's search tool", async () => {
    const homeDir = temporary("agent-home-find-");
    const store = new Store(homeDir);
    cleanup(() => store.close());
    const older = store.createSession({ title: "Tonal Android" });
    for (let index = 0; index < 60; index += 1) store.createSession({ title: `Other ${index}` });
    const fixture = join(process.cwd(), "src/codex/test-fixtures/fake-app-server.mjs");
    const client = new CodexAppServer({ command: process.execPath, args: [fixture], env: {
      ...process.env, AGENT_FAKE_SCENARIO: "home-find",
    } });
    const backend = new CodexHomeBackend({ homeDir, port: 0, codexCommand: "codex" }, store, client);
    expect(await backend.compose({ text: "Resume Tonal Android" }, store.sessionCards(), []))
      .toEqual([{ type: "continue", sessionId: older.id }]);
    client.stop();
  });
});
