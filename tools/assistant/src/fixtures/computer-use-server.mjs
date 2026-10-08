import { createInterface } from "node:readline";
import { appendFileSync } from "node:fs";
import { spawn } from "node:child_process";

const log = process.env.ASSISTANT_MCP_TEST_LOG;
const mode = process.env.ASSISTANT_MCP_TEST_MODE;
const record = value => appendFileSync(log, JSON.stringify(value) + "\n");
const send = value => process.stdout.write(JSON.stringify({ jsonrpc: "2.0", ...value }) + "\n");
const reply = (id, result) => send({ id, result });
let initialized = false;
let calls = 0;
let approval;
record({ event: "started", pid: process.pid });
const lines = createInterface({ input: process.stdin });
lines.on("line", line => {
  const message = JSON.parse(line);
  record(message);
  if (message.method === "initialize") {
    if (mode === "stall-initialize") return;
    if (mode === "bad-initialize") { send({ id: message.id, error: { code: -32603, message: "Initialization failed" } }); return; }
    reply(message.id, { protocolVersion: "2024-11-05", capabilities: { tools: {} }, serverInfo: { name: "test-computer-use", version: "1" } });
    return;
  }
  if (message.method === "notifications/initialized") { initialized = true; return; }
  if (message.id === "approval" && message.result) { reply(approval, { content: [{ type: "text", text: JSON.stringify(message.result) }] }); return; }
  if (message.method !== "tools/call") return;
  if (!initialized || message.params.name !== "js") { send({ id: message.id, error: { code: -32603, message: "Wrong initialization or tool" } }); return; }
  calls++;
  const args = message.params.arguments;
  switch (args.code) {
    case "wait": return;
    case "exit": process.exit(7); return;
    case "approve": approval = message.id; send({ id: "approval", method: "elicitation/create", params: { message: "Allow test", requestedSchema: { type: "object", properties: {} } } }); return;
    case "args": reply(message.id, { content: [{ type: "text", text: JSON.stringify(args) }] }); return;
    case "empty": reply(message.id, { content: [] }); return;
    case "structured": reply(message.id, { structuredContent: { result: "structured" } }); return;
    case "error": reply(message.id, { isError: true, content: [{ type: "text", text: "Script failed" }] }); return;
    case "rpc-error": send({ id: message.id, error: { code: -32603, message: "RPC failed" } }); return;
    case "media": reply(message.id, { content: [
      { type: "text", text: "Image follows" }, { type: "image", mimeType: "image/png", data: "aW1hZ2U=" },
      { type: "resource", resource: { uri: "test:text", text: "Embedded text" } },
      { type: "resource", resource: { uri: "test:image", mimeType: "image/png", blob: "ZW1iZWRkZWQ=" } },
    ] }); return;
    case "child": {
      const child = spawn(process.execPath, ["-e", "setInterval(() => {}, 1000)"], { stdio: "ignore" });
      reply(message.id, { content: [{ type: "text", text: JSON.stringify({ pid: process.pid, childPid: child.pid }) }] }); return;
    }
    default: {
      const result = { content: [{ type: "text", text: JSON.stringify({ pid: process.pid, calls }) }] };
      if (args.code === "delayed") setTimeout(() => reply(message.id, result), 30);
      else reply(message.id, result);
    }
  }
});
if (mode === "stubborn") { process.on("SIGTERM", () => {}); setInterval(() => {}, 1000); }
lines.on("close", () => { if (mode !== "stubborn") process.exit(0); });
