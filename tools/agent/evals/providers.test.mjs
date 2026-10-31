import assert from "node:assert/strict";
import { mkdtempSync, mkdirSync, writeFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import test from "node:test";
import { createModels, lazyStream } from "@earendil-works/pi-ai";
import { openaiProvider } from "@earendil-works/pi-ai/providers/openai";
import { anthropicProvider } from "@earendil-works/pi-ai/providers/anthropic";
import { googleProvider } from "@earendil-works/pi-ai/providers/google";
import { xaiProvider } from "@earendil-works/pi-ai/providers/xai";
import { Providers, defaultModel, utilityAgent } from "../src/providers.ts";
import { PiService, providerModels } from "../src/pi.ts";
import { fastModePayload, supportsFastMode } from "../src/fast-mode.ts";
import { PromptSuggestions } from "../src/prompt-suggestions.ts";
import { NativeSearchSources } from "../src/native-search.ts";
import { BACKGROUND_CONTEXT as context } from "@earendil-works/chord/context";
import { defineTool, MemoryStorage } from "@earendil-works/pi-durable";

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
  const dir = mkdtempSync(join(tmpdir(), "agent-providers-"));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const models = runtime();
  const current = models.getProvider("openai");
  models.setProvider({ ...current, id: "retired", name: "Retired provider (legacy)" });
  const providers = new Providers(dir, models);
  assert.deepEqual(providers.model, defaultModel);
  assert.equal(defaultModel.provider, "openai");
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
  assert.ok(!snapshot.providers.some(provider => provider.id === "retired"));
  const anthropic = snapshot.providers.find(provider => provider.id === "anthropic");
  assert.equal(anthropic.fastSupported, true);
  assert.ok(anthropic.models.every(model => !Object.hasOwn(model, "fastSupported")));
  const openai = snapshot.providers.find(provider => provider.id === "openai");
  assert.deepEqual(openai.models.map(model => model.id), ["gpt-6.1-sol", "gpt-6-astra", "gpt-6-luna"]);
  assert.equal(openai.defaultModel, "gpt-6.1-sol");
  assert.deepEqual(anthropic.models.map(model => model.id), ["claude-fable-5-1", "claude-opus-5-5", "claude-sonnet-5-5", "claude-haiku-5-5"]);
  assert.equal(anthropic.defaultModel, "claude-sonnet-5-5");
  const google = snapshot.providers.find(provider => provider.id === "google");
  assert.deepEqual(google.models.map(model => model.id), ["gemini-4-argon", "gemini-3.8-flash", "gemini-3.5-flash-lite"]);
  assert.equal(google.defaultModel, "gemini-4-argon");
  const xai = snapshot.providers.find(provider => provider.id === "xai");
  assert.deepEqual(xai.models.map(model => model.id), ["grok-4.7"]);
  assert.equal(xai.defaultModel, "grok-4.7");
  assert.ok(snapshot.providers.filter(provider => ["xai", "google"].includes(provider.id)).every(provider => provider.fastSupported));
  await assert.rejects(reopened.setFastMode("unknown", true), /Choose a provider/);
  const offline = new Providers(dir, new Proxy(models, { get(target, key) {
    return key === "checkAuth" ? async () => undefined : Reflect.get(target, key);
  } }));
  t.after(() => offline.close());
  await assert.rejects(offline.setFastMode("anthropic", true), /Connect Anthropic first/);
});

test("native search preserves client tools, skips router and dispatcher calls, and stays out of suggestions", async t => {
  const models = runtime();
  const wrapped = providerModels(models);
  const requests = [];
  t.mock.method(globalThis, "fetch", capture(requests));
  for (const [provider, id] of [["openai", "gpt-6-luna"], ["xai", "grok-4.7"],
    ["anthropic", "claude-sonnet-5-5"], ["google", "gemini-3.8-flash"]]) {
    const selected = models.getModel(provider, id);
    const send = async toolName => {
      await wrapped.streamSimple(selected, {
        messages: [{ role: "user", content: "Look up tomorrow's weather", timestamp: 0 }],
        tools: [{ name: toolName, description: "Fixture", parameters: { type: "object", properties: {} } }],
      }, { maxRetries: 0 }).result();
      return requests.at(-1).body;
    };
    const request = await send("read");
    if (provider === "google") {
      assert.equal(request.tools.filter(tool => tool.googleSearch).length, 1);
      assert.equal(request.tools.flatMap(tool => tool.functionDeclarations || []).some(tool => tool.name === "read"), true);
    } else {
      assert.equal(request.tools.filter(tool => tool.type?.startsWith("web_search")).length, 1);
      const clientTools = provider === "openai"
        ? request.input.filter(item => item.type === "additional_tools").flatMap(item => item.tools)
        : request.tools;
      assert.equal(clientTools.some(tool => tool.name === "read"), true);
      if (provider === "anthropic") assert.equal(request.tools.find(tool => tool.name === "web_search").type, "web_search_20250305");
    }
    for (const name of ["route_home", "dispatch_message"]) {
      const routing = await send(name);
      assert.ok(!(routing.tools || []).some(tool => tool.googleSearch || tool.type?.startsWith("web_search")));
    }
  }
});

