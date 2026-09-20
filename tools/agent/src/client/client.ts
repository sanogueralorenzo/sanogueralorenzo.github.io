import { readFileSync } from "node:fs";
import { join } from "node:path";
import { RUNTIME_PROTOCOL_VERSION, type RunEnvelope, type RunInfo, type RunState, type Session, type TurnRequest } from "../conversation/types.js";
import type { SetupStatus } from "../setup/service.js";

function decodeEvent(data: string): RunEnvelope {
  try {
    const event = JSON.parse(data) as RunEnvelope;
    if (!event || typeof event.sequence !== "number" || typeof event.runId !== "string" || typeof event.event?.type !== "string") throw new Error();
    return event;
  } catch {
    throw new Error("Agent runtime sent a malformed event.");
  }
}

export class RuntimeClient {
  constructor(private readonly homeDir: string) {}

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

  async *events(after: number, signal?: AbortSignal): AsyncGenerator<RunEnvelope> {
    const controller = new AbortController();
    const abort = () => controller.abort();
    signal?.addEventListener("abort", abort, { once: true });
    try {
      const response = await this.fetch(`/v1/events?after=${after}`, { signal: controller.signal });
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
            yield decodeEvent(data);
          }
          boundary = buffer.search(/\r?\n\r?\n/);
        }
        if (next.done) break;
      }
      if (!controller.signal.aborted) throw new Error("Agent runtime disconnected.");
    } finally {
      controller.abort();
      signal?.removeEventListener("abort", abort);
    }
  }

  runState(): Promise<RunState> {
    return this.json("/v1/runs");
  }

  async submit(turn: TurnRequest): Promise<RunInfo | null> {
    const response = await this.fetch("/v1/runs", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(turn),
    });
    if (response.status === 409) return null;
    if (!response.ok) throw new Error(await response.text() || `Runtime returned ${response.status}.`);
    return (await response.json() as { run: RunInfo }).run;
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

  async stop(): Promise<boolean> {
    const response = await this.fetch("/v1/runs/stop", { method: "POST" });
    if (!response.ok) throw new Error(await response.text() || `Runtime returned ${response.status}.`);
    return (await response.json() as { stopped: boolean }).stopped;
  }

  sessions(): Promise<{ sessions: Session[] }> {
    return this.json("/v1/sessions");
  }

  setupStatus(): Promise<SetupStatus> {
    return this.json("/v1/setup");
  }
}
