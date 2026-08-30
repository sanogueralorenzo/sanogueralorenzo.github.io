import test from 'node:test';
import assert from 'node:assert/strict';
import { handleBridgeRequest } from './service-bridge.ts';
import type { ClipboardCapture, ClipboardPolicy } from './contracts.ts';

const policy: ClipboardPolicy = { enabled: true, maxItems: 50, retentionDays: 7, excludedAppIds: [], ignoreSensitive: true };

test('bridge dispatches typed search, execution, clipboard, and copy requests', async () => {
  const backend = {
    searchCommands: async (query: string) => [{ id: query, title: query, mode: 'visible' as const }],
    executeCommand: async (commandId: string) => ({ status: 'success' as const, output: commandId }),
    listClipboard: async (query: string) => [{ id: query, kind: 'text' as const, content: query, createdAt: 1, pinned: false }],
    copyClipboard: async (itemId: string) => itemId === 'known',
    captureClipboard: async (item: ClipboardCapture) => item.content === 'capture me',
    getClipboardPolicy: async () => policy,
    setClipboardPolicy: async (next: ClipboardPolicy) => next,
  };

  const commands = await handleBridgeRequest({ id: '1', type: 'searchCommands', query: 'tonal' }, backend);
  assert.equal(commands.ok, true);
  if (commands.ok) assert.equal(commands.payload.type, 'commands');

  const result = await handleBridgeRequest({ id: '2', type: 'executeCommand', commandId: 'tonal-local' }, backend);
  assert.equal(result.ok, true);
  if (result.ok && result.payload.type === 'commandResult') assert.equal(result.payload.result.output, 'tonal-local');

  const clipboard = await handleBridgeRequest({ id: '3', type: 'listClipboard', query: 'hello' }, backend);
  assert.equal(clipboard.ok, true);
  if (clipboard.ok && clipboard.payload.type === 'clipboard') assert.equal(clipboard.payload.items[0]?.content, 'hello');

  const copied = await handleBridgeRequest({ id: '4', type: 'copyClipboard', itemId: 'known' }, backend);
  assert.equal(copied.ok, true);
  if (copied.ok && copied.payload.type === 'copied') assert.equal(copied.payload.copied, true);

  const captured = await handleBridgeRequest({ id: '5', type: 'captureClipboard', item: { id: 'c', kind: 'text', content: 'capture me', createdAt: 1, pinned: false } }, backend);
  assert.equal(captured.ok, true);
  if (captured.ok && captured.payload.type === 'captured') assert.equal(captured.payload.captured, true);

  const currentPolicy = await handleBridgeRequest({ id: '6', type: 'getClipboardPolicy' }, backend);
  assert.equal(currentPolicy.ok, true);
  if (currentPolicy.ok && currentPolicy.payload.type === 'clipboardPolicy') assert.equal(currentPolicy.payload.policy.maxItems, 50);

  const updatedPolicy = await handleBridgeRequest({ id: '7', type: 'setClipboardPolicy', policy: { ...policy, enabled: false } }, backend);
  assert.equal(updatedPolicy.ok, true);
  if (updatedPolicy.ok && updatedPolicy.payload.type === 'clipboardPolicy') assert.equal(updatedPolicy.payload.policy.enabled, false);
});

test('bridge turns backend errors into response errors', async () => {
  const response = await handleBridgeRequest({ id: 'x', type: 'executeCommand', commandId: 'broken' }, {
    searchCommands: async () => [],
    executeCommand: async () => { throw new Error('backend offline'); },
    listClipboard: async () => [],
    copyClipboard: async () => false,
    captureClipboard: async () => false,
    getClipboardPolicy: async () => policy,
    setClipboardPolicy: async (next: ClipboardPolicy) => next,
  });
  assert.deepEqual(response, { id: 'x', ok: false, error: 'backend offline' });
});
