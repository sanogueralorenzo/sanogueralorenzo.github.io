import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import test from "node:test";
import { createModels } from "@earendil-works/pi-ai";
import { openaiProvider } from "@earendil-works/pi-ai/providers/openai";
import { anthropicProvider } from "@earendil-works/pi-ai/providers/anthropic";
import { googleProvider } from "@earendil-works/pi-ai/providers/google";
import { xaiProvider } from "@earendil-works/pi-ai/providers/xai";
import { Providers } from "../src/providers.ts";
import { providerModels } from "../src/pi.ts";
import { fastModePayload, supportsFastMode } from "../src/fast-mode.ts";
import { PromptSuggestions } from "../src/prompt-suggestions.ts";

function runtime() {
  const models = createModels({ authContext: {
    env: async name => ["OPENAI_API_KEY", "ANTHROPIC_API_KEY", "GEMINI_API_KEY", "XAI_API_KEY"].includes(name) ? "test-key" : undefined,
    fileExists: async () => false,
  } });
  models.setProvider(openaiProvider());
  models.setProvider(anthropicProvider());
  models.setProvider(googleProvider());
  models.setProvider(xaiProvider());
  return models;
}

// Capture the real SDK's serialized HTTP request without contacting a provider.
function capture(requests) {
  return async (_url, init) => {
    requests.push({ body: JSON.parse(init.body), headers: new Headers(init.headers) });
    return new Response(JSON.stringify({ error: { message: "Test request captured", type: "invalid_request_error" } }),
      { status: 400, headers: { "content-type": "application/json" } });
  };
}

test("fast preferences persist independently and require a connected provider", async t => {
  const dir = mkdtempSync(join(tmpdir(), "assistant-providers-"));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const models = runtime();
  const providers = new Providers(dir, models);
  assert.equal(providers.fastEnabled("openai"), false);
  await providers.setFastMode("openai", true);
  await providers.setFastMode("anthropic", true);
  await providers.setFastMode("google", true);
  await providers.setFastMode("xai", true);
  await providers.setFastMode("openai", false);
  await providers.select("openai", "gpt-6-luna");
  await providers.close();
  const reopened = new Providers(dir, models);
  t.after(() => reopened.close());
  assert.equal(reopened.fastEnabled("openai"), false);
  assert.equal(reopened.fastEnabled("anthropic"), true);
  assert.equal(reopened.fastEnabled("google"), true);
  assert.equal(reopened.fastEnabled("xai"), true);
  assert.deepEqual(reopened.model, { provider: "openai", modelId: "gpt-6-luna" });
  const snapshot = await reopened.snapshot();
  const anthropic = snapshot.providers.find(provider => provider.id === "anthropic");
  assert.equal(anthropic.fastSupported, true);
  assert.ok(anthropic.models.every(model => !Object.hasOwn(model, "fastSupported")));
  const openai = snapshot.providers.find(provider => provider.id === "openai");
  assert.deepEqual(openai.models.map(model => model.id), ["gpt-6.1-sol", "gpt-6-astra", "gpt-6-luna"]);
  assert.equal(openai.defaultModel, "gpt-6.1-sol");
  assert.ok(snapshot.providers.filter(provider => ["xai", "google"].includes(provider.id)).every(provider => provider.fastSupported));
  await assert.rejects(reopened.setFastMode("unknown", true), /Choose a provider/);
  const offline = new Providers(dir, new Proxy(models, { get(target, key) {
    return key === "checkAuth" ? async () => undefined : Reflect.get(target, key);
  } }));
  t.after(() => offline.close());
  await assert.rejects(offline.setFastMode("anthropic", true), /Connect Anthropic first/);
});

test("Pi serializes fast options for all four providers and preserves Anthropic betas", async t => {
  const models = runtime();
  let fast = true;
  const wrapped = providerModels(models, () => fast);
  const requests = [];
  t.mock.method(globalThis, "fetch", capture(requests));
  const send = async (provider, id) => {
    await wrapped.streamSimple(models.getModel(provider, id), { messages: [{ role: "user", content: "Test", timestamp: 0 }] },
      { maxRetries: 0 }).result();
    return requests.at(-1);
  };
  assert.equal((await send("openai", "gpt-6-luna")).body.service_tier, "priority");
  assert.equal((await send("xai", "grok-4.7")).body.service_tier, "priority");
  assert.equal((await send("google", "gemini-3.8-flash")).body.serviceTier, "priority");
  assert.equal((await send("google", "gemma-4-31b-it")).body.serviceTier, undefined);
  const preview = await send("anthropic", "claude-opus-5");
  assert.equal(preview.body.speed, "fast");
  assert.match(preview.headers.get("anthropic-beta"), /fast-mode-2026-02-01/);
  assert.match(preview.headers.get("anthropic-beta"), /mid-conversation-output-config/);
  const opus = await send("anthropic", "claude-opus-5-5");
  assert.equal(opus.body.speed, "fast");
  assert.doesNotMatch(opus.headers.get("anthropic-beta"), /fast-mode-2026-02-01/);
  assert.equal((await send("anthropic", "claude-sonnet-5-5")).body.speed, undefined);
  fast = false;
  assert.equal((await send("openai", "gpt-6-luna")).body.service_tier, "default");
  assert.equal((await send("xai", "grok-4.7")).body.service_tier, "default");
  assert.equal((await send("google", "gemini-3.8-flash")).body.serviceTier, undefined);
  const standard = await send("anthropic", "claude-opus-5");
  assert.equal(standard.body.speed, undefined);
  assert.doesNotMatch(standard.headers.get("anthropic-beta"), /fast-mode-2026-02-01/);
  assert.match(standard.headers.get("anthropic-beta"), /mid-conversation-output-config/);
  const codex = { provider: "openai-codex", api: "openai-codex-responses", id: "gpt-6-luna" };
  assert.equal(fastModePayload(codex, {}, true).service_tier, "priority");
  assert.equal(fastModePayload(codex, {}, false).service_tier, "default");
  assert.equal(supportsFastMode({ ...codex, id: "gpt-6-luna-2026-09-01" }), true);
  assert.equal(supportsFastMode({ ...codex, id: "gpt-6-unknown" }), false);
  assert.equal(supportsFastMode({ ...codex, provider: "some-proxy" }), false);
});

test("reply suggestions follow the current provider fast preference", async t => {
  const models = runtime();
  const requests = [];
  t.mock.method(globalThis, "fetch", capture(requests));
  const db = new DatabaseSync(":memory:");
  t.after(() => db.close());
  let fast = true;
  let selected;
  const suggestions = new PromptSuggestions(Promise.resolve(models), db, () => selected, () => fast);
  const messages = [{ role: "user", text: "Test" }, { role: "assistant", text: "Done" }];
  for (const [provider, modelId, field, on, off] of [
    ["openai", "gpt-6-luna", "service_tier", "priority", "default"],
    ["xai", "grok-4.7", "service_tier", "priority", "default"],
    ["google", "gemini-3.8-flash", "serviceTier", "priority", undefined],
  ]) {
    selected = { provider, modelId };
    fast = true;
    await suggestions.get("session", "reply", messages);
    assert.equal(requests.at(-1).body[field], on);
    fast = false;
    await suggestions.get("session", "reply", messages);
    assert.equal(requests.at(-1).body[field], off);
  }
});
