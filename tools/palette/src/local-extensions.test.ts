import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdir, mkdtemp, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { loadLocalExtensions } from './local-extensions.ts';
import type { ProcessRunner } from './contracts.ts';

test('loads searchable local extension commands with extension-relative paths', async () => {
  const root = await mkdtemp(join(tmpdir(), 'palette-extensions-'));
  const extensionRoot = join(root, 'sample');
  await mkdir(extensionRoot);
  await writeFile(join(extensionRoot, 'extension.json'), JSON.stringify({
    id: 'sample-tools',
    name: 'Sample Tools',
    commands: [{ id: 'hello', title: 'Say Hello', command: './hello', args: ['world'] }],
  }));
  const calls: unknown[] = [];
  const runner: ProcessRunner = { run: async (spec) => { calls.push(spec); return { status: 'success' }; } };
  try {
    const commands = await loadLocalExtensions(root, runner);
    assert.equal(commands.length, 1);
    assert.equal(commands[0]?.id, 'extension:sample-tools:hello');
    assert.equal(commands[0]?.category, 'extension');
    assert.ok(commands[0]?.keywords?.includes('Sample Tools'));
    await commands[0]?.run({ platform: 'macos', invocation: 'silent', signal: new AbortController().signal });
    assert.deepEqual(calls, [{
      command: join(extensionRoot, 'hello'),
      args: ['world'],
      cwd: extensionRoot,
      background: true,
    }]);
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});
