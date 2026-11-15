import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import vm from 'node:vm';

const source = readFileSync(new URL('./extension/popup.mjs', import.meta.url), 'utf8');
const settle = async () => { for (let i = 0; i < 5; i++) await new Promise(resolve => setImmediate(resolve)); };
function fixture({ pairError } = {}) {
  const ui = Object.fromEntries(['dot', 'code', 'feedback', 'pair-form'].map(id => [id, {
    dataset: {}, attributes: {}, listeners: {}, value: '', textContent: '',
    setAttribute(name, value) { this.attributes[name] = value; },
    addEventListener(name, fn) { this.listeners[name] = fn; },
  }]));
  let settings = { keywords: ['chat', 'claude'] }, states = [{ connected: false }, { connected: true }], tick;
  const queries = [], pairs = [];
  const chrome = {
    runtime: { async sendMessage(message) {
      if (message.type === 'popup.settings') return { ok: true, value: settings };
      pairs.push(message);
      assert.equal(ui.code.disabled, true);
      return pairError ? { ok: false, error: pairError } : { ok: true, value: settings };
    } },
    tabs: {
      async query(query) { queries.push(query); return states.map((_, id) => ({ id })); },
      async sendMessage(id) { if (states[id] === null) throw new Error('Closed tab'); return states[id]; },
    },
  };
  vm.runInNewContext(source, { document: { getElementById: id => ui[id] }, chrome,
    window: { addEventListener() {} }, setInterval: fn => { tick = fn; return 1; }, clearInterval() {} });
  return { ui, queries, pairs, refresh: () => tick(), settings: value => { settings = value; }, states: value => { states = value; } };
}

test('connection checks all Slack tabs and tolerates a closed tab and previous request errors', async () => {
  const f = fixture();
  f.states([{ connected: true, error: 'CLI needs login' }, null]);
  await settle(); await f.refresh();
  assert.equal(f.queries[0].url, 'https://app.slack.com/*');
  assert.ok(!('active' in f.queries[0]));
  assert.equal(f.ui.dot.dataset.connected, 'true');
  assert.equal(f.ui.dot.attributes['aria-label'], 'Slack connected');
  assert.equal(f.ui.dot.title, 'CLI needs login');
  f.settings({ keywords: [], error: 'Local bridge is not running.' });
  await f.refresh();
  assert.equal(f.ui.dot.dataset.connected, 'false');
  assert.match(f.ui.dot.title, /not running/);
});

test('submitting the pairing field trims the code and clears it after a successful pair', async () => {
  const f = fixture(); await settle();
  f.ui.code.value = '  synthetic-pair-code  ';
  await f.ui['pair-form'].listeners.submit({ preventDefault() {} });
  assert.equal(f.pairs.length, 1);
  assert.equal(f.pairs[0].type, 'popup.pair');
  assert.equal(f.pairs[0].code, 'synthetic-pair-code');
  assert.equal(f.ui.code.value, '');
  assert.equal(f.ui.code.disabled, false);
  assert.equal(f.ui.feedback.textContent, '');
});

test('pairing failures show the fix without reflecting the code, and typing dismisses it', async () => {
  const f = fixture({ pairError: 'Pairing code expired. Rerun the installer.' }); await settle();
  f.ui.code.value = 'synthetic-private-pair-code';
  await f.ui['pair-form'].listeners.submit({ preventDefault() {} });
  assert.match(f.ui.feedback.textContent, /Rerun the installer/);
  assert.ok(!f.ui.feedback.textContent.includes(f.ui.code.value));
  assert.equal(f.ui.code.disabled, false);
  f.ui.code.listeners.input();
  assert.equal(f.ui.feedback.textContent, '');
});
