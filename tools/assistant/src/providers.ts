import { randomUUID } from "node:crypto";
import { existsSync, mkdirSync, readFileSync, renameSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import type { AuthEvent, AuthPrompt, AuthType, Models } from "@earendil-works/pi-ai";
import { ModelRuntime } from "@earendil-works/pi-coding-agent";
import type { ModelRef } from "@earendil-works/pi-durable";

export const defaultModel: ModelRef = { provider: "openai-codex", modelId: "gpt-6-luna" };
const preferredModels: Record<string, string> = { "openai-codex": defaultModel.modelId, anthropic: "claude-sonnet-5-5" };
// These providers include cloud account, endpoint, or credential-chain setup.
const cloudProviders = new Set(["amazon-bedrock", "azure", "google-vertex", "cloudflare-ai-gateway", "cloudflare-workers-ai"]);

export async function assistantModels(dataDir = join(homedir(), ".assistant")): Promise<Models> {
  mkdirSync(dataDir, { recursive: true, mode: 0o700 });
  return ModelRuntime.create({ authPath: join(dataDir, "auth.json"), modelsPath: null });
}

type LoginPrompt = { id: string; type: AuthPrompt["type"]; message: string; placeholder?: string;
  options?: readonly { id: string; label: string; description?: string }[] };
type Login = { id: string; provider: string; status: "pending" | "done" | "failed" | "cancelled";
  message?: string; url?: string; userCode?: string; prompt?: LoginPrompt };
type ProviderInfo = { id: string; name: string; cloud: boolean; defaultModel: string;
  methods: { id: AuthType; label: string }[]; models: { id: string; name: string }[] };
export type ProviderSnapshot = { selected: ModelRef; providers: (ProviderInfo & { connected: boolean; canLogout: boolean })[]; login?: Login };

export class Providers {
  readonly models: Models;
  private selected: ModelRef;
  private readonly path: string;
  private login?: Login;
  private controller?: AbortController;
  private pending?: { id: string; resolve: (value: string) => void };
  private running?: Promise<void>;
  private readonly listeners = new Set<() => void>();
  constructor(dataDir: string, models: Models) {
    mkdirSync(dataDir, { recursive: true, mode: 0o700 });
    this.models = models;
    this.path = join(dataDir, "provider.json");
    this.selected = existsSync(this.path) ? JSON.parse(readFileSync(this.path, "utf8")) as ModelRef : { ...defaultModel };
    if (existsSync(this.path)) this.validate(this.selected.provider, this.selected.modelId);
  }
  get model(): ModelRef { return { ...this.selected }; }
  subscribe(listener: () => void) { this.listeners.add(listener); return () => this.listeners.delete(listener); }
  private changed() { for (const listener of this.listeners) listener(); }
  private catalog(): ProviderInfo[] {
    return this.models.getProviders().flatMap(provider => {
      const catalog = this.models.getModels(provider.id);
      if (!catalog.length) return [];
      const cloud = cloudProviders.has(provider.id);
      const methods: ProviderInfo["methods"] = [];
      if (provider.auth.oauth?.login) methods.push({ id: "oauth", label: "Sign in" });
      if (provider.auth.apiKey?.login) methods.push({ id: "api_key", label: cloud ? "Cloud setup" : "API key" });
      return [{ id: provider.id, name: provider.name, cloud, methods,
        defaultModel: catalog.find(model => model.id === preferredModels[provider.id])?.id || catalog[0].id,
        models: catalog.map(model => ({ id: model.id, name: model.name })).sort((a, b) => a.name.localeCompare(b.name)) }];
    }).sort((a, b) => a.name.localeCompare(b.name));
  }
  private definition(provider: string) {
    const definition = this.catalog().find(item => item.id === provider);
    if (!definition) throw new Error("Choose a provider with chat models from the list");
    return definition;
  }
  private validate(provider: string, modelId: string) {
    this.definition(provider);
    if (!this.models.getModel(provider, modelId)) throw new Error("Choose a model from this provider's list");
  }
  async snapshot(): Promise<ProviderSnapshot> {
    const providers = await Promise.all(this.catalog().map(async definition => {
      const auth = await this.models.checkAuth(definition.id).catch(() => undefined);
      return { ...definition, connected: !!auth, canLogout: auth?.type === "oauth" || auth?.source === "stored credential" };
    }));
    return { selected: this.model, providers, ...(this.login && { login: structuredClone(this.login) }) };
  }
  async select(provider: string, modelId?: string) {
    const definition = this.definition(provider);
    const id = modelId || (this.selected.provider === provider ? this.selected.modelId : definition.defaultModel);
    this.validate(provider, id);
    if (!await this.models.checkAuth(provider)) throw new Error(`Connect ${definition.name} first`);
    const selected = { provider, modelId: id };
    const temporary = `${this.path}.${randomUUID()}.tmp`;
    writeFileSync(temporary, JSON.stringify(selected), { mode: 0o600 });
    renameSync(temporary, this.path);
    this.selected = selected;
    this.changed();
  }
  startLogin(provider: string, method: string) {
    const definition = this.definition(provider);
    if (!definition.methods.length) throw new Error("Configure this provider's credentials in the service environment");
    if (!definition.methods.some(item => item.id === method)) throw new Error("Choose a supported login method");
    if (this.login?.status === "pending") throw new Error("Finish or cancel the current sign-in first");
    const controller = new AbortController();
    this.controller = controller;
    const signal = AbortSignal.any([controller.signal, AbortSignal.timeout(10 * 60_000)]);
    const login: Login = { id: randomUUID(), provider, status: "pending", message: "Connecting…" };
    this.login = login;
    this.changed();
    this.running = (async () => {
      try {
        await this.models.login(provider, method as AuthType, {
          signal,
          notify: event => this.notify(login, event),
          prompt: prompt => this.ask(login, prompt, signal),
        }, { agentName: "assistant" });
        await this.models.refresh({ providers: [provider], allowNetwork: true, signal });
        signal.throwIfAborted();
        await this.select(provider);
        login.status = "done";
        login.message = "Connected";
      } catch {
        login.status = controller.signal.aborted ? "cancelled" : "failed";
        login.message = login.status === "cancelled" ? "Connection cancelled" : "Connection failed or timed out. Please try again.";
      } finally {
        delete login.prompt;
        delete login.url;
        delete login.userCode;
        this.pending = undefined;
        this.changed();
      }
    })();
    return login.id;
  }
  private notify(login: Login, event: AuthEvent) {
    if (event.type === "auth_url") {
      const url = new URL(event.url);
      if (url.protocol !== "https:" && url.protocol !== "http:") throw new Error("Unsupported sign-in URL");
      login.url = url.href;
      login.message = event.instructions || "Continue in your browser";
    } else if (event.type === "device_code") {
      login.url = event.verificationUri;
      login.userCode = event.userCode;
    } else login.message = event.message;
    this.changed();
  }
  private ask(login: Login, prompt: AuthPrompt, loginSignal: AbortSignal): Promise<string> {
    const signal = prompt.signal ? AbortSignal.any([loginSignal, prompt.signal]) : loginSignal;
    signal.throwIfAborted();
    const id = randomUUID();
    return new Promise((resolve, reject) => {
      const cleanup = () => {
        signal.removeEventListener("abort", abort);
        if (login.prompt?.id === id) delete login.prompt;
        if (this.pending?.id === id) this.pending = undefined;
      };
      const abort = () => { cleanup(); this.changed(); reject(signal.reason); };
      signal.addEventListener("abort", abort, { once: true });
      login.prompt = { id, type: prompt.type, message: prompt.message,
        ...("placeholder" in prompt && { placeholder: prompt.placeholder }),
        ...(prompt.type === "select" && { options: prompt.options }) };
      this.pending = { id, resolve: value => { cleanup(); resolve(value); } };
      this.changed();
    });
  }
  respond(loginId: string, promptId: string, value: string) {
    const prompt = this.login?.prompt;
    if (this.login?.id !== loginId || this.login.status !== "pending" || !prompt ||
      prompt.id !== promptId || this.pending?.id !== promptId) throw new Error("This sign-in step has ended. Refresh and try again.");
    if ((prompt.type !== "text" && !value.trim()) || value.length > 16_000) throw new Error("Enter a valid sign-in response");
    if (prompt.type === "select" && !prompt.options?.some(option => option.id === value)) throw new Error("Choose one of the listed sign-in methods");
    this.pending.resolve(value.trim());
    this.changed();
  }
  async cancelLogin(loginId: string) {
    if (this.login?.id !== loginId || this.login.status !== "pending") throw new Error("No matching sign-in is in progress");
    this.controller?.abort();
    await this.running;
  }
  async logout(provider: string) {
    this.definition(provider);
    if (this.login?.status === "pending" && this.login.provider === provider) await this.cancelLogin(this.login.id);
    await this.models.logout(provider);
    this.changed();
  }
  async close() { this.controller?.abort(); await this.running; }
}
