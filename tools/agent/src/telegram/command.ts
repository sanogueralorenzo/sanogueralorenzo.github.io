import { setupAgent } from "../setup/cli.js";
import { loadConfig } from "../local/config.js";
import { readTelegramToken } from "./credentials.js";
import { setupTelegram } from "./pairing.js";
import { installTelegramBackgroundService } from "./service.js";

export async function runTelegramCommand(args: string[]): Promise<void> {
  if (args[0] !== undefined && args[0] !== "setup") throw new Error(`Unknown Telegram command: ${args[0]}`);
  const config = loadConfig();
  if (args[0] === "setup") {
    const setupArgs = args.slice(1);
    await setupAgent(setupArgs, setupArgs.length === 0);
    await setupTelegram();
  } else if (!readTelegramToken(config.homeDir)) {
    throw new Error("Telegram is not connected. Run `agent telegram setup`.");
  }
  await installTelegramBackgroundService(config);
  console.log("Agent Telegram is running in the background.");
}
