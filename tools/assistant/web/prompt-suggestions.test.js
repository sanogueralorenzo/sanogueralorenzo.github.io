import assert from "node:assert/strict";
import { test } from "node:test";
import { createPromptSuggestions, suggestionTarget } from "./prompt-suggestions.js";

const tick = () => new Promise(setImmediate);
function fixture() {
  const state = { connected: true, selected: "home", input: "", replyToId: null, edit: null, transcript: [], data: {
    sessions: [{ id: "one", status: "idle" }, { id: "two", status: "idle" }], turns: [], messages: [{ status: "routed", createdAt: "1" }],
    entries: [{ sessionId: "one", updates: [{ id: "reply-one", kind: "result", createdAt: "2" }] }],
  } };
  const span = { textContent: "" };
  const attributes = new Map();
  const textarea = { placeholder: "Message", focus() {}, setSelectionRange() {}, setAttribute: (key, value) => attributes.set(key, value), removeAttribute: key => attributes.delete(key) };
  const button = { setAttribute: (key, value) => attributes.set(key, value) };
  const overlay = { hidden: true, querySelector: selector => selector === "span" ? span : button };
  const root = { querySelector: selector => selector === ".prompt-suggestion" ? overlay : textarea };
  const requests = [];
  let renders = 0;
  const suggestions = createPromptSuggestions({ state, root, render: () => renders++, api: (_path, _method, body) => {
    const request = { ...body, ...Promise.withResolvers() };
    requests.push(request);
    return request.promise;
  } });
  return { state, overlay, textarea, span, requests, suggestions, renders: () => renders };
}

test("typing hides pending hints and clearing the draft restores the saved hint", async () => {
  const f = fixture();
  f.suggestions.sync();
  f.suggestions.sync();
  assert.equal(f.requests.length, 1);
  f.state.input = "My own draft";
  f.suggestions.dismiss("draft");
  f.requests[0].resolve({ text: "Show the mockup." });
  await tick();
  assert.equal(f.state.input, "My own draft");
  assert.equal(f.overlay.hidden, true);
  f.state.input = "";
  f.suggestions.dismiss("draft");
  assert.equal(f.overlay.hidden, false);
  assert.equal(f.span.textContent, "Show the mockup.");
  assert.equal(f.requests.length, 1);
});

test("an accepted hint can be reused after clearing both draft and quote in either order", async () => {
  for (const quoteFirst of [false, true]) {
    const f = fixture();
    f.suggestions.sync();
    f.requests[0].resolve({ text: "Show the mockup." });
    await tick();
    assert.equal(f.suggestions.accept(), true);
    if (quoteFirst) f.state.replyToId = null;
    else f.state.input = "";
    f.suggestions.dismiss("draft");
    assert.equal(f.overlay.hidden, true);
    f.state.input = "";
    f.state.replyToId = null;
    f.suggestions.sync();
    assert.equal(f.overlay.hidden, false);
    assert.equal(f.suggestions.accept(), true);
    assert.equal(f.state.input, "Show the mockup.");
    assert.equal(f.state.replyToId, "reply-one");
    assert.equal(f.requests.length, 1);
  }
});

test("Escape hides a hint but Tab can restore it; no suggestion never fills or quotes", async () => {
  const f = fixture();
  f.suggestions.sync();
  f.requests[0].resolve({ text: "Show the mockup." });
  await tick();
  f.suggestions.dismiss();
  f.suggestions.sync();
  assert.equal(f.overlay.hidden, true);
  assert.equal(f.suggestions.accept(), true);
  assert.equal(f.state.input, "Show the mockup.");
  assert.equal(f.state.replyToId, "reply-one");
  f.suggestions.escape();
  f.state.data.entries[0].updates.push({ id: "newer", kind: "result", createdAt: "3" });
  f.suggestions.sync();
  f.requests[1].resolve({ text: null });
  await tick();
  assert.equal(f.textarea.placeholder, "Message");
  assert.equal(f.suggestions.accept(), false);
  assert.equal(f.state.replyToId, null);
});

test("Escape restores the visible accepted hint in Home and sessions without another request", async () => {
  for (const selected of ["home", "one"]) {
    const f = fixture();
    f.state.selected = selected;
    f.state.transcript = [{ id: "reply-one", role: "assistant", completed: true }];
    f.suggestions.sync();
    f.requests[0].resolve({ text: "Show the mockup." });
    await tick();
    for (let repeat = 0; repeat < 3; repeat++) {
      assert.equal(f.suggestions.accept(), true);
      assert.equal(f.state.input, "Show the mockup.");
      assert.equal(f.state.replyToId, "reply-one");
      assert.equal(f.suggestions.escape(), true);
      assert.equal(f.state.input, "");
      assert.equal(f.state.replyToId, null);
      assert.equal(f.overlay.hidden, false);
      assert.equal(f.span.textContent, "Show the mockup.");
      assert.equal(f.textarea.placeholder, "");
      f.suggestions.sync();
      assert.equal(f.overlay.hidden, false);
      assert.equal(f.textarea.placeholder, "");
    }
    assert.equal(f.requests.length, 1);
  }
});

