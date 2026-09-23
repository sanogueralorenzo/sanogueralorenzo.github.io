import { basename, resolve } from "node:path";
import { buildInstructions } from "./instructions.js";
import { failureMessage } from "./errors.js";
import type { AgentBackend } from "./backend.js";
import { containsSecret, redactSecrets } from "../workspace/security.js";
import type { Store } from "./store.js";
import type { RuntimeEvent, Session, SessionCard, TurnRequest } from "./types.js";
import { maySwitchContext } from "./routing.js";
import { HOME_SESSION_ID } from "./types.js";
import type { HomeBackend } from "../home/backend.js";
import { HomeFlow } from "../home/flow.js";

function titleFrom(text: string): string {
  const firstLine = text.trim().split("\n", 1)[0] ?? "New conversation";
  return firstLine.length > 64 ? `${firstLine.slice(0, 61)}…` : firstLine;
}

function explicitMemory(text: string): string | null {
  const match = text.trim().match(/^(?:please\s+)?remember(?:\s+that)?\s+(.{3,500})[.!]?$/i);
  return match?.[1]?.trim() ?? null;
}

export class AgentRuntime {
  private readonly homeFlow: HomeFlow;

  constructor(
    private readonly store: Store,
    private readonly backend: AgentBackend,
    home: HomeBackend,
  ) {
    this.homeFlow = new HomeFlow(store, home);
  }

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

  async steer(sessionId: string, text: string): Promise<boolean> {
    return this.backend.steer(sessionId, redactSecrets(text));
  }

  prepareTurn(incoming: TurnRequest): { session: Session; sessionTools: SessionCard[]; empty: boolean; deferTurn: boolean } {
    const requested = incoming.sessionId ? this.store.getSession(incoming.sessionId) : null;
    if (incoming.sessionId && !requested) throw new Error("Conversation not found.");
    const selected = requested ?? this.openSession(incoming);
    const empty = this.store.getMessages(selected.id, 1).length === 0;
    return {
      session: selected, empty, deferTurn: selected.id !== HOME_SESSION_ID && (maySwitchContext(incoming.text) || Boolean(incoming.attachments?.length)),
      sessionTools: this.store.sessionCards().filter((card) => card.id !== selected.id),
    };
  }

