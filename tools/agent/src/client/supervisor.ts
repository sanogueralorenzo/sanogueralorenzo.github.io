import { spawn, type ChildProcess } from "node:child_process";
import { fileURLToPath } from "node:url";
import { dirname, join, resolve } from "node:path";
import type { RuntimeClient } from "./client.js";

const projectRoot = resolve(dirname(fileURLToPath(import.meta.url)), "../..");

export class RuntimeSupervisor {
  private child: ChildProcess | null = null;
  private monitorTimer: NodeJS.Timeout | null = null;
  private recovering = false;
  private stopping = false;

  constructor(
    private readonly client: RuntimeClient,
    private readonly dev: boolean,
    private readonly onStatus: (message: string) => void,
  ) {}

  async start(): Promise<void> {
    if (!await this.client.healthy()) {
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

  private spawnRuntime(): void {
    const sourceMode = fileURLToPath(import.meta.url).endsWith(".ts");
    const runSource = sourceMode || this.dev;
    const entry = join(projectRoot, runSource ? "src/server/main.ts" : "dist/server/main.js");
    const args = runSource ? [...(this.dev ? ["--watch"] : []), "--import", "tsx", entry] : [entry];
    this.child = spawn(process.execPath, args, {
      cwd: projectRoot,
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

  stop(): void {
    this.stopping = true;
    if (this.monitorTimer) clearInterval(this.monitorTimer);
    this.child?.kill("SIGTERM");
    this.child = null;
  }
}
