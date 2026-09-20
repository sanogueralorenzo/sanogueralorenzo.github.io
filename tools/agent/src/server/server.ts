import { randomBytes } from "node:crypto";
import { unlinkSync } from "node:fs";
import { createServer, type IncomingMessage, type ServerResponse } from "node:http";
import { join } from "node:path";
import type { AddressInfo } from "node:net";
import type { AgentRuntime } from "../core/runtime.js";
import { MAX_HISTORY_MESSAGES } from "../core/config.js";
import type { Store } from "../core/store.js";
import type { RuntimeConfig, RuntimeEvent, TurnRequest } from "../core/types.js";
import type { BackendSetupService } from "../setup/service.js";
import { MAX_ATTACHMENT_BYTES, saveAttachment } from "../core/assets.js";
import { readPrivateJson, writePrivateFile } from "../core/files.js";

interface Discovery {
  protocolVersion: 1;
  port: number;
  token: string;
  pid: number;
}

export type RuntimeSetup = Pick<BackendSetupService,
  "status" | "setOpenAIKey" | "selectBackend" | "startCodexLogin" | "codexLoginStatus" | "cancelCodexLogin">;

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
  private restarting = false;

  constructor(
    private readonly config: RuntimeConfig,
    private readonly runtime: AgentRuntime,
    private readonly store: Store,
    private readonly setup: RuntimeSetup,
    private readonly onRestart?: () => void,
  ) {}

  async listen(): Promise<number> {
    await new Promise<void>((resolve, reject) => {
      this.server.once("error", reject);
      this.server.listen(this.config.port, this.config.host, () => resolve());
    });
    const port = (this.server.address() as AddressInfo).port;
    this.writeDiscovery(port);
    return port;
  }

  async close(): Promise<void> {
    for (const controller of this.controllers.values()) controller.abort();
    await new Promise<void>((resolve) => this.server.close(() => resolve()));
    const path = join(this.config.homeDir, "runtime.json");
    try {
      const discovery = readPrivateJson<Discovery>(path);
      if (discovery?.pid === process.pid && discovery.token === this.token) unlinkSync(path);
    } catch {
      // A replacement runtime may already own discovery.
    }
  }

  private writeDiscovery(port: number): void {
    const path = join(this.config.homeDir, "runtime.json");
    const discovery: Discovery = { protocolVersion: 1, port, token: this.token, pid: process.pid };
    writePrivateFile(path, `${JSON.stringify(discovery)}\n`);
  }

  private authorized(request: IncomingMessage): boolean {
    return request.headers.authorization === `Bearer ${this.token}`;
  }

  private async handle(request: IncomingMessage, response: ServerResponse): Promise<void> {
    const url = new URL(request.url ?? "/", `http://${this.config.host}`);
    if (request.method === "GET" && url.pathname === "/v1/health") {
      json(response, 200, { ok: true, protocolVersion: 1, pid: process.pid });
      return;
    }
    if (!this.authorized(request)) {
      json(response, 401, { error: "unauthorized" });
      return;
    }

    try {
      if (request.method === "GET" && url.pathname === "/v1/sessions") {
        json(response, 200, { sessions: this.store.listSessions() });
        return;
      }
      if (request.method === "GET" && url.pathname.startsWith("/v1/sessions/") && url.pathname.endsWith("/messages")) {
        const id = decodeURIComponent(url.pathname.slice("/v1/sessions/".length, -"/messages".length));
        const session = this.store.getSession(id);
        if (!session) {
          json(response, 404, { error: "session_not_found" });
          return;
        }
        json(response, 200, { session, messages: this.store.getMessages(id, MAX_HISTORY_MESSAGES) });
        return;
      }
      if (request.method === "GET" && url.pathname === "/v1/setup") {
        json(response, 200, await this.setup.status());
        return;
      }
      if (request.method === "POST" && url.pathname === "/v1/setup/openai") {
        const body = await readJson(request);
        const key = typeof body.apiKey === "string" ? body.apiKey.trim() : "";
        if (!key.startsWith("sk-")) throw new Error("That does not look like an OpenAI API key.");
        await this.setup.setOpenAIKey(key);
        json(response, 200, { connected: true });
        return;
      }
      if (request.method === "POST" && url.pathname === "/v1/setup/backend") {
        const body = await readJson(request);
        const backend = body.backend;
        if (backend !== "codex" && backend !== "responses") throw new Error("backend must be codex or responses");
        await this.setup.selectBackend(backend);
        json(response, 200, { connected: true, backend });
        return;
      }
      if (request.method === "POST" && url.pathname === "/v1/setup/codex/login") {
        const body = await readJson(request);
        const mode = body.mode;
        if (mode !== "browser" && mode !== "headless") throw new Error("login mode must be browser or headless");
        json(response, 200, await this.setup.startCodexLogin(mode));
        return;
      }
      if (request.method === "GET" && url.pathname.startsWith("/v1/setup/codex/login/")) {
        const loginId = decodeURIComponent(url.pathname.slice("/v1/setup/codex/login/".length));
        json(response, 200, await this.setup.codexLoginStatus(loginId));
        return;
      }
      if (request.method === "POST" && url.pathname.startsWith("/v1/setup/codex/login/") && url.pathname.endsWith("/cancel")) {
        const loginId = decodeURIComponent(url.pathname.slice("/v1/setup/codex/login/".length, -"/cancel".length));
        if (!loginId) throw new Error("login id is required");
        await this.setup.cancelCodexLogin(loginId);
        json(response, 200, { cancelled: true });
        return;
      }
      if (request.method === "POST" && url.pathname === "/v1/cancel") {
        const body = await readJson(request);
        const requestId = typeof body.requestId === "string" ? body.requestId.trim() : "";
        if (!requestId) throw new Error("requestId is required");
        const controller = this.controllers.get(requestId);
        controller?.abort();
        json(response, 200, { cancelled: Boolean(controller) });
        return;
      }
      if (request.method === "POST" && url.pathname === "/v1/runtime/restart") {
        if (!this.onRestart) {
          json(response, 501, { error: "restart_unavailable" });
          return;
        }
        if (this.controllers.size > 0) {
          json(response, 409, { error: "runtime_busy" });
          return;
        }
        this.restarting = true;
        json(response, 202, { restarting: true });
        setImmediate(this.onRestart);
        return;
      }
      if (request.method === "POST" && url.pathname === "/v1/attachments") {
        const encodedName = request.headers["x-agent-filename"];
        const rawName = Array.isArray(encodedName) ? encodedName[0] : encodedName;
        if (!rawName) throw new Error("x-agent-filename is required");
        const name = decodeURIComponent(rawName);
        const mimeType = String(request.headers["content-type"] ?? "application/octet-stream").split(";", 1)[0]!.trim();
        const attachment = saveAttachment(this.config.homeDir, this.store, {
          name,
          mimeType,
          data: await readBody(request, MAX_ATTACHMENT_BYTES),
        });
        json(response, 201, {
          id: attachment.id,
          kind: attachment.kind,
          name: attachment.name,
          mimeType: attachment.mimeType,
          size: attachment.size,
        });
        return;
      }
      if (request.method === "POST" && url.pathname === "/v1/chat") {
        if (this.restarting) {
          json(response, 503, { error: "runtime_restarting" });
          return;
        }
        await this.chat(request, response);
        return;
      }
      json(response, 404, { error: "not_found" });
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
    )) {
      json(response, 400, { error: "attachmentIds must contain at most 8 IDs" });
      return;
    }
    const attachmentIds = (body.attachmentIds ?? []) as string[];
    if (!text && attachmentIds.length === 0) {
      json(response, 400, { error: "text or an attachment is required" });
      return;
    }
    const attachments = attachmentIds.map((id) => this.store.getAttachment(id));
    if (attachments.some((attachment) => !attachment)) {
      json(response, 400, { error: "attachment not found" });
      return;
    }
    const requestId = typeof body.requestId === "string" ? body.requestId.trim() : "";
    if (!requestId) {
      json(response, 400, { error: "requestId is required" });
      return;
    }
    const channel = body.channel;
    if (channel !== "telegram" && channel !== "macos" && channel !== "cli" && channel !== "api") {
      json(response, 400, { error: "channel must be cli, telegram, macos, or api" });
      return;
    }
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
    let sequence = 0;
    const send = (event: RuntimeEvent) => {
      sequence += 1;
      response.write(`id: ${sequence}\nevent: ${event.type}\ndata: ${JSON.stringify({ v: 1, seq: sequence, requestId, event })}\n\n`);
    };
    const turn: TurnRequest = {
      text,
      ...(attachmentIds.length ? { attachmentIds, attachments: attachments.filter((attachment) => attachment !== null) } : {}),
      ...(typeof body.cwd === "string" ? { cwd: body.cwd } : {}),
      ...(typeof body.sessionId === "string" ? { sessionId: body.sessionId } : {}),
      ...(body.fresh === true ? { fresh: true } : {}),
      channel,
      ...(typeof body.senderId === "string" ? { senderId: body.senderId } : {}),
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
