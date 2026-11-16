import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import vm from 'node:vm';

const source = readFileSync(new URL('./extension/popup.mjs', import.meta.url), 'utf8');
test('popup updates from pushed status without polling and disconnects when closed', () => {
  const dot = { dataset: {}, attributes: {}, setAttribute(name, value) { this.attributes[name] = value; } };
  let message, disconnect, close, closed = false;
  const port = { onMessage: { addListener: fn => { message = fn; } }, onDisconnect: { addListener: fn => { disconnect = fn; } }, disconnect() { closed = true; } };
  vm.runInNewContext(source, { document: { getElementById: () => dot }, chrome: { runtime: { connect(options) { assert.equal(options.name, 'popup'); return port; } } },
    window: { addEventListener(name, fn) { assert.equal(name, 'pagehide'); close = fn; } } });
  message({ type: 'status', connected: true, detail: 'Slack connected' });
  assert.equal(dot.dataset.connected, 'true'); assert.equal(dot.attributes['aria-label'], 'Slack connected');
  message({ type: 'status', connected: false, detail: 'Bridge disconnected' });
  assert.equal(dot.dataset.connected, 'false'); assert.equal(dot.title, 'Bridge disconnected');
  disconnect(); assert.match(dot.title, /Reopen/);
  close(); assert.equal(closed, true);
});
test('popup contains only the Slack icon, label and connection status', () => {
  const html = readFileSync(new URL('../popup/index.html', import.meta.url), 'utf8');
  assert.ok(!/<input|<form|<button|<details/.test(html));
  assert.match(html, /slack\/icon.png/); assert.match(html, />Slack</); assert.match(html, /id="dot"/);
});
