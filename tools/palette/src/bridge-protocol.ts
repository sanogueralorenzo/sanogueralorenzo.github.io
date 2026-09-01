import type { ClipboardCapture, ClipboardItem, ClipboardPolicy, CommandResult, CommandSummary, Notification, RunHistoryEntry } from './contracts.ts';

export type BridgeRequestBody =
  | { type: 'searchCommands'; query: string }
  | { type: 'executeCommand'; commandId: string }
  | { type: 'listRunHistory'; limit?: number }
  | { type: 'listClipboard'; query: string }
  | { type: 'copyClipboard'; itemId: string }
  | { type: 'captureClipboard'; item: ClipboardCapture }
  | { type: 'getClipboardPolicy' }
  | { type: 'setClipboardPolicy'; policy: ClipboardPolicy };

export type BridgeRequest = BridgeRequestBody & { id: string };

export type BridgePayload =
  | { type: 'commands'; commands: CommandSummary[] }
  | { type: 'commandResult'; result: CommandResult }
  | { type: 'runHistory'; entries: RunHistoryEntry[] }
  | { type: 'clipboard'; items: ClipboardItem[] }
  | { type: 'copied'; copied: boolean }
  | { type: 'captured'; captured: boolean }
  | { type: 'clipboardPolicy'; policy: ClipboardPolicy };

export type BridgeResponse =
  | { id: string; ok: true; payload: BridgePayload }
  | { id: string; ok: false; error: string };

/** Out-of-band events emitted by a resident service (never confused with a response). */
export type BridgeEvent = { type: 'notification'; notification: Notification };

/** Messages consumed by a native host instead of the Node service. */
export type HostBridgeMessage = { type: 'dismissLauncher' } | { type: 'hostReady' };
