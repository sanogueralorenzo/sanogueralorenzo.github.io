import { createServer, type IncomingMessage, type ServerResponse } from "node:http";
import type { AddressInfo } from "node:net";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { writePrivateJson } from "../local/files.js";
import { cleanup, temporary } from "../test-support.js";
import { RUNTIME_PROTOCOL_VERSION, type RuntimeEvent } from "../conversation/types.js";
import { RuntimeClient } from "./client.js";

async function fixture(handler: (request: IncomingMessage, response: ServerResponse) => void | Promise<void>) {
  const homeDir = temporary("agent-client-");
  const server = createServer(handler);
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  cleanup(() => new Promise<void>((resolve) => server.close(() => resolve())));
  const port = (server.address() as AddressInfo).port;
  writePrivateJson(join(homeDir, "runtime.json"), { protocolVersion: RUNTIME_PROTOCOL_VERSION, port, token: "test-token", pid: process.pid });
  return new RuntimeClient(homeDir);
}

async function collect(events: AsyncIterable<RuntimeEvent>): Promise<RuntimeEvent[]> {
  const result: RuntimeEvent[] = [];
  for await (const event of events) result.push(event);
  return result;
}

describe("RuntimeClient event stream", () => {
  it("decodes SSE across chunk boundaries and requires a terminal event", async () => {
    const client = await fixture((_request, response) => {
      response.writeHead(200, { "content-type": "text/event-stream" });
      response.write("data: {\"type\":\"status\",\"message\":\"Working\"}\r\n\r");
      response.end("\ndata: {\"type\":\"done\",\"sessionId\":\"session-1\"}\n\n");
    });

    await expect(collect(client.events({ text: "hello", channel: "api" }))).resolves.toEqual([
      { type: "status", message: "Working" },
      { type: "done", sessionId: "session-1" },
    ]);
    expect(client.isRunning).toBe(false);
  });

  it.each([
    ["malformed", "data: {broken}\n\n", "malformed event"],
    ["invalid", "data: {\"type\":\"text_delta\"}\n\n", "invalid event"],
    ["disconnected", "data: {\"type\":\"status\",\"message\":\"Working\"}\n\n", "disconnected before"],
  ])("rejects a %s stream", async (_name, payload, message) => {
    const client = await fixture((_request, response) => {
      response.writeHead(200, { "content-type": "text/event-stream" });
      response.end(payload);
    });
    await expect(collect(client.events({ text: "hello" }))).rejects.toThrow(message);
    expect(client.isRunning).toBe(false);
  });

  it("owns busy state and cancels the active stream", async () => {
    let chatResponse: ServerResponse | undefined;
    const client = await fixture(async (request, response) => {
      if (request.url === "/v1/chat") {
        chatResponse = response;
        response.writeHead(200, { "content-type": "text/event-stream" });
        response.write("data: {\"type\":\"status\",\"message\":\"Working\"}\n\n");
      }
    });

    const iterator = client.events({ text: "hello" })[Symbol.asyncIterator]();
    await expect(iterator.next()).resolves.toMatchObject({ value: { type: "status" } });
    expect(client.isRunning).toBe(true);
    await expect(client.events({ text: "again" }).next()).rejects.toThrow("already running");
    await expect(client.cancel()).resolves.toBe(true);
    await expect(iterator.next()).rejects.toMatchObject({ name: "AbortError" });
    expect(client.isRunning).toBe(false);
    await expect(client.cancel()).resolves.toBe(false);
    chatResponse?.end();
  });

  it("closes the HTTP stream when its consumer stops early", async () => {
    let closed!: () => void;
    const connectionClosed = new Promise<void>((resolve) => { closed = resolve; });
    const client = await fixture((_request, response) => {
      response.once("close", closed);
      response.writeHead(200, { "content-type": "text/event-stream" });
      response.write("data: {\"type\":\"status\",\"message\":\"Working\"}\n\n");
    });

    for await (const _event of client.events({ text: "hello" })) break;
    await expect(connectionClosed).resolves.toBeUndefined();
    expect(client.isRunning).toBe(false);
  });
});
