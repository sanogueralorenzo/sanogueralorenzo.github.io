import type { BridgeRequest, BridgeRequestBody, BridgeResponse } from '../bridge-protocol.ts';
import type { ClipboardItem, CommandResult, CommandSummary } from '../contracts.ts';
import type { PaletteBridge } from './PaletteApp.tsx';

type WebKitMessageHandler = { postMessage(message: BridgeRequest): void };
type PaletteWindow = Window & {
  __paletteResolve?: (response: BridgeResponse) => void;
  webkit?: { messageHandlers?: { palette?: WebKitMessageHandler } };
};

/** WebView transport used by WKWebView/WebView2 hosts; no Electron globals. */
export function createWebViewBridge(): PaletteBridge {
  const target = window as PaletteWindow;
  let sequence = 0;
  const pending = new Map<string, { resolve: (response: BridgeResponse) => void; reject: (error: Error) => void }>();

  target.__paletteResolve = (response) => {
    const request = pending.get(response.id);
    if (!request) return;
    pending.delete(response.id);
    if (response.ok) request.resolve(response);
    else request.reject(new Error(response.error));
  };

  function request(message: BridgeRequestBody): Promise<BridgeResponse> {
    const handler = target.webkit?.messageHandlers?.palette;
    if (!handler) return Promise.reject(new Error('Palette host bridge is not connected'));
    const id = `webview-${++sequence}`;
    return new Promise((resolve, reject) => {
      pending.set(id, { resolve, reject });
      handler.postMessage({ ...message, id });
    });
  }

  return {
    searchCommands: async (query): Promise<CommandSummary[]> => {
      const response = await request({ type: 'searchCommands', query });
      return response.ok && response.payload.type === 'commands' ? response.payload.commands : [];
    },
    executeCommand: async (commandId): Promise<CommandResult> => {
      const response = await request({ type: 'executeCommand', commandId });
      if (response.ok && response.payload.type === 'commandResult') return response.payload.result;
      throw new Error('Invalid command response');
    },
    listClipboard: async (query): Promise<ClipboardItem[]> => {
      const response = await request({ type: 'listClipboard', query });
      return response.ok && response.payload.type === 'clipboard' ? response.payload.items : [];
    },
    copyClipboard: async (itemId): Promise<boolean> => {
      const response = await request({ type: 'copyClipboard', itemId });
      return response.ok && response.payload.type === 'copied' ? response.payload.copied : false;
    },
  };
}
