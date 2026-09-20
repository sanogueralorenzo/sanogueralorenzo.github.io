import { randomBytes } from "node:crypto";
import { mkdirSync, readFileSync, renameSync, unlinkSync, writeFileSync } from "node:fs";
import { createServer, type IncomingMessage, type ServerResponse } from "node:http";
import { join } from "node:path";
import type { AddressInfo } from "node:net";
import type { A1RRuntime } from "../core/runtime.js";
import type { Store } from "../core/store.js";
import type { RuntimeConfig, RuntimeEvent, TurnRequest } from "../core/types.js";
import type { BackendKind } from "../core/types.js";
import type { CodexLoginMode, CodexLoginResult, CodexLoginStart } from "../codex/protocol.js";
import type { SetupStatus } from "../setup/service.js";

interface Discovery {
  protocolVersion: 1;
  port: number;
  token: string;
  pid: number;
}

function json(response: ServerResponse, status: number, body: unknown): void {
  response.writeHead(status, { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" });
  response.end(JSON.stringify(body));
}

async function readJson(request: IncomingMessage): Promise<Record<string, unknown>> {
  const chunks: Buffer[] = [];
  let size = 0;
  for await (const chunk of request) {
    const buffer = Buffer.from(chunk);
    size += buffer.length;
    if (size > 1_000_000) throw new Error("Request body is too large.");
    chunks.push(buffer);
  }
  if (chunks.length === 0) return {};
  return JSON.parse(Buffer.concat(chunks).toString("utf8")) as Record<string, unknown>;
}

export class RuntimeServer {
  private readonly token = randomBytes(32).toString("base64url");
  private readonly controllers = new Map<string, AbortController>();
  private server = createServer(this.handle.bind(this));

  constructor(
    private readonly config: RuntimeConfig,
    private readonly runtime: A1RRuntime,
    private readonly store: Store,
    private readonly setup?: {
      status: () => Promise<SetupStatus>;
      setOpenAIKey: (key: string) => Promise<void>;
      selectBackend: (backend: BackendKind) => Promise<void>;
      startCodexLogin: (mode: CodexLoginMode) => Promise<CodexLoginStart>;
      codexLoginStatus: (loginId: string) => Promise<CodexLoginResult>;
      cancelCodexLogin: (loginId: string) => Promise<void>;
    },
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
      const discovery = JSON.parse(readFileSync(path, "utf8")) as Discovery;
      if (discovery.pid === process.pid && discovery.token === this.token) unlinkSync(path);
    } catch {
      // A replacement runtime may already own discovery.
    }
  }

  private writeDiscovery(port: number): void {
    mkdirSync(this.config.homeDir, { recursive: true, mode: 0o700 });
    const path = join(this.config.homeDir, "runtime.json");
    const temp = `${path}.${process.pid}.tmp`;
    const discovery: Discovery = { protocolVersion: 1, port, token: this.token, pid: process.pid };
    writeFileSync(temp, `${JSON.stringify(discovery)}\n`, { mode: 0o600 });
    renameSync(temp, path);
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
        json(response, 200, { session, messages: this.store.getMessages(id, this.config.maxHistoryMessages) });
        return;
      }
      if (request.method === "GET" && url.pathname === "/v1/setup") {
        if (!this.setup) {
          const openAIConfigured = Boolean(process.env.OPENAI_API_KEY);
          json(response, 200, {
            configured: openAIConfigured,
            selectedBackend: openAIConfigured ? "responses" : null,
            recommendedBackend: "codex",
            openAIConfigured,
            codex: { installed: false, connected: false, planType: null, allowanceAvailable: null, usage: [] },
          });
        } else {
          json(response, 200, await this.setup.status());
        }
        return;
      }
      if (request.method === "POST" && url.pathname === "/v1/setup/openai") {
        if (!this.setup) throw new Error("Runtime setup is unavailable.");
        const body = await readJson(request);
        const key = typeof body.apiKey === "string" ? body.apiKey.trim() : "";
        if (!key.startsWith("sk-")) throw new Error("That does not look like an OpenAI API key.");
        await this.setup.setOpenAIKey(key);
        json(response, 200, { connected: true });
        return;
      }
      if (request.method === "POST" && url.pathname === "/v1/setup/backend") {
        if (!this.setup) throw new Error("Runtime setup is unavailable.");
        const body = await readJson(request);
        const backend = body.backend;
        if (backend !== "codex" && backend !== "responses") throw new Error("backend must be codex or responses");
        await this.setup.selectBackend(backend);
        json(response, 200, { connected: true, backend });
        return;
      }
      if (request.method === "POST" && url.pathname === "/v1/setup/codex/login") {
        if (!this.setup) throw new Error("Runtime setup is unavailable.");
        const body = await readJson(request);
        const mode = body.mode ?? "browser";
        if (mode !== "browser" && mode !== "headless") throw new Error("login mode must be browser or headless");
        json(response, 200, await this.setup.startCodexLogin(mode));
        return;
      }
      if (request.method === "GET" && url.pathname.startsWith("/v1/setup/codex/login/")) {
        if (!this.setup) throw new Error("Runtime setup is unavailable.");
        const loginId = decodeURIComponent(url.pathname.slice("/v1/setup/codex/login/".length));
        json(response, 200, await this.setup.codexLoginStatus(loginId));
        return;
      }
      if (request.method === "POST" && url.pathname.startsWith("/v1/setup/codex/login/") && url.pathname.endsWith("/cancel")) {
        if (!this.setup) throw new Error("Runtime setup is unavailable.");
        const loginId = decodeURIComponent(url.pathname.slice("/v1/setup/codex/login/".length, -"/cancel".length));
        if (!loginId) throw new Error("login id is required");
        await this.setup.cancelCodexLogin(loginId);
        json(response, 200, { cancelled: true });
        return;
      }
      if (request.method === "POST" && url.pathname === "/v1/cancel") {
        const body = await readJson(request);
        const requestId = String(body.requestId ?? "");
        const controller = this.controllers.get(requestId);
        controller?.abort();
        json(response, 200, { cancelled: Boolean(controller) });
        return;
      }
      if (request.method === "POST" && url.pathname === "/v1/chat") {
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
    if (!text) {
      json(response, 400, { error: "text is required" });
      return;
    }
    const requestId = typeof body.requestId === "string" ? body.requestId : randomBytes(12).toString("hex");
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
      ...(typeof body.cwd === "string" ? { cwd: body.cwd } : {}),
      ...(typeof body.sessionId === "string" ? { sessionId: body.sessionId } : {}),
      ...(body.fresh === true ? { fresh: true } : {}),
      channel: body.channel === "telegram" || body.channel === "macos" || body.channel === "cli" ? body.channel : "api",
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

export function readDiscovery(homeDir: string): Discovery | null {
  try {
    return JSON.parse(readFileSync(join(homeDir, "runtime.json"), "utf8")) as Discovery;
  } catch {
    return null;
  }
}
