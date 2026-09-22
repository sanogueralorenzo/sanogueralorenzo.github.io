import type { CodexAppServer } from "../codex/app-server.js";
import type { CodexAuthMode, CodexLoginMode, CodexLoginResult, CodexLoginStart } from "../codex/protocol.js";

export interface SetupStatus {
  configured: boolean;
  authMode: CodexAuthMode | null;
  codex: {
    installed: boolean;
    connected: boolean;
  };
}

export class AgentSetupService {
  constructor(
    private readonly codex: CodexAppServer,
  ) {}

  async status(): Promise<SetupStatus> {
    const installed = this.codex.isInstalled();
    const account = installed ? (await this.codex.account(true)).account : null;
    const authMode = account?.type === "chatgpt" || account?.type === "apiKey" ? account.type : null;
    return {
      configured: authMode !== null,
      authMode,
      codex: { installed, connected: authMode !== null },
    };
  }

  async connectApiKey(key: string): Promise<void> {
    if (!this.codex.isInstalled()) throw new Error("Install the Codex CLI and retry.");
    await this.codex.loginWithApiKey(key);
  }

  async startCodexLogin(mode: CodexLoginMode): Promise<CodexLoginStart> {
    if (!this.codex.isInstalled()) throw new Error("Install the Codex CLI and retry.");
    return this.codex.beginLogin(mode);
  }

  async waitForCodexLogin(loginId: string, signal?: AbortSignal): Promise<CodexLoginResult> {
    const status = await this.codex.waitForLogin(loginId, 5 * 60_000, signal);
    return status;
  }
}
