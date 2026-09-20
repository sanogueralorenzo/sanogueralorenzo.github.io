import { readFileSync } from "node:fs";
import { join } from "node:path";
import { RUNTIME_PROTOCOL_VERSION, type RuntimeEvent, type Session, type TurnRequest } from "../conversation/types.js";
import type { SetupStatus } from "../setup/service.js";

function decodeEvent(data: string): RuntimeEvent {
  let value: unknown;
  try {
    value = JSON.parse(data);
  } catch {
    throw new Error("Agent runtime sent a malformed event.");
  }
  if (!value || typeof value !== "object" || typeof (value as { type?: unknown }).type !== "string") {
    throw new Error("Agent runtime sent an invalid event.");
  }
  const event = value as Record<string, unknown>;
  const valid = event.type === "session"
    ? typeof (event.session as Record<string, unknown> | undefined)?.id === "string"
    : event.type === "text_delta" ? typeof event.delta === "string"
      : event.type === "status" || event.type === "error" ? typeof event.message === "string"
        : event.type === "artifact" ? typeof (event.artifact as Record<string, unknown> | undefined)?.path === "string"
          : event.type === "tool_start" ? typeof event.name === "string" && typeof event.callId === "string"
            : event.type === "tool_end" ? typeof event.name === "string" && typeof event.callId === "string" && typeof event.summary === "string"
              : event.type === "done" && typeof event.sessionId === "string";
  if (!valid) throw new Error("Agent runtime sent an invalid event.");
  return value as RuntimeEvent;
}

export class RuntimeClient {
  private activeRequest: AbortController | null = null;

  constructor(private readonly homeDir: string) {}

  get isRunning(): boolean {
    return this.activeRequest !== null;
  }

  private connection(): { baseUrl: string; token: string } {
    let discovery: { protocolVersion: number; port: number; token: string };
    try {
      discovery = JSON.parse(readFileSync(join(this.homeDir, "runtime.json"), "utf8")) as typeof discovery;
    } catch {
      throw new Error("Agent runtime is not running.");
    }
    if (discovery.protocolVersion !== RUNTIME_PROTOCOL_VERSION) throw new Error("Agent runtime uses an incompatible protocol.");
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

  async *events(turn: TurnRequest): AsyncGenerator<RuntimeEvent> {
    if (this.activeRequest) throw new Error("A response is already running.");
    const controller = new AbortController();
    this.activeRequest = controller;
    let terminal = false;
    try {
      const response = await this.fetch("/v1/chat", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify(turn),
        signal: controller.signal,
      });
      if (!response.ok || !response.body) throw new Error(await response.text() || `Runtime returned ${response.status}.`);

      const reader = response.body.getReader();
      const decoder = new TextDecoder();
      let buffer = "";
      while (true) {
        const next = await reader.read();
        buffer += decoder.decode(next.value, { stream: !next.done });
        let boundary = buffer.search(/\r?\n\r?\n/);
        while (boundary >= 0) {
          const separator = buffer.slice(boundary).match(/^\r?\n\r?\n/)![0];
          const block = buffer.slice(0, boundary);
          buffer = buffer.slice(boundary + separator.length);
          const data = block.split(/\r?\n/).filter((line) => line.startsWith("data:")).map((line) => line.slice(5).trimStart()).join("\n");
          if (data) {
            const event = decodeEvent(data);
            terminal ||= event.type === "done" || event.type === "error";
            yield event;
          }
          boundary = buffer.search(/\r?\n\r?\n/);
        }
        if (next.done) break;
      }
      if (!terminal) throw new Error("Agent runtime disconnected before the response completed.");
    } finally {
      controller.abort();
      if (this.activeRequest === controller) this.activeRequest = null;
    }
  }

  async uploadAttachment(input: { name: string; mimeType: string; data: Uint8Array }): Promise<{ id: string }> {
    const response = await this.fetch("/v1/attachments", {
      method: "POST",
      headers: {
        "content-type": input.mimeType,
        "x-agent-filename": encodeURIComponent(input.name),
      },
      body: Buffer.from(input.data),
    });
    if (!response.ok) throw new Error(await response.text() || `Runtime returned ${response.status}.`);
    return response.json() as Promise<{ id: string }>;
  }

  async cancel(): Promise<boolean> {
    if (!this.activeRequest) return false;
    this.activeRequest.abort();
    return true;
  }

  sessions(): Promise<{ sessions: Session[] }> {
    return this.json("/v1/sessions");
  }

  setupStatus(): Promise<SetupStatus> {
    return this.json("/v1/setup");
  }
}
