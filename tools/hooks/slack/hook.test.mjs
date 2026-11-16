import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import vm from "node:vm";

const source = readFileSync(new URL("./hook.js", import.meta.url), "utf8");
const settle = async () => { for (let i = 0; i < 10; i++) await new Promise(resolve => setImmediate(resolve)); };
function locks() {
  const queues = new Map();
  return { request(key, options, fn) {
    return new Promise((resolve, reject) => {
      if (!queues.has(key)) queues.set(key, []);
      const queue = queues.get(key);
      const entry = { start() {
        entry.started = true;
        options.signal.removeEventListener('abort', abort);
        Promise.resolve().then(() => fn({ name: key })).then(resolve, reject).finally(() => {
          queue.shift(); if (queue.length) queue[0].start(); else queues.delete(key);
        });
      } };
      const abort = () => { if (!entry.started) { queue.splice(queue.indexOf(entry), 1); reject(new Error('Aborted')); } };
      options.signal.addEventListener('abort', abort, { once: true });
      queue.push(entry); if (queue.length === 1) entry.start();
    });
  } };
}

function fixture({ manager = locks(), action, failPost = false, removeEyes } = {}) {
  const calls = [], sockets = [], timers = new Map(), messages = [], listeners = new Map();
  let serial = 0, token = 'fixture', user = 'UTEST';
  const intervals = new Map();
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
      if (method === 'reactions.remove' && values.name === 'eyes' && removeEyes) await removeEyes();
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
    setInterval: (fn, ms) => { const id = ++serial; timers.set(id, fn); intervals.set(id, ms); return id; },
    clearInterval: id => { timers.delete(id); intervals.delete(id); },
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
  return { page, calls, sockets, messages, timers, intervals, respond,
    event: (name, value = {}) => { for (const fn of listeners.get(name) || []) fn(value); },
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

test('completion reactions wait until removing the eyes reaction finishes', async () => {
  for (const diagnostic of [false, true]) {
    let finishRemoval;
    const f = fixture({
      removeEyes: () => new Promise(resolve => { finishRemoval = resolve; }),
      action: d => d.action === 'run'
        ? { job: 'test', ...(diagnostic ? { error: { message: 'Sign in again.' } } : { answer: 'Done' }) }
        : d.action === 'claim' ? { claimed: true } : { ok: true },
    });
    f.configure(); await settle();
    f.sockets[0].event(message()); await settle();
    const reactions = () => f.calls.filter(c => c.method.startsWith('reactions.') && c.values.timestamp === message().ts)
      .map(c => `${c.method}:${c.values.name}`);
    assert.deepEqual(reactions(), ['reactions.add:eyes', 'reactions.remove:eyes']);
    assert.equal(f.page.agentHooks.status().pending, 1);
    finishRemoval(); await settle();
    assert.deepEqual(reactions(), ['reactions.add:eyes', 'reactions.remove:eyes', `reactions.add:${diagnostic ? 'warning' : 'white_check_mark'}`]);
    assert.equal(f.page.agentHooks.status().pending, 0);
    f.page.agentHooks.dispose();
  }
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
  a.page.agentHooks.dispose(); await settle();
  assert.equal(b.sockets.length, 1);
  b.page.agentHooks.dispose();
});

test('reload/dispose and account changes cancel queued sends and release the socket', async () => {
  let finish;
  const f = fixture({ action: () => new Promise(resolve => { finish = resolve; }) });
  f.configure(); await settle(); f.sockets[0].event(message()); await settle();
  f.token('changed'); f.event('storage', { key: 'localConfig_v2' }); await settle();
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

test('healthy listeners have no account polling and queued tabs take over without a timer', async () => {
  const manager = locks(), a = fixture({ manager }), b = fixture({ manager });
  a.configure(); b.configure(); await settle();
  assert.deepEqual([...a.intervals.values()], [15000]);
  assert.equal(b.timers.size, 0);
  a.page.agentHooks.dispose(); await settle();
  assert.equal(b.sockets.length, 1);
  b.page.agentHooks.dispose();
});

test('same-page storage writes and navigation events attach without polling', async () => {
  const f = fixture();
  // Real Storage methods are wrapped once and restored on disposal.
  class Storage { setItem() {} removeItem() {} clear() {} }
  const original = Storage.prototype.setItem;
  f.page.agentHooks.dispose();
  f.page.Storage = Storage;
  f.page.localStorage = new Storage();
  let loggedIn = false;
  f.page.localStorage.getItem = () => JSON.stringify({ teams: loggedIn ? { ETEST: { token: ['xoxc', 'fixture'].join('-') } } : {} });
  vm.runInNewContext(source, { window: f.page, URLSearchParams, AbortController, AbortSignal, Date: { now: () => 2000000000000 } });
  f.configure(); await settle(); assert.equal(f.sockets.length, 0);
  loggedIn = true; f.page.localStorage.setItem('localConfig_v2', 'fixture');
  await settle(); assert.equal(f.sockets.length, 1);
  f.page.location.pathname = '/client/EOTHER/COTHER'; f.event('popstate'); await settle();
  assert.equal(f.sockets[0].readyState, 3);
  f.page.agentHooks.dispose(); assert.equal(Storage.prototype.setItem, original);
});

test('bridge reconnection preserves the Slack listener and pending work, then clears its error', async () => {
  let finish;
  const f = fixture({ action: d => d.action === 'run'
    ? new Promise(resolve => { finish = resolve; })
    : d.action === 'claim' ? { claimed: true } : { ok: true } });
  f.configure(); await settle(); f.sockets[0].event({ type: 'hello' });
  f.sockets[0].event(message()); await settle();
  f.configure({ error: 'Local bridge disconnected. Reconnecting automatically…' });
  assert.equal(f.page.agentHooks.status().pending, 1);
  assert.equal(f.sockets[0].readyState, 1);
  assert.ok(!f.messages.some(value => value.type === 'cancel'));
  f.configure();
  assert.equal(f.page.agentHooks.status().error, null);
  finish({ job: 'test', answer: 'finished after reconnect' }); await settle();
  assert.equal(f.posts().length, 1);
  f.page.agentHooks.dispose();
});
