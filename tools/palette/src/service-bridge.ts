import type { BridgeRequest, BridgeResponse } from './bridge-protocol.ts';
import type { ClipboardCapture, ClipboardItem, ClipboardPolicy, CommandResult, CommandSummary, RunHistoryEntry } from './contracts.ts';

export type PaletteBridgeBackend = {
  searchCommands(query: string): Promise<CommandSummary[]>;
  executeCommand(commandId: string): Promise<CommandResult>;
  listRunHistory(limit?: number): Promise<RunHistoryEntry[]>;
  listClipboard(query: string): Promise<ClipboardItem[]>;
  copyClipboard(itemId: string): Promise<boolean>;
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
      case 'listClipboard':
        return { id: request.id, ok: true, payload: { type: 'clipboard', items: await backend.listClipboard(request.query) } };
      case 'copyClipboard':
        return { id: request.id, ok: true, payload: { type: 'copied', copied: await backend.copyClipboard(request.itemId) } };
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
