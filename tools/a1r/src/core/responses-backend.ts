import type {
  Response,
  ResponseFunctionToolCall,
  ResponseInputItem,
} from "openai/resources/responses/responses";
import { createHash } from "node:crypto";
import { buildDelegationContext } from "./context.js";
import type { AgentBackend, BackendEvent, BackendTurn } from "./backend.js";
import type { ModelClient } from "./model.js";
import type { Store } from "./store.js";
import { createTools, executeTool } from "./tools.js";
import type { RuntimeConfig } from "./types.js";

function isFunctionCall(item: { type: string }): item is ResponseFunctionToolCall {
  return item.type === "function_call";
}

function cacheKey(scopeKey: string): string {
  return createHash("sha256").update(`a1r:${scopeKey}`).digest("hex").slice(0, 32);
}

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
    const modelName = this.config.models[turn.route.tier];
    let input: ResponseInputItem[] = this.store.getMessages(turn.session.id, this.config.maxHistoryMessages)
      .filter((message) => message.role !== "tool")
      .map((message) => ({
        role: message.role as "user" | "assistant",
        content: message.content,
      }));
    const tools = createTools(this.store, {
      allowCodeTools: turn.route.allowTools,
      allowDelegation: turn.route.allowDelegation,
    });

    for (let round = 0; round < this.config.maxToolRounds; round += 1) {
      if (turn.signal?.aborted) throw new DOMException("Interrupted", "AbortError");
      const stream = this.model.stream({
        model: modelName,
        tier: turn.route.tier,
        instructions: turn.instructions,
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

      if (!roundText && response.output_text) {
        yield { type: "text_delta", delta: response.output_text };
      }

      const calls = response.output.filter(isFunctionCall);
      if (calls.length === 0) {
        yield { type: "done", responseId: response.id };
        return;
      }
      if (round === this.config.maxToolRounds - 1) {
        throw new Error(`Tool loop reached ${this.config.maxToolRounds} model rounds before final synthesis.`);
      }

      input = [...input, ...response.output as ResponseInputItem[]];
      const runCall = async (call: ResponseFunctionToolCall) => {
        try {
          const result = await executeTool(tools, call.name, call.arguments, {
            cwd: turn.session.cwd,
            sessionId: turn.session.id,
            memoryScope: turn.memoryScope,
            ...(turn.signal ? { signal: turn.signal } : {}),
            delegate: async (task) => this.model.delegate(
              task,
              `${turn.instructions}\n\n${buildDelegationContext(turn.session.cwd, task)}`,
              turn.signal,
            ),
          });
          return { call, output: result.output, summary: result.summary };
        } catch (error) {
          return {
            call,
            output: `Tool error: ${error instanceof Error ? error.message : String(error)}`,
            summary: "tool failed",
          };
        }
      };
      const readOnlyTools = new Set(["memory_search", "read_file", "list_files", "search_files", "delegate_task"]);
      if (calls.length > 1 && calls.every((call) => readOnlyTools.has(call.name))) {
        for (const call of calls) yield { type: "tool_start", name: call.name, callId: call.call_id };
        const results = await Promise.all(calls.map(runCall));
        for (const { call, output, summary } of results) {
          yield { type: "tool_end", name: call.name, callId: call.call_id, summary };
          input.push({ type: "function_call_output", call_id: call.call_id, output });
        }
      } else {
        for (const call of calls) {
          yield { type: "tool_start", name: call.name, callId: call.call_id };
          const result = await runCall(call);
          yield { type: "tool_end", name: call.name, callId: call.call_id, summary: result.summary };
          input.push({ type: "function_call_output", call_id: call.call_id, output: result.output });
        }
      }
    }

    throw new Error(`Tool loop exceeded ${this.config.maxToolRounds} rounds.`);
  }
}
