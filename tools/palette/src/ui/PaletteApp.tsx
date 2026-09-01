import { useEffect, useRef, useState, type KeyboardEvent } from 'react';
import type { ClipboardItem, ClipboardPolicy, CommandResult, CommandSummary, RunHistoryEntry } from '../contracts.ts';
import { CommandRegistry } from '../command-registry.ts';

export type PaletteBridge = {
  searchCommands(query: string): Promise<CommandSummary[]>;
  executeCommand(id: string): Promise<CommandResult>;
  listRunHistory?: (limit?: number) => Promise<RunHistoryEntry[]>;
  listClipboard?: (query: string) => Promise<ClipboardItem[]>;
  copyClipboard?: (id: string) => Promise<boolean>;
  getClipboardPolicy?: () => Promise<ClipboardPolicy>;
  setClipboardPolicy?: (policy: ClipboardPolicy) => Promise<void>;
  dismissLauncher?: () => void;
};

const emptyBridge: PaletteBridge = {
  searchCommands: async () => [],
  executeCommand: async () => ({ status: 'failure', message: 'Palette bridge is not connected' }),
};

export type PaletteAppProps = { bridge?: PaletteBridge };

/** Minimal launcher UI; all OS and process work enters through PaletteBridge. */
export function PaletteApp({ bridge = emptyBridge }: PaletteAppProps) {
  const [query, setQuery] = useState('');
  const [commands, setCommands] = useState<CommandSummary[]>([]);
  const [selected, setSelected] = useState(0);
  const [feedback, setFeedback] = useState<string>('');
  const [activeView, setActiveView] = useState<'launcher' | 'clipboard' | 'history'>('launcher');
  const [clipboardItems, setClipboardItems] = useState<ClipboardItem[]>([]);
  const [historyEntries, setHistoryEntries] = useState<RunHistoryEntry[]>([]);
  const [clipboardPolicy, setClipboardPolicyState] = useState<ClipboardPolicy | undefined>();
  const inputRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    const hostWindow = window as Window & { __paletteOpen?: () => void; __paletteOpenClipboard?: () => void };
    const focus = () => requestAnimationFrame(() => inputRef.current?.focus());
    hostWindow.__paletteOpen = () => { setActiveView('launcher'); setQuery(''); setFeedback(''); focus(); };
    hostWindow.__paletteOpenClipboard = () => { setActiveView('clipboard'); setQuery(''); setFeedback(''); focus(); };
    return () => { delete hostWindow.__paletteOpen; delete hostWindow.__paletteOpenClipboard; };
  }, []);

  useEffect(() => {
    const failed = (error: unknown) => setFeedback(error instanceof Error ? error.message : String(error));
    if (activeView === 'clipboard' && bridge.listClipboard) void bridge.listClipboard(query).then(setClipboardItems).catch(failed);
    else if (activeView === 'history' && bridge.listRunHistory) void bridge.listRunHistory(50).then(setHistoryEntries).catch(failed);
    else if (activeView === 'launcher') void bridge.searchCommands(query).then(setCommands).catch(failed);
  }, [activeView, bridge, query]);
  useEffect(() => {
    if (activeView === 'clipboard' && bridge.getClipboardPolicy) {
      void bridge.getClipboardPolicy().then(setClipboardPolicyState)
        .catch((error: unknown) => setFeedback(error instanceof Error ? error.message : String(error)));
    }
  }, [activeView, bridge]);
  useEffect(() => { setSelected(0); }, [activeView, query, commands.length, clipboardItems.length, historyEntries.length]);
  useEffect(() => { inputRef.current?.focus(); }, [activeView]);

  async function execute(command: CommandSummary | undefined): Promise<void> {
    if (!command) return;
    let result: CommandResult;
    try {
      result = await bridge.executeCommand(command.id);
    } catch (error) {
      setFeedback(error instanceof Error ? error.message : String(error));
      return;
    }
    if (result.nextView === 'clipboard') {
      setActiveView('clipboard');
      setQuery('');
      setFeedback('');
      return;
    }
    if (result.nextView === 'history') {
      setActiveView('history');
      setQuery('');
      setFeedback('');
      return;
    }
    setFeedback(result.status === 'success' ? (result.output || 'Done') : (result.message || 'Action failed'));
  }

  function onKeyDown(event: KeyboardEvent<HTMLInputElement>): void {
    const count = activeView === 'launcher' ? commands.length : activeView === 'clipboard' ? clipboardItems.length : historyEntries.length;
    if (event.key === 'ArrowDown') { event.preventDefault(); setSelected((value) => Math.min(value + 1, Math.max(0, count - 1))); }
    if (event.key === 'ArrowUp') { event.preventDefault(); setSelected((value) => Math.max(value - 1, 0)); }
    if (event.key === 'Enter') {
      event.preventDefault();
      if (activeView === 'launcher') void execute(commands[selected]);
      else if (activeView === 'clipboard' && clipboardItems[selected]) void copyClipboard(clipboardItems[selected]);
    }
    if (event.key === 'Escape') {
      event.preventDefault();
      if (activeView !== 'launcher') setActiveView('launcher');
      else bridge.dismissLauncher?.();
    }
  }

  async function copyClipboard(item: ClipboardItem): Promise<void> {
    try {
      const copied = await bridge.copyClipboard?.(item.id);
      setFeedback(copied === false ? 'Could not copy item' : 'Copied to clipboard');
    } catch (error) {
      setFeedback(error instanceof Error ? error.message : String(error));
    }
  }

  async function toggleClipboardCapture(): Promise<void> {
    if (!clipboardPolicy || !bridge.setClipboardPolicy) return;
    const next = { ...clipboardPolicy, enabled: !clipboardPolicy.enabled };
    try {
      await bridge.setClipboardPolicy(next);
      setClipboardPolicyState(next);
      setFeedback(next.enabled ? 'Clipboard capture resumed' : 'Clipboard capture paused');
    } catch (error) {
      setFeedback(error instanceof Error ? error.message : String(error));
    }
  }

  if (activeView === 'clipboard') {
    return (
      <main className="palette-shell">
        <input ref={inputRef} className="palette-search" value={query} onChange={(event) => setQuery(event.target.value)} onKeyDown={onKeyDown} placeholder="Search clipboard history" aria-label="Search clipboard history" />
        {clipboardPolicy && bridge.setClipboardPolicy && <button className="palette-policy" onClick={() => void toggleClipboardCapture()}>{clipboardPolicy.enabled ? 'Pause capture' : 'Resume capture'}</button>}
        <section className="palette-results" aria-live="polite">
          {clipboardItems.map((item, index) => <button key={item.id} className={`palette-row${index === selected ? ' selected' : ''}`} onClick={() => void copyClipboard(item)}><span><strong>{item.content.slice(0, 120) || '(empty)'}</strong><small>{item.kind}{item.pinned ? ' · pinned' : ''}</small></span></button>)}
          {!clipboardItems.length && <p className="palette-empty">No clipboard items</p>}
        </section>
        {feedback && <p className="palette-feedback" role="status">{feedback}</p>}
      </main>
    );
  }

  if (activeView === 'history') {
    return (
      <main className="palette-shell">
        <input ref={inputRef} className="palette-search" value={query} onChange={(event) => setQuery(event.target.value)} onKeyDown={onKeyDown} placeholder="Recent command runs" aria-label="Recent command runs" />
        <section className="palette-results" aria-live="polite">
          {historyEntries.filter((entry) => !query || entry.commandId.toLocaleLowerCase().includes(query.toLocaleLowerCase())).map((entry, index) => (
            <div key={entry.id} className={`palette-row palette-history${index === selected ? ' selected' : ''}`}>
              <span><strong>{entry.commandId}</strong><small>{entry.result.output || entry.result.message || new Date(entry.finishedAt).toLocaleString()}</small></span>
              <kbd className={entry.result.status}>{entry.result.status}</kbd>
            </div>
          ))}
          {!historyEntries.length && <p className="palette-empty">No command runs yet</p>}
        </section>
      </main>
    );
  }

  return (
    <main className="palette-shell">
      <input
        ref={inputRef}
        className="palette-search"
        value={query}
        onChange={(event) => setQuery(event.target.value)}
        onKeyDown={onKeyDown}
        placeholder="Search apps, files, and commands"
        aria-label="Search apps, files, and commands"
      />
      <section className="palette-results" aria-live="polite">
        {commands.map((command, index) => (
          <button key={command.id} className={`palette-row${index === selected ? ' selected' : ''}`} onClick={() => void execute(command)}>
            <span><strong>{command.title}</strong>{command.subtitle && <small>{command.subtitle}</small>}</span>
            <kbd>{command.mode === 'silent' ? 'silent' : 'open'}</kbd>
          </button>
        ))}
        {!commands.length && <p className="palette-empty">No matching commands</p>}
      </section>
      {feedback && <p className="palette-feedback" role="status">{feedback}</p>}
    </main>
  );
}

// Keep the first UI slice independently previewable before a host bridge exists.
export function createPreviewBridge(commands: CommandSummary[]): PaletteBridge {
  const registry = new CommandRegistry();
  for (const command of commands) registry.register({ ...command, run: async () => ({ status: 'success', output: `${command.title} executed` }) });
  return {
    searchCommands: async (query) => registry.summaries(query),
    executeCommand: async (id) => registry.execute(id, { platform: 'macos', invocation: 'visible', signal: new AbortController().signal }),
  };
}
