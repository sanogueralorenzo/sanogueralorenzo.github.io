import { randomUUID } from "node:crypto";
import type { AgentRuntime } from "./runtime.js";
import type { Store } from "./store.js";
import { HOME_SESSION_ID, type Channel, type QueuedTask, type RunEnvelope, type RunInfo, type RunSnapshot, type RuntimeEvent, type RuntimeSnapshot, type TurnRequest } from "./types.js";

export class RunBusyError extends Error {
  constructor(readonly run: RunInfo) {
    super("Agent is already working in this conversation.");
  }
}

type Listener = (event?: RunEnvelope) => void;
export const MAX_EVENT_BUFFER_BYTES = 1_000_000;
const MAX_PENDING_EVENTS = 1_024;

export class SlowSubscriberError extends Error {
  constructor() { super("Agent event subscriber fell behind."); }
}

export class RunCoordinator {
  private active = new Map<string, RunSnapshot & { controller: AbortController; terminal: boolean }>();
  private listeners = new Set<Listener>();
  private closed = false;
  private executing = new Set<Promise<void>>();
  private homeCommit = Promise.resolve();
  private pendingSteers = new Set<string>();

  constructor(private readonly runtime: Pick<AgentRuntime, "prepareTurn" | "run" | "steer">, private readonly store: Store) {
    queueMicrotask(() => { for (const id of this.store.home.queuedSessionIds()) this.startQueued(id); });
  }

  private activeFor(sessionId: string) {
    return [...this.active.values()].find((run) => run.run.sessionId === sessionId && !run.terminal);
  }

  private startQueued(sessionId: string): void {
    if (this.closed || this.activeFor(sessionId) || this.pendingSteers.has(sessionId)) return;
    const queued = this.store.home.queuedTask(sessionId);
    if (queued) {
      this.start({ text: queued.text, sessionId, channel: queued.channel, queuedTaskId: queued.id,
        ...(queued.homeEntryId ? { homeEntryId: queued.homeEntryId } : {}) });
      queueMicrotask(() => this.publishQueue(sessionId));
    }
  }

  queue(sessionId: string, text: string, channel: Channel): QueuedTask {
    if (!this.store.getSession(sessionId) || sessionId === HOME_SESSION_ID) throw new Error("Conversation was not found.");
    const task = this.store.home.enqueueTask(sessionId, text, channel);
    this.publishQueue(sessionId);
    this.startQueued(sessionId);
    return task;
  }

  removeQueued(sessionId: string, id: string): QueuedTask {
    if (this.pendingSteers.has(sessionId)) throw new Error("Wait for the steer to finish.");
    const task = this.store.home.removeQueuedTask(sessionId, id);
    if (!task) throw new Error("Follow-up is no longer queued.");
    this.publishQueue(sessionId);
    return task;
  }

  async steerQueued(sessionId: string, id: string, expectedRunId: string): Promise<boolean> {
    const active = this.activeFor(sessionId);
    if (!active || active.run.id !== expectedRunId || this.pendingSteers.has(sessionId)) return false;
    const task = this.store.home.queuedTasks(sessionId).find((item) => item.id === id);
    if (!task) throw new Error("Follow-up is no longer queued.");
    this.pendingSteers.add(sessionId);
    try {
      if (!await this.runtime.steer(sessionId, task.text)) return false;
      this.store.home.removeQueuedTask(sessionId, id);
      this.publishQueue(sessionId);
      this.publish(sessionId, active.run.id, { type: "steer", text: task.text, channel: task.channel });
      return true;
    } finally {
      this.pendingSteers.delete(sessionId);
      this.startQueued(sessionId);
    }
  }

  private publishQueue(sessionId: string): void {
    this.publish(sessionId, "", { type: "queue", tasks: this.store.home.queuedTasks(sessionId) });
  }

  start(turn: TurnRequest): RunInfo {
    const prepared = this.runtime.prepareTurn(turn);
    const sessionId = prepared.session.id;
    const busy = sessionId === HOME_SESSION_ID ? null : this.activeFor(sessionId);
    if (busy) throw new RunBusyError(busy.run);
    const info: RunInfo = { id: turn.requestId ?? randomUUID(), sessionId, origin: turn.channel ?? "api" };
    const run: RunSnapshot & { controller: AbortController; terminal: boolean } = {
      run: info,
      turn: { type: "turn", text: turn.text, channel: info.origin, hasAttachments: Boolean(turn.attachments?.length) },
      session: prepared.session,
      output: "",
      artifacts: [],
      navigation: null,
      controller: new AbortController(),
      terminal: false,
    };
    this.active.set(info.id, run);
    if (sessionId !== HOME_SESSION_ID) {
      this.publish(sessionId, info.id, { type: "session_activity", sessionId, runId: info.id });
      if (!prepared.deferTurn) this.publish(sessionId, info.id, run.turn);
    }
    let releaseHome: (() => void) | undefined;
    const beforeHomeDispatch = sessionId === HOME_SESSION_ID ? this.homeCommit : undefined;
    if (beforeHomeDispatch) this.homeCommit = new Promise<void>((resolve) => { releaseHome = resolve; });
    const execution = this.execute(run, turn, prepared, beforeHomeDispatch, releaseHome);
    this.executing.add(execution);
    void execution.finally(() => this.executing.delete(execution));
    return info;
  }

