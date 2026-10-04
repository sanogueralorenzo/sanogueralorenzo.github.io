import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { test } from "node:test";
import { Assistant } from "./assistant.ts";
import { State, now } from "./state.ts";

function fixture() {
  const dir = mkdtempSync(join(tmpdir(), "assistant-queue-"));
  const state = new State(dir, () => {});
  state.data.sessions.push({ id: "session", title: "Layout", cwd: dir, file: "session", status: "running", createdAt: now() });
  const app = Object.create(Assistant.prototype) as Assistant;
  Object.assign(app, { state, active: new Map(), drain: () => {}, pi: { transcript: () => [] } });
  return { app, state, dir, close() { state.db.close(); rmSync(dir, { recursive: true, force: true }); } };
}

test("withdrawing queued messages persists deletion while retaining the quote, conversation and unrelated work", () => {
  const f = fixture();
  try {
    const initial = f.state.message("Review the layout");
    const entry = f.state.entry(initial, "Layout", "session");
    f.state.update(entry, "I can fix the layout.", "result", "ready", initial.id, "proposal");
    f.app.submitSession("session", "Fix the padding", "followUp", { replyToId: "proposal" });
    const turn = f.state.data.turns.at(-1)!;
    f.app.submitSession("session", "Then check mobile");
    const remaining = f.state.data.turns.at(-1)!;
    const result = f.app.dequeue("session", turn.id);
    assert.equal(result.turn.replyToId, "proposal");
    assert.equal(result.turn.sessionId, "session");
    assert.equal(result.message?.text, "Fix the padding");
    assert.equal(f.state.data.messages.some((item) => item.id === turn.sourceId), false);
    assert.deepEqual(f.state.data.turns, [remaining]);
    assert.equal(entry.updates[0].text, "I can fix the layout.");
    assert.equal(f.state.data.sessions[0].status, "running");
    const reopened = new State(f.dir, () => {});
    try {
      assert.equal(reopened.data.messages.some((item) => item.id === turn.sourceId), false);
      assert.deepEqual(reopened.data.turns.map((item) => item.id), [remaining.id]);
    } finally { reopened.db.close(); }
    f.app.submitSession(result.turn.sessionId, "Fix padding and spacing", "followUp", { replyToId: result.turn.replyToId });
    assert.equal(f.state.data.turns.at(-1)?.replyToId, "proposal");
  } finally { f.close(); }
});

test("an unquoted first request can be withdrawn and resubmitted to its original conversation", () => {
  const f = fixture();
  try {
    f.app.submitSession("session", "First request");
    const turn = f.state.data.turns[0];
    const { turn: withdrawn } = f.app.dequeue("session", turn.id);
    assert.equal(f.state.data.messages.length, 0);
    assert.equal(f.state.data.entries.length, 0);
    f.app.submitSession(withdrawn.sessionId, "Edited first request");
    assert.equal(f.state.data.entries[0].sessionId, "session");
    assert.equal(f.state.data.messages[0].entryId, f.state.data.entries[0].id);
    assert.equal(f.state.data.turns[0].sessionId, "session");
  } finally { f.close(); }
});

test("dequeue rejects started, missing, duplicate and wrong-conversation requests without changing state", () => {
  const f = fixture();
  try {
    f.app.submitSession("session", "Request");
    const turn = f.state.data.turns[0];
    const before = JSON.stringify(f.state.data);
    assert.throws(() => f.app.dequeue("other", turn.id), /no longer queued/);
    assert.throws(() => f.app.dequeue("session", "missing"), /no longer queued/);
    assert.equal(JSON.stringify(f.state.data), before);
    turn.status = "running";
    const running = JSON.stringify(f.state.data);
    assert.throws(() => f.app.dequeue("session", turn.id), /already started/);
    assert.equal(JSON.stringify(f.state.data), running);
    turn.status = "queued";
    f.app.dequeue("session", turn.id);
    assert.throws(() => f.app.dequeue("session", turn.id), /no longer queued/);
  } finally { f.close(); }
});

test("withdrawing the first queued message preserves remaining work and clears references to the deleted message", () => {
  const f = fixture();
  try {
    f.app.submitSession("session", "First request");
    const first = f.state.data.turns[0];
    f.app.submitSession("session", "Follow up on that", "followUp", { replyToId: first.sourceId });
    const second = f.state.data.turns[1];
    f.app.dequeue("session", first.id);
    assert.equal(f.state.data.entries[0].sourceId, second.sourceId);
    assert.equal(f.state.data.messages[0].id, second.sourceId);
    assert.equal(f.state.data.messages[0].replyToId, undefined);
    assert.equal(second.replyToId, undefined);
    assert.deepEqual(f.state.data.turns, [second]);
  } finally { f.close(); }
});

