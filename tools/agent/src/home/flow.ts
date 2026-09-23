import { randomUUID } from "node:crypto";
import { failureMessage } from "../conversation/errors.js";
import type { Store } from "../conversation/store.js";
import { HOME_SESSION_ID, type HomeEntry, type RuntimeEvent, type Session, type SessionCard, type TurnRequest } from "../conversation/types.js";
import { redactSecrets } from "../workspace/security.js";
import type { HomeBackend } from "./backend.js";

export class HomeFlow {
  constructor(private readonly store: Store, private readonly backend: HomeBackend) {}

  async *dispatch(
    runId: string,
    messageId: number,
    request: TurnRequest,
    conversations: SessionCard[],
    options: {
      signal: AbortSignal | undefined;
      beforeDispatch: Promise<void> | undefined;
      steer: ((sessionId: string, text: string, channel: TurnRequest["channel"]) => Promise<boolean>) | undefined;
    },
  ): AsyncGenerator<RuntimeEvent> {
    let pendingEntryId: string | null = runId;
    try {
      const actions = await this.backend.compose(request, conversations, this.store.home.entries(), options.signal);
      await options.beforeDispatch;
      if (options.signal?.aborted) throw new DOMException("Interrupted", "AbortError");
      if (!actions.length) throw new Error("Home could not route this request. Try again.");
      for (const [index, action] of actions.entries()) {
        if (options.signal?.aborted) throw new DOMException("Interrupted", "AbortError");
        const reuseId = action.type === "start" ? undefined : action.entryId;
        const entryId = reuseId ?? (index === 0 ? runId : randomUUID());
        pendingEntryId = reuseId ? (index === 0 ? runId : null) : entryId;
        const body = redactSecrets(request.text);
        if (index > 0 && !reuseId) {
          this.store.home.createEntry(entryId, body);
          yield { type: "home_entry", entry: this.store.home.linkMessage(entryId, messageId) };
        }
        const target = action.type === "start"
          ? this.store.createSession({ title: action.title, ...(action.cwd ? { cwd: action.cwd } : {}) })
          : this.store.getSession(action.sessionId)!;
        const task = action.text?.trim();
        const dispatchedTask = !task ? "" : (actions.length > 1 || task !== request.text)
          ? [
            "Original user message (verbatim):",
            request.text,
            "",
            ...(actions.length > 1 ? [`Task assigned to this session: ${body}`, ""] : []),
            "Coordinator brief:",
            task,
            ...(actions.length > 1 ? ["", "Handle only this assigned task; other parts of the original request are routed separately."] : []),
          ].join("\n")
          : task;
        const dispatched = reuseId
          ? this.store.home.reuseEntry(index === 0 ? runId : "", entryId, target.id, body, Boolean(task), messageId)
          : this.store.home.dispatchEntry(entryId, target.id, body, Boolean(task));
        pendingEntryId = entryId;
        if (index === 0 && reuseId) yield { type: "home_entry_removed", id: runId };
        for (const entry of dispatched.superseded) yield { type: "home_entry", entry };
        yield { type: "home_entry", entry: dispatched.entry };
        if (!task) {
          yield { type: "home_entry", entry: await this.openedEntry(target) };
        } else if (action.type !== "steer" || !await options.steer?.(target.id, redactSecrets(dispatchedTask), request.channel)) {
          this.store.home.enqueueTask(target.id, redactSecrets(dispatchedTask), request.channel ?? "api", entryId);
          pendingEntryId = null;
          yield { type: "task_queued", sessionId: target.id };
        }
        pendingEntryId = null;
      }
      this.store.finishRun(runId, "complete");
      yield { type: "done", sessionId: HOME_SESSION_ID };
    } catch (error) {
      const message = failureMessage(error, options.signal);
      this.store.finishRun(runId, options.signal?.aborted ? "interrupted" : "failed", message);
      if (pendingEntryId && this.store.home.entry(pendingEntryId)) {
        yield { type: "home_entry", entry: this.store.home.failEntry(pendingEntryId, message) };
      }
      yield { type: "error", message };
    }
  }

  async taskUpdate(session: Session, runId: string, request: string, output: string, state: "complete" | "failed" | "interrupted"): Promise<HomeEntry | null> {
    if (this.store.latestRun(session.id)?.id !== runId) return null;
    if (this.store.home.queuedTask(session.id)) return this.store.home.updateEntry(session.id, "working", null);
    if (state === "interrupted") return this.store.home.updateEntry(session.id, "failed", "Interrupted. Open the task to continue.");
    let result: { state: "ready" | "needs_input" | "failed"; summary: string };
    try {
      result = await this.backend.summarize({
        title: session.title, request: redactSecrets(request), output: redactSecrets(output), state,
      });
    } catch {
      result = { state: state === "complete" ? "ready" : "failed", summary: "Update unavailable. Open task for details." };
    }
    if (this.store.latestRun(session.id)?.id !== runId) return null;
    if (this.store.home.queuedTask(session.id)) return this.store.home.updateEntry(session.id, "working", null);
    return this.store.home.updateEntry(session.id, result.state, redactSecrets(result.summary).trim());
  }

  private async openedEntry(session: Session): Promise<HomeEntry> {
    if (this.store.latestRun(session.id)?.state === "running") return this.store.home.updateEntry(session.id, "working", null)!;
    const messages = this.store.getMessages(session.id, 10);
    const answer = messages.filter((message) => message.role === "assistant").at(-1)?.content;
    if (!answer) return this.store.home.updateEntry(session.id, "ready", "Ready for your request.")!;
    try {
      const result = await this.backend.summarize({
        title: session.title,
        request: messages.filter((message) => message.role === "user").at(-1)?.content ?? "",
        output: answer,
        state: "complete",
      });
      return this.store.home.updateEntry(session.id, result.state, redactSecrets(result.summary).trim())!;
    } catch {
      return this.store.home.updateEntry(session.id, "ready", redactSecrets(answer).trim())!;
    }
  }
}
