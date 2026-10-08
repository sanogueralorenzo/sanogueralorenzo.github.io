import assert from "node:assert/strict";
import type { ConversationId } from "@earendil-works/pi-durable";
import { BACKGROUND_CONTEXT } from "@earendil-works/chord/context";
import { test } from "node:test";
import { fauxAssistantMessage } from "@earendil-works/pi-ai/providers/faux";
import { fixture, gate, toolAnswer, answered, waitFor } from "./test-support.ts";

test("Home and transcript share Durable entry IDs and survive reopening SQLite", async (t) => {
  const f = await fixture(t); await f.idle();
  const before = f.app.snapshot();
  const transcript = f.app.transcript(f.sessionId);
  const app = await f.reopen();
  assert.deepEqual(app.snapshot(), before);
  assert.deepEqual(app.transcript(f.sessionId), transcript);
});

test("closing during an unsafe tool resumes its turn without replaying the side effect", async (t) => {
  const pause = gate("unsafe");
  const f = await fixture(t, [toolAnswer("pause")], [pause.tool]); await pause.started;
  f.faux.appendResponses([async (context) => {
    const result = context.messages.filter((message) => message.role === "toolResult").at(-1)!;
    assert.match(JSON.stringify(result), /interrupt/i);
    return fauxAssistantMessage("Recovered after restart.");
  }]);
  const app = await f.reopen();
  await f.idle();
  assert.equal(pause.calls(), 1);
  assert.equal(answered(app, f.sessionId).at(-1)?.text, "Recovered after restart.");
  assert.equal(app.snapshot().turns.length, 0);
});

test("the browser can reload committed live text while the model is still streaming", async (t) => {
  const f = await fixture(t, [fauxAssistantMessage("Live text ".repeat(1000))], [], { tokensPerSecond: 1000, tokenSize: { min: 1, max: 1 } });
  await waitFor(f.app, () => f.app.transcript(f.sessionId).streaming.length > 0);
  const transcript = f.app.transcript(f.sessionId);
  assert.equal(transcript.session.status, "running");
  assert.match(transcript.streaming, /^Live text/);
  assert.equal(f.app.pi.models, f.models, "Tool-free suggestions use the unmodified model collection");
  await f.app.stop(f.sessionId);
});

test("a committed admission remains authoritative if its Home metadata write is interrupted", async (t) => {
  const pause = gate();
  const f = await fixture(t, [toolAnswer("pause")], [pause.tool]); await pause.started;
  await f.app.state.change(home => { delete home.messages[0].submissionId; });
  assert.equal(f.app.snapshot().turns[0].status, "running");
  await assert.rejects(f.app.dequeue(f.sessionId, f.sourceId), /already started/);
  await f.app.stop(f.sessionId);
  const app = await f.reopen();
  assert.equal(app.snapshot().entries[0].status, "interrupted");
  assert.equal(app.snapshot().turns.length, 0);
});


test("native views follow context resets while completed Home results survive reopening", async (t) => {
  const f = await fixture(t); await f.idle();
  const home = f.app.snapshot();
  const conversation = (await f.app.pi.harness.conversation(f.app.snapshot().sessions[0].conversationId as ConversationId, BACKGROUND_CONTEXT))!;
  await conversation.reset(undefined, BACKGROUND_CONTEXT);
  assert.deepEqual(f.app.transcript(f.sessionId).messages, []);
  assert.deepEqual(f.app.snapshot().entries, home.entries);
  const app = await f.reopen();
  assert.deepEqual(app.transcript(f.sessionId).messages, []);
  assert.deepEqual(app.snapshot(), home);
});

test("a slow conversation watcher catches up to the latest view and stops cleanly", { timeout: 5000 }, async (t) => {
  const f = await fixture(t); await f.idle();
  const conversation = (await f.app.pi.harness.conversation(f.app.snapshot().sessions[0].conversationId as ConversationId, BACKGROUND_CONTEXT))!;
  const { UserEntry } = await import("@earendil-works/pi-durable");
  let release!: () => void;
  let started!: () => void;
  const blocked = new Promise<void>((resolve) => { release = resolve; });
  const delivering = new Promise<void>((resolve) => { started = resolve; });
  let caughtUp!: () => void;
  const latest = new Promise<void>((resolve) => { caughtUp = resolve; });
  const events: Array<{ messages: unknown[] }> = [];
  const watch = await f.app.watchConversation(f.sessionId, async (event) => {
    events.push(event as { messages: unknown[] });
    if (events.length === 2) { started(); await blocked; }
    if (events.at(-1)!.messages.length === events[0].messages.length + 121) caughtUp();
  });
  t.after(() => watch.stop());
  const append = () => conversation.commit((tx) => tx.appendEntry(UserEntry, conversation.id, {
    model: [{ role: "user", content: "Committed while the client is slow", timestamp: Date.now() }],
  }), BACKGROUND_CONTEXT);
  await append(); await delivering;
  for (let i = 0; i < 120; i++) await append();
  release();
  await latest;
  assert.ok(events.length < 30, `Expected bounded catch-up, received ${events.length} frames`);
  await watch.stop();
  const delivered = events.length;
  await append();
  await new Promise<void>((resolve) => setImmediate(resolve));
  assert.equal(events.length, delivered);
});
