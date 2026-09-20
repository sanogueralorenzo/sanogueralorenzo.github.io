import { spawn, type ChildProcess } from "node:child_process";
import { watch, type FSWatcher } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join, resolve } from "node:path";
import type { RuntimeClient } from "../client/client.js";

export class RuntimeSupervisor {
  private child: ChildProcess | null = null;
  private watchers: FSWatcher[] = [];
  private restartTimer: NodeJS.Timeout | null = null;
  private monitorTimer: NodeJS.Timeout | null = null;
  private recovering = false;
  private stopping = false;
  private ownsRuntime = false;

  constructor(
    private readonly client: RuntimeClient,
    private readonly dev: boolean,
    private readonly onStatus: (message: string) => void,
  ) {}

  async start(): Promise<void> {
    if (!await this.client.healthy()) {
      this.ownsRuntime = true;
      this.spawnRuntime();
      await this.waitForRuntime();
    }
    this.monitorTimer = setInterval(() => void this.ensureRuntime(), 1_000);
    if (this.dev && this.ownsRuntime) this.startWatching();
  }

  private async ensureRuntime(): Promise<void> {
    if (this.stopping || this.recovering || await this.client.healthy()) return;
    this.recovering = true;
    this.onStatus("Runtime disconnected; reconnecting…");
    try {
      if (!this.child) {
        this.ownsRuntime = true;
        this.spawnRuntime();
      }
      await this.waitForRuntime();
      this.onStatus("Runtime reconnected. Session restored.");
    } catch {
      // The next monitor tick retries.
    } finally {
      this.recovering = false;
    }
  }

  private projectRoot(): string {
    return resolve(dirname(fileURLToPath(import.meta.url)), "../..");
  }

  private spawnRuntime(): void {
    const sourceMode = fileURLToPath(import.meta.url).endsWith(".ts");
    const runSource = sourceMode || this.dev;
    const entry = join(this.projectRoot(), runSource ? "src/server/main.ts" : "dist/server/main.js");
    const args = runSource ? ["--import", "tsx", entry] : [entry];
    this.child = spawn(process.execPath, args, {
      cwd: this.projectRoot(),
      env: process.env,
      stdio: ["ignore", "ignore", "pipe"],
    });
    this.child.stderr?.on("data", (chunk) => {
      const message = String(chunk).trim();
      if (message && !message.includes("ExperimentalWarning")) this.onStatus(message);
    });
    this.child.once("exit", (code) => {
      this.child = null;
      if (!this.stopping && this.ownsRuntime && code !== 0) {
        setTimeout(() => void this.ensureRuntime(), 300);
      }
    });
  }

  private async waitForRuntime(timeoutMs = 10_000): Promise<void> {
    const deadline = Date.now() + timeoutMs;
    while (Date.now() < deadline) {
      if (await this.client.healthy()) return;
      if (this.ownsRuntime && !this.child && !this.stopping) this.spawnRuntime();
      await new Promise((resolve) => setTimeout(resolve, this.child ? 100 : 300));
    }
    throw new Error("Agent runtime did not become ready.");
  }

  private startWatching(): void {
    for (const directory of ["core", "codex", "server", "setup", "prompts", "tools"]) {
      const path = join(this.projectRoot(), "src", directory);
      try {
        this.watchers.push(watch(path, { recursive: true }, () => this.scheduleRestart()));
      } catch {
        // Optional directories may not exist yet.
      }
    }
  }

  private scheduleRestart(): void {
    if (this.restartTimer) clearTimeout(this.restartTimer);
    this.restartTimer = setTimeout(() => void this.restart(), 180);
  }

  private async restart(): Promise<void> {
    if (!this.ownsRuntime || this.stopping) return;
    this.onStatus("Reloading runtime…");
    await this.stopChild();
    this.spawnRuntime();
    await this.waitForRuntime();
    this.onStatus("Runtime reloaded. Session restored.");
  }

  private async stopChild(): Promise<void> {
    const child = this.child;
    if (!child || child.exitCode !== null) return;
    await new Promise<void>((resolve) => {
      const timer = setTimeout(() => {
        child.kill("SIGKILL");
        resolve();
      }, 2_000);
      child.once("exit", () => {
        clearTimeout(timer);
        resolve();
      });
      child.kill("SIGTERM");
    });
  }

  async stop(): Promise<void> {
    this.stopping = true;
    if (this.restartTimer) clearTimeout(this.restartTimer);
    if (this.monitorTimer) clearInterval(this.monitorTimer);
    for (const watcher of this.watchers) watcher.close();
    await this.stopChild();
  }
}
