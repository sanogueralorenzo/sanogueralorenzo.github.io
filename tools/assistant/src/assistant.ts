import { randomUUID } from "node:crypto";
import { homedir } from "node:os";
import { PiService, assistantText } from "./pi.ts";
import { HomeRouter, type Route } from "./home-routing.ts";
import { State, now, type HomeMessage, type SessionRecord, type Turn } from "./state.ts";
import type { AgentSession } from "@earendil-works/pi-coding-agent";

type Active = { session: AgentSession; turn: Turn; output: string; error: string; stopped: boolean; lastProgress?: string };
const clean = (text: string) => text.replace(/\x1b\[[0-?]*[ -/]*[@-~]/g, "").replace(/[\x00-\x08\x0b-\x1f\x7f]/g, "");
const errorText = (error: unknown) => error instanceof Error ? error.message : String(error);
const progressByTool: Record<string, string> = { read: "Inspecting files", grep: "Searching files", find: "Finding files", ls: "Inspecting files",
  edit: "Making changes", write: "Making changes", bash: "Running commands" };
const toolProgress = (name: string) => progressByTool[name] || "Working with tools";

export class Assistant {
  readonly dataDir: string;
  readonly cwd: string;
  readonly concurrency: number;
  readonly state: State;
  readonly pi: PiService;
  readonly router: HomeRouter;
  private listeners = new Set<(event: unknown) => void>();
  private active = new Map<string, Active>();
  private starting = new Set<string>();
  private pendingStops = new Set<string>();
  private homeRouting: Promise<void> = Promise.resolve();
  private closing = false;
  constructor(dataDir: string, cwd: string, concurrency = 4) {
    this.dataDir = dataDir;
    this.cwd = cwd;
    this.concurrency = concurrency;
    this.state = new State(dataDir, () => { if (this.state) this.emit({ type: "snapshot", data: this.snapshot() }); });
    this.pi = new PiService(dataDir);
    this.router = new HomeRouter(this.state, this.pi, cwd);
    queueMicrotask(() => this.drain());
  }
  subscribe(listener: (event: unknown) => void) { this.listeners.add(listener); return () => this.listeners.delete(listener); }
  private emit(event: unknown) { for (const listener of this.listeners) listener(event); }
  snapshot() { return this.state.data; }
  submitHome(text: string, id?: string) {
    const message = this.state.message(text, id);
    const routed = this.homeRouting.then(async () => {
      try {
        const route = await this.router.discover(message);
        await this.commitRoute(message, route);
      }
      catch (error) { message.status = "failed"; this.state.entry(message, "Routing failed", null); const entry = this.state.data.entries.at(-1)!; this.state.update(entry, errorText(error), "error", "failed"); this.state.save(); }
    });
    this.homeRouting = routed.catch(() => undefined);
    return message;
  }
  private async commitRoute(message: HomeMessage, route: Route) {
    let session: SessionRecord;
    if (route.mode === "start") {
      const cwd = route.cwd?.trim() || (route.agent === "personal" ? homedir() : this.cwd);
      const pi = await this.pi.create(cwd, randomUUID(), route.agent);
      session = { id: pi.sessionId, title: clean(route.title.slice(0, 100)), role: route.agent, cwd, file: pi.sessionFile!, status: "idle", createdAt: now() };
      pi.dispose();
      this.state.data.sessions.push(session);
    } else session = this.state.data.sessions.find((item) => item.id === route.sessionId)!;
    const entry = this.state.entry(message, session.title, session.id);
    this.state.data.turns.push({ id: randomUUID(), sessionId: session.id, entryId: entry.id, sourceId: message.id,
      text: message.text, status: "queued", createdAt: now() });
    message.status = "routed";
    this.state.save();
    this.drain();
  }
  private replyTarget(id: string) {
    const message = this.state.data.messages.find((item) => item.id === id);
    if (message) {
      const entry = this.state.data.entries.find((item) => item.id === message.entryId);
      return entry && { entry, text: message.text, role: "user" };
    }
    for (const entry of this.state.data.entries) {
      const update = entry.updates.find((item) => item.id === id);
      if (update) return { entry, text: update.text, role: "assistant" };
    }
  }
  submitSession(sessionId: string, text: string, mode: "followUp" | "steer" = "followUp", replyToId?: string, id?: string) {
    const record = this.state.data.sessions.find((session) => session.id === sessionId);
    if (!record) throw new Error("Conversation not found");
    const referenced = replyToId ? this.replyTarget(replyToId) : undefined;
    if (replyToId && referenced?.entry.sessionId !== sessionId) throw new Error("Reply target is not in this conversation");
    const active = this.active.get(sessionId);
    const entry = mode === "steer" && active
      ? this.state.data.entries.find((item) => item.id === active.turn.entryId)
      : referenced?.entry || [...this.state.data.entries].reverse().find((item) => item.sessionId === sessionId);
    const source = this.state.message(text, id, replyToId);
    source.status = "routed";
    if (entry) source.entryId = entry.id;
    if (mode === "steer" && active) {
      active.turn.sourceId = source.id;
      if (entry) {
        this.state.update(entry, "Steered the active conversation.", "progress", "working", source.id);
      }
      void active.session.steer(text).catch((error) => this.emit({ type: "error", message: errorText(error) }));
      return { steered: true };
    }
    const turn: Turn = { id: randomUUID(), sessionId, entryId: entry?.id || null, sourceId: source.id, replyToId, text, status: "queued", createdAt: now() };
    this.state.data.turns.push(turn);
    this.state.save();
    this.drain();
    return { turn };
  }
  stop(sessionId: string) {
    const active = this.active.get(sessionId);
    if (!active) {
      if (!this.starting.has(sessionId)) return false;
      this.pendingStops.add(sessionId);
      return true;
    }
    active.stopped = true;
    void active.session.abort();
    return true;
  }
  async shutdown() {
    this.closing = true;
    const interrupted = this.state.data.turns.filter((item) => item.status === "running");
    await Promise.allSettled([...this.active.values()].map((run) => run.session.abort()));
    for (const turn of interrupted) {
      const entry = this.state.data.entries.find((item) => item.id === turn.entryId);
      if (entry) { entry.status = "interrupted"; entry.interruptedText = turn.text; entry.interruptedSourceId = turn.sourceId; }
      const record = this.state.data.sessions.find((item) => item.id === turn.sessionId);
      if (record) record.status = "interrupted";
    }
    this.state.data.turns = this.state.data.turns.filter((item) => item.status !== "running");
    this.state.save();
  }
  resume(entryId: string) {
    const entry = this.state.data.entries.find((item) => item.id === entryId);
    if (!entry?.sessionId || entry.status !== "interrupted") throw new Error("This task is not interrupted");
    entry.status = "queued";
    const request = entry.interruptedText || this.state.data.messages.find((message) => message.id === entry.sourceId)?.text || "";
    const sourceId = entry.interruptedSourceId || entry.sourceId;
    entry.interruptedText = undefined;
    entry.interruptedSourceId = undefined;
    const turn: Turn = { id: randomUUID(), sessionId: entry.sessionId, entryId, sourceId, text: `Continue the interrupted request in this conversation:\n${request}`, status: "queued", createdAt: now() };
    const firstWaiting = this.state.data.turns.findIndex((item) => item.sessionId === entry.sessionId);
    this.state.data.turns.splice(firstWaiting < 0 ? this.state.data.turns.length : firstWaiting, 0, turn);
    this.state.data.sessions.find((session) => session.id === entry.sessionId)!.status = "idle";
    this.state.save();
    this.drain();
  }
  transcript(sessionId: string) {
    const session = this.state.data.sessions.find((item) => item.id === sessionId);
    if (!session) throw new Error("Conversation not found");
    return { session, messages: this.pi.transcript(session.file), queue: this.state.data.turns.filter((turn) => turn.sessionId === sessionId) };
  }
  private drain() {
    if (this.closing) return;
    for (const turn of this.state.data.turns) {
      if (this.active.size + this.starting.size >= this.concurrency) break;
      if (turn.status !== "queued" || this.active.has(turn.sessionId) || this.starting.has(turn.sessionId) ||
        this.state.data.sessions.find((session) => session.id === turn.sessionId)?.status === "interrupted") continue;
      this.starting.add(turn.sessionId);
      void this.run(turn);
    }
  }
  private async run(turn: Turn) {
    const record = this.state.data.sessions.find((session) => session.id === turn.sessionId)!;
    turn.status = "running";
    record.status = "running";
    const entry = this.state.data.entries.find((item) => item.id === turn.entryId);
    if (entry) entry.status = "working";
    this.state.save();
    let session: AgentSession | undefined;
    let active: Active | undefined;
    let interruptedTurn = false;
    try {
      const role = record.role || "personal";
      session = await this.pi.open(record.cwd, record.file, role);
      active = { session, turn, output: "", error: "", stopped: false };
      this.active.set(record.id, active);
      this.starting.delete(record.id);
      if (this.pendingStops.has(record.id)) { active.stopped = true; throw new Error("Stopped"); }
      session.subscribe((event) => {
        if (event.type === "message_end" && event.message.role === "assistant") {
          const text = assistantText(event.message);
          if (text && event.message.stopReason !== "toolUse") active!.output = text;
          if (event.message.stopReason === "error") active!.error = event.message.errorMessage || "Model error";
          if (text && event.message.stopReason === "toolUse" && entry) this.state.update(entry, clean(text.slice(0, 900)), "progress", "working", turn.sourceId);
        }
        if (event.type === "message_update" && event.assistantMessageEvent.type === "text_delta") this.emit({ type: "delta", sessionId: record.id, delta: event.assistantMessageEvent.delta });
        if (event.type === "tool_execution_start") {
          this.emit({ type: "activity", sessionId: record.id, name: event.toolName });
          const progress = toolProgress(event.toolName);
          if (progress !== active!.lastProgress) {
            active!.lastProgress = progress;
            if (entry) this.state.update(entry, `${progress}…`, "progress", "working", turn.sourceId);
          }
        }
      });
      const replied = turn.replyToId && this.replyTarget(turn.replyToId);
      const prompt = replied ? `In reply to this earlier ${replied.role} message:\n> ${replied.text.slice(0, 2000).replaceAll("\n", "\n> ")}\n\n${turn.text}` : turn.text;
      await session.prompt(prompt, { expandPromptTemplates: false });
      if (active.stopped) throw new Error("Stopped");
      if (active.error) throw new Error(active.error);
      if (!active.output) throw new Error("Agent returned no final reply");
      if (entry) this.state.update(entry, clean(active.output), "result", "ready", turn.sourceId);
    } catch (error) {
      const interrupted = active?.stopped || errorText(error).toLowerCase().includes("abort");
      interruptedTurn = !!interrupted;
      if (entry) {
        if (interrupted) { entry.interruptedText = turn.text; entry.interruptedSourceId = turn.sourceId; }
        this.state.update(entry, interrupted ? "Stopped. You can continue this conversation." : errorText(error), "error", interrupted ? "interrupted" : "failed", turn.sourceId);
      }
    } finally {
      session?.dispose();
      this.active.delete(record.id);
      this.starting.delete(record.id);
      this.pendingStops.delete(record.id);
      record.status = interruptedTurn || this.closing ? "interrupted" : "idle";
      this.state.data.turns = this.state.data.turns.filter((item) => item.id !== turn.id);
      this.state.save();
      this.drain();
    }
  }
}
