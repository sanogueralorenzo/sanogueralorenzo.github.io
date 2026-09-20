import type { OpenAIModelClient } from "../openai/model.js";
import type { Store } from "../conversation/store.js";
import type { BackendKind } from "../conversation/types.js";
import type { CodexAppServer } from "../codex/app-server.js";
import type { CodexLoginMode, CodexLoginResult, CodexLoginStart } from "../codex/protocol.js";

export interface SetupStatus {
  configured: boolean;
  selectedBackend: BackendKind | null;
  openAIConfigured: boolean;
  codex: {
    installed: boolean;
    connected: boolean;
  };
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
    if (installed) {
      connected = (await this.codex.account(true)).account?.type === "chatgpt";
    }
    const stored = this.store.getSetting("backend");
    const selectedBackend = stored === "codex" || stored === "responses"
      ? stored
      : null;
    const configured = selectedBackend === "codex"
      ? connected
      : selectedBackend === "responses" ? this.responses.isConfigured() : false;
    return {
      configured,
      selectedBackend,
      openAIConfigured: this.responses.isConfigured(),
      codex: {
        installed,
        connected,
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

  async startCodexLogin(mode: CodexLoginMode): Promise<CodexLoginStart> {
    if (!this.codex.isInstalled()) throw new Error("Codex is not installed. Install the official Codex CLI, then run setup again.");
    return this.codex.beginLogin(mode);
  }

  async waitForCodexLogin(loginId: string, signal?: AbortSignal): Promise<CodexLoginResult> {
    const status = await this.codex.waitForLogin(loginId, 5 * 60_000, signal);
    if (status.state === "complete") this.store.setSetting("backend", "codex");
    return status;
  }
}
