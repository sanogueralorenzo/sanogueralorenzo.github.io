import { spawn, spawnSync, type ChildProcessWithoutNullStreams } from "node:child_process";
import { EventEmitter } from "node:events";
import { join } from "node:path";
import { createInterface } from "node:readline";
import { setTimeout as delay } from "node:timers/promises";
import type { RuntimeConfig } from "../conversation/types.js";
import type {
  CodexAccountStatus,
  CodexLoginMode,
  CodexLoginResult,
  CodexLoginStart,
  JsonRpcMessage,
} from "./protocol.js";
import { redactSecrets } from "../workspace/security.js";
import { ensurePrivateDirectory, writePrivateFile } from "../local/files.js";

export class CodexDisconnectedError extends Error {
  constructor(message = "Codex app-server disconnected.") {
    super(message);
  }
}

export interface CodexAppServerOptions {
  command: string;
  args?: string[];
  env?: NodeJS.ProcessEnv;
  requestTimeoutMs?: number;
}

export function prepareAgentCodexHome(homeDir: string): string {
  const codexHome = join(homeDir, "codex");
  ensurePrivateDirectory(homeDir);
  ensurePrivateDirectory(codexHome);
  writePrivateFile(join(codexHome, "config.toml"), "[agents]\nenabled = false\n");
  return codexHome;
}

export function createAgentCodexAppServer(
  config: Pick<RuntimeConfig, "homeDir" | "codexCommand">,
  options: Omit<CodexAppServerOptions, "command" | "env"> & { env?: NodeJS.ProcessEnv } = {},
): CodexAppServer {
  const codexHome = prepareAgentCodexHome(config.homeDir);
  const env = { ...process.env, ...options.env };
  for (const name of [
    "CODEX_ACCESS_TOKEN",
    "CODEX_API_KEY",
    "OPENAI_API_KEY",
    "OPENAI_FEDERATION_RULE_ID",
    "OPENAI_IDENTITY_TOKEN_FILE",
    "OPENAI_WORKLOAD_IDENTITY_CONTEXT",
  ]) delete env[name];
  env.CODEX_HOME = codexHome;
  env.CODEX_SQLITE_HOME = codexHome;
  return new CodexAppServer({
    ...options,
    command: config.codexCommand,
    env,
  });
}

interface PendingRequest {
  resolve: (value: unknown) => void;
  reject: (error: Error) => void;
  timer: NodeJS.Timeout;
}

export class CodexAppServer extends EventEmitter {
  private process: ChildProcessWithoutNullStreams | null = null;
  private starting: Promise<void> | null = null;
  private nextId = 1;
  private pending = new Map<number, PendingRequest>();
  private logins = new Map<string, CodexLoginResult>();
  private stderr = "";

  constructor(private readonly options: CodexAppServerOptions) {
    super();
  }

  isInstalled(): boolean {
    const result = spawnSync(this.options.command, ["--version"], { stdio: "ignore" });
    return !result.error && result.status === 0;
  }

  async ensureStarted(): Promise<void> {
    if (this.process) return;
    this.starting ??= this.start().finally(() => { this.starting = null; });
    await this.starting;
  }

  private async start(): Promise<void> {
    this.stderr = "";
    const child = spawn(this.options.command, this.options.args ?? ["app-server"], {
      stdio: ["pipe", "pipe", "pipe"],
      env: this.options.env ?? process.env,
    });
    this.process = child;
    createInterface({ input: child.stdout }).on("line", (line) => this.receive(line));
    child.stderr.setEncoding("utf8");
    child.stderr.on("data", (chunk: string) => {
      this.stderr = `${this.stderr}${chunk}`.slice(-4_000);
    });
    child.once("exit", (code, signal) => this.disconnected(child, code, signal));
    child.once("error", (error) => this.disconnected(child, null, null, error));

    try {
      await this.rawRequest("initialize", {
        clientInfo: { name: "agent", title: "Agent", version: "0.5.0" },
        capabilities: { experimentalApi: true, requestAttestation: false },
      });
      child.stdin.write(`${JSON.stringify({ method: "initialized", params: {} })}\n`);
    } catch (error) {
      child.kill("SIGTERM");
      throw error;
    }
  }

