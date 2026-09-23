#!/usr/bin/env node
const [command, ...args] = process.argv.slice(2);

try {
  if (command === "serve") {
    if (args.length > 0) throw new Error(`Unknown serve option: ${args[0]}`);
    await import("../server/main.js");
  } else if (command === "help" || command === "--help" || command === "-h") {
    if (args.length > 0) throw new Error(`Unknown help option: ${args[0]}`);
    console.log("Agent local runtime\n\n  agent serve    Run the shared local runtime\n  agent help     Show this help");
  } else {
    throw new Error(`Unknown command: ${command ?? "(none)"}. Run agent help.`);
  }
} catch (error) {
  console.error(error instanceof Error ? error.message : String(error));
  process.exitCode = 1;
}
