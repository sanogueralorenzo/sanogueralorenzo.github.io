import { describe, expect, it } from "vitest";
import type { AgentRuntime } from "./runtime.js";
import { MAX_EVENT_BUFFER_BYTES, RunBusyError, RunCoordinator, SlowSubscriberError } from "./runs.js";
import type { RunEnvelope, RuntimeEvent } from "./types.js";

function runtime(run: (signal: AbortSignal) => AsyncGenerator<RuntimeEvent>) {
  let executions = 0;
  return {
    value: {
      prepareTurn(turn: { sessionId?: string }) {
        const id = turn.sessionId ?? "s1";
        return { session: { id, cwd: null, title: id, updatedAt: "now" }, empty: false, sessionTools: [] };
      },
      async *run(_turn: unknown, options: { signal: AbortSignal }) {
      executions += 1;
      yield* run(options.signal);
      },
    } as unknown as AgentRuntime,
    executions: () => executions,
  };
}

async function collectRun(events: AsyncIterable<RunEnvelope>): Promise<RunEnvelope[]> {
  const result: RunEnvelope[] = [];
  for await (const event of events) {
    result.push(event);
    if (event.event.type === "done" || event.event.type === "error") break;
  }
  return result;
}

describe("RunCoordinator", () => {
  it("broadcasts one execution to live subscribers without replaying it later", async () => {
    const fixture = runtime(async function* () {
      yield { type: "text_delta", delta: "hello" };
      yield { type: "done", sessionId: "s1" };
    });
    const runs = new RunCoordinator(fixture.value);
    const first = collectRun(runs.events(new AbortController().signal));
    const second = collectRun(runs.events(new AbortController().signal));
    const run = runs.start({ text: "hi", channel: "cli" });
    const [a, b] = await Promise.all([first, second]);

    expect(fixture.executions()).toBe(1);
    expect(a).toEqual(b);
    expect(a[0]).toMatchObject({ runId: run.id, event: { type: "session_activity", sessionId: "s1" } });
    expect(a[1]).toMatchObject({ runId: run.id, event: { type: "turn", channel: "cli" } });

    const late = collectRun(runs.events(new AbortController().signal));
    const next = runs.start({ text: "next", channel: "telegram" });
    const c = await late;
    expect(fixture.executions()).toBe(2);
    expect(c.every(({ runId }) => runId === next.id)).toBe(true);
  });

  it("sends a late subscriber the current turn before later deltas", async () => {
    let release!: () => void;
    let reached!: () => void;
    const paused = new Promise<void>((resolve) => { release = resolve; });
    const reachedPause = new Promise<void>((resolve) => { reached = resolve; });
    const fixture = runtime(async function* () {
      yield { type: "text_delta", delta: "first" };
      reached();
      await paused;
      yield { type: "text_delta", delta: " second" };
      yield { type: "done", sessionId: "s1" };
    });
    const runs = new RunCoordinator(fixture.value);
    const run = runs.start({ text: "hi", channel: "macos" });
    await reachedPause;
    const late = runs.events(new AbortController().signal, undefined, () => ({
      sessions: [], transcript: null, activeRuns: runs.activeSnapshots(), lastRuns: [],
    }))[Symbol.asyncIterator]();
    expect((await late.next()).value).toMatchObject({ event: { type: "snapshot", snapshot: {
      activeRuns: [{ run: { id: run.id }, output: "first" }],
    } } });
    release();
    expect((await late.next()).value).toMatchObject({ runId: run.id, event: { type: "text_delta", delta: " second" } });
    expect((await late.next()).value?.event.type).toBe("done");
    await late.return?.();
  });

  it("keeps running when a subscriber leaves and rejects overlapping turns", async () => {
    let release!: () => void;
    let started!: () => void;
    let finished!: () => void;
    const running = new Promise<void>((resolve) => { started = resolve; });
    const completed = new Promise<void>((resolve) => { finished = resolve; });
    const fixture = runtime(async function* () {
      yield { type: "status", message: "working" };
      started();
      await new Promise<void>((resolve) => { release = resolve; });
      yield { type: "done", sessionId: "s1" };
      finished();
    });
    const runs = new RunCoordinator(fixture.value);
    const observer = runs.events(new AbortController().signal)[Symbol.asyncIterator]();
    const run = runs.start({ text: "first" });
    await observer.next();
    await observer.return?.();
    await running;
    expect(() => runs.start({ text: "second", sessionId: "s1" })).toThrow(RunBusyError);
    expect(run.origin).toBe("api");
    release();
    await completed;
  });

  it("cancels only through explicit stop", async () => {
    let aborted = false;
    const fixture = runtime(async function* (signal) {
      yield { type: "status", message: "working" };
      if (!signal.aborted) {
        await new Promise<void>((resolve) => signal.addEventListener("abort", resolve, { once: true }));
      }
      aborted = signal.aborted;
      yield { type: "error", message: "Interrupted." };
    });
    const runs = new RunCoordinator(fixture.value);
    const events = collectRun(runs.events(new AbortController().signal));
    const run = runs.start({ text: "stop me" });
    expect(runs.stop(run.id)).toBe(true);
    expect((await events).at(-1)?.event.type).toBe("error");
    expect(aborted).toBe(true);
    expect(runs.stop(run.id)).toBe(false);
  });

  it("disconnects a subscriber that falls behind without stopping the run", async () => {
    let notifyOverflow!: () => void;
    const overflow = new Promise<void>((resolve) => { notifyOverflow = resolve; });
    let completed = false;
    const fixture = runtime(async function* () {
      yield { type: "text_delta", delta: "x".repeat(MAX_EVENT_BUFFER_BYTES) };
      completed = true;
      yield { type: "done", sessionId: "s1" };
    });
    const runs = new RunCoordinator(fixture.value);
    const slow = runs.events(new AbortController().signal, notifyOverflow)[Symbol.asyncIterator]();
    const first = slow.next();
    runs.start({ text: "hi" });
    expect((await first).value?.event.type).toBe("session_activity");
    await overflow;
    await expect(slow.next()).rejects.toBeInstanceOf(SlowSubscriberError);
    expect(completed).toBe(true);
    expect(fixture.executions()).toBe(1);
  });
});
