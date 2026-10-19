import assert from "node:assert/strict";
import { existsSync, mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test, type TestContext } from "node:test";
import { BACKGROUND_CONTEXT } from "@earendil-works/chord/context";
import { createModels } from "@earendil-works/pi-ai";
import { fauxAssistantMessage, fauxProvider, type FauxResponseFactory } from "@earendil-works/pi-ai/providers/faux";
import { AssistantEntry, configure, defineExtension, defineTool, type Extension, type ToolRegistration } from "@earendil-works/pi-durable";
import { Type } from "typebox";
import { PiService } from "./pi.ts";
import { cancelDelegations, DelegationsDoc } from "./delegation.ts";
import { gate, toolAnswer } from "./test-support.ts";

async function fixture(t: TestContext, respond: FauxResponseFactory, extension?: Extension, names?: string[]) {
  const dir = mkdtempSync(join(tmpdir(), "assistant-inheritance-test-"));
  const faux = fauxProvider({ tokensPerSecond: 100000 });
  const models = createModels(); models.setProvider(faux.provider);
  const pi = await PiService.open(dir, { models, model: { provider: "faux", modelId: "faux-1" }, extensions: extension ? [extension] : [] });
  t.after(async () => { await pi.close(); rmSync(dir, { recursive: true, force: true }); });
  const agent = pi.agent("session", dir);
  const parent = await pi.harness.createConversation({ ownership: { kind: "ownerless" }, agent: {
    ...agent, extensions: [...agent.extensions, ...(extension ? [extension] : [])],
  } }, BACKGROUND_CONTEXT);
  if (names) {
    const available = (await parent.agent(BACKGROUND_CONTEXT)).tools;
    await parent.commit(tx => configure(tx, parent.id, { tools: available.filter(tool => names.includes(tool.name)) }), BACKGROUND_CONTEXT);
  }
  faux.setResponses(Array(30).fill(respond)); pi.harness.resume();
  const submission = await parent.submit({ type: "input", content: "Parent assignment" }, BACKGROUND_CONTEXT);
  return { pi, parent, dir, submission, finish: async () => {
    const result = await submission.wait(BACKGROUND_CONTEXT);
    assert.equal(result.status, "done");
    assert.ok(result.status === "done" && result.type === "input");
    await pi.harness.waitForIdle(BACKGROUND_CONTEXT);
    return pi.harness.commit(tx => tx.entry(AssistantEntry, result.answer), BACKGROUND_CONTEXT);
  } };
}

const input = (context: Parameters<FauxResponseFactory>[0]) => context.messages.filter(message => message.role === "user").at(-1)?.content;
const results = (context: Parameters<FauxResponseFactory>[0]) => context.messages.filter(message => message.role === "toolResult");

test("task-only delegation inherits native, custom, and computer tools with the parent's wrappers", async t => {
  let customCalls = 0; let computerCalls = 0;
  const extra = defineExtension({ name: "test-tools", tools: [defineTool({ name: "custom_tool", description: "Return project evidence", parameters: Type.Object({}),
    execute: async () => { customCalls++; return { output: [{ type: "text", text: "Custom evidence" }] }; } })],
    wraps: [{ tool: "computer_use", wrap: (tool: ToolRegistration): ToolRegistration => ({ ...tool, execute: async () => {
      computerCalls++; return { output: [{ type: "text", text: "Wrapped computer result" }] };
    } }) }] });
  const f = await fixture(t, context => {
    const answers = results(context);
    if (input(context) === "Worker assignment") {
      const prompt = JSON.stringify(context.messages.filter(message => message.role === "system"));
      assert.match(prompt, /worker assigned one focused task/);
      assert.doesNotMatch(prompt, /You own this persistent, user-visible conversation/);
      if (!answers.length) return toolAnswer("write", { path: "answer.mjs", content: "console.log(6 * 7)" });
      assert.equal(answers.at(-1)!.isError, false);
      if (answers.length === 1) return toolAnswer("edit", { path: "answer.mjs", edits: [{ oldText: "6 * 7", newText: "7 * 7" }] });
      if (answers.length === 2) return toolAnswer("bash", { command: "node answer.mjs" });
      if (answers.length === 3) { assert.match(JSON.stringify(answers.at(-1)!.content), /49/); return toolAnswer("custom_tool"); }
      if (answers.length === 4) return toolAnswer("computer_use", { code: "await cua.getState();" });
      assert.match(JSON.stringify(answers.at(-1)!.content), /Wrapped computer result/);
      return fauxAssistantMessage("Worker completed the changes and checks.");
    }
    if (!answers.length) return toolAnswer("delegate", { task: "Worker assignment" });
    return fauxAssistantMessage(answers.at(-1)!.toolName === "delegate" ? "Premature answer." : "Final answer uses worker findings.");
  }, extra);
  const closed: number[] = [];
  const closeComputer = f.pi.closeComputer.bind(f.pi);
  f.pi.closeComputer = id => { if (computerCalls) closed.push(id); closeComputer(id); };
  const final = await f.finish();
  assert.match(JSON.stringify(final), /Final answer uses worker findings/);
  const children = (await f.pi.harness.commit(tx => tx.scanConversations({}, 256), BACKGROUND_CONTEXT)).items.filter(child => child.owner);
  assert.equal(children.length, 1);
  const child = (await f.pi.harness.conversation(children[0].id, BACKGROUND_CONTEXT))!;
  const parentAgent = await f.parent.agent(BACKGROUND_CONTEXT); const childAgent = await child.agent(BACKGROUND_CONTEXT);
  assert.deepEqual(childAgent.tools.map(tool => tool.name), parentAgent.tools.map(tool => tool.name));
  assert.deepEqual(childAgent.model, parentAgent.model); assert.equal(childAgent.cwd, f.dir);
  assert.equal(readFileSync(join(f.dir, "answer.mjs"), "utf8"), "console.log(7 * 7)");
  assert.equal(customCalls, 1); assert.equal(computerCalls, 1);
  assert.ok(closed.includes(child.id), "Idle delegated conversations must close their computer-use clients");
});

