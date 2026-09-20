import { execFileSync } from "node:child_process";
import { accessSync, chmodSync, constants, existsSync, lstatSync, mkdirSync, realpathSync, renameSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { delimiter, dirname, join, resolve } from "node:path";
import type { RuntimeConfig } from "../core/types.js";

export const TELEGRAM_SERVICE_LABEL = "dev.a1r.telegram";

interface LaunchAgentOptions {
  executable: string;
  entryPath: string;
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
  const sourceMode = options.entryPath.endsWith(".ts");
  const args = [
    options.executable,
    ...(sourceMode ? ["--import", "tsx"] : []),
    options.entryPath,
    "telegram",
    "serve",
  ];
  const environment: Array<[string, string]> = [
    ["A1R_HOME", options.homeDir],
    ["A1R_CODEX_COMMAND", options.codexCommand],
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
    "  <key>ProgramArguments</key>",
    "  <array>",
    ...args.map(stringEntry),
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

export function installTelegramBackgroundService(
  config: Pick<RuntimeConfig, "homeDir" | "codexCommand">,
  entryPath = process.argv[1],
): boolean {
  if (process.platform !== "darwin") return false;
  if (!entryPath) throw new Error("A1R could not determine its executable path for the Telegram service.");
  if (typeof process.getuid !== "function") throw new Error("A1R could not determine the current macOS user.");

  const absoluteEntry = realpathSync(resolve(entryPath));
  const launchAgents = join(homedir(), "Library", "LaunchAgents");
  mkdirSync(launchAgents, { recursive: true, mode: 0o755 });
  if (lstatSync(launchAgents).isSymbolicLink()) throw new Error("The user LaunchAgents directory must not be a symbolic link.");
  mkdirSync(config.homeDir, { recursive: true, mode: 0o700 });
  chmodSync(config.homeDir, 0o700);

  const plistPath = join(launchAgents, `${TELEGRAM_SERVICE_LABEL}.plist`);
  if (existsSync(plistPath) && lstatSync(plistPath).isSymbolicLink()) {
    throw new Error("The A1R Telegram LaunchAgent must not be a symbolic link.");
  }
  const temporary = `${plistPath}.${process.pid}.tmp`;
  const plist = renderTelegramLaunchAgent({
    executable: process.execPath,
    entryPath: absoluteEntry,
    workingDirectory: resolve(dirname(absoluteEntry), "../.."),
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
  try {
    execFileSync("/bin/launchctl", ["bootstrap", domain, plistPath], { stdio: "ignore" });
    execFileSync("/bin/launchctl", ["kickstart", "-k", service], { stdio: "ignore" });
  } catch (cause) {
    throw new Error(`A1R could not start the Telegram background service: ${cause instanceof Error ? cause.message : String(cause)}`);
  }
  return true;
}
