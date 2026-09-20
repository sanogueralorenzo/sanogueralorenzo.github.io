import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import type { AgentRuntime } from "../conversation/runtime.js";
import { Store } from "../conversation/store.js";
import type { RuntimeConfig, RuntimeEvent } from "../conversation/types.js";
import { cleanup, temporary } from "../test-support.js";
import { RuntimeServer, type RuntimeSetup } from "./server.js";

function setupStub(overrides: Partial<RuntimeSetup> = {}): RuntimeSetup {
  return {
    status: async () => ({
      configured: false,
      selectedBackend: null,
      openAIConfigured: false,
      codex: { installed: false, connected: false },
    }),
    setOpenAIKey: async () => undefined,
    selectBackend: async () => undefined,
    startCodexLogin: async () => ({ type: "chatgpt", loginId: "login", authUrl: "https://auth.openai.com/fake" }),
    waitForCodexLogin: async () => ({ state: "complete" }),
    ...overrides,
  };
}

const tokenAt = (homeDir: string) => JSON.parse(readFileSync(join(homeDir, "runtime.json"), "utf8")).token as string;

async function serve(runtime: AgentRuntime, setup = setupStub()) {
  const homeDir = temporary("agent-server-");
  const store = new Store(homeDir);
  const config: RuntimeConfig = { homeDir, port: 0, codexCommand: "codex" };
  const server = new RuntimeServer(config, runtime, store, setup);
  const port = await server.listen();
  const token = tokenAt(homeDir);
  const headers = { authorization: `Bearer ${token}`, "content-type": "application/json" };
  cleanup(async () => { await server.close(); store.close(); });
  const request = (path: string, method = "GET", body?: unknown) => fetch(`http://127.0.0.1:${port}${path}`, {
    method, headers, ...(body === undefined ? {} : { body: JSON.stringify(body) }),
  });
  return { port, token, headers, request };
}

describe("RuntimeServer", () => {
  it("authenticates clients and streams the shared event protocol", async () => {
    let receivedTurn: Record<string, unknown> | undefined;
    const runtime = {
      async *run(turn: Record<string, unknown>): AsyncGenerator<RuntimeEvent> {
        receivedTurn = turn;
        yield { type: "status", message: "ready" };
        yield { type: "text_delta", delta: "hello" };
        yield { type: "done", sessionId: "session" };
      },
    } as unknown as AgentRuntime;
    const { port, token, request } = await serve(runtime);
    const unauthorized = await fetch(`http://127.0.0.1:${port}/v1/sessions`);
    expect(unauthorized.status).toBe(401);
    const uploaded = await fetch(`http://127.0.0.1:${port}/v1/attachments`, {
      method: "POST",
      headers: {
        authorization: `Bearer ${token}`,
        "content-type": "audio/ogg",
        "x-agent-filename": encodeURIComponent("voice note.ogg"),
      },
      body: Buffer.from("voice-data"),
    });
    expect(uploaded.status).toBe(201);
    const attachment = await uploaded.json() as { id: string; path?: string };
    expect(attachment.path).toBeUndefined();
    const streamed = await request("/v1/chat", "POST", {
      text: "hello", attachmentIds: [attachment.id], requestId: "test-request", channel: "api",
    });
    const body = await streamed.text();
    expect(streamed.headers.get("content-type")).toContain("text/event-stream");
    expect(body).toContain('"type":"text_delta","delta":"hello"');
    expect(body).toContain('"type":"done"');
    expect(receivedTurn).toMatchObject({
      text: "hello",
      attachmentIds: [attachment.id],
      attachments: [{ id: attachment.id, name: "voice note.ogg", mimeType: "audio/ogg" }],
    });
  });

  it("exposes backend-neutral guided setup endpoints", async () => {
    const runtime = { async *run() {} } as unknown as AgentRuntime;
    let selected = "";
    const loginModes: string[] = [];
    const setup = setupStub({
      status: async () => ({
        configured: false,
        selectedBackend: null,
        openAIConfigured: false,
        codex: { installed: true, connected: false },
      }),
      selectBackend: async (backend) => { selected = backend; },
      startCodexLogin: async (mode) => {
        loginModes.push(mode);
        return mode === "headless"
          ? { type: "chatgptDeviceCode", loginId: "login-2", verificationUrl: "https://auth.openai.com/codex/device", userCode: "Agent-TEST" }
          : { type: "chatgpt", loginId: "login-1", authUrl: "https://auth.openai.com/fake" };
      },
    });
    const { request } = await serve(runtime, setup);

    const status = await request("/v1/setup");
    await expect(status.json()).resolves.toMatchObject({ codex: { installed: true } });
    const missingMode = await request("/v1/setup/codex/login", "POST", {});
    expect(missingMode.status).toBe(400);
    expect(loginModes).toEqual([]);
    expect((await request("/v1/setup/codex/login", "POST", { mode: "browser" })).status).toBe(200);
    expect((await request("/v1/setup/codex/login", "POST", { mode: "headless" })).status).toBe(200);
    expect(loginModes).toEqual(["browser", "headless"]);
    const invalidMode = await request("/v1/setup/codex/login", "POST", { mode: "device" });
    expect(invalidMode.status).toBe(400);
    await expect(invalidMode.json()).resolves.toMatchObject({ error: "login mode must be browser or headless" });
    expect(loginModes).toEqual(["browser", "headless"]);
    const completed = await request("/v1/setup/codex/login/login-1/wait", "POST");
    await expect(completed.json()).resolves.toEqual({ state: "complete" });
    await request("/v1/setup/backend", "POST", { backend: "codex" });
    expect(selected).toBe("codex");
  });
});
