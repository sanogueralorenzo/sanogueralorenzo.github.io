import { execFileSync } from "node:child_process";
import { accessSync, chmodSync, constants, existsSync, lstatSync, mkdirSync, realpathSync, renameSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { delimiter, dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import type { RuntimeConfig } from "../core/types.js";

export const TELEGRAM_SERVICE_LABEL = "dev.agent.telegram";

interface LaunchAgentOptions {
  launcherPath: string;
  workingDirectory: string;
  homeDir: string;
  codexCommand: string;
  path?: string;
}

function xml(value: string): string {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&apos;");
}

function stringEntry(value: string): string {
  return `    <string>${xml(value)}</string>`;
}

export function renderTelegramLaunchAgent(options: LaunchAgentOptions): string {
  const environment: Array<[string, string]> = [
    ["AGENT_HOME", options.homeDir],
    ["AGENT_CODEX_COMMAND", options.codexCommand],
  ];
  if (options.path) environment.push(["PATH", options.path]);
  const logPath = join(options.homeDir, "telegram.log");
  return [
    '<?xml version="1.0" encoding="UTF-8"?>',
    '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">',
    '<plist version="1.0">',
    "<dict>",
    "  <key>Label</key>",
    `  <string>${TELEGRAM_SERVICE_LABEL}</string>`,
    "  <key>Program</key>",
    `  <string>${xml(options.launcherPath)}</string>`,
    "  <key>ProgramArguments</key>",
    "  <array>",
    stringEntry(options.launcherPath),
    "  </array>",
    "  <key>WorkingDirectory</key>",
    `  <string>${xml(options.workingDirectory)}</string>`,
    "  <key>EnvironmentVariables</key>",
    "  <dict>",
    ...environment.flatMap(([key, value]) => [
      `    <key>${key}</key>`,
      `    <string>${xml(value)}</string>`,
    ]),
    "  </dict>",
    "  <key>RunAtLoad</key>",
    "  <true/>",
    "  <key>KeepAlive</key>",
    "  <true/>",
    "  <key>ProcessType</key>",
    "  <string>Background</string>",
    "  <key>ThrottleInterval</key>",
    "  <integer>3</integer>",
    "  <key>StandardOutPath</key>",
    `  <string>${xml(logPath)}</string>`,
    "  <key>StandardErrorPath</key>",
    `  <string>${xml(logPath)}</string>`,
    "</dict>",
    "</plist>",
    "",
  ].join("\n");
}

function shellArgument(value: string): string {
  return `'${value.replaceAll("'", `'"'"'`)}'`;
}

export function renderTelegramGatewayLauncher(executable: string, serviceEntry: string): string {
  const args = [
    executable,
    ...(serviceEntry.endsWith(".ts") ? ["--import", "tsx"] : []),
    serviceEntry,
  ];
  return `#!/bin/sh\nexec ${args.map(shellArgument).join(" ")}\n`;
}

function executablePath(command: string): string {
  if (command.includes("/")) return resolve(command);
  for (const directory of (process.env.PATH ?? "").split(delimiter)) {
    if (!directory) continue;
    const candidate = join(directory, command);
    try {
      accessSync(candidate, constants.X_OK);
      return candidate;
    } catch {
      // Try the next PATH entry.
    }
  }
  return command;
}

function serviceIsLoaded(service: string): boolean {
  try {
    execFileSync("/bin/launchctl", ["print", service], { stdio: "ignore" });
    return true;
  } catch {
    return false;
  }
}

async function waitForServiceUnload(service: string): Promise<void> {
  const deadline = Date.now() + 3_000;
  while (serviceIsLoaded(service)) {
    if (Date.now() >= deadline) throw new Error("Agent timed out while replacing the previous Telegram background service.");
    await new Promise((resolve) => setTimeout(resolve, 50));
  }
}

export async function installTelegramBackgroundService(
  config: Pick<RuntimeConfig, "homeDir" | "codexCommand">,
): Promise<void> {
  if (process.platform !== "darwin") throw new Error("The Agent Telegram background service currently requires macOS.");
  if (typeof process.getuid !== "function") throw new Error("Agent could not determine the current macOS user.");

  const modulePath = fileURLToPath(import.meta.url);
  const sourceMode = modulePath.endsWith(".ts");
  const serviceEntry = realpathSync(join(dirname(modulePath), `main.${sourceMode ? "ts" : "js"}`));
  const launchAgents = join(homedir(), "Library", "LaunchAgents");
  mkdirSync(launchAgents, { recursive: true, mode: 0o755 });
  if (lstatSync(launchAgents).isSymbolicLink()) throw new Error("The user LaunchAgents directory must not be a symbolic link.");
  mkdirSync(config.homeDir, { recursive: true, mode: 0o700 });
  chmodSync(config.homeDir, 0o700);

  const binDirectory = join(config.homeDir, "bin");
  mkdirSync(binDirectory, { recursive: true, mode: 0o700 });
  if (lstatSync(binDirectory).isSymbolicLink()) throw new Error("The Agent bin directory must not be a symbolic link.");
  const launcherPath = join(binDirectory, "Agent");
  if (existsSync(launcherPath) && lstatSync(launcherPath).isSymbolicLink()) {
    throw new Error("The Agent Telegram launcher must not be a symbolic link.");
  }
  const launcherTemporary = `${launcherPath}.${process.pid}.tmp`;
  writeFileSync(launcherTemporary, renderTelegramGatewayLauncher(process.execPath, serviceEntry), { mode: 0o700 });
  renameSync(launcherTemporary, launcherPath);
  chmodSync(launcherPath, 0o700);

  const plistPath = join(launchAgents, `${TELEGRAM_SERVICE_LABEL}.plist`);
  if (existsSync(plistPath) && lstatSync(plistPath).isSymbolicLink()) {
    throw new Error("The Agent Telegram LaunchAgent must not be a symbolic link.");
  }
  const temporary = `${plistPath}.${process.pid}.tmp`;
  const plist = renderTelegramLaunchAgent({
    launcherPath,
    workingDirectory: resolve(dirname(serviceEntry), "../.."),
    homeDir: config.homeDir,
    codexCommand: executablePath(config.codexCommand),
    ...(process.env.PATH ? { path: process.env.PATH } : {}),
  });
  writeFileSync(temporary, plist, { mode: 0o600 });
  renameSync(temporary, plistPath);
  chmodSync(plistPath, 0o600);

  const domain = `gui/${process.getuid()}`;
  const service = `${domain}/${TELEGRAM_SERVICE_LABEL}`;
  try {
    execFileSync("/bin/launchctl", ["bootout", service], { stdio: "ignore" });
  } catch {
    // The service is not loaded on first setup.
  }
  await waitForServiceUnload(service);
  try {
    execFileSync("/bin/launchctl", ["bootstrap", domain, plistPath], { stdio: "ignore" });
    execFileSync("/bin/launchctl", ["kickstart", "-k", service], { stdio: "ignore" });
  } catch (cause) {
    throw new Error(`Agent could not start the Telegram background service: ${cause instanceof Error ? cause.message : String(cause)}`);
  }
}
