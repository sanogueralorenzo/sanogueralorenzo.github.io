import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import test from 'node:test';
import vm from 'node:vm';

const origin = 'chrome-extension://' + 'a'.repeat(32);
const job = 'b'.repeat(64);
const settle = async () => { for (let i = 0; i < 10; i++) await new Promise(resolve => setImmediate(resolve)); };
function event() {
  const listeners = new Set();
  return { addListener: fn => listeners.add(fn), emit: (...args) => { for (const fn of listeners) fn(...args); } };
}
function port(name = 'slack', sender = { url: 'https://app.slack.com/client/ETEST/CTEST', tab: { id: 1 }, frameId: 0 }) {
  const sent = [], onMessage = event(), onDisconnect = event();
  return { name, sender, sent, onMessage, onDisconnect, disconnected: false,
    postMessage: data => sent.push(JSON.parse(JSON.stringify(data))),
    send: data => onMessage.emit(data),
    disconnect() { this.disconnected = true; onDisconnect.emit(); },
  };
}
function worker({ token, bootstrap, pairStatus = 200 } = {}) {
  const stored = token ? { bridgeToken: token } : {}, calls = [], levels = [], sockets = [], timers = new Map();
  let serial = 0, state = { job, status: 'queued' }, fetchOverride;
  const chrome = {
    storage: { local: {
      async setAccessLevel(value) { levels.push(value); },
      async get(key) { return { [key]: stored[key] }; },
      async set(values) { Object.assign(stored, values); },
    } }, runtime: { getURL: path => `${origin}/${path}`, onConnect: event() },
  };
  class Socket {
    static OPEN = 1;
    readyState = 0;
    sent = [];
    constructor(url) { this.url = url; sockets.push(this); }
    open() { this.readyState = 1; this.onopen?.(); }
    event(value) { this.onmessage?.({ data: JSON.stringify(value) }); }
    send(value) { this.sent.push(JSON.parse(value)); }
    close() { this.readyState = 3; this.onclose?.(); }
  }
  const fetch = async (url, options) => {
    calls.push({ url, options });
    if (fetchOverride) return fetchOverride(url, options);
    if (url === `${origin}/bridge-pairing.json`) return { ok: true, async json() {
      return bootstrap === undefined ? { code: 'synthetic_pair_code_123456', expiresAt: Date.now() + 600_000 } : bootstrap;
    } };
    if (url.endsWith('/pair')) return { ok: pairStatus === 200, status: pairStatus, async json() { return { token: 't'.repeat(43) }; } };
    if (options.headers.Authorization !== `Bearer ${'t'.repeat(43)}`) return { ok: false, status: 403 };
    return { ok: true, async json() {
      if (url.endsWith('/config')) return { hooks: {slack: {keywords: ['chat', 'claude']}} };
      if (url.includes('/slack/jobs/')) return state;
      if (url.endsWith('/slack/run')) return { job, status: 'queued' };
      return { ok: true };
    } };
  };
  const transport = readFileSync(new URL('../bridge.mjs', import.meta.url), 'utf8').replace(/export /g, '');
  const source = readFileSync(new URL('./extension/background.mjs', import.meta.url), 'utf8').replace('export function', 'function')
    .replace(/^import .*?;\n/, `const {request, subscribe} = (() => { ${transport}; return {request, subscribe}; })();\n`);
  const module = vm.runInNewContext(source + '\n({connectPort, subscribe})', { chrome, fetch, WebSocket: Socket, URL, AbortSignal,
    setInterval: (fn, ms) => { const id = ++serial; timers.set(id, { fn, ms, interval: true }); return id; },
    setTimeout: (fn, ms) => { const id = ++serial; timers.set(id, { fn, ms }); return id; },
    clearInterval: id => timers.delete(id), clearTimeout: id => timers.delete(id),
  });
  return { ...module, stored, calls, levels, sockets, timers,
    state: value => { state = { job, ...value }; }, override: fn => { fetchOverride = fn; },
    async ready() { await settle(); const socket = sockets.at(-1); socket.open(); socket.event({ type: 'settings', hooks: {slack: {keywords: ['chat', 'claude']}} }); await settle(); return socket; },
    retry() { const [id, timer] = [...timers].find(([, timer]) => !timer.interval && timer.ms === 1000); timers.delete(id); timer.fn(); },
  };
}
const popup = () => port('popup', { url: `${origin}/popup/index.html` });

