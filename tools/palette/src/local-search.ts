import { readdir } from 'node:fs/promises';
import { basename, extname, join } from 'node:path';
import type { CommandDefinition, CommandSummary } from './contracts.ts';

type LocalSearchOptions = {
  roots: string[];
  openPath: (path: string) => Promise<void>;
  maxEntries?: number;
};

/** Node fallback index; the production hot path can be replaced by Rust. */
export class LocalSearchProvider {
  private readonly roots: string[];
  private readonly openPath: (path: string) => Promise<void>;
  private readonly maxEntries: number;
  private indexed: CommandDefinition[] | null = null;

  constructor(options: LocalSearchOptions) {
    this.roots = options.roots;
    this.openPath = options.openPath;
    this.maxEntries = options.maxEntries ?? 10_000;
  }

  async search(query: string): Promise<CommandSummary[]> {
    if (!query.trim()) return [];
    const indexed = await this.index();
    const needle = query.trim().toLocaleLowerCase();
    return indexed
      .filter((entry) => `${entry.title} ${(entry.keywords ?? []).join(' ')}`.toLocaleLowerCase().includes(needle))
      .map(({ run: _run, ...summary }) => summary);
  }

  async definition(id: string): Promise<CommandDefinition | undefined> {
    return (await this.index()).find((entry) => entry.id === id);
  }

  private async index(): Promise<CommandDefinition[]> {
    if (this.indexed) return this.indexed;
    const results: CommandDefinition[] = [];
    for (const root of this.roots) await this.walk(root, results);
    this.indexed = results;
    return results;
  }

  private async walk(directory: string, results: CommandDefinition[]): Promise<void> {
    if (results.length >= this.maxEntries) return;
    let entries;
    try { entries = await readdir(directory, { withFileTypes: true }); } catch { return; }
    for (const entry of entries) {
      if (results.length >= this.maxEntries) return;
      if (entry.name.startsWith('.') || entry.name === 'node_modules' || entry.name === 'dist') continue;
      const path = join(directory, entry.name);
      if (entry.isDirectory() && !entry.name.endsWith('.app')) {
        await this.walk(path, results);
        continue;
      }
      const isApp = entry.name.endsWith('.app') || extname(entry.name) === '.desktop';
      results.push({
        id: `local:${isApp ? 'app' : 'file'}:${path}`,
        title: isApp ? basename(entry.name, extname(entry.name)) : entry.name,
        subtitle: path,
        keywords: [path],
        mode: 'visible',
        category: isApp ? 'app' : 'file',
        run: async () => { await this.openPath(path); return { status: 'success' }; },
      });
    }
  }
}
