import { homedir } from "node:os";
import { resolve } from "node:path";
import type { RuntimeConfig } from "./types.js";

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
    host: env.AGENT_HOST ?? "127.0.0.1",
    port: Number.isFinite(port) ? port : 47821,
    models: {
      coordinator: "gpt-5.6-luna",
      bounded: "gpt-5.6-luna",
      coding: "gpt-5.6-sol",
      astra: "gpt-6-astra",
    },
    maxToolRounds: Number.parseInt(env.AGENT_MAX_TOOL_ROUNDS ?? "10", 10),
    maxHistoryMessages: Number.parseInt(env.AGENT_MAX_HISTORY ?? "40", 10),
    codexCommand: env.AGENT_CODEX_COMMAND ?? "codex",
  };
}
