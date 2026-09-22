import { randomBytes } from "node:crypto";
import { rmSync } from "node:fs";
import { createServer, type IncomingMessage, type ServerResponse } from "node:http";
import { join } from "node:path";
import type { AddressInfo } from "node:net";
import type { AgentRuntime } from "../conversation/runtime.js";
import type { Store } from "../conversation/store.js";
import { MAX_EVENT_BUFFER_BYTES, RunBusyError, RunCoordinator } from "../conversation/runs.js";
import { RUNTIME_PROTOCOL_VERSION, type Channel, type RuntimeConfig, type TurnRequest } from "../conversation/types.js";
import type { AgentSetupService } from "../setup/service.js";
import { MAX_ATTACHMENT_BYTES, saveAttachment } from "../workspace/assets.js";
import { readPrivateJson, writePrivateFile } from "../local/files.js";

export type RuntimeSetup = Pick<AgentSetupService,
  "status" | "connectApiKey" | "startCodexLogin" | "waitForCodexLogin">;

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

  constructor(
    private readonly config: RuntimeConfig,
    private readonly runtime: AgentRuntime,
    private readonly store: Store,
    private readonly setup: RuntimeSetup,
  ) {
    this.runs = new RunCoordinator(runtime);
  }

  async listen(): Promise<number> {
    await new Promise<void>((resolve, reject) => {
      this.server.once("error", reject);
      this.server.listen(this.config.port, "127.0.0.1", () => resolve());
    });
    const port = (this.server.address() as AddressInfo).port;
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
    if (request.headers.authorization !== `Bearer ${this.token}`) return json(response, 401, { error: "unauthorized" });

    try {
      const route = `${request.method} ${url.pathname}`;
      if (route.startsWith("GET /v1/sessions/") && route.endsWith("/messages")) {
        const id = decodeURIComponent(url.pathname.slice("/v1/sessions/".length, -"/messages".length));
        const session = this.store.getSession(id);
        return session
          ? json(response, 200, { session, messages: this.store.getMessages(id) })
          : json(response, 404, { error: "session_not_found" });
      }
      if (route.startsWith("POST /v1/setup/codex/login/") && route.endsWith("/wait")) {
        const loginId = decodeURIComponent(url.pathname.slice("/v1/setup/codex/login/".length, -"/wait".length));
        if (!loginId) throw new Error("login id is required");
        return json(response, 200, await this.setup.waitForCodexLogin(loginId));
      }
      switch (route) {
        case "GET /v1/events": return await this.events(response);
        case "POST /v1/runs": return json(response, 202, { run: this.runs.start(await this.turn(request)) });
        case "POST /v1/runs/stop": return json(response, 200, { stopped: this.runs.stop() });
        case "GET /v1/sessions": return json(response, 200, { sessions: this.store.listSessions() });
        case "GET /v1/setup": return json(response, 200, await this.setup.status());
        case "POST /v1/setup/openai": {
          const { apiKey } = await readJson(request);
          const key = typeof apiKey === "string" ? apiKey.trim() : "";
          if (!key.startsWith("sk-")) throw new Error("That does not look like an OpenAI API key.");
          await this.setup.connectApiKey(key);
          return json(response, 200, { connected: true });
        }
        case "POST /v1/setup/codex/login": {
          const { mode } = await readJson(request);
          if (mode !== "browser" && mode !== "headless") throw new Error("login mode must be browser or headless");
          return json(response, 200, await this.setup.startCodexLogin(mode));
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

  private async turn(request: IncomingMessage): Promise<TurnRequest> {
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
    const channel = body.channel as Channel;
    if (channel !== "telegram" && channel !== "macos" && channel !== "cli" && channel !== "api") throw new Error("channel must be cli, telegram, macos, or api");
    return {
      text,
      ...(attachmentIds.length ? { attachmentIds, attachments: attachments.filter((attachment) => attachment !== null) } : {}),
      ...(typeof body.cwd === "string" ? { cwd: body.cwd } : {}),
      ...(typeof body.sessionId === "string" ? { sessionId: body.sessionId } : {}),
      ...(body.fresh === true ? { fresh: true } : {}),
      channel,
    };
  }

  private async events(response: ServerResponse): Promise<void> {
    const controller = new AbortController();
    response.once("close", () => controller.abort());
    response.writeHead(200, {
      "content-type": "text/event-stream; charset=utf-8",
      "cache-control": "no-cache, no-transform",
      connection: "keep-alive",
      "x-accel-buffering": "no",
    });
    response.flushHeaders();
    response.write(": connected\n\n");
    try {
      for await (const event of this.runs.events(controller.signal, () => response.destroy())) {
        const frame = `data: ${JSON.stringify(event)}\n\n`;
        if (Buffer.byteLength(frame) > MAX_EVENT_BUFFER_BYTES) {
          response.destroy();
          break;
        }
        if (!response.write(frame)) await waitForDrain(response);
      }
    } finally {
      response.end();
    }
  }
}
