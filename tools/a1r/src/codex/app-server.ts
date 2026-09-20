import { spawn, spawnSync, type ChildProcessWithoutNullStreams } from "node:child_process";
import { chmodSync, existsSync, lstatSync, mkdirSync } from "node:fs";
import { join } from "node:path";
import { createInterface, type Interface } from "node:readline";
import type { RuntimeConfig } from "../core/types.js";
import type {
  CodexAccountStatus,
  CodexLoginResult,
  CodexLoginStart,
  CodexRateLimits,
  JsonRpcMessage,
} from "./protocol.js";
import { redactSecrets } from "../core/security.js";

type NotificationListener = (message: JsonRpcMessage) => void;

export class CodexRpcError extends Error {
  constructor(readonly code: number, message: string, readonly data?: unknown) {
    super(message);
    this.name = "CodexRpcError";
  }
}

export class CodexDisconnectedError extends Error {
  constructor(message = "Codex app-server disconnected.") {
    super(message);
    this.name = "CodexDisconnectedError";
  }
}

export interface CodexAppServerOptions {
  command: string;
  args?: string[];
  env?: NodeJS.ProcessEnv;
  installed?: boolean;
  requestTimeoutMs?: number;
}

export function prepareA1RCodexHome(homeDir: string): string {
  const codexHome = join(homeDir, "codex");
  mkdirSync(homeDir, { recursive: true, mode: 0o700 });
  chmodSync(homeDir, 0o700);
  if (existsSync(codexHome)) {
    const stat = lstatSync(codexHome);
    if (stat.isSymbolicLink() || !stat.isDirectory()) {
      throw new Error("A1R's private Codex profile must be a real directory, not a file or symbolic link.");
    }
  } else {
    mkdirSync(codexHome, { mode: 0o700 });
  }
  chmodSync(codexHome, 0o700);
  return codexHome;
}

export function createA1RCodexAppServer(
  config: Pick<RuntimeConfig, "homeDir" | "codexCommand">,
  options: Omit<CodexAppServerOptions, "command" | "env"> & { env?: NodeJS.ProcessEnv } = {},
): CodexAppServer {
  const codexHome = prepareA1RCodexHome(config.homeDir);
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

export class CodexAppServer {
  private process: ChildProcessWithoutNullStreams | null = null;
  private lines: Interface | null = null;
  private starting: Promise<void> | null = null;
  private nextId = 1;
  private pending = new Map<number | string, PendingRequest>();
  private listeners = new Set<NotificationListener>();
  private logins = new Map<string, CodexLoginResult>();
  private closing = false;
  private stderr = "";

  constructor(private readonly options: CodexAppServerOptions) {}

  isInstalled(): boolean {
    if (this.options.installed !== undefined) return this.options.installed;
    const result = spawnSync(this.options.command, ["--version"], { stdio: "ignore" });
    return !result.error && result.status === 0;
  }

  async ensureStarted(): Promise<void> {
    if (this.process && !this.process.killed) return;
    if (!this.starting) {
      this.starting = this.start().finally(() => { this.starting = null; });
    }
    await this.starting;
  }

  private async start(): Promise<void> {
    if (!this.isInstalled()) throw new Error("Codex is not installed. Install the official Codex CLI, then run ChatGPT setup again. API-key billing is available only through an explicit `a1r setup --api-key` selection.");
    this.closing = false;
    this.stderr = "";
    const child = spawn(this.options.command, this.options.args ?? ["app-server"], {
      stdio: ["pipe", "pipe", "pipe"],
      env: this.options.env ?? process.env,
    });
    this.process = child;
    this.lines = createInterface({ input: child.stdout });
    this.lines.on("line", (line) => this.receive(line));
    child.stderr.setEncoding("utf8");
    child.stderr.on("data", (chunk: string) => {
      this.stderr = `${this.stderr}${chunk}`.slice(-4_000);
    });
    child.once("exit", (code, signal) => this.disconnected(code, signal));
    child.once("error", (error) => this.disconnected(null, null, error));

    try {
      await this.rawRequest("initialize", {
        clientInfo: { name: "a1r", title: "A1R", version: "0.4.0" },
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

  onNotification(listener: NotificationListener): () => void {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }

  async account(refreshToken = true): Promise<CodexAccountStatus> {
    return this.request<CodexAccountStatus>("account/read", { refreshToken });
  }

  async rateLimits(): Promise<CodexRateLimits> {
    return this.request<CodexRateLimits>("account/rateLimits/read", {});
  }

  async beginLogin(): Promise<CodexLoginStart> {
    const result = await this.request<Partial<CodexLoginStart>>("account/login/start", {
      type: "chatgpt",
      useHostedLoginSuccessPage: true,
      appBrand: "chatgpt",
    });
    if (result.type !== "chatgpt" || typeof result.loginId !== "string" || typeof result.authUrl !== "string") {
      throw new Error("Codex app-server did not return a valid browser login.");
    }
    if (!this.logins.has(result.loginId)) this.logins.set(result.loginId, { state: "pending" });
    return result as CodexLoginStart;
  }

  loginStatus(loginId: string): CodexLoginResult {
    return this.logins.get(loginId) ?? { state: "failed", error: "Unknown login attempt." };
  }

  async waitForLogin(loginId: string, timeoutMs = 5 * 60_000): Promise<CodexLoginResult> {
    const current = this.loginStatus(loginId);
    if (current.state !== "pending") return current;
    return new Promise((resolve) => {
      const timer = setTimeout(() => {
        unsubscribe();
        resolve({ state: "failed", error: "Login timed out. Run setup again." });
      }, timeoutMs);
      const unsubscribe = this.onNotification((message) => {
        if (message.method !== "account/login/completed" || message.params?.loginId !== loginId) return;
        clearTimeout(timer);
        unsubscribe();
        resolve(this.loginStatus(loginId));
      });
    });
  }

  async restart(): Promise<void> {
    await this.stop();
    await this.ensureStarted();
  }

  async stop(): Promise<void> {
    this.closing = true;
    const child = this.process;
    this.process = null;
    this.lines?.close();
    this.lines = null;
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
    for (const listener of this.listeners) listener(message);
  }

  private respondToServerRequest(message: JsonRpcMessage): void {
    if (!this.process?.stdin.writable || message.id === undefined) return;
    let result: unknown;
    if (message.method === "item/commandExecution/requestApproval" || message.method === "item/fileChange/requestApproval") {
      result = { decision: "decline" };
    } else {
      this.process.stdin.write(`${JSON.stringify({ id: message.id, error: { code: -32601, message: "A1R does not implement this server request." } })}\n`);
      return;
    }
    this.process.stdin.write(`${JSON.stringify({ id: message.id, result })}\n`);
  }

  private disconnected(code: number | null, signal: NodeJS.Signals | null, error?: Error): void {
    const wasClosing = this.closing;
    this.process = null;
    this.lines?.close();
    this.lines = null;
    const detail = redactSecrets(error?.message ?? this.stderr.trim() ?? `exit ${code ?? signal ?? "unknown"}`);
    const disconnected = new CodexDisconnectedError(`Codex app-server disconnected (${detail}).`);
    for (const request of this.pending.values()) {
      clearTimeout(request.timer);
      request.reject(disconnected);
    }
    this.pending.clear();
    if (!wasClosing) {
      for (const listener of this.listeners) listener({ method: "a1r/disconnected", params: { message: disconnected.message } });
    }
  }
}
