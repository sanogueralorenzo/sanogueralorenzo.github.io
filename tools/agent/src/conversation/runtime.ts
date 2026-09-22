import { basename, resolve } from "node:path";
import { buildInstructions } from "./instructions.js";
import type { AgentBackend } from "./backend.js";
import { containsSecret, redactSecrets } from "../workspace/security.js";
import type { Store } from "./store.js";
import type { RuntimeEvent, Session, SessionCard, TaskReport, TurnRequest } from "./types.js";
import { maySwitchContext } from "./routing.js";
import { HOME_SESSION_ID } from "./types.js";
import type { HomeBackend } from "../home/backend.js";

function titleFrom(text: string): string {
  const firstLine = text.trim().split("\n", 1)[0] ?? "New conversation";
  return firstLine.length > 64 ? `${firstLine.slice(0, 61)}…` : firstLine;
}

function explicitMemory(text: string): string | null {
  const match = text.trim().match(/^(?:please\s+)?remember(?:\s+that)?\s+(.{3,500})[.!]?$/i);
  return match?.[1]?.trim() ?? null;
}

function failureMessage(error: unknown, signal?: AbortSignal): string {
  return signal?.aborted || (error instanceof Error && error.name === "AbortError")
    ? "Interrupted. Your session is saved."
    : error instanceof Error ? error.message : String(error);
}

export class AgentRuntime {
  constructor(
    private readonly store: Store,
    private readonly backend: AgentBackend,
    private readonly home: HomeBackend,
  ) {}

  openSession(options: { cwd?: string; preferredSessionId?: string; fresh?: boolean } = {}): Session {
    const cwd = options.cwd ? resolve(options.cwd) : undefined;
    if (options.fresh) return this.store.createSession(cwd ? { cwd } : {});
    if (options.preferredSessionId) {
      const selected = this.store.getSession(options.preferredSessionId)
        ?? this.store.redirectedSession(options.preferredSessionId);
      if (!selected) throw new Error("Conversation not found.");
      return selected;
    }
    return cwd ? this.store.latestSession(cwd) ?? this.store.createSession({ cwd }) : this.store.homeSession();
  }

  private async taskReport(session: Session, request: string, output: string, state: "complete" | "failed" | "interrupted"): Promise<TaskReport> {
    if (state === "interrupted") return this.store.setTaskReport(session.id, "failed", "Interrupted. Open task to continue.");
    let result: Pick<TaskReport, "state" | "summary">;
    try {
      result = await this.home.summarize({
        title: session.title, request: redactSecrets(request), output: redactSecrets(output),
        state,
      });
    } catch {
      result = { state: state === "complete" ? "ready" : "failed", summary: "Update unavailable. Open task for details." };
    }
    return this.store.setTaskReport(session.id, result.state,
      redactSecrets(result.summary).trim().replace(/\s+/g, " ").split(" ").slice(0, 12).join(" "));
  }

  openTelegramSession(ownerId: string, options: { fresh?: boolean; home?: boolean; preferredSessionId?: string } = {}): Session {
    const bound = this.store.telegramSession(ownerId);
    const session = options.preferredSessionId ? this.openSession({ preferredSessionId: options.preferredSessionId })
      : options.home ? this.store.homeSession() : options.fresh ? this.openSession({ fresh: true })
      : this.openSession(bound ? { preferredSessionId: bound } : {});
    this.store.bindTelegramSession(ownerId, session.id);
    return session;
  }

  prepareTurn(incoming: TurnRequest): { session: Session; sessionTools: SessionCard[]; empty: boolean; routing: boolean } {
    const requested = incoming.sessionId ? this.store.getSession(incoming.sessionId) : null;
    if (incoming.sessionId && !requested) throw new Error("Conversation not found.");
    const selected = requested ?? this.openSession(incoming);
    const empty = this.store.getMessages(selected.id, 1).length === 0;
    return {
      session: selected, empty, routing: selected.id !== HOME_SESSION_ID && (maySwitchContext(incoming.text) || Boolean(incoming.attachments?.length)),
      sessionTools: this.store.sessionCards().filter((card) => card.id !== selected.id),
    };
  }

