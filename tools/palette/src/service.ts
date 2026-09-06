import type {
  ClipboardItem,
  CommandResult,
  MenubarHost,
  Platform,
  ClipboardPolicy,
  RunHistoryEntry,
  RunHistoryStore,
} from './contracts.ts';
import { PolicyClipboardHistory } from './clipboard-history.ts';
import { CommandDispatcher } from './command-dispatcher.ts';
import { CommandRegistry } from './command-registry.ts';
import type { SearchProvider } from './local-search.ts';

export type PaletteServiceOptions = {
  platform: Platform;
  host: Pick<MenubarHost, 'notify' | 'setMenubarIcon' | 'writeClipboard' | 'openPath'>;
  history: RunHistoryStore;
  clipboard: PolicyClipboardHistory;
  clipboardPolicy: ClipboardPolicy;
  localSearch?: SearchProvider;
};

/** Long-lived Node service facade consumed by the native host and WebView. */
export class PaletteService {
  readonly registry = new CommandRegistry();
  private readonly dispatcher: CommandDispatcher;
  private readonly clipboard: PolicyClipboardHistory;
  private readonly localSearch?: SearchProvider;
  private readonly writeClipboard: (content: string) => Promise<void>;
  private readonly history: RunHistoryStore;
  private clipboardPolicy: ClipboardPolicy;

  constructor(options: PaletteServiceOptions) {
    this.clipboard = options.clipboard;
    this.clipboardPolicy = options.clipboardPolicy;
    this.localSearch = options.localSearch;
    this.writeClipboard = options.host.writeClipboard;
    this.history = options.history;
    this.dispatcher = new CommandDispatcher(this.registry, options.host, options.history, {
      platform: options.platform,
      signal: new AbortController().signal,
    });
    this.registry.register({
      id: 'clipboard-history',
      title: 'Clipboard History',
      subtitle: 'Search and reuse recent copies',
      keywords: ['clipboard', 'history', 'paste'],
      mode: 'visible',
      category: 'command',
      shortcut: { kind: 'accelerator', value: '⌘⇧V' },
      run: async () => ({ status: 'success', nextView: 'clipboard' }),
    });
    this.registry.register({
      id: 'run-history',
      title: 'Run History',
      subtitle: 'Review recent command results',
      keywords: ['recent', 'runs', 'output', 'errors'],
      mode: 'visible',
      category: 'command',
      run: async () => ({ status: 'success', nextView: 'history' }),
    });
  }

  async searchCommands(query = '') {
    if (this.localSearch) {
      for (const summary of await this.localSearch.search(query)) {
        const definition = await this.localSearch.definition(summary.id);
        if (definition && this.registry.modeOf(definition.id) === undefined) {
          try { this.registry.register(definition); } catch {}
        }
      }
    }
    return this.registry.summaries(query);
  }

  executeCommand(commandId: string): Promise<CommandResult> {
    return this.dispatcher.execute(commandId);
  }

  listRunHistory(limit?: number): Promise<RunHistoryEntry[]> {
    return this.history.list(limit);
  }

  listClipboard(query?: string): Promise<ClipboardItem[]> {
    return this.clipboard.list(query);
  }

  async getClipboardItem(id: string): Promise<ClipboardItem | null> {
    return (await this.clipboard.list()).find((item) => item.id === id) ?? null;
  }

  removeClipboard(id: string): Promise<boolean> { return this.clipboard.remove(id); }
  pinClipboard(id: string, pinned: boolean): Promise<ClipboardItem | null> { return this.clipboard.setPinned(id, pinned); }

  async captureClipboard(item: ClipboardItem & { sensitive?: boolean }): Promise<boolean> {
    return this.clipboard.capture(item);
  }

  getClipboardPolicy(): ClipboardPolicy {
    return structuredClone(this.clipboardPolicy);
  }

  setClipboardPolicy(policy: ClipboardPolicy): void {
    if (typeof policy.enabled !== 'boolean' || typeof policy.ignoreSensitive !== 'boolean' || !Number.isInteger(policy.maxItems) || policy.maxItems < 0 || policy.maxItems > 10000 || (policy.retentionDays !== null && (!Number.isFinite(policy.retentionDays) || policy.retentionDays < 0)) || !Array.isArray(policy.excludedAppIds) || policy.excludedAppIds.some((id) => typeof id !== 'string')) throw new Error('Invalid clipboard settings');
    this.clipboardPolicy = structuredClone(policy);
    this.clipboard.setPolicy(this.clipboardPolicy);
  }

  async copyClipboard(id: string): Promise<boolean> {
    const item = (await this.clipboard.list()).find((candidate) => candidate.id === id);
    if (!item) return false;
    if (item.kind === 'image' || item.kind === 'file') throw new Error('Restoring this format requires the native macOS host.');
    await this.writeClipboard(item.content);
    return true;
  }
}
