import { randomBytes } from "node:crypto";
import { rmSync } from "node:fs";
import { createServer, type IncomingMessage, type ServerResponse } from "node:http";
import { join } from "node:path";
import type { AddressInfo } from "node:net";
import type { AgentRuntime } from "../conversation/runtime.js";
import type { Store } from "../conversation/store.js";
import { RunBusyError, RunCoordinator } from "../conversation/runs.js";
import { RUNTIME_PROTOCOL_VERSION, type RuntimeConfig, type RuntimeSnapshot, type SessionStatus } from "../conversation/types.js";
import type { AgentSetupService } from "../setup/service.js";
import { MAX_ATTACHMENT_BYTES, saveAttachment } from "../workspace/assets.js";
import { readPrivateJson, writePrivateFile } from "../local/files.js";
import { readBody, readJson, readTurn } from "./request.js";

export type RuntimeSetup = Pick<AgentSetupService,
  "status" | "connectApiKey" | "logout" | "startCodexLogin" | "waitForCodexLogin">;

function json(response: ServerResponse, status: number, body: unknown): void {
  response.writeHead(status, { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" });
  response.end(JSON.stringify(body));
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
    this.runs = new RunCoordinator(runtime, store);
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
        const session = this.store.getSession(id) ?? this.store.redirectedSession(id);
        return session
          ? json(response, 200, { session, messages: this.store.getMessages(session.id) })
          : json(response, 404, { error: "session_not_found" });
      }
      if (route.startsWith("POST /v1/setup/codex/login/") && route.endsWith("/wait")) {
        const loginId = decodeURIComponent(url.pathname.slice("/v1/setup/codex/login/".length, -"/wait".length));
        if (!loginId) throw new Error("login id is required");
        return json(response, 200, await this.setup.waitForCodexLogin(loginId));
      }
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
        case "GET /v1/sessions": return json(response, 200, { sessions: this.sessionStatuses(), homeEntries: this.store.homeEntries() });
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
        case "POST /v1/telegram/session": {
          const { ownerId, fresh, home, preferredSessionId } = await readJson(request);
          if (typeof ownerId !== "string" || !/^\d+$/.test(ownerId)) throw new Error("Telegram owner ID is required.");
          return json(response, 200, { session: this.runtime.openTelegramSession(ownerId, {
            fresh: fresh === true, home: home === true,
            ...(typeof preferredSessionId === "string" ? { preferredSessionId } : {}),
          }) });
        }
        case "GET /v1/setup": return json(response, 200, await this.setup.status());
        case "POST /v1/setup/logout": {
          await this.setup.logout();
          return json(response, 200, { connected: false });
        }
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
      homeEntries: this.store.homeEntries(),
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
