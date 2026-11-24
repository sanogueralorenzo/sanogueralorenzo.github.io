import { randomUUID } from "node:crypto";
import { mkdirSync, readFileSync, renameSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import type { ModelThinkingLevel } from "@earendil-works/pi-ai";
import type { ModelRef } from "@earendil-works/pi-durable";
import { cliConnection, cliProvider, cliProviders, defaultModel, fastSupported, type CliProvider } from "./cli/catalog.ts";

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
  private readonly statuses = new Map<string, { status: CliStatus; checkedAt: number }>();
  private readonly checking = new Map<string, Promise<void>>();
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
    return this.connectedModel() ?? { ...defaultModel };
  }

  connectedModel(preferred?: ModelRef): ModelRef | undefined {
    if (preferred && this.usable(preferred)) return preferred;
    if (this.usable(this.selected)) return { ...this.selected };
    const provider = cliProviders.find(item => this.statuses.get(item.id)?.status.connected);
    if (provider) return { provider: provider.id, modelId: provider.defaultModel };
  }

  private usable(ref: ModelRef) {
    return this.statuses.get(ref.provider)?.status.connected === true &&
      cliProvider(ref.provider)?.models.some(([id]) => id === ref.modelId) === true;
  }

  fastEnabled(provider: string) { return this.fast[provider] === true; }

  private changed() { for (const listener of this.listeners) listener(); }

  private refreshProvider(provider: CliProvider, force = false) {
    const pending = this.checking.get(provider.id);
    if (pending) return pending;
    const previous = this.statuses.get(provider.id);
    if (this.controller.signal.aborted || (!force && previous && Date.now() - previous.checkedAt < 5000)) return Promise.resolve();
    const checking = this.probe(provider, this.controller.signal).then(status => {
      if (this.controller.signal.aborted) return;
      this.statuses.set(provider.id, { status, checkedAt: Date.now() });
      if (previous?.status.connected !== status.connected || previous?.status.installed !== status.installed) this.changed();
    }).finally(() => { this.checking.delete(provider.id); });
    this.checking.set(provider.id, checking);
    return checking;
  }

  async refresh() {
    await Promise.all(cliProviders.map(provider => this.refreshProvider(provider)));
  }

  recheck(provider: CliProvider) {
    void this.refreshProvider(provider, true).catch(() => {});
  }

  startPolling() {
    this.timer ||= setInterval(() => { void this.refresh().catch(() => {}); }, 15_000).unref();
  }

  subscribe(listener: () => void) {
    this.listeners.add(listener);
    return () => { this.listeners.delete(listener); };
  }

  async snapshot() {
    await this.refresh();
    return { selected: this.model, providers: cliProviders.map(provider => ({
      id: provider.id, name: provider.name, loginCommand: provider.login,
      ...(this.statuses.get(provider.id)?.status ?? offline),
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
    await this.refreshProvider(provider);
    if (!this.usable(model)) throw new Error(`Sign in to ${provider.name} on the Agent host`);
    writeSettings(this.path, model);
    this.selected = model;
    this.changed();
  }

  async setFastMode(providerId: string, enabled: boolean) {
    const provider = cliProvider(providerId);
    if (!provider?.models.some(([id]) => fastSupported(providerId, id))) throw new Error("This CLI does not support fast mode");
    await this.refreshProvider(provider);
    if (!this.statuses.get(provider.id)?.status.connected) throw new Error(`Sign in to ${provider.name} on the Agent host`);
    const fast = { ...this.fast, [providerId]: enabled };
    writeSettings(this.fastPath, fast);
    this.fast = fast;
    this.changed();
  }

  async close() {
    this.controller.abort();
    clearInterval(this.timer);
    await Promise.allSettled(this.checking.values());
  }
}
