import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import vm from "node:vm";

const source = readFileSync(new URL("./hook.js", import.meta.url), "utf8");
const settle = async () => { for (let i = 0; i < 10; i++) await new Promise(resolve => setImmediate(resolve)); };
function locks() {
  const held = new Set();
  return { async request(key, _options, fn) {
    if (held.has(key)) return fn(null);
    held.add(key); try { return await fn({ name: key }); } finally { held.delete(key); }
  } };
}
function fixture({ manager = locks(), action, failPost = false } = {}) {
  const calls = [], sockets = [], timers = new Map(), messages = [], listeners = new Map();
  let serial = 0, token = 'fixture', user = 'UTEST';
  class Socket {
    readyState = 1;
    constructor(url) { this.url = url; sockets.push(this); }
    event(value) { this.onmessage?.({ data: JSON.stringify(value) }); }
    send() {}
    close() { this.readyState = 3; this.onclose?.(); }
  }
  const page = {
    location: { origin: 'https://app.slack.com', pathname: '/client/ETEST/CGENERAL' },
    navigator: { locks: manager },
    localStorage: { getItem: () => JSON.stringify({ teams: { ETEST: { token: ['xoxc', token].join('-') } } }) },
    crypto: { randomUUID: () => `fixture-${++serial}` },
    WebSocket: Socket,
    async fetch(url, options) {
      const method = url.split('/').at(-1), values = Object.fromEntries(options.body);
      calls.push({ method, values, options });
      if (method === 'chat.postMessage' && failPost) throw new Error('Unknown network delivery');
      let result = {};
      if (method === 'auth.test') result = { user_id: user };
      if (method === 'team.info') result = { team: { id: 'ETEST' } };
      if (method === 'conversations.replies') result = { messages: [message({ ts: '2000000001.000001', text: 'Earlier context' })] };
      if (method === 'chat.postMessage') {
        result = { ts: `2000000099.${String(++serial).padStart(6, '0')}` };
        sockets.at(-1).event(message({ ts: result.ts, text: values.markdown_text, channel: values.channel, client_msg_id: values.client_msg_id }));
      }
      return { ok: true, json: async () => ({ ok: true, ...result }) };
    },
    setTimeout: fn => { const id = ++serial; timers.set(id, fn); return id; },
    clearTimeout: id => timers.delete(id),
    setInterval: fn => { const id = ++serial; timers.set(id, fn); return id; },
    clearInterval: id => timers.delete(id),
    addEventListener(name, fn) { if (!listeners.has(name)) listeners.set(name, new Set()); listeners.get(name).add(fn); },
    removeEventListener(name, fn) { listeners.get(name)?.delete(fn); },
    postMessage(data) {
      messages.push(data);
      if (data.type === 'request') {
        const value = action ? action(data) : data.action === 'run'
          ? { job: `job-${data.id}`, answer: 'Test agent answer' }
          : data.action === 'claim' ? { claimed: true } : { ok: true };
        Promise.resolve(value).then(result => respond(data.id, result));
      }
    },
  };
  function respond(id, value) { for (const fn of listeners.get('message') || []) fn({ source: page, origin: page.location.origin, data: { source: 'browser-hooks-extension', type: 'response', id, ok: true, value } }); }
  vm.runInNewContext(source, { window: page, URLSearchParams, AbortController, AbortSignal, Date: { now: () => 2000000000000 } });
  return { page, calls, sockets, messages, timers, respond,
    configure: (options = {}) => page.agentHooks.configure({ keywords: ['hook'], ...options }),
    tick: () => { for (const fn of [...timers.values()]) fn(); },
    token: value => { token = value; }, user: value => { user = value; },
    posts: () => calls.filter(c => c.method === 'chat.postMessage') };
}
const message = (extra = {}) => ({ type: 'message', channel: 'DSELF', user: 'UTEST', ts: '2000000002.000001', text: 'hook ping', ...extra });

test('starts from any Slack view and replies in public/private channels, DMs and group DMs', async () => {
  const f = fixture(); f.configure(); await settle();
  assert.equal(f.sockets.length, 1);
  f.sockets[0].event({ type: 'hello' });
  for (const channel of ['DSELF', 'DOTHER', 'CPUBLIC', 'GPRIVATE', 'GGROUP']) f.sockets[0].event(message({ channel }));
  await settle();
  assert.equal(f.posts().length, 5);
  assert.ok(f.posts().every(p => p.values.thread_ts === '2000000002.000001'));
  assert.ok(f.posts().every(p => p.values.markdown_text === 'Test agent answer' && !('text' in p.values)));
  assert.ok(f.calls.every(c => c.options.credentials === 'same-origin' && c.options.redirect === 'error'));
  assert.ok(!JSON.stringify(f.page.agentHooks.status()).includes('xoxc'));
  assert.ok(!JSON.stringify(f.messages).includes('xoxc'));
});

