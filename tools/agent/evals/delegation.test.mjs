import assert from "node:assert/strict";
import { mkdtempSync, mkdirSync, existsSync, readFileSync, realpathSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import { lazyStream } from "@earendil-works/pi-ai";
import { BACKGROUND_CONTEXT as context } from "@earendil-works/chord/context";
import { configure, MemoryStorage } from "@earendil-works/pi-durable";
import { PiService } from "../src/pi.ts";
import { DelegationsDoc } from "../src/delegation.ts";

const model = { provider: "fixture", id: "fixture", api: "openai-responses", contextWindow: 1000000, maxTokens: 4096 };
const toolCall = (name, args) => ({ type: "toolCall", id: crypto.randomUUID(), name, arguments: args });
const text = value => ({ type: "text", text: value });

async function fixture(t, respond) {
  const cwd = realpathSync(mkdtempSync(join(tmpdir(), "agent-delegation-")));
  const runtime = {
    getModel: () => model,
    streamSimple: (selected, transcript) => lazyStream(selected, async () => (async function* () {
      const content = respond(transcript.messages);
      const message = { role: "assistant", content, api: model.api, provider: model.provider, model: model.id,
        usage: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, totalTokens: 0,
          cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0 } },
        stopReason: content.some(part => part.type === "toolCall") ? "toolUse" : "stop", timestamp: Date.now() };
      yield { type: "done", reason: message.stopReason, message };
    })()),
  };
  const service = await PiService.open(join(cwd, "state"), {
    models: runtime, model: { provider: model.provider, modelId: model.id }, storage: new MemoryStorage(),
  });
  t.after(async () => { await service.close(); rmSync(cwd, { recursive: true, force: true }); });
  const session = await service.harness.root(context, { agent: service.agent("coordinator", cwd) });
  return { cwd, service, session };
}

test("coordinators reject file writes, shell commands, and computer control", { timeout: 15000 }, async t => {
  const { cwd, session } = await fixture(t, messages => messages.some(message => message.role === "toolResult")
    ? [text("Rejected execution")]
    : [toolCall("write", { path: "forbidden.txt", content: "unexpected" }),
      toolCall("bash", { command: "touch forbidden.txt" }),
      toolCall("computer_use", { code: "await cua.getState()" })]);
  const agent = await session.agent(context);
  assert.ok(["read", "grep", "find", "ls", "delegate", "delegate_result", "delegate_cancel"].every(name => agent.tools.some(tool => tool.name === name)));
  assert.ok(["write", "edit", "bash", "computer_use"].every(name => !agent.tools.some(tool => tool.name === name)));
  const result = await (await session.submit({ type: "input", content: "Attempt execution" }, context)).wait(context);
  assert.equal(result.status, "done");
  const transcript = await session.context(context);
  const rejected = transcript.messages.filter(message => message.role === "toolResult");
  assert.equal(rejected.length, 3);
  assert.ok(rejected.every(message => message.isError));
  assert.equal(existsSync(join(cwd, "forbidden.txt")), false);
});

test("workers execute and review with their own tools and collect nested work before finishing", { timeout: 15000 }, async t => {
  const { cwd, service, session } = await fixture(t, messages => {
    const request = messages.find(message => message.role === "user").content;
    const results = messages.filter(message => message.role === "toolResult");
    const called = name => results.some(message => message.toolName === name);
    if (request === "Coordinate") {
      const collected = results.filter(message => message.toolName === "delegate_result").length;
      const delegated = results.filter(message => message.toolName === "delegate").length;
      if (delegated === 0) return [toolCall("delegate", { task: "Implement" })];
      if (collected === 1 && delegated === 1) return [toolCall("delegate", { task: "Review" })];
      return [text(collected === 2 ? "Implementation verified" : "Premature completion")];
    }
    if (request === "Implement") return called("delegate")
      ? [text("Implementation delegated")]
      : [toolCall("delegate", { task: "Write and check" })];
    if (request === "Write and check") {
      if (!called("working_directory")) return [toolCall("working_directory", { path: "target" })];
      if (!called("write")) return [toolCall("write", { path: "result.txt", content: "verified\n" })];
      if (!called("bash")) return [toolCall("bash", { command: "cat result.txt" })];
      return [text("Wrote result.txt and checked its contents")];
    }
    assert.equal(request, "Review");
    return called("read") ? [text("Independently verified result.txt")] : [toolCall("read", { path: "target/result.txt" })];
  });
  mkdirSync(join(cwd, "target"));
  // Workers must get their own capabilities even when the parent has explicit tool filters.
  const parent = await session.agent(context);
  await service.harness.commit(tx => configure(tx, session.id, { tools: parent.tools, modelTools: parent.tools }), context);
  const result = await (await session.submit({ type: "input", content: "Coordinate" }, context)).wait(context);
  assert.equal(result.status, "done");
  assert.equal(readFileSync(join(cwd, "target/result.txt"), "utf8"), "verified\n");
  assert.equal((await session.agent(context)).cwd, cwd);
  const transcript = await session.context(context);
  assert.equal(transcript.messages.at(-1).content[0].text, "Implementation verified");
  const records = await service.harness.commit(tx => tx.scanConversations({}, 20), context);
  assert.equal(records.items.length, 4);
  let collected = 0;
  for (const record of records.items) {
    const conversation = await service.harness.conversation(record.id, context);
    const agent = await conversation.agent(context);
    assert.deepEqual(agent.model, parent.model);
    assert.equal(agent.thinkingLevel, parent.thinkingLevel);
    if (record.id !== session.id) {
      assert.ok(["write", "edit", "bash", "computer_use", "delegate"].every(name => agent.tools.some(tool => tool.name === name)));
      assert.equal(agent.extensions.some(extension => extension.name === "agent-coordinator"), false);
      assert.ok([cwd, join(cwd, "target")].includes(agent.cwd));
      const workerTranscript = await conversation.context(context);
      assert.ok(workerTranscript.messages.filter(message => message.role === "toolResult").every(message => !message.isError));
    }
    const calls = (await service.harness.snapshot(DelegationsDoc, record.id, context))?.calls || {};
    for (const call of Object.values(calls)) { assert.equal(call.status, "collected"); collected++; }
  }
  assert.equal(collected, 3);
});
