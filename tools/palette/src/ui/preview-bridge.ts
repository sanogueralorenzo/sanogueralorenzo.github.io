import type { PaletteBridge } from './PaletteApp.tsx';
import type { ClipboardItem, ClipboardPolicy } from '../contracts.ts';

/** Synthetic, memory-only data for visual review. Never connected to the system clipboard. */
export function createPreviewBridge(): PaletteBridge {
  const ago = (minutes: number) => Date.now() - minutes * 60_000;
  let policy: ClipboardPolicy = { enabled: true, maxItems: 200, retentionDays: 30, excludedAppIds: [], ignoreSensitive: true };
  let items: ClipboardItem[] = [
    { id: 'link', kind: 'url', content: 'https://developer.apple.com/documentation/webkit', title: 'WebKit documentation', sourceAppName: 'Safari', sourceAppId: 'com.apple.Safari', createdAt: ago(2), pinned: false },
    { id: 'note', kind: 'text', content: 'Ship the smaller version first.\n\nMake finding and reusing a clip feel effortless. Keep the keyboard flow clear, the preview useful, and the source app easy to recognize.', sourceAppName: 'Slack', sourceAppId: 'com.tinyspeck.slackmacgap', createdAt: ago(8), pinned: false },
    { id: 'code', kind: 'text', content: 'npm run build', sourceAppName: 'VS Code', sourceAppId: 'com.microsoft.VSCode', createdAt: ago(22), pinned: false },
    { id: 'file', kind: 'file', content: '/Example/Design/Palette/clipboard-exploration.png', sourceAppName: 'Finder', sourceAppId: 'com.apple.finder', createdAt: ago(35), pinned: false },
    { id: 'pin', kind: 'text', content: 'Focus on finding and reusing.', sourceAppName: 'Slack', sourceAppId: 'com.tinyspeck.slackmacgap', createdAt: ago(48), pinned: true },
  ];
  return {
    searchCommands: async () => [{ id: 'clipboard', title: 'Clipboard History', subtitle: 'Synthetic preview', mode: 'visible' }],
    executeCommand: async () => ({ status: 'success', nextView: 'clipboard' }),
    listClipboard: async (query) => items.filter((item) => item.content.toLowerCase().includes(query.toLowerCase())),
    copyClipboard: async () => true,
    pasteClipboard: async () => { throw new Error('Browser preview: use the native app to verify paste.'); },
    pinClipboard: async (id, pinned) => { const item = items.find((item) => item.id === id); if (!item) return null; item.pinned = pinned; return item; },
    removeClipboard: async (id) => { items = items.filter((item) => item.id !== id); return true; },
    getClipboardPolicy: async () => policy,
    setClipboardPolicy: async (next) => { policy = next; },
  };
}
