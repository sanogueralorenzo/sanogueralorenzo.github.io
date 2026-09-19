import { homedir } from "node:os";
import { resolve } from "node:path";
import type { RuntimeConfig } from "./types.js";

function expandHome(value: string): string {
  return value === "~" || value.startsWith("~/")
    ? resolve(homedir(), value.slice(2))
    : resolve(value);
}

export function loadConfig(env: NodeJS.ProcessEnv = process.env): RuntimeConfig {
  const homeDir = expandHome(env.A1R_HOME ?? "~/.a1r");
  const port = Number.parseInt(env.A1R_PORT ?? "47821", 10);
  return {
    homeDir,
    host: env.A1R_HOST ?? "127.0.0.1",
    port: Number.isFinite(port) ? port : 47821,
    models: {
      fast: env.A1R_MODEL_FAST ?? "gpt-5.6-luna",
      standard: env.A1R_MODEL_STANDARD ?? "gpt-5.6-terra",
      deep: env.A1R_MODEL_DEEP ?? "gpt-6-astra",
    },
    maxToolRounds: Number.parseInt(env.A1R_MAX_TOOL_ROUNDS ?? "10", 10),
    maxHistoryMessages: Number.parseInt(env.A1R_MAX_HISTORY ?? "40", 10),
    ...(env.TELEGRAM_BOT_TOKEN ? { telegramToken: env.TELEGRAM_BOT_TOKEN } : {}),
    ...(env.A1R_TELEGRAM_OWNER_ID ? { telegramOwnerId: env.A1R_TELEGRAM_OWNER_ID } : {}),
  };
}
