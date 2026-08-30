import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { randomBytes } from 'node:crypto';
import { EncryptedJsonClipboardStore } from './encrypted-clipboard-store.ts';

test('encrypted clipboard store persists and reloads without plaintext on disk', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'palette-clipboard-'));
  const file = join(directory, 'history.json');
  const key = randomBytes(32);
  try {
    const first = new EncryptedJsonClipboardStore(file, key);
    await first.add({ id: 'one', kind: 'text', content: 'private clipboard value', createdAt: Date.now(), pinned: false });

    const raw = await readFile(file, 'utf8');
    assert.equal(raw.includes('private clipboard value'), false);

    const second = new EncryptedJsonClipboardStore(file, key);
    assert.equal((await second.list())[0]?.content, 'private clipboard value');
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});

test('encrypted clipboard store requires a 32-byte key', () => {
  assert.throws(() => new EncryptedJsonClipboardStore('/tmp/clipboard.json', randomBytes(16)), /32 bytes/);
});
