import assert from "node:assert/strict";
import { existsSync, mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test, type TestContext } from "node:test";
import { BACKGROUND_CONTEXT } from "@earendil-works/chord/context";
import type { JsonValue } from "@earendil-works/chord";
import { createModels, lazyStream, type Models } from "@earendil-works/pi-ai";
import { fauxAssistantMessage, fauxProvider, fauxToolCall, type FauxResponseFactory } from "@earendil-works/pi-ai/providers/faux";
import { configure, defineTool, MemoryStorage } from "@earendil-works/pi-durable";
import { Type } from "typebox";
import { PiService, roleExtension } from "./pi.ts";
import { WorkerPermissionsDoc } from "./worker-permissions.ts";
import { toolAnswer } from "./test-support.ts";

async function delegated(t: TestContext, args: Record<string, JsonValue>, worker: FauxResponseFactory,
  options: { parentTools?: string[]; exposeWorkerTools?: boolean } = {}) {
  const dir = mkdtempSync(join(tmpdir(), "assistant-permissions-test-"));
  const faux = fauxProvider({ provider: "openai-codex", tokensPerSecond: 100000 });
  const runtime = createModels(); runtime.setProvider(faux.provider);
  const requests: { input: unknown; tools: { type: string; name?: string }[] }[] = [];
  // Exercise the production payload hook without a network request. Include an existing
  // hosted tool to prove baseline search is offered once, regardless of extra grants.
  const models: Models = new Proxy(runtime, { get(target, key) {
    if (key === "streamSimple") return ((model, context, options) => lazyStream(model, async () => {
      const tools = context.messages.flatMap(message => message.role === "system" ? message.toolsAdded || [] : []);
      const payload = await options?.onPayload?.({ tools: [...tools.map(tool => ({ type: "function", name: tool.name })), { type: "web_search" }] }, model) as { tools: { type: string; name?: string }[] };
      requests.push({ input: context.messages.filter(message => message.role === "user").at(-1)?.content, tools: payload.tools });
      return target.streamSimple(model, context, options);
    })) as Models["streamSimple"];
    const value = Reflect.get(target, key);
    return typeof value === "function" ? value.bind(target) : value;
  } });
  const pi = await PiService.open(dir, { models, model: { provider: "openai-codex", modelId: "faux-1" }, storage: new MemoryStorage() });
  t.after(async () => { await pi.close(); rmSync(dir, { recursive: true, force: true }); });
  const parent = await pi.harness.createConversation({ ownership: { kind: "ownerless" }, agent: pi.agent("session", dir) }, BACKGROUND_CONTEXT);
  if (options.parentTools) {
    const agent = await parent.agent(BACKGROUND_CONTEXT);
    await parent.commit(tx => configure(tx, parent.id, { tools: agent.tools.filter(tool => options.parentTools!.includes(tool.name)) }), BACKGROUND_CONTEXT);
  }
  let result: { isError?: boolean; content: unknown } | undefined;
  const respond: FauxResponseFactory = async (context, streamOptions, state, model) => {
    const input = context.messages.filter(message => message.role === "user").at(-1)?.content;
    if (input === "Worker assignment") {
      if (options.exposeWorkerTools) {
        const children = await pi.harness.commit(tx => tx.scanConversations({}, 256), BACKGROUND_CONTEXT);
        const child = children.items.find(child => child.owner)!;
        await pi.harness.commit(tx => configure(tx, child.id, { tools: roleExtension("worker").tools! }), BACKGROUND_CONTEXT);
      }
      return worker(context, streamOptions, state, model);
    }
    const last = context.messages.filter(message => message.role === "toolResult").at(-1);
    if (!last) return toolAnswer("delegate", args);
    result = last;
    return fauxAssistantMessage("Parent finished.");
  };
  faux.setResponses(Array(20).fill(respond));
  pi.harness.resume();
  const settled = await (await parent.submit({ type: "input", content: "Parent assignment" }, BACKGROUND_CONTEXT)).wait(BACKGROUND_CONTEXT);
  assert.equal(settled.status, "done");
  await pi.harness.waitForIdle(BACKGROUND_CONTEXT);
  const children = (await pi.harness.commit(tx => tx.scanConversations({}, 256), BACKGROUND_CONTEXT)).items.filter(child => child.owner);
  return { pi, parent, dir, children, requests, result: result! };
}

