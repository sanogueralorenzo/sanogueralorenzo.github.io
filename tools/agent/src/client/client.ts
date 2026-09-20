import { randomUUID } from "node:crypto";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import type { RuntimeEvent, Session, TurnRequest } from "../core/types.js";
import type { SetupStatus } from "../setup/service.js";

interface Envelope {
  v: 1;
  seq: number;
  requestId: string;
  event: RuntimeEvent;
}

export interface UploadedAttachment {
  id: string;
  kind: "audio" | "image" | "file";
  name: string;
  mimeType: string;
  size: number;
}

export class RuntimeClient {
  constructor(private readonly homeDir: string) {}

  private connection(): { baseUrl: string; token: string } {
    let discovery: { port: number; token: string };
    try {
      discovery = JSON.parse(readFileSync(join(this.homeDir, "runtime.json"), "utf8")) as typeof discovery;
    } catch {
      throw new Error("Agent runtime is not running.");
    }
    return { baseUrl: `http://127.0.0.1:${discovery.port}`, token: discovery.token };
  }

  private fetch(path: string, init: RequestInit = {}): Promise<Response> {
    const { baseUrl, token } = this.connection();
    const headers = new Headers(init.headers);
    headers.set("authorization", `Bearer ${token}`);
    return fetch(`${baseUrl}${path}`, { ...init, headers });
  }

  private async json<T>(path: string): Promise<T> {
    const response = await this.fetch(path);
    if (!response.ok) throw new Error(await response.text());
    return response.json() as Promise<T>;
  }

  async healthy(): Promise<boolean> {
    try {
      return (await this.fetch("/v1/health", { signal: AbortSignal.timeout(800) })).ok;
    } catch {
      return false;
    }
  }

  async waitUntilHealthy(timeoutMs = 10_000): Promise<void> {
    const deadline = Date.now() + timeoutMs;
    while (Date.now() < deadline) {
      if (await this.healthy()) return;
      await new Promise((resolve) => setTimeout(resolve, 100));
    }
    throw new Error("Agent runtime did not become ready.");
  }

  async chat(turn: TurnRequest, onEvent: (event: RuntimeEvent) => void, requestId: string = randomUUID()): Promise<void> {
    const response = await this.fetch("/v1/chat", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ ...turn, requestId }),
    });
    if (!response.ok || !response.body) throw new Error(await response.text() || `Runtime returned ${response.status}.`);

    const reader = response.body.getReader();
    const decoder = new TextDecoder();
    let buffer = "";
    while (true) {
      const next = await reader.read();
      if (next.done) break;
      buffer += decoder.decode(next.value, { stream: true }).replaceAll("\r\n", "\n");
      let boundary = buffer.indexOf("\n\n");
      while (boundary >= 0) {
        const block = buffer.slice(0, boundary);
        buffer = buffer.slice(boundary + 2);
        const data = block.split("\n").find((line) => line.startsWith("data: "))?.slice(6);
        if (data) onEvent((JSON.parse(data) as Envelope).event);
        boundary = buffer.indexOf("\n\n");
      }
    }
  }

  async uploadAttachment(input: { name: string; mimeType: string; data: Uint8Array }): Promise<UploadedAttachment> {
    const response = await this.fetch("/v1/attachments", {
      method: "POST",
      headers: {
        "content-type": input.mimeType,
        "x-agent-filename": encodeURIComponent(input.name),
      },
      body: Buffer.from(input.data),
    });
    if (!response.ok) throw new Error(await response.text() || `Runtime returned ${response.status}.`);
    return response.json() as Promise<UploadedAttachment>;
  }

  async cancel(requestId: string): Promise<void> {
    await this.fetch("/v1/cancel", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ requestId }),
    });
  }

  async requestRestart(): Promise<boolean> {
    const response = await this.fetch("/v1/runtime/restart", { method: "POST" });
    if (response.status === 409) return false;
    if (!response.ok) throw new Error(await response.text() || `Runtime returned ${response.status}.`);
    return true;
  }

  sessions(): Promise<{ sessions: Session[] }> {
    return this.json("/v1/sessions");
  }

  setupStatus(): Promise<SetupStatus> {
    return this.json("/v1/setup");
  }
}
