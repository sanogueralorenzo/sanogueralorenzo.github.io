import { readFile } from 'node:fs/promises';
import type { ClipboardPolicy } from './contracts.ts';
import { writeAtomically } from './file-stores.ts';

export type PaletteSettings = { clipboard: ClipboardPolicy };

const defaultSettings: PaletteSettings = {
  clipboard: { enabled: true, maxItems: 200, retentionDays: 30, excludedAppIds: [], ignoreSensitive: true },
};

export class JsonSettingsStore {
  private readonly path: string;

  constructor(path: string) {
    this.path = path;
  }

  async load(): Promise<PaletteSettings> {
    try {
      const parsed = JSON.parse(await readFile(this.path, 'utf8')) as Partial<PaletteSettings>;
      const clipboard = parsed.clipboard;
      if (!clipboard || typeof clipboard !== 'object') return structuredClone(defaultSettings);
      return {
        clipboard: {
          ...defaultSettings.clipboard,
          ...clipboard,
          excludedAppIds: Array.isArray(clipboard.excludedAppIds) ? clipboard.excludedAppIds.filter((id): id is string => typeof id === 'string') : [],
        },
      };
    } catch {
      return structuredClone(defaultSettings);
    }
  }

  async save(settings: PaletteSettings): Promise<void> {
    await writeAtomically(this.path, JSON.stringify(settings));
  }
}
