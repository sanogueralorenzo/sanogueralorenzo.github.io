import { execFileSync } from "node:child_process";
import { join } from "node:path";
import { ensurePrivateDirectory, readPrivateJson, writePrivateJson } from "./files.js";

const services = {
  openai: "dev.agent.openai",
  telegram: "dev.agent.telegram",
} as const;

export type SecretName = keyof typeof services;

export function readSecret(name: SecretName, homeDir: string): string | undefined {
  const envName = name === "openai" ? "OPENAI_API_KEY" : "TELEGRAM_BOT_TOKEN";
  if (process.env[envName]) return process.env[envName];
  if (process.platform === "darwin") {
    try {
      return execFileSync("security", ["find-generic-password", "-a", "agent", "-s", services[name], "-w"], {
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
      execFileSync("security", ["add-generic-password", "-U", "-a", "agent", "-s", services[name], "-w", value], {
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
