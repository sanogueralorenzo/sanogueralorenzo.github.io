import assert from "node:assert/strict";
import { mkdtempSync, realpathSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import { lazyStream } from "@earendil-works/pi-ai";
import { BACKGROUND_CONTEXT as context } from "@earendil-works/chord/context";
import { Assistant } from "../src/assistant.ts";

const model = { provider: "fixture", id: "fixture", api: "openai-responses", contextWindow: 1000000, maxTokens: 4096 };
const text = text => ({ type: "text", text });
const call = (name, args) => ({ type: "toolCall", id: crypto.randomUUID(), name, arguments: args });
const gate = () => Promise.withResolvers();
async function until(check, message = "condition") {
  for (let i = 0; i < 400; i++) { const value = await check(); if (value) return value; await new Promise(resolve => setTimeout(resolve, 10)); }
  throw new Error(`Timed out waiting for ${message}`);
}
async function fixture(t, respond, admission = () => ({ action: "start", dependsOn: [] }), storage = undefined) {
  const cwd = realpathSync(mkdtempSync(join(tmpdir(), "assistant-request-")));
  const calls = [];
  const runtime = { getModel: () => model, streamSimple: (selected, transcript, options = {}) => lazyStream(selected, async () => (async function* () {
    const timestamp = Date.now();
    const input = transcript.messages.filter(message => message.role === "user").at(-1)?.content;
    const names = (transcript.tools || transcript.messages.flatMap(message => message.toolsAdded || [])).map(tool => tool.name);
    let content;
    if (names.includes("admit_message")) {
      const request = JSON.parse(input);
      calls.push({ admission: request });
      content = [call("admit_message", await admission(request))];
    } else if (names.includes("route_home")) {
      const match = input.match(/Recent saved conversations: (.*)\nRecent Home exchanges/);
      const sessions = JSON.parse(match[1]);
      content = [call("route_home", { mode: "continue", sessionId: sessions[0].id })];
    } else {
      calls.push({ input, transcript });
      content = await respond(input, transcript, options.signal);
    }
    const message = { role: "assistant", content, api: model.api, provider: model.provider, model: model.id,
      usage: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, totalTokens: 0, cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0 } },
      stopReason: content.some(part => part.type === "toolCall") ? "toolUse" : "stop", timestamp };
    yield { type: "done", reason: message.stopReason, message };
  })()) };
  let app = await Assistant.open(join(cwd, "state"), cwd, { models: runtime, model: { provider: model.provider, modelId: model.id }, storage });
  t.after(async () => { await app.shutdown(); rmSync(cwd, { recursive: true, force: true }); });
  const receipt = id => {
    const source = app.state.home.messages.find(message => message.id === id);
    const session = app.state.home.sessions[0];
    return app.pi.harness.commit(tx => tx.submissionByRequest(session.conversationId, source.requestId || source.id), context);
  };
  return { get app() { return app; }, calls, receipt, restart: async () => {
    await app.shutdown();
    app = await Assistant.open(join(cwd, "state"), cwd, { models: runtime, model: { provider: model.provider, modelId: model.id }, storage });
  } };
}
function block(signal, pending) {
  return new Promise((resolve, reject) => {
    const abort = () => reject(signal.reason || new Error("aborted"));
    signal?.addEventListener("abort", abort, { once: true });
    pending.promise.then(value => { signal?.removeEventListener("abort", abort); resolve(value); });
  });
}

test("independent Home follow-ups finish while an earlier coordinator is busy", { timeout: 15000 }, async t => {
  const slow = gate();
  const f = await fixture(t, async (input, _transcript, signal) => input.endsWith("Slow weather") ? block(signal, slow) : [text("Market result")]);
  await f.app.submitHome("Slow weather", "weather");
  await until(() => f.calls.find(call => call.input?.endsWith("Slow weather")), "first execution");
  await f.app.submitHome("Stock market", "market");
  await until(async () => (await f.receipt("market"))?.status === "done", "independent completion");
  assert.equal((await f.receipt("weather")).status, "placed");
  const data = f.app.snapshot();
  assert.equal(data.sessions.length, 1);
  assert.equal(data.entries.find(entry => entry.sourceId === "market").updates.at(-1).text, "Market result");
  slow.resolve([text("Weather result")]);
  await until(async () => (await f.receipt("weather"))?.status === "done");
  const completed = f.app.snapshot().entries;
  assert.ok(completed.find(entry => entry.sourceId === "weather").updatedAt >= completed.find(entry => entry.sourceId === "market").updatedAt);
  const transcript = f.app.transcript(data.sessions[0].id).messages;
  assert.deepEqual(transcript.filter(message => message.role === "assistant").map(message => message.text), ["Market result", "Weather result"]);
  assert.equal(f.calls.filter(call => call.input?.endsWith("Stock market")).length, 1);
});

