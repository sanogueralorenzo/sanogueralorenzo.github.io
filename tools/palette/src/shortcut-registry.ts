import type { Shortcut } from './contracts.ts';

function keyFor(shortcut: Shortcut): string {
  return shortcut.kind === 'accelerator'
    ? `accelerator:${shortcut.value.trim().toLocaleLowerCase()}`
    : `chord:${shortcut.steps.map((step) => step.trim().toLocaleLowerCase()).join('>')}`;
}

/** Keeps shortcut ownership and conflict rules independent from native APIs. */
export class ShortcutRegistry {
  private readonly bindings = new Map<string, { commandId: string; shortcut: Shortcut }>();

  register(commandId: string, shortcut: Shortcut): void {
    if (!commandId.trim()) throw new Error('Command id is required');
    if (shortcut.kind === 'chord' && shortcut.steps.length < 2) {
      throw new Error('A chord requires at least two steps');
    }
    const key = keyFor(shortcut);
    const existing = this.bindings.get(key);
    if (existing && existing.commandId !== commandId) {
      throw new Error(`Shortcut already assigned to ${existing.commandId}`);
    }
    this.bindings.set(key, { commandId, shortcut });
  }

  unregister(commandId: string): void {
    for (const [key, binding] of this.bindings) {
      if (binding.commandId === commandId) this.bindings.delete(key);
    }
  }

  find(shortcut: Shortcut): string | undefined {
    return this.bindings.get(keyFor(shortcut))?.commandId;
  }

  list(): Array<{ commandId: string; shortcut: Shortcut }> {
    return [...this.bindings.values()];
  }
}
