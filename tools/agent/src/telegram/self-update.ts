import { createHash } from "node:crypto";
import { execFile } from "node:child_process";
import { existsSync, watch, type FSWatcher } from "node:fs";
import { readdir, readFile } from "node:fs/promises";
import { join, relative } from "node:path";
import { setTimeout as delay } from "node:timers/promises";
import { promisify } from "node:util";
import { readPrivateJson, writePrivateJson } from "../local/files.js";

const execFileAsync = promisify(execFile);
const ROOT_FILES = new Set(["package.json", "package-lock.json", "tsconfig.json", "vitest.config.ts"]);
const UPDATE_STATE = "self-update.json";

interface UpdateState {
  deployedFingerprint: string;
  notificationOwnerId?: string;
}

interface SelfUpdateOptions {
  projectRoot: string;
  homeDir: string;
  requestRuntimeRestart: () => Promise<boolean>;
  stopGateway: () => Promise<void>;
  ownerId: () => string | undefined;
  verify?: (signal: AbortSignal) => Promise<void>;
  onStatus?: (message: string) => void;
  onFailure?: (message: string) => Promise<void> | void;
  debounceMs?: number;
}

async function addDirectory(hash: ReturnType<typeof createHash>, root: string, path: string): Promise<void> {
  const entries = await readdir(path, { withFileTypes: true });
  entries.sort((left, right) => left.name.localeCompare(right.name));
  for (const entry of entries) {
    const child = join(path, entry.name);
    if (entry.isDirectory()) {
      await addDirectory(hash, root, child);
    } else if (entry.isFile()) {
      hash.update(relative(root, child));
      hash.update(await readFile(child));
    }
  }
}

export async function agentSourceFingerprint(projectRoot: string): Promise<string> {
  const hash = createHash("sha256");
  const source = join(projectRoot, "src");
  if (existsSync(source)) await addDirectory(hash, projectRoot, source);
  for (const name of [...ROOT_FILES].sort()) {
    const path = join(projectRoot, name);
    if (!existsSync(path)) continue;
    hash.update(name);
    hash.update(await readFile(path));
  }
  return hash.digest("hex");
}

function readState(homeDir: string): UpdateState | null {
  return readPrivateJson(join(homeDir, UPDATE_STATE));
}

function writeState(homeDir: string, state: UpdateState): void {
  writePrivateJson(join(homeDir, UPDATE_STATE), state);
}

export function pendingUpdateOwner(homeDir: string): string | null {
  return readState(homeDir)?.notificationOwnerId ?? null;
}

export function acknowledgeUpdate(homeDir: string): void {
  const state = readState(homeDir);
  if (!state?.notificationOwnerId) return;
  writeState(homeDir, { deployedFingerprint: state.deployedFingerprint });
}

async function verifyAgent(projectRoot: string, signal: AbortSignal): Promise<void> {
  const environment = Object.fromEntries(
    Object.entries(process.env).filter(([key]) => !/(?:KEY|TOKEN|SECRET|PASSWORD|CREDENTIAL)/i.test(key)),
  );
  try {
    await execFileAsync("npm", ["run", "check"], {
      cwd: projectRoot,
      env: environment,
      timeout: 300_000,
      maxBuffer: 2_000_000,
      signal,
    });
  } catch (error) {
    const result = error as { stdout?: string; stderr?: string };
    const detail = [result.stdout, result.stderr].filter(Boolean).join("\n").trim().slice(-4_000);
    throw new Error(detail || (error instanceof Error ? error.message : String(error)));
  }
}

export class TelegramSelfUpdate {
  private watcher: FSWatcher | null = null;
  private readonly debounceMs: number;
  private activeTurns = 0;
  private dirty = false;
  private applying = false;
  private stopped = false;
  private timer: NodeJS.Timeout | null = null;
  private verifyController: AbortController | null = null;

  constructor(private readonly options: SelfUpdateOptions) {
    this.debounceMs = options.debounceMs ?? 500;
  }

  async start(): Promise<void> {
    this.watcher = watch(this.options.projectRoot, { recursive: true }, (_event, filename) => {
      const path = String(filename ?? "");
      if (/^src[\\/]/.test(path) || ROOT_FILES.has(path)) this.noteChange();
    });

    const fingerprint = await agentSourceFingerprint(this.options.projectRoot);
    const state = readState(this.options.homeDir);
    if (!state) writeState(this.options.homeDir, { deployedFingerprint: fingerprint });
    else if (state.deployedFingerprint !== fingerprint) this.noteChange();
  }

  beginTurn(): boolean {
    if (this.applying || this.stopped) return false;
    this.activeTurns += 1;
    return true;
  }

  endTurn(): void {
    this.activeTurns = Math.max(0, this.activeTurns - 1);
    this.schedule();
  }

  noteChange(): void {
    if (this.stopped) return;
    this.dirty = true;
    this.schedule();
  }

  stop(): void {
    this.stopped = true;
    this.verifyController?.abort();
    if (this.timer) clearTimeout(this.timer);
    this.watcher?.close();
  }

  private schedule(): void {
    if (!this.dirty || this.applying || this.activeTurns > 0 || this.stopped) return;
    if (this.timer) clearTimeout(this.timer);
    this.timer = setTimeout(() => {
      this.timer = null;
      void this.apply();
    }, this.debounceMs);
  }

  private async apply(): Promise<void> {
    if (!this.dirty || this.applying || this.activeTurns > 0 || this.stopped) return;
    this.applying = true;
    this.dirty = false;
    this.options.onStatus?.("Verifying Agent update…");
    this.verifyController = new AbortController();
    try {
      const before = await agentSourceFingerprint(this.options.projectRoot);
      await (this.options.verify ?? ((signal) => verifyAgent(this.options.projectRoot, signal)))(this.verifyController.signal);
      await delay(this.debounceMs);
      if (before !== await agentSourceFingerprint(this.options.projectRoot)) {
        this.dirty = true;
        return;
      }
      this.options.onStatus?.("Agent update verified; restarting…");
      if (!await this.options.requestRuntimeRestart()) throw new Error("Agent is busy; the update was not applied.");
      const ownerId = this.options.ownerId();
      writeState(this.options.homeDir, { deployedFingerprint: before, ...(ownerId ? { notificationOwnerId: ownerId } : {}) });
      await this.options.stopGateway();
    } catch (error) {
      if (this.stopped) return;
      const message = error instanceof Error ? error.message : String(error);
      this.options.onStatus?.(`Agent update was not applied: ${message}`);
      await this.options.onFailure?.(message);
    } finally {
      this.verifyController = null;
      this.applying = false;
      this.schedule();
    }
  }
}
