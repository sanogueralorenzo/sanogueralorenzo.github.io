import { accessSync, constants } from "node:fs";
import { homedir } from "node:os";
import { resolve } from "node:path";
import type { RuntimeConfig } from "../conversation/types.js";

export const UTILITY_MODEL = "gpt-6-luna";

function expandHome(value: string): string {
  return value === "~" || value.startsWith("~/")
    ? resolve(homedir(), value.slice(2))
    : resolve(value);
}

function installedCodexCommand(): string | null {
  if (process.platform !== "darwin") return null;
  const bundlePaths = [
    "/Applications/ChatGPT.app/Contents/Resources/codex",
    resolve(homedir(), "Applications/ChatGPT.app/Contents/Resources/codex"),
  ];
  for (const path of bundlePaths) {
    try {
      accessSync(path, constants.X_OK);
      return path;
    } catch {
      // Try the other standard ChatGPT.app installation location.
    }
  }
  return null;
}

export function loadConfig(env: NodeJS.ProcessEnv = process.env): RuntimeConfig {
  const homeDir = expandHome(env.AGENT_HOME ?? "~/.agent");
  const port = Number.parseInt(env.AGENT_PORT ?? "47821", 10);
  let codexCommand = env.AGENT_CODEX_COMMAND;
  if (codexCommand == null) {
    if (process.platform === "darwin") {
      codexCommand = installedCodexCommand() ?? undefined;
      if (codexCommand == null) {
        throw new Error(
          "Could not find Codex bundled with ChatGPT.app in /Applications or ~/Applications. Set AGENT_CODEX_COMMAND to an executable path to use a different installation.",
        );
      }
    } else {
      codexCommand = "codex";
    }
  }
  return {
    homeDir,
    codexHome: expandHome(env.CODEX_HOME ?? "~/.codex"),
    port: Number.isFinite(port) ? port : 47821,
    codexCommand,
  };
}
