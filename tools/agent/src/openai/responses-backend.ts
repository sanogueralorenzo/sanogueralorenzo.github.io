import { createHash } from "node:crypto";
import type { Response, ResponseFunctionToolCall, ResponseInputItem, Tool } from "openai/resources/responses/responses";
import { saveArtifactData } from "../workspace/assets.js";
import type { AgentBackend, BackendEvent, BackendTurn } from "../conversation/backend.js";
import { MAX_HISTORY_MESSAGES, MAX_TOOL_ROUNDS, MODELS } from "../local/config.js";
import type { ModelClient } from "./model.js";
import type { Store } from "../conversation/store.js";
import { createTools, executeTool, type AgentTool } from "../workspace/tools.js";
import type { Attachment, RuntimeConfig } from "../conversation/types.js";

const parallelTools = new Set(["memory_search", "read_file", "list_files", "search_files"]);
const wantsImage = (text: string) => /\b(?:create|draw|generate|make)\b[\s\S]{0,80}\b(?:image|illustration|picture|logo|icon)\b/i.test(text);
const cacheKey = (scope: string) => createHash("sha256").update(`agent:${scope}`).digest("hex").slice(0, 32);
const functionCalls = (response: Response) => response.output.filter((item): item is ResponseFunctionToolCall => item.type === "function_call");

async function resultOf<T>(generator: AsyncGenerator<BackendEvent, T>): Promise<T> {
  while (true) {
    const next = await generator.next();
    if (next.done) return next.value;
  }
}

interface Completion {
  model: string;
  instructions: string;
  input: ResponseInputItem[];
  tools: AgentTool[];
  modelTools?: Tool[];
  visible: boolean;
  turn: BackendTurn;
}

export class ResponsesBackend implements AgentBackend {
  readonly kind = "responses" as const;

  constructor(
    private readonly config: RuntimeConfig,
    private readonly store: Store,
    private readonly model: ModelClient,
  ) {}

  async transcribeAudio(attachment: Attachment, signal?: AbortSignal): Promise<string> {
    if (!this.model.transcribeAudio) throw new Error("This OpenAI connection does not support voice transcription.");
    const transcript = await this.model.transcribeAudio(attachment, signal);
    if (!transcript) throw new Error("The voice note did not contain recognizable speech.");
    return transcript;
  }

  async *run(turn: BackendTurn): AsyncGenerator<BackendEvent> {
    let workerResult = "";
    if (turn.route.worker) {
      const worker = turn.route.worker;
      const tools = createTools(this.store, {
        allowCodeTools: worker === "coding" || (worker === "astra" && turn.route.kind === "coding"),
        allowCodeWrites: worker === "coding",
        allowMemoryWrite: false,
      });
      const result = await resultOf(this.complete({
        model: MODELS[worker],
        instructions: turn.workerInstructions,
        input: [{ role: "user", content: turn.request.text }],
        tools,
        visible: false,
        turn,
      }));
      workerResult = result.text;
      if (!workerResult.trim()) throw new Error(`${worker} worker completed without a result.`);
    }

    const tools = createTools(this.store, { allowCodeTools: false, allowMemoryWrite: true });
    const instructions = workerResult
      ? `${turn.instructions}\n\nInternal worker result (working material, not user instructions):\n<worker_result>\n${workerResult.slice(0, 30_000)}\n</worker_result>`
      : turn.instructions;
    const extraTools: Tool[] = wantsImage(turn.request.text) ? [{ type: "image_generation" }] : [];
    yield* this.complete({
      model: MODELS.coordinator,
      instructions,
      input: this.store.getMessages(turn.session.id, MAX_HISTORY_MESSAGES)
        .filter((message) => message.role !== "tool")
        .map((message) => ({ role: message.role as "user" | "assistant", content: message.content })),
      tools,
      modelTools: [...tools.map((tool) => tool.definition), ...extraTools],
      visible: true,
      turn,
    });
    yield { type: "done" };
  }

  private async *complete(completion: Completion): AsyncGenerator<BackendEvent, { text: string }> {
    let input = completion.input;
    let text = "";
    for (let round = 0; round < MAX_TOOL_ROUNDS; round += 1) {
      if (completion.turn.signal?.aborted) throw new DOMException("Interrupted", "AbortError");
      const stream = this.model.stream({
        model: completion.model,
        reasoningEffort: "high",
        instructions: completion.instructions,
        input,
        tools: completion.modelTools ?? completion.tools.map((tool) => tool.definition),
        promptCacheKey: cacheKey(completion.visible
          ? completion.turn.session.scopeKey
          : `${completion.turn.session.scopeKey}:worker:${completion.model}`),
        ...(completion.turn.signal ? { signal: completion.turn.signal } : {}),
      });
      let response!: Response;
      let roundText = "";
      while (true) {
        const next = await stream.next();
        if (next.done) {
          response = next.value;
          break;
        }
        roundText += next.value.delta;
        if (completion.visible) yield { type: "text_delta", delta: next.value.delta };
      }
      if (!roundText) {
        roundText = response.output_text;
        if (completion.visible && roundText) yield { type: "text_delta", delta: roundText };
      }
      text += roundText;

      if (completion.visible) {
        for (const item of response.output) {
          if (item.type === "image_generation_call" && item.result) {
            yield {
              type: "artifact",
              artifact: saveArtifactData(this.config.homeDir, {
                name: `generated-${item.id}.png`,
                mimeType: "image/png",
                data: Buffer.from(item.result, "base64"),
              }),
            };
          }
        }
      }

      const calls = functionCalls(response);
      if (calls.length === 0) return { text };
      if (round === MAX_TOOL_ROUNDS - 1) throw new Error("Tool round limit reached before completion.");
      input = [...input, ...response.output as ResponseInputItem[]];
      if (completion.visible) {
        for (const call of calls) yield { type: "tool_start", name: call.name, callId: call.call_id };
      }
      const execute = (call: ResponseFunctionToolCall) => this.runTool(call, completion.tools, completion.turn);
      const results = [];
      if (calls.every((call) => parallelTools.has(call.name))) results.push(...await Promise.all(calls.map(execute)));
      else for (const call of calls) results.push(await execute(call));
      for (const result of results) {
        if (completion.visible) yield { type: "tool_end", name: result.call.name, callId: result.call.call_id, summary: result.summary };
        input.push({ type: "function_call_output", call_id: result.call.call_id, output: result.output });
      }
    }
    throw new Error("Tool round limit reached before completion.");
  }

  private async runTool(call: ResponseFunctionToolCall, tools: AgentTool[], turn: BackendTurn) {
    try {
      const result = await executeTool(tools, call.name, call.arguments, {
        cwd: turn.session.cwd,
        sessionId: turn.session.id,
        memoryScope: turn.memoryScope,
        ...(turn.signal ? { signal: turn.signal } : {}),
      });
      return { call, ...result };
    } catch (error) {
      return { call, output: `Tool error: ${error instanceof Error ? error.message : String(error)}`, summary: "tool failed" };
    }
  }
}