  stop(runId: string): boolean {
    const run = this.active.get(runId);
    if (!run) return false;
    run.controller.abort();
    return true;
  }

  async close(): Promise<void> {
    this.closed = true;
    for (const run of this.active.values()) run.controller.abort();
    for (const listener of this.listeners) listener();
    this.listeners.clear();
    await Promise.all(this.executing);
  }

  activeSnapshots(sessionId?: string): RunSnapshot[] {
    const runs = [...this.active.values()].filter((run) => !run.terminal && run.run.sessionId !== HOME_SESSION_ID && (!sessionId || run.run.sessionId === sessionId));
    return runs.map((run) => {
      const { run: info, turn, session, output, artifacts, navigation } = run;
      return { run: info, turn, session, output, artifacts: [...artifacts], navigation };
    });
  }

  activeInfos(): RunInfo[] {
    return [...this.active.values()].filter((run) => !run.terminal && run.run.sessionId !== HOME_SESSION_ID).map((run) => run.run);
  }

  async *events(signal: AbortSignal, onOverflow?: () => void, snapshot?: () => RuntimeSnapshot, sessionId?: string): AsyncGenerator<RunEnvelope> {
    const queued: { event: RunEnvelope; bytes: number }[] = [];
    let pendingBytes = 0;
    let overflow = false;
    let wake: (() => void) | undefined;
    const listener: Listener = (event) => {
      if (event && sessionId && event.sessionId !== sessionId && event.event.type !== "session_activity"
        && event.event.type !== "home_entry" && event.event.type !== "home_entry_removed") return;
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
      if (snapshot) yield { sessionId: sessionId ?? "", runId: "", event: { type: "snapshot", snapshot: snapshot() } };
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

  private async execute(
    run: RunSnapshot & { controller: AbortController; terminal: boolean },
    turn: TurnRequest,
    prepared: ReturnType<AgentRuntime["prepareTurn"]>,
    beforeHomeDispatch?: Promise<void>,
    releaseHome?: () => void,
  ): Promise<void> {
    let terminal = false;
    try {
      for await (const event of this.runtime.run(turn, {
        signal: run.controller.signal,
        runId: run.run.id,
        prepared,
        ...(beforeHomeDispatch ? { beforeHomeDispatch } : {}),
        canHandoff: (targetId) => {
          const busy = this.activeFor(targetId);
          if (busy && busy !== run) throw new RunBusyError(busy.run);
        },
        steer: async (targetId, text, channel) => {
          const active = this.activeFor(targetId);
          if (!active || !await this.runtime.steer(targetId, text)) return false;
          this.publish(targetId, active.run.id, { type: "steer", text, channel: channel ?? "api" });
          return true;
        },
      })) {
        if (event.type === "task_queued") {
          this.publishQueue(event.sessionId);
          this.startQueued(event.sessionId);
          continue;
        }
        if (event.type === "home_entry" || event.type === "home_entry_removed") {
          this.publish(HOME_SESSION_ID, run.run.id, event);
          continue;
        }
        terminal ||= event.type === "done" || event.type === "error";
        if (run.run.sessionId === HOME_SESSION_ID) {
          continue;
        }
        if (event.type === "navigate") {
          const sourceId = run.run.sessionId;
          this.publish(sourceId, run.run.id, event);
          run.run.sessionId = event.session.id;
          this.publish(sourceId, run.run.id, { type: "session_activity", sessionId: sourceId, runId: null });
          this.publish(event.session.id, run.run.id, { type: "session_activity", sessionId: event.session.id, runId: run.run.id });
          continue;
        }
        this.publish(run.run.sessionId, run.run.id, event);
      }
      if (!terminal) this.publish(run.run.sessionId, run.run.id,
        run.run.sessionId === HOME_SESSION_ID
          ? { type: "error", message: "Home stopped before dispatching the request." }
          : { type: "error", message: "Agent stopped before completing the response." });
    } catch (error) {
      this.publish(run.run.sessionId, run.run.id, {
        type: "error",
        message: error instanceof Error ? error.message : String(error),
      });
    } finally {
      releaseHome?.();
      this.active.delete(run.run.id);
      if (run.run.sessionId !== HOME_SESSION_ID) this.publish(run.run.sessionId, run.run.id, {
        type: "session_activity", sessionId: run.run.sessionId, runId: null,
      });
      this.startQueued(run.run.sessionId);
    }
  }

  private publish(sessionId: string, runId: string, event: RuntimeEvent): void {
    const active = this.active.get(runId);
    if (active?.run.id === runId) {
      if (event.type === "done" || event.type === "error") active.terminal = true;
      if (event.type === "turn") active.turn = event;
      if (event.type === "session") active.session = event.session;
      if (event.type === "navigate") active.navigation = event;
      if (event.type === "text_delta") active.output += event.delta;
      if (event.type === "artifact") active.artifacts.push(event.artifact);
    }
    const envelope = { sessionId, runId, event };
    for (const listener of this.listeners) listener(envelope);
  }
}