test("hosted search citations survive Pi normalization without browser calls", async t => {
  const models = runtime();
  const annotation = { type: "url_citation", url: "https://example.com/forecast", title: "Forecast" };
  const item = { id: "message", type: "message", role: "assistant", content: [
    { type: "output_text", text: "Rain tomorrow.", annotations: [annotation] },
  ] };
  const events = [
    { type: "response.output_item.added", output_index: 0, item: { ...item, content: [] } },
    { type: "response.output_text.delta", output_index: 0, content_index: 0, delta: "Rain tomorrow." },
    { type: "response.output_text.annotation.added", annotation },
    { type: "response.output_item.done", output_index: 0, item },
    { type: "response.completed", response: { id: "response", status: "completed", output: [item] } },
  ];
  t.mock.method(globalThis, "fetch", async () => new Response(events.map(event => `data: ${JSON.stringify(event)}\n\n`).join(""),
    { headers: { "content-type": "text/event-stream" } }));
  const observed = [];
  const answer = await providerModels(models).streamSimple(models.getModel("openai", "gpt-6-luna"), {
    messages: [{ role: "user", content: "Tomorrow's weather?", timestamp: 0 }],
  }, { maxRetries: 0, onProviderStreamEvent: event => { observed.push(event.type); } }).result();
  assert.equal(answer.stopReason, "stop");
  assert.equal(answer.content.some(part => part.type === "toolCall"), false);
  const text = answer.content.filter(part => part.type === "text").map(part => part.text).join("");
  assert.equal(text, "Rain tomorrow.\n\nSources: [Forecast](https://example.com/forecast)");
  assert.equal(observed.length, events.length);
});

test("Claude citations and Gemini grounding retain safe source URLs without duplicates", () => {
  const sources = new NativeSearchSources();
  sources.observe({ delta: { citation: { type: "web_search_result_location", url: "https://example.com/claude", title: "Claude source" } } });
  sources.observe({ candidates: [{ groundingMetadata: { groundingChunks: [{ web: { uri: "https://example.com/gemini", title: "Gemini source" } }] } }] });
  sources.observe({ annotation: { url: "javascript:alert(1)", title: "Unsafe" } });
  const answer = { stopReason: "stop", content: [{ type: "text", text: "Answer [Claude source](https://example.com/claude)" }] };
  sources.append(answer);
  assert.equal(answer.content.at(-1).text, "\n\nSources: [Gemini source](https://example.com/gemini)");
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
  const openai = { provider: "openai", api: "openai-responses", id: "gpt-6-luna" };
  assert.equal(fastModePayload(openai, {}, true).service_tier, "priority");
  assert.equal(fastModePayload(openai, {}, false).service_tier, "default");
  assert.equal(supportsFastMode({ ...openai, id: "gpt-6-luna-2026-09-01" }), true);
  assert.equal(supportsFastMode({ ...openai, id: "gpt-6-unknown" }), false);
  assert.equal(supportsFastMode({ ...openai, provider: "some-proxy" }), false);
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
    assert.ok(!(requests.at(-1).body.tools || []).some(tool => tool.googleSearch || tool.type?.startsWith("web_search")));
    fast = false;
    await suggestions.get("session", "reply", messages);
    assert.equal(requests.at(-1).body[field], off);
  }
});


test("router and dispatcher disable reasoning or use the provider minimum with fast mode on or off", { timeout: 15000 }, async t => {
  const dir = mkdtempSync(join(tmpdir(), "agent-utility-models-"));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const catalog = runtime();
  for (const [provider, modelId, expected, thinkingLevel] of [
    ["openai", "gpt-6-astra", "gpt-6-luna", "off"],
    ["anthropic", "claude-fable-5-1", "claude-haiku-5-5", "off"],
    ["google", "gemini-4-argon", "gemini-3.5-flash-lite", "minimal"],
    ["xai", "grok-4.7", "grok-4.7", "low"],
    ["fixture", "custom-model", "custom-model", "low"],
  ]) for (const fast of [false, true]) {
    const calls = [];
    const models = {
      getAuth: async () => undefined,
      getModel: (name, id) => name === "fixture" ? { ...catalog.getModel("openai", "gpt-6-luna"), provider: name, id } : catalog.getModel(name, id),
      streamSimple: (selected, transcript, options) => lazyStream(selected, async () => (async function* () {
        calls.push({ provider: selected.provider, modelId: selected.id, effort: options.reasoning });
        const tools = transcript.tools || transcript.messages.flatMap(message => message.toolsAdded || []);
        const name = tools.find(tool => ["route_home", "dispatch_message"].includes(tool.name)).name;
        const message = { role: "assistant", content: [{ type: "toolCall", id: crypto.randomUUID(), name, arguments: {} }],
          api: selected.api, provider: selected.provider, model: selected.id, stopReason: "toolUse", timestamp: Date.now(),
          usage: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, totalTokens: 0, cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0 } } };
        yield { type: "done", reason: "toolUse", message };
      })()),
    };
    const dataDir = join(dir, `${provider}-${fast}`);
    mkdirSync(dataDir);
    writeFileSync(join(dataDir, "fast-mode.json"), JSON.stringify({ [provider]: fast }));
    const service = await PiService.open(dataDir, { models, model: { provider, modelId }, storage: new MemoryStorage() });
    try {
      for (const [role, name] of [["router", "route_home"], ["dispatcher", "dispatch_message"]]) {
        const config = service.agent(role, dir);
        assert.deepEqual(config.model, { provider, modelId: expected });
        assert.equal(config.thinkingLevel, thinkingLevel);
        let accepted;
        const choose = defineTool({ name, description: "Choose", parameters: { type: "object", properties: {} },
          execute: async () => { accepted = "accepted"; return { output: [{ type: "text", text: accepted }] }; } });
        assert.equal(await service.utility(role, "Classify this request", dir, [choose], () => accepted), "accepted");
      }
      assert.deepEqual(calls, Array.from({ length: 2 }, () => ({ provider, modelId: expected, effort: thinkingLevel === "off" ? undefined : thinkingLevel })));
      for (const role of ["coordinator", "worker"]) {
        assert.deepEqual(service.agent(role, dir).model, { provider, modelId });
        assert.equal(service.agent(role, dir).thinkingLevel, "high");
      }
      assert.deepEqual(service.model, { provider, modelId });
    } finally { await service.close(); }
  }
});


