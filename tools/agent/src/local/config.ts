import { homedir } from "node:os";
import { resolve } from "node:path";
import type { RuntimeConfig } from "../conversation/types.js";

export const WORK_MODEL = "gpt-6-sol";
export const UTILITY_MODEL = "gpt-6-luna";

function expandHome(value: string): string {
  return value === "~" || value.startsWith("~/")
    ? resolve(homedir(), value.slice(2))
    : resolve(value);
}

export function loadConfig(env: NodeJS.ProcessEnv = process.env): RuntimeConfig {
  const homeDir = expandHome(env.AGENT_HOME ?? "~/.agent");
  const port = Number.parseInt(env.AGENT_PORT ?? "47821", 10);
  return {
    homeDir,
    port: Number.isFinite(port) ? port : 47821,
    codexCommand: env.AGENT_CODEX_COMMAND ?? "codex",
  };
}
