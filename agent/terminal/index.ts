import { runTerminal } from "./app.ts";

if (!process.stdin.isTTY || !process.stdout.isTTY) {
  console.error("Agent needs an interactive terminal.");
  process.exitCode = 1;
} else {
  const url = new URL(process.env.AGENT_URL || "http://127.0.0.1:4180");
  if (!["http:", "https:"].includes(url.protocol)) throw new Error("AGENT_URL must use HTTP or HTTPS");
  runTerminal(url);
}
