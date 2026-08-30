import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, mkdir, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { LocalSearchProvider } from './local-search.ts';

test('local search discovers apps and files and keeps them executable', async () => {
  const root = await mkdtemp(join(tmpdir(), 'palette-search-'));
  const opened: string[] = [];
  try {
    await mkdir(join(root, 'Demo.app'));
    await mkdir(join(root, 'nested'));
    await writeFile(join(root, 'nested', 'project-notes.md'), 'notes');
    await writeFile(join(root, 'demo.desktop'), '[Desktop Entry]');
    const provider = new LocalSearchProvider({ roots: [root], openPath: async (path) => { opened.push(path); } });

    const appResults = await provider.search('demo');
    assert.deepEqual(appResults.map((result) => result.category).sort(), ['app', 'app']);
    const fileResults = await provider.search('project-notes');
    assert.equal(fileResults[0]?.category, 'file');

    const definition = await provider.definition(fileResults[0]!.id);
    assert.ok(definition);
    const result = await definition!.run({ platform: 'macos', invocation: 'visible', signal: new AbortController().signal });
    assert.equal(result.status, 'success');
    assert.equal(opened[0], join(root, 'nested', 'project-notes.md'));
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});
