import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, describe, expect, it } from "vitest";
import type { A1RRuntime } from "../core/runtime.js";
import { Store } from "../core/store.js";
import type { RuntimeConfig, RuntimeEvent } from "../core/types.js";
import { readDiscovery, RuntimeServer } from "./server.js";

const paths: string[] = [];

afterEach(() => {
  for (const path of paths.splice(0)) rmSync(path, { recursive: true, force: true });
});

describe("RuntimeServer", () => {
  it("authenticates clients and streams the shared event protocol", async () => {
    const homeDir = mkdtempSync(join(tmpdir(), "a1r-server-"));
    paths.push(homeDir);
    const config: RuntimeConfig = {
      homeDir, host: "127.0.0.1", port: 0,
      models: { fast: "fast", standard: "standard", deep: "deep" },
      maxToolRounds: 2, maxHistoryMessages: 10,
    };
    const store = new Store(homeDir);
    const runtime = {
      async *run(): AsyncGenerator<RuntimeEvent> {
        yield { type: "status", message: "ready" };
        yield { type: "text_delta", delta: "hello" };
        yield { type: "done", sessionId: "session", responseId: "response" };
      },
    } as unknown as A1RRuntime;
    const server = new RuntimeServer(config, runtime, store);
    const port = await server.listen();
    const discovery = readDiscovery(homeDir)!;

    const unauthorized = await fetch(`http://127.0.0.1:${port}/v1/sessions`);
    expect(unauthorized.status).toBe(401);
    const streamed = await fetch(`http://127.0.0.1:${port}/v1/chat`, {
      method: "POST",
      headers: { authorization: `Bearer ${discovery.token}`, "content-type": "application/json" },
      body: JSON.stringify({ text: "hello", requestId: "test-request" }),
    });
    const body = await streamed.text();
    expect(streamed.headers.get("content-type")).toContain("text/event-stream");
    expect(body).toContain('"type":"text_delta","delta":"hello"');
    expect(body).toContain('"type":"done"');

    await server.close();
    store.close();
  });
});
