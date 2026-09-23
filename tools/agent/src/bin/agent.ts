#!/usr/bin/env node
const [command, ...args] = process.argv.slice(2);

try {
  if (command === "serve") {
    if (args.length > 0) throw new Error(`Unknown serve option: ${args[0]}`);
    await import("../server/main.js");
  } else if (command === "web") {
    if (args.some((arg) => arg !== "--tailscale")) throw new Error(`Unknown web option: ${args.find((arg) => arg !== "--tailscale")}`);
    if (args.filter((arg) => arg === "--tailscale").length > 1) throw new Error("Use --tailscale only once.");
    process.env.AGENT_OPEN_WEB = "1";
    if (args.includes("--tailscale")) process.env.AGENT_TAILSCALE_WEB = "1";
    await import("../server/main.js");
  } else if (command === "help" || command === "--help" || command === "-h") {
    if (args.length > 0) throw new Error(`Unknown help option: ${args[0]}`);
    console.log("Agent local runtime\n\n  agent web              Launch the local Agent website\n  agent web --tailscale  Also serve on this Mac's Tailscale address\n  agent serve            Run the shared local runtime\n  agent help             Show this help");
  } else {
    throw new Error(`Unknown command: ${command ?? "(none)"}. Run agent help.`);
  }
} catch (error) {
  console.error(error instanceof Error ? error.message : String(error));
  process.exitCode = 1;
}
