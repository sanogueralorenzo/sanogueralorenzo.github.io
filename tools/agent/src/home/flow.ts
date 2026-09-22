import { failureMessage } from "../conversation/errors.js";
import type { Store } from "../conversation/store.js";
import { HOME_SESSION_ID, type HomeEntry, type RuntimeEvent, type Session, type SessionCard, type TurnRequest } from "../conversation/types.js";
import { redactSecrets } from "../workspace/security.js";
import type { HomeBackend } from "./backend.js";

export class HomeFlow {
  constructor(private readonly store: Store, private readonly backend: HomeBackend) {}

  async *dispatch(
    runId: string,
    request: TurnRequest,
    conversations: SessionCard[],
    options: {
      signal: AbortSignal | undefined;
      beforeDispatch: Promise<void> | undefined;
      steer: ((sessionId: string, text: string, channel: TurnRequest["channel"]) => Promise<boolean>) | undefined;
    },
  ): AsyncGenerator<RuntimeEvent> {
    try {
      const action = await this.backend.compose(request, conversations, this.store.homeEntries(), options.signal);
      await options.beforeDispatch;
      if (options.signal?.aborted) throw new DOMException("Interrupted", "AbortError");
      const target = action.type === "start"
        ? this.store.createSession({ title: action.title, ...(action.cwd ? { cwd: action.cwd } : {}) })
        : this.store.getSession(action.sessionId)!;
      const task = action.text?.trim();
      const dispatched = this.store.dispatchHomeEntry(runId, target.id, action.title, redactSecrets(request.text), Boolean(task));
      for (const entry of dispatched.superseded) yield { type: "home_entry", entry };
      yield { type: "home_entry", entry: dispatched.entry };
      if (!task) {
        yield { type: "home_entry", entry: await this.openedEntry(target) };
      } else if (action.type !== "steer" || !await options.steer?.(target.id, redactSecrets(task), request.channel)) {
        this.store.enqueueTask(target.id, redactSecrets(task), request.channel ?? "api");
        yield { type: "task_queued", sessionId: target.id };
      }
      this.store.finishRun(runId, "complete");
      yield { type: "done", sessionId: HOME_SESSION_ID };
    } catch (error) {
      const message = failureMessage(error, options.signal);
      this.store.finishRun(runId, options.signal?.aborted ? "interrupted" : "failed", message);
      yield { type: "home_entry", entry: this.store.failHomeEntry(runId, message) };
      yield { type: "error", message };
    }
  }

  async taskUpdate(session: Session, runId: string, request: string, output: string, state: "complete" | "failed" | "interrupted"): Promise<HomeEntry | null> {
    if (this.store.latestRun(session.id)?.id !== runId) return null;
    if (this.store.queuedTask(session.id)) return this.store.updateHomeEntry(session.id, "working", null);
    if (state === "interrupted") return this.store.updateHomeEntry(session.id, "failed", "Interrupted. Open the task to continue.");
    let result: { state: "ready" | "needs_input" | "failed"; summary: string };
    try {
      result = await this.backend.summarize({
        title: session.title, request: redactSecrets(request), output: redactSecrets(output), state,
      });
    } catch {
      result = { state: state === "complete" ? "ready" : "failed", summary: "Update unavailable. Open task for details." };
    }
    if (this.store.latestRun(session.id)?.id !== runId) return null;
    if (this.store.queuedTask(session.id)) return this.store.updateHomeEntry(session.id, "working", null);
    return this.store.updateHomeEntry(session.id, result.state,
      redactSecrets(result.summary).trim().replace(/\s+/g, " ").split(" ").slice(0, 12).join(" "));
  }

  private async openedEntry(session: Session): Promise<HomeEntry> {
    if (this.store.latestRun(session.id)?.state === "running") return this.store.updateHomeEntry(session.id, "working", null)!;
    const messages = this.store.getMessages(session.id, 10);
    const answer = messages.filter((message) => message.role === "assistant").at(-1)?.content;
    if (!answer) return this.store.updateHomeEntry(session.id, "ready", "Ready for your request.")!;
    try {
      const result = await this.backend.summarize({
        title: session.title,
        request: messages.filter((message) => message.role === "user").at(-1)?.content ?? "",
        output: answer,
        state: "complete",
      });
      return this.store.updateHomeEntry(session.id, result.state, redactSecrets(result.summary))!;
    } catch {
      return this.store.updateHomeEntry(session.id, "ready", redactSecrets(answer).trim().replace(/\s+/g, " ").split(" ").slice(0, 12).join(" "))!;
    }
  }
}