test('manifest registers automatic scripts without new permissions or exposed pairing files', () => {
  const manifest = JSON.parse(readFileSync(new URL('../manifest.json', import.meta.url)));
  assert.deepEqual(manifest.permissions, ['storage']);
  assert.deepEqual(manifest.host_permissions, ['https://app.slack.com/*', 'http://127.0.0.1/*']);
  assert.equal(manifest.web_accessible_resources, undefined);
  for (const script of manifest.content_scripts) for (const file of script.js) assert.ok(existsSync(new URL(`../${file}`, import.meta.url)));
});

test('connecting a registered page pairs once; tokens stay in trusted extension contexts', async () => {
  const w = worker(), page = port(), view = popup();
  w.connectPort(page); w.connectPort(view);
  const socket = await w.ready();
  assert.equal(w.stored.bridgeToken, 't'.repeat(43));
  assert.deepEqual(JSON.parse(JSON.stringify(w.levels)), [{ accessLevel: 'TRUSTED_CONTEXTS' }]);
  assert.equal(w.calls.filter(c => c.url.endsWith('/pair')).length, 1);
  assert.deepEqual(socket.sent[0], { type: 'authenticate', token: w.stored.bridgeToken });
  assert.equal(socket.url, 'ws://127.0.0.1:19736/events');
  assert.ok(!JSON.stringify(page.sent).includes(w.stored.bridgeToken));
  assert.ok(!JSON.stringify(view.sent).includes(w.stored.bridgeToken));
  assert.ok(w.calls.every(c => c.options.credentials === 'omit' && c.options.redirect === 'error'));
});

test('persisted and stale credentials reconnect or repair without user input', async () => {
  for (const token of ['t'.repeat(43), 'stale-token']) {
    const w = worker({ token }); w.connectPort(port()); await w.ready();
    assert.equal(w.stored.bridgeToken, 't'.repeat(43));
    assert.equal(w.calls.filter(c => c.url.endsWith('/pair')).length, token === 'stale-token' ? 1 : 0);
  }
});

test('expired and malformed pairing files show a safe repair and retry only on failure', async () => {
  for (const bootstrap of [null, { code: 'synthetic-private-secret', expiresAt: Date.now() - 1 }]) {
    const w = worker({ bootstrap }), page = port(); w.connectPort(page); await settle();
    assert.match(page.sent.at(-1).settings.error, /Rerun.*installer/);
    assert.ok(!JSON.stringify(page.sent).includes('synthetic-private-secret'));
    assert.equal(w.sockets.length, 0);
    assert.ok([...w.timers.values()].some(timer => !timer.interval));
  }
});

test('only top-level Slack pages and the exact extension popup can connect', async () => {
  const w = worker();
  for (const client of [port('slack', { url: 'https://example.com', tab: { id: 1 }, frameId: 0 }),
    port('slack', { url: 'https://app.slack.com/client/ETEST/CTEST', tab: { id: 1 }, frameId: 1 }),
    port('popup', { url: `${origin}/other.html` })]) {
    w.connectPort(client); assert.equal(client.disconnected, true);
  }
  assert.equal(w.calls.length, 0);
  const page = port(); w.connectPort(page); await w.ready();
  const count = w.calls.length;
  page.send({ type: 'request', id: 'invalid', action: 'poll', payload: { job: '../config' } }); await settle();
  assert.match(page.sent.at(-1).error, /Invalid Slack operation/);
  assert.equal(w.calls.length, count);
});

test('healthy idle connections only send keepalives; popup status is pushed', async () => {
  const w = worker(), page = port(), view = popup();
  w.connectPort(page); w.connectPort(view); const socket = await w.ready();
  const count = w.calls.length;
  assert.deepEqual([...w.timers.values()].map(timer => timer.ms), [20000]);
  [...w.timers.values()][0].fn();
  assert.deepEqual(socket.sent.at(-1), { type: 'ping' });
  assert.equal(w.calls.length, count);
  page.send({ type: 'status', status: { connected: true, error: 'CLI needs login' } });
  assert.deepEqual(view.sent.at(-1), { type: 'status', connected: true, detail: 'CLI needs login' });
  page.disconnect(); assert.equal(view.sent.at(-1).connected, false);
  view.disconnect(); assert.equal(w.timers.size, 0); assert.equal(socket.readyState, 3);
});

