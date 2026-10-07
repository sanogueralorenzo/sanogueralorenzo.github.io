import assert from "node:assert/strict";
import { test } from "node:test";
import { BACKGROUND_CONTEXT } from "@earendil-works/chord/context";
import { fauxAssistantMessage, fauxToolCall } from "@earendil-works/pi-ai/providers/faux";
import { roleExtension } from "./pi.ts";
import { fixture, answered, gate, toolAnswer, waitFor } from "./test-support.ts";

test("Home routes through Durable without an extra coordinator model call", async (t) => {
  const f = await fixture(t);
  await f.idle();
  assert.equal(f.faux.state.callCount, 2);
  const entry = f.app.snapshot().entries[0];
  assert.equal(entry.status, "ready");
  assert.equal(entry.title, "Test");
  assert.equal(entry.updates[0].text, "First proposal.\nIts details.");
  assert.equal(answered(f.app, f.sessionId)[0].id, entry.updates[0].id);
  assert.equal(f.app.snapshot().turns.length, 0);
});

test("replies quote the selected answer and thumbs-up is admitted once", async (t) => {
  const f = await fixture(t); await f.idle();
  const reply = answered(f.app, f.sessionId)[0];
  f.faux.appendResponses([async (context) => {
    const input = context.messages.filter((message) => message.role === "user").at(-1)!;
    assert.equal(input.content, "In reply to this earlier assistant message:\n> First proposal.\n> Its details.\n\nYes, go ahead.");
    return fauxAssistantMessage("Approved.");
  }]);
  const options = { replyToId: reply.id, reaction: "thumbs-up" as const };
  await f.app.submitSession(f.sessionId, "ignored", "followUp", options);
  assert.deepEqual(await f.app.submitSession(f.sessionId, "ignored", "followUp", options), { reacted: true });
  await f.idle();
  assert.equal(f.app.snapshot().messages.filter((message) => message.reaction).length, 1);
  assert.equal(f.app.transcript(f.sessionId).messages.filter((message) => message.reaction).length, 1);
  await assert.rejects(f.app.submitSession(f.sessionId, "x", "followUp", { replyToId: "missing" }), /not in this conversation/);
  await assert.rejects(f.app.submitSession(f.sessionId, "x", "steer", options), /React to an assistant reply/);
});

test("Durable delegation stores a read-only child with no delegation or Computer Use tools", async (t) => {
  const f = await fixture(t, [toolAnswer("delegate", { role: "researcher", task: "Find evidence" }), async (context) => {
    assert.deepEqual(context.messages.flatMap((message) => message.role === "system" ? message.toolsAdded?.map((tool) => tool.name) || [] : []), ["read", "grep", "find", "ls"]);
    return fauxAssistantMessage("Evidence found.");
  }, async (context) => {
    const result = context.messages.filter((message) => message.role === "toolResult").at(-1)!;
    assert.match(JSON.stringify(result.content), /Evidence found/);
    return fauxAssistantMessage("Final answer.");
  }]);
  await f.idle();
  const children = await f.app.pi.harness.commit((tx) => tx.scanConversations({}, 256), BACKGROUND_CONTEXT);
  const child = children.items.find((item) => item.owner);
  assert.ok(child);
  const conversation = await f.app.pi.harness.conversation(child.id, BACKGROUND_CONTEXT);
  const history = await conversation!.entries({}, 256, undefined, BACKGROUND_CONTEXT);
  assert.ok(history.items.some((entry) => entry.kind === "pi.assistant"));
  assert.equal(answered(f.app, f.sessionId).at(-1)?.text, "Final answer.");
});

test("stopping work keeps queued inputs and resuming runs the interrupted request first", async (t) => {
  const pause = gate();
  const f = await fixture(t, [toolAnswer("pause")], [pause.tool]);
  await pause.started;
  await f.app.submitSession(f.sessionId, "Later follow-up");
  await waitFor(f.app, () => f.app.state.home.messages.at(-1)?.submissionId !== undefined);
  await f.app.stop(f.sessionId);
  assert.equal(f.app.snapshot().sessions[0].status, "interrupted");
  assert.equal(f.app.snapshot().turns.filter((turn) => turn.status === "queued").length, 1);
  const requests: string[] = [];
  f.faux.appendResponses([async (context) => { requests.push(String(context.messages.filter((message) => message.role === "user").at(-1)!.content)); return fauxAssistantMessage("Resumed."); },
    async (context) => { requests.push(String(context.messages.filter((message) => message.role === "user").at(-1)!.content)); return fauxAssistantMessage("Follow-up."); }]);
  await f.app.resume(f.app.snapshot().entries[0].id);
  await f.idle();
  assert.match(requests[0], /^Continue the interrupted request/);
  assert.equal(requests[1], "Later follow-up");
  assert.equal(f.app.snapshot().sessions[0].status, "idle");
});

test("a restarted delegation reuses its owned child and committed task request", async (t) => {
  const pause = gate();
  const f = await fixture(t, [toolAnswer("delegate", { role: "researcher", task: "Find evidence" }), toolAnswer("pause")], [], {}, [roleExtension("researcher", [pause.tool])]);
  await pause.started;
  const before = await f.app.pi.harness.commit((tx) => tx.scanConversations({}, 256), BACKGROUND_CONTEXT);
  const originalChild = before.items.find((item) => item.owner)!;
  f.faux.appendResponses([fauxAssistantMessage("Recovered evidence."), fauxAssistantMessage("Recovered parent answer.")]);
  const app = await f.reopen(); await f.idle();
  const after = await app.pi.harness.commit((tx) => tx.scanConversations({}, 256), BACKGROUND_CONTEXT);
  assert.deepEqual(after.items.filter((item) => item.owner).map((item) => item.id), [originalChild.id]);
  assert.equal(pause.calls(), 1);
  assert.equal(answered(app, f.sessionId).at(-1)?.text, "Recovered parent answer.");
});

test("stopping the parent aborts and joins its owned child", async (t) => {
  const pause = gate();
  const f = await fixture(t, [toolAnswer("delegate", { role: "reviewer", task: "Review it" }), toolAnswer("pause")], [], {}, [roleExtension("reviewer", [pause.tool])]);
  await pause.started;
  await f.app.stop(f.sessionId);
  const inspection = await f.app.pi.harness.inspect(BACKGROUND_CONTEXT);
  assert.equal(inspection.tasks.length, 0);
  assert.equal(f.app.snapshot().sessions[0].status, "interrupted");
});

test("a lookup batched with an accepted route cannot trigger another coordinator request", async (t) => {
  const f = await fixture(t); await f.idle();
  const count = f.faux.state.callCount;
  f.faux.appendResponses([fauxAssistantMessage([
    fauxToolCall("find_conversations", { query: "Test" }),
    fauxToolCall("route_home", { mode: "continue", sessionId: f.sessionId }),
  ], { stopReason: "toolUse" }), fauxAssistantMessage("Continued.")]);
  await f.app.submitHome("Continue this work"); await f.idle();
  assert.equal(f.faux.state.callCount - count, 2);
  assert.equal(answered(f.app, f.sessionId).at(-1)?.text, "Continued.");
});

test("an empty model answer is reported as a failure rather than an invisible completion", async (t) => {
  const f = await fixture(t, [fauxAssistantMessage("")]); await f.idle();
  const entry = f.app.snapshot().entries[0];
  assert.equal(entry.status, "failed");
  assert.equal(entry.updates[0].text, "Agent returned no final reply");
});
