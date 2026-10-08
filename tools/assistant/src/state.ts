import type { AttachedReplicatedState, Draft, JsonValue } from "@earendil-works/chord";
import { BACKGROUND_CONTEXT } from "@earendil-works/chord/context";
import { defineDoc, watchEvents, type AgentEventStream, type ConversationId, type ConversationView, type DocumentState, type EntryRecord, type Harness, type LiveState, type TaskRecord, type TaskId, type SubmissionRecord, type Tx } from "@earendil-works/pi-durable";
import type { AssistantMessage } from "@earendil-works/pi-ai";

export type EntryStatus = "routing" | "queued" | "working" | "ready" | "failed" | "interrupted";
export type HomeMessage = { id: string; text: string; createdAt: string; entryId: string | null; replyToId?: string; editOfId?: string; reaction?: "thumbs-up";
  status: "routing" | "routed" | "failed"; submissionId?: number; taskId?: number; requestId?: string; mode?: "followUp" | "steer"; prompt?: string; error?: string };
export type Update = { id: string; text: string; kind: "progress" | "result" | "error"; sourceId?: string; quoteSource?: boolean; createdAt: string };
type SavedEntry = { id: string; sourceId: string; title: string; sessionId: string | null; createdAt: string; updatedAt: string };
export type HomeEntry = SavedEntry & { status: EntryStatus; interruptedText?: string; interruptedSourceId?: string; updates: Update[] };
type SavedSession = { id: string; conversationId: number; title: string; cwd: string; paused: boolean; createdAt: string };
export type SessionRecord = SavedSession & { status: "idle" | "running" | "interrupted" };
export type Turn = { id: string; sessionId: string; entryId: string | null; sourceId?: string; replyToId?: string; text: string; status: "queued" | "running"; createdAt: string };
export type Data = { messages: HomeMessage[]; entries: HomeEntry[]; sessions: SessionRecord[]; turns: Turn[] };
export type HomeData = { messages: HomeMessage[]; entries: SavedEntry[]; sessions: SavedSession[]; lastDispatchTaskId?: number };
export const HomeDoc = defineDoc<HomeData>({ kind: "assistant.home", version: 1, scope: "session", initial: () => ({ messages: [], entries: [], sessions: [] }) });
export const now = () => new Date().toISOString();
export const messageText = (message: { content?: unknown }): string => typeof message.content === "string" ? message.content : Array.isArray(message.content)
  ? message.content.flatMap((part) => part?.type === "text" && typeof part.text === "string" ? [part.text] : []).join("\n") : "";
export const assistantText = (message: { role?: string; content?: unknown }) => message.role === "assistant" ? messageText(message).replace(/\s*\(\[\]\(\)\)/g, "").trim() : "";

