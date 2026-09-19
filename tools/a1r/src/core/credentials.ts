import { execFileSync } from "node:child_process";
import { chmodSync, existsSync, lstatSync, mkdirSync, readFileSync, renameSync, writeFileSync } from "node:fs";
import { join } from "node:path";

const services = {
  openai: "dev.a1r.openai",
  telegram: "dev.a1r.telegram",
} as const;

export type SecretName = keyof typeof services;

export function readSecret(name: SecretName, homeDir: string): string | undefined {
  const envName = name === "openai" ? "OPENAI_API_KEY" : "TELEGRAM_BOT_TOKEN";
  if (process.env[envName]) return process.env[envName];
  if (process.platform === "darwin") {
    try {
      return execFileSync("security", ["find-generic-password", "-a", "a1r", "-s", services[name], "-w"], {
        encoding: "utf8",
        stdio: ["ignore", "pipe", "ignore"],
      }).trim();
    } catch {
      // Fall through to the portable local credential file.
    }
  }
  try {
    const path = join(homeDir, "credentials.json");
    if (lstatSync(path).isSymbolicLink()) return undefined;
    const parsed = JSON.parse(readFileSync(path, "utf8")) as Record<string, string>;
    return parsed[name];
  } catch {
    return undefined;
  }
}

export function writeSecret(name: SecretName, value: string, homeDir: string): "keychain" | "file" {
  if (process.platform === "darwin") {
    try {
      execFileSync("security", ["add-generic-password", "-U", "-a", "a1r", "-s", services[name], "-w", value], {
        stdio: "ignore",
      });
      return "keychain";
    } catch {
      // Portable fallback keeps local setup usable without Keychain access.
    }
  }
  mkdirSync(homeDir, { recursive: true, mode: 0o700 });
  const homeStat = lstatSync(homeDir);
  if (homeStat.isSymbolicLink()) throw new Error("A1R_HOME must not be a symbolic link.");
  if (typeof process.getuid === "function" && homeStat.uid !== process.getuid()) throw new Error("A1R_HOME is owned by another user.");
  chmodSync(homeDir, 0o700);
  const path = join(homeDir, "credentials.json");
  if (existsSync(path) && lstatSync(path).isSymbolicLink()) throw new Error("Credential file must not be a symbolic link.");
  let existing: Record<string, string> = {};
  try {
    existing = JSON.parse(readFileSync(path, "utf8")) as Record<string, string>;
  } catch {
    // First credential.
  }
  const temporary = `${path}.${process.pid}.tmp`;
  writeFileSync(temporary, `${JSON.stringify({ ...existing, [name]: value }, null, 2)}\n`, { mode: 0o600 });
  renameSync(temporary, path);
  chmodSync(path, 0o600);
  return "file";
}
