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

function fixture({ manager = locks(), action, failPost = false, recovery = [], threadPage } = {}) {
  const calls = [], sockets = [], timers = new Map(), timeouts = new Map(), messages = [], listeners = new Map();
  let serial = 0, token = 'fixture', user = 'UTEST';
  const intervals = new Map();
  const claimed = new Set();
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
      if (method === 'conversations.replies') result = threadPage ? threadPage(values) : { messages: [message({ ts: '2000000001.000001', text: 'Earlier context' })] };
      if (method === 'chat.postMessage') {
        result = { ts: `2000000099.${String(++serial).padStart(6, '0')}` };
        sockets.at(-1).event(message({ ts: result.ts, text: values.markdown_text, channel: values.channel, client_msg_id: values.client_msg_id }));
      }
      return { ok: true, json: async () => ({ ok: true, ...result }) };
    },
    setTimeout: (fn, ms) => { const id = ++serial; timers.set(id, fn); timeouts.set(id, ms); return id; },
    clearTimeout: id => { timers.delete(id); timeouts.delete(id); },
    setInterval: (fn, ms) => { const id = ++serial; timers.set(id, fn); intervals.set(id, ms); return id; },
    clearInterval: id => { timers.delete(id); intervals.delete(id); },
    addEventListener(name, fn) { if (!listeners.has(name)) listeners.set(name, new Set()); listeners.get(name).add(fn); },
    removeEventListener(name, fn) { listeners.get(name)?.delete(fn); },
    postMessage(data) {
      messages.push(data);
      if (data.type === 'request') {
        const fallback = data.action === 'run' ? { job: `job-${data.id}`, status: 'queued' }
          : data.action === 'wait' ? { job: data.payload.job, answer: 'Test agent answer' }
          : data.action === 'recover' ? { jobs: typeof recovery === 'function' ? recovery() : recovery }
          : data.action === 'history' ? { after: null }
          : data.action === 'claim' ? { claimed: !claimed.has(data.payload.job) } : { ok: true };
        if (data.action === 'claim' && fallback.claimed) claimed.add(data.payload.job);
        const value = action?.(data) ?? fallback;
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
    elapse: ms => { for (const [id, delay] of [...timeouts]) if (delay <= ms) { const fn = timers.get(id); timers.delete(id); timeouts.delete(id); fn(); } },
    token: value => { token = value; }, user: value => { user = value; },
    posts: () => calls.filter(c => c.method === 'chat.postMessage') };
}
const message = (extra = {}) => ({ type: 'message', channel: 'DSELF', user: 'UTEST', ts: '2000000002.000001', text: 'hook ping', ...extra });
const requestReactions = f => f.calls.filter(c => c.method.startsWith('reactions.') && c.values.timestamp === message().ts)
  .map(c => `${c.method}:${c.values.name}`);

test('long-thread continuation fetches only messages after the completed checkpoint', async () => {
  const after = '2000000001.000000';
  const older = Array.from({ length: 1500 }, (_, i) => message({ ts: `1999999999.${String(i).padStart(6, '0')}`, text: 'Old context' }));
  const all = [...older, message({ ts: after, text: 'Already completed' }), message({ ts: '2000000001.000001', text: 'Fresh context' }), message()];
  const f = fixture({ action: d => d.action === 'history' ? { after } : undefined,
    threadPage(values) {
      const eligible = all.filter(m => !values.oldest || Number(m.ts) >= Number(values.oldest));
      const offset = Number(values.cursor || 0), next = offset + 200;
      return { messages: eligible.slice(offset, next), response_metadata: { next_cursor: next < eligible.length ? String(next) : '' } };
    } });
  f.configure(); await settle();
  f.sockets[0].event(message({ thread_ts: '1999999999.000001' })); await settle();
  const calls = f.calls.filter(c => c.method === 'conversations.replies');
  assert.equal(calls.length, 1);
  assert.equal(calls[0].values.oldest, after);
  const accepted = f.messages.find(m => m.action === 'run').payload;
  assert.equal(accepted.history_after, after);
  assert.deepEqual(Array.from(accepted.messages, m => m.text), ['Fresh context', 'hook ping']);
  assert.equal(f.posts().length, 1);
  f.page.agentHooks.dispose();
});

