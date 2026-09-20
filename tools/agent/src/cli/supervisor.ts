import { spawn, type ChildProcess } from "node:child_process";
import { fileURLToPath } from "node:url";
import { dirname, join, resolve } from "node:path";
import type { RuntimeClient } from "../client/client.js";

export class RuntimeSupervisor {
  private child: ChildProcess | null = null;
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
      await this.client.waitUntilHealthy();
    }
    this.monitorTimer = setInterval(() => void this.ensureRuntime(), 1_000);
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
      await this.client.waitUntilHealthy();
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
    const args = runSource ? [...(this.dev ? ["--watch"] : []), "--import", "tsx", entry] : [entry];
    this.child = spawn(process.execPath, args, {
      cwd: this.projectRoot(),
      env: process.env,
      stdio: ["ignore", "ignore", "pipe"],
    });
    this.child.stderr?.on("data", (chunk) => {
      const message = String(chunk).trim();
      if (message && !message.includes("ExperimentalWarning")) this.onStatus(message);
    });
    this.child.once("exit", () => {
      this.child = null;
    });
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
    if (this.monitorTimer) clearInterval(this.monitorTimer);
    await this.stopChild();
  }
}
