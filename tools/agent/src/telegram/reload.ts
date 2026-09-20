import { readFileSync } from "node:fs";
import { join } from "node:path";

interface TelegramReloadOptions {
  projectRoot: string;
  restart: () => Promise<void>;
  intervalMs?: number;
}

export class TelegramReload {
  private readonly marker: string;
  private version: string | null;
  private timer: NodeJS.Timeout | null = null;
  private active = false;
  private pending = false;
  private restarting = false;

  constructor(private readonly options: TelegramReloadOptions) {
    this.marker = join(options.projectRoot, "dist", ".ready");
    this.version = this.readVersion();
  }

  start(): void {
    this.readBuild();
    this.timer = setInterval(() => this.readBuild(), this.options.intervalMs ?? 250);
  }

  turnStarted(): void {
    this.active = true;
  }

  turnDelivered(): void {
    this.active = false;
    this.restartIfIdle();
  }

  stop(): void {
    if (this.timer) clearInterval(this.timer);
    this.timer = null;
  }

  private readVersion(): string | null {
    try {
      return readFileSync(this.marker, "utf8").trim() || null;
    } catch {
      return null;
    }
  }

  private readBuild(): void {
    const version = this.readVersion();
    if (!version || version === this.version) return;
    this.version = version;
    this.pending = true;
    this.restartIfIdle();
  }

  private restartIfIdle(): void {
    if (!this.pending || this.active || this.restarting) return;
    this.restarting = true;
    this.stop();
    void this.options.restart().catch((error) => console.error(`Telegram restart failed: ${error instanceof Error ? error.message : String(error)}`));
  }
}
