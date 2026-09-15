import { mkdir, readFile, rename, writeFile } from "node:fs/promises";
import { dirname } from "node:path";
import process from "node:process";

export type TopicBinding = {
  threadId: string;
  title: string;
  cwd: string;
};

type BindingMap = Record<string, TopicBinding>;

export function topicKey(chatId: string, topicId: number): string {
  return chatId + ":" + topicId;
}

export class TopicStore {
  private writeQueue: Promise<void> = Promise.resolve();

  constructor(private readonly filePath: string) {}

  async get(chatId: string, topicId: number): Promise<TopicBinding | null> {
    const bindings = await this.readAll();
    return bindings[topicKey(chatId, topicId)] ?? null;
  }

  async set(chatId: string, topicId: number, binding: TopicBinding): Promise<void> {
    await this.enqueueWrite(async () => {
      const bindings = await this.readAll();
      bindings[topicKey(chatId, topicId)] = binding;
      await this.writeAll(bindings);
    });
  }

  async remove(chatId: string, topicId: number): Promise<boolean> {
    return this.enqueueWrite(async () => {
      const bindings = await this.readAll();
      const key = topicKey(chatId, topicId);
      if (!bindings[key]) {
        return false;
      }
      delete bindings[key];
      await this.writeAll(bindings);
      return true;
    });
  }

  private async readAll(): Promise<BindingMap> {
    await this.ensureFile();
    const raw = await readFile(this.filePath, "utf8");

    try {
      const parsed = JSON.parse(raw) as unknown;
      if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
        return {};
      }

      const out: BindingMap = {};
      for (const [key, value] of Object.entries(parsed)) {
        if (!value || typeof value !== "object" || Array.isArray(value)) {
          continue;
        }
        const binding = value as Record<string, unknown>;
        if (
          typeof binding.threadId === "string" &&
          typeof binding.title === "string" &&
          typeof binding.cwd === "string"
        ) {
          out[key] = {
            threadId: binding.threadId,
            title: binding.title,
            cwd: binding.cwd,
          };
        }
      }
      return out;
    } catch {
      return {};
    }
  }

  private async writeAll(bindings: BindingMap): Promise<void> {
    await this.ensureFile();
    const tmpPath = this.filePath + "." + process.pid + "." + Date.now() + ".tmp";
    await writeFile(tmpPath, JSON.stringify(bindings, null, 2) + "\n", "utf8");
    await rename(tmpPath, this.filePath);
  }

  private async ensureFile(): Promise<void> {
    const dir = dirname(this.filePath);
    await mkdir(dir, { recursive: true });

    try {
      await readFile(this.filePath, "utf8");
    } catch {
      await writeFile(this.filePath, "{}\n", "utf8");
    }
  }

  private enqueueWrite<T>(work: () => Promise<T>): Promise<T> {
    const next = this.writeQueue.then(work, work);
    this.writeQueue = next.then(
      () => undefined,
      () => undefined
    );
    return next;
  }
}