test("inheritance preserves the parent's effective tool availability", async t => {
  const f = await fixture(t, context => {
    const answers = results(context);
    if (input(context) === "Worker assignment") {
      assert.deepEqual(context.messages.flatMap(message => message.role === "system" ? message.toolsAdded?.map(tool => tool.name) || [] : []),
        ["read", "delegate", "delegate_result", "delegate_cancel"]);
      if (!answers.length) return toolAnswer("write", { path: "unavailable.txt", content: "denied" });
      assert.equal(answers.at(-1)!.isError, true); assert.match(JSON.stringify(answers.at(-1)!.content), /not available/);
      return fauxAssistantMessage("Unavailable tool reported.");
    }
    return !answers.length ? toolAnswer("delegate", { task: "Worker assignment" }) : fauxAssistantMessage("Parent finished.");
  }, undefined, ["read", "delegate", "delegate_result", "delegate_cancel"]);
  await f.finish(); assert.equal(existsSync(join(f.dir, "unavailable.txt")), false);
});

test("workers can delegate and collect nested results before the parent's final answer", async t => {
  const f = await fixture(t, context => {
    const answers = results(context);
    if (input(context) === "Leaf assignment") {
      if (!answers.length) return toolAnswer("write", { path: "leaf.txt", content: "Leaf evidence" });
      return fauxAssistantMessage("Leaf evidence saved.");
    }
    const worker = input(context) === "Worker assignment";
    if (!answers.length) return toolAnswer("delegate", { task: worker ? "Leaf assignment" : "Worker assignment" });
    if (answers.at(-1)!.toolName === "delegate") return fauxAssistantMessage("Premature answer.");
    assert.match(JSON.stringify(answers.at(-1)!.content), /Leaf evidence/);
    return fauxAssistantMessage(worker ? "Worker incorporated Leaf evidence." : "Parent incorporated Leaf evidence.");
  });
  const final = await f.finish(); assert.match(JSON.stringify(final), /Parent incorporated Leaf evidence/);
  assert.equal(readFileSync(join(f.dir, "leaf.txt"), "utf8"), "Leaf evidence");
  const children = (await f.pi.harness.commit(tx => tx.scanConversations({}, 256), BACKGROUND_CONTEXT)).items.filter(child => child.owner);
  assert.equal(children.length, 2);
  for (const id of [f.parent.id, ...children.map(child => child.id)]) {
    const calls = (await f.pi.harness.snapshot(DelegationsDoc, id, BACKGROUND_CONTEXT))?.calls || {};
    for (const call of Object.values(calls)) assert.equal(call.status, "collected");
  }
});

test("stopping a parent joins workers and their nested workers", async t => {
  const pause = gate();
  const f = await fixture(t, context => {
    if (input(context) === "Leaf assignment") return toolAnswer("pause");
    if (!results(context).length) return toolAnswer("delegate", { task: input(context) === "Worker assignment" ? "Leaf assignment" : "Worker assignment" });
    return fauxAssistantMessage("Premature answer.");
  }, defineExtension({ name: "test-tools", tools: [pause.tool] }));
  await pause.started;
  await f.parent.abort(BACKGROUND_CONTEXT);
  await cancelDelegations(f.pi.harness, f.parent.id, BACKGROUND_CONTEXT);
  assert.equal((await f.pi.harness.inspect(BACKGROUND_CONTEXT)).tasks.length, 0);
  assert.equal(pause.calls(), 1);
});
