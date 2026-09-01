import type { BridgeRequest, BridgeRequestBody, BridgeResponse, HostBridgeMessage } from '../bridge-protocol.ts';
import type { ClipboardItem, ClipboardPolicy, CommandResult, CommandSummary, RunHistoryEntry } from '../contracts.ts';
import type { PaletteBridge } from './PaletteApp.tsx';

type WebKitMessageHandler = { postMessage(message: BridgeRequest | HostBridgeMessage): void };
type WebView2Bridge = {
  postMessage(message: BridgeRequest | HostBridgeMessage): void;
  addEventListener(type: 'message', listener: (event: MessageEvent<BridgeResponse>) => void): void;
};
type PaletteWindow = Window & {
  __paletteResolve?: (response: BridgeResponse) => void;
  webkit?: { messageHandlers?: { palette?: WebKitMessageHandler } };
  chrome?: { webview?: WebView2Bridge };
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
  target.chrome?.webview?.addEventListener('message', (event) => target.__paletteResolve?.(event.data));

  function request(message: BridgeRequestBody): Promise<BridgeResponse> {
    const handler = target.webkit?.messageHandlers?.palette;
    const webview2 = target.chrome?.webview;
    if (!handler && !webview2) return Promise.reject(new Error('Palette host bridge is not connected'));
    const id = `webview-${++sequence}`;
    return new Promise((resolve, reject) => {
      pending.set(id, { resolve, reject });
      const payload = { ...message, id };
      if (handler) handler.postMessage(payload);
      else webview2?.postMessage(payload);
    });
  }

  function hostMessage(message: HostBridgeMessage): void {
    const handler = target.webkit?.messageHandlers?.palette;
    const webview2 = target.chrome?.webview;
    if (handler) handler.postMessage(message);
    else if (webview2) webview2.postMessage(message);
    else if (message.type === 'dismissLauncher') window.close();
  }

  hostMessage({ type: 'hostReady' });

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
    listRunHistory: async (limit): Promise<RunHistoryEntry[]> => {
      const response = await request({ type: 'listRunHistory', limit });
      return response.ok && response.payload.type === 'runHistory' ? response.payload.entries : [];
    },
    listClipboard: async (query): Promise<ClipboardItem[]> => {
      const response = await request({ type: 'listClipboard', query });
      return response.ok && response.payload.type === 'clipboard' ? response.payload.items : [];
    },
    copyClipboard: async (itemId): Promise<boolean> => {
      const response = await request({ type: 'copyClipboard', itemId });
      return response.ok && response.payload.type === 'copied' ? response.payload.copied : false;
    },
    getClipboardPolicy: async (): Promise<ClipboardPolicy> => {
      const response = await request({ type: 'getClipboardPolicy' });
      if (response.ok && response.payload.type === 'clipboardPolicy') return response.payload.policy;
      throw new Error('Invalid clipboard policy response');
    },
    setClipboardPolicy: async (policy: ClipboardPolicy): Promise<void> => {
      const response = await request({ type: 'setClipboardPolicy', policy });
      if (!response.ok || response.payload.type !== 'clipboardPolicy') throw new Error('Invalid clipboard policy response');
    },
    dismissLauncher: () => hostMessage({ type: 'dismissLauncher' }),
  };
}
