#!/usr/bin/env node
import { runChat } from "../cli/chat.js";
import { setupA1R } from "../cli/setup.js";

const [command = "chat", ...args] = process.argv.slice(2);

try {
  if (command === "chat") {
    const unknown = args.filter((arg) => arg !== "--dev");
    if (unknown.length > 0) throw new Error(`Unknown chat option: ${unknown[0]}`);
    await runChat({ dev: args.includes("--dev") });
  } else if (command === "setup") {
    await setupA1R(args);
  } else if (command === "serve") {
    if (args.length > 0) throw new Error(`Unknown serve option: ${args[0]}`);
    await import("../server/main.js");
  } else if (command === "help" || command === "--help" || command === "-h") {
    if (args.length > 0) throw new Error(`Unknown help option: ${args[0]}`);
    console.log(`A1R\n\n  a1r setup                         Choose browser, headless device, or API-key setup\n  a1r setup --chatgpt               Sign in through the browser using A1R's private profile\n  a1r setup --headless              Sign in on a remote/headless device with a one-time code\n  a1r setup --api-key               Explicitly select independent Responses API mode\n  a1r chat                          Start the assistant\n  a1r chat --dev                    Start with session-safe hot reload\n  a1r serve                         Run the shared local runtime\n  a1r telegram setup                Connect Telegram and start its background gateway\n  a1r telegram setup --headless     Use headless ChatGPT setup before Telegram pairing\n  a1r telegram                      Start or repair the Telegram background gateway\n`);
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
