import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import test from 'node:test';
import vm from 'node:vm';

const origin = 'chrome-extension://' + 'a'.repeat(32);
const popup = { url: `${origin}/popup/index.html` };
const slack = { url: 'https://app.slack.com/client/ETEST/CTEST', tab: { id: 1 }, frameId: 0 };
async function worker({ token, bootstrap, pairStatus = 200 } = {}) {
  const stored = token ? { bridgeToken: token } : {}, calls = [], levels = [];
  globalThis.chrome = {
    storage: { local: {
      async setAccessLevel(value) { levels.push(value); },
      async get(keys) { return Object.fromEntries((Array.isArray(keys) ? keys : [keys]).filter(k => k in stored).map(k => [k, stored[k]])); },
      async set(values) { Object.assign(stored, values); },
    } }, runtime: { getURL: path => `${origin}/${path}`, onMessage: { addListener() {} } },
  };
  globalThis.fetch = async (url, options) => {
    calls.push({ url, options });
    if (url === `${origin}/bridge-pairing.json`) return { ok: true, async json() {
      return bootstrap === undefined ? { code: 'synthetic_pair_code_123456', expiresAt: Date.now() + 600_000 } : bootstrap;
    } };
    if (url.endsWith('/pair')) return { ok: pairStatus === 200, status: pairStatus, async json() { return { token: 't'.repeat(43) }; } };
    if (options.headers.Authorization !== `Bearer ${'t'.repeat(43)}`) return { ok: false, status: 403 };
    return { ok: true, async json() {
      if (url.endsWith('/config')) return { keywords: ['code', 'chat'] };
      return { job: 'a'.repeat(64), status: 'queued' };
    } };
  };
  const module = await import(`./extension/background.mjs?test=${Math.random()}`);
  // Let startup pairing finish without opening any popup or Slack page.
  for (let i = 0; i < 5; i++) await new Promise(resolve => setImmediate(resolve));
  return { ...module, stored, calls, levels };
}

test('manifest registers automatic Slack scripts with no debugger or broad website access', () => {
  const manifest = JSON.parse(readFileSync(new URL('../manifest.json', import.meta.url)));
  assert.deepEqual(manifest.permissions, ['storage']);
  assert.deepEqual(manifest.host_permissions, ['https://app.slack.com/*', 'http://127.0.0.1/*']);
  assert.equal(manifest.content_scripts.length, 2);
  for (const script of manifest.content_scripts) {
    assert.deepEqual(script.matches, ['https://app.slack.com/*']);
    for (const file of script.js) assert.ok(existsSync(new URL(`../${file}`, import.meta.url)));
  }
  assert.ok(existsSync(new URL(`../${manifest.background.service_worker}`, import.meta.url)));
  const html = readFileSync(new URL('../popup/index.html', import.meta.url), 'utf8');
  assert.ok(!/Start listening|Stop|Pause|Resume/.test(html));
});

test('startup pairs from the private file once and keeps the token out of page and popup replies', async () => {
  const w = await worker();
  assert.deepEqual(w.levels, [{ accessLevel: 'TRUSTED_CONTEXTS' }]);
  assert.equal(w.stored.bridgeToken, 't'.repeat(43));
  const results = await Promise.all([w.handle({ type: 'popup.settings' }, popup), w.handle({ type: 'slack.settings' }, slack)]);
  for (const result of results) {
    assert.deepEqual(result, { keywords: ['code', 'chat'] });
    assert.ok(!JSON.stringify(result).includes(w.stored.bridgeToken));
  }
  assert.equal(w.calls.filter(c => c.url.endsWith('/pair')).length, 1);
  const authenticated = w.calls.find(c => c.url.endsWith('/config'));
  assert.equal(authenticated.options.headers.Authorization, `Bearer ${w.stored.bridgeToken}`);
  assert.equal(authenticated.options.headers['X-Browser-Hooks-Origin'], origin);
  assert.ok(w.calls.every(c => c.options.credentials === 'omit' && c.options.redirect === 'error'));
  assert.ok(!JSON.stringify(w.calls).includes('xoxc'));
});

test('a stored token reconnects without reading or consuming the bootstrap file', async () => {
  const w = await worker({ token: 't'.repeat(43), bootstrap: null });
  assert.deepEqual(await w.handle({ type: 'slack.settings' }, slack), { keywords: ['code', 'chat'] });
  assert.ok(w.calls.every(c => c.url.endsWith('/config')));
});

test('stale credentials repair automatically and simultaneous requests redeem only one code', async () => {
  const w = await worker({ token: 'stale-token' });
  assert.equal(w.stored.bridgeToken, 't'.repeat(43));
  delete w.stored.bridgeToken;
  await Promise.all(Array.from({ length: 8 }, () => w.handle({ type: 'slack.settings' }, slack)));
  assert.equal(w.calls.filter(c => c.url.endsWith('/pair')).length, 2);
});

