import { createCipheriv, createDecipheriv, createHash, randomBytes } from 'node:crypto';
import { mkdir, readFile, rename, writeFile } from 'node:fs/promises';
import { dirname } from 'node:path';
import type { ClipboardItem, ClipboardStore } from './contracts.ts';

type Envelope = { version: 1; iv: string; authTag: string; ciphertext: string };

/**
 * Encrypted-at-rest clipboard storage. The platform host must supply a 32-byte
 * key from Keychain, DPAPI, libsecret, or another OS credential store.
 */
export class EncryptedJsonClipboardStore implements ClipboardStore {
  private items: ClipboardItem[] | null = null;
  private readonly path: string;
  private readonly key: Buffer;
  private readonly fingerprints = new WeakMap<ClipboardItem, string>();
  private readonly sizes = new WeakMap<ClipboardItem, number>();

  constructor(path: string, key: Buffer) {
    this.path = path;
    this.key = key;
    if (key.length !== 32) throw new Error('Clipboard encryption key must be 32 bytes');
  }

  async list(query?: string): Promise<ClipboardItem[]> {
    const items = await this.load();
    if (!query?.trim()) return [...items];
    const needle = query.toLocaleLowerCase();
    return items.filter((item) => [item.content, item.title, item.sourceAppName, item.sourceAppId].some((value) => value?.toLocaleLowerCase().includes(needle)));
  }

  async add(item: ClipboardItem): Promise<boolean> {
    const items = await this.load();
    // Identical copies from different apps belong to their respective app histories.
    const identity = this.fingerprint(item);
    const existing = items.find((candidate) => candidate.sourceAppId === item.sourceAppId && this.fingerprint(candidate) === identity);
    const next = [{ ...item, id: existing?.id ?? item.id, pinned: existing?.pinned ?? item.pinned },
      ...items.filter((candidate) => candidate.id !== existing?.id)];
    // Bound encrypted JSON writes, including binary formats. Never evict a pin.
    let bytes = 2 + Math.max(0, next.length - 1) + next.reduce((total, clip) => total + this.serializedSize(clip), 0);
    for (let index = next.length - 1; bytes > 64 * 1024 * 1024 && index >= 0; index--) {
      if (next[index].pinned) continue;
      bytes -= this.serializedSize(next[index]) + (next.length > 1 ? 1 : 0);
      next.splice(index, 1);
    }
    if (bytes > 64 * 1024 * 1024) throw new Error('Pinned history is full. Unpin or delete a clip to make space.');
    if (!next.some((clip) => clip.id === (existing?.id ?? item.id))) throw new Error('History is full of pinned clips. Unpin or delete a clip to make space.');
    await this.save(next);
    return true;
  }

  async remove(id: string): Promise<boolean> {
    const items = await this.load();
    const before = items.length;
    const next = items.filter((item) => item.id !== id);
    if (next.length === before) return false;
    await this.save(next);
    return true;
  }

  async removeMany(ids: string[]): Promise<void> {
    const removed = new Set(ids);
    await this.save((await this.load()).filter((item) => !removed.has(item.id)));
  }

  async setPinned(id: string, pinned: boolean): Promise<ClipboardItem | null> {
    const items = await this.load();
    const item = items.find((candidate) => candidate.id === id);
    if (!item) return null;
    const updated = { ...item, pinned };
    await this.save(items.map((candidate) => candidate.id === id ? updated : candidate));
    return updated;
  }

  async clear(): Promise<void> {
    await this.save([]);
  }

  private fingerprint(item: ClipboardItem): string {
    let value = this.fingerprints.get(item);
    if (!value) {
      value = createHash('sha256').update(JSON.stringify([item.kind, item.content, item.representations ?? null])).digest('hex');
      this.fingerprints.set(item, value);
    }
    return value;
  }

  private serializedSize(item: ClipboardItem): number {
    let value = this.sizes.get(item);
    if (value === undefined) { value = Buffer.byteLength(JSON.stringify(item)); this.sizes.set(item, value); }
    return value;
  }

  private async load(): Promise<ClipboardItem[]> {
    if (this.items) return this.items;
    try {
      const envelope = JSON.parse(await readFile(this.path, 'utf8')) as Envelope;
      if (envelope?.version !== 1) throw new Error('Unsupported clipboard envelope');
      const decipher = createDecipheriv('aes-256-gcm', this.key, Buffer.from(envelope.iv, 'base64'));
      decipher.setAuthTag(Buffer.from(envelope.authTag, 'base64'));
      this.items = JSON.parse(Buffer.concat([decipher.update(Buffer.from(envelope.ciphertext, 'base64')), decipher.final()]).toString('utf8'));
      if (!Array.isArray(this.items)) { this.items = null; throw new Error('Invalid clipboard storage'); }
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code !== 'ENOENT') throw new Error('Clipboard history could not be decrypted. Existing data has been preserved.');
      this.items = [];
    }
    return this.items;
  }

  private async save(items: ClipboardItem[]): Promise<void> {
    const iv = randomBytes(12);
    const cipher = createCipheriv('aes-256-gcm', this.key, iv);
    const ciphertext = Buffer.concat([cipher.update(JSON.stringify(items), 'utf8'), cipher.final()]);
    const envelope: Envelope = {
      version: 1,
      iv: iv.toString('base64'),
      authTag: cipher.getAuthTag().toString('base64'),
      ciphertext: ciphertext.toString('base64'),
    };
    await mkdir(dirname(this.path), { recursive: true });
    const tempPath = `${this.path}.${process.pid}.tmp`;
    await writeFile(tempPath, JSON.stringify(envelope), { encoding: 'utf8', mode: 0o600 });
    await rename(tempPath, this.path);
    this.items = items;
  }
}
