import test from 'node:test';
import assert from 'node:assert/strict';
import { ShortcutRegistry } from './shortcut-registry.ts';

test('shortcut registry detects accelerator and chord conflicts', () => {
  const registry = new ShortcutRegistry();
  registry.register('open-palette', { kind: 'accelerator', value: '⌘ Space' });
  registry.register('tonal-local', { kind: 'chord', steps: ['⌘T', 'L'], timeoutMs: 800 });

  assert.equal(registry.find({ kind: 'accelerator', value: '  ⌘ SPACE ' }), 'open-palette');
  assert.equal(registry.find({ kind: 'chord', steps: ['⌘t', 'l'] }), 'tonal-local');
  assert.throws(() => registry.register('other', { kind: 'chord', steps: ['⌘t', 'l'] }), /already assigned/);
  assert.throws(() => registry.register('invalid', { kind: 'chord', steps: ['⌘T'] }), /at least two/);
});

test('unregister removes every shortcut owned by a command', () => {
  const registry = new ShortcutRegistry();
  registry.register('clipboard', { kind: 'accelerator', value: '⌘⇧V' });
  registry.register('clipboard', { kind: 'chord', steps: ['⌘K', 'V'] });
  registry.unregister('clipboard');

  assert.equal(registry.list().length, 0);
});
