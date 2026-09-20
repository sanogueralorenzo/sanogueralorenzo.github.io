#!/usr/bin/env node
import { runChat } from "../cli/chat.js";
import { setupAgent } from "../cli/setup.js";

const [command = "chat", ...args] = process.argv.slice(2);

try {
  if (command === "chat") {
    const unknown = args.filter((arg) => arg !== "--dev");
    if (unknown.length > 0) throw new Error(`Unknown chat option: ${unknown[0]}`);
    await runChat({ dev: args.includes("--dev") });
  } else if (command === "setup") {
    await setupAgent(args);
  } else if (command === "serve") {
    if (args.length > 0) throw new Error(`Unknown serve option: ${args[0]}`);
    await import("../server/main.js");
  } else if (command === "help" || command === "--help" || command === "-h") {
    if (args.length > 0) throw new Error(`Unknown help option: ${args[0]}`);
    console.log(`Agent\n\n  agent setup                         Choose browser, headless device, or API-key setup\n  agent setup --chatgpt               Sign in through the browser using Agent's private profile\n  agent setup --headless              Sign in on a remote/headless device with a one-time code\n  agent setup --api-key               Connect an OpenAI API key through Agent's private profile\n  agent chat                          Start the assistant\n  agent chat --dev                    Start with session-safe hot reload\n  agent serve                         Run the shared local runtime\n  agent telegram setup                Connect Telegram and start its background gateway\n  agent telegram setup --headless     Use headless ChatGPT setup before Telegram pairing\n  agent telegram                      Start or repair the Telegram background gateway\n`);
  } else if (command === "telegram") {
    const { runTelegramCommand } = await import("../telegram/command.js");
    await runTelegramCommand(args);
  } else {
    throw new Error(`Unknown command: ${command}. Run agent help.`);
  }
} catch (error) {
  console.error(error instanceof Error ? error.message : String(error));
  process.exitCode = 1;
}
