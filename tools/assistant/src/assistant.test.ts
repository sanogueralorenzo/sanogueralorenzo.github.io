import assert from "node:assert/strict";
import { test } from "node:test";
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

test("independent native tools start before either completes", { timeout: 10000 }, async (t) => {
  const read = gate("safe"), grep = gate("safe");
  const extension = roleExtension("session");
  const tools = extension.tools!.map(tool => tool.name === "read" ? { ...tool, execute: read.tool.execute }
    : tool.name === "grep" ? { ...tool, execute: grep.tool.execute } : tool);
  const f = await fixture(t, [fauxAssistantMessage([
    fauxToolCall("read", { path: "first.ts" }),
    fauxToolCall("grep", { pattern: "evidence" }),
  ], { stopReason: "toolUse" }), fauxAssistantMessage("Both finished.")], [], {}, [{ ...extension, tools }]);
  await Promise.all([read.started, grep.started]);
  read.release(); grep.release();
  await f.idle();
  assert.equal(read.calls(), 1); assert.equal(grep.calls(), 1);
  assert.equal(answered(f.app, f.sessionId).at(-1)?.text, "Both finished.");
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
