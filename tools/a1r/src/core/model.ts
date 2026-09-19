import OpenAI from "openai";
import type {
  FunctionTool,
  Response,
  ResponseInputItem,
} from "openai/resources/responses/responses";
import type { ModelTier, RuntimeConfig } from "./types.js";

export interface ModelRequest {
  model: string;
  tier: ModelTier;
  instructions: string;
  input: ResponseInputItem[];
  tools: FunctionTool[];
  promptCacheKey: string;
  signal?: AbortSignal;
}

export interface ModelStreamEvent {
  type: "text_delta";
  delta: string;
}

export interface ModelClient {
  stream(request: ModelRequest): AsyncGenerator<ModelStreamEvent, Response>;
  delegate(task: string, context: string, signal?: AbortSignal): Promise<string>;
}

export class OpenAIModelClient implements ModelClient {
  private client: OpenAI;
  private configured: boolean;

  constructor(private readonly config: RuntimeConfig, apiKey = process.env.OPENAI_API_KEY) {
    this.configured = Boolean(apiKey);
    this.client = new OpenAI({ apiKey: apiKey ?? "not-configured" });
  }

  isConfigured(): boolean {
    return this.configured;
  }

  async setApiKey(apiKey: string): Promise<void> {
    const candidate = new OpenAI({ apiKey });
    await candidate.models.list();
    this.client = candidate;
    this.configured = true;
  }

  async *stream(request: ModelRequest): AsyncGenerator<ModelStreamEvent, Response> {
    if (!this.configured) throw new Error("OpenAI is not connected. Run `a1r setup` once, then try again.");
    const candidates = [...new Set([request.model, this.config.models.standard, this.config.models.fast])];
    for (const [index, model] of candidates.entries()) {
      let emitted = false;
      try {
        const stream = await this.client.responses.create({
          model,
          instructions: request.instructions,
          input: request.input,
          tools: request.tools,
          tool_choice: request.tools.length > 0 ? "auto" : "none",
          parallel_tool_calls: true,
          reasoning: { effort: request.tier === "deep" ? "high" : request.tier === "standard" ? "medium" : "low" },
          include: ["reasoning.encrypted_content"],
          prompt_cache_key: request.promptCacheKey,
          store: false,
          stream: true,
        }, request.signal ? { signal: request.signal } : undefined);

        let finalResponse: Response | null = null;
        for await (const event of stream) {
          if (event.type === "response.output_text.delta" || event.type === "response.refusal.delta") {
            emitted = true;
            yield { type: "text_delta", delta: event.delta };
          }
          if (event.type === "response.completed") finalResponse = event.response;
          if (event.type === "response.incomplete") {
            const reason = event.response.incomplete_details?.reason ?? "unknown reason";
            throw new Error(`The OpenAI response was incomplete: ${reason}.`);
          }
          if (event.type === "response.failed") {
            throw new Error(event.response.error?.message ?? "The OpenAI response failed.");
          }
          if (event.type === "error") throw new Error(event.message);
        }
        if (!finalResponse) throw new Error("The OpenAI stream ended before a final response arrived.");
        return finalResponse;
      } catch (error) {
        const status = (error as { status?: number }).status;
        const canFallback = !emitted && index < candidates.length - 1 && (status === 400 || status === 404);
        if (!canFallback) throw error;
      }
    }
    throw new Error("No configured OpenAI model is available.");
  }

  async delegate(task: string, context: string, signal?: AbortSignal): Promise<string> {
    if (!this.configured) throw new Error("OpenAI is not connected. Run `a1r setup` once, then try again.");
    const response = await this.client.responses.create({
      model: this.config.models.fast,
      instructions: "You are a focused internal A1R worker. Investigate the bounded task using only the supplied context. Return concise findings to the parent assistant. Do not address the end user.",
      input: `${task}\n\nContext:\n${context.slice(0, 20_000)}`,
      reasoning: { effort: "low" },
      store: false,
    }, signal ? { signal } : undefined);
    return response.output_text;
  }
}