test("dependent follow-ups wait for results and inherit the finished prerequisite", { timeout: 15000 }, async t => {
  const slow = gate();
  const f = await fixture(t, async (input, transcript, signal) => {
    if (input.endsWith("Slow weather")) return block(signal, slow);
    assert.ok(transcript.messages.some(message => message.role === "assistant" && message.content.some(part => part.text === "Weather result")));
    return [text("Buy groceries before the rain")];
  }, () => ({ action: "start", dependsOn: ["weather"] }));
  await f.app.submitHome("Slow weather", "weather");
  await until(() => f.calls.find(call => call.input?.endsWith("Slow weather")));
  await f.app.submitSession(f.app.snapshot().sessions[0].id, "Should I buy groceries?", "followUp", { id: "groceries" });
  await until(async () => (await f.receipt("groceries"))?.status === "queued");
  const queued = f.app.snapshot().turns.find(turn => turn.id === "groceries");
  assert.deepEqual(queued.dependsOn, ["weather"]);
  assert.equal(f.calls.some(call => call.input?.endsWith("Should I buy groceries?")), false);
  slow.resolve([text("Weather result")]);
  await until(async () => (await f.receipt("groceries"))?.status === "done");
});

test("failed prerequisites fail dependent tasks without executing them", { timeout: 15000 }, async t => {
  const slow = gate();
  const f = await fixture(t, (input, _transcript, signal) => input.endsWith("Slow weather") ? block(signal, slow) : [text("Must not run")],
    () => ({ action: "start", dependsOn: ["weather"] }));
  await f.app.submitHome("Slow weather", "weather");
  await until(() => f.calls.find(call => call.input?.endsWith("Slow weather")));
  await f.app.submitSession(f.app.snapshot().sessions[0].id, "Dependent", "followUp", { id: "dependent" });
  await until(async () => (await f.receipt("dependent"))?.status === "queued");
  await f.app.pi.harness.abortTask(f.app.state.home.messages.find(message => message.id === "weather").workTaskId, context);
  await until(async () => (await f.receipt("dependent"))?.status === "unanswered");
  assert.match(String((await f.receipt("dependent")).detail), /Prerequisite.*did not complete/);
  assert.equal(f.calls.some(call => call.input?.endsWith("Dependent")), false);
});

test("revision cancels its target and redirects waiting dependents before replacement runs", { timeout: 15000 }, async t => {
  const slow = gate();
  const f = await fixture(t, async (input, transcript, signal) => {
    if (input.endsWith("Taipei weather")) return block(signal, slow);
    if (input.endsWith("Groceries")) {
      assert.ok(transcript.messages.some(message => message.role === "assistant" && message.content.some(part => part.text === "Kaohsiung result")));
      return [text("Groceries based on Kaohsiung")];
    }
    return [text("Kaohsiung result")];
  }, request => request.message === "Groceries" ? { action: "start", dependsOn: ["weather"] } : { action: "revise", targetId: "weather" });
  await f.app.submitHome("Taipei weather", "weather");
  await until(() => f.calls.some(call => call.input?.endsWith("Taipei weather")));
  const sessionId = f.app.snapshot().sessions[0].id;
  await f.app.submitSession(sessionId, "Groceries", "followUp", { id: "groceries" });
  await until(async () => (await f.receipt("groceries"))?.status === "queued");
  await f.app.submitSession(sessionId, "Actually Kaohsiung", "followUp", { id: "revision" });
  await until(async () => (await f.receipt("groceries"))?.status === "done");
  assert.equal((await f.receipt("weather")).reason, "superseded");
  assert.deepEqual(f.app.state.home.messages.find(message => message.id === "groceries").dependsOn, ["revision"]);
  slow.resolve([text("Stale Taipei result")]);
  assert.equal(f.app.transcript(sessionId).messages.some(message => message.text.includes("Stale Taipei result")), false);
});

test("cancellation stops only the selected task and independent work continues", { timeout: 15000 }, async t => {
  const weather = gate(), market = gate();
  const f = await fixture(t, (input, _transcript, signal) => input.endsWith("Weather") ? block(signal, weather)
    : input.endsWith("Market") ? block(signal, market) : [text("Cancelled weather")],
    request => request.message === "Stop weather" ? { action: "cancel", targetId: "weather" } : { action: "start", dependsOn: [] });
  await f.app.submitHome("Weather", "weather");
  await until(() => f.calls.some(call => call.input?.endsWith("Weather")));
  const id = f.app.snapshot().sessions[0].id;
  await f.app.submitSession(id, "Market", "followUp", { id: "market" });
  await until(() => f.calls.some(call => call.input?.endsWith("Market")));
  await f.app.submitSession(id, "Stop weather", "followUp", { id: "cancel" });
  await until(async () => (await f.receipt("cancel"))?.status === "done");
  assert.equal((await f.receipt("weather")).status, "unanswered");
  assert.equal((await f.receipt("market")).status, "placed");
  market.resolve([text("Market finished")]);
  await until(async () => (await f.receipt("market"))?.status === "done");
});

