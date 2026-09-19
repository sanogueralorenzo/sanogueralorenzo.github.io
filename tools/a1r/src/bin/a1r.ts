#!/usr/bin/env node
import { runChat } from "../cli/chat.js";
import { setupOpenAI } from "../cli/setup.js";

const [command = "chat", ...args] = process.argv.slice(2);

try {
  if (command === "chat") {
    await runChat({ dev: args.includes("--dev") });
  } else if (command === "setup") {
    await setupOpenAI();
  } else if (command === "serve") {
    await import("../server/main.js");
  } else if (command === "help" || command === "--help" || command === "-h") {
    console.log(`A1R\n\n  a1r setup          Connect OpenAI\n  a1r chat           Start the assistant\n  a1r chat --dev     Start with session-safe hot reload\n  a1r serve          Run the shared local runtime\n  a1r telegram       Run the Telegram gateway\n`);
  } else if (command === "telegram") {
    const { runTelegramCommand } = await import("../telegram/command.js");
    await runTelegramCommand(args);
  } else {
    throw new Error(`Unknown command: ${command}. Run a1r help.`);
  }
} catch (error) {
  console.error(error instanceof Error ? error.message : String(error));
  process.exitCode = 1;
}
