import { randomUUID } from "node:crypto";
import type { AgentRuntime } from "./runtime.js";
import type { RunEnvelope, RunInfo, RunSnapshot, RuntimeEvent, RuntimeSnapshot, TurnRequest } from "./types.js";

export class RunBusyError extends Error {
  constructor(readonly run: RunInfo) {
    super("Agent is already working on another message.");
  }
}

type Listener = (event?: RunEnvelope) => void;
export const MAX_EVENT_BUFFER_BYTES = 1_000_000;
const MAX_PENDING_EVENTS = 1_024;

export class SlowSubscriberError extends Error {
  constructor() { super("Agent event subscriber fell behind."); }
}

export class RunCoordinator {
  private active: (RunSnapshot & { controller: AbortController; terminal: boolean }) | null = null;
  private listeners = new Set<Listener>();
  private closed = false;
  private executing: Promise<void> | null = null;

  constructor(private readonly runtime: Pick<AgentRuntime, "run">) {}

  start(turn: TurnRequest): RunInfo {
    if (this.active) throw new RunBusyError(this.active.run);
    const info: RunInfo = { id: randomUUID(), origin: turn.channel ?? "api" };
    const run: RunSnapshot & { controller: AbortController; terminal: boolean } = {
      run: info,
      turn: { type: "turn", text: turn.text, channel: info.origin, hasAttachments: Boolean(turn.attachments?.length) },
      session: null,
      output: "",
      artifacts: [],
      navigation: null,
      controller: new AbortController(),
      terminal: false,
    };
    this.active = run;
    this.publish(info.id, run.turn);
    this.executing = this.execute(run, turn);
    return info;
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

  activeSnapshot(): RunSnapshot | null {
    if (!this.active || this.active.terminal) return null;
    const { run, turn, session, output, artifacts, navigation } = this.active;
    return { run, turn, session, output, artifacts: [...artifacts], navigation };
  }

  async *events(signal: AbortSignal, onOverflow?: () => void, snapshot?: () => RuntimeSnapshot): AsyncGenerator<RunEnvelope> {
    const queued: { event: RunEnvelope; bytes: number }[] = [];
    let pendingBytes = 0;
    let overflow = false;
    let wake: (() => void) | undefined;
    const listener: Listener = (event) => {
      if (event && !overflow) {
        const bytes = Buffer.byteLength(JSON.stringify(event));
        if (queued.length >= MAX_PENDING_EVENTS || pendingBytes + bytes > MAX_EVENT_BUFFER_BYTES) {
          overflow = true;
          queued.length = 0;
          pendingBytes = 0;
          onOverflow?.();
        } else {
          queued.push({ event, bytes });
          pendingBytes += bytes;
        }
      }
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
      if (snapshot) yield { runId: "", event: { type: "snapshot", snapshot: snapshot() } };
      while (!this.closed && !signal.aborted) {
        if (overflow) throw new SlowSubscriberError();
        if (!queued.length) await new Promise<void>((resolve) => { wake = resolve; });
        if (overflow) throw new SlowSubscriberError();
        while (queued.length) {
          const { event, bytes } = queued.shift()!;
          pendingBytes -= bytes;
          yield event;
        }
      }
    } finally {
      this.listeners.delete(listener);
      signal.removeEventListener("abort", aborted);
    }
  }

  private async execute(run: RunSnapshot & { controller: AbortController; terminal: boolean }, turn: TurnRequest): Promise<void> {
    let terminal = false;
    try {
      for await (const event of this.runtime.run(turn, { signal: run.controller.signal, runId: run.run.id })) {
        terminal ||= event.type === "done" || event.type === "error";
        this.publish(run.run.id, event);
      }
      if (!terminal) this.publish(run.run.id, { type: "error", message: "Agent stopped before completing the response." });
    } catch (error) {
      this.publish(run.run.id, { type: "error", message: error instanceof Error ? error.message : String(error) });
    } finally {
      if (this.active?.run.id === run.run.id) this.active = null;
      this.executing = null;
    }
  }

  private publish(runId: string, event: RuntimeEvent): void {
    if (this.active?.run.id === runId) {
      if (event.type === "done" || event.type === "error") this.active.terminal = true;
      if (event.type === "session" || event.type === "navigate") this.active.session = event.session;
      if (event.type === "navigate") this.active.navigation = event;
      if (event.type === "text_delta") this.active.output += event.delta;
      if (event.type === "artifact") this.active.artifacts.push(event.artifact);
    }
    const envelope = { runId, event };
    for (const listener of this.listeners) listener(envelope);
  }
}
