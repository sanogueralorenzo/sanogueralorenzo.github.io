import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, writeFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { loadConfiguredCommands } from './command-config.ts';
import type { ProcessRunner } from './contracts.ts';

test('loads configured direct-process commands and skips malformed entries', async () => {
  const root = await mkdtemp(join(tmpdir(), 'palette-commands-'));
  try {
    const path = join(root, 'commands.json');
    await writeFile(path, JSON.stringify([
      { id: 'tonal-local', title: 'Tonal Local', keywords: ['tonal'], shortcut: { kind: 'chord', steps: ['⌘T', 'L'] }, command: '/usr/local/bin/tonal', args: ['local'], mode: 'silent' },
      { id: 'missing-command' },
    ]));
    const runner: ProcessRunner = { run: async () => ({ status: 'success', output: 'ok' }) };
    const commands = await loadConfiguredCommands(path, runner);
    assert.equal(commands.length, 1);
    assert.equal(commands[0]?.mode, 'silent');
    assert.deepEqual(commands[0]?.shortcut, { kind: 'chord', steps: ['⌘T', 'L'] });
    assert.deepEqual(await commands[0]!.run({ platform: 'macos', invocation: 'visible', signal: new AbortController().signal }), { status: 'success', output: 'ok' });
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});
