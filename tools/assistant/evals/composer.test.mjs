import assert from "node:assert/strict";
import { once } from "node:events";
import { before, after, test } from "node:test";
import { chromium } from "playwright";
import { createAssistantServer } from "../src/http-server.ts";
import { Assistant } from "../src/assistant.ts";

let browser;
before(async () => { browser = await chromium.launch({ channel: process.env.ASSISTANT_BROWSER_CHANNEL || "chrome" }); });
after(async () => { await browser?.close(); });

async function fixture(t, { suggestion = null, empty = false } = {}) {
  const listeners = new Set();
  const watchers = new Map();
  const calls = [];
  const data = { messages: [], entries: [], sessions: [], turns: [] };
  for (const id of empty ? [] : ["1", "2"]) {
    const createdAt = `2026-01-01T00:00:0${id}.000Z`;
    data.sessions.push({ id, title: `Conversation ${id}`, status: "idle" });
    data.messages.push({ id: `request-${id}`, entryId: `entry-${id}`, text: `Request ${id}`, createdAt, status: "routed" });
    data.entries.push({ id: `entry-${id}`, sourceId: `request-${id}`, sessionId: id, title: `Conversation ${id}`, status: "ready",
      updates: [{ id: `reply-${id}`, sourceId: `request-${id}`, text: `Reply ${id}`, kind: "result", createdAt }] });
  }
  const app = {
    snapshot: () => data,
    progress: () => [],
    subscribe: listener => { listeners.add(listener); return () => listeners.delete(listener); },
    pi: { providers: { snapshot: async () => ({ selected: { provider: "fixture", modelId: "fixture" }, providers: [] }), subscribe: () => () => {} } },
    transcript: id => ({ messages: [{ id: `reply-${id}`, role: "assistant", text: `Reply ${id}`, replyable: true, completed: true }], streaming: "" }),
    watchConversation: async (id, send) => {
      watchers.set(id, send);
      await send({ type: "conversation", sessionId: id, ...app.transcript(id) });
      return { stop: async () => { if (watchers.get(id) === send) watchers.delete(id); } };
    },
    suggestion: async () => ({ text: suggestion }),
    submitSession: async (sessionId, text, mode, options) => { calls.push({ sessionId, text, mode, ...options }); return {}; },
    submitHome: async (text, id) => { calls.push({ text, id }); return {}; },
    dequeue: async (_sessionId, id) => {
      const turn = data.turns.find(turn => turn.id === id);
      const message = data.messages.find(message => message.id === turn.sourceId);
      data.turns = data.turns.filter(turn => turn.id !== id);
      data.messages = data.messages.filter(item => item.id !== message?.id);
      return { turn, message, removedMessageId: message?.id };
    },
  };
  const { server, close } = createAssistantServer(app);
  server.listen(0, "127.0.0.1");
  await once(server, "listening");
  const context = await browser.newContext();
  const page = await context.newPage();
  const errors = [];
  page.on("pageerror", error => errors.push(error.message));
  t.after(async () => { await context.close(); await close(); assert.deepEqual(errors, []); });
  await page.goto(`http://127.0.0.1:${server.address().port}`);
  if (!empty) await page.getByText("Reply 1", { exact: true }).waitFor();
  else await page.locator(".landing-mark").waitFor();
  await page.evaluate(() => {
    window.originalComposer = document.querySelector("textarea");
    window.composerDetached = false;
    new MutationObserver(records => {
      for (const record of records) for (const node of record.removedNodes)
        if (node === window.originalComposer || node.contains?.(window.originalComposer)) window.composerDetached = true;
    }).observe(document.querySelector("#app"), { childList: true, subtree: true });
  });
  const input = page.getByRole("textbox", { name: "Message", exact: true });
  const emit = event => { for (const listener of listeners) listener(event); };
  const snapshot = () => emit({ type: "snapshot", data });
  const focused = async () => assert.equal(await input.evaluate(input => input === window.originalComposer && document.activeElement === input && !window.composerDetached), true);
  return { page, input, app, data, calls, server, watchers, emit, snapshot, focused };
}