test("delegate rejects missing, unknown, and duplicate extra permissions before creating a worker", async t => {
  for (const permissions of [undefined, ["unknown"], ["files.read"], ["web.search"], ["files.write", "files.write"]]) {
    const f = await delegated(t, { task: "Worker assignment", ...(permissions && { permissions }) }, () => { throw new Error("Rejected worker must not start"); });
    assert.equal(f.result.isError, true, JSON.stringify(permissions));
    assert.equal(f.children.length, 0);
  }
});

test("an empty extra-permissions list provides inspection and search while rejecting fabricated writes", async t => {
  const f = await delegated(t, { task: "Worker assignment", permissions: [] }, context => {
    const results = context.messages.filter(message => message.role === "toolResult");
    if (!results.length) return toolAnswer("write", { path: "denied.txt", content: "denied" });
    assert.equal(results.at(-1)!.isError, true);
    return fauxAssistantMessage("Reasoned from context.");
  });
  const worker = f.requests.find(request => request.input === "Worker assignment")!;
  assert.deepEqual(worker.tools.map(tool => tool.name || tool.type), ["read", "grep", "find", "ls", "web_search"]);
  assert.equal(existsSync(join(f.dir, "denied.txt")), false);
  assert.deepEqual((await f.pi.harness.snapshot(WorkerPermissionsDoc, f.children[0].id, BACKGROUND_CONTEXT))?.permissions, []);
  assert.match(JSON.stringify(f.result.content), /Reasoned from context/);
});

test("read-only workers cannot write or run shell commands even if their tools are accidentally exposed", async t => {
  const f = await delegated(t, { task: "Worker assignment", permissions: [] }, context => {
    const results = context.messages.filter(message => message.role === "toolResult");
    if (!results.length) return fauxAssistantMessage([
      fauxToolCall("write", { path: "denied.txt", content: "denied" }),
      fauxToolCall("bash", { command: "printf denied > denied.txt" }),
    ], { stopReason: "toolUse" });
    assert.equal(results.length, 2);
    for (const result of results) {
      assert.equal(result.isError, true);
      assert.match(JSON.stringify(result.content), /Worker permission denied/);
    }
    return fauxAssistantMessage("Missing edit and command access.");
  }, { exposeWorkerTools: true });
  assert.equal(existsSync(join(f.dir, "denied.txt")), false);
  assert.deepEqual(f.requests.find(request => request.input === "Worker assignment")!.tools.filter(tool => tool.type === "function").map(tool => tool.name), ["read", "grep", "find", "ls"]);
});

test("workers with file grants can write and edit without command access", async t => {
  const f = await delegated(t, { task: "Worker assignment", permissions: ["files.write"] }, context => {
    const results = context.messages.filter(message => message.role === "toolResult");
    if (!results.length) return toolAnswer("write", { path: "result.txt", content: "before" });
    assert.equal(results.at(-1)!.isError, false);
    return results.length === 1 ? toolAnswer("edit", { path: "result.txt", edits: [{ oldText: "before", newText: "after" }] }) : fauxAssistantMessage("Edited result.txt.");
  });
  assert.equal(readFileSync(join(f.dir, "result.txt"), "utf8"), "after");
  assert.match(JSON.stringify(f.result.content), /Edited result.txt/);
  const tools = f.requests.find(request => request.input === "Worker assignment")!.tools.map(tool => tool.name);
  assert.ok(tools.includes("write") && tools.includes("edit") && !tools.includes("bash"));
});

test("a command grant supplies available editing tools and runs commands in the inherited directory", async t => {
  const f = await delegated(t, { task: "Worker assignment", permissions: ["commands.run"] }, context => {
    const results = context.messages.filter(message => message.role === "toolResult");
    if (!results.length) return toolAnswer("bash", { command: "printf command > result.txt" });
    assert.equal(results.at(-1)!.isError, false);
    return fauxAssistantMessage("Command completed.");
  });
  assert.equal(readFileSync(join(f.dir, "result.txt"), "utf8"), "command");
  assert.match(JSON.stringify(f.result.content), /Command completed/);
  const tools = f.requests.find(request => request.input === "Worker assignment")!.tools.map(tool => tool.name);
  assert.ok(tools.includes("bash") && tools.includes("write") && tools.includes("edit"));
});

