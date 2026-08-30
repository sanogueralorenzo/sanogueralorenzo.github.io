import { mkdir, readFile, rename, writeFile } from 'node:fs/promises';
import { dirname } from 'node:path';
import type { RunHistoryEntry, RunHistoryStore } from './contracts.ts';

export async function writeAtomically(path: string, value: string): Promise<void> {
  await mkdir(dirname(path), { recursive: true });
  const tempPath = `${path}.${process.pid}.tmp`;
  await writeFile(tempPath, value, 'utf8');
  await rename(tempPath, path);
}

export class JsonRunHistoryStore implements RunHistoryStore {
  private entries: RunHistoryEntry[] | null = null;
  private readonly path: string;
  private readonly maxEntries: number;

  constructor(path: string, maxEntries = 200) {
    this.path = path;
    this.maxEntries = maxEntries;
  }

  async append(entry: RunHistoryEntry): Promise<void> {
    const entries = await this.load();
    entries.unshift(entry);
    entries.splice(this.maxEntries);
    await writeAtomically(this.path, JSON.stringify(entries));
    this.entries = entries;
  }

  async list(limit = this.maxEntries): Promise<RunHistoryEntry[]> {
    return (await this.load()).slice(0, Math.max(0, limit));
  }

  private async load(): Promise<RunHistoryEntry[]> {
    if (this.entries) return this.entries;
    try {
      const parsed = JSON.parse(await readFile(this.path, 'utf8'));
      this.entries = Array.isArray(parsed) ? parsed : [];
    } catch {
      this.entries = [];
    }
    return this.entries;
  }
}
