import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import vm from 'node:vm';

const source = readFileSync(new URL('./extension/popup.mjs', import.meta.url), 'utf8');
const settle = async () => { for (let i = 0; i < 5; i++) await new Promise(resolve => setImmediate(resolve)); };
function fixture() {
  const dot = { dataset: {}, attributes: {}, setAttribute(name, value) { this.attributes[name] = value; } };
  let settings = { keywords: ['chat', 'claude'] }, states = [{ connected: false }, { connected: true }], tick;
  const queries = [];
  const chrome = {
    runtime: { async sendMessage(message) {
      assert.equal(message.type, 'popup.settings');
      return { ok: true, value: settings };
    } },
    tabs: {
      async query(query) { queries.push(query); return states.map((_, id) => ({ id })); },
      async sendMessage(id) { if (states[id] === null) throw new Error('Closed tab'); return states[id]; },
    },
  };
  vm.runInNewContext(source, { document: { getElementById: id => { assert.equal(id, 'dot'); return dot; } }, chrome,
    window: { addEventListener() {} }, setInterval: fn => { tick = fn; return 1; }, clearInterval() {} });
  return { dot, queries, refresh: () => tick(), settings: value => { settings = value; }, states: value => { states = value; } };
}

test('connection checks all Slack tabs and tolerates a closed tab and previous request errors', async () => {
  const f = fixture();
  f.states([{ connected: true, error: 'CLI needs login' }, null]);
  await settle(); await f.refresh();
  assert.equal(f.queries[0].url, 'https://app.slack.com/*');
  assert.ok(!('active' in f.queries[0]));
  assert.equal(f.dot.dataset.connected, 'true');
  assert.equal(f.dot.attributes['aria-label'], 'Slack connected');
  assert.equal(f.dot.title, 'CLI needs login');
  f.settings({ keywords: [], error: 'Local bridge is not running.' });
  await f.refresh();
  assert.equal(f.dot.dataset.connected, 'false');
  assert.match(f.dot.title, /not running/);
});

test('popup contains only the Slack icon, label and connection status', () => {
  const html = readFileSync(new URL('../popup/index.html', import.meta.url), 'utf8');
  assert.ok(!/<input|<form|<button|<details/.test(html));
  assert.match(html, /slack\/icon.png/);
  assert.match(html, />Slack</);
  assert.match(html, /id="dot"/);
});
