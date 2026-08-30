import type { ClipboardItem, ClipboardPolicy, ClipboardStore } from './contracts.ts';

export function shouldCapture(
  item: Pick<ClipboardItem, 'sourceAppId'> & { sensitive?: boolean },
  policy: ClipboardPolicy,
): boolean {
  if (!policy.enabled) return false;
  if (item.sourceAppId && policy.excludedAppIds.includes(item.sourceAppId)) return false;
  if (policy.ignoreSensitive && item.sensitive) return false;
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

  list(query?: string): Promise<ClipboardItem[]> {
    return this.store.list(query);
  }

  private async prune(): Promise<void> {
    const items = await this.store.list();
    const cutoff = this.policy.retentionDays === null
      ? null
      : this.now() - this.policy.retentionDays * 86_400_000;

    const expired = cutoff === null
      ? []
      : items.filter((item) => !item.pinned && item.createdAt < cutoff);
    for (const item of expired) await this.store.remove(item.id);

    const remaining = (await this.store.list())
      .filter((item) => !expired.some((removed) => removed.id === item.id));
    const allowedUnpinned = Math.max(0, this.policy.maxItems - remaining.filter((item) => item.pinned).length);
    const overflow = remaining.filter((item) => !item.pinned).slice(allowedUnpinned);
    for (const item of overflow) await this.store.remove(item.id);
  }
}
