import { spawn } from "node:child_process";
import { createServer, type ServerResponse } from "node:http";
import type { AddressInfo } from "node:net";
import { join } from "node:path";
import { describe, expect, it, vi } from "vitest";
import { RUNTIME_PROTOCOL_VERSION } from "../conversation/types.js";
import { writePrivateJson } from "../local/files.js";
import { cleanup, temporary } from "../test-support.js";

describe("CLI shared runs", () => {
  const session = { id: "s1", cwd: null, title: "Hello", updatedAt: new Date().toISOString() };
  it("submits once and renders the centralized event feed", async () => {
    const homeDir = temporary("agent-cli-runs-");
    let feed: ServerResponse | undefined;
    let openFeed!: () => void;
    const feedReady = new Promise<void>((resolve) => { openFeed = resolve; });
    let receivedTurn: Record<string, unknown> = {};
    let sessionSelections = 0;
    let selectionBody: unknown;
    const server = createServer(async (request, response) => {
      response.setHeader("content-type", "application/json");
      if (request.url === "/v1/health") return response.end('{"ok":true}');
      if (request.url === "/v1/sessions/auto") {
        sessionSelections++;
        const chunks: Buffer[] = [];
        for await (const chunk of request) chunks.push(Buffer.from(chunk));
        selectionBody = JSON.parse(Buffer.concat(chunks).toString());
        return response.end(JSON.stringify({ session }));
      }
      if (request.url?.startsWith("/v1/events?sessionId=")) {
        feed = response;
        response.writeHead(200, { "content-type": "text/event-stream", "x-agent-stream": "snapshot" });
        response.write(`data: ${JSON.stringify({ sessionId: "s1", runId: "", event: { type: "snapshot", snapshot: { sessions: [{ ...session, activeRunId: null }], transcript: { session, messages: [] }, activeRuns: [], lastRuns: [] } } })}\n\n`);
        openFeed();
        return;
      }
      if (request.url === "/v1/runs" && request.method === "POST") {
        const chunks: Buffer[] = [];
        for await (const chunk of request) chunks.push(Buffer.from(chunk));
        receivedTurn = JSON.parse(Buffer.concat(chunks).toString()) as Record<string, unknown>;
        response.statusCode = 202;
        response.end('{"run":{"id":"r1","sessionId":"s1","origin":"cli"}}');
        setImmediate(() => feed?.write([
          'data: {"sessionId":"s1","runId":"r1","event":{"type":"turn","text":"hello","channel":"cli","hasAttachments":false}}',
          'data: {"sessionId":"s1","runId":"r1","event":{"type":"text_delta","delta":"CLI answer"}}',
          'data: {"sessionId":"s1","runId":"r1","event":{"type":"done","sessionId":"s1"}}',
          "",
        ].join("\n\n")));
        return;
      }
      response.statusCode = 404;
      response.end();
    });
    await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
    cleanup(() => new Promise<void>((resolve) => server.close(() => resolve())));
    writePrivateJson(join(homeDir, "runtime.json"), {
      protocolVersion: RUNTIME_PROTOCOL_VERSION,
      port: (server.address() as AddressInfo).port,
      token: "test-token",
      pid: process.pid,
    });

    const child = spawn(process.execPath, ["--import", "tsx", "src/bin/agent.ts", "chat"], {
      cwd: process.cwd(),
      env: { ...process.env, AGENT_HOME: homeDir },
      stdio: ["pipe", "pipe", "pipe"],
    });
    cleanup(() => child.kill("SIGTERM"));
    let stdout = "";
    let stderr = "";
    child.stdout.on("data", (chunk) => { stdout += String(chunk); });
    child.stderr.on("data", (chunk) => { stderr += String(chunk); });
    await feedReady;
    feed?.write([
      'data: {"sessionId":"s1","runId":"remote","event":{"type":"turn","text":"from phone","channel":"telegram","hasAttachments":false}}',
      'data: {"sessionId":"s1","runId":"remote","event":{"type":"text_delta","delta":"Remote answer"}}',
      'data: {"sessionId":"s1","runId":"remote","event":{"type":"done","sessionId":"s1"}}',
      "",
    ].join("\n\n"));
    await vi.waitFor(() => expect(stdout).toContain("Remote answer"), { timeout: 5_000 });
    child.stdin.write("hello\n");
    await vi.waitFor(() => expect(stdout).toContain("CLI answer"), { timeout: 5_000 });
    child.stdin.write("/quit\n");
    const exitCode = await new Promise<number | null>((resolve) => child.once("exit", resolve));

    expect(exitCode, stderr).toBe(0);
    expect(stdout).toContain("telegram › from phone");
    expect(receivedTurn).toMatchObject({ text: "hello", channel: "cli", sessionId: "s1" });
    expect(sessionSelections).toBe(1);
    expect(selectionBody).toEqual({});
  });

  it("finishes a submitted run from the reconnect snapshot even when its turn was missed", async () => {
    const homeDir = temporary("agent-cli-reconnect-");
    let feed: ServerResponse | undefined;
    let connections = 0;
    let reconnect!: () => void;
    const reconnected = new Promise<void>((resolve) => { reconnect = resolve; });
    const server = createServer(async (request, response) => {
      response.setHeader("content-type", "application/json");
      if (request.url === "/v1/health") return response.end('{"ok":true}');
      if (request.url === "/v1/sessions/auto") return response.end(JSON.stringify({ session }));
      if (request.url?.startsWith("/v1/events?sessionId=")) {
        connections++;
        feed = response;
        response.writeHead(200, { "content-type": "text/event-stream", "x-agent-stream": "snapshot" });
        const snapshot = connections === 1
          ? { sessions: [{ ...session, activeRunId: null }], transcript: { session, messages: [] }, activeRuns: [], lastRuns: [] }
          : {
              transcript: {
                session: { id: "s1", cwd: null, title: "Hello", updatedAt: new Date().toISOString() },
                messages: [{ role: "user", content: "hello" }, { role: "assistant", content: "Recovered answer" }],
              },
              sessions: [{ ...session, activeRunId: null }],
              activeRuns: [],
              lastRuns: [{ id: "r1", sessionId: "s1", state: "complete" }],
            };
        response.write(`data: ${JSON.stringify({ sessionId: "s1", runId: "", event: { type: "snapshot", snapshot } })}\n\n`);
        if (connections === 2) reconnect();
        return;
      }
      if (request.url === "/v1/runs" && request.method === "POST") {
        for await (const _chunk of request) { /* consume body */ }
        feed?.destroy();
        await reconnected;
        response.statusCode = 202;
        response.end('{"run":{"id":"r1","sessionId":"s1","origin":"cli"}}');
        return;
      }
      response.statusCode = 404;
      response.end();
    });
    await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
    cleanup(() => new Promise<void>((resolve) => server.close(() => resolve())));
    writePrivateJson(join(homeDir, "runtime.json"), {
      protocolVersion: RUNTIME_PROTOCOL_VERSION,
      port: (server.address() as AddressInfo).port,
      token: "test-token",
      pid: process.pid,
    });
    const child = spawn(process.execPath, ["--import", "tsx", "src/bin/agent.ts", "chat"], {
      cwd: process.cwd(),
      env: { ...process.env, AGENT_HOME: homeDir },
      stdio: ["pipe", "pipe", "pipe"],
    });
    cleanup(() => child.kill("SIGTERM"));
    let stdout = "";
    let stderr = "";
    child.stdout.on("data", (chunk) => { stdout += String(chunk); });
    child.stderr.on("data", (chunk) => { stderr += String(chunk); });
    await vi.waitFor(() => expect(stdout).toContain("› "), { timeout: 5_000 });
    child.stdin.write("hello\n");
    await vi.waitFor(() => expect(stdout).toContain("Recovered answer"), { timeout: 5_000 });
    child.stdin.write("/quit\n");
    const exitCode = await new Promise<number | null>((resolve) => child.once("exit", resolve));
    expect(exitCode, stderr).toBe(0);
    expect(connections).toBe(2);
  });

  it("follows a saved-conversation redirect after missing its original event", async () => {
    const homeDir = temporary("agent-cli-redirect-");
    const source = { ...session, id: "source", title: "New conversation" };
    const target = { ...session, id: "target", title: "Saved work" };
    let targetFeed: ServerResponse | undefined;
    let receivedSessionId = "";
    const server = createServer(async (request, response) => {
      response.setHeader("content-type", "application/json");
      if (request.url === "/v1/health") return response.end('{"ok":true}');
      if (request.url === "/v1/sessions/auto") return response.end(JSON.stringify({ session: source }));
      if (request.url === "/v1/events?sessionId=source") {
        response.writeHead(200, { "content-type": "text/event-stream", "x-agent-stream": "snapshot" });
        return response.end(`data: ${JSON.stringify({ sessionId: source.id, runId: "", event: { type: "navigate", session: target, url: "agent://sessions/target" } })}\n\n`);
      }
      if (request.url === "/v1/events?sessionId=target") {
        targetFeed = response;
        response.writeHead(200, { "content-type": "text/event-stream", "x-agent-stream": "snapshot" });
        response.write(`data: ${JSON.stringify({ sessionId: target.id, runId: "", event: { type: "snapshot", snapshot: { sessions: [{ ...target, activeRunId: null }], transcript: { session: target, messages: [] }, activeRuns: [], lastRuns: [] } } })}\n\n`);
        return;
      }
      if (request.url === "/v1/runs" && request.method === "POST") {
        const chunks: Buffer[] = [];
        for await (const chunk of request) chunks.push(Buffer.from(chunk));
        receivedSessionId = (JSON.parse(Buffer.concat(chunks).toString()) as { sessionId: string }).sessionId;
        response.statusCode = 202;
        response.end('{"run":{"id":"r1","sessionId":"target","origin":"cli"}}');
        setImmediate(() => targetFeed?.write([
          'data: {"sessionId":"target","runId":"r1","event":{"type":"turn","text":"hello","channel":"cli","hasAttachments":false}}',
          'data: {"sessionId":"target","runId":"r1","event":{"type":"text_delta","delta":"Continued answer"}}',
          'data: {"sessionId":"target","runId":"r1","event":{"type":"done","sessionId":"target"}}',
          "",
        ].join("\n\n")));
        return;
      }
      response.statusCode = 404;
      response.end();
    });
    await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
    cleanup(() => new Promise<void>((resolve) => server.close(() => resolve())));
    writePrivateJson(join(homeDir, "runtime.json"), {
      protocolVersion: RUNTIME_PROTOCOL_VERSION,
      port: (server.address() as AddressInfo).port,
      token: "test-token",
      pid: process.pid,
    });
    const child = spawn(process.execPath, ["--import", "tsx", "src/bin/agent.ts", "chat"], {
      cwd: process.cwd(),
      env: { ...process.env, AGENT_HOME: homeDir },
      stdio: ["pipe", "pipe", "pipe"],
    });
    cleanup(() => child.kill("SIGTERM"));
    let stdout = "";
    let stderr = "";
    child.stdout.on("data", (chunk) => { stdout += String(chunk); });
    child.stderr.on("data", (chunk) => { stderr += String(chunk); });
    await vi.waitFor(() => expect(stdout).toContain("› "), { timeout: 5_000 });
    child.stdin.write("hello\n");
    await vi.waitFor(() => expect(stdout).toContain("Continued answer"), { timeout: 5_000 });
    child.stdin.write("/quit\n");
    expect(await new Promise<number | null>((resolve) => child.once("exit", resolve)), stderr).toBe(0);
    expect(stdout).toContain("Resumed “Saved work”.");
    expect(stdout).not.toContain("Response ended while reconnecting");
    expect(receivedSessionId).toBe("target");
  });
});
