import assert from "node:assert/strict";
import { mkdtempSync, mkdirSync, readFileSync, writeFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import test from "node:test";
import { lazyStream } from "@earendil-works/pi-ai";
import { Providers } from "../src/providers.ts";
import { PiService, providerModels } from "../src/pi.ts";
import { cliModels } from "../src/cli/models.ts";
import { PromptSuggestions } from "../src/prompt-suggestions.ts";
import { NativeSearchSources } from "../src/native-search.ts";
import { defineTool, MemoryStorage } from "@earendil-works/pi-durable";

function fixture(t) {
  const dir = mkdtempSync(join(tmpdir(), "agent-cli-"));
  const previous = process.env.PATH;
  const requests = join(dir, "requests");
  process.env.PATH = dir;
  t.after(() => { process.env.PATH = previous; rmSync(dir, { recursive: true, force: true }); });
  function fake(binary, connected = true) {
    writeFileSync(join(dir, binary), `#!${process.execPath}
const {appendFileSync, readFileSync} = require("node:fs");
const {join} = require("node:path");
const readline = require("node:readline");
const args = process.argv.slice(2);
const binary = ${JSON.stringify(binary)};
const connected = ${connected};
const capture = values => appendFileSync(${JSON.stringify(requests)}, JSON.stringify({binary, args, ...values}) + "\\n");
const send = event => console.log(JSON.stringify(event));
const command = args[0];
if (command === "--version") process.exit(0);
if (command === "login") process.exit(connected ? 0 : 1);
if (command === "auth") { send({loggedIn: connected}); process.exit(0); }
const lines = readline.createInterface({input: process.stdin});
lines.on("line", line => {
  const request = JSON.parse(line);
  if (command === "acp") {
    if (request.id === 1) send({id: 1, result: {}});
    if (request.id === 2) send(connected ? {id: 2, result: {sessions: []}} : {id: 2, error: {code: -32000}});
    return;
  }
  const output = {text: "Check the tests", calls: []};
  if (binary === "codex") {
    if (request.id === 1) send({id: 1, result: {}});
    if (request.id === 2) { capture({thread: request.params}); send({id: 2, result: {thread: {id: "thread"}}}); }
    if (request.id === 3) {
      capture({turn: request.params});
      send({method: "item/agentMessage/delta", params: {threadId: "thread", itemId: "answer", delta: JSON.stringify(output)}});
      send({method: "item/completed", params: {threadId: "thread", item: {type: "agentMessage", text: JSON.stringify(output)}}});
      send({method: "turn/completed", params: {threadId: "thread", turn: {status: "completed"}}});
    }
  } else if (binary === "claude") {
    capture({request, prompt: readFileSync(args[args.indexOf("--system-prompt-file") + 1], "utf8")});
    send({type: "result", subtype: "success", structured_output: output});
  } else {
    capture({request, prompt: readFileSync(join(".agents", "agents", "agent-turn.md"), "utf8")});
    send({event: "result", result: {status: "SUCCESS", structured_output: output}});
  }
});
`, { mode: 0o700 });
  }
  return { dir, fake, requests: () => readFileSync(requests, "utf8").trim().split("\n").map(JSON.parse) };
}

test("checks exactly three CLI accounts and persists fast settings for connected CLIs", async t => {
  const { dir, fake } = fixture(t);
  fake("codex", false);
  fake("agy");
  const first = new Providers(dir);
  t.after(() => first.close());
  const { providers, selected } = await first.snapshot();
  assert.deepEqual(providers.map(({ id, installed, connected }) => [id, installed, connected]), [
    ["openai", true, false], ["anthropic", false, false], ["google", true, true],
  ]);
  assert.equal(selected.provider, "google");
  await assert.rejects(first.select("anthropic"), /Sign in to Claude Code/);
  await assert.rejects(first.setFastMode("openai", true), /Sign in to Codex/);
  fake("codex");
  fake("claude");
  const connected = new Providers(dir);
  t.after(() => connected.close());
  await connected.setFastMode("openai", true);
  await connected.setFastMode("anthropic", true);
  await connected.setFastMode("openai", false);
  await connected.select("openai", "gpt-6-luna");
  const reopened = new Providers(dir);
  t.after(() => reopened.close());
  await reopened.refresh();
  assert.deepEqual(reopened.model, { provider: "openai", modelId: "gpt-6-luna" });
  assert.equal(reopened.fastEnabled("openai"), false);
  assert.equal(reopened.fastEnabled("anthropic"), true);
});

test("CLI turns retain Agent tools and enable web search only for execution", async t => {
  const { fake, requests } = fixture(t);
  for (const binary of ["codex", "claude", "agy"]) fake(binary);
  const models = cliModels(() => true);
  for (const provider of models.getProviders()) {
    const model = models.getModels(provider.id)[0];
    for (const name of ["read", "route_home", "dispatch_message"]) {
      const stream = models.streamSimple(model, {
        messages: [{ role: "user", content: "Test", timestamp: 0 }],
        tools: [{ name, description: "Fixture", parameters: { type: "object", properties: {} } }],
      });
      assert.equal((await stream.result()).stopReason, "stop");
      const captured = requests();
      if (provider.id === "openai") {
        const { thread, args } = captured.at(-2);
        assert.match(thread.baseInstructions, new RegExp(`"name":"${name}"`));
        assert.ok(args.includes(name === "read" ? 'web_search="live"' : 'web_search="disabled"'));
        assert.equal(thread.serviceTier, "fast");
      } else {
        const { prompt, args } = captured.at(-1);
        assert.match(prompt, new RegExp(`"name":"${name}"`));
        if (provider.id === "anthropic") assert.equal(args[args.indexOf("--tools") + 1], name === "read" ? "WebSearch,WebFetch" : "");
        else assert.equal(prompt.includes('"search_web"'), name === "read");
      }
    }
  }
});

test("CLI citations retain safe source URLs without duplicates", () => {
  const sources = new NativeSearchSources();
  sources.observe({ url: "https://example.com/claude", title: "Claude source" });
  sources.observe({ url: "https://example.com/other", title: "Other source" });
  sources.observe({ url: "javascript:alert(1)", title: "Unsafe" });
  const answer = { stopReason: "stop", content: [{ type: "text", text: "Answer [Claude source](https://example.com/claude)" }] };
  sources.append(answer);
  assert.equal(answer.content.at(-1).text, "\n\nSources: [Other source](https://example.com/other)");
});

test("reply suggestions use the current CLI fast preference without search", async t => {
  const { fake, requests } = fixture(t);
  fake("codex");
  const db = new DatabaseSync(":memory:");
  t.after(() => db.close());
  let fast = true;
  const suggestions = new PromptSuggestions(cliModels(() => fast), db);
  const messages = [{ role: "user", text: "Test" }, { role: "assistant", text: "Done" }];
  assert.equal(await suggestions.get("session", "one", messages), "Check the tests");
  const first = requests().at(-2);
  assert.equal(first.thread.serviceTier, "fast");
  assert.ok(first.args.includes('web_search="disabled"'));
  fast = false;
  assert.equal(await suggestions.get("session", "two", messages), "Check the tests");
  assert.equal(requests().at(-2).thread.serviceTier, undefined);
});

test("router and dispatcher use the fast utility model with low or disabled reasoning", { timeout: 15000 }, async t => {
  const dir = mkdtempSync(join(tmpdir(), "agent-utility-models-"));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const catalog = cliModels(() => false);
  for (const [provider, modelId, expected, thinkingLevel] of [
    ["openai", "gpt-6-astra", "gpt-6-luna", "off"],
    ["anthropic", "claude-fable-5-1", "claude-haiku-5-5", "low"],
    ["google", "gemini-4-argon", "gemini-3.5-flash-lite", "low"],
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


test("Home routing and dispatch keep reserved capacity under execution and dispatch load", { timeout: 10000 }, async () => {
  const model = cliModels(() => false).getModel("openai", "gpt-6-luna");
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
