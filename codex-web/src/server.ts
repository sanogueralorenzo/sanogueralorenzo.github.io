import { createServer, type IncomingMessage, type ServerResponse } from "node:http";
import { createReadStream } from "node:fs";
import { mkdir } from "node:fs/promises";
import { extname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { CodexCli, CancelledError } from "./codex.js";
import { EventHub } from "./events.js";
import { FileStore, NotFoundError } from "./storage.js";
import type { CodexEvent, CodexSession, CreateSessionBody, MessageBody } from "./types.js";

type ActiveTurn = {
  controller: AbortController;
};

export type AppConfig = {
  host: string;
  port: number;
  dataDir: string;
  codexBin: string;
  publicDir: string;
};

const activeTurns = new Map<string, ActiveTurn>();

export async function createApp(config: AppConfig): Promise<ReturnType<typeof createServer>> {
  await mkdir(config.dataDir, { recursive: true });
  const store = new FileStore(config.dataDir);
  await store.load();
  const hub = new EventHub();
  const codex = new CodexCli(config.codexBin);

  return createServer(async (request, response) => {
    try {
      await route(request, response, { store, hub, codex, publicDir: config.publicDir });
    } catch (error) {
      if (error instanceof NotFoundError) {
        json(response, 404, { error: error.message });
        return;
      }
      json(response, 500, { error: (error as Error).message });
    }
  });
}

type RouteContext = {
  store: FileStore;
  hub: EventHub;
  codex: CodexCli;
  publicDir: string;
};

async function route(request: IncomingMessage, response: ServerResponse, context: RouteContext): Promise<void> {
  const url = new URL(request.url ?? "/", "http://localhost");
  if (request.method === "GET" && url.pathname === "/health") return json(response, 200, { status: "ok" });
  if (request.method === "GET" && url.pathname === "/api/info") return json(response, 200, await context.codex.info());
  if (request.method === "GET" && url.pathname === "/api/sessions") {
    return json(response, 200, { sessions: context.store.listSessions() });
  }
  if (request.method === "POST" && url.pathname === "/api/sessions") {
    const created = await context.store.createSession(await readJson<CreateSessionBody>(request));
    context.hub.publish(created.event);
    return json(response, 201, created.session);
  }
  const sessionMatch = /^\/api\/sessions\/([^/]+)(?:\/([^/]+))?$/.exec(url.pathname);
  if (sessionMatch) {
    const [, sessionId, action] = sessionMatch;
    if (!sessionId) return json(response, 404, { error: "Not found." });
    if (request.method === "GET" && !action) return json(response, 200, context.store.getSession(sessionId));
    if (request.method === "DELETE" && !action) return deleteSession(response, context, sessionId);
    if (request.method === "POST" && action === "messages") return postMessage(request, response, context, sessionId);
    if (request.method === "POST" && action === "cancel") return cancelTurn(response, sessionId);
    if (request.method === "GET" && action === "events") return streamEvents(request, response, context, sessionId, url);
  }
  if (request.method === "GET") return serveStatic(response, context.publicDir, url.pathname);
  json(response, 404, { error: "Not found." });
}

async function postMessage(
  request: IncomingMessage,
  response: ServerResponse,
  context: RouteContext,
  sessionId: string,
): Promise<void> {
  const session = context.store.getSession(sessionId);
  const body = await readJson<MessageBody>(request);
  const text = body.text?.trim();
  if (!text) return json(response, 400, { error: "Message text is required." });
  if (activeTurns.has(sessionId)) return json(response, 409, { error: "Session already has an active turn." });

  await publishStored(context, await context.store.appendEvent(sessionId, "message.user", { text }));
  await publishStored(context, await context.store.appendEvent(sessionId, "turn.started", { text }));
  await publishStored(context, (await context.store.updateSession(sessionId, { status: "running" })).event);

  const controller = new AbortController();
  activeTurns.set(sessionId, { controller });
  void runTurn(context, session, text, controller).finally(() => activeTurns.delete(sessionId));
  json(response, 202, { accepted: true });
}

async function runTurn(context: RouteContext, session: CodexSession, text: string, controller: AbortController): Promise<void> {
  const emit = async (event: CodexEvent): Promise<void> => publishStored(context, event);
  try {
    const result = await context.codex.runTurn(controller.signal, session, text, (type, data, raw) => {
      void context.store.appendEvent(session.id, type, data, raw).then(emit);
    });
    if (result.codexThreadId && result.codexThreadId !== session.codexThreadId) {
      await emit((await context.store.updateSession(session.id, { codexThreadId: result.codexThreadId })).event);
    }
    await emit(await context.store.appendEvent(session.id, "final.answer", { text: result.finalAnswer }));
    await emit((await context.store.updateSession(session.id, { status: "idle" })).event);
  } catch (error) {
    const cancelled = error instanceof CancelledError;
    await emit(await context.store.appendEvent(session.id, cancelled ? "turn.cancelled" : "turn.failed", {
      message: (error as Error).message,
    }));
    await emit((await context.store.updateSession(session.id, { status: cancelled ? "cancelled" : "failed" })).event);
  }
}

async function deleteSession(response: ServerResponse, context: RouteContext, sessionId: string): Promise<void> {
  activeTurns.get(sessionId)?.controller.abort();
  const event = await context.store.deleteSession(sessionId);
  context.hub.publish(event);
  json(response, 200, { deleted: true });
}

function cancelTurn(response: ServerResponse, sessionId: string): void {
  const turn = activeTurns.get(sessionId);
  if (!turn) return json(response, 409, { error: "Session has no active turn." });
  turn.controller.abort();
  json(response, 202, { cancelled: true });
}

async function streamEvents(
  request: IncomingMessage,
  response: ServerResponse,
  context: RouteContext,
  sessionId: string,
  url: URL,
): Promise<void> {
  const lastEventId = Number(request.headers["last-event-id"] ?? url.searchParams.get("after") ?? 0);
  context.store.getSession(sessionId);
  response.writeHead(200, {
    "Content-Type": "text/event-stream",
    "Cache-Control": "no-cache",
    Connection: "keep-alive",
  });
  let lastSent = Number.isFinite(lastEventId) ? lastEventId : 0;
  for (const event of await context.store.eventsAfter(sessionId, lastSent)) {
    writeSse(response, event);
    lastSent = event.id;
  }
  const unsubscribe = context.hub.subscribe(sessionId, (event) => {
    if (event.id <= lastSent) return;
    writeSse(response, event);
    lastSent = event.id;
  });
  request.on("close", unsubscribe);
}

async function publishStored(context: RouteContext, event: CodexEvent): Promise<void> {
  await context.store.save();
  context.hub.publish(event);
}

function writeSse(response: ServerResponse, event: CodexEvent): void {
  response.write(`id: ${event.id}\n`);
  response.write(`event: ${event.type}\n`);
  response.write(`data: ${JSON.stringify(event)}\n\n`);
}

async function readJson<T>(request: IncomingMessage): Promise<T> {
  const chunks: Buffer[] = [];
  for await (const chunk of request) chunks.push(Buffer.from(chunk as Buffer));
  const text = Buffer.concat(chunks).toString().trim();
  if (!text) return {} as T;
  return JSON.parse(text) as T;
}

function json(response: ServerResponse, status: number, value: unknown): void {
  response.writeHead(status, { "Content-Type": "application/json" });
  response.end(JSON.stringify(value));
}

function serveStatic(response: ServerResponse, publicDir: string, pathname: string): void {
  const safePath = pathname === "/" ? "/index.html" : pathname;
  const filePath = resolve(join(publicDir, safePath));
  if (!filePath.startsWith(resolve(publicDir))) return json(response, 403, { error: "Forbidden." });
  const stream = createReadStream(filePath);
  stream.on("error", () => {
    if (safePath !== "/index.html") {
      serveStatic(response, publicDir, "/index.html");
      return;
    }
    json(response, 404, { error: "Not found." });
  });
  response.writeHead(200, { "Content-Type": contentType(filePath) });
  stream.pipe(response);
}

function contentType(filePath: string): string {
  switch (extname(filePath)) {
    case ".css":
      return "text/css; charset=utf-8";
    case ".js":
      return "text/javascript; charset=utf-8";
    case ".svg":
      return "image/svg+xml";
    default:
      return "text/html; charset=utf-8";
  }
}

const isMain = process.argv[1] === fileURLToPath(import.meta.url);
if (isMain) {
  const root = resolve(fileURLToPath(new URL("..", import.meta.url)), "..");
  const config: AppConfig = {
    host: process.env.CODEX_WEB_HOST ?? "127.0.0.1",
    port: Number(process.env.CODEX_WEB_PORT ?? 3000),
    dataDir: process.env.CODEX_WEB_DATA_DIR ?? join(process.cwd(), ".codex-web"),
    codexBin: process.env.CODEX_BIN ?? "codex",
    publicDir: process.env.CODEX_WEB_PUBLIC_DIR ?? join(root, "public"),
  };
  const app = await createApp(config);
  app.listen(config.port, config.host, () => {
    console.log(`codex-web listening on http://${config.host}:${config.port}`);
  });
}