test("Stop preserves queued dependencies and Continue resumes them after the stopped task", { timeout: 15000 }, async t => {
  const slow = gate();
  let attempts = 0;
  const f = await fixture(t, (input, _transcript, signal) => input.endsWith("Weather") && ++attempts === 1 ? block(signal, slow)
    : [text(input.endsWith("Weather") ? "Weather resumed" : "Dependent finished")], () => ({ action: "start", dependsOn: ["weather"] }));
  await f.app.submitHome("Weather", "weather");
  await until(() => f.calls.some(call => call.input?.endsWith("Weather")));
  const id = f.app.snapshot().sessions[0].id;
  await f.app.submitSession(id, "Dependent", "followUp", { id: "dependent" });
  await until(async () => (await f.receipt("dependent"))?.status === "queued");
  await f.app.stop(id);
  assert.equal((await f.receipt("weather")).reason, "aborted");
  assert.equal((await f.receipt("dependent")).status, "queued");
  const entry = f.app.snapshot().entries.find(entry => entry.sourceId === "weather");
  assert.equal(entry.status, "interrupted");
  await f.app.resume(entry.id);
  await until(async () => (await f.receipt("dependent"))?.status === "done");
  assert.equal((await f.receipt("weather")).status, "done");
  assert.equal(attempts, 2);
});

test("restart resumes in-flight work and durable dependency waits without duplicate replies", { timeout: 15000 }, async t => {
  const slow = gate();
  let attempts = 0;
  const f = await fixture(t, (input, _transcript, signal) => input.endsWith("Weather") && ++attempts === 1 ? block(signal, slow)
    : [text(input.endsWith("Weather") ? "Weather after restart" : "Dependent after restart")], () => ({ action: "start", dependsOn: ["weather"] }));
  await f.app.submitHome("Weather", "weather");
  await until(() => f.calls.some(call => call.input?.endsWith("Weather")));
  const id = f.app.snapshot().sessions[0].id;
  await f.app.submitSession(id, "Dependent", "followUp", { id: "dependent" });
  await until(async () => (await f.receipt("dependent"))?.status === "queued");
  await f.restart();
  await until(async () => (await f.receipt("dependent"))?.status === "done");
  assert.deepEqual(f.app.transcript(id).messages.filter(message => message.role === "assistant").map(message => message.text), ["Weather after restart", "Dependent after restart"]);
});

test("a coordinator waiting for delegated work does not block independent requests", { timeout: 15000 }, async t => {
  const slow = gate();
  const f = await fixture(t, (input, transcript, signal) => {
    if (input === "Hold worker") return block(signal, slow);
    if (input.endsWith("Delegated work")) {
      const results = transcript.messages.filter(message => message.role === "toolResult");
      if (!results.some(result => result.toolName === "delegate")) return [call("delegate", { task: "Hold worker" })];
      return [text(results.some(result => result.toolName === "delegate_result") ? "Collected worker result" : "Premature completion")];
    }
    return [text("Independent finished")];
  });
  await f.app.submitHome("Delegated work", "delegated");
  await until(() => f.calls.some(call => call.input === "Hold worker"));
  await f.app.submitSession(f.app.snapshot().sessions[0].id, "Independent", "followUp", { id: "independent" });
  await until(async () => (await f.receipt("independent"))?.status === "done");
  assert.equal((await f.receipt("delegated")).status, "placed");
  slow.resolve([text("Worker done")]);
  await until(async () => (await f.receipt("delegated"))?.status === "done");
  assert.ok(f.app.snapshot().entries.find(entry => entry.sourceId === "delegated").updates.some(update => update.text === "Collected worker result"));
});

test("deleting a queued task prevents execution and fails its dependents explicitly", { timeout: 15000 }, async t => {
  const slow = gate();
  const f = await fixture(t, (input, _transcript, signal) => input.endsWith("Weather") ? block(signal, slow) : [text("Must not execute")],
    request => ({ action: "start", dependsOn: [request.message === "First dependent" ? "weather" : "first"] }));
  await f.app.submitHome("Weather", "weather");
  await until(() => f.calls.some(call => call.input?.endsWith("Weather")));
  const sessionId = f.app.snapshot().sessions[0].id;
  await f.app.submitSession(sessionId, "First dependent", "followUp", { id: "first" });
  await until(async () => (await f.receipt("first"))?.status === "queued");
  await f.app.submitSession(sessionId, "Second dependent", "followUp", { id: "second" });
  await until(async () => (await f.receipt("second"))?.status === "queued");
  await f.app.dequeue(sessionId, "first");
  await until(async () => (await f.receipt("second"))?.status === "unanswered");
  assert.equal(f.app.snapshot().messages.some(message => message.id === "first"), false);
  assert.equal(f.calls.some(call => call.input?.endsWith("First dependent")), false);
  slow.resolve([text("Weather result")]);
});

