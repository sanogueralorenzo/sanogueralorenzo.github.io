import type { BridgeRequest, BridgeResponse } from './bridge-protocol.ts';
import { createHash } from 'node:crypto';
import type { ClipboardCapture, ClipboardItem, ClipboardPolicy, CommandResult, CommandSummary, RunHistoryEntry } from './contracts.ts';

export type PaletteBridgeBackend = {
  searchCommands(query: string): Promise<CommandSummary[]>;
  executeCommand(commandId: string): Promise<CommandResult>;
  listRunHistory(limit?: number): Promise<RunHistoryEntry[]>;
  listClipboard(query: string): Promise<ClipboardItem[]>;
  copyClipboard(itemId: string): Promise<boolean>;
  getClipboardItem?(itemId: string): Promise<ClipboardItem | null>;
  removeClipboard?(itemId: string): Promise<boolean>;
  pinClipboard?(itemId: string, pinned: boolean): Promise<ClipboardItem | null>;
  captureClipboard(item: ClipboardCapture): Promise<boolean>;
  getClipboardPolicy(): Promise<ClipboardPolicy>;
  setClipboardPolicy(policy: ClipboardPolicy): Promise<ClipboardPolicy>;
};

/** Dispatches serialized WebView messages without knowing the host transport. */
export async function handleBridgeRequest(
  request: BridgeRequest,
  backend: PaletteBridgeBackend,
): Promise<BridgeResponse> {
  try {
    switch (request.type) {
      case 'searchCommands':
        return { id: request.id, ok: true, payload: { type: 'commands', commands: await backend.searchCommands(request.query) } };
      case 'executeCommand':
        return { id: request.id, ok: true, payload: { type: 'commandResult', result: await backend.executeCommand(request.commandId) } };
      case 'listRunHistory':
        return { id: request.id, ok: true, payload: { type: 'runHistory', entries: await backend.listRunHistory(request.limit) } };
      case 'listClipboard': {
        const items = await backend.listClipboard(request.query);
        if (request.revision === undefined) return { id: request.id, ok: true, payload: { type: 'clipboard', items } };
        // Stored clips are immutable apart from pins; recapture updates createdAt.
        // Avoid serializing and transferring binary previews on unchanged polls.
        const revision = createHash('sha256').update(JSON.stringify(items.map(({ id, createdAt, pinned }) => [id, createdAt, pinned]))).digest('hex');
        const unchanged = request.revision === revision;
        return { id: request.id, ok: true, payload: { type: 'clipboard', items: unchanged ? [] : items, revision, unchanged } };
      }
      case 'copyClipboard':
        return { id: request.id, ok: true, payload: { type: 'copied', copied: await backend.copyClipboard(request.itemId) } };
      case 'pasteClipboard':
        throw new Error('Direct paste requires the native macOS host. Use Copy instead.');
      case 'getClipboardItem':
        return { id: request.id, ok: true, payload: { type: 'clipboardItem', item: await backend.getClipboardItem?.(request.itemId) ?? null } };
      case 'removeClipboard':
        return { id: request.id, ok: true, payload: { type: 'removed', removed: await backend.removeClipboard?.(request.itemId) ?? false } };
      case 'pinClipboard':
        return { id: request.id, ok: true, payload: { type: 'clipboardItem', item: await backend.pinClipboard?.(request.itemId, request.pinned) ?? null } };
      case 'captureClipboard':
        return { id: request.id, ok: true, payload: { type: 'captured', captured: await backend.captureClipboard(request.item) } };
      case 'getClipboardPolicy':
        return { id: request.id, ok: true, payload: { type: 'clipboardPolicy', policy: await backend.getClipboardPolicy() } };
      case 'setClipboardPolicy':
        return { id: request.id, ok: true, payload: { type: 'clipboardPolicy', policy: await backend.setClipboardPolicy(request.policy) } };
    }
  } catch (error) {
    return { id: request.id, ok: false, error: error instanceof Error ? error.message : String(error) };
  }
}