async function clickReply(page, id = "1") { await page.locator(`[data-action="reply"][data-reply="reply-${id}"]`).click(); }
async function send(page, input, text) {
  await input.fill(text);
  const response = page.waitForResponse(response => response.url().endsWith("/api/turns") && response.request().method() === "POST");
  await input.press("Enter");
  await response;
}

test("reply submission preserves the composer, selection, and typing through live updates", async t => {
  const { page, input, data, calls, emit, snapshot, focused } = await fixture(t);
  await input.fill("Draft text");
  await input.evaluate(input => input.setSelectionRange(2, 5, "backward"));
  await clickReply(page);
  await focused();
  assert.deepEqual(await input.evaluate(input => [input.selectionStart, input.selectionEnd, input.selectionDirection]), [2, 5, "backward"]);
  data.sessions[0].status = "running";
  data.turns.push({ id: "active", sourceId: "request-1", sessionId: "1", text: "Request 1", status: "running" });
  for (let i = 0; i < 12; i++) { snapshot(); emit({ type: "progress", sourceId: "request-1", text: `Checking the result ${i}` }); }
  await page.getByText("Checking the result 11", { exact: true }).waitFor();
  await focused();
  assert.equal(await input.inputValue(), "Draft text");
  assert.deepEqual(await input.evaluate(input => [input.selectionStart, input.selectionEnd]), [2, 5]);
  await input.dispatchEvent("keydown", { key: "Enter", isComposing: true });
  assert.equal(calls.length, 0);
  await send(page, input, "Follow-up");
  await focused();
  assert.equal(calls.at(-1).replyToId, "reply-1");
  assert.equal(calls.at(-1).sessionId, "1");
  assert.equal(await input.inputValue(), "");
  await input.fill("Next draft");
  snapshot();
  await focused();
  assert.equal(await input.inputValue(), "Next draft");
});

test("drafts, reply suggestions, edits, and queued edits share the persistent composer", async t => {
  const { page, input, data, snapshot, focused } = await fixture(t, { suggestion: "Suggested follow-up" });
  await page.locator(".prompt-suggestion:not([hidden])").waitFor();
  await input.focus();
  await input.press("Tab");
  assert.equal(await input.inputValue(), "Suggested follow-up");
  await focused();
  await input.press("Escape");
  assert.equal(await input.inputValue(), "");
  await input.fill("Home draft");
  await page.locator('.home-update[data-session="1"]').click();
  await page.locator(".session-scroll").waitFor();
  assert.equal(await input.inputValue(), "");
  await input.fill("Session draft");
  await clickReply(page);
  await focused();
  data.turns.push({ id: "queued", sourceId: "queued", sessionId: "1", text: "Queued text", status: "queued" });
  data.messages.push({ id: "queued", text: "Queued text", entryId: "entry-1", status: "routed", createdAt: "2026-01-02T00:00:00.000Z" });
  snapshot();
  await page.locator('.queued-card [data-action="edit-queued"]').click();
  await page.getByRole("button", { name: "Cancel edit", exact: true }).waitFor();
  assert.equal(await input.inputValue(), "Queued text");
  await focused();
  await page.getByRole("button", { name: "Cancel edit", exact: true }).click();
  assert.equal(await input.inputValue(), "Session draft");
  await focused();
  await page.getByRole("button", { name: /Back to Home/ }).click();
  assert.equal(await input.inputValue(), "Home draft");
  data.sessions[0].status = "running";
  data.turns.push({ id: "active", sourceId: "request-1", sessionId: "1", text: "Request 1", status: "running" });
  snapshot();
  await page.locator('[data-action="edit"][data-edit="request-1"]').click();
  assert.equal(await input.inputValue(), "Request 1");
  await input.fill("Revised request");
  const response = page.waitForResponse(response => response.url().endsWith("/api/turns"));
  await page.getByRole("button", { name: "Send", exact: true }).click();
  await response;
  await focused();
  assert.equal(await input.inputValue(), "Home draft");
  await page.reload();
  await input.waitFor();
  assert.equal(await input.inputValue(), "Home draft");
});

