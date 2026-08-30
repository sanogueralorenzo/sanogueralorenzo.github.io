import type {
  ClipboardItem,
  CommandResult,
  MenubarHost,
  Platform,
  RunHistoryStore,
} from './contracts.ts';
import { PolicyClipboardHistory } from './clipboard-history.ts';
import { CommandDispatcher } from './command-dispatcher.ts';
import { CommandRegistry } from './command-registry.ts';

export type PaletteServiceOptions = {
  platform: Platform;
  host: Pick<MenubarHost, 'notify' | 'setMenubarIcon' | 'writeClipboard'>;
  history: RunHistoryStore;
  clipboard: PolicyClipboardHistory;
};

/** Long-lived Node service facade consumed by the native host and WebView. */
export class PaletteService {
  readonly registry = new CommandRegistry();
  private readonly dispatcher: CommandDispatcher;
  private readonly clipboard: PolicyClipboardHistory;
  private readonly writeClipboard: (content: string) => Promise<void>;

  constructor(options: PaletteServiceOptions) {
    this.clipboard = options.clipboard;
    this.writeClipboard = options.host.writeClipboard;
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
      shortcut: { kind: 'accelerator', value: '⌘⇧V' },
      run: async () => ({ status: 'success', nextView: 'clipboard' }),
    });
  }

  searchCommands(query = '') {
    return this.registry.summaries(query);
  }

  executeCommand(commandId: string): Promise<CommandResult> {
    return this.dispatcher.execute(commandId);
  }

  listClipboard(query?: string): Promise<ClipboardItem[]> {
    return this.clipboard.list(query);
  }

  async captureClipboard(item: ClipboardItem & { sensitive?: boolean }): Promise<boolean> {
    return this.clipboard.capture(item);
  }

  async copyClipboard(id: string): Promise<boolean> {
    const item = (await this.clipboard.list()).find((candidate) => candidate.id === id);
    if (!item) return false;
    await this.writeClipboard(item.content);
    return true;
  }
}
