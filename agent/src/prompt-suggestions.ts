import { readFileSync } from "node:fs";
import type { DatabaseSync } from "node:sqlite";
import type { Models } from "@earendil-works/pi-ai";
import type { ModelRef } from "@earendil-works/pi-durable";
import { defaultModel } from "./cli/catalog.ts";

const systemPrompt = readFileSync(new URL("../prompts/suggestion.md", import.meta.url), "utf8");
type Message = { role: string; text: string };

export class PromptSuggestions {
  private readonly runtime: Models;
  private readonly db: DatabaseSync;
  private readonly model: (sessionId: string) => ModelRef | Promise<ModelRef>;
  private readonly pending = new Map<string, Promise<string | null>>();
  private readonly controller = new AbortController();
  constructor(runtime: Models, db: DatabaseSync, model: (sessionId: string) => ModelRef | Promise<ModelRef> = () => defaultModel) {
    this.runtime = runtime;
    this.db = db;
    this.model = model;
    db.exec("CREATE TABLE IF NOT EXISTS suggestions (session_id TEXT NOT NULL, reply_id TEXT NOT NULL, text TEXT, PRIMARY KEY (session_id, reply_id))");
  }

  get(sessionId: string, replyId: string, messages: Message[]) {
    if (this.controller.signal.aborted) return Promise.resolve(null);
    const saved = this.db.prepare("SELECT text FROM suggestions WHERE session_id = ? AND reply_id = ?").get(sessionId, replyId) as { text: string | null } | undefined;
    if (saved) return Promise.resolve(saved.text);
    const key = JSON.stringify([sessionId, replyId]);
    const cached = this.pending.get(key);
    if (cached) return cached;
    const result = this.generate(sessionId, messages).then((answer) => {
      if (answer) this.db.prepare("INSERT INTO suggestions (session_id, reply_id, text) VALUES (?, ?, ?)").run(sessionId, replyId, answer.text);
      return answer?.text ?? null;
    }).catch(() => null).finally(() => this.pending.delete(key));
    this.pending.set(key, result);
    return result;
  }

  async close() {
    this.controller.abort();
    await Promise.all(this.pending.values());
  }

  private async generate(sessionId: string, messages: Message[]) {
    // Keep recent user intent and completed replies; no agent instructions, tools, or tool output.
    const conversation = messages.filter((message) => message.role === "user" || message.role === "assistant").slice(-12)
      .map(({ role, text }) => ({ role, text: text.slice(-6000) }));
    const signal = AbortSignal.any([this.controller.signal, AbortSignal.timeout(12000)]);
    const selected = await this.model(sessionId);
    if (signal.aborted) return;
    const model = this.runtime.getModel(selected.provider, selected.modelId);
    if (!model) return;
    const stream = this.runtime.streamSimple(model, { systemPrompt, messages: [{ role: "user", timestamp: 0,
      content: JSON.stringify({ conversation }) }] }, {
      maxRetries: 0, signal,
    });
    const answer = await stream.result();
    if (signal.aborted || answer.stopReason !== "stop") return;
    const text = answer.content.filter((part) => part.type === "text").map((part) => part.text).join("").trim();
    if (text === "NONE") return { text: null };
    if (!text || /[\r\n\x00-\x1f]/.test(text) || text.length > 180 || text.split(/\s+/).length > 16) return;
    return { text };
  }
}