test('full thread context is deduplicated and sorted across pages and excludes future messages', async () => {
  const pages = [
    [message({ ts: '2000000001.000003', text: 'Last' }), message({ ts: '2000000001.000001', text: 'First' })],
    [message({ ts: '2000000001.000001', text: 'First, latest copy' }), message({ ts: '2000000001.000002', text: 'Middle' }), message({ ts: '2000000003.000001', text: 'Future' })],
  ];
  const f = fixture({ threadPage: values => ({ messages: pages[Number(values.cursor || 0)], response_metadata: { next_cursor: values.cursor ? '' : '1' } }) });
  f.configure(); await settle();
  f.sockets[0].event(message({ thread_ts: '1999999999.000001' })); await settle();
  const calls = f.calls.filter(c => c.method === 'conversations.replies');
  assert.equal(calls.length, 2);
  assert.ok(calls.every(c => !('oldest' in c.values)));
  const accepted = f.messages.find(m => m.action === 'run').payload;
  assert.equal(accepted.history_after, null);
  assert.deepEqual(Array.from(accepted.messages, m => m.text), ['First, latest copy', 'Middle', 'Last']);
  f.page.agentHooks.dispose();
});

test('the context limit still applies when a new session needs full history', async () => {
  const f = fixture({ threadPage: () => ({ messages: Array.from({ length: 1001 }, (_, i) => message({ ts: `1999999999.${String(i).padStart(6, '0')}` })) }) });
  f.configure(); await settle();
  f.sockets[0].event(message({ thread_ts: '1999999999.000001' })); await settle();
  assert.ok(!f.messages.some(m => m.action === 'run'));
  assert.match(f.page.agentHooks.status().error, /Thread too large/);
  f.page.agentHooks.dispose();
});

test('a reloaded page recovers accepted jobs without admitting or reacting to them again', async () => {
  let finish;
  const first = fixture({ action: d => d.action === 'wait' ? new Promise(resolve => { finish = resolve; }) : undefined });
  first.configure(); await settle();
  first.sockets[0].event(message()); await settle();
  const job = first.messages.find(m => m.action === 'run').id;
  first.page.agentHooks.dispose();
  const recovered = { job: `job-${job}`, event: { channel: 'DSELF', ts: message().ts, thread_ts: message().ts } };
  const next = fixture({ recovery: [recovered], action: d => d.action === 'wait'
    ? { job: recovered.job, answer: 'Finished while page was closed' } : undefined });
  next.configure(); await settle();
  assert.equal(next.posts().length, 1);
  assert.equal(next.posts()[0].values.markdown_text, 'Finished while page was closed');
  assert.equal(next.messages.filter(m => m.action === 'run').length, 0);
  assert.deepEqual(requestReactions(next), []);
  finish({ job: recovered.job, answer: 'Old page must not send' }); await settle();
  assert.equal(first.posts().length, 0);
  next.page.agentHooks.dispose();
});

test('bridge reconnection recovers an accepted request whose admission response was lost', async () => {
  let lost;
  const recovered = { job: 'accepted', event: { channel: 'DSELF', ts: message().ts, thread_ts: message().ts } };
  const f = fixture({ recovery: () => lost ? [recovered] : [], action: d => d.action === 'run'
    ? new Promise(resolve => { lost = resolve; }) : undefined });
  f.configure(); await settle();
  f.sockets[0].event(message()); await settle();
  f.configure({ error: 'Local bridge disconnected' }); f.configure(); await settle();
  // Recovery joins the accepted job even though its original request is already in the seen set.
  lost({ job: recovered.job }); await settle();
  assert.equal(f.posts().length, 1);
  assert.equal(f.messages.filter(m => m.action === 'run').length, 1);
  f.page.agentHooks.dispose();
});

test('a pending run survives beyond the former eleven-minute watchdog', async () => {
  let finish;
  const f = fixture({ action: d => d.action === 'wait'
    ? new Promise(resolve => { finish = resolve; })
    : d.action === 'claim' ? { claimed: true } : undefined });
  f.configure(); await settle();
  f.sockets[0].event({ type: 'hello' });
  f.sockets[0].event(message()); await settle();
  f.elapse(15 * 60 * 1000); await settle();
  assert.equal(f.page.agentHooks.status().pending, 1);
  assert.ok(!f.messages.some(m => m.type === 'cancel'));
  finish({ job: 'long-running', answer: 'Finished' }); await settle();
  assert.equal(f.posts().length, 1);
  assert.equal(f.posts()[0].values.markdown_text, 'Finished');
});

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

test('requests keep only the eyes acknowledgement after success or a diagnostic reply', async () => {
  for (const diagnostic of [false, true]) {
    const f = fixture({
      action: d => d.action === 'wait'
        ? { job: 'test', ...(diagnostic ? { error: { message: 'Sign in again.' } } : { answer: 'Done' }) }
        : d.action === 'claim' ? { claimed: true } : undefined,
    });
    f.configure(); await settle();
    f.sockets[0].event(message()); await settle();
    assert.equal(f.posts().length, 1);
    assert.deepEqual(requestReactions(f), ['reactions.add:eyes']);
    assert.equal(f.page.agentHooks.status().pending, 0);
    f.page.agentHooks.dispose();
  }
});

