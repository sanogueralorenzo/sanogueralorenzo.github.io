import { createHash } from "node:crypto";
import { resolve } from "node:path";
import type {
  ResponseFunctionToolCall,
  ResponseInputItem,
} from "openai/resources/responses/responses";
import { buildDelegationContext, buildInstructions } from "./context.js";
import type { ModelClient } from "./model.js";
import { routeTurn } from "./router.js";
import { redactSecrets } from "./security.js";
import type { Store } from "./store.js";
import { createTools, executeTool } from "./tools.js";
import type { RuntimeConfig, RuntimeEvent, Session, TurnRequest } from "./types.js";

export interface RunOptions {
  signal?: AbortSignal;
}

function isFunctionCall(item: { type: string }): item is ResponseFunctionToolCall {
  return item.type === "function_call";
}

function scopeFor(request: TurnRequest, kind: "personal" | "coding"): string {
  if (request.channel === "telegram" && request.senderId) return `telegram:${request.senderId}`;
  if (kind === "coding" && request.cwd) return `project:${resolve(request.cwd)}`;
  return "personal:local";
}

function titleFrom(text: string): string {
  const firstLine = text.trim().split("\n", 1)[0] ?? "New conversation";
  return firstLine.length > 64 ? `${firstLine.slice(0, 61)}…` : firstLine;
}

function cacheKey(session: Session): string {
  return createHash("sha256").update(`a1r:${session.scopeKey}`).digest("hex").slice(0, 32);
}

export class A1RRuntime {
  private readonly sessionTails = new Map<string, Promise<void>>();

  constructor(
    private readonly config: RuntimeConfig,
    private readonly store: Store,
    private readonly model: ModelClient,
  ) {}

