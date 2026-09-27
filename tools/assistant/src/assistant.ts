import { randomUUID } from "node:crypto";
import { homedir } from "node:os";
import { CodexService } from "./codex.ts";
import { HomeRouter, type Route } from "./home-routing.ts";
import { State, now, type HomeEntry, type HomeMessage, type SessionRecord, type Turn } from "./state.ts";
type Active = { turn: Turn; codexTurnId: string | null; output: string; error: string; stopped: boolean;
  commentary: string; tool: string; thinking: string; lastProgress: string; savedProgress: string;
  messagePhases: Map<string, string | null>; pendingSteers: Array<{ text: string; sourceId: string; entry?: HomeEntry }> };
const clean = (text: string) => text.replace(/\x1b\[[0-?]*[ -/]*[@-~]/g, "").replace(/[\x00-\x08\x0b-\x1f\x7f]/g, "");
const errorText = (error: unknown) => error instanceof Error ? error.message : String(error);
const toolLabels: Record<string, string> = {
  read: "Looking through files", grep: "Looking through files", find: "Looking through files", ls: "Looking through files",
  edit: "Editing files", write: "Editing files", bash: "Running a command",
};
function toolLabel(name: string, args: unknown) {
  if (name === "delegate") return (args as { role?: string })?.role === "reviewer" ? "Reviewing" : "Researching";
  return toolLabels[name] || `Tool: ${name}`;
}

export class Assistant {
  readonly dataDir: string;
  readonly cwd: string;
  readonly concurrency = 4;
  readonly state: State;
  readonly codex: CodexService;
  readonly router: HomeRouter;
  private listeners = new Set<(event: unknown) => void>();
  private active = new Map<string, Active>();
  private starting = new Set<string>();
  private pendingStops = new Set<string>();
  private homeRouting: Promise<void> = Promise.resolve();
  private closing = false;
  constructor(dataDir: string, cwd: string) {
    this.dataDir = dataDir;
    this.cwd = cwd;
    this.state = new State(dataDir, () => { if (this.state) this.emit({ type: "snapshot", data: this.snapshot() }); });
    this.codex = new CodexService();
    this.router = new HomeRouter(this.state, this.codex, cwd);
    this.codex.subscribe((method, params) => this.onCodexEvent(method, params));
    queueMicrotask(() => this.drain());
  }
  subscribe(listener: (event: unknown) => void) { this.listeners.add(listener); return () => this.listeners.delete(listener); }
  private emit(event: unknown) { for (const listener of this.listeners) listener(event); }
  snapshot() { return this.state.data; }
  activities() { return [...this.active.values()].filter((run) => run.turn.sourceId)
    .map((run) => ({ type: "homeActivity", sourceId: run.turn.sourceId, text: run.lastProgress })); }
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
      const cwd = route.cwd?.trim() || homedir();
      const id = await this.codex.create(cwd);
      session = { id, title: clean(route.title.slice(0, 100)), cwd, status: "idle", createdAt: now() };
      await this.codex.name(id, session.title);
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
  submitSession(sessionId: string, text: string, mode: "followUp" | "steer" = "followUp", options: { replyToId?: string; editOfId?: string; id?: string } = {}) {
    const { replyToId, editOfId, id } = options;
    const record = this.state.data.sessions.find((session) => session.id === sessionId);
    if (!record) throw new Error("Conversation not found");
    if (replyToId && editOfId) throw new Error("Choose Reply or Edit");
    const referenced = replyToId || editOfId ? this.replyTarget((replyToId || editOfId)!) : undefined;
    if (replyToId && referenced?.entry.sessionId !== sessionId) throw new Error("Reply target is not in this conversation");
    const active = this.active.get(sessionId);
    if (editOfId && (mode !== "steer" || referenced?.role !== "user" || referenced.entry.sessionId !== sessionId || active?.turn.sourceId !== editOfId))
      throw new Error("This message is no longer active. Use Reply for a follow-up.");
    if (editOfId && text === referenced?.text) throw new Error("Change the message before sending a revision");
    const entry = mode === "steer" && active
      ? this.state.data.entries.find((item) => item.id === active.turn.entryId)
      : referenced?.entry || [...this.state.data.entries].reverse().find((item) => item.sessionId === sessionId);
    const source = this.state.message(text, id, editOfId ? { editOfId } : { replyToId });
    source.status = "routed";
    if (entry) source.entryId = entry.id;
    if (mode === "steer" && active) {
      active.turn.sourceId = source.id;
      if (editOfId) active.turn.text = text;
      if (entry) entry.status = "working";
      this.state.save();
      const steer = { text: editOfId ? `Use this revision of my active request:\n${text}` : text, sourceId: source.id, entry };
      if (active.codexTurnId) void this.codex.steer(sessionId, active.codexTurnId, steer.text)
        .catch((error) => { if (entry) this.state.update(entry, errorText(error), "error", "failed", source.id); });
      else active.pendingSteers.push(steer);
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
    if (active.codexTurnId) void this.codex.interrupt(sessionId, active.codexTurnId);
    return true;
  }
  async shutdown() {
    this.closing = true;
    const interrupted = this.state.data.turns.filter((item) => item.status === "running");
    await Promise.allSettled([...this.active.entries()].filter(([, run]) => run.codexTurnId)
      .map(([id, run]) => this.codex.interrupt(id, run.codexTurnId!)));
    for (const turn of interrupted) {
      const entry = this.state.data.entries.find((item) => item.id === turn.entryId);
      if (entry) { entry.status = "interrupted"; entry.interruptedText = turn.text; entry.interruptedSourceId = turn.sourceId; }
      const record = this.state.data.sessions.find((item) => item.id === turn.sessionId);
      if (record) record.status = "interrupted";
    }
    this.state.data.turns = this.state.data.turns.filter((item) => item.status !== "running");
    this.state.save();
    await this.codex.close();
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
  async transcript(sessionId: string) {
    const session = this.state.data.sessions.find((item) => item.id === sessionId);
    if (!session) throw new Error("Conversation not found");
    return { session, messages: await this.codex.transcript(sessionId), queue: this.state.data.turns.filter((turn) => turn.sessionId === sessionId) };
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
  private onCodexEvent(method: string, params: Record<string, unknown>) {
    const sessionId = params.threadId as string | undefined;
    const active = sessionId && this.active.get(sessionId);
    if (!active) return;
    const entry = this.state.data.entries.find((item) => item.id === active.turn.entryId);
    const progress = (persist = false) => {
      const text = clean(active.commentary || active.tool || active.thinking).trim().slice(-1200);
      if (text !== active.lastProgress) {
        active.lastProgress = text;
        if (active.turn.sourceId) this.emit({ type: "homeActivity", sourceId: active.turn.sourceId, text });
      }
      if (persist && entry && text && text !== active.savedProgress) {
        active.savedProgress = text;
        this.state.update(entry, text, "progress", "working", active.turn.sourceId);
      }
    };
    const item = params.item as { id?: string; type?: string; phase?: string | null; text?: string; command?: string; server?: string; tool?: string; arguments?: unknown; query?: string; action?: { type?: string; url?: string } } | undefined;
    if (method === "item/agentMessage/delta" && typeof params.delta === "string") {
      active.commentary += params.delta;
      progress();
      if (active.messagePhases.get(String(params.itemId)) === "final_answer")
        this.emit({ type: "delta", sessionId, delta: params.delta });
    }
    if (method === "item/reasoning/summaryTextDelta" && typeof params.delta === "string") {
      active.thinking += params.delta;
      progress();
    }
    if (method === "item/started" && item) {
      if (item.type === "agentMessage") {
        if (item.id) active.messagePhases.set(item.id, item.phase || null);
        active.commentary = active.tool = active.thinking = "";
        progress();
      }
      if (item.type === "reasoning") active.thinking = "";
      const label = item.type === "commandExecution" ? toolLabel("bash", { command: item.command })
        : item.type === "fileChange" ? "Editing files"
        : item.type === "webSearch" ? item.action?.type === "openPage" ? `Opening: ${item.action.url || "page"}` : `Web search: ${item.query || ""}`
        : item.type === "collabToolCall" ? "Researching"
        : item.type === "dynamicToolCall" ? toolLabel(item.tool || "", item.arguments)
        : item.type === "mcpToolCall" ? item.server === "computer-use" ? "Using your computer" : `Tool: ${item.tool || "MCP"}` : "";
      if (label) { active.tool = label; active.commentary = ""; this.emit({ type: "activity", sessionId, label }); progress(true); }
    }
    if (method === "item/completed" && item) {
      if (item.type === "agentMessage" && item.text) {
        if (item.phase === "final_answer" || item.phase === null) active.output = item.text;
        else { active.commentary = item.text; progress(true); }
      }
      if (item.type !== "agentMessage") { active.tool = active.thinking = ""; progress(true); }
    }
  }
  private async run(turn: Turn) {
    const record = this.state.data.sessions.find((session) => session.id === turn.sessionId)!;
    turn.status = "running";
    record.status = "running";
    const entry = this.state.data.entries.find((item) => item.id === turn.entryId);
    if (entry) entry.status = "working";
    this.state.save();
    let active: Active | undefined;
    let interruptedTurn = false;
    try {
      await this.codex.resume(record.id, record.cwd);
      active = { turn, codexTurnId: null, output: "", error: "", stopped: false, commentary: "", tool: "", thinking: "", lastProgress: "", savedProgress: "", messagePhases: new Map(), pendingSteers: [] };
      this.active.set(record.id, active);
      this.starting.delete(record.id);
      if (this.pendingStops.has(record.id)) { active.stopped = true; throw new Error("Stopped"); }
      const replied = turn.replyToId && this.replyTarget(turn.replyToId);
      const prompt = replied ? `In reply to this earlier ${replied.role} message:\n> ${replied.text.slice(0, 2000).replaceAll("\n", "\n> ")}\n\n${turn.text}` : turn.text;
      active.codexTurnId = await this.codex.start(record.id, prompt);
      for (const steer of active.pendingSteers) await this.codex.steer(record.id, active.codexTurnId, steer.text)
        .catch((error) => { if (steer.entry) this.state.update(steer.entry, errorText(error), "error", "failed", steer.sourceId); });
      active.pendingSteers = [];
      if (active.stopped) await this.codex.interrupt(record.id, active.codexTurnId);
      const completed = await this.codex.wait(record.id, active.codexTurnId);
      const codexTurn = completed.turn as { status: string; error?: { message?: string } };
      if (codexTurn.status === "interrupted") throw new Error("Stopped");
      if (codexTurn.status !== "completed") throw new Error(codexTurn.error?.message || "Codex turn failed");
      if (active.stopped) throw new Error("Stopped");
      if (active.error) throw new Error(active.error);
      if (!active.output) throw new Error("Agent returned no final reply");
      if (entry) this.state.update(entry, clean(active.output), "result", "ready", turn.sourceId);
    } catch (error) {
      const failure = errorText(error).toLowerCase();
      const interrupted = active?.stopped || failure.includes("stopped") || failure.includes("app-server exited");
      interruptedTurn = !!interrupted;
      if (entry) {
        if (interrupted) { entry.interruptedText = turn.text; entry.interruptedSourceId = turn.sourceId; }
        this.state.update(entry, interrupted ? "Stopped. You can continue this conversation." : errorText(error), "error", interrupted ? "interrupted" : "failed", turn.sourceId);
      }
    } finally {
      if (turn.sourceId) this.emit({ type: "homeActivity", sourceId: turn.sourceId, text: "" });
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
