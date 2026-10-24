import { randomUUID } from "node:crypto";
import { mkdirSync } from "node:fs";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { BACKGROUND_CONTEXT } from "@earendil-works/chord/context";
import type { ConversationId, ConversationView, SubmissionId, TaskId } from "@earendil-works/pi-durable";
import { PiService, type PiOptions } from "./pi.ts";
import { HomeRouter } from "./home-routing.ts";
import { HomeDoc, State, now, assistantText, type HomeMessage, type Turn } from "./state.ts";
import { PromptSuggestions } from "./prompt-suggestions.ts";
import { requestTask, enqueueRequest, cancelRequest, requestsInSession } from "./request-tasks.ts";
import { routingTask, dispatchTask, enqueueDispatch } from "./request-scheduling.ts";

const clean = (text: string) => text.replace(/\x1b\[[0-?]*[ -/]*[@-~]/g, "").replace(/[\x00-\x08\x0b-\x1f\x7f]/g, "");
const replyPrompt = (text: string, reply?: { role: string; text: string }) => reply
  ? `In reply to this earlier ${reply.role} message:\n> ${reply.text.slice(0, 2000).replaceAll("\n", "\n> ")}\n\n${text}` : text;

export class Assistant {
  readonly dataDir: string;
  readonly cwd: string;
  readonly pi: PiService;
  readonly state: State;
  readonly router: HomeRouter;
  readonly suggestions: PromptSuggestions;
  private readonly db: DatabaseSync;
  readonly work: ReturnType<typeof requestTask>;
  private readonly routing: ReturnType<typeof routingTask>;
  private readonly dispatch: ReturnType<typeof dispatchTask>;
  private readonly rootId: ConversationId;
  private readonly listeners = new Set<(event: unknown) => void>();
  private readonly finished = new Set<string>();
  private closing?: Promise<void>;
  private constructor(dataDir: string, cwd: string, pi: PiService, db: DatabaseSync, routing: ReturnType<typeof routingTask>, dispatch: ReturnType<typeof dispatchTask>, work: ReturnType<typeof requestTask>, rootId: ConversationId) {
    this.dataDir = dataDir; this.cwd = cwd; this.pi = pi; this.db = db; this.routing = routing; this.dispatch = dispatch; this.work = work; this.rootId = rootId;
    this.state = new State(pi.harness); this.router = new HomeRouter(this.state, pi, cwd);
    this.suggestions = new PromptSuggestions(Promise.resolve(pi.models), db, async (sessionId) => {
      const record = this.state.home.sessions.find(session => session.id === sessionId);
      if (!record) return pi.model;
      const conversation = await pi.harness.conversation(record.conversationId as ConversationId, BACKGROUND_CONTEXT);
      return (await conversation!.agent(BACKGROUND_CONTEXT)).model || pi.model;
    }, provider => pi.providers.fastEnabled(provider));
  }
  static async open(dataDir: string, cwd: string, options: PiOptions = {}) {
    let app!: Assistant;
    const dispatch = dispatchTask(() => app);
    const routing = routingTask(() => app, dispatch);
    const work = requestTask(() => app);
    const pi = await PiService.open(dataDir, { ...options, tasks: [...(options.tasks || []), routing, dispatch, work] });
    mkdirSync(dataDir, { recursive: true, mode: 0o700 });
    const db = new DatabaseSync(join(dataDir, "suggestions.db"));
    try {
      const root = await pi.harness.root(BACKGROUND_CONTEXT);
      app = new Assistant(dataDir, cwd, pi, db, routing, dispatch, work, root.id);
      await app.state.load(() => app.publish());
      for (const entry of app.snapshot().entries) for (const update of entry.updates) if (update.kind === "result") app.finished.add(update.id);
      for (const record of app.state.home.sessions) {
        for (const source of requestsInSession(app, record.id)) {
          if (!record.paused && source.executionId !== undefined && app.snapshot().turns.some(turn => turn.sourceId === source.id)) await app.state.observe(source.executionId);
          if (record.paused) await cancelRequest(app, source.id);
        }
      }
      pi.harness.resume();
      return app;
    } catch (error) { db.close(); await pi.close(); throw error; }
  }
  subscribe(listener: (event: unknown) => void) { this.listeners.add(listener); return () => this.listeners.delete(listener); }
  private emit(event: unknown) { for (const listener of this.listeners) listener(event); }
  snapshot() { return this.state.data; }
  progress() {
    return this.snapshot().turns.filter((turn) => turn.status === "running").flatMap((turn) => {
      const record = this.state.home.sessions.find((item) => item.id === turn.sessionId)!;
      const source = this.state.home.messages.find(item => item.id === turn.sourceId);
      const text = assistantText(this.state.live(source?.executionId ?? record.conversationId)?.generation?.message || {});
      return text ? [{ type: "progress", sourceId: turn.sourceId, text: clean(text).slice(-1200) }] : [];
    });
  }
  private publish() {
    const data = this.snapshot();
    this.emit({ type: "snapshot", data });
    for (const progress of this.progress()) this.emit(progress);
    for (const entry of data.entries) for (const update of entry.updates) if (update.kind === "result" && !this.finished.has(update.id)) {
      this.finished.add(update.id);
      const record = data.sessions.find((item) => item.id === entry.sessionId);
      if (record) void this.suggestions.get(record.id, update.id, this.state.transcript(record.id).filter((message) => message.role === "user" || message.completed)).catch(() => {});
    }
  }
  async submitHome(text: string, id: string = randomUUID()) {
    await this.state.change(async (home, tx) => {
      if (home.messages.some((message) => message.id === id)) throw new Error("Request ID already exists");
      home.entries.push({ id: randomUUID(), sourceId: id, title: "", sessionId: null, createdAt: now(), updatedAt: now() });
      const entry = home.entries.at(-1)!;
      home.messages.push({ id, text, createdAt: now(), entryId: entry.id, status: "routing" });
      const taskId = await tx.createTask(this.routing, { sourceId: id, ...(home.lastRouteTaskId !== undefined && { after: home.lastRouteTaskId }) }, { conversationId: this.rootId, ownership: { kind: "conversation" } });
      home.messages.at(-1)!.taskId = taskId;
      home.lastRouteTaskId = taskId;
    });
    this.pi.harness.resume();
    return this.state.home.messages.find((message) => message.id === id)!;
  }
  private replyTarget(id: string, sessionId?: string) {
    const data = this.snapshot();
    const message = data.messages.find((item) => item.id === id);
    if (message) { const entry = data.entries.find((item) => item.id === message.entryId); return entry && { entry, sessionId: entry.sessionId, text: message.text, role: "user" }; }
    for (const entry of data.entries) { const update = entry.updates.find((item) => item.id === id); if (update) return { entry, sessionId: entry.sessionId, text: update.text, role: "assistant" }; }
    const reply = sessionId && this.state.transcript(sessionId).find((message) => message.id === id && message.replyable);
    if (reply) return { entry: undefined, sessionId, text: reply.text, role: "assistant" };
  }
  async submitSession(sessionId: string, text: string, mode: "followUp" | "steer" = "followUp", options: { replyToId?: string; editOfId?: string; id?: string; reaction?: "thumbs-up" } = {}) {
    const { replyToId, editOfId, reaction } = options;
    const id = options.id || randomUUID();
    const record = this.snapshot().sessions.find((session) => session.id === sessionId);
    if (!record) throw new Error("Conversation not found");
    if (replyToId && editOfId) throw new Error("Choose Reply or Edit");
    const referenced = replyToId || editOfId ? this.replyTarget((replyToId || editOfId)!, sessionId) : undefined;
    if (replyToId && referenced?.sessionId !== sessionId) throw new Error("Reply target is not in this conversation");
    if (reaction) {
      if (mode !== "followUp" || !replyToId || referenced?.role !== "assistant") throw new Error("React to an assistant reply");
      text = "Yes, go ahead.";
    }
    const running = this.snapshot().turns.filter(turn => turn.sessionId === sessionId && turn.status === "running");
    const active = editOfId ? running.find(turn => turn.sourceId === editOfId) : running.at(-1);
    if (editOfId && (mode !== "steer" || referenced?.role !== "user" || active?.sourceId !== editOfId)) throw new Error("This message is no longer active. Use Reply for a follow-up.");
    if (editOfId && text === referenced?.text) throw new Error("Change the message before sending a revision");
    const entryId = randomUUID();
    return this.state.change(async (home, tx) => {
      if (reaction && home.messages.some((message) => message.reaction === reaction && message.replyToId === replyToId)) return { reacted: true };
      if (home.messages.some((message) => message.id === id)) throw new Error("Request ID already exists");
      if (!home.entries.some((entry) => entry.id === entryId)) home.entries.push({ id: entryId!, sourceId: id, title: record.title, sessionId, createdAt: now(), updatedAt: now() });
      const message = JSON.parse(JSON.stringify({ id, text, mode, entryId, status: "routed", createdAt: now(), replyToId, editOfId, reaction,
        prompt: editOfId ? `Use this revision of my active request:\n${text}` : replyPrompt(text, referenced) })) as HomeMessage;
      home.messages.push(message);
      await enqueueDispatch(tx, this.dispatch, home.messages.at(-1)!, sessionId);
      return { turn: { id, sessionId, text, replyToId, status: "queued" } };
    });
  }
  async dequeue(sessionId: string, turnId: string): Promise<{ turn: Turn; message: HomeMessage; removedMessageId: string }> {
    const turn = this.snapshot().turns.find(item => item.id === turnId && item.sessionId === sessionId && item.status === "queued");
    if (!turn) throw new Error("This message has already started or is no longer queued.");
    const source = this.state.home.messages.find(item => item.id === turnId)!;
    // Abort the dispatch task before withdrawing its queued request.
    if (source.taskId !== undefined) {
      await this.pi.harness.abortTask(source.taskId as TaskId, BACKGROUND_CONTEXT);
      await this.pi.harness.waitForTask(source.taskId as TaskId, BACKGROUND_CONTEXT);
    }
    const message = await this.state.change(async (home, tx) => {
      const source = home.messages.find(item => item.id === turnId)!;
      const record = home.sessions.find(item => item.id === sessionId)!;
      const receipt = await tx.submissionByRequest(record.conversationId as ConversationId, source.requestId || source.id);
      if (receipt && receipt.status !== "queued") throw new Error("This message has already started or is no longer queued.");
      source.withdrawn = true;
      if (receipt) tx.settleSubmission(receipt.id, { status: "unanswered", reason: "withdrawn" });
      return JSON.parse(JSON.stringify(source)) as HomeMessage;
    });
    await cancelRequest(this, turnId);
    await this.state.change(home => {
      home.messages = home.messages.filter(item => item.id !== turnId);
      for (const item of home.messages) if (item.replyToId === turnId) { delete item.replyToId; item.prompt = item.text; }
      home.entries = home.entries.filter(item => item.id !== message.entryId);
    });
    return { turn, message, removedMessageId: turnId };
  }
  async steerQueued(sessionId: string, turnId: string) {
    const turn = this.snapshot().turns.find(item => item.id === turnId && item.sessionId === sessionId && item.status === "queued");
    const active = this.snapshot().turns.filter(item => item.sessionId === sessionId && item.status === "running").at(-1);
    if (!turn || !active) throw new Error("Choose a queued message and an active task to revise.");
    const { message } = await this.dequeue(sessionId, turnId);
    await this.submitSession(sessionId, message.text, "steer", { editOfId: active.sourceId });
    return { steered: true };
  }
  async stop(sessionId: string) {
    const record = this.state.home.sessions.find(item => item.id === sessionId);
    if (!record) throw new Error("Conversation not found");
    const turns = this.snapshot().turns.filter(item => item.sessionId === sessionId);
    if (!turns.length) return false;
    await this.state.change(home => { home.sessions.find(item => item.id === sessionId)!.paused = true; });
    // Drain dispatches before cancelling execution; no task can start after Stop returns.
    for (const source of requestsInSession(this, sessionId)) if (source.taskId !== undefined) {
      await this.pi.harness.abortTask(source.taskId as TaskId, BACKGROUND_CONTEXT);
      await this.pi.harness.waitForTask(source.taskId as TaskId, BACKGROUND_CONTEXT);
    }
    await Promise.all(requestsInSession(this, sessionId).map(source => cancelRequest(this, source.id)));
    await this.state.change(async (home, tx) => {
      const messages = home.messages.filter(message => home.entries.find(entry => entry.id === message.entryId)?.sessionId === sessionId);
      const receipts = await Promise.all(messages.map(message => tx.submissionByRequest(record.conversationId as ConversationId, message.requestId || message.id)));
      if (receipts.some(receipt => receipt?.status === "unanswered" && receipt.reason === "aborted")) return;
      const candidate = messages.find((message, index) => receipts[index]?.status === "queued" || (!receipts[index] && message.status === "routed"));
      if (!candidate) { home.sessions.find(item => item.id === sessionId)!.paused = false; return; }
      if (candidate.submissionId === undefined) await enqueueRequest(tx, this.work, candidate, sessionId);
      tx.settleSubmission(candidate.submissionId as SubmissionId, { status: "unanswered", reason: "aborted" });
    });
    return true;
  }
  async resume(entryId: string) {
    const entry = this.snapshot().entries.find(item => item.id === entryId);
    if (!entry?.sessionId || entry.status !== "interrupted") throw new Error("This task is not interrupted");
    const sessionId = entry.sessionId;
    const queued = new Set(this.snapshot().turns.filter(item => item.sessionId === sessionId && item.status === "queued").map(item => item.sourceId));
    await this.state.change(async (home, tx) => {
      const record = home.sessions.find(item => item.id === sessionId)!;
      record.paused = false;
      const source = home.messages.find(item => item.id === entry.interruptedSourceId)!;
      source.requestId = `${source.id}:resume:${randomUUID()}`;
      delete source.executionId;
      delete source.error;
      if (source.dependsOn === undefined) {
        delete source.submissionId;
        await enqueueDispatch(tx, this.dispatch, source, sessionId);
      } else await enqueueRequest(tx, this.work, source, sessionId);
      for (const message of home.messages) if (queued.has(message.id)) {
        if (message.submissionId === undefined) await enqueueDispatch(tx, this.dispatch, message, sessionId);
        else message.workTaskId = await tx.createTask(this.work, { sourceId: message.id, sessionId }, { conversationId: record.conversationId as ConversationId, ownership: { kind: "conversation" } });
      }
    });
    this.pi.harness.resume();
  }
  transcript(sessionId: string, view?: ConversationView) {
    const session = this.snapshot().sessions.find((session) => session.id === sessionId);
    if (!session) throw new Error("Conversation not found");
    return { session, messages: this.state.transcript(sessionId, view), queue: this.snapshot().turns.filter((turn) => turn.sessionId === sessionId),
      streaming: this.progress().filter(item => this.snapshot().turns.some(turn => turn.sourceId === item.sourceId && turn.sessionId === sessionId)).map(item => item.text).join("\n\n") };
  }
  async watchConversation(sessionId: string, send: (event: unknown) => Promise<void>) {
    const record = this.state.home.sessions.find((session) => session.id === sessionId);
    if (!record) throw new Error("Conversation not found");
    await this.state.observe(record.conversationId);
    const conversation = (await this.pi.harness.conversation(record.conversationId as ConversationId, BACKGROUND_CONTEXT))!;
    const watch = await conversation.watch(BACKGROUND_CONTEXT);
    const home = (await this.pi.harness.watchDoc(HomeDoc, BACKGROUND_CONTEXT))!;
    const publish = async (view: ConversationView) => { await send({ type: "conversation", sessionId, ...this.transcript(sessionId, view) }); };
    try {
      await publish(watch.value);
      watch.start(publish);
      home.start(async () => { await publish(watch.value); });
      return { stop: async () => { await Promise.all([watch.stop(), home.stop()]); } };
    } catch (error) { await Promise.all([watch.stop(), home.stop()]); throw error; }
  }
  async suggestion(sessionId: string, replyId: string) {
    const current = () => {
      const record = this.snapshot().sessions.find((session) => session.id === sessionId);
      if (!record) throw new Error("Conversation not found");
      if (record.status !== "idle" || this.snapshot().turns.some((turn) => turn.sessionId === sessionId)) return null;
      const messages = this.state.transcript(sessionId);
      return messages.at(-1)?.id === replyId && messages.at(-1)?.completed ? messages : null;
    };
    const messages = current();
    if (!messages) return { text: null };
    const text = await this.suggestions.get(sessionId, replyId, messages.filter((message) => message.role === "user" || message.completed));
    return { text: current() ? text : null };
  }
  shutdown() { return this.closing ||= (async () => { await this.pi.close(); await this.state.close(); this.db.close(); })(); }
}