test('job completion is pushed and failure diagnostics are delivered without polling', async () => {
  for (const result of [{ status: 'ready', answer: 'answer' }, { status: 'failed', error: { code: 'auth_required', message: 'Run claude auth login.' } }]) {
    const w = worker(), page = port(); w.connectPort(page); const socket = await w.ready();
    page.send({ type: 'request', id: 'request', action: 'run', payload: { text: 'chat ping' } }); await settle();
    assert.equal(w.calls.filter(c => c.url.includes('/slack/jobs/')).length, 1);
    assert.ok(!page.sent.some(value => value.type === 'response'));
    w.state(result); socket.event({ type: 'job', hook: 'slack', job }); await settle();
    assert.equal(w.calls.filter(c => c.url.endsWith('/slack/run')).length, 1);
    const response = page.sent.find(value => value.type === 'response');
    assert.equal(response.ok, true);
    assert.equal(response.value.answer || response.value.error.message, result.answer || result.error.message);
  }
});

test('a completion arriving during the initial snapshot cannot be lost', async () => {
  const w = worker(), page = port(); w.connectPort(page); const socket = await w.ready();
  let release;
  w.override(async url => url.includes('/slack/jobs/')
    ? new Promise(resolve => { release = () => resolve({ ok: true, json: async () => ({ job, status: 'queued' }) }); })
    : { ok: true, json: async () => ({ job, status: 'queued' }) });
  page.send({ type: 'request', id: 'race', action: 'run', payload: {} }); await settle();
  w.override(async () => ({ ok: true, json: async () => ({ job, status: 'ready', answer: 'not lost' }) }));
  socket.event({ type: 'job', hook: 'slack', job }); await settle();
  assert.equal(page.sent.find(value => value.id === 'race').value.answer, 'not lost');
  release(); await settle();
  assert.equal(page.sent.filter(value => value.id === 'race').length, 1);
});

test('overlapping completion events answer each request only once', async () => {
  const w = worker(), page = port(); w.connectPort(page); const socket = await w.ready();
  page.send({ type: 'request', id: 'once', action: 'run', payload: {} }); await settle();
  w.state({ status: 'ready', answer: 'one answer' });
  socket.event({ type: 'job', hook: 'slack', job }); socket.event({ type: 'job', hook: 'slack', job }); await settle();
  assert.equal(page.sent.filter(value => value.id === 'once').length, 1);
});

test('bridge reconnect takes pending job snapshots without rerunning commands', async () => {
  const w = worker(), page = port(); w.connectPort(page); const socket = await w.ready();
  page.send({ type: 'request', id: 'resume', action: 'run', payload: {} }); await settle();
  socket.close(); assert.match(page.sent.at(-1).settings.error, /disconnected/);
  assert.deepEqual(page.sent.at(-1).settings.keywords, ['chat', 'claude']);
  w.state({ status: 'ready', answer: 'finished while disconnected' });
  w.retry(); await w.ready();
  assert.equal(page.sent.find(value => value.id === 'resume').value.answer, 'finished while disconnected');
  assert.equal(w.calls.filter(c => c.url.endsWith('/slack/run')).length, 1);
});

test('closing a page cancels its pending job and releases the push connection', async () => {
  const w = worker(), page = port(); w.connectPort(page); await w.ready();
  page.send({ type: 'request', id: 'cancel', action: 'run', payload: {} }); await settle();
  page.disconnect(); await settle();
  assert.equal(w.calls.filter(c => c.url.endsWith('/slack/cancel')).length, 1);
  assert.equal(w.timers.size, 0);
});

