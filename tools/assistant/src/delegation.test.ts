import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { test, type TestContext } from "node:test";
import { BACKGROUND_CONTEXT } from "@earendil-works/chord/context";
import { fauxAssistantMessage, fauxToolCall, type FauxResponseFactory } from "@earendil-works/pi-ai/providers/faux";
import { roleExtension } from "./pi.ts";
import { answered, fixture, gate, toolAnswer, waitFor } from "./test-support.ts";

async function delegated(t: TestContext, options: { empty?: boolean } = {}) {
  const pause = gate();
  let delegationId = "";
  const respond: FauxResponseFactory = (context) => {
    const user = context.messages.filter(message => message.role === "user").at(-1)!;
    const results = context.messages.filter(message => message.role === "toolResult");
    if (user.content === "Find evidence") {
      assert.deepEqual(context.messages.flatMap(message => message.role === "system" ? message.toolsAdded?.map(tool => tool.name) || [] : []),
        ["read", "grep", "find", "ls", "pause"]);
      if (!results.length) return toolAnswer("pause");
      if (results.at(-1)!.toolName === "pause") return toolAnswer("read", { path: "parent.txt" });
      assert.match(JSON.stringify(results.at(-1)!.content), /parent/, "Child must inherit its parent's working directory");
      return fauxAssistantMessage(options.empty ? "" : "Evidence found.");
    }
    const last = results.at(-1);
    if (!last) return toolAnswer("delegate", { role: "researcher", task: "Find evidence" });
    if (last.toolName === "delegate") {
      delegationId = JSON.parse((last.content[0] as { text: string }).text).delegationId;
      assert.ok(delegationId);
      return toolAnswer("bash", { command: "printf parent > parent.txt" });
    }
    if (last.toolName === "bash") return toolAnswer("delegate_result", { delegationId });
    const findings = JSON.parse((last!.content[0] as { text: string }).text);
    assert.equal(findings.status, options.empty ? "failed" : "done");
    assert.match(findings.text || findings.error, options.empty ? /no answer/ : /Evidence found/);
    return fauxAssistantMessage(options.empty ? "Worker failure reported." : "Final answer with evidence.");
  };
  const f = await fixture(t, Array(12).fill(respond), [], {}, [roleExtension("researcher", [pause.tool])]);
  await pause.started;
  await waitFor(f.app, () => !!f.app.state.live(Number(f.sessionId))?.tools?.some(tool => tool.name === "delegate_result"));
  assert.equal(readFileSync(join(f.dir, "parent.txt"), "utf8"), "parent", "Parent must do independent work while its child is blocked");
  return { ...f, pause, delegationId };
}

test("delegation returns immediately and its read-only findings are collected later", { timeout: 15000 }, async t => {
  const f = await delegated(t);
  assert.equal(f.app.snapshot().entries[0].status, "working");
  f.pause.release(); await f.idle();
  assert.equal(answered(f.app, f.sessionId).at(-1)?.text, "Final answer with evidence.");
  const children = await f.app.pi.harness.commit(tx => tx.scanConversations({}, 256), BACKGROUND_CONTEXT);
  assert.equal(children.items.filter(child => child.owner).length, 1);
});

test("a restarted result wait reuses the existing child and submission", { timeout: 15000 }, async t => {
  const f = await delegated(t);
  const before = await f.app.pi.harness.commit(tx => tx.scanConversations({}, 256), BACKGROUND_CONTEXT);
  const originalChild = before.items.find(child => child.owner)!;
  const app = await f.reopen(); await f.idle();
  const after = await app.pi.harness.commit(tx => tx.scanConversations({}, 256), BACKGROUND_CONTEXT);
  assert.deepEqual(after.items.filter(child => child.owner).map(child => child.id), [originalChild.id]);
  assert.equal(f.pause.calls(), 1);
  const requests = await app.pi.harness.inspect(BACKGROUND_CONTEXT);
  assert.equal(requests.submissions.length, 0);
  assert.equal(answered(app, f.sessionId).at(-1)?.text, "Final answer with evidence.");
});

test("stopping a parent aborts and joins its asynchronous child", { timeout: 15000 }, async t => {
  const f = await delegated(t);
  await f.app.submitSession(f.sessionId, "Later follow-up");
  await waitFor(f.app, () => f.app.state.home.messages.at(-1)?.submissionId !== undefined);
  await f.app.stop(f.sessionId);
  const inspection = await f.app.pi.harness.inspect(BACKGROUND_CONTEXT);
  assert.equal(inspection.tasks.length, 0);
  assert.equal(f.app.snapshot().sessions[0].status, "interrupted");
  assert.equal(f.app.snapshot().turns.filter(turn => turn.status === "queued").length, 1);
});

