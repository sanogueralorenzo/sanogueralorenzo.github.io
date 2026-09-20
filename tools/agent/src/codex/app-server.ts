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

export class CodexRpcError extends Error {
  constructor(readonly code: number, message: string, readonly data?: unknown) {
    super(message);
  }
}

export class CodexDisconnectedError extends Error {
  constructor(message = "Codex app-server disconnected.") {
    super(message);
  }
}

export interface CodexAppServerOptions {
  command: string;
  args?: string[];
  env?: NodeJS.ProcessEnv;
  installed?: boolean;
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
  private pending = new Map<number | string, PendingRequest>();
  private logins = new Map<string, CodexLoginResult>();
  private closing = false;
  private stderr = "";

  constructor(private readonly options: CodexAppServerOptions) {
    super();
  }

  isInstalled(): boolean {
    if (this.options.installed !== undefined) return this.options.installed;
    const result = spawnSync(this.options.command, ["--version"], { stdio: "ignore" });
    return !result.error && result.status === 0;
  }

  async ensureStarted(): Promise<void> {
    if (this.process && !this.process.killed) return;
    this.starting ??= this.start().finally(() => { this.starting = null; });
    await this.starting;
  }

  private async start(): Promise<void> {
    if (!this.isInstalled()) throw new Error("Codex is not installed. Install the official Codex CLI, then run ChatGPT setup again. API-key billing is available only through an explicit `agent setup --api-key` selection.");
    this.closing = false;
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
    child.once("exit", (code, signal) => this.disconnected(code, signal));
    child.once("error", (error) => this.disconnected(null, null, error));

    try {
      await this.rawRequest("initialize", {
        clientInfo: { name: "agent", title: "Agent", version: "0.5.0" },
        capabilities: { experimentalApi: true, requestAttestation: false },
      });
      this.notify("initialized", {});
    } catch (error) {
      child.kill("SIGTERM");
      throw error;
    }
  }

  async request<T>(method: string, params: Record<string, unknown> = {}): Promise<T> {
    await this.ensureStarted();
    return this.rawRequest(method, params) as Promise<T>;
  }

  notify(method: string, params: Record<string, unknown>): void {
    if (!this.process?.stdin.writable) throw new CodexDisconnectedError();
    this.process.stdin.write(`${JSON.stringify({ method, params })}\n`);
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

  loginStatus(loginId: string): CodexLoginResult {
    return this.logins.get(loginId) ?? { state: "failed", error: "Unknown login attempt." };
  }

  async cancelLogin(loginId: string): Promise<void> {
    await this.request("account/login/cancel", { loginId });
    if (this.loginStatus(loginId).state === "pending") {
      this.logins.set(loginId, { state: "failed", error: "ChatGPT sign-in was cancelled." });
    }
  }

  async waitForLogin(loginId: string, timeoutMs = 5 * 60_000, signal?: AbortSignal): Promise<CodexLoginResult> {
    const timeout = AbortSignal.timeout(timeoutMs);
    const combined = signal ? AbortSignal.any([signal, timeout]) : timeout;
    try {
      while (this.loginStatus(loginId).state === "pending") await delay(25, undefined, { signal: combined });
      return this.loginStatus(loginId);
    } catch {
      await this.cancelLogin(loginId).catch(() => undefined);
      return { state: "failed", error: signal?.aborted ? "Setup cancelled." : "Login timed out. Run setup again." };
    }
  }

  async restart(): Promise<void> {
    await this.stop();
    await this.ensureStarted();
  }

  async stop(): Promise<void> {
    this.closing = true;
    const child = this.process;
    this.process = null;
    if (!child || child.exitCode !== null || child.signalCode !== null) return;
    await new Promise<void>((resolve) => {
      const timer = setTimeout(() => {
        child.kill("SIGKILL");
        resolve();
      }, 1_000);
      child.once("exit", () => {
        clearTimeout(timer);
        resolve();
      });
      child.kill("SIGTERM");
    });
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
    if (message.id !== undefined && (message.result !== undefined || message.error !== undefined)) {
      const pending = this.pending.get(message.id);
      if (!pending) return;
      clearTimeout(pending.timer);
      this.pending.delete(message.id);
      if (message.error) pending.reject(new CodexRpcError(message.error.code, message.error.message, message.error.data));
      else pending.resolve(message.result);
      return;
    }
    if (message.id !== undefined && message.method) {
      this.respondToServerRequest(message);
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

  private respondToServerRequest(message: JsonRpcMessage): void {
    if (!this.process?.stdin.writable || message.id === undefined) return;
    let result: unknown;
    if (message.method === "item/commandExecution/requestApproval" || message.method === "item/fileChange/requestApproval") {
      result = { decision: "decline" };
    } else {
      this.process.stdin.write(`${JSON.stringify({ id: message.id, error: { code: -32601, message: "Agent does not implement this server request." } })}\n`);
      return;
    }
    this.process.stdin.write(`${JSON.stringify({ id: message.id, result })}\n`);
  }

  private disconnected(code: number | null, signal: NodeJS.Signals | null, error?: Error): void {
    const wasClosing = this.closing;
    this.process = null;
    const detail = redactSecrets(error?.message ?? this.stderr.trim() ?? `exit ${code ?? signal ?? "unknown"}`);
    const disconnected = new CodexDisconnectedError(`Codex app-server disconnected (${detail}).`);
    for (const request of this.pending.values()) {
      clearTimeout(request.timer);
      request.reject(disconnected);
    }
    this.pending.clear();
    if (!wasClosing) {
      this.emit("notification", { method: "agent/disconnected", params: { message: disconnected.message } });
    }
  }
}
