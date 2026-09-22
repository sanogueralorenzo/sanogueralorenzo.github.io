import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
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
    const runs = new RunCoordinator(runtime);
    const controller = new AbortController();
    const stream = runs.events(controller.signal, undefined, undefined, HOME_SESSION_ID)[Symbol.asyncIterator]();
    const firstEvent = stream.next();
    const run = runs.start({ text: "Do both", sessionId: runtime.openSession().id, channel: "macos" });
    const events = [(await firstEvent).value!];
    while (!events.some((event) => event.runId === run.id && event.event.type === "done")) {
      events.push((await stream.next()).value!);
    }
    expect(runs.activeInfos().filter((item) => item.sessionId !== HOME_SESSION_ID)).toHaveLength(2);
    expect(store.taskReports().map((report) => report.state)).toEqual(["working", "working"]);
    expect(events.some((event) => event.event.type === "status" && event.sessionId !== HOME_SESSION_ID)).toBe(false);
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
});