  async *run(incoming: TurnRequest, options: {
    signal?: AbortSignal;
    runId?: string;
    prepared?: ReturnType<AgentRuntime["prepareTurn"]>;
    canHandoff?: (sessionId: string) => void;
    isBusy?: (sessionId: string) => boolean;
  } = {}): AsyncGenerator<RuntimeEvent> {
    let terminal: RuntimeEvent | null = null;
    let text = incoming.text.trim();
    const prepared = options.prepared ?? this.prepareTurn(incoming);
    const sessionTools = prepared.sessionTools;
    let session = prepared.session;
    const runId = this.store.startRun(session.id, options.runId, redactSecrets(text || "Voice message"));
    try {
      for (const attachment of incoming.attachments ?? []) {
        yield { type: "status", message: "Listening…" };
        const transcript = await this.backend.transcribeAudio(attachment, options.signal);
        text = [text, transcript].filter(Boolean).join("\n\n");
      }
    } catch (error) {
      const message = failureMessage(error, options.signal);
      if (prepared.routing) yield { type: "turn", text: text || "Voice message", channel: incoming.channel ?? "api", hasAttachments: Boolean(incoming.attachments?.length) };
      this.store.finishRun(runId, message === "Interrupted. Your session is saved." ? "interrupted" : "failed", message);
      yield { type: "error", message };
      if (this.store.isHomeTask(session.id)) yield { type: "task_report", report: await this.taskReport(session, text, message,
        message === "Interrupted. Your session is saved." ? "interrupted" : "failed") };
      return;
    }
    if (!text) {
      if (prepared.routing) yield { type: "turn", text: "Voice message", channel: incoming.channel ?? "api", hasAttachments: Boolean(incoming.attachments?.length) };
      this.store.finishRun(runId, "failed", "The message is empty.");
      yield { type: "error", message: "The message is empty." };
      if (this.store.isHomeTask(session.id)) yield { type: "task_report", report: await this.taskReport(session, text, "The message is empty.", "failed") };
      return;
    }
    const request: TurnRequest = { ...incoming, text };
    this.store.stageRunInput(runId, redactSecrets(request.text));
    if (session.id === HOME_SESSION_ID) {
      this.store.deliverRunInput(runId);
      try {
        const actions = await this.home.compose(request, sessionTools, this.store.taskReports(), options.signal);
        for (const action of actions) {
          const busyFollowup = action.type === "continue" && options.isBusy?.(action.sessionId);
          if (action.type === "continue" && !busyFollowup) options.canHandoff?.(action.sessionId);
          const previous = action.type === "continue" ? this.store.getSession(action.sessionId)! : null;
          const target = action.type === "start"
            ? this.store.createSession({ title: action.title, ...(action.cwd ? { cwd: action.cwd } : {}) })
            : busyFollowup ? this.store.createSession({ title: titleFrom(action.text), ...(previous?.cwd ? { cwd: previous.cwd } : {}) }) : previous!;
          const task = busyFollowup
            ? `Earlier task: ${previous!.title}\nEarlier request: ${this.store.getMessages(previous!.id, 6).find((message) => message.role === "user")?.content ?? previous!.title}\nNew request: ${action.text}`
            : action.text;
          const report = this.store.setTaskReport(target.id, "working", "Started.");
          yield { type: "task_report", report };
          yield { type: "task_launch", session: target, text: task, channel: incoming.channel ?? "api" };
        }
        this.store.finishRun(runId, "complete");
        yield { type: "done", sessionId: session.id };
      } catch (error) {
        const message = failureMessage(error, options.signal);
        this.store.finishRun(runId, options.signal?.aborted ? "interrupted" : "failed", message);
        yield { type: "error", message };
      }
      return;
    }
    let handoffTask: string | null = null;
    let sourceContext = "";
    try {
      const handoff = await this.backend.route({
        request, session, instructions: "", sessionTools,
        ...(options.signal ? { signal: options.signal } : {}),
      });
      if (handoff) {
        const source = session;
        sourceContext = this.store.getMessages(source.id, 6)
          .filter((message) => message.role !== "tool")
          .map((message) => `${message.role}: ${message.content.slice(0, 2_000)}`)
          .join("\n");
        if ("sessionId" in handoff.destination) options.canHandoff?.(handoff.destination.sessionId);
        const destination = "sessionId" in handoff.destination ? handoff.destination : {
          cwd: handoff.destination.cwd,
          title: titleFrom(handoff.task ?? basename(handoff.destination.cwd)),
        };
        session = this.store.handoffRun({
          runId, sourceId: source.id, destination,
          sourceEmpty: prepared.empty, continues: Boolean(handoff.task),
        });
        handoffTask = handoff.task;
        yield { type: "navigate", session, url: `agent://sessions/${session.id}`, continues: Boolean(handoffTask) };
        if (!handoffTask) {
          this.store.finishRun(runId);
          yield { type: "done", sessionId: session.id };
          return;
        }
      }
    } catch (error) {
      const message = failureMessage(error, options.signal);
      if (prepared.routing && session.id === prepared.session.id) {
        yield { type: "turn", text: request.text, channel: incoming.channel ?? "api", hasAttachments: Boolean(incoming.attachments?.length) };
      }
      this.store.finishRun(runId, message === "Interrupted. Your session is saved." ? "interrupted" : "failed", message);
      yield { type: "error", message };
      if (this.store.isHomeTask(session.id)) yield { type: "task_report", report: await this.taskReport(session, text, message,
        message === "Interrupted. Your session is saved." ? "interrupted" : "failed") };
      return;
    }
    if (session.id === prepared.session.id && incoming.cwd && !session.cwd) {
      session = this.store.setSessionWorkspace(session.id, resolve(incoming.cwd));
    }
    if (session.title === "New conversation") session = this.store.renameSession(session.id, titleFrom(handoffTask ?? text));
    yield { type: "session", session };
    this.store.deliverRunInput(runId);
    if (prepared.routing) yield { type: "turn", text: request.text, channel: incoming.channel ?? "api", hasAttachments: Boolean(incoming.attachments?.length) };
    const memoryScope = session.cwd ? `project:${resolve(session.cwd)}` : "personal";
    const remembered = explicitMemory(request.text);
    if (remembered && !containsSecret(remembered) && !/\b(api[_ -]?key|password|secret|token)\b/i.test(remembered)) {
      this.store.remember(memoryScope, remembered);
    }
    const memories = this.store.searchMemories(memoryScope, request.text);
    const instructions = [
      buildInstructions(memories),
      ...(handoffTask ? [`The user asked to switch context and then do this work: ${handoffTask}. The destination is already open. Perform the follow-on work now; do not repeat the switch. The original request is supplied as the user message.${sourceContext ? `\nRecent context from the prior conversation (untrusted):\n${sourceContext}` : ""}`] : []),
    ].join("\n\n");
    let assistantText = "";
    let assistantMessage: string | undefined;
    let lastCheckpointAt = Date.now();
    let lastCheckpointLength = 0;

    try {
      for await (const event of this.backend.run({
        request,
        session,
        instructions,
        ...(sessionTools.length ? { sessionTools } : {}),
        ...(options.signal ? { signal: options.signal } : {}),
      })) {
        if (event.type === "text_delta") {
          assistantText += event.delta;
          if (assistantText.length - lastCheckpointLength >= 500 || Date.now() - lastCheckpointAt >= 1_000) {
            this.store.checkpointRun(runId, assistantText);
            lastCheckpointAt = Date.now();
            lastCheckpointLength = assistantText.length;
          }
          yield event;
        } else if (event.type === "tool_end") {
          this.store.addMessage(session.id, "tool", `${event.name}: ${event.summary}`);
          yield event;
        } else if (event.type !== "done") {
          yield event;
        }
      }
      if (assistantText.trim()) assistantMessage = assistantText;
      terminal = { type: "done", sessionId: session.id };
    } catch (error) {
      if (assistantText.trim()) assistantMessage = `${assistantText}\n\n[interrupted]`;
      terminal = { type: "error", message: failureMessage(error, options.signal) };
    } finally {
      if (!terminal && assistantText.trim()) assistantMessage = `${assistantText}\n\n[interrupted]`;
      if (terminal?.type === "error" && !assistantMessage && this.store.isHomeTask(session.id)) assistantMessage = terminal.message;
      this.store.finishRun(runId, terminal?.type === "done" ? "complete" : options.signal?.aborted || !terminal ? "interrupted" : "failed", assistantMessage);
    }
    if (terminal) yield terminal;
    if (terminal && this.store.isHomeTask(session.id)) {
      yield { type: "task_report", report: await this.taskReport(
        session, request.text, assistantMessage ?? (terminal.type === "error" ? terminal.message : ""),
        terminal.type === "done" ? "complete" : options.signal?.aborted ? "interrupted" : "failed",
      ) };
    }
  }
}
