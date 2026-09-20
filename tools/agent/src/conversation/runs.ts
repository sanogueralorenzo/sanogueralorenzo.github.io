import { randomUUID } from "node:crypto";
import type { AgentRuntime } from "./runtime.js";
import type { RunEnvelope, RunInfo, RuntimeEvent, TurnRequest } from "./types.js";

export class RunBusyError extends Error {
  constructor(readonly run: RunInfo) {
    super("Agent is already working on another message.");
  }
}

type Listener = (event?: RunEnvelope) => void;

export class RunCoordinator {
  private active: (RunInfo & { controller: AbortController }) | null = null;
  private listeners = new Set<Listener>();
  private closed = false;
  private executing: Promise<void> | null = null;

  constructor(private readonly runtime: Pick<AgentRuntime, "run">) {}

  start(turn: TurnRequest): RunInfo {
    if (this.active) throw new RunBusyError(this.active);
    const run: RunInfo & { controller: AbortController } = {
      id: randomUUID(),
      origin: turn.channel ?? "api",
      controller: new AbortController(),
    };
    this.active = run;
    this.publish(run.id, {
      type: "turn",
      text: turn.text,
      channel: run.origin,
      hasAttachments: Boolean(turn.attachments?.length),
    });
    this.executing = this.execute(run, turn);
    return { id: run.id, origin: run.origin };
  }

  stop(): boolean {
    if (!this.active) return false;
    this.active.controller.abort();
    return true;
  }

  isBusy(): boolean {
    return this.active !== null;
  }

  async close(): Promise<void> {
    this.closed = true;
    this.active?.controller.abort();
    for (const listener of this.listeners) listener();
    this.listeners.clear();
    await this.executing;
  }

  async *events(signal: AbortSignal): AsyncGenerator<RunEnvelope> {
    const queued: RunEnvelope[] = [];
    let wake: (() => void) | undefined;
    const listener: Listener = (event) => {
      if (event) queued.push(event);
      wake?.();
      wake = undefined;
    };
    const aborted = () => {
      wake?.();
      wake = undefined;
    };
    this.listeners.add(listener);
    signal.addEventListener("abort", aborted, { once: true });
    try {
      while (!this.closed && !signal.aborted) {
        if (!queued.length) await new Promise<void>((resolve) => { wake = resolve; });
        while (queued.length) {
          const event = queued.shift()!;
          yield event;
        }
      }
    } finally {
      this.listeners.delete(listener);
      signal.removeEventListener("abort", aborted);
    }
  }

  private async execute(run: RunInfo & { controller: AbortController }, turn: TurnRequest): Promise<void> {
    let terminal = false;
    try {
      for await (const event of this.runtime.run(turn, { signal: run.controller.signal })) {
        terminal ||= event.type === "done" || event.type === "error";
        this.publish(run.id, event);
      }
      if (!terminal) this.publish(run.id, { type: "error", message: "Agent stopped before completing the response." });
    } catch (error) {
      this.publish(run.id, { type: "error", message: error instanceof Error ? error.message : String(error) });
    } finally {
      if (this.active?.id === run.id) this.active = null;
      this.executing = null;
    }
  }

  private publish(runId: string, event: RuntimeEvent): void {
    const envelope = { runId, event };
    for (const listener of this.listeners) listener(envelope);
  }
}
