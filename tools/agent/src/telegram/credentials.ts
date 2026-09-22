import { execFileSync } from "node:child_process";
import { join } from "node:path";
import { ensurePrivateDirectory, readPrivateJson, writePrivateJson } from "../local/files.js";

const service = "dev.agent.telegram";
const macOSKeychain = "/usr/bin/security";

export function readTelegramToken(homeDir: string): string | undefined {
  if (process.env.TELEGRAM_BOT_TOKEN) return process.env.TELEGRAM_BOT_TOKEN;
  if (process.platform === "darwin") {
    try {
      return execFileSync(macOSKeychain, ["find-generic-password", "-a", "agent", "-s", service, "-w"], {
        encoding: "utf8",
        stdio: ["ignore", "pipe", "ignore"],
      }).trim();
    } catch {
      return undefined;
    }
  }
  return readPrivateJson<{ telegram?: string }>(join(homeDir, "credentials.json"))?.telegram;
}

export function writeTelegramToken(value: string, homeDir: string): void {
  if (process.platform === "darwin") {
    try {
      execFileSync(macOSKeychain, ["add-generic-password", "-U", "-a", "agent", "-s", service, "-w", value], {
        stdio: "ignore",
      });
      return;
    } catch (cause) {
      throw new Error(`Agent could not save Telegram in macOS Keychain: ${cause instanceof Error ? cause.message : String(cause)}`);
    }
  }
  ensurePrivateDirectory(homeDir);
  writePrivateJson(join(homeDir, "credentials.json"), { telegram: value });
}