test("parallel delegations have distinct children and collect each result", { timeout: 15000 }, async t => {
  const pause = gate();
  const respond: FauxResponseFactory = context => {
    const user = context.messages.filter(message => message.role === "user").at(-1)!;
    const results = context.messages.filter(message => message.role === "toolResult");
    if (user.content === "Find callers" || user.content === "Review callers")
      return results.length ? fauxAssistantMessage(String(user.content)) : toolAnswer("pause");
    if (!results.length) return fauxAssistantMessage([
      fauxToolCall("delegate", { role: "researcher", task: "Find callers" }),
      fauxToolCall("delegate", { role: "reviewer", task: "Review callers" }),
    ], { stopReason: "toolUse" });
    if (results.at(-1)!.toolName === "delegate") {
      const children = results.map(result => JSON.parse((result.content[0] as { text: string }).text));
      assert.equal(new Set(children.map(child => child.delegationId)).size, 2);
      return fauxAssistantMessage(children.map(child => fauxToolCall("delegate_result", { delegationId: child.delegationId })), { stopReason: "toolUse" });
    }
    const findings = results.filter(result => result.toolName === "delegate_result").map(result => JSON.parse((result.content[0] as { text: string }).text));
    assert.deepEqual(findings.map(result => result.text).sort(), ["Find callers", "Review callers"]);
    return fauxAssistantMessage("Both results collected.");
  };
  const f = await fixture(t, Array(12).fill(respond), [], {}, [roleExtension("researcher", [pause.tool]), roleExtension("reviewer", [pause.tool])]);
  await waitFor(f.app, () => pause.calls() === 2 && !!f.app.state.live(Number(f.sessionId))?.tools?.some(tool => tool.name === "delegate_result"));
  pause.release(); await f.idle();
  assert.equal(answered(f.app, f.sessionId).at(-1)?.text, "Both results collected.");
  const children = await f.app.pi.harness.commit(tx => tx.scanConversations({}, 256), BACKGROUND_CONTEXT);
  assert.equal(children.items.filter(child => child.owner).length, 2);
});

test("empty child answers are reported as failures", { timeout: 15000 }, async t => {
  const f = await delegated(t, { empty: true });
  f.pause.release(); await f.idle();
  assert.equal(answered(f.app, f.sessionId).at(-1)?.text, "Worker failure reported.");
});

test("Stop can clean up an uncollected child after the parent has yielded", { timeout: 15000 }, async t => {
  const pause = gate();
  const respond: FauxResponseFactory = context => {
    const user = context.messages.filter(message => message.role === "user").at(-1)!;
    if (user.content === "Find evidence") return toolAnswer("pause");
    return context.messages.some(message => message.role === "toolResult") ? fauxAssistantMessage("Yielded.")
      : toolAnswer("delegate", { role: "researcher", task: "Find evidence" });
  };
  const f = await fixture(t, Array(6).fill(respond), [], {}, [roleExtension("researcher", [pause.tool])]);
  await pause.started;
  await waitFor(f.app, () => f.app.snapshot().entries[0].status === "ready");
  assert.equal(await f.app.stop(f.sessionId), true);
  assert.equal((await f.app.pi.harness.inspect(BACKGROUND_CONTEXT)).tasks.length, 0);
  assert.equal(f.app.state.home.sessions[0].paused, false);
});

test("result handles must belong to the requesting conversation", { timeout: 15000 }, async t => {
  const f = await delegated(t);
  const other = await f.app.pi.harness.createConversation({ ownership: { kind: "ownerless" }, agent: f.app.pi.agent("session", f.dir) }, BACKGROUND_CONTEXT);
  f.faux.setResponses([toolAnswer("delegate_result", { delegationId: f.delegationId }), context => {
    const result = context.messages.filter(message => message.role === "toolResult").at(-1)!;
    assert.equal(result.isError, true);
    assert.match(JSON.stringify(result.content), /not found in this conversation/);
    return fauxAssistantMessage("Foreign handle rejected.");
  }]);
  const result = await (await other.submit({ type: "input", content: "Collect another conversation's child" }, BACKGROUND_CONTEXT)).wait(BACKGROUND_CONTEXT);
  assert.equal(result.status, "done");
  await f.app.stop(f.sessionId);
});
