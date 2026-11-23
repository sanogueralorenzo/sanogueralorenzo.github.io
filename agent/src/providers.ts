import { randomUUID } from "node:crypto";
import { mkdirSync, readFileSync, renameSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import type { ModelThinkingLevel } from "@earendil-works/pi-ai";
import type { ModelRef } from "@earendil-works/pi-durable";
import { cliConnection, cliProvider, cliProviders, defaultModel, fastSupported } from "./cli/catalog.ts";

export function utilityAgent(selected: ModelRef): { model: ModelRef; thinkingLevel: ModelThinkingLevel } {
  const provider = cliProvider(selected.provider);
  return { model: provider ? { provider: provider.id, modelId: provider.utilityModel } : selected,
    thinkingLevel: selected.provider === "openai" ? "off" : "low" };
}

function readSettings<T>(path: string, fallback: T): T {
  try { return JSON.parse(readFileSync(path, "utf8")); }
  catch (error) {
    if ((error as NodeJS.ErrnoException).code !== "ENOENT") throw error;
    return fallback;
  }
}

function writeSettings(path: string, value: unknown) {
  const temporary = `${path}.${randomUUID()}.tmp`;
  writeFileSync(temporary, JSON.stringify(value), { mode: 0o600 });
  renameSync(temporary, path);
}

type CliStatus = Awaited<ReturnType<typeof cliConnection>>;
const offline: CliStatus = { installed: false, connected: false };

export class Providers {
  private selected: ModelRef;
  private readonly path: string;
  private readonly fastPath: string;
  private fast: Record<string, boolean>;
  private readonly probe: typeof cliConnection;
  private readonly controller = new AbortController();
  private readonly listeners = new Set<() => void>();
  private statuses = new Map<string, CliStatus>();
  private checking?: Promise<void>;
  private checkedAt = 0;
  private timer?: NodeJS.Timeout;

  constructor(dataDir: string, probe = cliConnection) {
    mkdirSync(dataDir, { recursive: true, mode: 0o700 });
    this.probe = probe;
    this.path = join(dataDir, "provider.json");
    this.fastPath = join(dataDir, "fast-mode.json");
    this.selected = readSettings(this.path, defaultModel);
    this.fast = readSettings(this.fastPath, {});
  }

  get model(): ModelRef {
    if (this.usable(this.selected)) return { ...this.selected };
    const provider = cliProviders.find(item => this.statuses.get(item.id)?.connected);
    return provider ? { provider: provider.id, modelId: provider.defaultModel } : { ...defaultModel };
  }

  usable(ref: ModelRef) {
    return this.statuses.get(ref.provider)?.connected === true &&
      cliProvider(ref.provider)?.models.some(([id]) => id === ref.modelId) === true;
  }

  fastEnabled(provider: string) { return this.fast[provider] === true; }

  private changed() { for (const listener of this.listeners) listener(); }

  refresh() {
    if (Date.now() - this.checkedAt < 5000 || this.controller.signal.aborted) return Promise.resolve();
    return this.checking ||= Promise.all(cliProviders.map(async provider =>
      [provider.id, await this.probe(provider, this.controller.signal)] as const)).then(entries => {
      this.checkedAt = Date.now();
      const different = entries.some(([id, status]) => {
        const old = this.statuses.get(id);
        return old?.connected !== status.connected || old?.installed !== status.installed;
      });
      this.statuses = new Map(entries);
      if (different && !this.controller.signal.aborted) this.changed();
    }).finally(() => { this.checking = undefined; });
  }

  subscribe(listener: () => void) {
    this.listeners.add(listener);
    this.timer ||= setInterval(() => { void this.refresh().catch(() => {}); }, 15_000).unref();
    return () => {
      this.listeners.delete(listener);
      if (!this.listeners.size) { clearInterval(this.timer); this.timer = undefined; }
    };
  }

  async snapshot() {
    await this.refresh();
    return { selected: this.model, providers: cliProviders.map(provider => ({
      id: provider.id, name: provider.name, loginCommand: provider.login,
      ...(this.statuses.get(provider.id) ?? offline),
      fastSupported: provider.models.some(([id]) => fastSupported(provider.id, id)),
      fastEnabled: this.fastEnabled(provider.id),
      models: provider.models.map(([id, name]) => ({ id, name })),
    })) };
  }

  async select(providerId: string, modelId?: string) {
    const provider = cliProvider(providerId);
    if (!provider) throw new Error("Choose a provider from the list");
    const model = { provider: provider.id, modelId: modelId || provider.defaultModel };
    if (!provider.models.some(([id]) => id === model.modelId)) throw new Error("Choose a model from this provider's list");
    await this.refresh();
    if (!this.usable(model)) throw new Error(`Sign in to ${provider.name} on the Agent host`);
    writeSettings(this.path, model);
    this.selected = model;
    this.changed();
  }

  async setFastMode(providerId: string, enabled: boolean) {
    const provider = cliProvider(providerId);
    if (!provider?.models.some(([id]) => fastSupported(providerId, id))) throw new Error("This CLI does not support fast mode");
    await this.refresh();
    if (!this.statuses.get(provider.id)?.connected) throw new Error(`Sign in to ${provider.name} on the Agent host`);
    const fast = { ...this.fast, [providerId]: enabled };
    writeSettings(this.fastPath, fast);
    this.fast = fast;
    this.changed();
  }

  async close() {
    this.controller.abort();
    clearInterval(this.timer);
    await this.checking;
  }
}