test('admits queued turns before earlier answers finish and delivers each thread in order', async () => {
  const waits = [];
  const f = fixture({ action(data) {
    if (data.action === 'wait') return new Promise(resolve => waits.push(resolve));
  } });
  f.configure(); await settle();
  f.sockets[0].event(message());
  f.sockets[0].event(message({ ts: '2000000003.000001', thread_ts: '2000000002.000001' }));
  f.sockets[0].event(message({ channel: 'COTHER' }));
  await settle();
  const requests = f.messages.filter(m => m.action === 'run');
  assert.equal(requests.length, 3);
  assert.equal(waits.length, 2);
  assert.equal(requests.find(m => m.payload.ts === '2000000003.000001').payload.messages.length, 1);
  waits[0]({ job: 'one', answer: 'first' }); await settle();
  assert.equal(waits.length, 3);
  waits[1]({ job: 'two', answer: 'other channel' });
  waits[2]({ job: 'three', answer: 'same thread' }); await settle();
  assert.equal(f.posts().length, 3);
  assert.ok(f.posts().findIndex(p => p.values.markdown_text === 'first') < f.posts().findIndex(p => p.values.markdown_text === 'same thread'));
  assert.equal(f.page.agentHooks.status().pending, 0);
});

test('stop bypasses a full queue and history fetch, then acknowledges cancellation', async () => {
  const jobs = new Set(), cancelled = new Set(), waiting = new Map();
  const f = fixture({ action(data) {
    if (data.action === 'run') {
      if (/^chat\s+stop\s*$/i.test(data.payload.text)) {
        for (const job of jobs) { cancelled.add(job); waiting.get(job)?.({ skip: true }); }
        return { job: 'stop-receipt', status: 'ready' };
      }
      const job = `job-${data.id}`; jobs.add(job); return { job, status: 'queued' };
    }
    if (data.action === 'wait') {
      if (data.payload.job === 'stop-receipt') return { job: 'stop-receipt', answer: 'Stopping chat requests in this thread.' };
      if (cancelled.has(data.payload.job)) return { skip: true };
      return new Promise(resolve => waiting.set(data.payload.job, resolve));
    }
  } });
  f.configure({ keywords: ['chat', 'claude'] }); await settle();
  for (let i = 1; i <= 100; i++) f.sockets[0].event(message({ ts: `2000000002.${String(i).padStart(6, '0')}`, thread_ts: message().ts, text: 'chat hold' }));
  await settle();
  assert.equal(f.page.agentHooks.status().pending, 100);
  assert.equal(jobs.size, 100);
  const historyCalls = f.calls.filter(c => c.method === 'conversations.replies').length;
  const preflights = f.messages.filter(m => m.action === 'history').length;
  f.sockets[0].event(message({ ts: '2000000003.000001', thread_ts: message().ts, text: 'ChAt\tSTOP ' }));
  await settle();
  assert.equal(cancelled.size, 100);
  assert.equal(f.calls.filter(c => c.method === 'conversations.replies').length, historyCalls);
  assert.equal(f.messages.filter(m => m.action === 'history').length, preflights);
  assert.equal(f.posts().length, 1);
  assert.equal(f.posts()[0].values.markdown_text, 'Stopping chat requests in this thread.');
  assert.equal(f.posts()[0].values.thread_ts, message().ts);
  assert.equal(f.page.agentHooks.status().pending, 0);
  assert.equal(f.page.agentHooks.status().error, null);
  f.page.agentHooks.dispose();
});

test('stop still requires an own configured command and longer stop requests remain agent instructions', async () => {
  const f = fixture(); f.configure({ keywords: ['chat'] }); await settle();
  f.sockets[0].event(message({ text: 'chat stop', user: 'UOTHER' }));
  f.sockets[0].event(message({ text: 'unknown stop' }));
  await settle();
  assert.equal(f.messages.filter(m => m.action === 'run').length, 0);
  f.sockets[0].event(message({ text: 'chat stop using polling', thread_ts: '2000000001.000001' }));
  await settle();
  const run = f.messages.find(m => m.action === 'run');
  assert.equal(run.payload.text, 'chat stop using polling');
  assert.equal(run.payload.messages.length, 1);
  assert.equal(f.posts()[0].values.markdown_text, 'Test agent answer');
  f.page.agentHooks.dispose();
});