test('only own new keyword-prefixed messages trigger; ignores duplicates, edits, apps, empty requests', async () => {
  const f = fixture(); f.configure({ keywords: ['code'] }); await settle();
  const socket = f.sockets[0];
  for (const extra of [{ user: 'UOTHER' }, { ts: '1999999999.000001' }, { subtype: 'message_changed' }, { bot_id: 'BTEST' },
    { app_id: 'ATEST' }, { text: 'hook ping' }, { text: ' code ping' }, { text: 'code ' }, { channel: '' }]) socket.event(message({ text: 'code ping', ...extra }));
  socket.event(message({ text: 'CoDe\tping' })); socket.event(message({ text: 'CoDe\tping' }));
  await settle(); assert.equal(f.posts().length, 1);
});

test('queues each channel/thread in order while different conversations run concurrently', async () => {
  const waits = [], requests = [];
  const f = fixture({ action(data) {
    if (data.action === 'run') { requests.push(data.payload); return new Promise(resolve => waits.push(resolve)); }
    if (data.action === 'claim') return { claimed: true };
    return { ok: true };
  } });
  f.configure(); await settle();
  f.sockets[0].event(message());
  f.sockets[0].event(message({ ts: '2000000003.000001', thread_ts: '2000000002.000001' }));
  f.sockets[0].event(message({ channel: 'COTHER' }));
  await settle(); assert.equal(requests.length, 2);
  waits[0]({ job: 'one', answer: 'hook answer with a keyword must not loop' });
  await settle(); assert.equal(requests.length, 3);
  assert.equal(requests[2].messages.length, 1);
  waits[1]({ job: 'two', answer: 'second channel' }); waits[2]({ job: 'three', answer: 'same thread' });
  await settle(); assert.equal(f.posts().length, 3);
  assert.equal(f.page.agentHooks.status().pending, 0);
});

test('one workspace leader prevents duplicate replies across tabs; another tab takes over after close', async () => {
  const manager = locks(), a = fixture({ manager }), b = fixture({ manager });
  a.configure(); b.configure(); await settle();
  assert.equal(a.sockets.length + b.sockets.length, 1);
  assert.equal(b.page.agentHooks.status().standby, true);
  a.page.agentHooks.dispose(); await settle(); b.tick(); await settle();
  assert.equal(b.sockets.length, 1);
  b.page.agentHooks.dispose();
});

test('reload/dispose and account changes cancel queued sends and release the socket', async () => {
  let finish;
  const f = fixture({ action: () => new Promise(resolve => { finish = resolve; }) });
  f.configure(); await settle(); f.sockets[0].event(message()); await settle();
  f.token('changed'); f.tick(); await settle();
  finish({ job: 'one', answer: 'must not send' }); await settle();
  assert.equal(f.posts().length, 0);
  assert.equal(f.sockets[0].readyState, 3);
  f.page.agentHooks.dispose(); assert.equal(f.timers.size, 0);
});

test('uncertain Slack delivery is not retried and later duplicate events do not send again', async () => {
  const f = fixture({ failPost: true }); f.configure(); await settle();
  f.sockets[0].event(message()); await settle(); f.sockets[0].event(message()); await settle();
  assert.equal(f.posts().length, 1);
  assert.ok(f.calls.some(c => c.method === 'reactions.remove'));
});

test('a delivery claim denied by the bridge prevents sending', async () => {
  const f = fixture({ action: d => d.action === 'run' ? { job: 'test', answer: 'answer' } : { claimed: false } });
  f.configure(); await settle(); f.sockets[0].event(message()); await settle();
  assert.equal(f.posts().length, 0);
});

test('reconnect preserves admission state and uses only Slack fixed socket origin', async () => {
  const f = fixture(); f.configure(); await settle(); f.sockets[0].event(message()); await settle();
  f.sockets[0].close(); f.tick(); await settle();
  const socket = f.sockets.at(-1);
  assert.equal(new URL(socket.url).origin, 'wss://wss-primary.slack.com');
  socket.event(message()); await settle(); assert.equal(f.posts().length, 1);
});

test('CLI failures post one actionable diagnostic with warning, never a success reaction', async () => {
  const messageText = 'Claude login expired. Run `claude auth login` on your computer.';
  const f = fixture({ action: d => d.action === 'run'
    ? { job: 'test', error: { code: 'auth_required', message: messageText } }
    : d.action === 'claim' ? { claimed: true } : { ok: true } });
  f.configure(); await settle();
  f.sockets[0].event(message()); f.sockets[0].event(message()); await settle();
  assert.equal(f.posts().length, 1);
  assert.equal(f.posts()[0].values.markdown_text, `⚠️ ${messageText}`);
  assert.equal(f.page.agentHooks.status().error, messageText);
  assert.ok(f.calls.some(c => c.method === 'reactions.add' && c.values.name === 'warning'));
  assert.ok(!f.calls.some(c => c.method === 'reactions.add' && c.values.name === 'white_check_mark'));
});
