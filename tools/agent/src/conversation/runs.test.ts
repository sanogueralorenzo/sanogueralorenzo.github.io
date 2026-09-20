import { describe, expect, it } from "vitest";
import type { AgentRuntime } from "./runtime.js";
import { RunBusyError, RunCoordinator } from "./runs.js";
import type { RunEnvelope, RuntimeEvent } from "./types.js";

function runtime(run: (signal: AbortSignal) => AsyncGenerator<RuntimeEvent>) {
  let executions = 0;
  return {
    value: { async *run(_turn: unknown, options: { signal: AbortSignal }) {
      executions += 1;
      yield* run(options.signal);
    } } as unknown as AgentRuntime,
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
    expect(a[0]).toMatchObject({ runId: run.id, event: { type: "turn", channel: "cli" } });

    const late = collectRun(runs.events(new AbortController().signal));
    const next = runs.start({ text: "next", channel: "telegram" });
    const c = await late;
    expect(fixture.executions()).toBe(2);
    expect(c.every(({ runId }) => runId === next.id)).toBe(true);
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
    expect(() => runs.start({ text: "second" })).toThrow(RunBusyError);
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
    runs.start({ text: "stop me" });
    expect(runs.stop()).toBe(true);
    expect((await events).at(-1)?.event.type).toBe("error");
    expect(aborted).toBe(true);
    expect(runs.stop()).toBe(false);
  });
});
