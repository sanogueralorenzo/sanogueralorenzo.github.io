import { resolve } from "node:path";
import { buildInstructions, buildWorkerInstructions } from "./context.js";
import type { BackendRegistry } from "./backend.js";
import { routeTurn } from "./router.js";
import { containsSecret, redactSecrets } from "../workspace/security.js";
import type { Store } from "./store.js";
import type { RuntimeConfig, RuntimeEvent, TurnRequest } from "./types.js";

export interface RunOptions {
  signal?: AbortSignal;
}

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

export class AgentRuntime {
  private readonly sessionTails = new Map<string, Promise<void>>();

  constructor(
    private readonly config: RuntimeConfig,
    private readonly store: Store,
    private readonly backends: BackendRegistry,
  ) {}

  async *run(incoming: TurnRequest, options: RunOptions = {}): AsyncGenerator<RuntimeEvent> {
    let backend;
    let terminal: RuntimeEvent;
    try {
      backend = await this.backends.resolve();
    } catch (error) {
      yield { type: "error", message: error instanceof Error ? error.message : String(error) };
      return;
    }

    const audio = incoming.attachments?.filter((attachment) => attachment.kind === "audio") ?? [];
    let text = incoming.text.trim();
    try {
      for (const attachment of audio) {
        yield { type: "status", message: "Listening…" };
        const transcript = await backend.transcribeAudio(attachment, options.signal);
        text = [text, transcript].filter(Boolean).join("\n\n");
      }
    } catch (error) {
      const interrupted = options.signal?.aborted || (error instanceof Error && error.name === "AbortError");
      yield {
        type: "error",
        message: interrupted ? "Interrupted. Your session is saved." : error instanceof Error ? error.message : String(error),
      };
      return;
    }
    if (!text) {
      yield { type: "error", message: "The message is empty." };
      return;
    }
    const request: TurnRequest = {
      ...incoming,
      text,
      ...(incoming.attachments
        ? { attachments: incoming.attachments.filter((attachment) => attachment.kind !== "audio") }
        : {}),
    };
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

    const release = await this.lockSession(session.id);
    this.store.addMessage(session.id, "user", redactSecrets(request.text));
    const runId = this.store.startRun(session.id);
    const memoryScope = route.kind === "coding" && session.cwd ? `project:${resolve(session.cwd)}` : "personal";
    const remembered = explicitMemory(request.text);
    if (remembered && !containsSecret(remembered) && !/\b(api[_ -]?key|password|secret|token)\b/i.test(remembered)) {
      this.store.remember(memoryScope, remembered, session.id);
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
      for await (const event of backend.run({
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
      this.store.finishRun(runId);
      terminal = { type: "done", sessionId: session.id };
    } catch (error) {
      const interrupted = options.signal?.aborted || (error instanceof Error && error.name === "AbortError");
      this.store.finishRun(runId);
      if (assistantText.trim()) this.store.addMessage(session.id, "assistant", `${assistantText}\n\n[interrupted]`);
      terminal = {
        type: "error",
        message: interrupted ? "Interrupted. Your session is saved." : error instanceof Error ? error.message : String(error),
      };
    } finally {
      release();
    }
    yield terminal;
  }

  private async lockSession(sessionId: string): Promise<() => void> {
    const previous = this.sessionTails.get(sessionId) ?? Promise.resolve();
    let unlock!: () => void;
    const current = new Promise<void>((resolve) => { unlock = resolve; });
    const tail = previous.then(() => current);
    this.sessionTails.set(sessionId, tail);
    await previous;
    return () => {
      unlock();
      if (this.sessionTails.get(sessionId) === tail) this.sessionTails.delete(sessionId);
    };
  }
}
