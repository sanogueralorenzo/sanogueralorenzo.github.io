import type { ClipboardItem, ClipboardPolicy, ClipboardStore } from './contracts.ts';

const sensitivePattern = /(?:password|passwd|secret|token|api[_ -]?key)\s*[:=]\s*\S+/i;

/** Conservative local classifier for obvious credential-shaped clipboard text. */
export function looksSensitive(content: string): boolean {
  return sensitivePattern.test(content) || /^eyJ[a-zA-Z0-9_-]+\.[a-zA-Z0-9_-]+\.[a-zA-Z0-9_-]+$/.test(content.trim());
}

export function shouldCapture(
  item: Pick<ClipboardItem, 'sourceAppId'> & { sensitive?: boolean; content?: string },
  policy: ClipboardPolicy,
): boolean {
  if (!policy.enabled) return false;
  if (item.sourceAppId && policy.excludedAppIds.includes(item.sourceAppId)) return false;
  if (policy.ignoreSensitive && (item.sensitive || (item.content !== undefined && looksSensitive(item.content)))) return false;
  return true;
}

/** Policy wrapper that keeps retention and capacity rules out of platform code. */
export class PolicyClipboardHistory {
  private readonly store: ClipboardStore;
  private policy: ClipboardPolicy;
  private readonly now: () => number;

  constructor(
    store: ClipboardStore,
    policy: ClipboardPolicy,
    now: () => number = Date.now,
  ) {
    this.store = store;
    this.policy = policy;
    this.now = now;
  }

  setPolicy(policy: ClipboardPolicy): void {
    this.policy = policy;
  }

  async capture(item: ClipboardItem & { sensitive?: boolean }): Promise<boolean> {
    if (!shouldCapture(item, this.policy)) return false;
    const { sensitive: _sensitive, ...stored } = item;
    const captured = await this.store.add(stored);
    await this.prune();
    return captured;
  }

  async list(query?: string): Promise<ClipboardItem[]> {
    await this.prune();
    return this.store.list(query);
  }

  remove(id: string): Promise<boolean> { return this.store.remove(id); }

  async setPinned(id: string, pinned: boolean): Promise<ClipboardItem | null> {
    const item = await this.store.setPinned(id, pinned);
    await this.prune();
    return item;
  }

  private async prune(): Promise<void> {
    const items = await this.store.list();
    const cutoff = this.policy.retentionDays === null
      ? null
      : this.now() - this.policy.retentionDays * 86_400_000;

    const expired = cutoff === null
      ? []
      : items.filter((item) => !item.pinned && item.createdAt < cutoff);
    const expiredIds = new Set(expired.map((item) => item.id));
    const remaining = items.filter((item) => !expiredIds.has(item.id));
    const allowedUnpinned = Math.max(0, this.policy.maxItems - remaining.filter((item) => item.pinned).length);
    const overflow = remaining.filter((item) => !item.pinned).slice(allowedUnpinned);
    const removed = [...expired, ...overflow].map((item) => item.id);
    if (!removed.length) return;
    if (this.store.removeMany) await this.store.removeMany(removed);
    else for (const id of removed) await this.store.remove(id);
  }
}