  async *run(incoming: TurnRequest, options: {
    signal?: AbortSignal;
    runId?: string;
    prepared?: ReturnType<AgentRuntime["prepareTurn"]>;
    canHandoff?: (sessionId: string) => void;
    beforeHomeDispatch?: Promise<void>;
    steer?: (sessionId: string, text: string, channel: TurnRequest["channel"]) => Promise<boolean>;
  } = {}): AsyncGenerator<RuntimeEvent> {
    let terminal: RuntimeEvent | null = null;
    let text = incoming.text.trim();
    const prepared = options.prepared ?? this.prepareTurn(incoming);
    const sessionTools = prepared.sessionTools;
    let session = prepared.session;
    const runId = this.store.startRun(session.id, options.runId, redactSecrets(text || "Voice message"), incoming.queuedTaskId);
    if (session.id === HOME_SESSION_ID) yield { type: "home_entry", entry: this.store.home.createEntry(runId, redactSecrets(text || "Voice message")) };
    if (incoming.queuedTaskId) {
      const entry = this.store.home.updateEntry(session.id, "working", null);
      if (entry) yield { type: "home_entry", entry };
    }
    try {
      for (const attachment of incoming.attachments ?? []) {
        yield { type: "status", message: "Listening…" };
        const transcript = await this.backend.transcribeAudio(attachment, options.signal);
        text = [text, transcript].filter(Boolean).join("\n\n");
      }
    } catch (error) {
      const message = failureMessage(error, options.signal);
      if (prepared.deferTurn) yield { type: "turn", text: text || "Voice message", channel: incoming.channel ?? "api", hasAttachments: Boolean(incoming.attachments?.length) };
      this.store.finishRun(runId, message === "Interrupted. Your session is saved." ? "interrupted" : "failed", message);
      yield { type: "error", message };
      if (this.store.home.hasEntry(session.id)) {
        const entry = await this.homeFlow.taskUpdate(session, runId, text, message, message === "Interrupted. Your session is saved." ? "interrupted" : "failed");
        if (entry) yield { type: "home_entry", entry };
      }
      return;
    }
    if (!text) {
      if (prepared.deferTurn) yield { type: "turn", text: "Voice message", channel: incoming.channel ?? "api", hasAttachments: Boolean(incoming.attachments?.length) };
      this.store.finishRun(runId, "failed", "The message is empty.");
      yield { type: "error", message: "The message is empty." };
      if (this.store.home.hasEntry(session.id)) {
        const entry = await this.homeFlow.taskUpdate(session, runId, text, "The message is empty.", "failed");
        if (entry) yield { type: "home_entry", entry };
      }
      return;
    }
    const request: TurnRequest = { ...incoming, text };
    this.store.stageRunInput(runId, redactSecrets(request.text));
    if (session.id === HOME_SESSION_ID) {
      const messageId = this.store.deliverRunInput(runId)!;
      yield { type: "home_entry", entry: this.store.home.linkMessage(runId, messageId) };
      yield* this.homeFlow.dispatch(runId, messageId, request, sessionTools, {
        signal: options.signal,
        beforeDispatch: options.beforeHomeDispatch,
        steer: options.steer,
      });
      return;
    }
    let handoffTask: string | null = null;
    let sourceContext = "";
    try {
      const handoff = maySwitchContext(request.text) ? await this.backend.route({
        request, session, sessionTools,
        ...(options.signal ? { signal: options.signal } : {}),
      }) : null;
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
      if (prepared.deferTurn && session.id === prepared.session.id) {
        yield { type: "turn", text: request.text, channel: incoming.channel ?? "api", hasAttachments: Boolean(incoming.attachments?.length) };
      }
      this.store.finishRun(runId, message === "Interrupted. Your session is saved." ? "interrupted" : "failed", message);
      yield { type: "error", message };
      if (this.store.home.hasEntry(session.id)) {
        const entry = await this.homeFlow.taskUpdate(session, runId, text, message, message === "Interrupted. Your session is saved." ? "interrupted" : "failed");
        if (entry) yield { type: "home_entry", entry };
      }
      return;
    }
    if (session.id === prepared.session.id && incoming.cwd && !session.cwd) {
      session = this.store.setSessionWorkspace(session.id, resolve(incoming.cwd));
    }
    if (session.title === "New conversation") session = this.store.renameSession(session.id, titleFrom(handoffTask ?? text));
    yield { type: "session", session };
    const messageId = this.store.deliverRunInput(runId);
    if (messageId && !incoming.homeEntryId) {
      const entry = this.store.home.linkLatestMessage(session.id, messageId);
      if (entry) yield { type: "home_entry", entry };
    }
    if (prepared.deferTurn) yield { type: "turn", text: request.text, channel: incoming.channel ?? "api", hasAttachments: Boolean(incoming.attachments?.length) };
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
      if (terminal?.type === "error" && !assistantMessage && this.store.home.hasEntry(session.id)) assistantMessage = terminal.message;
      this.store.finishRun(runId, terminal?.type === "done" ? "complete" : options.signal?.aborted || !terminal ? "interrupted" : "failed", assistantMessage);
    }
    if (terminal) yield terminal;
    if (terminal && this.store.home.hasEntry(session.id)) {
      const entry = await this.homeFlow.taskUpdate(
        session, runId, request.text, assistantMessage ?? (terminal.type === "error" ? terminal.message : ""),
        terminal.type === "done" ? "complete" : options.signal?.aborted ? "interrupted" : "failed",
      );
      if (entry) yield { type: "home_entry", entry };
    }
  }
}