// Home stores presentation metadata; Durable owns transcripts, submissions, and execution state.
export class State {
  readonly harness: Harness;
  private homeState!: DocumentState<HomeData>;
  private readonly views = new Map<number, AttachedReplicatedState<ConversationView>>();
  private readonly observing = new Map<number, Promise<void>>();
  private readonly streams: AgentEventStream[] = [];
  private readonly submissions = new Map<number, SubmissionRecord>();
  // Home results survive context resets and compaction; the active transcript belongs to Pi's view.
  private readonly answers = new Map<number, EntryRecord>();
  private readonly failures = new Map<number, string>();
  private projection?: Data;
  private changed: () => void = () => {};
  constructor(harness: Harness) { this.harness = harness; }
  get home(): Readonly<HomeData> { return this.homeState.value!; }
  view(conversationId: number) { return this.views.get(conversationId)?.value; }
  live(conversationId: number): LiveState | undefined { return this.view(conversationId)?.docs["pi.live"] as LiveState | undefined; }
  async load(changed: () => void) {
    await this.change(() => {});
    this.homeState = (await this.harness.documentState(HomeDoc, BACKGROUND_CONTEXT))!;
    this.homeState.subscribe(() => { this.invalidate(); });
    const root = await this.harness.root(BACKGROUND_CONTEXT);
    await this.observe(root.id);
    await Promise.all(this.home.sessions.map((session) => this.observe(session.conversationId)));
    await this.refreshReceipts();
    this.projection = undefined;
    this.changed = changed;
  }
  private async refreshReceipts(conversationId?: number) {
    await this.harness.commit(async (tx) => {
      for (const message of this.home.messages) {
        const sessionId = this.home.entries.find((entry) => entry.id === message.entryId)?.sessionId;
        const record = this.home.sessions.find((session) => session.id === sessionId);
        if (record && (conversationId === undefined || conversationId === record.conversationId)) {
          const submission = await tx.submissionByRequest(record.conversationId as ConversationId, message.requestId || message.id);
          if (submission) {
            this.submissions.set(submission.id, submission);
            if (submission.status === "done" && submission.type === "input") {
              const answer = await tx.entry(submission.answer);
              if (answer) this.answers.set(answer.id, answer);
            }
          }
        }
        if (message.taskId !== undefined) {
          const task = await tx.task(message.taskId as TaskId);
          if (task) this.recordFailure(task);
        }
      }
    }, BACKGROUND_CONTEXT);
  }
  observe(conversationId: number): Promise<void> {
    let pending = this.observing.get(conversationId);
    if (!pending) {
      pending = (async () => {
        const conversation = (await this.harness.conversation(conversationId as ConversationId, BACKGROUND_CONTEXT))!;
        const view = await conversation.viewState(BACKGROUND_CONTEXT);
        this.views.set(conversationId, view);
        view.subscribe(() => this.invalidate());
        const stream = await watchEvents(this.harness, conversation.id, BACKGROUND_CONTEXT);
        this.streams.push(stream);
        stream.start(async (events) => {
          let changed = false;
          for (const event of events) {
            if (event.type === "snapshot") { await this.refreshReceipts(conversationId); changed = true; }
            if (event.type === "message_end" && event.entry.model?.[0]?.role === "assistant" && event.entry.model[0].stopReason !== "toolUse") this.answers.set(event.entry.id, event.entry);
            if (event.type === "submission") {
              this.submissions.set(event.record.id, event.record);
              const record = event.record;
              if (record.status === "done" && record.type === "input") {
                const answer = this.view(conversationId)?.entries.find((entry) => entry.id === record.answer);
                if (answer) this.answers.set(answer.id, answer);
              }
              changed = true;
            }
            if (event.type === "task_failed") { this.failures.set(event.taskId, event.message); changed = true; }
          }
          if (changed) this.invalidate();
        });
        this.invalidate();
      })();
      this.observing.set(conversationId, pending);
    }
    return pending;
  }
  private invalidate() {
    this.projection = undefined;
    this.changed();
  }
  private recordFailure(task: TaskRecord<JsonValue, JsonValue, JsonValue>) {
    if (task.state.status !== "terminal") return false;
    const outcome = task.state.outcome;
    if (outcome.status === "failed" || outcome.status === "faulted") this.failures.set(task.id, outcome.error.message);
    else if (outcome.status === "orphaned") this.failures.set(task.id, outcome.reason);
    else return false;
    return true;
  }
  async close() {
    await Promise.allSettled(this.observing.values());
    await Promise.all(this.streams.map((stream) => stream.stop()));
    for (const view of this.views.values()) view.dispose();
    this.homeState.dispose();
  }
  change<T>(change: (home: Draft<HomeData>, tx: Tx) => T | Promise<T>) {
    return this.harness.commit(async (tx) => change(await tx.doc(HomeDoc), tx), BACKGROUND_CONTEXT);
  }
  private submissionFor(message: HomeMessage) {
    const sessionId = this.home.entries.find((entry) => entry.id === message.entryId)?.sessionId;
    const conversationId = this.home.sessions.find((session) => session.id === sessionId)?.conversationId;
    return (message.submissionId !== undefined ? this.submissions.get(message.submissionId) : undefined) ||
      [...this.submissions.values()].find((item) => item.conversationId === conversationId && item.requestId === (message.requestId || message.id));
  }
  get data(): Data {
    if (this.projection) return this.projection;
    const sessions = this.home.sessions.map((session): SessionRecord => ({ ...session,
      status: session.paused ? "interrupted" : this.live(session.conversationId)?.run ? "running" : "idle" }));
    const turns: Turn[] = [];
    const entries = this.home.entries.map((entry): HomeEntry => {
      const messages = this.home.messages.filter((message) => message.entryId === entry.id);
      const updates = new Map<string, Update>();
      let status: EntryStatus = "routing";
      let interrupted: HomeMessage | undefined;
      for (const message of messages) {
        const submission = this.submissionFor(message);
        const error = message.error || (message.taskId !== undefined ? this.failures.get(message.taskId) : undefined);
        if (submission?.status === "queued" || submission?.status === "placed") {
          status = submission.status === "queued" ? "queued" : "working";
          turns.push({ id: message.id, sessionId: entry.sessionId!, entryId: entry.id, sourceId: message.id, replyToId: message.replyToId,
            text: message.text, status: submission.status === "queued" ? "queued" : "running", createdAt: message.createdAt });
        } else if (submission?.status === "done" && submission.type === "input") {
          status = "ready";
          const answer = this.answers.get(submission.answer);
          const text = assistantText(answer?.model?.[0] || {});
          if (text) updates.set(String(submission.answer), { id: String(submission.answer), text, kind: "result", sourceId: message.id,
            quoteSource: this.home.messages.at(-1)?.id !== message.id, createdAt: new Date((answer!.model![0] as AssistantMessage).timestamp).toISOString() });
          else {
            status = "failed";
            updates.set(`error-${message.id}`, { id: `error-${message.id}`, text: "Agent returned no final reply", kind: "error", sourceId: message.id, createdAt: message.createdAt });
          }
        } else if (submission?.status === "unanswered" || error) {
          interrupted = submission?.status === "unanswered" && submission.reason === "aborted" ? message : undefined;
          status = interrupted ? "interrupted" : "failed";
          updates.set(`error-${message.id}`, { id: `error-${message.id}`, text: interrupted ? "Stopped. You can continue this conversation." : error || (submission?.status === "unanswered" ? typeof submission.detail === "string" ? submission.detail : submission.reason : "Request failed"),
            kind: "error", sourceId: message.id, createdAt: message.createdAt });
        } else if (message.status === "routed") {
          status = "queued";
          turns.push({ id: message.id, sessionId: entry.sessionId!, entryId: entry.id, sourceId: message.id, replyToId: message.replyToId,
            text: message.text, status: "queued", createdAt: message.createdAt });
        }
      }
      const values = [...updates.values()];
      if (interrupted && sessions.find((session) => session.id === entry.sessionId)?.status === "interrupted") status = "interrupted";
      return { ...entry, status, updates: values, updatedAt: values.at(-1)?.createdAt || entry.updatedAt,
        ...(interrupted && { interruptedText: interrupted.text, interruptedSourceId: interrupted.id }) };
    });
    return this.projection = { messages: this.home.messages.map((message) => ({ ...message })), entries, sessions, turns };
  }
  transcript(sessionId: string, view?: ConversationView) {
    const record = this.home.sessions.find((session) => session.id === sessionId);
    if (!record) throw new Error("Conversation not found");
    const reactions = new Set(this.home.messages.filter((message) => message.reaction).map((message) => this.submissionFor(message)?.entry));
    return ((view || this.view(record.conversationId))?.entries || []).flatMap((entry) => {
      const message = entry.model?.[0];
      if (!message || (message.role !== "user" && message.role !== "assistant")) return [];
      const text = message.role === "assistant" ? assistantText(message) : messageText(message);
      return text.trim() ? [{ id: String(entry.id), role: message.role, text, replyable: message.role === "assistant" && message.stopReason !== "toolUse",
        completed: message.role === "assistant" && message.stopReason === "stop", ...(reactions.has(entry.id) && { reaction: "thumbs-up" as const }) }] : [];
    });
  }
}
