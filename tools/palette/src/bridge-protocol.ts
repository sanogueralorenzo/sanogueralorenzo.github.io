import type { ClipboardItem, CommandResult, CommandSummary } from './contracts.ts';

export type BridgeRequestBody =
  | { type: 'searchCommands'; query: string }
  | { type: 'executeCommand'; commandId: string }
  | { type: 'listClipboard'; query: string }
  | { type: 'copyClipboard'; itemId: string };

export type BridgeRequest = BridgeRequestBody & { id: string };

export type BridgePayload =
  | { type: 'commands'; commands: CommandSummary[] }
  | { type: 'commandResult'; result: CommandResult }
  | { type: 'clipboard'; items: ClipboardItem[] }
  | { type: 'copied'; copied: boolean };

export type BridgeResponse =
  | { id: string; ok: true; payload: BridgePayload }
  | { id: string; ok: false; error: string };