test("Tab cannot restore a dismissed hint during work or after the reply changes", async () => {
  const f = fixture();
  f.suggestions.sync();
  f.requests[0].resolve({ text: "Show the mockup." });
  await tick();
  f.suggestions.escape();
  f.state.data.turns.push({ sessionId: "one" });
  assert.equal(f.suggestions.accept(), false);
  f.state.data.turns.length = 0;
  f.state.data.entries[0].updates.push({ id: "newer", kind: "result", createdAt: "3" });
  f.suggestions.sync();
  assert.equal(f.suggestions.accept(), false);
  f.requests[1].resolve({ text: null });
  await tick();
  assert.equal(f.suggestions.accept(), false);
  assert.equal(f.state.input, "");
  assert.equal(f.state.replyToId, null);
});

test("Escape only removes the quote from custom or edited drafts", async () => {
  const f = fixture();
  f.suggestions.sync();
  f.requests[0].resolve({ text: "Show the mockup." });
  await tick();
  for (const draft of ["Show the mockup first.", "Show the mockup. ", "My own reply", ""]) {
    for (const replyToId of ["reply-one", "older"]) {
      f.state.input = draft;
      f.state.replyToId = replyToId;
      assert.equal(f.suggestions.escape(), true);
      assert.equal(f.state.input, draft);
      assert.equal(f.state.replyToId, null);
    }
  }
  f.suggestions.accept();
  f.state.input = "";
  f.suggestions.dismiss("draft");
  f.suggestions.escape();
  f.suggestions.sync();
  assert.equal(f.overlay.hidden, false);
});

test("Escape still recognizes the accepted hint when another conversation finishes", async () => {
  const f = fixture();
  f.suggestions.sync();
  f.requests[0].resolve({ text: "Show the mockup." });
  await tick();
  f.suggestions.accept();
  f.state.data.entries.push({ sessionId: "two", updates: [{ id: "reply-two", kind: "result", createdAt: "3" }] });
  f.suggestions.sync();
  f.suggestions.escape();
  assert.equal(f.state.input, "");
  assert.equal(f.state.replyToId, null);
});

test("Escape compares persisted suggestions after reload, even with a nonempty draft", async () => {
  const f = fixture();
  f.state.input = "Show the mockup.";
  f.state.replyToId = "reply-one";
  f.suggestions.sync();
  assert.equal(f.requests.length, 1);
  f.requests[0].resolve({ text: "Show the mockup." });
  await tick();
  f.suggestions.escape();
  assert.equal(f.state.input, "");
  assert.equal(f.state.replyToId, null);
  assert.equal(f.overlay.hidden, false);
  assert.equal(f.span.textContent, "Show the mockup.");
  assert.equal(f.textarea.placeholder, "");
  f.state.input = "Show the mockup.";
  f.suggestions.escape();
  assert.equal(f.state.input, "");
  f.state.edit = { id: "active-request" };
  f.state.input = "Show the mockup.";
  assert.equal(f.suggestions.escape(), false);
  assert.equal(f.state.input, "Show the mockup.");
});

test("out-of-order responses cannot replace the newest hint; accepting pins its origin without sending", async () => {
  const f = fixture();
  f.suggestions.sync();
  f.state.data.entries.push({ sessionId: "two", updates: [{ id: "reply-two", kind: "result", createdAt: "3" }] });
  f.suggestions.sync();
  f.requests[1].resolve({ text: "Run the verification." });
  await tick();
  f.requests[0].resolve({ text: "Show the mockup." });
  await tick();
  assert.equal(f.span.textContent, "Run the verification.");
  assert.equal(f.suggestions.accept(), true);
  assert.equal(f.state.input, "Run the verification.");
  assert.equal(f.state.replyToId, "reply-two");
  assert.equal(f.renders(), 1);
  assert.equal(f.requests.length, 2);
});

test("hints stay scoped to idle completed context and do not interfere with quotes or queued work", () => {
  const { state } = fixture();
  assert.deepEqual(suggestionTarget(state), { sessionId: "one", replyId: "reply-one" });
  state.replyToId = "older";
  assert.equal(suggestionTarget(state), null);
  state.replyToId = null;
  state.data.turns.push({ sessionId: "one" });
  assert.equal(suggestionTarget(state), null);
  state.data.turns.length = 0;
  state.data.entries[0].updates.push({ id: "error", kind: "error", createdAt: "3" });
  assert.equal(suggestionTarget(state), null);
  state.selected = "two";
  state.transcript = [{ id: "commentary", role: "assistant", completed: false }];
  assert.equal(suggestionTarget(state), null);
  state.transcript = [{ id: "final", role: "assistant", completed: true }];
  assert.deepEqual(suggestionTarget(state), { sessionId: "two", replyId: "final" });
  state.connected = false;
  assert.equal(suggestionTarget(state), null);
});
