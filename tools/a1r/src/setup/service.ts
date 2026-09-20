import type { OpenAIModelClient } from "../core/model.js";
import type { Store } from "../core/store.js";
import type { BackendKind } from "../core/types.js";
import type { CodexAppServer } from "../codex/app-server.js";
import type { CodexLoginResult, CodexLoginStart, CodexRateLimits, RateLimitSnapshot } from "../codex/protocol.js";

export interface UsageSummary {
  name: string;
  usedPercent: number;
  remainingPercent: number;
  resetsAt: number | null;
}

export interface SetupStatus {
  configured: boolean;
  selectedBackend: BackendKind | null;
  recommendedBackend: "codex";
  openAIConfigured: boolean;
  codex: {
    installed: boolean;
    connected: boolean;
    planType: string | null;
    allowanceAvailable: boolean | null;
    usage: UsageSummary[];
    error?: string;
  };
}

function summaries(limits: CodexRateLimits): UsageSummary[] {
  const entries: Array<[string, RateLimitSnapshot]> = limits.rateLimitsByLimitId
    ? Object.entries(limits.rateLimitsByLimitId)
    : [[limits.rateLimits.limitId ?? "codex", limits.rateLimits]];
  return entries.flatMap(([id, snapshot]) => {
    if (!snapshot.primary) return [];
    return [{
      name: snapshot.limitName ?? id,
      usedPercent: snapshot.primary.usedPercent,
      remainingPercent: Math.max(0, Math.min(100, 100 - snapshot.primary.usedPercent)),
      resetsAt: snapshot.primary.resetsAt,
    }];
  });
}

export class BackendSetupService {
  constructor(
    private readonly store: Store,
    private readonly responses: OpenAIModelClient,
    private readonly codex: CodexAppServer,
    private readonly saveOpenAIKey: (key: string) => void | Promise<void>,
  ) {}

  async status(): Promise<SetupStatus> {
    const installed = this.codex.isInstalled();
    let connected = false;
    let planType: string | null = null;
    let allowanceAvailable: boolean | null = null;
    let usage: UsageSummary[] = [];
    let error: string | undefined;
    if (installed) {
      try {
        const account = await this.codex.account(true);
        connected = account.account?.type === "chatgpt";
        planType = account.account?.type === "chatgpt" ? account.account.planType ?? null : null;
        if (connected) {
          try {
            const limits = await this.codex.rateLimits();
            allowanceAvailable = limits.ordinaryUsageAllowed;
            if (allowanceAvailable === null) {
              const buckets = limits.rateLimitsByLimitId ? Object.values(limits.rateLimitsByLimitId) : [limits.rateLimits];
              allowanceAvailable = !buckets.some((bucket) => Boolean(bucket.rateLimitReachedType));
            }
            usage = summaries(limits);
          } catch {
            // Usage is optional in the documented protocol.
          }
        }
      } catch (cause) {
        error = cause instanceof Error ? cause.message : String(cause);
      }
    }
    const stored = this.store.getSetting("backend");
    const selectedBackend = stored === "codex" || stored === "responses"
      ? stored
      : this.responses.isConfigured() ? "responses" : null;
    const configured = selectedBackend === "codex"
      ? connected && allowanceAvailable !== false
      : selectedBackend === "responses" ? this.responses.isConfigured() : false;
    return {
      configured,
      selectedBackend,
      recommendedBackend: "codex",
      openAIConfigured: this.responses.isConfigured(),
      codex: {
        installed,
        connected,
        planType,
        allowanceAvailable,
        usage,
        ...(error ? { error } : {}),
      },
    };
  }

  async setOpenAIKey(key: string): Promise<void> {
    await this.responses.setApiKey(key);
    await this.saveOpenAIKey(key);
    this.store.setSetting("backend", "responses");
  }

  async selectBackend(backend: BackendKind): Promise<void> {
    if (backend === "responses") {
      if (!this.responses.isConfigured()) throw new Error("Connect an OpenAI API key before selecting API-key billing.");
    } else {
      const account = await this.codex.account(true);
      if (account.account?.type !== "chatgpt") {
        throw new Error("Continue with ChatGPT before selecting Codex subscription mode.");
      }
    }
    this.store.setSetting("backend", backend);
  }

  async startCodexLogin(mode: "browser" | "device"): Promise<CodexLoginStart> {
    if (!this.codex.isInstalled()) throw new Error("Codex is not installed. Install the official Codex CLI, or use API-key billing.");
    return this.codex.beginLogin(mode);
  }

  async codexLoginStatus(loginId: string): Promise<CodexLoginResult> {
    const status = this.codex.loginStatus(loginId);
    if (status.state === "complete") this.store.setSetting("backend", "codex");
    return status;
  }
}
