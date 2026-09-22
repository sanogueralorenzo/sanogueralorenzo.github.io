import { createServer, type IncomingMessage, type ServerResponse } from "node:http";
import type { AddressInfo } from "node:net";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { RUNTIME_PROTOCOL_VERSION, type RunEnvelope } from "../conversation/types.js";
import { writePrivateJson } from "../local/files.js";
import { cleanup, temporary } from "../test-support.js";
import { RuntimeClient } from "./client.js";

async function fixture(handler: (request: IncomingMessage, response: ServerResponse) => void | Promise<void>) {
  const homeDir = temporary("agent-client-");
  const server = createServer(handler);
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  cleanup(() => new Promise<void>((resolve) => server.close(() => resolve())));
  writePrivateJson(join(homeDir, "runtime.json"), {
    protocolVersion: RUNTIME_PROTOCOL_VERSION,
    port: (server.address() as AddressInfo).port,
    token: "test-token",
    pid: process.pid,
  });
  return new RuntimeClient(homeDir);
}

async function collect(events: AsyncIterable<RunEnvelope>): Promise<RunEnvelope[]> {
  const result: RunEnvelope[] = [];
  for await (const event of events) result.push(event);
  return result;
}

describe("RuntimeClient run protocol", () => {
  it("connects before returning and decodes SSE events across chunk boundaries", async () => {
    const client = await fixture((_request, response) => {
      response.writeHead(200, { "content-type": "text/event-stream", "x-agent-stream": "snapshot" });
      response.write('data: {"sessionId":"s1","runId":"","event":{"type":"snapshot","snapshot":{"sessions":[],"transcript":null,"activeRuns":[],"lastRuns":[]}}}\r\n\r\n');
      response.write('data: {"sessionId":"s1","runId":"r1","event":{"type":"status","message":"Working"}}\r\n\r');
      response.end('\ndata: {"sessionId":"s1","runId":"r1","event":{"type":"done","sessionId":"s1"}}\n\n');
    });

    const events = (await client.events())[Symbol.asyncIterator]();
    await expect(events.next()).resolves.toMatchObject({ value: { event: { type: "snapshot" } } });
    await expect(events.next()).resolves.toMatchObject({ value: { runId: "r1", event: { type: "status" } } });
    await expect(events.next()).resolves.toMatchObject({ value: { runId: "r1", event: { type: "done" } } });
    await expect(events.next()).rejects.toThrow("runtime disconnected");
  });

  it("rejects malformed events", async () => {
    const client = await fixture((_request, response) => {
      response.writeHead(200, { "content-type": "text/event-stream", "x-agent-stream": "snapshot" });
      response.end("data: {broken}\n\n");
    });
    await expect(collect(await client.events())).rejects.toThrow("malformed event");
  });

  it("accepts a redirect as the first event when a session moved", async () => {
    const client = await fixture((_request, response) => {
      response.writeHead(200, { "content-type": "text/event-stream", "x-agent-stream": "snapshot" });
      response.end('data: {"sessionId":"old","runId":"","event":{"type":"navigate","session":{"id":"new","cwd":null,"title":"Saved work","updatedAt":"now"},"url":"agent://sessions/new"}}\n\n');
    });
    const stream = (await client.events())[Symbol.asyncIterator]();
    await expect(stream.next()).resolves.toMatchObject({ value: { event: { type: "navigate", session: { id: "new" } } } });
    await stream.return?.();
  });

  it("rejects an older stream contract before subscribing", async () => {
    const client = await fixture((_request, response) => {
      response.writeHead(200, { "content-type": "text/event-stream" });
      response.end();
    });
    await expect(client.events()).rejects.toThrow("needs to restart");
  });

  it("submits, reports busy, and stops through shared endpoints", async () => {
    const requests: string[] = [];
    const client = await fixture(async (request, response) => {
      requests.push(`${request.method} ${request.url}`);
      response.setHeader("content-type", "application/json");
      if (request.url === "/v1/runs" && request.method === "POST") {
        const chunks: Buffer[] = [];
        for await (const chunk of request) chunks.push(Buffer.from(chunk));
        const body = JSON.parse(Buffer.concat(chunks).toString()) as { text: string };
        if (body.text === "busy") {
          response.statusCode = 409;
          return response.end('{"error":"busy"}');
        }
        response.statusCode = 202;
        return response.end('{"run":{"id":"r1","sessionId":"s1","origin":"cli"}}');
      }
      if (request.url === "/v1/runs/stop") return response.end('{"stopped":true}');
      response.statusCode = 404;
      response.end();
    });

    await expect(client.submit({ text: "hello", channel: "cli", sessionId: "s1" })).resolves.toEqual({ id: "r1", sessionId: "s1", origin: "cli" });
    await expect(client.submit({ text: "busy", channel: "cli" })).resolves.toBeNull();
    await expect(client.stop("r1")).resolves.toBe(true);
    expect(requests).toEqual(["POST /v1/runs", "POST /v1/runs", "POST /v1/runs/stop"]);
  });

  it("closing a subscription only closes its HTTP stream", async () => {
    let closed!: () => void;
    const connectionClosed = new Promise<void>((resolve) => { closed = resolve; });
    const client = await fixture((_request, response) => {
      response.once("close", closed);
      response.writeHead(200, { "content-type": "text/event-stream", "x-agent-stream": "snapshot" });
      response.write('data: {"sessionId":"s1","runId":"","event":{"type":"snapshot","snapshot":{"sessions":[],"transcript":null,"activeRuns":[],"lastRuns":[]}}}\n\n');
    });

    for await (const _event of await client.events()) break;
    await expect(connectionClosed).resolves.toBeUndefined();
  });
});
