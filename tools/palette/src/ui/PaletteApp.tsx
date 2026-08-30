import { useEffect, useRef, useState, type KeyboardEvent } from 'react';
import type { CommandResult, CommandSummary } from '../contracts.ts';
import { CommandRegistry } from '../command-registry.ts';

export type PaletteBridge = {
  searchCommands(query: string): Promise<CommandSummary[]>;
  executeCommand(id: string): Promise<CommandResult>;
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
  const inputRef = useRef<HTMLInputElement>(null);

  useEffect(() => { void bridge.searchCommands(query).then(setCommands); }, [bridge, query]);
  useEffect(() => { setSelected(0); }, [query, commands.length]);
  useEffect(() => { inputRef.current?.focus(); }, []);

  async function execute(command: CommandSummary | undefined): Promise<void> {
    if (!command) return;
    const result = await bridge.executeCommand(command.id);
    setFeedback(result.status === 'success' ? (result.output || 'Done') : (result.message || 'Action failed'));
  }

  function onKeyDown(event: KeyboardEvent<HTMLInputElement>): void {
    if (event.key === 'ArrowDown') { event.preventDefault(); setSelected((value) => Math.min(value + 1, commands.length - 1)); }
    if (event.key === 'ArrowUp') { event.preventDefault(); setSelected((value) => Math.max(value - 1, 0)); }
    if (event.key === 'Enter') { event.preventDefault(); void execute(commands[selected]); }
    if (event.key === 'Escape') { window.close(); }
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