test('closing one owner preserves another pending request for the same job', async () => {
  const w = worker(), first = port(), second = port();
  w.connectPort(first); w.connectPort(second); const socket = await w.ready();
  first.send({ type: 'request', id: 'first', action: 'run', payload: {} });
  second.send({ type: 'request', id: 'second', action: 'run', payload: {} }); await settle();
  first.disconnect(); await settle();
  assert.equal(w.calls.filter(c => c.url.endsWith('/slack/cancel')).length, 0);
  w.state({ status: 'ready', answer: 'still wanted' }); socket.event({ type: 'job', hook: 'slack', job }); await settle();
  assert.equal(second.sent.find(value => value.id === 'second').value.answer, 'still wanted');
  assert.ok(!first.sent.some(value => value.type === 'response'));
});

test('cancelling before run acknowledgement cancels the accepted job without replying', async () => {
  const w = worker(), page = port(); w.connectPort(page); await w.ready();
  let release;
  w.override(async url => url.endsWith('/slack/run') ? new Promise(resolve => {
    release = () => resolve({ ok: true, json: async () => ({ job, status: 'queued' }) });
  }) : { ok: true, json: async () => ({ ok: true }) });
  page.send({ type: 'request', id: 'cancel-early', action: 'run', payload: {} }); await settle();
  page.send({ type: 'cancel', id: 'cancel-early' }); release(); await settle();
  assert.equal(w.calls.filter(c => c.url.endsWith('/slack/cancel')).length, 1);
  assert.ok(!page.sent.some(value => value.type === 'response'));
});

test('relay forwards events without idle timers and disconnects on page close', async () => {
  const listeners = new Map(), posted = [], client = port();
  const page = { location: { origin: 'https://app.slack.com' },
    addEventListener: (name, fn) => listeners.set(name, fn), removeEventListener: name => listeners.delete(name), postMessage: value => posted.push(value) };
  const source = readFileSync(new URL('./extension/relay.js', import.meta.url), 'utf8');
  vm.runInNewContext(source, { window: page, chrome: { runtime: { connect: () => client } }, setTimeout() { throw new Error('No idle retry expected'); }, clearTimeout() {} });
  client.onMessage.emit({ type: 'settings', settings: { keywords: ['chat'] } });
  assert.deepEqual([...posted[0].settings.keywords], ['chat']);
  listeners.get('message')({ source: page, origin: page.location.origin, data: { source: 'browser-hooks-slack', type: 'request', id: 'run', action: 'run', payload: {} } });
  assert.equal(client.sent.at(-1).action, 'run');
  client.onMessage.emit({ type: 'response', id: 'run', ok: true, value: { job, answer: 'answer' } });
  assert.equal(posted.at(-1).value.answer, 'answer');
  listeners.get('pagehide')(); assert.equal(client.disconnected, true);
});

test('adapters share one bridge socket and releasing one preserves the other', async () => {
  const w = worker(), page = port();
  w.connectPort(page); const socket = await w.ready();
  const events = [], errors = [];
  const release = w.subscribe(value => events.push(value), error => errors.push(error));
  await settle();
  assert.equal(w.sockets.length, 1);
  assert.equal(w.calls.filter(c => c.url.endsWith('/config')).length, 1);
  assert.deepEqual([...events[0].hooks.slack.keywords], ['chat', 'claude']);
  page.disconnect();
  assert.equal(socket.readyState, 1);
  socket.event({type: 'job', hook: 'another-site', job});
  assert.equal(events.at(-1).hook, 'another-site');
  assert.equal(errors.length, 0);
  release();
  assert.equal(socket.readyState, 3);
  assert.equal(w.timers.size, 0);
});

test('Slack only consumes its own namespaced job events', async () => {
  const w = worker(), page = port();
  w.connectPort(page); const socket = await w.ready();
  page.send({type:'request', id:'scoped', action:'run', payload:{}}); await settle();
  assert.ok(w.calls.some(c => c.url.endsWith('/slack/run')));
  const count = w.calls.length;
  w.state({status:'ready', answer:'Slack answer'});
  socket.event({type:'job', hook:'another-site', job}); await settle();
  assert.equal(w.calls.length, count);
  assert.ok(!page.sent.some(message => message.id === 'scoped'));
  socket.event({type:'job', hook:'slack', job}); await settle();
  assert.equal(page.sent.find(message => message.id === 'scoped').value.answer, 'Slack answer');
});
