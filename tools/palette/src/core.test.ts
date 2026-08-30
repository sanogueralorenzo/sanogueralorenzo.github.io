import test from 'node:test';
import assert from 'node:assert/strict';
import { CommandRegistry } from './command-registry.ts';
import { PolicyClipboardHistory } from './clipboard-history.ts';
import type { ClipboardItem, ClipboardStore } from './contracts.ts';

const signal = new AbortController().signal;

test('registry ranks exact, prefix, and keyword matches', () => {
  const registry = new CommandRegistry();
  registry.register({ id: 'open-terminal', title: 'Open Terminal', keywords: ['shell'], mode: 'visible', run: async () => ({ status: 'success' }) });
  registry.register({ id: 'tonal-local', title: 'Tonal Local', keywords: ['tonal'], mode: 'silent', background: true, run: async () => ({ status: 'success' }) });

  assert.equal(registry.summaries('tonal')[0]?.id, 'tonal-local');
  assert.equal(registry.summaries('terminal')[0]?.id, 'open-terminal');
  assert.equal(registry.summaries('missing').length, 0);
});

test('execution preserves silent mode and returns failures instead of throwing', async () => {
  const registry = new CommandRegistry();
  let invocation = '';
  registry.register({
    id: 'silent-command',
    title: 'Silent Command',
    mode: 'silent',
    run: async (context) => { invocation = context.invocation; return { status: 'success', output: 'done' }; },
  });
  registry.register({ id: 'broken', title: 'Broken', mode: 'visible', run: async () => { throw new Error('boom'); } });

  assert.deepEqual(await registry.execute('silent-command', { platform: 'macos', invocation: 'visible', signal }), { status: 'success', output: 'done' });
  assert.equal(invocation, 'silent');
  assert.deepEqual(await registry.execute('broken', { platform: 'macos', invocation: 'visible', signal }), { status: 'failure', message: 'boom' });
});

class MemoryClipboardStore implements ClipboardStore {
  items: ClipboardItem[] = [];
  async list(query?: string): Promise<ClipboardItem[]> { return query ? this.items.filter((item) => item.content.includes(query)) : [...this.items]; }
  async add(item: ClipboardItem): Promise<boolean> { this.items.unshift(item); return true; }
  async remove(id: string): Promise<boolean> { const before = this.items.length; this.items = this.items.filter((item) => item.id !== id); return before !== this.items.length; }
  async setPinned(id: string, pinned: boolean): Promise<ClipboardItem | null> { const item = this.items.find((candidate) => candidate.id === id); if (!item) return null; item.pinned = pinned; return item; }
  async clear(): Promise<void> { this.items = []; }
}

test('clipboard policy excludes sensitive and blacklisted captures', async () => {
  const store = new MemoryClipboardStore();
  const history = new PolicyClipboardHistory(store, { enabled: true, maxItems: 10, retentionDays: null, excludedAppIds: ['com.passwords'], ignoreSensitive: true });
  const base = { kind: 'text' as const, createdAt: Date.now(), pinned: false };

  assert.equal(await history.capture({ ...base, id: 'secret', content: 'password', sensitive: true }), false);
  assert.equal(await history.capture({ ...base, id: 'blocked', content: 'token', sourceAppId: 'com.passwords' }), false);
  assert.equal(await history.capture({ ...base, id: 'okay', content: 'hello' }), true);
  assert.deepEqual((await history.list()).map((item) => item.id), ['okay']);
});

test('clipboard history preserves pinned items while pruning oldest unpinned items', async () => {
  const store = new MemoryClipboardStore();
  const history = new PolicyClipboardHistory(store, { enabled: true, maxItems: 2, retentionDays: null, excludedAppIds: [], ignoreSensitive: true });
  const now = Date.now();
  const item = (id: string, pinned = false): ClipboardItem => ({ id, kind: 'text', content: id, createdAt: now, pinned });

  await history.capture(item('old'));
  await history.capture(item('pinned', true));
  await history.capture(item('new'));

  assert.deepEqual((await history.list()).map((entry) => entry.id), ['new', 'pinned']);
});
