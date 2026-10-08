import { once } from "node:events";
import { createServer, type IncomingMessage, type ServerResponse } from "node:http";
import { readFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import type { Assistant } from "./assistant.ts";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
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
  "/message-actions.js": ["message-actions.js", "text/javascript"],
  "/prompt-suggestions.js": ["prompt-suggestions.js", "text/javascript"],
  "/queued-messages.js": ["queued-messages.js", "text/javascript"],
};

export function createAssistantServer(app: Assistant) {
  const clients = new Set<ServerResponse>();
  const server = createServer(async (req, res) => {
  try {
    const url = new URL(req.url || "/", `http://${req.headers.host || "localhost"}`);
    if (req.method === "GET" && url.pathname === "/api/events") {
      res.writeHead(200, { "content-type": "text/event-stream", "cache-control": "no-cache", connection: "keep-alive", "x-accel-buffering": "no" });
      clients.add(res);
      const controller = new AbortController();
      const watches = new Map<string, ReturnType<Assistant["watchConversation"]>>();
      const send = async (event: unknown) => {
        controller.signal.throwIfAborted();
        if (!res.write(`data: ${JSON.stringify(event)}\n\n`)) await once(res, "drain", { signal: controller.signal });
      };
      const attach = () => {
        for (const session of app.snapshot().sessions) if (!watches.has(session.id)) {
          const pending = app.watchConversation(session.id, send);
          watches.set(session.id, pending);
          void pending.then((watch) => { if (controller.signal.aborted) void watch.stop(); }, () => res.destroy());
        }
      };
      const unsubscribe = app.subscribe((event) => {
        // Home metadata is small; reconnect a stalled client with a fresh snapshot.
        if (res.writableNeedDrain) { res.destroy(); return; }
        void send(event).catch(() => res.destroy());
        attach();
      });
      res.on("close", () => {
        clients.delete(res); controller.abort(); unsubscribe();
        for (const pending of watches.values()) void pending.then((watch) => watch.stop(), () => {});
      });
      await send({ type: "snapshot", data: app.snapshot() });
      for (const activity of app.activities()) await send(activity);
      attach();
      return;
    }
    if (req.method === "GET" && url.pathname === "/api/state") return json(res, 200, app.snapshot());
    const sessionMatch = url.pathname.match(/^\/api\/sessions\/([a-f0-9-]+)$/);
    if (req.method === "GET" && sessionMatch) return json(res, 200, app.transcript(sessionMatch[1]));
    if (req.method === "POST") {
      const origin = req.headers.origin;
      if (origin && new URL(origin).host !== req.headers.host) return json(res, 403, { error: "Cross-origin request denied" });
      const request = await body(req);
      if (url.pathname === "/api/suggestions") return json(res, 200, await app.suggestion(input(request.sessionId), input(request.replyId)));
      if (url.pathname === "/api/home") return json(res, 202, { message: await app.submitHome(input(request.text), typeof request.id === "string" ? request.id : undefined) });
      if (url.pathname === "/api/turns") return json(res, 202, await app.submitSession(String(request.sessionId), input(request.text), request.mode === "steer" ? "steer" : "followUp", {
        replyToId: typeof request.replyToId === "string" ? request.replyToId : undefined,
        editOfId: typeof request.editOfId === "string" ? request.editOfId : undefined,
        id: typeof request.id === "string" ? request.id : undefined,
        reaction: request.reaction === "thumbs-up" ? "thumbs-up" : undefined,
      }));
      if (url.pathname === "/api/stop") return json(res, 200, { stopped: await app.stop(String(request.sessionId)) });
      if (url.pathname === "/api/dequeue") return json(res, 200, await app.dequeue(input(request.sessionId), input(request.turnId)));
      if (url.pathname === "/api/steer-queued") return json(res, 200, await app.steerQueued(input(request.sessionId), input(request.turnId)));
      if (url.pathname === "/api/resume") { await app.resume(String(request.entryId)); return json(res, 202, { resumed: true }); }
      return json(res, 404, { error: "Unknown endpoint" });
    }
    const asset = assets[url.pathname];
    if (req.method === "GET" && asset) {
      res.writeHead(200, { "content-type": `${asset[1]}; charset=utf-8`, "cache-control": "no-store" });
      res.end(readFileSync(join(root, "web", asset[0])));
      return;
    }
    json(res, 404, { error: "Not found" });
  } catch (error) { if (res.headersSent) { res.destroy(); return; } json(res, 400, { error: error instanceof Error ? error.message : String(error) }); }
});
  return { server, close: async () => {
    for (const client of clients) client.end();
    server.closeAllConnections();
    await new Promise<void>((resolve, reject) => server.close(error => error ? reject(error) : resolve()));
  } };
}
