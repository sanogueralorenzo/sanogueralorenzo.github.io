import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, describe, expect, it } from "vitest";
import type { AgentRuntime } from "../core/runtime.js";
import { Store } from "../core/store.js";
import type { RuntimeConfig, RuntimeEvent } from "../core/types.js";
import { readDiscovery, RuntimeServer, type RuntimeSetup } from "./server.js";

const paths: string[] = [];

afterEach(() => {
  for (const path of paths.splice(0)) rmSync(path, { recursive: true, force: true });
});

function setupStub(): RuntimeSetup {
  return {
    status: async () => ({
      configured: false,
      selectedBackend: null,
      recommendedBackend: "codex",
      openAIConfigured: false,
      codex: { installed: false, connected: false, planType: null, allowanceAvailable: null, usage: [] },
    }),
    setOpenAIKey: async () => undefined,
    selectBackend: async () => undefined,
    startCodexLogin: async () => ({ type: "chatgpt", loginId: "login", authUrl: "https://auth.openai.com/fake" }),
    codexLoginStatus: async () => ({ state: "complete" }),
    cancelCodexLogin: async () => undefined,
  };
}

describe("RuntimeServer", () => {
  it("authenticates clients and streams the shared event protocol", async () => {
    const homeDir = mkdtempSync(join(tmpdir(), "agent-server-"));
    paths.push(homeDir);
    const config: RuntimeConfig = {
      homeDir, host: "127.0.0.1", port: 0,
      models: { coordinator: "gpt-5.6-luna", bounded: "gpt-5.6-luna", coding: "gpt-5.6-sol", astra: "gpt-6-astra" },
      maxToolRounds: 2, maxHistoryMessages: 10,
      codexCommand: "codex",
    };
    const store = new Store(homeDir);
    const runtime = {
      async *run(): AsyncGenerator<RuntimeEvent> {
        yield { type: "status", message: "ready" };
        yield { type: "text_delta", delta: "hello" };
        yield { type: "done", sessionId: "session", responseId: "response" };
      },
    } as unknown as AgentRuntime;
    const server = new RuntimeServer(config, runtime, store, setupStub());
    const port = await server.listen();
    const discovery = readDiscovery(homeDir)!;

    const unauthorized = await fetch(`http://127.0.0.1:${port}/v1/sessions`);
    expect(unauthorized.status).toBe(401);
    const streamed = await fetch(`http://127.0.0.1:${port}/v1/chat`, {
      method: "POST",
      headers: { authorization: `Bearer ${discovery.token}`, "content-type": "application/json" },
      body: JSON.stringify({ text: "hello", requestId: "test-request", channel: "api" }),
    });
    const body = await streamed.text();
    expect(streamed.headers.get("content-type")).toContain("text/event-stream");
    expect(body).toContain('"type":"text_delta","delta":"hello"');
    expect(body).toContain('"type":"done"');

    await server.close();
    store.close();
  });

  it("exposes backend-neutral guided setup endpoints", async () => {
    const homeDir = mkdtempSync(join(tmpdir(), "agent-server-setup-"));
    paths.push(homeDir);
    const config: RuntimeConfig = {
      homeDir, host: "127.0.0.1", port: 0,
      models: { coordinator: "gpt-5.6-luna", bounded: "gpt-5.6-luna", coding: "gpt-5.6-sol", astra: "gpt-6-astra" },
      maxToolRounds: 2, maxHistoryMessages: 10, codexCommand: "codex",
    };
    const store = new Store(homeDir);
    const runtime = { async *run() {} } as unknown as AgentRuntime;
    let selected = "";
    const loginModes: string[] = [];
    let cancelledLogin = "";
    const server = new RuntimeServer(config, runtime, store, {
      status: async () => ({
        configured: false,
        selectedBackend: null,
        recommendedBackend: "codex",
        openAIConfigured: false,
        codex: { installed: true, connected: false, planType: null, allowanceAvailable: null, usage: [] },
      }),
      setOpenAIKey: async () => undefined,
      selectBackend: async (backend) => { selected = backend; },
      startCodexLogin: async (mode) => {
        loginModes.push(mode);
        return mode === "headless"
          ? { type: "chatgptDeviceCode", loginId: "login-2", verificationUrl: "https://auth.openai.com/codex/device", userCode: "Agent-TEST" }
          : { type: "chatgpt", loginId: "login-1", authUrl: "https://auth.openai.com/fake" };
      },
      codexLoginStatus: async () => ({ state: "complete" }),
      cancelCodexLogin: async (loginId) => { cancelledLogin = loginId; },
    });
    const port = await server.listen();
    const token = readDiscovery(homeDir)!.token;
    const headers = { authorization: `Bearer ${token}`, "content-type": "application/json" };

    const status = await fetch(`http://127.0.0.1:${port}/v1/setup`, { headers });
    await expect(status.json()).resolves.toMatchObject({ recommendedBackend: "codex", codex: { installed: true } });
    const missingMode = await fetch(`http://127.0.0.1:${port}/v1/setup/codex/login`, {
      method: "POST", headers, body: JSON.stringify({}),
    });
    expect(missingMode.status).toBe(400);
    expect(loginModes).toEqual([]);
    const login = await fetch(`http://127.0.0.1:${port}/v1/setup/codex/login`, {
      method: "POST", headers, body: JSON.stringify({ mode: "browser" }),
    });
    await expect(login.json()).resolves.toEqual({ type: "chatgpt", loginId: "login-1", authUrl: "https://auth.openai.com/fake" });
    expect(loginModes).toEqual(["browser"]);
    const headless = await fetch(`http://127.0.0.1:${port}/v1/setup/codex/login`, {
      method: "POST", headers, body: JSON.stringify({ mode: "headless" }),
    });
    await expect(headless.json()).resolves.toEqual({
      type: "chatgptDeviceCode",
      loginId: "login-2",
      verificationUrl: "https://auth.openai.com/codex/device",
      userCode: "Agent-TEST",
    });
    expect(loginModes).toEqual(["browser", "headless"]);
    const invalidMode = await fetch(`http://127.0.0.1:${port}/v1/setup/codex/login`, {
      method: "POST", headers, body: JSON.stringify({ mode: "device" }),
    });
    expect(invalidMode.status).toBe(400);
    await expect(invalidMode.json()).resolves.toMatchObject({ error: "login mode must be browser or headless" });
    expect(loginModes).toEqual(["browser", "headless"]);
    const completed = await fetch(`http://127.0.0.1:${port}/v1/setup/codex/login/login-1`, { headers });
    await expect(completed.json()).resolves.toEqual({ state: "complete" });
    const cancelled = await fetch(`http://127.0.0.1:${port}/v1/setup/codex/login/login-2/cancel`, { method: "POST", headers });
    await expect(cancelled.json()).resolves.toEqual({ cancelled: true });
    expect(cancelledLogin).toBe("login-2");
    await fetch(`http://127.0.0.1:${port}/v1/setup/backend`, {
      method: "POST", headers, body: JSON.stringify({ backend: "codex" }),
    });
    expect(selected).toBe("codex");

    await server.close();
    store.close();
  });

  it("accepts a graceful restart only after active turns finish", async () => {
    const homeDir = mkdtempSync(join(tmpdir(), "agent-server-restart-"));
    paths.push(homeDir);
    const config: RuntimeConfig = {
      homeDir, host: "127.0.0.1", port: 0,
      models: { coordinator: "gpt-5.6-luna", bounded: "gpt-5.6-luna", coding: "gpt-5.6-sol", astra: "gpt-6-astra" },
      maxToolRounds: 2, maxHistoryMessages: 10, codexCommand: "codex",
    };
    let entered!: () => void;
    let release!: () => void;
    const turnEntered = new Promise<void>((resolve) => { entered = resolve; });
    const turnReleased = new Promise<void>((resolve) => { release = resolve; });
    const runtime = {
      async *run(): AsyncGenerator<RuntimeEvent> {
        entered();
        await turnReleased;
        yield { type: "done", sessionId: "session", responseId: null };
      },
    } as unknown as AgentRuntime;
    let restarted!: () => void;
    const restartCalled = new Promise<void>((resolve) => { restarted = resolve; });
    const store = new Store(homeDir);
    const server = new RuntimeServer(config, runtime, store, setupStub(), restarted);
    const port = await server.listen();
    const token = readDiscovery(homeDir)!.token;
    const headers = { authorization: `Bearer ${token}`, "content-type": "application/json" };

    const chat = fetch(`http://127.0.0.1:${port}/v1/chat`, {
      method: "POST", headers, body: JSON.stringify({ text: "work", requestId: "active", channel: "api" }),
    });
    await turnEntered;
    const busy = await fetch(`http://127.0.0.1:${port}/v1/runtime/restart`, { method: "POST", headers });
    expect(busy.status).toBe(409);

    release();
    await (await chat).text();
    const accepted = await fetch(`http://127.0.0.1:${port}/v1/runtime/restart`, { method: "POST", headers });
    expect(accepted.status).toBe(202);
    await restartCalled;

    await server.close();
    store.close();
  });
});
