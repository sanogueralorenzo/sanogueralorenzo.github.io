import assert from "node:assert/strict";
import { test } from "node:test";
import { composerDraft, restoreComposerDraft, createQueuedMessages } from "./queued-messages.js";
import { createMessageActions } from "./message-actions.js";
import { suggestionTarget } from "./prompt-suggestions.js";

function fixture() {
  const message = { id: "queued", text: "Change the padding", replyToId: "proposal" };
  const turn = { id: "turn", sessionId: "session", sourceId: message.id, text: message.text, replyToId: message.replyToId, status: "queued" };
  const state = { selected: "home", input: "My existing draft", replyToId: "older", edit: null, queuedEdit: null, sessionDrafts: {},
    data: { messages: [message], turns: [turn], sessions: [{ id: "session", title: "Layout" }], entries: [] }, transcript: [] };
  const requests = [];
  const pending = Promise.withResolvers();
  const root = { querySelector: () => ({ focus() {} }) };
  const api = (path, method, body) => { requests.push({ path, method, body }); return pending.promise; };
  const queue = createQueuedMessages({ state, root, api, render() {} });
  const button = action => ({ dataset: { action, turn: turn.id, session: turn.sessionId } });
  return { state, message, turn, queue, requests, pending, root, button, result: { turn, message, removedMessageId: message.id } };
}

test("editing a queued reply withdraws once, preserves its conversation and quote, and can restore the previous draft", async () => {
  const f = fixture();
  const previous = composerDraft(f.state);
  const edit = f.queue.handleClick(f.button("edit-queued"));
  await f.queue.handleClick(f.button("edit-queued"));
  assert.equal(f.requests.length, 1);
  f.pending.resolve(f.result);
  await edit;
  assert.equal(f.state.data.turns.length, 0);
  assert.equal(f.state.data.messages.length, 0);
  assert.equal(f.state.input, "Change the padding");
  assert.equal(f.state.replyToId, "proposal");
  assert.equal(f.state.queuedEdit.sessionId, "session");
  assert.deepEqual(f.state.queuedEdit.previous, previous);
  assert.equal(suggestionTarget(f.state), null);
  assert.equal(f.queue.cancelEdit(), true);
  assert.deepEqual(composerDraft(f.state), previous);
});

test("deleting a queued message leaves the composer alone, and a started-message rejection leaves both intact", async () => {
  for (const succeeds of [true, false]) {
    const f = fixture();
    const before = composerDraft(f.state);
    const deletion = f.queue.handleClick(f.button("delete-queued"));
    if (succeeds) f.pending.resolve(f.result);
    else f.pending.reject(new Error("Already started"));
    if (succeeds) await deletion;
    else await assert.rejects(deletion, /Already started/);
    assert.deepEqual(composerDraft(f.state), before);
    assert.equal(f.state.data.turns.length, succeeds ? 0 : 1);
    assert.equal(f.state.data.messages.length, succeeds ? 0 : 1);
  }
});

test("an unquoted queued edit exposes its pinned conversation and survives view draft and reload serialization", async () => {
  const f = fixture();
  delete f.turn.replyToId;
  delete f.message.replyToId;
  const edit = f.queue.handleClick(f.button("edit-queued"));
  f.pending.resolve(f.result);
  await edit;
  const saved = JSON.parse(JSON.stringify(composerDraft(f.state)));
  restoreComposerDraft(f.state);
  restoreComposerDraft(f.state, saved);
  const actions = createMessageActions({ state: f.state, root: f.root, api() {}, render() {} });
  assert.match(actions.preview(), /Layout/);
  assert.match(actions.preview(), /dismiss-queued-edit/);
  assert.equal(f.state.replyToId, null);
  assert.equal(f.state.queuedEdit.sessionId, "session");
  restoreComposerDraft(f.state, f.state.queuedEdit.previous);
  assert.equal(f.state.input, "My existing draft");
});

test("changing views while dequeue is pending keeps the withdrawn draft in the original view", async () => {
  const f = fixture();
  const edit = f.queue.handleClick(f.button("edit-queued"));
  f.state.sessionDrafts.home = composerDraft(f.state);
  f.state.selected = "other";
  restoreComposerDraft(f.state, { input: "Other conversation draft" });
  f.pending.resolve(f.result);
  await edit;
  assert.equal(f.state.input, "Other conversation draft");
  assert.equal(f.state.queuedEdit, null);
  assert.equal(f.state.sessionDrafts.home.input, "Change the padding");
  assert.equal(f.state.sessionDrafts.home.queuedEdit.previous.input, "My existing draft");
});

test("session queue controls are visible and include only waiting messages in that conversation", () => {
  const f = fixture();
  f.state.selected = "session";
  f.state.data.turns.push({ ...f.turn, id: "running", status: "running" }, { ...f.turn, id: "other", sessionId: "other" });
  const html = f.queue.composer();
  assert.match(html, /queue-action/);
  assert.match(html, /Edit queued message/);
  assert.match(html, /Delete queued message/);
  assert.match(html, /Steer with this message/);
  assert.doesNotMatch(html, /data-turn="(?:running|other)"/);
  assert.match(f.queue.controls(f.turn, true), /reply-action/);
  f.state.data.turns = [f.turn];
  assert.doesNotMatch(f.queue.composer(), /Steer with this message/);
});

test("steering a queued row preserves the draft and original message, and failure keeps the row queued", async () => {
  for (const succeeds of [true, false]) {
    const f = fixture();
    const before = composerDraft(f.state);
    const request = f.queue.handleClick(f.button("steer-queued"));
    await f.queue.handleClick(f.button("steer-queued"));
    assert.equal(f.requests.length, 1);
    assert.equal(f.requests[0].path, "/api/steer-queued");
    if (succeeds) f.pending.resolve({ turn: f.turn, steered: true });
    else f.pending.reject(new Error("No active work"));
    if (succeeds) await request;
    else await assert.rejects(request, /No active work/);
    assert.deepEqual(composerDraft(f.state), before);
    assert.deepEqual(f.state.data.messages, [f.message]);
    assert.equal(f.state.data.turns.length, succeeds ? 0 : 1);
  }
});
