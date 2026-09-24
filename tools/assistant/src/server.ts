import { createServer, type IncomingMessage, type ServerResponse } from "node:http";
import { readFileSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { Assistant } from "./assistant.ts";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const workspace = resolve(process.env.ASSISTANT_WORKSPACE || process.cwd());
const dataDir = resolve(process.env.ASSISTANT_DATA_DIR || join(process.env.XDG_DATA_HOME || join(homedir(), ".local", "share"), "assistant"));
const app = new Assistant(dataDir, workspace, Number(process.env.ASSISTANT_CONCURRENCY || 4));
const port = Number(process.env.ASSISTANT_PORT || 4180);
const clients = new Set<ServerResponse>();
app.subscribe((event) => {
  const payload = `data: ${JSON.stringify(event)}\n\n`;
  for (const client of clients) client.write(payload);
});

function json(res: ServerResponse, status: number, value: unknown) {
  res.writeHead(status, { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" });
  res.end(JSON.stringify(value));
}
async function body(req: IncomingMessage) {
  let text = "";
  for await (const chunk of req) {
    text += chunk.toString();
    if (text.length > 100_000) throw new Error("Request too large");
  }
  return JSON.parse(text || "{}") as Record<string, unknown>;
}
function input(value: unknown) {
  if (typeof value !== "string" || !value.trim() || value.length > 30_000) throw new Error("Enter a message under 30,000 characters");
  return value.trim();
}
const assets: Record<string, [string, string]> = {
  "/": ["index.html", "text/html"], "/app.js": ["app.js", "text/javascript"],
  "/app.css": ["app.css", "text/css"], "/view.js": ["view.js", "text/javascript"],
};

const server = createServer(async (req, res) => {
  try {
    const url = new URL(req.url || "/", `http://${req.headers.host || "localhost"}`);
    if (req.method === "GET" && url.pathname === "/api/events") {
      res.writeHead(200, { "content-type": "text/event-stream", "cache-control": "no-cache", connection: "keep-alive", "x-accel-buffering": "no" });
      clients.add(res);
      res.write(`data: ${JSON.stringify({ type: "snapshot", data: app.snapshot() })}\n\n`);
      req.on("close", () => clients.delete(res));
      return;
    }
    if (req.method === "GET" && url.pathname === "/api/state") return json(res, 200, app.snapshot());
    const sessionMatch = url.pathname.match(/^\/api\/sessions\/([a-f0-9-]+)$/);
    if (req.method === "GET" && sessionMatch) return json(res, 200, app.transcript(sessionMatch[1]));
    if (req.method === "POST") {
      const origin = req.headers.origin;
      if (origin && new URL(origin).host !== req.headers.host) return json(res, 403, { error: "Cross-origin request denied" });
      const request = await body(req);
      if (url.pathname === "/api/home") return json(res, 202, { message: app.submitHome(input(request.text), typeof request.id === "string" ? request.id : undefined) });
      if (url.pathname === "/api/turns") return json(res, 202, app.submitSession(String(request.sessionId), input(request.text), request.mode === "steer" ? "steer" : "followUp", typeof request.replyToId === "string" ? request.replyToId : undefined, typeof request.id === "string" ? request.id : undefined));
      if (url.pathname === "/api/stop") return json(res, 200, { stopped: app.stop(String(request.sessionId)) });
      if (url.pathname === "/api/resume") { app.resume(String(request.entryId)); return json(res, 202, { resumed: true }); }
      return json(res, 404, { error: "Unknown endpoint" });
    }
    const asset = assets[url.pathname];
    if (req.method === "GET" && asset) {
      res.writeHead(200, { "content-type": `${asset[1]}; charset=utf-8`, "cache-control": "no-store" });
      res.end(readFileSync(join(root, "web", asset[0])));
      return;
    }
    json(res, 404, { error: "Not found" });
  } catch (error) { json(res, 400, { error: error instanceof Error ? error.message : String(error) }); }
}).listen(port, "127.0.0.1", () => console.log(`Assistant is available at http://127.0.0.1:${port}`));
for (const signal of ["SIGINT", "SIGTERM"] as const) process.once(signal, () => {
  void app.shutdown().finally(() => {
    for (const client of clients) client.end();
    server.close(() => process.exit(0));
  });
});
