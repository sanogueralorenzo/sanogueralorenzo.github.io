import { readFileSync } from "node:fs";
import type { DatabaseSync } from "node:sqlite";
import type { Models } from "@earendil-works/pi-ai";

const systemPrompt = readFileSync(new URL("../prompts/suggestion.md", import.meta.url), "utf8");
type Message = { role: string; text: string };

export class PromptSuggestions {
  private readonly runtime: Promise<Models>;
  private readonly db: DatabaseSync;
  private readonly pending = new Map<string, Promise<string | null>>();
  constructor(runtime: Promise<Models>, db: DatabaseSync) {
    this.runtime = runtime;
    this.db = db;
    db.exec("CREATE TABLE IF NOT EXISTS suggestions (session_id TEXT NOT NULL, reply_id TEXT NOT NULL, text TEXT, PRIMARY KEY (session_id, reply_id))");
  }

  get(sessionId: string, replyId: string, messages: Message[]) {
    const saved = this.db.prepare("SELECT text FROM suggestions WHERE session_id = ? AND reply_id = ?").get(sessionId, replyId) as { text: string | null } | undefined;
    if (saved) return Promise.resolve(saved.text);
    const key = JSON.stringify([sessionId, replyId]);
    const cached = this.pending.get(key);
    if (cached) return cached;
    const result = this.generate(messages).then((answer) => {
      if (answer) this.db.prepare("INSERT INTO suggestions (session_id, reply_id, text) VALUES (?, ?, ?)").run(sessionId, replyId, answer.text);
      return answer?.text ?? null;
    }).catch(() => null).finally(() => this.pending.delete(key));
    this.pending.set(key, result);
    return result;
  }

  private async generate(messages: Message[]) {
    // Keep recent user intent and completed replies; no agent instructions, tools, or tool output.
    const conversation = messages.filter((message) => message.role === "user" || message.role === "assistant").slice(-12)
      .map(({ role, text }) => ({ role, text: text.slice(-6000) }));
    const signal = AbortSignal.timeout(5000);
    const runtime = await this.runtime;
    if (signal.aborted) return;
    const model = runtime.getModel("openai-codex", "gpt-6-luna");
    if (!model) return;
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
    if (signal.aborted || answer.stopReason !== "stop") return;
    const text = answer.content.filter((part) => part.type === "text").map((part) => part.text).join("").trim();
    if (text === "NONE") return { text: null };
    if (!text || /[\r\n\x00-\x1f]/.test(text) || text.length > 180 || text.split(/\s+/).length > 16) return;
    return { text };
  }
}
