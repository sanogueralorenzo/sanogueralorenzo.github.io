import { mkdir, readFile, writeFile } from "node:fs/promises";
import { dirname } from "node:path";

type BindingMap = Record<string, string>;

export class BindingStore {
  constructor(private readonly filePath: string) {}

  async get(chatId: string): Promise<string | null> {
    const bindings = await this.readAll();
    return bindings[chatId] ?? null;
  }

  async set(chatId: string, threadId: string): Promise<void> {
    const bindings = await this.readAll();
    bindings[chatId] = threadId;
    await this.writeAll(bindings);
  }

  async remove(chatId: string): Promise<boolean> {
    const bindings = await this.readAll();
    if (!bindings[chatId]) {
      return false;
    }
    delete bindings[chatId];
    await this.writeAll(bindings);
    return true;
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
      for (const [k, v] of Object.entries(parsed)) {
        if (typeof v === "string") {
          out[k] = v;
        }
      }
      return out;
    } catch {
      return {};
    }
  }

  private async writeAll(bindings: BindingMap): Promise<void> {
    await this.ensureFile();
    await writeFile(this.filePath, `${JSON.stringify(bindings, null, 2)}\n`, "utf8");
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
}
