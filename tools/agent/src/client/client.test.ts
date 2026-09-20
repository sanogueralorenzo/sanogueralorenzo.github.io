import { createServer, type IncomingMessage, type ServerResponse } from "node:http";
import type { AddressInfo } from "node:net";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { writePrivateJson } from "../local/files.js";
import { cleanup, temporary } from "../test-support.js";
import type { RuntimeEvent } from "../conversation/types.js";
import { RuntimeClient } from "./client.js";

async function body(request: IncomingMessage): Promise<Record<string, unknown>> {
  const chunks: Buffer[] = [];
  for await (const chunk of request) chunks.push(Buffer.from(chunk));
  return JSON.parse(Buffer.concat(chunks).toString("utf8")) as Record<string, unknown>;
}

async function fixture(handler: (request: IncomingMessage, response: ServerResponse) => void | Promise<void>) {
  const homeDir = temporary("agent-client-");
  const server = createServer(handler);
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  cleanup(() => new Promise<void>((resolve) => server.close(() => resolve())));
  const port = (server.address() as AddressInfo).port;
  writePrivateJson(join(homeDir, "runtime.json"), { protocolVersion: 1, port, token: "test-token", pid: process.pid });
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

  it("owns request identity, busy state, and cancellation", async () => {
    let chatResponse: ServerResponse | undefined;
    let chatId = "";
    let cancelledId = "";
    const client = await fixture(async (request, response) => {
      if (request.url === "/v1/chat") {
        chatId = String((await body(request)).requestId);
        chatResponse = response;
        response.writeHead(200, { "content-type": "text/event-stream" });
        response.write("data: {\"type\":\"status\",\"message\":\"Working\"}\n\n");
      } else if (request.url === "/v1/cancel") {
        cancelledId = String((await body(request)).requestId);
        response.writeHead(200, { "content-type": "application/json" });
        response.end('{"cancelled":true}');
        chatResponse!.end("data: {\"type\":\"error\",\"message\":\"Interrupted\"}\n\n");
      }
    });

    const iterator = client.events({ text: "hello" })[Symbol.asyncIterator]();
    await expect(iterator.next()).resolves.toMatchObject({ value: { type: "status" } });
    expect(client.isRunning).toBe(true);
    await expect(client.events({ text: "again" }).next()).rejects.toThrow("already running");
    await expect(client.cancel()).resolves.toBe(true);
    await expect(iterator.next()).resolves.toEqual({ value: { type: "error", message: "Interrupted" }, done: false });
    await expect(iterator.next()).resolves.toEqual({ value: undefined, done: true });
    expect(cancelledId).toBe(chatId);
    expect(client.isRunning).toBe(false);
    await expect(client.cancel()).resolves.toBe(false);
  });
});
