import { createCipheriv, createDecipheriv, randomBytes } from 'node:crypto';
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

  constructor(path: string, key: Buffer) {
    this.path = path;
    this.key = key;
    if (key.length !== 32) throw new Error('Clipboard encryption key must be 32 bytes');
  }

  async list(query?: string): Promise<ClipboardItem[]> {
    const items = await this.load();
    if (!query?.trim()) return [...items];
    const needle = query.toLocaleLowerCase();
    return items.filter((item) => item.content.toLocaleLowerCase().includes(needle));
  }

  async add(item: ClipboardItem): Promise<boolean> {
    const items = await this.load();
    const existing = items.findIndex((candidate) => candidate.content === item.content && candidate.kind === item.kind);
    if (existing >= 0) items.splice(existing, 1);
    items.unshift(item);
    await this.save(items);
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

  async setPinned(id: string, pinned: boolean): Promise<ClipboardItem | null> {
    const items = await this.load();
    const item = items.find((candidate) => candidate.id === id);
    if (!item) return null;
    item.pinned = pinned;
    await this.save(items);
    return item;
  }

  async clear(): Promise<void> {
    await this.save([]);
  }

  private async load(): Promise<ClipboardItem[]> {
    if (this.items) return this.items;
    try {
      const envelope = JSON.parse(await readFile(this.path, 'utf8')) as Envelope;
      if (envelope?.version !== 1) throw new Error('Unsupported clipboard envelope');
      const decipher = createDecipheriv('aes-256-gcm', this.key, Buffer.from(envelope.iv, 'base64'));
      decipher.setAuthTag(Buffer.from(envelope.authTag, 'base64'));
      this.items = JSON.parse(Buffer.concat([decipher.update(Buffer.from(envelope.ciphertext, 'base64')), decipher.final()]).toString('utf8'));
      if (!Array.isArray(this.items)) this.items = [];
    } catch {
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
    await writeFile(tempPath, JSON.stringify(envelope), 'utf8');
    await rename(tempPath, this.path);
    this.items = items;
  }
}
