import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import vm from "node:vm";

const source = readFileSync(new URL("./hook.js", import.meta.url), "utf8");
const settle = () => new Promise(resolve => setImmediate(resolve));

// All identities and session data in these fixtures are synthetic.
function fixture({ self = true, onPost } = {}) {
  const calls = [], sockets = [], timers = new Map(), logs = [];
  let serial = 0;
  class Element {
    children = [];
    style = {};
    listeners = {};
    append(child) { this.children.push(child); }
    get firstChild() { return this.children[0]; }
    addEventListener(name, callback) { this.listeners[name] = callback; }
    remove() { this.removed = true; }
  }
  class Socket {
    readyState = 1;
    constructor(url) { this.url = url; sockets.push(this); }
    event(event) { this.onmessage({ data: JSON.stringify(event) }); }
    send() {}
    close() { this.readyState = 3; this.onclose?.(); }
  }
  const page = {
    location: { origin: "https://app.slack.com", pathname: "/client/ETEST/DSELF" },
    localStorage: { getItem: () => JSON.stringify({ teams: { ETEST: { token: ["xoxc", "fixture"].join("-") } } }) },
    crypto: { randomUUID: () => `fixture-${++serial}` },
    document: { createElement: () => new Element(), createTextNode: text => ({ textContent: text }), body: new Element() },
    WebSocket: Socket,
    async fetch(url, options) {
      const method = url.split("/").at(-1);
      const values = Object.fromEntries(options.body);
      calls.push({ method, values, options });
      let result;
      if (method === "auth.test") result = { user_id: "UTEST" };
      if (method === "conversations.info") result = { channel: { is_im: true, user: self ? "UTEST" : "UOTHER" } };
      if (method === "team.info") result = { team: { id: "ETEST" } };
      if (method === "chat.postMessage") {
        onPost?.(values, sockets[0]);
        result = { ts: "2000000010.000001" };
      }
      return { ok: true, json: async () => ({ ok: true, ...result }) };
    },
    setTimeout: fn => { const id = ++serial; timers.set(id, fn); return id; },
    clearTimeout: id => timers.delete(id),
    setInterval: fn => { const id = ++serial; timers.set(id, fn); return id; },
    clearInterval: id => timers.delete(id),
    addEventListener() {}, removeEventListener() {},
  };
  vm.runInNewContext(source, { window: page, URLSearchParams,
    Date: { now: () => 2000000000000 }, console: { info: text => logs.push(text), warn: text => logs.push(text) } });
  return { page, calls, sockets, timers, logs, posts: () => calls.filter(call => call.method === "chat.postMessage") };
}

const message = (extra = {}) => ({ type: "message", channel: "DSELF", user: "UTEST",
  ts: "2000000001.000001", text: "hook ping", ...extra });

test("uses only Slack's same-origin authenticated API and self-DM event stream", async () => {
  const f = fixture();
  await settle();
  assert.equal(f.sockets.length, 1);
  const url = new URL(f.sockets[0].url);
  assert.equal(url.origin, "wss://wss-primary.slack.com");
  assert.equal(url.searchParams.get("gateway_server"), "ETEST-1");
  f.sockets[0].event({ type: "hello" });
  f.sockets[0].event(message());
  await settle();
  assert.equal(f.posts().length, 1);
  assert.equal(f.posts()[0].values.channel, "DSELF");
  assert.equal(f.posts()[0].values.thread_ts, "2000000001.000001");
  assert.equal(f.posts()[0].values.text, "🤖 Browser hook received: ping");
  assert.ok(f.calls.every(call => call.options.credentials === "include" && call.options.redirect === "error"));
  assert.ok(!JSON.stringify(f.page.agentHooks.status()).includes("xoxc"));
  assert.ok(!f.logs.join(" ").includes("xoxc"));
});

test("ignores other people, channels, old messages, edits, apps, and duplicates", async () => {
  const f = fixture();
  await settle();
  const socket = f.sockets[0];
  for (const extra of [{ user: "UOTHER" }, { channel: "DOTHER" }, { channel: "CTEST" },
    { ts: "1999999999.000001" }, { subtype: "message_changed" }, { bot_id: "BTEST" },
    { app_id: "ATEST" }, { text: "hello" }, { text: "hook " }]) socket.event(message(extra));
  socket.event(message());
  socket.event(message());
  await settle();
  assert.equal(f.posts().length, 1);
});

test("refuses to start in another person's DM", async () => {
  const f = fixture({ self: false });
  await settle();
  assert.equal(f.sockets.length, 0);
  assert.equal(f.page.agentHooks.status().running, false);
  assert.match(f.page.agentHooks.status().error, /own self-DM/);
});

test("serializes follow-ups within a thread and suppresses own sends before HTTP completes", async () => {
  const f = fixture({ onPost(values, socket) {
    socket.event(message({ ts: "2000000010.000001", text: values.text, client_msg_id: values.client_msg_id }));
  } });
  await settle();
  let finish;
  const requests = [];
  f.page.agentHooks.setHandler(request => {
    requests.push(request);
    return requests.length === 1 ? new Promise(resolve => { finish = resolve; }) : "hook second answer";
  });
  const socket = f.sockets[0];
  socket.event(message());
  socket.event(message({ ts: "2000000002.000001", thread_ts: "2000000001.000001", text: "hook second" }));
  await settle();
  assert.equal(requests.length, 1);
  finish("hook first answer");
  await settle();
  assert.equal(requests.length, 2);
  assert.equal(f.posts().length, 2);
  assert.equal(f.posts()[1].values.thread_ts, "2000000001.000001");
  assert.ok(!("token" in requests[0]));
});

test("Stop cancels pending handler replies, timers, and the socket", async () => {
  const f = fixture();
  await settle();
  let finish;
  f.page.agentHooks.setHandler(() => new Promise(resolve => { finish = resolve; }));
  f.sockets[0].event(message());
  await settle();
  f.page.agentHooks.stop();
  finish("do not send");
  await settle();
  assert.equal(f.posts().length, 0);
  assert.equal(f.timers.size, 0);
  assert.equal(f.sockets[0].readyState, 3);
});
