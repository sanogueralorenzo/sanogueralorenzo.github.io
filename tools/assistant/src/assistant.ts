import { randomUUID } from "node:crypto";
import { mkdirSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { BACKGROUND_CONTEXT } from "@earendil-works/chord/context";
import { configure, defineTask, GenerationTask, InboxDoc, LiveDoc, UserEntry, type ConversationId, type ConversationView, type LiveState, type SubmissionId, type TaskId } from "@earendil-works/pi-durable";
import { PiService, type PiOptions } from "./pi.ts";
import { HomeRouter, type Route } from "./home-routing.ts";
import { HomeDoc, State, now, assistantText, type HomeMessage, type Turn } from "./state.ts";
import { PromptSuggestions } from "./prompt-suggestions.ts";
import { hostedSearchLabel } from "./hosted-search.ts";

type DispatchState = { phase: "route" } | { phase: "create"; route: Route } | { phase: "admit"; sessionId: string };
const clean = (text: string) => text.replace(/\x1b\[[0-?]*[ -/]*[@-~]/g, "").replace(/[\x00-\x08\x0b-\x1f\x7f]/g, "");
const errorText = (error: unknown) => error instanceof Error ? error.message : String(error);
const replyPrompt = (text: string, reply?: { role: string; text: string }) => reply
  ? `In reply to this earlier ${reply.role} message:\n> ${reply.text.slice(0, 2000).replaceAll("\n", "\n> ")}\n\n${text}` : text;
const toolLabels: Record<string, string> = { read: "Looking through files", grep: "Looking through files", find: "Looking through files", ls: "Looking through files",
  edit: "Editing files", write: "Editing files", bash: "Running a command", computer_use: "Using your computer", delegate: "Researching or reviewing" };

export class Assistant {
  readonly dataDir: string;
  readonly cwd: string;
  readonly pi: PiService;
  readonly state: State;
  readonly router: HomeRouter;
  readonly suggestions: PromptSuggestions;
  private readonly db: DatabaseSync;
  private readonly dispatch: ReturnType<typeof Assistant.dispatchTask>;
  private readonly rootId: ConversationId;
  private readonly listeners = new Set<(event: unknown) => void>();
  private readonly search = new Map<number, string>();
  private readonly finished = new Set<string>();
  private closing?: Promise<void>;
  private constructor(dataDir: string, cwd: string, pi: PiService, db: DatabaseSync, dispatch: ReturnType<typeof Assistant.dispatchTask>, rootId: ConversationId) {
    this.dataDir = dataDir; this.cwd = cwd; this.pi = pi; this.db = db; this.dispatch = dispatch; this.rootId = rootId;
    this.state = new State(pi.harness); this.router = new HomeRouter(this.state, pi, cwd);
    this.suggestions = new PromptSuggestions(Promise.resolve(pi.models), db);
  }
  static async open(dataDir: string, cwd: string, options: PiOptions = {}) {
    let app!: Assistant;
    const dispatch = Assistant.dispatchTask(() => app);
    const pi = await PiService.open(dataDir, { ...options, tasks: [...(options.tasks || []), dispatch] });
    mkdirSync(dataDir, { recursive: true, mode: 0o700 });
    const db = new DatabaseSync(join(dataDir, "suggestions.db"));
    try {
      const root = await pi.harness.root(BACKGROUND_CONTEXT);
      app = new Assistant(dataDir, cwd, pi, db, dispatch, root.id);
      await app.state.load(() => app.publish());
      for (const entry of app.snapshot().entries) for (const update of entry.updates) if (update.kind === "result") app.finished.add(update.id);
      pi.onProviderEvent = (id, data) => { const label = hostedSearchLabel(data); if (label) { app.search.set(id, label); app.publish(); } };
      for (const record of app.state.home.sessions) if (record.paused) {
        const taskId = app.state.live(record.conversationId)?.run?.taskId;
        if (taskId) { await pi.harness.abortTask(taskId, BACKGROUND_CONTEXT); await pi.harness.waitForTask(taskId, BACKGROUND_CONTEXT); }
      }
      pi.harness.resume();
      return app;
    } catch (error) { db.close(); await pi.close(); throw error; }
  }
  private static dispatchTask(getApp: () => Assistant) {
    return defineTask<{ sourceId: string; after?: number }, DispatchState, null>({ name: "assistant.dispatch", version: 1, initial: () => ({ phase: "route" }),
      phases: {
        route: async (task, runtime, context) => {
          const app = getApp();
          if (task.input.after !== undefined) {
            const previous = await runtime.getTask(task.input.after as TaskId, context);
            if (previous && previous.state.status !== "terminal") {
              await runtime.commit(() => ({ status: "waiting", checkpoint: { phase: "route" }, on: [task.input.after as TaskId], policy: "allSettled" }), context);
              return;
            }
          }
          const message = app.state.home.messages.find((item) => item.id === task.input.sourceId);
          if (!message) { await runtime.commit(() => ({ status: "terminal", outcome: { status: "completed", result: null } }), context); return; }
          try {
            const entry = app.state.home.entries.find((item) => item.id === message.entryId);
            const route: Route = entry?.sessionId ? { mode: "continue", sessionId: entry.sessionId } : await app.router.discover(message);
            await runtime.commit(() => ({ status: "running", checkpoint: { phase: "create", route: JSON.parse(JSON.stringify(route)) } }), context);
          } catch (error) {
            if (context.abortSignal?.aborted) throw error;
            await runtime.commit(async (tx) => {
              const home = await tx.doc(HomeDoc);
              const source = home.messages.find((item) => item.id === task.input.sourceId);
              if (source) { source.status = "failed"; source.error = errorText(error); }
              return { status: "terminal", outcome: { status: "failed", error: { message: errorText(error) } } };
            }, context);
          }
        },
        create: async (task, runtime, context) => {
          const app = getApp();
          await runtime.commit(async (tx) => {
            const home = await tx.doc(HomeDoc);
            const source = home.messages.find((item) => item.id === task.input.sourceId)!;
            const route = task.state.checkpoint.route;
            let session = route.mode === "continue" ? home.sessions.find((item) => item.id === route.sessionId) : undefined;
            if (!session) {
              const cwd = route.mode === "start" ? route.cwd?.trim() || homedir() : app.cwd;
              const created = await tx.createConversation({ ownership: { kind: "ownerless" } });
              await configure(tx, created.id, app.pi.agent("session", cwd));
              const record = { id: String(created.id), conversationId: created.id, title: route.mode === "start" ? clean(route.title.slice(0, 100)) : "Conversation", cwd, paused: false, createdAt: now() };
              home.sessions.push(record); session = home.sessions.at(-1)!;
            }
            let entry = home.entries.find((item) => item.id === source.entryId);
            if (!entry) {
              home.entries.push({ id: randomUUID(), sourceId: source.id, title: session.title, sessionId: session.id, createdAt: now(), updatedAt: now() });
              entry = home.entries.at(-1)!; source.entryId = entry.id;
            }
            entry.sessionId = session.id; entry.title = session.title;
            source.status = "routed";
            return { status: "running", checkpoint: { phase: "admit", sessionId: session.id } };
          }, context);
        },
        admit: async (task, runtime, context) => {
          const app = getApp();
          const message = app.state.home.messages.find((item) => item.id === task.input.sourceId);
          if (!message) { await runtime.commit(() => ({ status: "terminal", outcome: { status: "completed", result: null } }), context); return; }
          const record = app.state.home.sessions.find((item) => item.id === task.state.checkpoint.sessionId)!;
          await app.state.observe(record.conversationId);
          const conversation = (await runtime.conversation(record.conversationId as ConversationId, context))!;
          // Admission is deduplicated by the saved request ID if the process closes before the metadata commit.
          if (record.paused) {
            await runtime.commit(async (tx) => {
              const existing = await tx.submissionByRequest(record.conversationId as ConversationId, message.requestId || message.id);
              const inbox = await tx.doc(InboxDoc, record.conversationId as ConversationId);
              const queued = existing || await tx.createSubmission({ conversationId: record.conversationId as ConversationId, type: "input", status: "queued", requestId: message.requestId || message.id });
              if (!existing) inbox.items.push({ id: queued.id, mode: "followUp", content: message.prompt || message.text });
              const source = (await tx.doc(HomeDoc)).messages.find((item) => item.id === task.input.sourceId);
              if (source) { source.submissionId = queued.id; source.mode = "followUp"; }
              return { status: "terminal", outcome: { status: "completed", result: null } };
            }, context);
            return;
          }
          const submissionId = (await conversation.submit({ type: "input", content: message.prompt || message.text,
            requestId: message.requestId || message.id, whenBusy: message.mode || "followUp" }, context)).id;
          await runtime.commit(async (tx) => {
            const source = (await tx.doc(HomeDoc)).messages.find((item) => item.id === task.input.sourceId);
            if (source) source.submissionId = submissionId;
            return { status: "terminal", outcome: { status: "completed", result: null } };
          }, context);
        },
      },
      abort: async (_task, runtime, context) => { await runtime.commit(() => ({ status: "terminal", outcome: { status: "aborted" } }), context); },
    });
  }
  subscribe(listener: (event: unknown) => void) { this.listeners.add(listener); return () => this.listeners.delete(listener); }
  private emit(event: unknown) { for (const listener of this.listeners) listener(event); }
  snapshot() { return this.state.data; }
  activities() {
    return this.snapshot().turns.filter((turn) => turn.status === "running").map((turn) => {
      const record = this.state.home.sessions.find((item) => item.id === turn.sessionId)!;
      const live = this.state.live(record.conversationId);
      const message = live?.generation?.message;
      const thinking = message?.content.filter((part) => part.type === "thinking").map((part) => part.thinking).join("\n");
      const tool = live?.tools?.find((item) => item.status !== "done");
      const text = clean(this.search.get(record.conversationId) || assistantText(message || {}) || (tool && toolLabels[tool.name]) || thinking || "Working…").slice(-1200);
      return { type: "homeActivity", sourceId: turn.sourceId, text };
    });
  }
  private publish() {
    const data = this.snapshot();
    this.emit({ type: "snapshot", data });
    for (const activity of this.activities()) this.emit(activity);
    for (const record of data.sessions) if (record.status !== "running") { this.search.delete(record.conversationId); this.pi.closeComputer(record.conversationId); }
    for (const entry of data.entries) for (const update of entry.updates) if (update.kind === "result" && !this.finished.has(update.id)) {
      this.finished.add(update.id);
      const record = data.sessions.find((item) => item.id === entry.sessionId);
      if (record) void this.suggestions.get(record.id, update.id, this.state.transcript(record.id).filter((message) => message.role === "user" || message.completed)).catch(() => {});
    }
  }
  async submitHome(text: string, id: string = randomUUID()) {
    await this.state.change(async (home, tx) => {
      if (home.messages.some((message) => message.id === id)) throw new Error("Request ID already exists");
      home.entries.push({ id: randomUUID(), sourceId: id, title: "Choosing a conversation", sessionId: null, createdAt: now(), updatedAt: now() });
      const entry = home.entries.at(-1)!;
      home.messages.push({ id, text, createdAt: now(), entryId: entry.id, status: "routing" });
      const taskId = await tx.createTask(this.dispatch, { sourceId: id, ...(home.lastDispatchTaskId !== undefined && { after: home.lastDispatchTaskId }) }, { conversationId: this.rootId, ownership: { kind: "conversation" } });
      home.messages.at(-1)!.taskId = taskId;
      home.lastDispatchTaskId = taskId;
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
    const active = this.snapshot().turns.filter((turn) => turn.sessionId === sessionId && turn.status === "running").at(-1);
    if (editOfId && (mode !== "steer" || referenced?.role !== "user" || active?.sourceId !== editOfId)) throw new Error("This message is no longer active. Use Reply for a follow-up.");
    if (editOfId && text === referenced?.text) throw new Error("Change the message before sending a revision");
    const entryId = mode === "steer" && active ? active.entryId : referenced?.entry?.id || this.state.home.entries.filter((entry) => entry.sessionId === sessionId).at(-1)?.id || randomUUID();
    return this.state.change(async (home, tx) => {
      if (editOfId) {
        const source = home.messages.find((message) => message.id === editOfId);
        const live = await tx.doc(LiveDoc, record.conversationId as ConversationId);
        const submission = source && await tx.submissionByRequest(record.conversationId as ConversationId, source.requestId || source.id);
        if (!submission || !live.run?.inputs.includes(submission.id)) throw new Error("This message is no longer active. Use Reply for a follow-up.");
      }
      if (reaction && home.messages.some((message) => message.reaction === reaction && message.replyToId === replyToId)) return { reacted: true };
      if (home.messages.some((message) => message.id === id)) throw new Error("Request ID already exists");
      if (!home.entries.some((entry) => entry.id === entryId)) home.entries.push({ id: entryId!, sourceId: id, title: record.title, sessionId, createdAt: now(), updatedAt: now() });
      const message = JSON.parse(JSON.stringify({ id, text, mode, entryId, status: "routed", createdAt: now(), replyToId, editOfId, reaction,
        prompt: editOfId ? `Use this revision of my active request:\n${text}` : replyPrompt(text, referenced) })) as HomeMessage;
      home.messages.push(message);
      const taskId = await tx.createTask(this.dispatch, { sourceId: id, ...(home.lastDispatchTaskId !== undefined && { after: home.lastDispatchTaskId }) }, { conversationId: this.rootId, ownership: { kind: "conversation" } });
      home.messages.at(-1)!.taskId = taskId;
      home.lastDispatchTaskId = taskId;
      return { turn: { id, sessionId, text, replyToId, status: "queued" } };
    });
  }
  async dequeue(sessionId: string, turnId: string): Promise<{ turn: Turn; message: HomeMessage; removedMessageId: string }> {
    const turn = this.snapshot().turns.find((item) => item.id === turnId && item.sessionId === sessionId && item.status === "queued");
    if (!turn) throw new Error("This message has already started or is no longer queued.");
    const message = this.state.home.messages.find((item) => item.id === turn.sourceId)!;
    if (message.submissionId === undefined) {
      if (message.taskId) { await this.pi.harness.abortTask(message.taskId as TaskId, BACKGROUND_CONTEXT); await this.pi.harness.waitForTask(message.taskId as TaskId, BACKGROUND_CONTEXT); }
      if (this.state.home.messages.find((item) => item.id === message.id)?.submissionId !== undefined) return this.dequeue(sessionId, turnId);
    }
    return this.state.change(async (home, tx) => {
      const source = home.messages.find((item) => item.id === message.id)!;
      if (!source) throw new Error("This message has already started or is no longer queued.");
      const record = home.sessions.find((item) => item.id === sessionId)!;
      const submission = await tx.submissionByRequest(record.conversationId as ConversationId, source.requestId || source.id);
      const inbox = await tx.doc(InboxDoc, record.conversationId as ConversationId);
      if (submission) {
        if (submission.status !== "queued") throw new Error("This message has already started or is no longer queued.");
        inbox.items = inbox.items.filter((item) => item.id !== submission.id);
      }
      home.messages = home.messages.filter((item) => item.id !== source.id);
      for (const item of home.messages) if (item.replyToId === source.id) {
        delete item.replyToId; item.prompt = item.text;
        const referenced = await tx.submissionByRequest(record.conversationId as ConversationId, item.requestId || item.id);
        const queued = inbox.items.find((queued) => queued.id === referenced?.id);
        if (queued && queued.mode !== "write") queued.content = item.text;
      }
      const entry = home.entries.find((item) => item.id === source.entryId);
      const remaining = home.messages.filter((item) => item.entryId === source.entryId);
      if (entry && !remaining.length) home.entries = home.entries.filter((item) => item.id !== entry.id);
      else if (entry?.sourceId === source.id && remaining[0]) entry.sourceId = remaining[0].id;
      if (submission) tx.settleSubmission(submission.id, { status: "unanswered", reason: "aborted" });
      return { turn, message: JSON.parse(JSON.stringify(source)) as HomeMessage, removedMessageId: source.id };
    });
  }
  async steerQueued(sessionId: string, turnId: string) {
    return this.state.change(async (home, tx) => {
      const source = home.messages.find((item) => item.id === turnId);
      const record = home.sessions.find((item) => item.id === sessionId);
      if (!source || !record || home.entries.find((entry) => entry.id === source.entryId)?.sessionId !== sessionId)
        throw new Error("This message has already started or is no longer queued.");
      const submission = await tx.submissionByRequest(record.conversationId as ConversationId, source.requestId || source.id);
      if (submission && submission.status !== "queued") throw new Error("This message has already started or is no longer queued.");
      const live = await tx.doc(LiveDoc, record.conversationId as ConversationId);
      if (!live.run) throw new Error("There is no active work to steer. The message is still queued.");
      if (submission) {
        const inbox = await tx.doc(InboxDoc, record.conversationId as ConversationId);
        const item = inbox.items.find((item) => item.id === submission.id);
        if (!item || item.mode === "write") throw new Error("This message is no longer queued.");
        item.mode = "steer";
      }
      source.mode = "steer";
      const active = home.messages.filter((message) => message.submissionId !== undefined && live.run!.inputs.includes(message.submissionId as SubmissionId)).at(-1);
      if (active) source.entryId = active.entryId;
      return { steered: true };
    });
  }
  async stop(sessionId: string) {
    const record = this.state.home.sessions.find((item) => item.id === sessionId);
    if (!record) throw new Error("Conversation not found");
    const taskId = this.state.live(record.conversationId)?.run?.taskId;
    if (!taskId) return false;
    await this.state.change((home) => { home.sessions.find((item) => item.id === sessionId)!.paused = true; });
    await this.pi.harness.abortTask(taskId, BACKGROUND_CONTEXT);
    await this.pi.harness.waitForTask(taskId, BACKGROUND_CONTEXT);
    return true;
  }
  async resume(entryId: string) {
    const entry = this.snapshot().entries.find((item) => item.id === entryId);
    if (!entry?.sessionId || entry.status !== "interrupted") throw new Error("This task is not interrupted");
    await this.state.change(async (home, tx) => {
      const record = home.sessions.find((item) => item.id === entry.sessionId)!;
      const source = home.messages.find((item) => item.id === entry.interruptedSourceId)!;
      const live = await tx.doc(LiveDoc, record.conversationId as ConversationId);
      if (live.run) throw new Error("This conversation is already running");
      const requestId = `${source.id}:resume:${randomUUID()}`;
      const prompt = `Continue the interrupted request in this conversation:\n${source.text}`;
      const input = await tx.appendEntry(UserEntry, record.conversationId as ConversationId, { model: [{ role: "user", content: prompt, timestamp: Date.now() }] });
      const submission = await tx.createSubmission({ conversationId: record.conversationId as ConversationId, requestId, type: "input", status: "placed", entry: input.id });
      const taskId = await tx.createTask(GenerationTask, {}, { conversationId: record.conversationId as ConversationId, ownership: { kind: "conversation" } });
      live.run = { taskId, inputs: [submission.id] };
      record.paused = false; source.requestId = requestId; source.prompt = prompt; source.submissionId = submission.id;
      delete source.error;
    });
  }
  transcript(sessionId: string, view?: ConversationView) {
    const session = this.snapshot().sessions.find((session) => session.id === sessionId);
    if (!session) throw new Error("Conversation not found");
    const live = view ? view.docs["pi.live"] as LiveState | undefined : this.state.live(session.conversationId);
    const activity = this.activities().find((item) => this.snapshot().turns.some((turn) => turn.sourceId === item.sourceId && turn.sessionId === sessionId));
    return { session: { ...session, status: session.paused ? "interrupted" : live?.run ? "running" : "idle" }, messages: this.state.transcript(sessionId, view), queue: this.snapshot().turns.filter((turn) => turn.sessionId === sessionId),
      streaming: assistantText(live?.generation?.message || {}), activity: activity?.text || "" };
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
