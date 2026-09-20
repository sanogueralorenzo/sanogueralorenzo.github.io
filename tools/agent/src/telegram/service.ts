import { execFileSync } from "node:child_process";
import { accessSync, constants, existsSync, realpathSync, rmSync } from "node:fs";
import { homedir } from "node:os";
import { delimiter, dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import type { RuntimeConfig } from "../conversation/types.js";
import { ensurePrivateDirectory, writePrivateFile } from "../local/files.js";

export const TELEGRAM_SERVICE_LABEL = "dev.agent.telegram";
const TELEGRAM_RESTART_REQUEST = "telegram.restart";

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

export function renderTelegramLaunchAgent(options: LaunchAgentOptions): string {
  const environment: Array<[string, string]> = [
    ["AGENT_HOME", options.homeDir],
    ["AGENT_CODEX_COMMAND", options.codexCommand],
  ];
  if (options.path) environment.push(["PATH", options.path]);
  const logPath = join(options.homeDir, "telegram.log");
  const variables = environment.map(([key, value]) => `    <key>${key}</key>\n    <string>${xml(value)}</string>`).join("\n");
  return `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>${TELEGRAM_SERVICE_LABEL}</string>
  <key>Program</key><string>${xml(options.launcherPath)}</string>
  <key>ProgramArguments</key><array><string>${xml(options.launcherPath)}</string></array>
  <key>WorkingDirectory</key><string>${xml(options.workingDirectory)}</string>
  <key>EnvironmentVariables</key><dict>
${variables}
  </dict>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>ProcessType</key><string>Interactive</string>
  <key>ThrottleInterval</key><integer>3</integer>
  <key>StandardOutPath</key><string>${xml(logPath)}</string>
  <key>StandardErrorPath</key><string>${xml(logPath)}</string>
</dict>
</plist>
`;
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

export function installTelegramGatewayLauncher(homeDir: string, executable: string, serviceEntry: string): string {
  const binDirectory = join(homeDir, "bin");
  ensurePrivateDirectory(binDirectory);
  const launcherPath = join(binDirectory, "agent");
  rmSync(join(binDirectory, "Agent"), { force: true });
  writePrivateFile(launcherPath, renderTelegramGatewayLauncher(executable, serviceEntry), 0o700);
  return launcherPath;
}

export function requestTelegramRestart(homeDir: string): void {
  writePrivateFile(join(homeDir, TELEGRAM_RESTART_REQUEST), "restart\n");
}

export function consumeTelegramRestart(homeDir: string): boolean {
  const path = join(homeDir, TELEGRAM_RESTART_REQUEST);
  if (!existsSync(path)) return false;
  rmSync(path);
  return true;
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
): void {
  if (process.platform !== "darwin") throw new Error("The Agent Telegram background service currently requires macOS.");
  if (typeof process.getuid !== "function") throw new Error("Agent could not determine the current macOS user.");

  const modulePath = fileURLToPath(import.meta.url);
  const sourceMode = modulePath.endsWith(".ts");
  const serviceEntry = realpathSync(join(dirname(modulePath), `main.${sourceMode ? "ts" : "js"}`));
  const launchAgents = join(homedir(), "Library", "LaunchAgents");
  ensurePrivateDirectory(config.homeDir);

  const launcherPath = installTelegramGatewayLauncher(config.homeDir, process.execPath, serviceEntry);

  const plistPath = join(launchAgents, `${TELEGRAM_SERVICE_LABEL}.plist`);
  const plist = renderTelegramLaunchAgent({
    launcherPath,
    workingDirectory: resolve(dirname(serviceEntry), "../.."),
    homeDir: config.homeDir,
    codexCommand: executablePath(config.codexCommand),
    ...(process.env.PATH ? { path: process.env.PATH } : {}),
  });
  writePrivateFile(plistPath, plist);

  const domain = `gui/${process.getuid()}`;
  const service = `${domain}/${TELEGRAM_SERVICE_LABEL}`;
  try {
    execFileSync("/bin/launchctl", ["bootout", domain, plistPath], { stdio: "ignore" });
  } catch {
    // The service is not loaded on first setup.
  }
  try {
    execFileSync("/bin/launchctl", ["bootstrap", domain, plistPath], { stdio: "ignore" });
    execFileSync("/bin/launchctl", ["kickstart", "-k", service], { stdio: "ignore" });
  } catch (cause) {
    throw new Error(`Agent could not start the Telegram background service: ${cause instanceof Error ? cause.message : String(cause)}`);
  }
}