  async request<T>(method: string, params: Record<string, unknown> = {}): Promise<T> {
    await this.ensureStarted();
    return this.rawRequest(method, params) as Promise<T>;
  }

  async account(refreshToken = true): Promise<CodexAccountStatus> {
    return this.request<CodexAccountStatus>("account/read", { refreshToken });
  }

  async beginLogin(mode: CodexLoginMode): Promise<CodexLoginStart> {
    const result = await this.request<Record<string, unknown>>("account/login/start", {
      type: mode === "headless" ? "chatgptDeviceCode" : "chatgpt",
    });
    const login = result as unknown as CodexLoginStart;
    const valid = typeof login.loginId === "string" && (mode === "browser"
      ? login.type === "chatgpt" && typeof login.authUrl === "string"
      : login.type === "chatgptDeviceCode" && typeof login.verificationUrl === "string" && typeof login.userCode === "string");
    if (!valid) throw new Error(`Codex app-server did not return a valid ${mode} login.`);
    this.logins.set(login.loginId, { state: "pending" });
    return login;
  }

  async waitForLogin(loginId: string, timeoutMs = 5 * 60_000, signal?: AbortSignal): Promise<CodexLoginResult> {
    const timeout = AbortSignal.timeout(timeoutMs);
    const combined = signal ? AbortSignal.any([signal, timeout]) : timeout;
    try {
      while (this.logins.get(loginId)?.state === "pending") await delay(25, undefined, { signal: combined });
      return this.logins.get(loginId) ?? { state: "failed", error: "Unknown login attempt." };
    } catch {
      await this.request("account/login/cancel", { loginId }).catch(() => undefined);
      return { state: "failed", error: signal?.aborted ? "Setup cancelled." : "Login timed out. Run setup again." };
    }
  }

  async restart(): Promise<void> {
    this.stop();
    await this.ensureStarted();
  }

  stop(): void {
    const child = this.process;
    this.process = null;
    if (child?.exitCode === null && child.signalCode === null) child.kill("SIGTERM");
  }

  private rawRequest(method: string, params: Record<string, unknown>): Promise<unknown> {
    const child = this.process;
    if (!child?.stdin.writable) return Promise.reject(new CodexDisconnectedError());
    const id = this.nextId++;
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        this.pending.delete(id);
        reject(new Error(`Codex app-server timed out while handling ${method}.`));
      }, this.options.requestTimeoutMs ?? 30_000);
      this.pending.set(id, { resolve, reject, timer });
      child.stdin.write(`${JSON.stringify({ method, id, params })}\n`, (error) => {
        if (!error) return;
        clearTimeout(timer);
        this.pending.delete(id);
        reject(new CodexDisconnectedError(error.message));
      });
    });
  }

  private receive(line: string): void {
    let message: JsonRpcMessage;
    try {
      message = JSON.parse(line) as JsonRpcMessage;
    } catch {
      return;
    }
    if (typeof message.id === "number" && (message.result !== undefined || message.error !== undefined)) {
      const pending = this.pending.get(message.id);
      if (!pending) return;
      clearTimeout(pending.timer);
      this.pending.delete(message.id);
      if (message.error) pending.reject(new Error(message.error.message));
      else pending.resolve(message.result);
      return;
    }
    if (message.method === "account/login/completed") {
      const loginId = typeof message.params?.loginId === "string" ? message.params.loginId : null;
      if (loginId) {
        const success = message.params?.success === true;
        const error = typeof message.params?.error === "string" ? message.params.error : undefined;
        this.logins.set(loginId, success ? { state: "complete" } : { state: "failed", ...(error ? { error } : {}) });
      }
    }
    this.emit("notification", message);
  }

  private disconnected(child: ChildProcessWithoutNullStreams, code: number | null, signal: NodeJS.Signals | null, error?: Error): void {
    if (this.process !== child) return;
    this.process = null;
    const detail = redactSecrets(error?.message ?? this.stderr.trim() ?? `exit ${code ?? signal ?? "unknown"}`);
    const disconnected = new CodexDisconnectedError(`Codex app-server disconnected (${detail}).`);
    for (const request of this.pending.values()) {
      clearTimeout(request.timer);
      request.reject(disconnected);
    }
    this.pending.clear();
    this.emit("notification", { method: "agent/disconnected", params: { message: disconnected.message } });
  }
}
