import { randomBytes } from "node:crypto";
import { createReadStream, readFileSync, readdirSync, statSync } from "node:fs";
import { createServer, request as createRequest, type IncomingMessage, type ServerResponse } from "node:http";
import { extname, join, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";

const WEB_ROOT = fileURLToPath(new URL("../web/", import.meta.url));
const MIME_TYPES: Record<string, string> = {
  ".css": "text/css; charset=utf-8",
  ".html": "text/html; charset=utf-8",
  ".ico": "image/x-icon",
  ".js": "text/javascript; charset=utf-8",
  ".json": "application/json; charset=utf-8",
  ".svg": "image/svg+xml",
};

export interface ExistingRuntime {
  port: number;
  pid: number;
  token: string;
}

export class WebsiteProxy {
  private readonly token = randomBytes(32).toString("base64url");
  private readonly server = createServer(this.handle.bind(this));
  private port = 0;

  constructor(private readonly runtime: ExistingRuntime, private readonly homeDir: string) {}

  async listen(port = 0): Promise<number> {
    try {
      await this.listenOn(port);
    } catch (error) {
      if (port === 0 || (error as NodeJS.ErrnoException).code !== "EADDRINUSE") throw error;
      await this.listenOn(0);
    }
    this.port = (this.server.address() as { port: number }).port;
    return this.port;
  }

  private listenOn(port: number): Promise<void> {
    return new Promise((resolve, reject) => {
      this.server.once("error", reject);
      this.server.listen(port, "127.0.0.1", resolve);
    });
  }

  close(): void {
    this.server.closeAllConnections();
    this.server.close();
  }

  private async handle(request: IncomingMessage, response: ServerResponse): Promise<void> {
    const url = new URL(request.url ?? "/", "http://127.0.0.1");
    if (request.method === "GET" && (url.pathname === "/" || url.pathname.startsWith("/web/"))) {
      if (!this.isLocalHost(request)) return this.json(response, 403, { error: "local_only" });
      return this.serveWeb(url.pathname, response);
    }
    if (!this.isSameOrigin(request)) return this.json(response, 403, { error: "cross_origin_request" });
    const cookie = request.headers.cookie?.split(";").map((value) => value.trim()).find((value) => value.startsWith("agent_session="))?.slice("agent_session=".length);
    if (cookie !== this.token) return this.json(response, 401, { error: "unauthorized" });
    if (request.method === "POST" && url.pathname === "/v1/control/quit") {
      this.json(response, 200, { closed: true });
      setTimeout(() => this.close(), 50).unref();
      return;
    }
    if (request.method === "GET" && url.pathname.startsWith("/v1/artifacts/")) {
      return this.serveArtifact(decodeURIComponent(url.pathname.slice("/v1/artifacts/".length)), response);
    }
    if (!url.pathname.startsWith("/v1/")) return this.json(response, 404, { error: "not_found" });
    this.proxy(request, response);
  }

  private proxy(request: IncomingMessage, response: ServerResponse): void {
    const headers = { ...request.headers };
    delete headers.cookie;
    delete headers.origin;
    delete headers.authorization;
    delete headers.connection;
    headers.host = `127.0.0.1:${this.runtime.port}`;
    headers.origin = `http://127.0.0.1:${this.runtime.port}`;
    headers.authorization = `Bearer ${this.runtime.token}`;
    const upstream = createRequest({
      hostname: "127.0.0.1",
      port: this.runtime.port,
      method: request.method,
      path: request.url,
      headers,
    }, (upstreamResponse) => {
      const responseHeaders = { ...upstreamResponse.headers };
      delete responseHeaders.connection;
      response.writeHead(upstreamResponse.statusCode ?? 502, responseHeaders);
      upstreamResponse.pipe(response);
    });
    upstream.on("error", () => {
      if (!response.headersSent) this.json(response, 502, { error: "runtime_unavailable" });
      else response.destroy();
    });
    response.on("close", () => upstream.destroy());
    request.pipe(upstream);
  }

  private serveArtifact(id: string, response: ServerResponse): void {
    if (!/^[0-9a-f-]{36}$/i.test(id)) return this.json(response, 404, { error: "artifact_not_found" });
    try {
      const artifactDir = join(this.homeDir, "artifacts");
      const name = readdirSync(artifactDir).find((entry) => entry.startsWith(`${id}.`));
      if (!name) return this.json(response, 404, { error: "artifact_not_found" });
      const path = join(artifactDir, name);
      if (!statSync(path).isFile()) return this.json(response, 404, { error: "artifact_not_found" });
      response.writeHead(200, {
        "content-type": this.artifactMimeType(extname(path)),
        "content-disposition": `inline; filename="${name.replaceAll('"', "_").replaceAll("\\", "_")}"`,
        "cache-control": "private, no-store",
        "x-content-type-options": "nosniff",
      });
      createReadStream(path).pipe(response);
    } catch {
      this.json(response, 404, { error: "artifact_not_found" });
    }
  }

  private serveWeb(pathname: string, response: ServerResponse): void {
    const relativePath = pathname === "/" ? "index.html" : decodeURIComponent(pathname.slice("/web/".length));
    const path = resolve(WEB_ROOT, relativePath);
    if (path !== WEB_ROOT && !path.startsWith(`${resolve(WEB_ROOT)}${sep}`)) return this.json(response, 404, { error: "not_found" });
    try {
      const content = readFileSync(path);
      response.writeHead(200, {
        "content-type": MIME_TYPES[extname(path)] ?? "application/octet-stream",
        "cache-control": "no-store",
        "content-security-policy": "default-src 'self'; img-src 'self' data: blob:; media-src 'self' blob:; style-src 'self' 'unsafe-inline'; script-src 'self'; connect-src 'self'; object-src 'none'; base-uri 'none'; frame-ancestors 'none'",
        "referrer-policy": "no-referrer",
        "x-content-type-options": "nosniff",
        ...(pathname === "/" ? { "set-cookie": `agent_session=${this.token}; HttpOnly; SameSite=Strict; Path=/` } : {}),
      });
      response.end(content);
    } catch {
      this.json(response, 404, { error: "not_found" });
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

  private json(response: ServerResponse, status: number, value: unknown): void {
    response.writeHead(status, { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" });
    response.end(JSON.stringify(value));
  }

  private artifactMimeType(extension: string): string {
    const known: Record<string, string> = {
      ".gif": "image/gif", ".jpeg": "image/jpeg", ".jpg": "image/jpeg", ".pdf": "application/pdf",
      ".png": "image/png", ".svg": "image/svg+xml", ".txt": "text/plain; charset=utf-8", ".webp": "image/webp",
    };
    return known[extension.toLowerCase()] ?? "application/octet-stream";
  }
}