test('expired, malformed and rejected bootstrap files give a repair without exposing secrets', async () => {
  for (const options of [
    { bootstrap: { code: 'synthetic-private-secret', expiresAt: Date.now() - 1 } },
    { bootstrap: null },
    { bootstrap: { code: 'synthetic-private-secret', expiresAt: Date.now() + 60_000 }, pairStatus: 403 },
  ]) {
    const w = await worker(options);
    const result = await w.handle({ type: 'slack.settings' }, slack);
    assert.match(result.error, /Rerun.*installer/);
    assert.ok(!JSON.stringify(result).includes('synthetic-private-secret'));
    assert.equal(w.stored.bridgeToken, undefined);
  }
});

test('websites, content scripts and popup messages cannot supply a pairing code or executable configuration', async () => {
  const w = await worker();
  const count = w.calls.length;
  for (const sender of [popup, slack, { url: 'https://example.com' }, { ...slack, frameId: 1 }]) {
    await assert.rejects(w.handle({ type: 'popup.pair', code: 'synthetic_pair_code_123456' }, sender));
  }
  await assert.rejects(w.handle({ type: 'slack.request', action: 'fetch', payload: { url: 'https://example.com' } }, slack));
  await assert.rejects(w.handle({ type: 'slack.request', action: 'poll', payload: { job: '../config' } }, slack));
  assert.equal(w.calls.length, count);
  const manifest = JSON.parse(readFileSync(new URL('../manifest.json', import.meta.url)));
  assert.equal(manifest.web_accessible_resources, undefined);
});

test('isolated relay discovers settings automatically and polls jobs using short background requests', async () => {
  const listeners = new Map(), posted = [], calls = [], intervals = new Set();
  let poll = 0, terminal = { status: 'ready', answer: 'answer' };
  const page = {
    location: { origin: 'https://app.slack.com' },
    addEventListener(name, fn) { listeners.set(name, fn); },
    removeEventListener(name) { listeners.delete(name); },
    postMessage(data) { posted.push(data); },
  };
  const chrome = { runtime: { onMessage: { addListener() {} }, async sendMessage(data) {
    calls.push(data);
    if (data.type === 'slack.settings') return { ok: true, value: { keywords: ['code'] } };
    if (data.action === 'run') return { ok: true, value: { job: 'a'.repeat(64), status: 'queued' } };
    return { ok: true, value: ++poll > 1 ? { job: 'a'.repeat(64), ...terminal } : { status: 'running' } };
  } } };
  const source = readFileSync(new URL('./extension/relay.js', import.meta.url), 'utf8');
  vm.runInNewContext(source, { window: page, chrome, Date, setTimeout: fn => setImmediate(fn),
    setInterval: fn => { intervals.add(fn); return fn; }, clearInterval: fn => intervals.delete(fn) });
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(posted[0].type, 'configure');
  assert.deepEqual([...posted[0].settings.keywords], ['code']);
  listeners.get('message')({ source: page, origin: page.location.origin, data: { source: 'browser-hooks-slack', type: 'request', id: 'request', action: 'run', payload: { text: 'code ping' } } });
  for (let i = 0; i < 10; i++) await new Promise(resolve => setImmediate(resolve));
  assert.deepEqual(calls.filter(c => c.type === 'slack.request').map(c => c.action), ['run', 'poll', 'poll']);
  const response = posted.find(p => p.type === 'response');
  assert.equal(response.value.answer, 'answer');
  assert.ok(!calls.some(c => c.action === 'claim')); // Claim occurs only when the page is ready to post.
  terminal = { status: 'failed', error: { code: 'auth_required', message: 'Run claude auth login.' } };
  poll = 0;
  listeners.get('message')({ source: page, origin: page.location.origin, data: { source: 'browser-hooks-slack', type: 'request', id: 'failure', action: 'run', payload: { text: 'code ping' } } });
  for (let i = 0; i < 10; i++) await new Promise(resolve => setImmediate(resolve));
  assert.equal(posted.find(p => p.id === 'failure').value.error.message, 'Run claude auth login.');
  listeners.get('pagehide')();
  assert.equal(intervals.size, 0);
});

test('bridge offline, missing bootstrap and malformed responses give distinct fixes without raw errors', async () => {
  const w = await worker();
  w.stored.bridgeToken = 't'.repeat(43);
  globalThis.fetch = async () => { throw new Error('fixture-private-secret'); };
  let config = await w.handle({ type: 'slack.settings' }, slack);
  assert.match(config.error, /not running/);
  assert.ok(!config.error.includes('fixture-private-secret'));
  globalThis.fetch = async () => ({ status: 403, ok: false });
  config = await w.handle({ type: 'slack.settings' }, slack);
  assert.match(config.error, /Automatic pairing/);
  globalThis.fetch = async () => ({ ok: true, json() { throw new Error('fixture-private-secret'); } });
  config = await w.handle({ type: 'slack.settings' }, slack);
  assert.match(config.error, /invalid response/);
  assert.ok(!config.error.includes('fixture-private-secret'));
});
