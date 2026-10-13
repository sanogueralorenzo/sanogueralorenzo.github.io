import assert from "node:assert/strict";
import { existsSync, mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test, type TestContext } from "node:test";
import { BACKGROUND_CONTEXT } from "@earendil-works/chord/context";
import type { JsonValue } from "@earendil-works/chord";
import { createModels, lazyStream, type Models } from "@earendil-works/pi-ai";
import { fauxAssistantMessage, fauxProvider, fauxToolCall, type FauxResponseFactory } from "@earendil-works/pi-ai/providers/faux";
import { configure, MemoryStorage } from "@earendil-works/pi-durable";
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
  // hosted tool to prove denied grants remove it, rather than merely skipping injection.
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

test("delegate rejects missing, unknown, duplicate, and inconsistent permissions before creating a worker", async t => {
  for (const permissions of [undefined, ["unknown"], ["files.read", "files.read"], ["files.write"], ["commands.run"], ["files.read", "commands.run"]]) {
    const f = await delegated(t, { task: "Worker assignment", ...(permissions && { permissions }) }, () => { throw new Error("Rejected worker must not start"); });
    assert.equal(f.result.isError, true, JSON.stringify(permissions));
    assert.equal(f.children.length, 0);
  }
});

test("an explicit empty list permits reasoning and rejects fabricated native tool calls", async t => {
  const f = await delegated(t, { task: "Worker assignment", permissions: [] }, context => {
    const results = context.messages.filter(message => message.role === "toolResult");
    if (!results.length) return toolAnswer("write", { path: "denied.txt", content: "denied" });
    assert.equal(results.at(-1)!.isError, true);
    return fauxAssistantMessage("Reasoned from context.");
  });
  const worker = f.requests.find(request => request.input === "Worker assignment")!;
  assert.deepEqual(worker.tools, []);
  assert.equal(existsSync(join(f.dir, "denied.txt")), false);
  assert.deepEqual((await f.pi.harness.snapshot(WorkerPermissionsDoc, f.children[0].id, BACKGROUND_CONTEXT))?.permissions, []);
  assert.match(JSON.stringify(f.result.content), /Reasoned from context/);
});

test("read-only workers cannot write or run shell commands even if their tools are accidentally exposed", async t => {
  const f = await delegated(t, { task: "Worker assignment", permissions: ["files.read"] }, context => {
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
  assert.deepEqual(f.requests.find(request => request.input === "Worker assignment")!.tools.map(tool => tool.name), ["read", "grep", "find", "ls"]);
});

test("workers with file grants can write and edit without command access", async t => {
  const f = await delegated(t, { task: "Worker assignment", permissions: ["files.read", "files.write"] }, context => {
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

test("workers with command and file grants can run commands in the inherited directory", async t => {
  const f = await delegated(t, { task: "Worker assignment", permissions: ["files.read", "files.write", "commands.run"] }, context => {
    const results = context.messages.filter(message => message.role === "toolResult");
    if (!results.length) return toolAnswer("bash", { command: "printf command > result.txt" });
    assert.equal(results.at(-1)!.isError, false);
    return fauxAssistantMessage("Command completed.");
  });
  assert.equal(readFileSync(join(f.dir, "result.txt"), "utf8"), "command");
  assert.match(JSON.stringify(f.result.content), /Command completed/);
});

test("the production provider grants hosted search only to workers that requested it", async t => {
  for (const permissions of [[], ["web.search"]]) {
    const f = await delegated(t, { task: "Worker assignment", permissions }, () => fauxAssistantMessage("Finished."));
    const count = (input: string) => f.requests.find(request => request.input === input)!.tools.filter(tool => tool.type === "web_search").length;
    assert.equal(count("Parent assignment"), 1);
    assert.equal(count("Worker assignment"), permissions.length);
  }
});

test("a parent cannot grant native permissions beyond its own available tools", async t => {
  const f = await delegated(t, { task: "Worker assignment", permissions: ["files.read", "files.write"] }, () => { throw new Error("Rejected worker must not start"); },
    { parentTools: ["read", "grep", "find", "ls", "delegate", "delegate_result", "delegate_cancel"] });
  assert.equal(f.result.isError, true);
  assert.match(JSON.stringify(f.result.content), /Parent cannot grant files.write/);
  assert.equal(f.children.length, 0);
});
