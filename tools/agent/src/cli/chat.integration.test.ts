import { spawn } from "node:child_process";
import { createServer, type ServerResponse } from "node:http";
import type { AddressInfo } from "node:net";
import { join } from "node:path";
import { describe, expect, it, vi } from "vitest";
import { RUNTIME_PROTOCOL_VERSION } from "../conversation/types.js";
import { writePrivateJson } from "../local/files.js";
import { cleanup, temporary } from "../test-support.js";

describe("CLI shared runs", () => {
  it("submits once and renders the centralized event feed", async () => {
    const homeDir = temporary("agent-cli-runs-");
    let feed: ServerResponse | undefined;
    let openFeed!: () => void;
    const feedReady = new Promise<void>((resolve) => { openFeed = resolve; });
    let receivedTurn: Record<string, unknown> = {};
    const server = createServer(async (request, response) => {
      response.setHeader("content-type", "application/json");
      if (request.url === "/v1/health") return response.end('{"ok":true}');
      if (request.url === "/v1/events") {
        feed = response;
        response.writeHead(200, { "content-type": "text/event-stream" });
        openFeed();
        return;
      }
      if (request.url === "/v1/runs" && request.method === "POST") {
        const chunks: Buffer[] = [];
        for await (const chunk of request) chunks.push(Buffer.from(chunk));
        receivedTurn = JSON.parse(Buffer.concat(chunks).toString()) as Record<string, unknown>;
        response.statusCode = 202;
        response.end('{"run":{"id":"r1","origin":"cli"}}');
        setImmediate(() => feed?.write([
          'data: {"runId":"r1","event":{"type":"turn","text":"hello","channel":"cli","hasAttachments":false}}',
          'data: {"runId":"r1","event":{"type":"text_delta","delta":"CLI answer"}}',
          'data: {"runId":"r1","event":{"type":"done","sessionId":"s1"}}',
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
      'data: {"runId":"remote","event":{"type":"turn","text":"from phone","channel":"telegram","hasAttachments":false}}',
      'data: {"runId":"remote","event":{"type":"text_delta","delta":"Remote answer"}}',
      'data: {"runId":"remote","event":{"type":"done","sessionId":"s1"}}',
      "",
    ].join("\n\n"));
    await vi.waitFor(() => expect(stdout).toContain("Remote answer"), { timeout: 5_000 });
    child.stdin.write("hello\n");
    await vi.waitFor(() => expect(stdout).toContain("CLI answer"), { timeout: 5_000 });
    child.stdin.write("/quit\n");
    const exitCode = await new Promise<number | null>((resolve) => child.once("exit", resolve));

    expect(exitCode, stderr).toBe(0);
    expect(stdout).toContain("telegram › from phone");
    expect(receivedTurn).toMatchObject({ text: "hello", channel: "cli" });
  });
});