  async *run(request: TurnRequest, options: RunOptions = {}): AsyncGenerator<RuntimeEvent> {
    const explicitSession = request.sessionId ? this.store.getSession(request.sessionId) : null;
    const gatewayLinked = request.channel === "telegram" && request.senderId
      ? this.store.gatewaySession("telegram", request.senderId)
      : null;
    const priorSession = request.fresh ? null : explicitSession ?? gatewayLinked;
    const route = routeTurn(request, priorSession?.kind);
    const baseScopeKey = scopeFor(request, route.kind);
    const scopeKey = request.fresh ? `${baseScopeKey}:${Date.now()}` : baseScopeKey;
    const linked = explicitSession?.kind === route.kind
      ? explicitSession
      : gatewayLinked?.kind === route.kind
        ? gatewayLinked
        : !request.cwd && route.kind === "coding"
          ? this.store.latestSession("coding")
          : null;
    const session = this.store.resolveSession({
      ...(!request.fresh && linked?.id ? { sessionId: linked.id } : {}),
      scopeKey,
      kind: route.kind,
      ...(request.cwd ? { cwd: resolve(request.cwd) } : {}),
      title: titleFrom(request.text),
    });
    if (request.channel === "telegram" && request.senderId) {
      this.store.linkGateway("telegram", request.senderId, session.id);
    }

    const modelName = this.config.models[route.tier];
    yield { type: "session", session, route, model: modelName };

    const release = await this.lockSession(session.id);
    this.store.addMessage(session.id, "user", redactSecrets(request.text));
    const runId = this.store.startRun(session.id);
    const memoryScope = route.kind === "coding" && session.cwd ? `project:${resolve(session.cwd)}` : "personal";
    const memories = this.store.searchMemories(memoryScope, request.text);
    const instructions = buildInstructions({ session, route, memories });
    const history = this.store.getMessages(session.id, this.config.maxHistoryMessages);
    let input: ResponseInputItem[] = history
      .filter((message) => message.role !== "tool")
      .map((message) => ({
        role: message.role as "user" | "assistant",
        content: message.content,
      }));
    const tools = createTools(this.store, { allowCodeTools: route.allowTools, allowDelegation: route.allowDelegation });
    let assistantText = "";
    let lastResponseId: string | null = null;
    let lastCheckpointAt = Date.now();
    let lastCheckpointLength = 0;

    try {
      for (let round = 0; round < this.config.maxToolRounds; round += 1) {
        if (options.signal?.aborted) throw new DOMException("Interrupted", "AbortError");
        const stream = this.model.stream({
          model: modelName,
          tier: route.tier,
          instructions,
          input,
          tools: tools.map((tool) => tool.definition),
          promptCacheKey: cacheKey(session),
          ...(options.signal ? { signal: options.signal } : {}),
        });
        let response;
        let roundText = "";
        while (true) {
          const next = await stream.next();
          if (next.done) {
            response = next.value;
            break;
          }
          roundText += next.value.delta;
          assistantText += next.value.delta;
          if (assistantText.length - lastCheckpointLength >= 500 || Date.now() - lastCheckpointAt >= 1_000) {
            this.store.checkpointRun(runId, assistantText, lastResponseId ?? undefined);
            lastCheckpointAt = Date.now();
            lastCheckpointLength = assistantText.length;
          }
          yield { type: "text_delta", delta: next.value.delta };
        }
        lastResponseId = response.id;

        if (!roundText && response.output_text) {
          assistantText += response.output_text;
          yield { type: "text_delta", delta: response.output_text };
        }

        const calls = response.output.filter(isFunctionCall);
        if (calls.length === 0) {
          const finalText = assistantText || response.output_text;
          if (finalText.trim()) this.store.addMessage(session.id, "assistant", finalText);
          this.store.finishRun(runId, "complete", response.id, undefined, finalText);
          release();
          yield { type: "done", sessionId: session.id, responseId: response.id };
          return;
        }
        if (round === this.config.maxToolRounds - 1) {
          throw new Error(`Tool loop reached ${this.config.maxToolRounds} model rounds before final synthesis.`);
        }

        input = [...input, ...response.output as ResponseInputItem[]];
        const runCall = async (call: ResponseFunctionToolCall) => {
          let output: string;
          let summary: string;
          try {
            const result = await executeTool(tools, call.name, call.arguments, {
              cwd: session.cwd,
              sessionId: session.id,
              memoryScope,
              ...(options.signal ? { signal: options.signal } : {}),
              delegate: async (task) => this.model.delegate(task, `${instructions}\n\n${buildDelegationContext(session.cwd, task)}`, options.signal),
            });
            output = result.output;
            summary = result.summary;
          } catch (error) {
            output = `Tool error: ${error instanceof Error ? error.message : String(error)}`;
            summary = "tool failed";
          }
          return { call, output, summary };
        };
        const readOnlyTools = new Set(["memory_search", "read_file", "list_files", "search_files", "delegate_task"]);
        if (calls.length > 1 && calls.every((call) => readOnlyTools.has(call.name))) {
          for (const call of calls) yield { type: "tool_start", name: call.name, callId: call.call_id };
          const results = await Promise.all(calls.map(runCall));
          for (const { call, output, summary } of results) {
            this.store.addMessage(session.id, "tool", `${call.name}: ${summary}`);
            yield { type: "tool_end", name: call.name, callId: call.call_id, summary };
            input.push({ type: "function_call_output", call_id: call.call_id, output });
          }
        } else for (const call of calls) {
          yield { type: "tool_start", name: call.name, callId: call.call_id };
          const result = await runCall(call);
          this.store.addMessage(session.id, "tool", `${call.name}: ${result.summary}`);
          yield { type: "tool_end", name: call.name, callId: call.call_id, summary: result.summary };
          input.push({ type: "function_call_output", call_id: call.call_id, output: result.output });
        }
      }

      throw new Error(`Tool loop exceeded ${this.config.maxToolRounds} rounds.`);
    } catch (error) {
      const interrupted = options.signal?.aborted || (error instanceof Error && error.name === "AbortError");
      this.store.finishRun(runId, interrupted ? "interrupted" : "failed", lastResponseId ?? undefined, error instanceof Error ? error.message : String(error), assistantText);
      if (assistantText.trim()) this.store.addMessage(session.id, "assistant", `${assistantText}\n\n[interrupted]`);
      release();
      yield {
        type: "error",
        message: interrupted ? "Interrupted. Your session is saved." : error instanceof Error ? error.message : String(error),
        recoverable: true,
      };
    }
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
