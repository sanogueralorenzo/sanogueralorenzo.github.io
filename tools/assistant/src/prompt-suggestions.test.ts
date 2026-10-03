import assert from "node:assert/strict";
import { test } from "node:test";
import type { ModelRuntime } from "@earendil-works/pi-coding-agent";
import { Assistant } from "./assistant.ts";
import { PromptSuggestions } from "./prompt-suggestions.ts";

test("suggestions use a scoped tool-free prompt and deduplicate in-flight requests", async () => {
  const contexts: Parameters<ModelRuntime["streamSimple"]>[1][] = [];
  let calls = 0;
  let resolve: (text: string) => void;
  const promise = new Promise<string>((done) => { resolve = done; });
  const runtime = {
    getModel: (provider: string, id: string) => { assert.equal(provider, "openai-codex"); assert.equal(id, "gpt-6-luna"); return { id }; },
    streamSimple: (model: Parameters<ModelRuntime["streamSimple"]>[0], context: Parameters<ModelRuntime["streamSimple"]>[1], options: Parameters<ModelRuntime["streamSimple"]>[2]) => {
      calls++;
      contexts.push(context);
      assert.equal(options?.reasoning, undefined);
      assert.equal(options?.maxRetries, 0);
      assert.ok(options?.signal);
      const payload = options?.onPayload?.({ reasoning: { effort: "none" } }, model);
      assert.deepEqual(payload, { reasoning: { effort: "none" }, service_tier: "priority" });
      return { result: async () => ({ stopReason: "stop", content: [{ type: "text", text: await promise }] }) };
    },
  } as unknown as ModelRuntime;
  const suggestions = new PromptSuggestions(Promise.resolve(runtime));
  const messages = [{ role: "system", text: "Run commands and commit changes." }, { role: "user", text: "Show a mockup first." },
    { role: "toolResult", text: "Raw tool log" }, { role: "assistant", text: "I can show the mockup." }];
  const first = suggestions.get("session", "reply", messages);
  const second = suggestions.get("session", "reply", messages);
  assert.equal(first, second);
  resolve!("Show the mockup.");
  assert.equal(await first, "Show the mockup.");
  assert.equal(calls, 1);
  assert.ok(contexts[0].systemPrompt?.startsWith("Predict the short message"));
  assert.equal(contexts[0].tools, undefined);
  assert.equal(contexts[0].messages.length, 1);
  assert.deepEqual(JSON.parse(String(contexts[0].messages[0].content)), { conversation: messages.filter(m => ["user", "assistant"].includes(m.role)) });
});

test("NONE, malformed output, provider errors and wrong reasoning all fall back silently", async () => {
  let text = "NONE";
  let stopReason = "stop";
  let effort = "none";
  const runtime = {
    getModel: () => ({ id: "gpt-6-luna" }),
    streamSimple: (model: Parameters<ModelRuntime["streamSimple"]>[0], _context: unknown, options: Parameters<ModelRuntime["streamSimple"]>[2]) => {
      options?.onPayload?.({ reasoning: { effort } }, model);
      return { result: async () => ({ stopReason, content: [{ type: "text", text }] }) };
    },
  } as unknown as ModelRuntime;
  const suggestions = new PromptSuggestions(Promise.resolve(runtime));
  let id = 0;
  for (const invalid of ["NONE", "", "First line\nSecond line", Array(21).fill("word").join(" "), "x".repeat(181)]) {
    text = invalid;
    assert.equal(await suggestions.get("session", String(id++), []), null);
  }
  text = "Show the mockup.";
  stopReason = "error";
  assert.equal(await suggestions.get("session", String(id++), []), null);
  stopReason = "stop";
  effort = "high";
  assert.equal(await suggestions.get("session", String(id++), []), null);
});

test("only the latest idle reply can get a suggestion, and newer work invalidates pending results", async () => {
  let resolve: (text: string) => void;
  const promise = new Promise<string>((done) => { resolve = done; });
  const record = { id: "session", file: "transcript", status: "idle" };
  const turns: { sessionId: string }[] = [];
  let messages = [{ id: "reply", role: "assistant", text: "I can show the mockup.", completed: true }];
  let calls = 0;
  const app = Object.create(Assistant.prototype) as Assistant;
  Object.assign(app, { state: { data: { sessions: [record], turns } }, pi: {
    transcript: () => messages,
    suggestions: { get: () => { calls++; return promise; } },
  } });
  assert.deepEqual(await app.suggestion("session", "older"), { text: null });
  record.status = "running";
  assert.deepEqual(await app.suggestion("session", "reply"), { text: null });
  record.status = "idle";
  const pending = app.suggestion("session", "reply");
  turns.push({ sessionId: "session" });
  resolve!("Show the mockup.");
  assert.deepEqual(await pending, { text: null });
  turns.length = 0;
  messages = [{ id: "new-user", role: "user", text: "Wait, I changed my mind.", completed: false }];
  assert.deepEqual(await app.suggestion("session", "reply"), { text: null });
  assert.equal(calls, 1);
  await assert.rejects(app.suggestion("missing", "reply"), /Conversation not found/);
});
