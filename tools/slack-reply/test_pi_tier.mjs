import assert from "node:assert/strict";
import test from "node:test";
import tierExtension, { tierPayload } from "./pi_tier.mjs";

test("Pi maps fast and default tiers without changing models, reasoning, or unrelated fields", () => {
  for (const [provider, api] of [["openai", "openai-responses"], ["openai-codex", "openai-codex-responses"], ["xai", "openai-completions"]]) {
    const payload = { model: "test-model", reasoning: { effort: "high" }, service_tier: "priority" };
    for (const tier of ["default", "fast"]) {
      const result = tierPayload({ provider, api, id: "test-model" }, payload, tier);
      assert.deepEqual(result, { ...payload, service_tier: tier === "fast" ? "priority" : "default" });
    }
  }
  const google = { provider: "google", api: "google-generative-ai", id: "gemini-test" };
  const payload = { model: google.id, config: { temperature: 0, serviceTier: "priority" } };
  assert.deepEqual(tierPayload(google, payload, "default"), { model: google.id, config: { temperature: 0 } });
  assert.deepEqual(tierPayload(google, payload, "fast"), payload);
});

test("Pi enables Anthropic fast mode only on supported Opus models", () => {
  const model = { provider: "anthropic", api: "anthropic-messages", id: "claude-opus-5-5" };
  const payload = { model: model.id, speed: "fast", max_tokens: 100 };
  assert.deepEqual(tierPayload(model, payload, "fast"), payload);
  assert.deepEqual(tierPayload(model, payload, "default"), { model: model.id, max_tokens: 100 });
  assert.throws(() => tierPayload({ ...model, id: "claude-sonnet-5-5" }, payload, "fast"), /unsupported/);
  assert.throws(() => tierPayload({ provider: "custom", id: "test" }, {}, "fast"), /unsupported/);
});

test("Pi stops unsupported requests and manages the preview beta without removing other headers", () => {
  const handlers = new Map();
  let tier = "fast";
  tierExtension({ registerFlag() {}, getFlag: () => tier, on: (event, handler) => handlers.set(event, handler) });
  let aborted = false;
  assert.throws(() => handlers.get("before_provider_request")({ payload: {} }, {
    model: { provider: "custom", id: "test" }, abort: () => { aborted = true; },
  }), /Slack Reply tier:/);
  assert.equal(aborted, true);
  const ctx = { model: { provider: "anthropic", api: "anthropic-messages", id: "claude-opus-5" } };
  const event = { headers: { "anthropic-beta": "other-beta", authorization: "test" } };
  handlers.get("before_provider_headers")(event, ctx);
  assert.equal(event.headers["anthropic-beta"], "other-beta,fast-mode-2026-02-01");
  tier = "default";
  handlers.get("before_provider_headers")(event, ctx);
  assert.deepEqual(event.headers, { "anthropic-beta": "other-beta", authorization: "test" });
});
