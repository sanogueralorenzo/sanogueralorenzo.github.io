import OpenAI from "openai";
import type {
  FunctionTool,
  Response,
  ResponseInputItem,
} from "openai/resources/responses/responses";

export interface ModelRequest {
  model: string;
  reasoningEffort: "high";
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
  isConfigured?(): boolean;
  stream(request: ModelRequest): AsyncGenerator<ModelStreamEvent, Response>;
}

export class OpenAIModelClient implements ModelClient {
  private client: OpenAI;
  private configured: boolean;

  constructor(apiKey = process.env.OPENAI_API_KEY) {
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
    if (!this.configured) throw new Error("OpenAI is not connected. Run `agent setup` once, then try again.");
    const stream = await this.client.responses.create({
      model: request.model,
      instructions: request.instructions,
      input: request.input,
      tools: request.tools,
      tool_choice: request.tools.length > 0 ? "auto" : "none",
      parallel_tool_calls: true,
      reasoning: { effort: request.reasoningEffort },
      include: ["reasoning.encrypted_content"],
      prompt_cache_key: request.promptCacheKey,
      store: false,
      stream: true,
    }, request.signal ? { signal: request.signal } : undefined);

    let finalResponse: Response | null = null;
    for await (const event of stream) {
      if (event.type === "response.output_text.delta" || event.type === "response.refusal.delta") {
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
  }

}
