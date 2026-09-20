import { createHash } from "node:crypto";
import { execFile } from "node:child_process";
import {
  chmodSync,
  existsSync,
  lstatSync,
  mkdirSync,
  readFileSync,
  renameSync,
  watch,
  writeFileSync,
  type FSWatcher,
} from "node:fs";
import { readdir, readFile } from "node:fs/promises";
import { basename, join, relative } from "node:path";
import { promisify } from "node:util";

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

function delay(milliseconds: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
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

function statePath(homeDir: string): string {
  return join(homeDir, UPDATE_STATE);
}

function readState(homeDir: string): UpdateState | null {
  try {
    return JSON.parse(readFileSync(statePath(homeDir), "utf8")) as UpdateState;
  } catch {
    return null;
  }
}

function writeState(homeDir: string, state: UpdateState): void {
  mkdirSync(homeDir, { recursive: true, mode: 0o700 });
  chmodSync(homeDir, 0o700);
  const path = statePath(homeDir);
  if (existsSync(path) && lstatSync(path).isSymbolicLink()) throw new Error("Agent update state must not be a symbolic link.");
  const temporary = `${path}.${process.pid}.tmp`;
  writeFileSync(temporary, `${JSON.stringify(state, null, 2)}\n`, { mode: 0o600 });
  renameSync(temporary, path);
  chmodSync(path, 0o600);
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
  private readonly watchers: FSWatcher[] = [];
  private readonly debounceMs: number;
  private activeTurns = 0;
  private dirty = false;
  private applying = false;
  private accepting = true;
  private stopped = false;
  private timer: NodeJS.Timeout | null = null;
  private verifyController: AbortController | null = null;

  constructor(private readonly options: SelfUpdateOptions) {
    this.debounceMs = options.debounceMs ?? 500;
  }

  async start(): Promise<void> {
    const source = join(this.options.projectRoot, "src");
    if (existsSync(source)) {
      this.watchers.push(watch(source, { recursive: true }, () => this.noteChange()));
    }
    this.watchers.push(watch(this.options.projectRoot, (_event, filename) => {
      if (filename && ROOT_FILES.has(basename(String(filename)))) this.noteChange();
    }));

    const fingerprint = await agentSourceFingerprint(this.options.projectRoot);
    const state = readState(this.options.homeDir);
    if (!state) writeState(this.options.homeDir, { deployedFingerprint: fingerprint });
    else if (state.deployedFingerprint !== fingerprint) this.noteChange();
  }

  beginTurn(): boolean {
    if (!this.accepting || this.stopped) return false;
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
    for (const watcher of this.watchers.splice(0)) watcher.close();
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
    this.accepting = false;
    try {
      let verifiedFingerprint = "";
      while (!this.stopped) {
        const before = await agentSourceFingerprint(this.options.projectRoot);
        this.dirty = false;
        this.options.onStatus?.("Verifying Agent update…");
        this.verifyController = new AbortController();
        try {
          await (this.options.verify ?? ((signal) => verifyAgent(this.options.projectRoot, signal)))(this.verifyController.signal);
        } catch (error) {
          if (this.stopped) return;
          const afterFailure = await agentSourceFingerprint(this.options.projectRoot);
          if (afterFailure !== before) {
            this.dirty = true;
            continue;
          }
          throw error;
        } finally {
          this.verifyController = null;
        }
        await delay(this.debounceMs);
        const after = await agentSourceFingerprint(this.options.projectRoot);
        if (after === before) {
          verifiedFingerprint = after;
          break;
        }
        this.dirty = true;
      }
      if (this.stopped) return;

      const ownerId = this.options.ownerId();
      writeState(this.options.homeDir, {
        deployedFingerprint: verifiedFingerprint,
        ...(ownerId ? { notificationOwnerId: ownerId } : {}),
      });
      this.options.onStatus?.("Agent update verified; restarting…");
      let accepted = false;
      while (!accepted && !this.stopped) {
        try {
          accepted = await this.options.requestRuntimeRestart();
        } catch {
          // The supervisor may be replacing a runtime that disconnected independently.
        }
        if (accepted) break;
        await delay(Math.min(250, this.debounceMs));
      }
      if (this.stopped) return;
      await this.options.stopGateway();
    } catch (error) {
      if (this.stopped) return;
      this.applying = false;
      this.accepting = true;
      const message = error instanceof Error ? error.message : String(error);
      this.options.onStatus?.(`Agent update was not applied: ${message}`);
      await this.options.onFailure?.(message);
      this.schedule();
    }
  }
}
