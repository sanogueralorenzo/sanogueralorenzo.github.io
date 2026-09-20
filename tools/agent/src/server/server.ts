import { randomBytes } from "node:crypto";
import { rmSync } from "node:fs";
import { createServer, type IncomingMessage, type ServerResponse } from "node:http";
import { join } from "node:path";
import type { AddressInfo } from "node:net";
import type { AgentRuntime } from "../conversation/runtime.js";
import { MAX_HISTORY_MESSAGES } from "../local/config.js";
import type { Store } from "../conversation/store.js";
import type { RuntimeConfig, RuntimeEvent, TurnRequest } from "../conversation/types.js";
import type { BackendSetupService } from "../setup/service.js";
import { MAX_ATTACHMENT_BYTES, saveAttachment } from "../workspace/assets.js";
import { readPrivateJson, writePrivateFile } from "../local/files.js";

interface Discovery {
  protocolVersion: 1;
  port: number;
  token: string;
  pid: number;
}

export type RuntimeSetup = Pick<BackendSetupService,
  "status" | "setOpenAIKey" | "selectBackend" | "startCodexLogin" | "waitForCodexLogin">;

function json(response: ServerResponse, status: number, body: unknown): void {
  response.writeHead(status, { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" });
  response.end(JSON.stringify(body));
}

async function readBody(request: IncomingMessage, limit: number): Promise<Buffer> {
  const chunks: Buffer[] = [];
  let size = 0;
  for await (const chunk of request) {
    const buffer = Buffer.from(chunk);
    size += buffer.length;
    if (size > limit) throw new Error("Request body is too large.");
    chunks.push(buffer);
  }
  return Buffer.concat(chunks);
}

async function readJson(request: IncomingMessage): Promise<Record<string, unknown>> {
  const body = await readBody(request, 1_000_000);
  return body.length ? JSON.parse(body.toString("utf8")) as Record<string, unknown> : {};
}

export class RuntimeServer {
  private readonly token = randomBytes(32).toString("base64url");
  private readonly controllers = new Map<string, AbortController>();
  private server = createServer(this.handle.bind(this));

  constructor(
    private readonly config: RuntimeConfig,
    private readonly runtime: AgentRuntime,
    private readonly store: Store,
    private readonly setup: RuntimeSetup,
  ) {}

  async listen(): Promise<number> {
    await new Promise<void>((resolve, reject) => {
      this.server.once("error", reject);
      this.server.listen(this.config.port, "127.0.0.1", () => resolve());
    });
    const port = (this.server.address() as AddressInfo).port;
    writePrivateFile(join(this.config.homeDir, "runtime.json"), `${JSON.stringify({ protocolVersion: 1, port, token: this.token, pid: process.pid })}\n`);
    return port;
  }

  async close(): Promise<void> {
    for (const controller of this.controllers.values()) controller.abort();
    await new Promise<void>((resolve) => this.server.close(() => resolve()));
    const path = join(this.config.homeDir, "runtime.json");
    const discovery = readPrivateJson<Discovery>(path);
    if (discovery?.pid === process.pid && discovery.token === this.token) rmSync(path, { force: true });
  }

  private async handle(request: IncomingMessage, response: ServerResponse): Promise<void> {
    const url = new URL(request.url ?? "/", "http://127.0.0.1");
    if (request.method === "GET" && url.pathname === "/v1/health") return json(response, 200, { ok: true, protocolVersion: 1, pid: process.pid });
    if (request.headers.authorization !== `Bearer ${this.token}`) return json(response, 401, { error: "unauthorized" });

    try {
      const route = `${request.method} ${url.pathname}`;
      if (route.startsWith("GET /v1/sessions/") && route.endsWith("/messages")) {
        const id = decodeURIComponent(url.pathname.slice("/v1/sessions/".length, -"/messages".length));
        const session = this.store.getSession(id);
        return session
          ? json(response, 200, { session, messages: this.store.getMessages(id, MAX_HISTORY_MESSAGES) })
          : json(response, 404, { error: "session_not_found" });
      }
      if (route.startsWith("POST /v1/setup/codex/login/") && route.endsWith("/wait")) {
        const loginId = decodeURIComponent(url.pathname.slice("/v1/setup/codex/login/".length, -"/wait".length));
        if (!loginId) throw new Error("login id is required");
        return json(response, 200, await this.setup.waitForCodexLogin(loginId));
      }
      switch (route) {
        case "GET /v1/sessions": return json(response, 200, { sessions: this.store.listSessions() });
        case "GET /v1/setup": return json(response, 200, await this.setup.status());
        case "POST /v1/setup/openai": {
          const { apiKey } = await readJson(request);
          const key = typeof apiKey === "string" ? apiKey.trim() : "";
          if (!key.startsWith("sk-")) throw new Error("That does not look like an OpenAI API key.");
          await this.setup.setOpenAIKey(key);
          return json(response, 200, { connected: true });
        }
        case "POST /v1/setup/backend": {
          const { backend } = await readJson(request);
          if (backend !== "codex" && backend !== "responses") throw new Error("backend must be codex or responses");
          await this.setup.selectBackend(backend);
          return json(response, 200, { connected: true, backend });
        }
        case "POST /v1/setup/codex/login": {
          const { mode } = await readJson(request);
          if (mode !== "browser" && mode !== "headless") throw new Error("login mode must be browser or headless");
          return json(response, 200, await this.setup.startCodexLogin(mode));
        }
        case "POST /v1/cancel": {
          const { requestId } = await readJson(request);
          if (typeof requestId !== "string" || !requestId.trim()) throw new Error("requestId is required");
          const controller = this.controllers.get(requestId.trim());
          controller?.abort();
          return json(response, 200, { cancelled: Boolean(controller) });
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
        case "POST /v1/chat": return this.chat(request, response);
        default: return json(response, 404, { error: "not_found" });
      }
    } catch (error) {
      if (!response.headersSent) json(response, 400, { error: error instanceof Error ? error.message : String(error) });
      else response.end();
    }
  }

  private async chat(request: IncomingMessage, response: ServerResponse): Promise<void> {
    const body = await readJson(request);
    const text = typeof body.text === "string" ? body.text.trim() : "";
    if (body.attachmentIds !== undefined && (
      !Array.isArray(body.attachmentIds)
      || body.attachmentIds.length > 8
      || !body.attachmentIds.every((id) => typeof id === "string" && id.length > 0)
    )) throw new Error("attachmentIds must contain at most 8 IDs");
    const attachmentIds = (body.attachmentIds ?? []) as string[];
    if (!text && attachmentIds.length === 0) throw new Error("text or an attachment is required");
    const attachments = attachmentIds.map((id) => this.store.getAttachment(id));
    if (attachments.some((attachment) => !attachment)) throw new Error("attachment not found");
    const requestId = typeof body.requestId === "string" ? body.requestId.trim() : "";
    if (!requestId) throw new Error("requestId is required");
    const channel = body.channel;
    if (channel !== "telegram" && channel !== "macos" && channel !== "cli" && channel !== "api") throw new Error("channel must be cli, telegram, macos, or api");
    if (this.controllers.has(requestId)) {
      json(response, 409, { error: "request_already_running" });
      return;
    }
    const controller = new AbortController();
    this.controllers.set(requestId, controller);
    let finished = false;
    const abortDisconnected = () => { if (!finished) controller.abort(); };
    request.once("aborted", abortDisconnected);
    response.once("close", abortDisconnected);
    response.writeHead(200, {
      "content-type": "text/event-stream; charset=utf-8",
      "cache-control": "no-cache, no-transform",
      connection: "keep-alive",
      "x-accel-buffering": "no",
    });
    response.flushHeaders();
    const send = (event: RuntimeEvent) => response.write(`data: ${JSON.stringify(event)}\n\n`);
    const turn: TurnRequest = {
      text,
      ...(attachmentIds.length ? { attachmentIds, attachments: attachments.filter((attachment) => attachment !== null) } : {}),
      ...(typeof body.cwd === "string" ? { cwd: body.cwd } : {}),
      ...(typeof body.sessionId === "string" ? { sessionId: body.sessionId } : {}),
      ...(body.fresh === true ? { fresh: true } : {}),
      channel,
    };
    try {
      for await (const event of this.runtime.run(turn, { signal: controller.signal })) send(event);
    } finally {
      this.controllers.delete(requestId);
      finished = true;
      response.end();
    }
  }
}
