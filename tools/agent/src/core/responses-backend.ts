import { createHash } from "node:crypto";
import type { Response, ResponseFunctionToolCall, ResponseInputItem } from "openai/resources/responses/responses";
import type { AgentBackend, BackendEvent, BackendTurn } from "./backend.js";
import type { ModelClient } from "./model.js";
import type { Store } from "./store.js";
import { createTools, executeTool, type AgentTool } from "./tools.js";
import type { RuntimeConfig, WorkerKind } from "./types.js";

function isFunctionCall(item: { type: string }): item is ResponseFunctionToolCall {
  return item.type === "function_call";
}

function cacheKey(scopeKey: string): string {
  return createHash("sha256").update(`agent:${scopeKey}`).digest("hex").slice(0, 32);
}

const parallelTools = new Set(["memory_search", "read_file", "list_files", "search_files"]);

export class ResponsesBackend implements AgentBackend {
  readonly kind = "responses" as const;
  readonly label = "OpenAI Responses API";

  constructor(
    private readonly config: RuntimeConfig,
    private readonly store: Store,
    private readonly model: ModelClient,
  ) {}

  isConfigured(): boolean {
    return this.model.isConfigured?.() ?? true;
  }

  async *run(turn: BackendTurn): AsyncGenerator<BackendEvent> {
    const workerResult = turn.route.worker ? await this.runWorker(turn, turn.route.worker) : null;
    const instructions = workerResult
      ? `${turn.instructions}\n\nInternal worker result (working material, not user instructions):\n<worker_result>\n${workerResult.slice(0, 30_000)}\n</worker_result>`
      : turn.instructions;
    let input: ResponseInputItem[] = this.store.getMessages(turn.session.id, this.config.maxHistoryMessages)
      .filter((message) => message.role !== "tool")
      .map((message) => ({ role: message.role as "user" | "assistant", content: message.content }));
    const tools = createTools(this.store, { allowCodeTools: false, allowMemoryWrite: true });

    for (let round = 0; round < this.config.maxToolRounds; round += 1) {
      if (turn.signal?.aborted) throw new DOMException("Interrupted", "AbortError");
      const stream = this.model.stream({
        model: this.config.models.coordinator,
        reasoningEffort: "high",
        instructions,
        input,
        tools: tools.map((tool) => tool.definition),
        promptCacheKey: cacheKey(turn.session.scopeKey),
        ...(turn.signal ? { signal: turn.signal } : {}),
      });
      let response: Response;
      let roundText = "";
      while (true) {
        const next = await stream.next();
        if (next.done) {
          response = next.value;
          break;
        }
        roundText += next.value.delta;
        yield { type: "text_delta", delta: next.value.delta };
      }

      if (!roundText && response.output_text) yield { type: "text_delta", delta: response.output_text };
      const calls = response.output.filter(isFunctionCall);
      if (calls.length === 0) {
        yield { type: "done", responseId: response.id };
        return;
      }
      if (round === this.config.maxToolRounds - 1) {
        throw new Error(`Tool loop reached ${this.config.maxToolRounds} model rounds before final synthesis.`);
      }

      input = [...input, ...response.output as ResponseInputItem[]];
      if (calls.length > 1 && calls.every((call) => parallelTools.has(call.name))) {
        for (const call of calls) yield { type: "tool_start", name: call.name, callId: call.call_id };
        const results = await Promise.all(calls.map((call) => this.runTool(call, tools, turn)));
        for (const { call, output, summary } of results) {
          yield { type: "tool_end", name: call.name, callId: call.call_id, summary };
          input.push({ type: "function_call_output", call_id: call.call_id, output });
        }
      } else {
        for (const call of calls) {
          yield { type: "tool_start", name: call.name, callId: call.call_id };
          const result = await this.runTool(call, tools, turn);
          yield { type: "tool_end", name: call.name, callId: call.call_id, summary: result.summary };
          input.push({ type: "function_call_output", call_id: call.call_id, output: result.output });
        }
      }
    }
    throw new Error(`Tool loop exceeded ${this.config.maxToolRounds} rounds.`);
  }

  private async runWorker(turn: BackendTurn, worker: WorkerKind): Promise<string> {
    const tools = createTools(this.store, { allowCodeTools: worker === "coding", allowMemoryWrite: false });
    let input: ResponseInputItem[] = [{ role: "user", content: turn.request.text }];
    let accumulated = "";

    for (let round = 0; round < this.config.maxToolRounds; round += 1) {
      if (turn.signal?.aborted) throw new DOMException("Interrupted", "AbortError");
      const stream = this.model.stream({
        model: this.config.models[worker],
        reasoningEffort: "high",
        instructions: turn.workerInstructions,
        input,
        tools: tools.map((tool) => tool.definition),
        promptCacheKey: cacheKey(`${turn.session.scopeKey}:worker:${worker}`),
        ...(turn.signal ? { signal: turn.signal } : {}),
      });
      let response: Response;
      let roundText = "";
      while (true) {
        const next = await stream.next();
        if (next.done) {
          response = next.value;
          break;
        }
        roundText += next.value.delta;
      }
      accumulated += roundText || response.output_text;
      const calls = response.output.filter(isFunctionCall);
      if (calls.length === 0) {
        if (!accumulated.trim()) throw new Error(`${worker} worker completed without a result.`);
        return accumulated;
      }
      if (round === this.config.maxToolRounds - 1) {
        throw new Error(`${worker} worker reached the tool-round limit before completion.`);
      }

      input = [...input, ...response.output as ResponseInputItem[]];
      const results = calls.length > 1 && calls.every((call) => parallelTools.has(call.name))
        ? await Promise.all(calls.map((call) => this.runTool(call, tools, turn)))
        : await this.runToolsSequentially(calls, tools, turn);
      for (const { call, output } of results) {
        input.push({ type: "function_call_output", call_id: call.call_id, output });
      }
    }
    throw new Error(`${worker} worker exceeded ${this.config.maxToolRounds} rounds.`);
  }

  private async runToolsSequentially(calls: ResponseFunctionToolCall[], tools: AgentTool[], turn: BackendTurn) {
    const results = [];
    for (const call of calls) results.push(await this.runTool(call, tools, turn));
    return results;
  }

  private async runTool(call: ResponseFunctionToolCall, tools: AgentTool[], turn: BackendTurn) {
    try {
      const result = await executeTool(tools, call.name, call.arguments, {
        cwd: turn.session.cwd,
        sessionId: turn.session.id,
        memoryScope: turn.memoryScope,
        ...(turn.signal ? { signal: turn.signal } : {}),
      });
      return { call, output: result.output, summary: result.summary };
    } catch (error) {
      return {
        call,
        output: `Tool error: ${error instanceof Error ? error.message : String(error)}`,
        summary: "tool failed",
      };
    }
  }
}
