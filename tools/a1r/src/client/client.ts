import { randomUUID } from "node:crypto";
import type { RuntimeEvent, TurnRequest } from "../core/types.js";
import { readDiscovery } from "../server/server.js";

interface Envelope {
  v: 1;
  seq: number;
  requestId: string;
  event: RuntimeEvent;
}

export class RuntimeClient {
  constructor(private readonly homeDir: string) {}

  private connection(): { baseUrl: string; token: string } {
    const discovery = readDiscovery(this.homeDir);
    if (!discovery) throw new Error("A1R runtime is not running.");
    return { baseUrl: `http://127.0.0.1:${discovery.port}`, token: discovery.token };
  }

  async healthy(): Promise<boolean> {
    try {
      const { baseUrl } = this.connection();
      const response = await fetch(`${baseUrl}/v1/health`, { signal: AbortSignal.timeout(800) });
      return response.ok;
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
    throw new Error("A1R runtime did not become ready.");
  }

  async chat(turn: TurnRequest, onEvent: (event: RuntimeEvent) => void, requestId: string = randomUUID()): Promise<void> {
    const { baseUrl, token } = this.connection();
    const response = await fetch(`${baseUrl}/v1/chat`, {
      method: "POST",
      headers: { authorization: `Bearer ${token}`, "content-type": "application/json" },
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

  async cancel(requestId: string): Promise<void> {
    const { baseUrl, token } = this.connection();
    await fetch(`${baseUrl}/v1/cancel`, {
      method: "POST",
      headers: { authorization: `Bearer ${token}`, "content-type": "application/json" },
      body: JSON.stringify({ requestId }),
    });
  }

  async sessions(): Promise<unknown> {
    const { baseUrl, token } = this.connection();
    const response = await fetch(`${baseUrl}/v1/sessions`, { headers: { authorization: `Bearer ${token}` } });
    if (!response.ok) throw new Error(await response.text());
    return response.json();
  }

  async setupStatus(): Promise<{ openAIConfigured: boolean }> {
    const { baseUrl, token } = this.connection();
    const response = await fetch(`${baseUrl}/v1/setup`, { headers: { authorization: `Bearer ${token}` } });
    if (!response.ok) throw new Error(await response.text());
    return response.json() as Promise<{ openAIConfigured: boolean }>;
  }

  async connectOpenAI(apiKey: string): Promise<void> {
    const { baseUrl, token } = this.connection();
    const response = await fetch(`${baseUrl}/v1/setup/openai`, {
      method: "POST",
      headers: { authorization: `Bearer ${token}`, "content-type": "application/json" },
      body: JSON.stringify({ apiKey }),
    });
    if (!response.ok) throw new Error(await response.text());
  }
}
