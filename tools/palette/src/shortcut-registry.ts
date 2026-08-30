import type { Shortcut } from './contracts.ts';

function keyFor(shortcut: Shortcut): string {
  return shortcut.kind === 'accelerator'
    ? `accelerator:${shortcut.value.trim().toLocaleLowerCase()}`
    : `chord:${shortcut.steps.map((step) => step.trim().toLocaleLowerCase()).join('>')}`;
}

function normalizeStep(step: string): string {
  return step.trim().toLocaleLowerCase();
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

/** Resolves native key events into accelerator or chord command ids. */
export class ShortcutMatcher {
  private pending: string[] = [];
  private pendingAt = 0;
  private readonly registry: ShortcutRegistry;

  constructor(registry: ShortcutRegistry) {
    this.registry = registry;
  }

  press(step: string, now = Date.now()): string | undefined {
    const normalized = normalizeStep(step);
    if (!normalized) return undefined;
    const accelerator = this.registry.find({ kind: 'accelerator', value: normalized });
    if (accelerator) { this.reset(); return accelerator; }

    const previous = now - this.pendingAt;
    if (this.pending.length && previous > this.timeoutForPending()) this.reset();
    const candidate = [...this.pending, normalized];
    const exact = this.registry.find({ kind: 'chord', steps: candidate });
    if (exact) { this.reset(); return exact; }
    const isPrefix = this.registry.list().some(({ shortcut }) => shortcut.kind === 'chord'
      && shortcut.steps.length > candidate.length
      && candidate.every((part, index) => normalizeStep(shortcut.steps[index] ?? '') === part));
    this.pending = isPrefix ? candidate : [];
    this.pendingAt = isPrefix ? now : 0;
    return undefined;
  }

  reset(): void {
    this.pending = [];
    this.pendingAt = 0;
  }

  private timeoutForPending(): number {
    const first = this.pending[0];
    const binding = this.registry.list().find(({ shortcut }) => shortcut.kind === 'chord'
      && normalizeStep(shortcut.steps[0] ?? '') === first);
    return binding?.shortcut.kind === 'chord' ? binding.shortcut.timeoutMs ?? 800 : 800;
  }
}