test("mapped utility models serialize disabled or minimum reasoning and respect each provider's fast compatibility", async t => {
  const models = runtime();
  let fast = false;
  const wrapped = providerModels(models, () => fast);
  const requests = [];
  t.mock.method(globalThis, "fetch", capture(requests));
  for (const selected of [
    { provider: "openai", modelId: "gpt-6-astra" },
    { provider: "anthropic", modelId: "claude-fable-5-1" },
    { provider: "google", modelId: "gemini-4-argon" },
    { provider: "xai", modelId: "grok-4.7" },
  ]) for (const enabled of [false, true]) for (const name of ["route_home", "dispatch_message"]) {
    fast = enabled;
    const { model: mapped, thinkingLevel } = utilityAgent(selected);
    await wrapped.streamSimple(models.getModel(mapped.provider, mapped.modelId), {
      messages: [{ role: "user", content: "Choose", timestamp: 0 }],
      tools: [{ name, description: "Choose", parameters: { type: "object", properties: {} } }],
    }, { ...(thinkingLevel === "off" ? {} : { reasoning: thinkingLevel }), maxRetries: 0 }).result();
    const request = requests.at(-1).body;
    if (selected.provider === "google") {
      assert.equal(request.generationConfig.thinkingConfig.thinkingLevel, "MINIMAL");
      assert.equal(request.serviceTier, enabled ? "priority" : undefined);
    } else {
      assert.equal(request.model, mapped.modelId);
      if (selected.provider === "anthropic") {
        assert.deepEqual(request.thinking, { type: "disabled" });
        assert.equal(request.output_config, undefined);
        assert.ok(!request.messages.some(message => message.output_config));
        assert.equal(request.speed, undefined); // Haiku has no Opus fast mode.
      } else {
        assert.equal(request.reasoning.effort, selected.provider === "openai" ? "none" : "low");
        assert.equal(request.service_tier, enabled ? "priority" : "default");
      }
    }
    assert.ok(!(request.tools || []).some(tool => tool.googleSearch || tool.type?.startsWith("web_search")));
  }
});

test("Home routing and dispatch keep reserved capacity under execution and dispatch load", { timeout: 10000 }, async () => {
  const model = runtime().getModel("openai", "gpt-6-luna");
  for (const flood of [Array(9).fill("dispatch_message"), Array(8).fill("read")]) {
    const release = Promise.withResolvers();
    const started = [];
    const models = providerModels({ streamSimple: (selected, transcript) => lazyStream(selected, async () => (async function* () {
      const name = transcript.tools[0].name;
      started.push(name);
      if (name !== "route_home") await release.promise;
      yield { type: "done", reason: "stop", message: { role: "assistant", content: [{ type: "text", text: "Done" }],
        api: selected.api, provider: selected.provider, model: selected.id, stopReason: "stop", timestamp: Date.now(),
        usage: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, totalTokens: 0, cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0 } } } };
    })()) });
    const send = name => models.streamSimple(model, { messages: [], tools: [{ name, description: "Choose", parameters: { type: "object", properties: {} } }] }).result();
    const pending = flood.map(send);
    if (flood[0] === "read") pending.push(send("dispatch_message"));
    pending.push(send("dispatch_message"));
    try {
      await send("route_home");
      assert.equal(started.filter(name => name === "dispatch_message").length, flood[0] === "read" ? 1 : 9);
      assert.equal(started.filter(name => name === "read").length, flood[0] === "read" ? 8 : 0);
      assert.equal(started.filter(name => name === "route_home").length, 1);
    } finally { release.resolve(); await Promise.all(pending); }
  }
});
