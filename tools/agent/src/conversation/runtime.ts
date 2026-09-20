import { resolve } from "node:path";
import { buildInstructions, buildWorkerInstructions } from "./context.js";
import type { AgentBackend } from "./backend.js";
import { routeTurn } from "./router.js";
import { containsSecret, redactSecrets } from "../workspace/security.js";
import type { Store } from "./store.js";
import type { RuntimeEvent, TurnRequest } from "./types.js";

function scopeFor(request: TurnRequest, kind: "personal" | "coding"): string {
  if (kind === "coding" && request.cwd) return `project:${resolve(request.cwd)}`;
  return "personal:local";
}

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

  async *run(incoming: TurnRequest, options: { signal?: AbortSignal } = {}): AsyncGenerator<RuntimeEvent> {
    let terminal: RuntimeEvent;

    let text = incoming.text.trim();
    try {
      for (const attachment of incoming.attachments ?? []) {
        yield { type: "status", message: "Listening…" };
        const transcript = await this.backend.transcribeAudio(attachment, options.signal);
        text = [text, transcript].filter(Boolean).join("\n\n");
      }
    } catch (error) {
      yield { type: "error", message: failureMessage(error, options.signal) };
      return;
    }
    if (!text) {
      yield { type: "error", message: "The message is empty." };
      return;
    }
    const request: TurnRequest = { ...incoming, text };
    const explicitSession = request.sessionId ? this.store.getSession(request.sessionId) : null;
    const priorSession = request.fresh ? null : explicitSession ?? this.store.listSessions(1)[0];
    const route = routeTurn(request, priorSession?.kind);
    const baseScopeKey = scopeFor(request, route.kind);
    const scopeKey = request.fresh ? `${baseScopeKey}:${Date.now()}` : baseScopeKey;
    const candidate = explicitSession ?? (!request.cwd ? this.store.latestSession(route.kind) : null);
    const linked = candidate?.kind === route.kind ? candidate : null;
    const session = this.store.resolveSession({
      ...(!request.fresh && linked?.id ? { sessionId: linked.id } : {}),
      scopeKey,
      kind: route.kind,
      ...(request.cwd ? { cwd: resolve(request.cwd) } : {}),
      title: titleFrom(request.text),
    });
    yield { type: "session", session };

    this.store.addMessage(session.id, "user", redactSecrets(request.text));
    const runId = this.store.startRun(session.id);
    const memoryScope = route.kind === "coding" && session.cwd ? `project:${resolve(session.cwd)}` : "personal";
    const remembered = explicitMemory(request.text);
    if (remembered && !containsSecret(remembered) && !/\b(api[_ -]?key|password|secret|token)\b/i.test(remembered)) {
      this.store.remember(memoryScope, remembered);
    }
    const memories = this.store.searchMemories(memoryScope, request.text);
    const instructions = buildInstructions({ session, route, memories });
    const workerInstructions = route.worker
      ? buildWorkerInstructions({ session, route, memories, worker: route.worker })
      : instructions;
    let assistantText = "";
    let lastCheckpointAt = Date.now();
    let lastCheckpointLength = 0;

    try {
      for await (const event of this.backend.run({
        request,
        session,
        route,
        instructions,
        workerInstructions,
        memoryScope,
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
      if (assistantText.trim()) this.store.addMessage(session.id, "assistant", assistantText);
      terminal = { type: "done", sessionId: session.id };
    } catch (error) {
      if (assistantText.trim()) this.store.addMessage(session.id, "assistant", `${assistantText}\n\n[interrupted]`);
      terminal = { type: "error", message: failureMessage(error, options.signal) };
    } finally {
      this.store.finishRun(runId);
    }
    yield terminal;
  }
}
