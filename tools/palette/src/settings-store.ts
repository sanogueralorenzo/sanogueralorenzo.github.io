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
      const candidate = clipboard as Partial<ClipboardPolicy>;
      const maxItems = typeof candidate.maxItems === 'number' && Number.isFinite(candidate.maxItems)
        ? Math.max(0, Math.floor(candidate.maxItems))
        : defaultSettings.clipboard.maxItems;
      const retentionDays = candidate.retentionDays === null
        ? null
        : typeof candidate.retentionDays === 'number' && Number.isFinite(candidate.retentionDays)
          ? Math.max(0, candidate.retentionDays)
          : defaultSettings.clipboard.retentionDays;
      return {
        clipboard: {
          ...defaultSettings.clipboard,
          enabled: typeof candidate.enabled === 'boolean' ? candidate.enabled : defaultSettings.clipboard.enabled,
          maxItems,
          retentionDays,
          ignoreSensitive: typeof candidate.ignoreSensitive === 'boolean' ? candidate.ignoreSensitive : defaultSettings.clipboard.ignoreSensitive,
          excludedAppIds: Array.isArray(candidate.excludedAppIds) ? candidate.excludedAppIds.filter((id): id is string => typeof id === 'string') : [],
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
