import { execFileSync, spawnSync } from "node:child_process";
import { rmSync } from "node:fs";
import { join } from "node:path";
import { ensurePrivateDirectory, readPrivateJson, writePrivateJson } from "./files.js";

const services = {
  openai: "dev.agent.openai",
  telegram: "dev.agent.telegram",
} as const;
const macOSKeychain = "/usr/bin/security";

export type SecretName = keyof typeof services;

export function readSecret(name: SecretName, homeDir: string): string | undefined {
  const envName = name === "openai" ? "OPENAI_API_KEY" : "TELEGRAM_BOT_TOKEN";
  if (process.env[envName]) return process.env[envName];
  if (process.platform === "darwin") {
    try {
      return execFileSync(macOSKeychain, ["find-generic-password", "-a", "agent", "-s", services[name], "-w"], {
        encoding: "utf8",
        stdio: ["ignore", "pipe", "ignore"],
      }).trim();
    } catch {
      return undefined;
    }
  }
  return readPrivateJson<Record<string, string>>(join(homeDir, "credentials.json"))?.[name];
}

export function writeSecret(name: SecretName, value: string, homeDir: string): "keychain" | "file" {
  if (process.platform === "darwin") {
    try {
      execFileSync(macOSKeychain, ["add-generic-password", "-U", "-a", "agent", "-s", services[name], "-w", value], {
        stdio: "ignore",
      });
      return "keychain";
    } catch (cause) {
      throw new Error(`Agent could not save ${name} in macOS Keychain: ${cause instanceof Error ? cause.message : String(cause)}`);
    }
  }
  ensurePrivateDirectory(homeDir);
  const path = join(homeDir, "credentials.json");
  writePrivateJson(path, { ...readPrivateJson<Record<string, string>>(path), [name]: value });
  return "file";
}

export function deleteSecret(name: SecretName, homeDir: string): void {
  if (process.platform === "darwin") {
    const result = spawnSync(macOSKeychain, ["delete-generic-password", "-a", "agent", "-s", services[name]], { stdio: "ignore" });
    if (result.error) throw result.error;
    if (result.status !== 0 && result.status !== 44) throw new Error(`Agent could not remove ${name} from macOS Keychain.`);
    return;
  }
  const path = join(homeDir, "credentials.json");
  const credentials = readPrivateJson<Record<string, string>>(path);
  if (!credentials) return;
  delete credentials[name];
  if (Object.keys(credentials).length === 0) rmSync(path, { force: true });
  else writePrivateJson(path, credentials);
}
