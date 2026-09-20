import { randomUUID } from "node:crypto";
import type { AgentRuntime } from "./runtime.js";
import type { RunEnvelope, RunInfo, RunState, RuntimeEvent, TurnRequest } from "./types.js";

const MAX_EVENTS = 1_000;

export class RunBusyError extends Error {
  constructor(readonly run: RunInfo) {
    super("Agent is already working on another message.");
  }
}

type Listener = (event?: RunEnvelope) => void;

export class RunCoordinator {
  private active: (RunInfo & { controller: AbortController }) | null = null;
  private history: RunEnvelope[] = [];
  private listeners = new Set<Listener>();
  private sequence = 0;
  private closed = false;
  private executing: Promise<void> | null = null;

  constructor(private readonly runtime: Pick<AgentRuntime, "run">) {}

  state(): RunState {
    const { active } = this;
    return {
      active: active ? { id: active.id, origin: active.origin, startSequence: active.startSequence } : null,
      latestSequence: this.sequence,
    };
  }

  start(turn: TurnRequest): RunInfo {
    if (this.active) throw new RunBusyError(this.active);
    const run: RunInfo & { controller: AbortController } = {
      id: randomUUID(),
      origin: turn.channel ?? "api",
      startSequence: this.sequence + 1,
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
    return { id: run.id, origin: run.origin, startSequence: run.startSequence };
  }

  stop(): boolean {
    if (!this.active) return false;
    this.active.controller.abort();
    return true;
  }

  async close(): Promise<void> {
    this.closed = true;
    this.active?.controller.abort();
    for (const listener of this.listeners) listener();
    this.listeners.clear();
    await this.executing;
  }

  async *events(cursor: number, signal: AbortSignal): AsyncGenerator<RunEnvelope> {
    let after = cursor > this.sequence ? 0 : cursor;
    const queued = this.history.filter((event) => event.sequence > after);
    let wake: (() => void) | undefined;
    const listener: Listener = (event) => {
      if (event && event.sequence > after) queued.push(event);
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
          if (event.sequence <= after || !event.runId) continue;
          after = event.sequence;
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
    const envelope = { runId, sequence: ++this.sequence, event };
    this.history.push(envelope);
    if (this.history.length > MAX_EVENTS) this.history.shift();
    for (const listener of this.listeners) listener(envelope);
  }
}
