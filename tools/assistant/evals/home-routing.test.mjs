import assert from "node:assert/strict";
import { mkdtempSync, realpathSync, rmSync } from "node:fs";
import { homedir, tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import { lazyStream } from "@earendil-works/pi-ai";
import { BACKGROUND_CONTEXT as context } from "@earendil-works/chord/context";
import { MemoryStorage } from "@earendil-works/pi-durable";
import { Assistant } from "../src/assistant.ts";

test("the first Home message skips routing; a follow-up routes to the new session", { timeout: 15000 }, async t => {
  const cwd = realpathSync(mkdtempSync(join(tmpdir(), "assistant-routing-")));
  const model = { provider: "fixture", id: "fixture", api: "openai-responses", contextWindow: 1000000, maxTokens: 4096 };
  const requests = [];
  const firstGeneration = Promise.withResolvers();
  let app;
  const models = {
    getModel: () => model,
    streamSimple: (selected, transcript) => lazyStream(selected, async () => (async function* () {
      const tools = transcript.tools || transcript.messages.flatMap(message => message.role === "system" ? message.toolsAdded || [] : []);
      const routing = tools.some(tool => tool.name === "route_home");
      requests.push({ routing, messages: transcript.messages });
      if (!routing) firstGeneration.resolve(transcript.messages);
      const content = routing
        ? [{ type: "toolCall", id: crypto.randomUUID(), name: "route_home", arguments: { mode: "continue", sessionId: app.snapshot().sessions[0].id } }]
        : [{ type: "text", text: "Done" }];
      const message = { role: "assistant", content, api: model.api, provider: model.provider, model: model.id,
        usage: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, totalTokens: 0,
          cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0 } },
        stopReason: routing ? "toolUse" : "stop", timestamp: Date.now() };
      yield { type: "done", reason: message.stopReason, message };
    })()),
  };
  app = await Assistant.open(join(cwd, "state"), cwd, {
    models, model: { provider: model.provider, modelId: model.id }, storage: new MemoryStorage(),
  });
  t.after(async () => { await app.shutdown(); rmSync(cwd, { recursive: true, force: true }); });
  app.suggestions.get = async () => null;

  const original = "  Help me\n  plan a project  ";
  const first = await app.submitHome(original, "first");
  await app.pi.harness.waitForTask(first.taskId, context);
  const initial = app.snapshot();
  assert.equal(initial.sessions.length, 1);
  assert.equal(initial.sessions[0].title, "Help me plan a project");
  assert.equal(initial.sessions[0].cwd, homedir());
  assert.equal(requests.filter(request => request.routing).length, 0);
  const messages = await firstGeneration.promise;
  assert.ok(messages.some(message => message.role === "user" && message.content === original));

  const followUp = await app.submitHome("Continue that plan", "second");
  await app.pi.harness.waitForTask(followUp.taskId, context);
  const snapshot = app.snapshot();
  assert.equal(requests.filter(request => request.routing).length, 1);
  assert.equal(snapshot.sessions.length, 1);
  assert.ok(snapshot.entries.every(entry => entry.sessionId === snapshot.sessions[0].id));
  assert.ok(snapshot.messages.every(message => message.status === "routed" && message.submissionId !== undefined));
});