test("admission rejects self or future dependencies and only sees older tasks", { timeout: 15000 }, async t => {
  const slow = gate();
  let decisions = 0;
  const f = await fixture(t, (input, _transcript, signal) => input.endsWith("Weather") ? block(signal, slow) : [text("Independent result")], request => {
    if (request.message === "First follow-up") {
      const attempt = decisions++;
      if (attempt < 2) return { action: "start", dependsOn: [attempt === 0 ? "later" : "first"] };
    }
    return { action: "start", dependsOn: [] };
  });
  await f.app.submitHome("Weather", "weather");
  await until(() => f.calls.some(call => call.input?.endsWith("Weather")));
  const id = f.app.snapshot().sessions[0].id;
  await f.app.submitSession(id, "First follow-up", "followUp", { id: "first" });
  await f.app.submitSession(id, "Second follow-up", "followUp", { id: "later" });
  await until(async () => (await f.receipt("later"))?.status === "done");
  assert.deepEqual(f.app.state.home.messages.find(message => message.id === "first").dependsOn, []);
  assert.equal(decisions, 3);
  for (const { admission } of f.calls.filter(call => call.admission?.message === "First follow-up"))
    assert.deepEqual(admission.tasks.map(task => task.taskId), ["weather"]);
  slow.resolve([text("Weather result")]);
});

test("explicit edits revise the selected running task when several requests are active", { timeout: 15000 }, async t => {
  const weather = gate(), market = gate();
  const f = await fixture(t, (input, _transcript, signal) => input.endsWith("Weather") ? block(signal, weather)
    : input.endsWith("Market") ? block(signal, market) : [text("Revised weather")]);
  await f.app.submitHome("Weather", "weather");
  await until(() => f.calls.some(call => call.input?.endsWith("Weather")));
  const sessionId = f.app.snapshot().sessions[0].id;
  await f.app.submitSession(sessionId, "Market", "followUp", { id: "market" });
  await until(() => f.calls.some(call => call.input?.endsWith("Market")));
  await f.app.submitSession(sessionId, "Different weather", "steer", { id: "edit", editOfId: "weather" });
  await until(async () => (await f.receipt("edit"))?.status === "done");
  assert.equal((await f.receipt("weather")).reason, "superseded");
  assert.equal((await f.receipt("market")).status, "placed");
  market.resolve([text("Market result")]);
});

test("Stop cancels workers below earlier coordinator generation rounds", { timeout: 15000 }, async t => {
  const slow = gate();
  const f = await fixture(t, (input, transcript, signal) => {
    if (input === "Hold worker") return block(signal, slow);
    return transcript.messages.some(message => message.role === "toolResult" && message.toolName === "delegate")
      ? [text("Premature completion")] : [call("delegate", { task: "Hold worker" })];
  });
  await f.app.submitHome("Delegated work", "delegated");
  await until(() => f.calls.some(call => call.input === "Hold worker"));
  await f.app.stop(f.app.snapshot().sessions[0].id);
  assert.equal((await f.receipt("delegated")).reason, "aborted");
  const records = await f.app.pi.harness.commit(tx => tx.scanTasks({}, 100), context);
  assert.deepEqual(records.items.filter(task => task.state.status !== "terminal"), []);
});

test("cancellation does not claim to stop a task that finished during admission", { timeout: 15000 }, async t => {
  const slow = gate(), deciding = gate(), release = gate();
  const f = await fixture(t, (input, _transcript, signal) => input.endsWith("Weather") ? block(signal, slow) : [text("Already finished")], async () => {
    deciding.resolve();
    await release.promise;
    return { action: "cancel", targetId: "weather" };
  });
  await f.app.submitHome("Weather", "weather");
  await until(() => f.calls.some(call => call.input?.endsWith("Weather")));
  await f.app.submitSession(f.app.snapshot().sessions[0].id, "Stop weather", "followUp", { id: "cancel" });
  await deciding.promise;
  slow.resolve([text("Weather completed")]);
  await until(async () => (await f.receipt("weather"))?.status === "done");
  release.resolve();
  await until(async () => (await f.receipt("cancel"))?.status === "done");
  assert.equal(f.app.state.home.messages.find(message => message.id === "weather").replacedBy, undefined);
  assert.match(f.calls.find(call => call.input?.includes("Original message: Stop weather")).input, /already finished before cancellation/);
});
