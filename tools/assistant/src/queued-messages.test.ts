import assert from "node:assert/strict";
import { test } from "node:test";
import { fauxAssistantMessage } from "@earendil-works/pi-ai/providers/faux";
import { fixture, gate, toolAnswer, waitFor, assertQueued, answered } from "./test-support.ts";

test("withdrawal removes only the selected Durable inbox item and survives reopen", async (t) => {
  const pause = gate();
  const f = await fixture(t, [toolAnswer("pause")], [pause.tool]); await pause.started;
  await f.app.submitSession(f.sessionId, "First waiting request");
  await f.app.submitSession(f.sessionId, "Second waiting request");
  await waitFor(f.app, () => f.app.state.home.messages.filter((message) => message.submissionId !== undefined).length === 3);
  const selected = f.app.snapshot().turns.find((turn) => turn.text === "First waiting request")!;
  const removed = await f.app.dequeue(f.sessionId, selected.id);
  assert.equal(removed.message.text, "First waiting request");
  assertQueued(f.app, f.sessionId, 1);
  await assert.rejects(f.app.dequeue(f.sessionId, selected.id), /no longer queued/);
  await assert.rejects(f.app.dequeue("wrong", f.app.snapshot().turns[0].id), /no longer queued/);
  await f.app.stop(f.sessionId);
  const app = await f.reopen();
  assert.equal(app.snapshot().messages.some((message) => message.id === removed.removedMessageId), false);
  assertQueued(app, f.sessionId, 1);
});

test("steering changes the selected Durable inbox item in place and keeps its quote", async (t) => {
  const pause = gate();
  const f = await fixture(t, undefined, [pause.tool]); await f.idle();
  const reply = answered(f.app, f.sessionId)[0];
  f.faux.appendResponses([toolAnswer("pause"), async (context) => {
    const input = context.messages.filter((message) => message.role === "user").at(-1)!;
    assert.match(String(input.content), /In reply to this earlier assistant message/);
    assert.match(String(input.content), /Focus on that proposal/);
    return fauxAssistantMessage("Steered answer.");
  }, fauxAssistantMessage("Later answer.")]);
  await f.app.submitSession(f.sessionId, "Active request"); await pause.started;
  await f.app.submitSession(f.sessionId, "Focus on that proposal", "followUp", { replyToId: reply.id });
  await f.app.submitSession(f.sessionId, "Later request");
  await waitFor(f.app, () => f.app.state.home.messages.at(-1)?.submissionId !== undefined);
  const selected = f.app.snapshot().turns.find((turn) => turn.text === "Focus on that proposal")!;
  const submissionId = f.app.state.home.messages.find((message) => message.id === selected.sourceId)!.submissionId;
  await f.app.steerQueued(f.sessionId, selected.id);
  assert.equal(f.app.state.home.messages.find((message) => message.id === selected.sourceId)!.submissionId, submissionId);
  pause.release(); await f.idle();
  assert.equal(answered(f.app, f.sessionId).at(-1)?.text, "Later answer.");
  assert.equal(f.app.snapshot().turns.length, 0);
});

test("started requests cannot be withdrawn or steered as queued messages", async (t) => {
  const pause = gate();
  const f = await fixture(t, [toolAnswer("pause")], [pause.tool]); await pause.started;
  const active = f.app.snapshot().turns.find((turn) => turn.status === "running")!;
  const before = JSON.stringify(f.app.snapshot().messages);
  await assert.rejects(f.app.dequeue(f.sessionId, active.id), /already started/);
  await assert.rejects(f.app.steerQueued(f.sessionId, active.id), /already started/);
  assert.equal(JSON.stringify(f.app.snapshot().messages), before);
  await f.app.stop(f.sessionId);
});

test("withdrawing a quoted queued request clears the quote in both Home and the Durable inbox", async (t) => {
  const pause = gate();
  const f = await fixture(t, [toolAnswer("pause")], [pause.tool]); await pause.started;
  const queued = await f.app.submitSession(f.sessionId, "Withdraw this");
  const id = queued.turn!.id;
  await f.app.submitSession(f.sessionId, "Follow up", "followUp", { replyToId: id });
  await waitFor(f.app, () => f.app.state.home.messages.at(-1)?.submissionId !== undefined);
  await f.app.dequeue(f.sessionId, id);
  assert.equal(f.app.snapshot().messages.at(-1)?.replyToId, undefined);
  f.faux.appendResponses([fauxAssistantMessage("Active answer."), async context => {
    assert.equal(context.messages.filter(message => message.role === "user").at(-1)!.content, "Follow up");
    return fauxAssistantMessage("Follow-up answer.");
  }]);
  pause.release(); await f.idle();
  assert.equal(answered(f.app, f.sessionId).at(-1)?.text, "Follow-up answer.");
});
