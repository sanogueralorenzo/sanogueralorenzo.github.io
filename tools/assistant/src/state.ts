import type { Draft, JsonValue } from "@earendil-works/chord";
import { BACKGROUND_CONTEXT } from "@earendil-works/chord/context";
import { defineDoc, LiveDoc, type ConversationId, type Cursor, type EntryRecord, type Harness, type LiveState, type TaskRecord, type TaskId, type SubmissionRecord, type Tx } from "@earendil-works/pi-durable";
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
  home: Readonly<HomeData> = { messages: [], entries: [], sessions: [] };
  readonly submissions = new Map<number, SubmissionRecord>();
  readonly entries = new Map<number, EntryRecord>();
  readonly live = new Map<number, LiveState>();
  private readonly failures = new Map<number, string>();
  private projection?: Data;
  private unsubscribe = () => {};
  constructor(harness: Harness) { this.harness = harness; }
  async load(changed: (conversationIds: Set<number>) => void) {
    await this.change(() => {});
    this.home = (await this.harness.snapshot(HomeDoc, BACKGROUND_CONTEXT))!;
    await this.harness.commit(async (tx) => {
      let cursor: Cursor | undefined;
      const conversationIds: ConversationId[] = [];
      do {
        const page = await tx.scanConversations({}, 256, cursor);
        conversationIds.push(...page.items.map((item) => item.id));
        cursor = page.next;
      } while (cursor !== undefined);
      for (const conversationId of conversationIds) {
        cursor = undefined;
        do {
          const page = await tx.scanEntries({ conversationId }, 256, cursor);
          for (const entry of page.items) this.entries.set(entry.id, entry);
          cursor = page.next;
        } while (cursor !== undefined);
      }
      for (const record of this.home.sessions) {
        this.live.set(record.conversationId, JSON.parse(JSON.stringify(await tx.doc(LiveDoc, record.conversationId as ConversationId))));
        for (const message of this.home.messages.filter((item) => this.home.entries.find((entry) => entry.id === item.entryId)?.sessionId === record.id)) {
          const submission = await tx.submissionByRequest(record.conversationId as ConversationId, message.requestId || message.id);
          if (submission) this.submissions.set(submission.id, submission);
        }
      }
      for (const message of this.home.messages) if (message.taskId !== undefined) {
        const task = await tx.task(message.taskId as TaskId);
        if (task) this.recordFailure(task);
      }
    }, BACKGROUND_CONTEXT);
    this.unsubscribe = this.harness.subscribeCommits((publication) => {
      const conversationIds = new Set<number>();
      let homeChanged = false;
      for (const change of publication.changes) {
        if (change.type === "entry") { this.entries.set(change.value.id, change.value); conversationIds.add(change.value.conversationId); }
        if (change.type === "submission") { this.submissions.set(change.value.id, change.value); conversationIds.add(change.value.conversationId); }
        if (change.type === "task" && this.recordFailure(change.value) && this.home.messages.some((message) => message.taskId === change.value.id)) homeChanged = true;
        if (change.type === "document" && change.value) {
          if (change.record.kind === HomeDoc.definition.kind) { this.home = change.value as HomeData; homeChanged = true; }
          if (change.record.kind === "pi.live" && change.conversationId !== undefined) { this.live.set(change.conversationId, change.value as LiveState); conversationIds.add(change.conversationId); }
        }
      }
      this.projection = undefined;
      if (homeChanged || this.home.sessions.some((session) => conversationIds.has(session.conversationId))) changed(conversationIds);
    });
  }
  private recordFailure(task: TaskRecord<JsonValue, JsonValue, JsonValue>) {
    if (task.state.status !== "terminal") return false;
    const outcome = task.state.outcome;
    if (outcome.status === "failed" || outcome.status === "faulted") this.failures.set(task.id, outcome.error.message);
    else if (outcome.status === "orphaned") this.failures.set(task.id, outcome.reason);
    else return false;
    return true;
  }
  close() { this.unsubscribe(); }
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
      status: session.paused ? "interrupted" : this.live.get(session.conversationId)?.run ? "running" : "idle" }));
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
          const answer = this.entries.get(submission.answer);
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
  transcript(sessionId: string) {
    const record = this.home.sessions.find((session) => session.id === sessionId);
    if (!record) throw new Error("Conversation not found");
    const reactions = new Set(this.home.messages.filter((message) => message.reaction).map((message) => this.submissionFor(message)?.entry));
    return [...this.entries.values()].filter((entry) => entry.conversationId === record.conversationId).sort((a, b) => a.id - b.id).flatMap((entry) => {
      const message = entry.model?.[0];
      if (!message || (message.role !== "user" && message.role !== "assistant")) return [];
      const text = message.role === "assistant" ? assistantText(message) : messageText(message);
      return text.trim() ? [{ id: String(entry.id), role: message.role, text, replyable: message.role === "assistant" && message.stopReason !== "toolUse",
        completed: message.role === "assistant" && message.stopReason === "stop", ...(reactions.has(entry.id) && { reaction: "thumbs-up" as const }) }] : [];
    });
  }
}
