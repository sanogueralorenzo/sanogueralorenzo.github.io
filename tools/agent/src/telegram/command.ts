import { setupAgent } from "../cli/setup.js";
import { loadConfig } from "../local/config.js";
import { readSecret } from "../local/credentials.js";
import { setupTelegram } from "./pairing.js";
import { installTelegramBackgroundService, requestTelegramRestart } from "./service.js";

export async function runTelegramCommand(args: string[]): Promise<void> {
  if (args[0] !== undefined && args[0] !== "setup" && args[0] !== "restart") throw new Error(`Unknown Telegram command: ${args[0]}`);
  const config = loadConfig();
  if (args[0] === "restart") {
    if (args.length > 1) throw new Error(`Unknown Telegram command: ${args.slice(1).join(" ")}`);
    requestTelegramRestart(config.homeDir);
    console.log("Telegram will restart after this response.");
    return;
  }
  if (args[0] === "setup") {
    const setupArgs = args.slice(1);
    await setupAgent(setupArgs, setupArgs.length === 0);
    await setupTelegram();
  } else if (!readSecret("telegram", config.homeDir)) {
    throw new Error("Telegram is not connected. Run `agent telegram setup`.");
  }
  await installTelegramBackgroundService(config);
  console.log("Agent Telegram is running in the background.");
}
