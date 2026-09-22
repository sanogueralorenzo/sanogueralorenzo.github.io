import { basename, resolve } from "node:path";
import { buildInstructions } from "./instructions.js";
import type { AgentBackend } from "./backend.js";
import { containsSecret, redactSecrets } from "../workspace/security.js";
import type { Store } from "./store.js";
import type { RuntimeEvent, Session, SessionCard, TurnRequest } from "./types.js";
import { maySwitchContext } from "./routing.js";

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
    return this.store.latestSession(cwd) ?? this.store.createSession(cwd ? { cwd } : {});
  }

  openTelegramSession(ownerId: string, options: { fresh?: boolean; sessionId?: string } = {}): Session {
    const bound = this.store.telegramSession(ownerId);
    const session = options.sessionId
      ? this.openSession({ preferredSessionId: options.sessionId })
      : options.fresh ? this.openSession({ fresh: true })
      : this.openSession(bound ? { preferredSessionId: bound } : {});
    this.store.bindTelegramSession(ownerId, session.id);
    return session;
  }

  prepareTurn(incoming: TurnRequest): { session: Session; sessionTools: SessionCard[]; empty: boolean; routing: boolean } {
    const requested = incoming.sessionId ? this.store.getSession(incoming.sessionId) : null;
    if (incoming.sessionId && !requested) throw new Error("Conversation not found.");
    const selected = requested ?? this.openSession(incoming);
    const session = incoming.cwd && !selected.cwd
      ? this.store.setSessionWorkspace(selected.id, resolve(incoming.cwd))
      : selected;
    const empty = this.store.getMessages(session.id, 1).length === 0;
    return {
      session, empty, routing: maySwitchContext(incoming.text) || Boolean(incoming.attachments?.length),
      sessionTools: this.store.sessionCards().filter((card) => card.id !== session.id),
    };
  }

  async *run(incoming: TurnRequest, options: {
    signal?: AbortSignal;
    runId?: string;
    prepared?: ReturnType<AgentRuntime["prepareTurn"]>;
    canHandoff?: (sessionId: string) => void;
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
      return;
    }
    if (!text) {
      if (prepared.routing) yield { type: "turn", text: "Voice message", channel: incoming.channel ?? "api", hasAttachments: Boolean(incoming.attachments?.length) };
      this.store.finishRun(runId, "failed", "The message is empty.");
      yield { type: "error", message: "The message is empty." };
      return;
    }
    const request: TurnRequest = { ...incoming, text };
    this.store.stageRunInput(runId, redactSecrets(request.text));
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
      return;
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
      this.store.finishRun(runId, terminal?.type === "done" ? "complete" : options.signal?.aborted || !terminal ? "interrupted" : "failed", assistantMessage);
    }
    if (terminal) yield terminal;
  }
}
