import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { JsonSettingsStore } from './settings-store.ts';

test('settings store defaults safely and persists clipboard policy', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'palette-settings-'));
  try {
    const store = new JsonSettingsStore(join(directory, 'settings.json'));
    const defaults = await store.load();
    assert.equal(defaults.clipboard.enabled, true);
    await store.save({ clipboard: { ...defaults.clipboard, enabled: false, maxItems: 12, excludedAppIds: ['com.example.App'] } });
    const restored = await store.load();
    assert.equal(restored.clipboard.enabled, false);
    assert.equal(restored.clipboard.maxItems, 12);
    assert.deepEqual(restored.clipboard.excludedAppIds, ['com.example.App']);
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});
