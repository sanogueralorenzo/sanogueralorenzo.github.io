import { spawn } from "node:child_process";
import { createServer } from "node:http";
import type { AddressInfo } from "node:net";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { writePrivateJson } from "../local/files.js";
import { cleanup, temporary } from "../test-support.js";

describe("CLI stream", () => {
  it("consumes the shared event stream through the real entry point", async () => {
    const homeDir = temporary("agent-cli-stream-");
    let turn: Record<string, unknown> = {};
    let answered!: () => void;
    const responseSent = new Promise<void>((resolve) => { answered = resolve; });
    const server = createServer(async (request, response) => {
      if (request.url === "/v1/health") {
        response.writeHead(200, { "content-type": "application/json" });
        return response.end('{"ok":true}');
      }
      const chunks: Buffer[] = [];
      for await (const chunk of request) chunks.push(Buffer.from(chunk));
      turn = JSON.parse(Buffer.concat(chunks).toString("utf8")) as Record<string, unknown>;
      response.writeHead(200, { "content-type": "text/event-stream" });
      response.end([
        'data: {"type":"session","session":{"id":"cli-session"}}',
        'data: {"type":"text_delta","delta":"CLI answer"}',
        'data: {"type":"done","sessionId":"cli-session"}',
        "",
      ].join("\n\n"));
      answered();
    });
    await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
    cleanup(() => new Promise<void>((resolve) => server.close(() => resolve())));
    writePrivateJson(join(homeDir, "runtime.json"), {
      protocolVersion: 1,
      port: (server.address() as AddressInfo).port,
      token: "test-token",
      pid: process.pid,
    });

    const controller = new AbortController();
    const child = spawn(process.execPath, ["--import", "tsx", "src/bin/agent.ts", "chat"], {
      cwd: process.cwd(),
      env: { ...process.env, AGENT_HOME: homeDir },
      signal: controller.signal,
      stdio: ["pipe", "pipe", "pipe"],
    });
    cleanup(() => {
      controller.abort();
      child.kill("SIGTERM");
    });
    let stdout = "";
    let stderr = "";
    child.stdout.on("data", (chunk) => { stdout += String(chunk); });
    child.stderr.on("data", (chunk) => { stderr += String(chunk); });
    child.stdin.write("hello\n");
    await responseSent;
    child.stdin.end("/quit\n");
    const exitCode = await new Promise<number | null>((resolve, reject) => {
      const timeout = setTimeout(() => reject(new Error("CLI stream test timed out")), 5_000);
      child.once("error", reject);
      child.once("exit", (code) => {
        clearTimeout(timeout);
        resolve(code);
      });
    });

    expect(exitCode, stderr).toBe(0);
    expect(stdout).toContain("CLI answer");
    expect(turn).toMatchObject({ text: "hello", channel: "cli" });
    expect(turn.requestId).toEqual(expect.any(String));
  });
});
