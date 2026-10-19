import assert from "node:assert/strict";
import { test } from "node:test";
import { visibleProviders } from "./providers.js";

const providers = [
  { id: "amazon-bedrock", name: "Amazon Bedrock", cloud: true, methods: [{ id: "api_key" }] },
  { id: "anthropic", name: "Claude", cloud: false, methods: [{ id: "oauth" }, { id: "api_key" }] },
  { id: "google", name: "Google Gemini", cloud: false, methods: [{ id: "api_key" }] },
  { id: "openai-codex", name: "Codex", cloud: false, methods: [{ id: "oauth" }] },
];
const ids = values => values.map(provider => provider.id);

test("provider search matches names and Pi IDs without changing catalog order", () => {
  assert.deepEqual(visibleProviders(providers, "", "all"), providers);
  assert.deepEqual(ids(visibleProviders(providers, "  ANTHROPIC  ", "all")), ["anthropic"]);
  assert.deepEqual(ids(visibleProviders(providers, "gemini google", "all")), ["google"]);
  assert.deepEqual(ids(visibleProviders(providers, "codex", "all")), ["openai-codex"]);
});

test("authentication filters include every matching login method and combine with search", () => {
  assert.deepEqual(ids(visibleProviders(providers, "", "oauth")), ["anthropic", "openai-codex"]);
  assert.deepEqual(ids(visibleProviders(providers, "", "api_key")), ["amazon-bedrock", "anthropic", "google"]);
  assert.deepEqual(ids(visibleProviders(providers, "", "cloud")), ["amazon-bedrock"]);
  assert.deepEqual(ids(visibleProviders(providers, "claude", "api_key")), ["anthropic"]);
  assert.deepEqual(visibleProviders(providers, "claude", "cloud"), []);
  assert.deepEqual(visibleProviders(providers, "missing", "all"), []);
});
