import { readFileSync } from "node:fs";
import type { ModelRuntime } from "@earendil-works/pi-coding-agent";

const systemPrompt = readFileSync(new URL("../prompts/suggestion.md", import.meta.url), "utf8");
type Message = { role: string; text: string };

export class PromptSuggestions {
  private readonly runtime: Promise<ModelRuntime>;
  private readonly latest = new Map<string, { replyId: string; result: Promise<string | null> }>();
  constructor(runtime: Promise<ModelRuntime>) { this.runtime = runtime; }

  get(sessionId: string, replyId: string, messages: Message[]) {
    const cached = this.latest.get(sessionId);
    if (cached?.replyId === replyId) return cached.result;
    const result = this.generate(messages).catch(() => null);
    this.latest.set(sessionId, { replyId, result });
    return result;
  }

  private async generate(messages: Message[]) {
    // Keep recent user intent and completed replies; no agent instructions, tools, or tool output.
    const conversation = messages.filter((message) => message.role === "user" || message.role === "assistant").slice(-12)
      .map(({ role, text }) => ({ role, text: text.slice(-6000) }));
    const signal = AbortSignal.timeout(5000);
    const runtime = await this.runtime;
    if (signal.aborted) return null;
    const model = runtime.getModel("openai-codex", "gpt-6-luna");
    if (!model) return null;
    const stream = runtime.streamSimple(model, { systemPrompt, messages: [{ role: "user", timestamp: 0,
      content: JSON.stringify({ conversation }) }] }, {
      // Omitting Pi's thinking level maps to native effort "none"; verify the provider payload below.
      transport: "sse", maxRetries: 0, signal,
      onPayload: (payload) => {
        if (typeof payload !== "object" || payload === null || Array.isArray(payload)) throw new Error("Unexpected suggestion payload");
        const request = { ...payload as Record<string, unknown>, service_tier: "priority" };
        const reasoning = (request as Record<string, unknown>).reasoning as { effort?: unknown } | undefined;
        if (reasoning?.effort !== "none") throw new Error("Suggestions require no reasoning");
        return request;
      },
    });
    const answer = await stream.result();
    if (signal.aborted || answer.stopReason !== "stop") return null;
    const text = answer.content.filter((part) => part.type === "text").map((part) => part.text).join("").trim();
    return !text || text === "NONE" || /[\r\n\x00-\x1f]/.test(text) || text.length > 180 || text.split(/\s+/).length > 20 ? null : text;
  }
}