test("the production provider supplies hosted search for every extra-permission choice", async t => {
  for (const permissions of [[], ["files.write"], ["commands.run"]]) {
    const f = await delegated(t, { task: "Worker assignment", permissions }, () => fauxAssistantMessage("Finished."));
    const count = (input: string) => f.requests.find(request => request.input === input)!.tools.filter(tool => tool.type === "web_search").length;
    assert.equal(count("Parent assignment"), 1);
    assert.equal(count("Worker assignment"), 1);
  }
});

test("a parent cannot grant native permissions beyond its own available tools", async t => {
  const f = await delegated(t, { task: "Worker assignment", permissions: ["files.write"] }, () => { throw new Error("Rejected worker must not start"); },
    { parentTools: ["read", "grep", "find", "ls", "delegate", "delegate_result", "delegate_cancel"] });
  assert.equal(f.result.isError, true);
  assert.match(JSON.stringify(f.result.content), /Parent cannot grant files.write/);
  assert.equal(f.children.length, 0);
});

test("baseline inspection inherits only the parent's available tools and enforces that exact set", async t => {
  const f = await delegated(t, { task: "Worker assignment", permissions: [] }, context => {
    const results = context.messages.filter(message => message.role === "toolResult");
    if (!results.length) return toolAnswer("ls", { path: "." });
    assert.equal(results.at(-1)!.isError, true);
    assert.match(JSON.stringify(results.at(-1)!.content), /Worker permission denied/);
    return fauxAssistantMessage("Unavailable inspection tool reported.");
  }, { parentTools: ["read", "delegate", "delegate_result", "delegate_cancel"], exposeWorkerTools: true });
  assert.deepEqual(f.requests.find(request => request.input === "Worker assignment")!.tools.map(tool => tool.name || tool.type), ["read", "web_search"]);
  assert.deepEqual((await f.pi.harness.snapshot(WorkerPermissionsDoc, f.children[0].id, BACKGROUND_CONTEXT))?.tools, ["read"]);
});

test("a parent with editing tools cannot grant commands unless it also has shell access", async t => {
  const f = await delegated(t, { task: "Worker assignment", permissions: ["commands.run"] }, () => { throw new Error("Rejected worker must not start"); },
    { parentTools: ["read", "write", "edit", "delegate", "delegate_result", "delegate_cancel"] });
  assert.equal(f.result.isError, true);
  assert.match(JSON.stringify(f.result.content), /Parent cannot grant commands.run/);
  assert.equal(f.children.length, 0);
});

test("extra worker tools cannot bypass the stored grants when accidentally exposed", async t => {
  let calls = 0;
  const extra = defineTool({ name: "extra_action", description: "Perform an external action", parameters: Type.Object({}),
    execute: async () => { calls++; return { content: [{ type: "text", text: "Action performed" }] }; } });
  const dir = mkdtempSync(join(tmpdir(), "assistant-extra-tool-test-"));
  const faux = fauxProvider({ tokensPerSecond: 100000 });
  const models = createModels(); models.setProvider(faux.provider);
  const worker = roleExtension("worker", [extra]);
  const pi = await PiService.open(dir, { models, model: { provider: "faux", modelId: "faux-1" }, extensions: [worker], storage: new MemoryStorage() });
  t.after(async () => { await pi.close(); rmSync(dir, { recursive: true, force: true }); });
  const conversation = await pi.harness.createConversation({ ownership: { kind: "ownerless" }, agent: { ...pi.agent("worker", dir), extensions: [worker] } }, BACKGROUND_CONTEXT);
  await conversation.commit(async tx => { (await tx.doc(WorkerPermissionsDoc, conversation.id)).tools = ["read", "grep", "find", "ls"]; }, BACKGROUND_CONTEXT);
  faux.setResponses([toolAnswer("extra_action"), context => {
    const results = context.messages.filter(message => message.role === "toolResult");
    assert.equal(results.at(-1)!.isError, true);
    assert.match(JSON.stringify(results.at(-1)!.content), /Worker permission denied/);
    return fauxAssistantMessage("Extra action blocked.");
  }]);
  pi.harness.resume();
  const result = await (await conversation.submit({ type: "input", content: "Attempt an ungranted extra action" }, BACKGROUND_CONTEXT)).wait(BACKGROUND_CONTEXT);
  assert.equal(result.status, "done");
  await pi.harness.waitForIdle(BACKGROUND_CONTEXT);
  assert.equal(calls, 0);
});