test('stop skips only its keyword while gathering context and acknowledges before another provider finishes', async () => {
  let release, finishClaude, preflights = 0;
  const f = fixture({ action(data) {
    if (data.action === 'history' && ++preflights === 1) return new Promise(resolve => { release = resolve; });
    if (data.action === 'run' && data.payload.text === 'claude queued') return { job: 'claude-running' };
    if (data.action === 'run' && data.payload.text === 'chat stop') return { job: 'stop-receipt' };
    if (data.action === 'wait' && data.payload.job === 'claude-running') return new Promise(resolve => { finishClaude = resolve; });
    if (data.action === 'wait' && data.payload.job === 'stop-receipt') return { job: 'stop-receipt', answer: 'Stopping chat requests in this thread.' };
  } });
  f.configure({ keywords: ['chat', 'claude'] }); await settle();
  const thread_ts = '2000000001.000001';
  f.sockets[0].event(message({ thread_ts, text: 'chat first' })); await settle();
  f.sockets[0].event(message({ ts: '2000000003.000001', thread_ts, text: 'chat queued' }));
  f.sockets[0].event(message({ ts: '2000000003.000002', thread_ts, text: 'claude queued' }));
  f.sockets[0].event(message({ ts: '2000000004.000001', thread_ts, text: 'chat stop' }));
  release({ after: null }); await settle();
  assert.deepEqual(f.messages.filter(m => m.action === 'run').map(m => m.payload.text), ['claude queued', 'chat stop']);
  assert.equal(f.messages.filter(m => m.action === 'history').length, 2);
  assert.equal(f.calls.filter(c => c.method === 'conversations.replies').length, 1);
  assert.equal(f.page.agentHooks.status().pending, 1);
  assert.deepEqual(f.posts().map(p => p.values.markdown_text), ['Stopping chat requests in this thread.']);
  f.sockets[0].event(message({ ts: '2000000005.000001', thread_ts, text: 'chat continue' })); await settle();
  assert.deepEqual(f.messages.filter(m => m.action === 'run').map(m => m.payload.text), ['claude queued', 'chat stop', 'chat continue']);
  finishClaude({ job: 'claude-running', answer: 'Claude completed' }); await settle();
  assert.deepEqual(f.posts().map(p => p.values.markdown_text), ['Stopping chat requests in this thread.', 'Claude completed', 'Test agent answer']);
  assert.equal(f.page.agentHooks.status().pending, 0);
  f.page.agentHooks.dispose();
});

test('recovered stop acknowledgements do not wait for another provider in the thread', async () => {
  let finish;
  const f = fixture({ recovery: [
    { job: 'running', stop: false, event: { channel: 'DSELF', ts: '2000000002.000001', thread_ts: '2000000002.000001' } },
    { job: 'stop', stop: true, event: { channel: 'DSELF', ts: '2000000003.000001', thread_ts: '2000000002.000001' } },
  ], action(data) {
    if (data.action === 'wait' && data.payload.job === 'running') return new Promise(resolve => { finish = resolve; });
    if (data.action === 'wait' && data.payload.job === 'stop') return { job: 'stop', answer: 'Stopping claude requests in this thread.' };
  } });
  f.configure(); await settle();
  assert.deepEqual(f.posts().map(p => p.values.markdown_text), ['Stopping claude requests in this thread.']);
  finish({ job: 'running', answer: 'Codex completed' }); await settle();
  assert.deepEqual(f.posts().map(p => p.values.markdown_text), ['Stopping claude requests in this thread.', 'Codex completed']);
  f.page.agentHooks.dispose();
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
  const f = fixture({ action: d => d.action === 'wait' ? new Promise(resolve => { finish = resolve; }) : undefined });
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
  assert.deepEqual(requestReactions(f), ['reactions.add:eyes']);
});

test('a delivery claim denied by the bridge prevents sending', async () => {
  const f = fixture({ action: d => d.action === 'wait' ? { job: 'test', answer: 'answer' } : d.action === 'claim' ? { claimed: false } : undefined });
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

test('CLI failures post one actionable diagnostic and keep the eyes acknowledgement', async () => {
  const messageText = 'Claude login expired. Run `claude auth login` on your computer.';
  const f = fixture({ action: d => d.action === 'wait'
    ? { job: 'test', error: { code: 'auth_required', message: messageText } }
    : d.action === 'claim' ? { claimed: true } : undefined });
  f.configure(); await settle();
  f.sockets[0].event(message()); f.sockets[0].event(message()); await settle();
  assert.equal(f.posts().length, 1);
  assert.equal(f.posts()[0].values.markdown_text, `⚠️ ${messageText}`);
  assert.equal(f.page.agentHooks.status().error, messageText);
  assert.deepEqual(requestReactions(f), ['reactions.add:eyes']);
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
  const f = fixture({ action: d => d.action === 'wait'
    ? new Promise(resolve => { finish = resolve; })
    : d.action === 'claim' ? { claimed: true } : undefined });
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