test("withdrawing an approval clears its reaction; withdrawing a resumed request preserves completed history", () => {
  const f = fixture();
  try {
    const initial = f.state.message("Review this");
    const entry = f.state.entry(initial, "Layout", "session");
    f.state.update(entry, "I can fix this.", "result", "ready", initial.id, "proposal");
    f.app.submitSession("session", "ignored", "followUp", { replyToId: "proposal", reaction: "thumbs-up" });
    const turn = f.state.data.turns.at(-1)!;
    f.app.dequeue("session", turn.id);
    assert.equal(f.state.data.messages.some((item) => item.reaction), false);
    f.app.submitSession("session", "ignored", "followUp", { replyToId: "proposal", reaction: "thumbs-up" });
    assert.equal(f.state.data.turns.length, 1);
    f.state.data.turns.push({ ...turn, id: "resume", sourceId: initial.id, text: "Continue the interrupted request" });
    const resumed = f.app.dequeue("session", "resume");
    assert.equal(resumed.removedMessageId, undefined);
    assert.ok(f.state.data.messages.some((item) => item.id === initial.id));
    assert.equal(entry.updates.length, 1);
  } finally { f.close(); }
});

test("steering consumes the selected queued message once and retains its source, quote and unrelated queued work", async () => {
  const f = fixture();
  try {
    f.app.submitSession("session", "Original request");
    const running = f.state.data.turns[0];
    running.status = "running";
    const prompts: string[] = [];
    Object.assign(f.app, { active: new Map([["session", { turn: running, stopped: false, session: { steer: async (prompt: string) => { prompts.push(prompt); } } }]]) });
    const entry = f.state.data.entries[0];
    f.state.update(entry, "Earlier proposal", "result", "working", running.sourceId, "proposal");
    f.app.submitSession("session", "Use this proposal", "followUp", { replyToId: "proposal" });
    const selected = f.state.data.turns[1];
    f.app.submitSession("session", "Later follow-up");
    const later = f.state.data.turns[2];
    const before = f.state.data.messages.map((message) => message.id);
    const request = f.app.steerQueued("session", selected.id);
    await assert.rejects(f.app.steerQueued("session", selected.id), /no longer queued/);
    await request;
    assert.deepEqual(prompts, ["In reply to this earlier assistant message:\n> Earlier proposal\n\nUse this proposal"]);
    assert.deepEqual(f.state.data.turns, [running, later]);
    assert.deepEqual(f.state.data.messages.map((message) => message.id), before);
    assert.equal(running.sourceId, selected.sourceId);
    assert.equal(f.state.data.messages.find((message) => message.id === selected.sourceId)?.replyToId, "proposal");
  } finally { f.close(); }
});

test("failed steering restores the queue order and original active source without losing the message", async () => {
  const f = fixture();
  try {
    f.app.submitSession("session", "Active request");
    const running = f.state.data.turns[0];
    running.status = "running";
    f.state.data.entries[0].status = "working";
    f.app.submitSession("session", "Queued request");
    const queued = f.state.data.turns[1];
    await assert.rejects(f.app.steerQueued("session", queued.id), /no active work/);
    let reject!: (reason: Error) => void;
    const pending = new Promise<void>((_, fail) => { reject = fail; });
    Object.assign(f.app, { active: new Map([["session", { turn: running, stopped: false, session: { steer: () => pending } }]]) });
    const before = JSON.stringify(f.state.data);
    const request = f.app.steerQueued("session", queued.id);
    assert.equal(f.state.data.turns.some((turn) => turn.id === queued.id), false);
    reject(new Error("Steering rejected"));
    await assert.rejects(request, /Steering rejected/);
    assert.equal(JSON.stringify(f.state.data), before);
    await assert.rejects(f.app.steerQueued("wrong", queued.id), /no longer queued/);
    await assert.rejects(f.app.steerQueued("session", running.id), /already started/);
  } finally { f.close(); }
});

test("steering a separately routed queued request moves its Home message into the active entry", async () => {
  const f = fixture();
  try {
    f.app.submitSession("session", "Active request");
    const running = f.state.data.turns[0];
    running.status = "running";
    Object.assign(f.app, { active: new Map([["session", { turn: running, stopped: false, session: { steer: async () => {} } }]]) });
    const message = f.state.message("Separately routed request");
    const entry = f.state.entry(message, "New request", "session");
    const queued = { ...running, id: "routed", sourceId: message.id, entryId: entry.id, text: message.text, status: "queued" as const };
    f.state.data.turns.push(queued);
    await f.app.steerQueued("session", queued.id);
    assert.equal(message.entryId, running.entryId);
    assert.equal(f.state.data.entries.some((item) => item.id === entry.id), false);
    assert.equal(f.state.data.messages.some((item) => item.id === message.id), true);
  } finally { f.close(); }
});
