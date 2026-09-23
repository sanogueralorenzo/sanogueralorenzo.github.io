import { randomBytes } from "node:crypto";
import { readdirSync, readFileSync, rmSync, statSync } from "node:fs";
import { createServer, type IncomingMessage, type ServerResponse } from "node:http";
import { extname, join, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";
import type { AddressInfo } from "node:net";
import type { AgentRuntime } from "../conversation/runtime.js";
import type { Store } from "../conversation/store.js";
import { RunBusyError, RunCoordinator } from "../conversation/runs.js";
import { HOME_SESSION_ID, RUNTIME_PROTOCOL_VERSION, type RuntimeConfig, type RuntimeSnapshot, type SessionStatus } from "../conversation/types.js";
import { handleSetupRequest, type RuntimeSetup } from "../setup/http.js";
import { MAX_ATTACHMENT_BYTES, saveAttachment } from "../workspace/assets.js";
import { readPrivateJson, writePrivateFile } from "../local/files.js";
import { readBody, readJson, readTurn } from "./request.js";

function json(response: ServerResponse, status: number, body: unknown): void {
  response.writeHead(status, { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" });
  response.end(JSON.stringify(body));
}

const WEB_ROOT = fileURLToPath(new URL("../web/", import.meta.url));
const MIME_TYPES: Record<string, string> = {
  ".css": "text/css; charset=utf-8",
  ".html": "text/html; charset=utf-8",
  ".ico": "image/x-icon",
  ".js": "text/javascript; charset=utf-8",
  ".json": "application/json; charset=utf-8",
  ".svg": "image/svg+xml",
};

function waitForDrain(response: ServerResponse): Promise<void> {
  if (response.destroyed) return Promise.resolve();
  return new Promise((resolve) => {
    const done = () => {
      response.off("drain", done);
      response.off("close", done);
      resolve();
    };
    response.once("drain", done);
    response.once("close", done);
  });
}

export class RuntimeServer {
  private readonly token = randomBytes(32).toString("base64url");
  private readonly runs: RunCoordinator;
  private server = createServer(this.handle.bind(this));
  private port: number;

  constructor(
    private readonly config: RuntimeConfig,
    private readonly runtime: AgentRuntime,
    private readonly store: Store,
    private readonly setup: RuntimeSetup,
  ) {
    this.runs = new RunCoordinator(runtime, store);
    this.port = config.port;
  }

  async listen(): Promise<number> {
    await new Promise<void>((resolve, reject) => {
      this.server.once("error", reject);
      this.server.listen(this.config.port, "127.0.0.1", () => resolve());
    });
    const port = (this.server.address() as AddressInfo).port;
    this.port = port;
    writePrivateFile(join(this.config.homeDir, "runtime.json"), `${JSON.stringify({ protocolVersion: RUNTIME_PROTOCOL_VERSION, port, token: this.token, pid: process.pid })}\n`);
    return port;
  }

  async close(): Promise<void> {
    await this.runs.close();
    const closed = new Promise<void>((resolve) => this.server.close(() => resolve()));
    this.server.closeAllConnections();
    await closed;
    const path = join(this.config.homeDir, "runtime.json");
    const discovery = readPrivateJson<{ pid: number; token: string }>(path);
    if (discovery?.pid === process.pid && discovery.token === this.token) rmSync(path, { force: true });
  }

  private async handle(request: IncomingMessage, response: ServerResponse): Promise<void> {
    const url = new URL(request.url ?? "/", "http://127.0.0.1");
    if (request.method === "GET" && url.pathname === "/v1/health") return json(response, 200, { ok: true, protocolVersion: RUNTIME_PROTOCOL_VERSION, pid: process.pid });

    if (request.method === "GET" && (url.pathname === "/" || url.pathname.startsWith("/web/"))) {
      if (!this.isLocalHost(request)) return json(response, 403, { error: "local_only" });
      return this.serveWeb(url.pathname, response);
    }

    if (!this.isSameOrigin(request)) return json(response, 403, { error: "cross_origin_request" });
    const cookie = request.headers.cookie?.split(";").map((value) => value.trim()).find((value) => value.startsWith("agent_session="))?.slice("agent_session=".length);
    if (request.headers.authorization !== `Bearer ${this.token}` && cookie !== this.token) return json(response, 401, { error: "unauthorized" });

    try {
      const route = `${request.method} ${url.pathname}`;
      if (route === "POST /v1/control/quit") {
        json(response, 200, { closed: false });
        return;
      }
      if (route.startsWith("GET /v1/sessions/") && route.endsWith("/messages")) {
        const id = decodeURIComponent(url.pathname.slice("/v1/sessions/".length, -"/messages".length));
        const session = this.store.getSession(id) ?? this.store.redirectedSession(id);
        return session
          ? json(response, 200, { session, messages: this.store.getMessages(session.id) })
          : json(response, 404, { error: "session_not_found" });
      }
      if (route.startsWith("GET /v1/artifacts/")) {
        const id = decodeURIComponent(url.pathname.slice("/v1/artifacts/".length));
        if (!/^[0-9a-f-]{36}$/i.test(id)) return json(response, 404, { error: "artifact_not_found" });
        const fileName = readdirSync(join(this.config.homeDir, "artifacts")).find((name) => name.startsWith(`${id}.`));
        if (!fileName) return json(response, 404, { error: "artifact_not_found" });
        const path = join(this.config.homeDir, "artifacts", fileName);
        if (!statSync(path).isFile()) return json(response, 404, { error: "artifact_not_found" });
        const inlineName = fileName.replaceAll('"', "_").replaceAll("\\", "_");
        response.writeHead(200, {
          "content-type": this.mimeType(extname(fileName)),
          "content-disposition": `inline; filename="${inlineName}"`,
          "cache-control": "private, no-store",
          "x-content-type-options": "nosniff",
        });
        response.end(readFileSync(path));
        return;
      }
      const setupResponse = await handleSetupRequest(route, request, this.setup);
      if (setupResponse) return json(response, setupResponse.status, setupResponse.body);
      switch (route) {
        case "GET /v1/events": {
          const sessionId = url.searchParams.get("sessionId") ?? undefined;
          const runId = url.searchParams.get("runId") ?? undefined;
          const handoff = sessionId && runId ? this.store.handoffFor(runId, sessionId) : null;
          const current = sessionId ? this.store.getSession(sessionId) : null;
          const redirected = handoff
            ? this.store.getSession(handoff.targetId)
            : sessionId && !current ? this.store.redirectedSession(sessionId) : null;
          if (sessionId && !current && !redirected) return json(response, 404, { error: "session_not_found" });
          return await this.events(response, sessionId, redirected, runId, handoff?.continues ?? false);
        }
        case "POST /v1/runs": return json(response, 202, { run: this.runs.start(await readTurn(request, this.store)) });
        case "POST /v1/runs/stop": {
          const { runId } = await readJson(request);
          if (typeof runId !== "string" || !runId) throw new Error("runId is required");
          return json(response, 200, { stopped: this.runs.stop(runId) });
        }
        case "POST /v1/follow-ups": {
          const { sessionId, text, channel } = await readJson(request);
          if (typeof sessionId !== "string" || typeof text !== "string" || !text.trim()) throw new Error("Conversation and text are required.");
          return json(response, 201, { task: this.runs.queue(sessionId, text.trim(), channel === "macos" ? channel : "api") });
        }
        case "POST /v1/follow-ups/remove": {
          const { sessionId, taskId } = await readJson(request);
          if (typeof sessionId !== "string" || typeof taskId !== "string") throw new Error("Conversation and follow-up are required.");
          return json(response, 200, { task: this.runs.removeQueued(sessionId, taskId) });
        }
        case "POST /v1/follow-ups/steer": {
          const { sessionId, taskId, runId } = await readJson(request);
          if (typeof sessionId !== "string" || typeof taskId !== "string" || typeof runId !== "string") throw new Error("Conversation, follow-up, and run are required.");
          return json(response, 200, { steered: await this.runs.steerQueued(sessionId, taskId, runId) });
        }
        case "GET /v1/sessions": return json(response, 200, { sessions: this.sessionStatuses(), homeEntries: this.store.home.entries(-1) });
        case "POST /v1/sessions": {
          const { cwd } = await readJson(request);
          const session = this.runtime.openSession({ fresh: true, ...(typeof cwd === "string" ? { cwd } : {}) });
          return json(response, 201, { session });
        }
        case "POST /v1/sessions/auto": {
          const { cwd, preferredSessionId } = await readJson(request);
          const session = this.runtime.openSession({
            ...(typeof cwd === "string" ? { cwd } : {}),
            ...(typeof preferredSessionId === "string" ? { preferredSessionId } : {}),
          });
          return json(response, 200, { session });
        }
        case "POST /v1/attachments": {
          const header = request.headers["x-agent-filename"];
          const name = Array.isArray(header) ? header[0] : header;
          if (!name) throw new Error("x-agent-filename is required");
          const attachment = saveAttachment(this.config.homeDir, this.store, {
            name: decodeURIComponent(name),
            mimeType: String(request.headers["content-type"] ?? "application/octet-stream").split(";", 1)[0]!.trim(),
            data: await readBody(request, MAX_ATTACHMENT_BYTES),
          });
          const { path: _path, ...visible } = attachment;
          return json(response, 201, visible);
        }
        default: return json(response, 404, { error: "not_found" });
      }
    } catch (error) {
      const status = error instanceof RunBusyError ? 409 : 400;
      const detail = error instanceof RunBusyError
        ? { error: "busy", run: error.run }
        : { error: error instanceof Error ? error.message : String(error) };
      if (!response.headersSent) json(response, status, detail);
      else response.end();
    }
  }

  private isLocalHost(request: IncomingMessage): boolean {
    const host = request.headers.host?.toLowerCase();
    return host === `127.0.0.1:${this.port}` || host === `localhost:${this.port}`;
  }

  private isSameOrigin(request: IncomingMessage): boolean {
    const origin = request.headers.origin;
    if (!origin) return true;
    try { return new URL(origin).host.toLowerCase() === request.headers.host?.toLowerCase(); }
    catch { return false; }
  }

  private serveWeb(pathname: string, response: ServerResponse): void {
    const relativePath = pathname === "/" ? "index.html" : decodeURIComponent(pathname.slice("/web/".length));
    const path = resolve(WEB_ROOT, relativePath);
    if (path !== WEB_ROOT && !path.startsWith(`${resolve(WEB_ROOT)}${sep}`)) return json(response, 404, { error: "not_found" });
    try {
      const body = readFileSync(path);
      response.writeHead(200, {
        "content-type": MIME_TYPES[extname(path)] ?? "application/octet-stream",
        "cache-control": "no-store",
        "content-security-policy": "default-src 'self'; img-src 'self' data: blob:; media-src 'self' blob:; style-src 'self' 'unsafe-inline'; script-src 'self'; connect-src 'self'; object-src 'none'; base-uri 'none'; frame-ancestors 'none'",
        "referrer-policy": "no-referrer",
        "x-content-type-options": "nosniff",
        ...(pathname === "/" ? { "set-cookie": `agent_session=${this.token}; HttpOnly; SameSite=Strict; Path=/` } : {}),
      });
      response.end(body);
    } catch {
      json(response, 404, { error: "not_found" });
    }
  }

  private mimeType(extension: string): string {
    const known: Record<string, string> = {
      ".gif": "image/gif", ".jpeg": "image/jpeg", ".jpg": "image/jpeg", ".pdf": "application/pdf",
      ".png": "image/png", ".svg": "image/svg+xml", ".txt": "text/plain; charset=utf-8", ".webp": "image/webp",
    };
    return known[extension.toLowerCase()] ?? "application/octet-stream";
  }

  private async events(
    response: ServerResponse,
    sessionId?: string,
    redirected?: ReturnType<Store["redirectedSession"]>,
    runId?: string,
    continues = false,
  ): Promise<void> {
    const controller = new AbortController();
    response.once("close", () => controller.abort());
    response.writeHead(200, {
      "content-type": "text/event-stream; charset=utf-8",
      "cache-control": "no-cache, no-transform",
      connection: "keep-alive",
      "x-accel-buffering": "no",
      "x-agent-stream": "snapshot",
    });
    response.flushHeaders();
    response.write(": connected\n\n");
    if (redirected && sessionId) {
      response.end(`data: ${JSON.stringify({ sessionId, runId: runId ?? "", event: { type: "navigate", session: redirected, url: `agent://sessions/${redirected.id}`, continues } })}\n\n`);
      return;
    }
    try {
      for await (const event of this.runs.events(controller.signal, () => response.destroy(), () => this.snapshot(sessionId), sessionId)) {
        const frame = `data: ${JSON.stringify(event)}\n\n`;
        if (!response.write(frame)) await waitForDrain(response);
      }
    } finally {
      response.end();
    }
  }

  private snapshot(sessionId?: string): RuntimeSnapshot {
    const session = sessionId ? this.store.getSession(sessionId) : this.store.latestSession();
    const sessions = this.sessionStatuses();
    return {
      sessions,
      homeEntries: this.store.home.entries(-1),
      queuedTasks: session && session.id !== HOME_SESSION_ID ? this.store.home.queuedTasks(session.id) : [],
      transcript: session ? { session, messages: this.store.getMessages(session.id) } : null,
      activeRuns: this.runs.activeSnapshots(sessionId),
      lastRuns: (sessionId ? [session].filter((value): value is NonNullable<typeof value> => Boolean(value)) : sessions)
        .map((item) => this.store.latestRun(item.id))
        .filter((run): run is NonNullable<typeof run> => Boolean(run))
        .map(({ id, sessionId: runSessionId, state }) => ({ id, sessionId: runSessionId, state })),
    };
  }

  private sessionStatuses(): SessionStatus[] {
    const active = new Map(this.runs.activeInfos().map((run) => [run.sessionId, run.id]));
    return this.store.listSessions().map((session) => ({ ...session, activeRunId: active.get(session.id) ?? null }));
  }
}
