import test from 'node:test';
import assert from 'node:assert/strict';
import { ShortcutMatcher, ShortcutRegistry } from './shortcut-registry.ts';

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

test('shortcut matcher resolves accelerators and timed chords', () => {
  const registry = new ShortcutRegistry();
  registry.register('open', { kind: 'accelerator', value: '⌥ Space' });
  registry.register('tonal-local', { kind: 'chord', steps: ['⌘T', 'L'], timeoutMs: 500 });
  const matcher = new ShortcutMatcher(registry);

  assert.equal(matcher.press('⌥ space', 100), 'open');
  assert.equal(matcher.press('⌘t', 200), undefined);
  assert.equal(matcher.press('l', 600), 'tonal-local');
  assert.equal(matcher.press('⌘t', 700), undefined);
  assert.equal(matcher.press('l', 1301), undefined);
});
