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
  it("decodes sequenced SSE events across chunk boundaries", async () => {
    const client = await fixture((_request, response) => {
      response.writeHead(200, { "content-type": "text/event-stream" });
      response.write('data: {"runId":"r1","sequence":1,"event":{"type":"status","message":"Working"}}\r\n\r');
      response.end('\ndata: {"runId":"r1","sequence":2,"event":{"type":"done","sessionId":"s1"}}\n\n');
    });

    const events = client.events(0)[Symbol.asyncIterator]();
    await expect(events.next()).resolves.toMatchObject({ value: { runId: "r1", sequence: 1, event: { type: "status" } } });
    await expect(events.next()).resolves.toMatchObject({ value: { runId: "r1", sequence: 2, event: { type: "done" } } });
    await expect(events.next()).rejects.toThrow("runtime disconnected");
  });

  it("rejects malformed events", async () => {
    const client = await fixture((_request, response) => {
      response.writeHead(200, { "content-type": "text/event-stream" });
      response.end("data: {broken}\n\n");
    });
    await expect(collect(client.events(0))).rejects.toThrow("malformed event");
  });

  it("submits, reports busy, reads state, and stops through shared endpoints", async () => {
    const requests: string[] = [];
    const client = await fixture(async (request, response) => {
      requests.push(`${request.method} ${request.url}`);
      response.setHeader("content-type", "application/json");
      if (request.url === "/v1/runs" && request.method === "GET") return response.end('{"active":null,"latestSequence":4}');
      if (request.url === "/v1/runs" && request.method === "POST") {
        const chunks: Buffer[] = [];
        for await (const chunk of request) chunks.push(Buffer.from(chunk));
        const body = JSON.parse(Buffer.concat(chunks).toString()) as { text: string };
        if (body.text === "busy") {
          response.statusCode = 409;
          return response.end('{"error":"busy"}');
        }
        response.statusCode = 202;
        return response.end('{"run":{"id":"r1","origin":"cli","startSequence":5}}');
      }
      if (request.url === "/v1/runs/stop") return response.end('{"stopped":true}');
      response.statusCode = 404;
      response.end();
    });

    await expect(client.runState()).resolves.toEqual({ active: null, latestSequence: 4 });
    await expect(client.submit({ text: "hello", channel: "cli" })).resolves.toEqual({ id: "r1", origin: "cli", startSequence: 5 });
    await expect(client.submit({ text: "busy", channel: "cli" })).resolves.toBeNull();
    await expect(client.stop()).resolves.toBe(true);
    expect(requests).toEqual(["GET /v1/runs", "POST /v1/runs", "POST /v1/runs", "POST /v1/runs/stop"]);
  });

  it("closing a subscription only closes its HTTP stream", async () => {
    let closed!: () => void;
    const connectionClosed = new Promise<void>((resolve) => { closed = resolve; });
    const client = await fixture((_request, response) => {
      response.once("close", closed);
      response.writeHead(200, { "content-type": "text/event-stream" });
      response.write('data: {"runId":"r1","sequence":1,"event":{"type":"turn","text":"hello","channel":"api","hasAttachments":false}}\n\n');
    });

    for await (const _event of client.events(0)) break;
    await expect(connectionClosed).resolves.toBeUndefined();
  });
});