test("session streaming and an SSE reconnect keep focus and the original textarea", async t => {
  const { page, input, server, watchers, focused } = await fixture(t);
  await page.locator('.home-update[data-session="1"]').click();
  await page.locator(".session-scroll").waitFor();
  await clickReply(page);
  await input.fill("Keep typing");
  const origin = await page.evaluate(() => performance.timeOrigin);
  for (let i = 0; i < 12; i++) await watchers.get("1")({ type: "conversation", sessionId: "1",
    messages: [{ id: "reply-1", role: "assistant", text: "Reply 1", replyable: true, completed: true }], streaming: `Progress ${i}` });
  await page.getByText("Progress 11", { exact: true }).waitFor();
  await focused();
  server.closeAllConnections();
  await page.waitForFunction(() => document.querySelector(".connection-dot.online") === null);
  await page.waitForFunction(() => document.querySelector(".session-scroll .message-text")?.textContent === "Reply 1" && !document.querySelector(".session-scroll").textContent.includes("Progress 11"));
  assert.equal(await page.evaluate(() => performance.timeOrigin), origin);
  assert.equal(await input.inputValue(), "Keep typing");
  await focused();
});

test("failed sends restore the reply without overwriting newer typing", async t => {
  const { page, input, app, focused } = await fixture(t);
  app.submitSession = async () => { throw new Error("Please retry"); };
  await clickReply(page);
  await send(page, input, "Retry this reply");
  await page.getByText("Please retry", { exact: true }).waitFor();
  assert.equal(await input.inputValue(), "Retry this reply");
  await focused();
  const received = Promise.withResolvers();
  const pending = Promise.withResolvers();
  app.submitSession = async () => { received.resolve(); return pending.promise; };
  await input.press("Enter");
  await received.promise;
  await input.fill("Newer draft");
  const response = page.waitForResponse(response => response.url().endsWith("/api/turns"));
  pending.reject(new Error("Please retry"));
  await response;
  await page.getByText("Please retry", { exact: true }).waitFor();
  assert.equal(await input.inputValue(), "Newer draft");
  await focused();
});

test("minimal landing keeps its animation and the composer mounted when work starts", async t => {
  const { page, input, calls, focused } = await fixture(t, { empty: true });
  assert.equal((await page.locator(".landing").textContent()).trim(), "");
  assert.equal(await page.locator(".landing button, .landing-prompts").count(), 0);
  assert.notEqual(await page.locator(".landing-spark").evaluate(node => getComputedStyle(node).animationName), "none");
  assert.equal(await input.inputValue(), "");
  assert.equal(calls.length, 0);
  await page.emulateMedia({ reducedMotion: "reduce" });
  assert.equal(await page.locator(".landing-spark, .landing-glow").evaluateAll(nodes => nodes.every(node => getComputedStyle(node).animationName === "none")), true);
  await page.setViewportSize({ width: 390, height: 844 });
  const fits = await input.evaluate(node => { const bounds = node.getBoundingClientRect(); return bounds.left >= 0 && bounds.right <= innerWidth && bounds.bottom <= innerHeight; });
  assert.equal(fits, true);
  await input.fill("Let's start");
  const response = page.waitForResponse(response => response.url().endsWith("/api/home"));
  await input.press("Enter");
  await response;
  assert.equal(calls.length, 1);
  assert.equal(calls[0].text, "Let's start");
  assert.equal(await page.locator(".landing").count(), 0);
  assert.equal(await page.getByRole("navigation", { name: "Starting points" }).isVisible(), false);
  await focused();
});

test("UI progress excludes tool activity and private reasoning", () => {
  const message = { role: "assistant", content: [{ type: "thinking", thinking: "Private reasoning" }, { type: "toolCall", name: "bash", arguments: { command: "secret" } }] };
  const app = { snapshot: () => ({ turns: [{ status: "running", sessionId: "1", sourceId: "request-1" }] }),
    state: { home: { sessions: [{ id: "1", conversationId: 1 }] }, live: () => ({ generation: { message }, tools: [{ name: "bash", status: "running" }] }) } };
  assert.deepEqual(Assistant.prototype.progress.call(app), []);
  message.content.push({ type: "text", text: "Checking the result" });
  assert.deepEqual(Assistant.prototype.progress.call(app), [{ type: "progress", sourceId: "request-1", text: "Checking the result" }]);
});
