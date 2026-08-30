import { createInterface, type Interface } from 'node:readline';
import { spawn, type ChildProcessWithoutNullStreams } from 'node:child_process';
import type { CommandDefinition, CommandSummary } from './contracts.ts';
import type { SearchProvider } from './local-search.ts';

type RustSearchResult = Omit<CommandSummary, 'mode' | 'subtitle'> & { mode?: 'visible'; subtitle: string };

/** Client for the long-lived Rust indexer JSON-lines process. */
export class RustSearchProvider implements SearchProvider {
  private process: ChildProcessWithoutNullStreams | null = null;
  private output: Interface | null = null;
  private pending: Array<{ resolve: (results: RustSearchResult[]) => void; reject: (error: Error) => void }> = [];
  private readonly definitions = new Map<string, CommandDefinition>();
  private readonly binaryPath: string;
  private readonly roots: string[];
  private readonly openPath: (path: string) => Promise<void>;

  constructor(
    binaryPath: string,
    roots: string[],
    openPath: (path: string) => Promise<void>,
  ) {
    this.binaryPath = binaryPath;
    this.roots = roots;
    this.openPath = openPath;
  }

  async search(query: string): Promise<CommandSummary[]> {
    if (!query.trim()) return [];
    this.start();
    const results = await new Promise<RustSearchResult[]>((resolve, reject) => {
      this.pending.push({ resolve, reject });
      this.process!.stdin.write(`${JSON.stringify({ query })}\n`);
    });
    return results.map((result) => {
      const path = result.subtitle;
      const definition: CommandDefinition = {
        ...result,
        mode: 'visible',
        category: result.category === 'app' || result.category === 'file' ? result.category : 'file',
        run: async () => { await this.openPath(path); return { status: 'success' }; },
      };
      this.definitions.set(result.id, definition);
      return { ...result, mode: 'visible' };
    });
  }

  async definition(id: string): Promise<CommandDefinition | undefined> {
    return this.definitions.get(id);
  }

  close(): void {
    this.output?.close();
    this.output = null;
    this.process?.kill();
    this.process = null;
    for (const request of this.pending.splice(0)) request.reject(new Error('Rust indexer closed'));
  }

  private start(): void {
    if (this.process) return;
    const child = spawn(this.binaryPath, ['--max-entries', '100000', ...this.roots.flatMap((root) => ['--root', root])], {
      stdio: ['pipe', 'pipe', 'pipe'],
      windowsHide: true,
    });
    this.process = child;
    this.output = createInterface({ input: child.stdout, crlfDelay: Infinity });
    this.output.on('line', (line) => {
      const request = this.pending.shift();
      if (!request) return;
      try { request.resolve(JSON.parse(line) as RustSearchResult[]); }
      catch (error) { request.reject(error instanceof Error ? error : new Error(String(error))); }
    });
    child.stderr.on('data', () => {});
    const fail = (error: Error) => {
      this.process = null;
      this.output?.close();
      this.output = null;
      for (const request of this.pending.splice(0)) request.reject(error);
    };
    child.once('error', fail);
    child.once('exit', (code) => { if (code !== 0) fail(new Error(`Rust indexer exited with ${code ?? 'unknown'}`)); });
  }
}
