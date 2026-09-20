import { existsSync, lstatSync, mkdtempSync, readFileSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { afterEach, describe, expect, it } from "vitest";
import { BackendRegistry, BackendUnavailableError, type AgentBackend, type BackendTurn } from "../core/backend.js";
import { Store } from "../core/store.js";
import type { RuntimeConfig } from "../core/types.js";
import { AgentRuntime } from "../core/runtime.js";
import { CodexAppServer, CodexRpcError, createAgentCodexAppServer, prepareAgentCodexHome } from "./app-server.js";
import { CodexAllowanceError, CodexAuthenticationError, CodexBackend } from "./backend.js";

const fixture = join(dirname(fileURLToPath(import.meta.url)), "test-fixtures", "fake-app-server.mjs");
const paths: string[] = [];

afterEach(() => {
  for (const path of paths.splice(0)) rmSync(path, { recursive: true, force: true });
});

function temp(name: string): string {
  const path = mkdtempSync(join(tmpdir(), name));
  paths.push(path);
  return path;
}

function client(scenario: string, extra: NodeJS.ProcessEnv = {}): CodexAppServer {
  return new CodexAppServer({
    command: process.execPath,
    args: [fixture],
    installed: true,
    requestTimeoutMs: 2_000,
    env: { ...process.env, AGENT_FAKE_SCENARIO: scenario, ...extra },
  });
}

function config(homeDir: string): RuntimeConfig {
  return {
    homeDir,
    host: "127.0.0.1",
    port: 0,
    models: { coordinator: "gpt-5.6-luna", bounded: "gpt-5.6-luna", coding: "gpt-5.6-sol", astra: "gpt-6-astra" },
    maxToolRounds: 4,
    maxHistoryMessages: 20,
    codexCommand: "codex",
  };
}

function turn(store: Store, homeDir: string, worker: BackendTurn["route"]["worker"] = "coding"): BackendTurn {
  const session = store.resolveSession({ scopeKey: "project:test", kind: "coding", cwd: homeDir, title: "test" });
  return {
    request: { text: "Fix the test", cwd: homeDir, channel: "api" },
    session,
    route: { kind: "coding", worker, reasons: [] },
    instructions: "Act as Agent. Use the supplied memory.",
    workerInstructions: "Act as Agent's internal coding worker.",
    memoryScope: `project:${homeDir}`,
  };
}

async function collect(backend: CodexBackend, input: BackendTurn) {
  const events = [];
  for await (const event of backend.run(input)) events.push(event);
  return events;
}

describe("Codex app-server contract", () => {
  it("runs production app-server in a private, locked-down Agent profile", async () => {
    const homeDir = temp("agent-codex-profile-");
    const envLog = join(homeDir, "env.json");
    const rpcLog = join(homeDir, "rpc.log");
    const appServer = createAgentCodexAppServer(
      { homeDir, codexCommand: process.execPath },
      {
        args: [fixture],
        installed: true,
        env: {
          CODEX_HOME: "/tmp/must-not-be-used",
          CODEX_SQLITE_HOME: "/tmp/must-not-be-used",
          CODEX_ACCESS_TOKEN: "must-not-leak",
          OPENAI_API_KEY: "must-not-leak",
          AGENT_FAKE_SCENARIO: "normal",
          AGENT_FAKE_ENV_LOG: envLog,
          AGENT_FAKE_LOG: rpcLog,
        },
      },
    );

    await appServer.account(false);
    expect(JSON.parse(readFileSync(envLog, "utf8"))).toEqual({
      CODEX_HOME: join(homeDir, "codex"),
      CODEX_SQLITE_HOME: join(homeDir, "codex"),
      CODEX_ACCESS_TOKEN: null,
      OPENAI_API_KEY: null,
    });
    expect(lstatSync(join(homeDir, "codex")).mode & 0o777).toBe(0o700);
    expect(readFileSync(join(homeDir, "codex", "config.toml"), "utf8")).toBe("[agents]\nenabled = false\n");
    expect(lstatSync(join(homeDir, "codex", "config.toml")).mode & 0o777).toBe(0o600);
    const initialized = readFileSync(rpcLog, "utf8").trim().split("\n")
      .map((line) => JSON.parse(line) as { method: string; params: Record<string, unknown> })
      .find((message) => message.method === "initialize");
    expect(initialized?.params.capabilities).toEqual({ experimentalApi: true, requestAttestation: false });
    await appServer.beginLogin("browser");
    await appServer.beginLogin("headless");
    const loginRequests = readFileSync(rpcLog, "utf8").trim().split("\n")
      .map((line) => JSON.parse(line) as { method: string; params: Record<string, unknown> })
      .filter((message) => message.method === "account/login/start");
    expect(loginRequests.map((request) => request.params.type)).toEqual(["chatgpt", "chatgptDeviceCode"]);
    await appServer.stop();
  });

  it("refuses a symbolic-link credential profile", () => {
    const homeDir = temp("agent-codex-profile-link-");
    const target = temp("agent-codex-profile-target-");
    symlinkSync(target, join(homeDir, "codex"));
    expect(() => prepareAgentCodexHome(homeDir)).toThrow(/real directory/);
  });

  it("starts browser login with a neutral local confirmation page", async () => {
    const homeDir = temp("agent-codex-browser-");
    const log = join(homeDir, "rpc.log");
    const appServer = client("login-success", { AGENT_FAKE_LOG: log });
    const login = await appServer.beginLogin("browser");

    expect(login).toEqual({ type: "chatgpt", loginId: "login-1", authUrl: "https://auth.openai.com/fake" });
    const request = readFileSync(log, "utf8").trim().split("\n")
      .map((line) => JSON.parse(line) as { method: string; params: Record<string, unknown> })
      .find((message) => message.method === "account/login/start");
    expect(request?.params).toEqual({ type: "chatgpt" });
    await expect(appServer.waitForLogin(login.loginId, 1_000)).resolves.toEqual({ state: "complete" });
    await appServer.stop();
  });

  it("starts the documented device-code flow only for explicit headless setup", async () => {
    const homeDir = temp("agent-codex-headless-");
    const log = join(homeDir, "rpc.log");
    const appServer = client("login-success", { AGENT_FAKE_LOG: log });
    const login = await appServer.beginLogin("headless");

    expect(login).toEqual({
      type: "chatgptDeviceCode",
      loginId: "login-1",
      verificationUrl: "https://auth.openai.com/codex/device",
      userCode: "Agent-TEST",
    });
    const request = readFileSync(log, "utf8").trim().split("\n")
      .map((line) => JSON.parse(line) as { method: string; params: Record<string, unknown> })
      .find((message) => message.method === "account/login/start");
    expect(request?.params).toEqual({ type: "chatgptDeviceCode" });
    await expect(appServer.waitForLogin(login.loginId, 1_000)).resolves.toEqual({ state: "complete" });
    await appServer.stop();
  });

  it("rejects a device response during browser login instead of switching flows", async () => {
    const appServer = client("device-response");
    await expect(appServer.beginLogin("browser")).rejects.toThrow(/valid browser login/);
    await appServer.stop();
  });

  it("rejects a browser response during headless login instead of switching flows", async () => {
    const appServer = client("browser-response");
    await expect(appServer.beginLogin("headless")).rejects.toThrow(/valid headless login/);
    await appServer.stop();
  });

  it.each([
    ["browser", "login-failed", "ChatGPT sign-in failed"],
    ["headless", "login-expired", "The one-time code expired"],
    ["headless", "login-cancelled", "ChatGPT sign-in was cancelled"],
  ] as const)("surfaces %s login failure state without exposing credentials", async (mode, scenario, error) => {
    const appServer = client(scenario);
    const login = await appServer.beginLogin(mode);
    await expect(appServer.waitForLogin(login.loginId, 1_000)).resolves.toEqual({ state: "failed", error });
    await appServer.stop();
  });

  it("times out a pending headless login clearly", async () => {
    const appServer = client("login-pending");
    const login = await appServer.beginLogin("headless");
    await expect(appServer.waitForLogin(login.loginId, 10)).resolves.toEqual({ state: "failed", error: "Login timed out. Run setup again." });
    await appServer.stop();
  });

  it("cancels a pending headless login when setup is interrupted", async () => {
    const homeDir = temp("agent-codex-login-cancel-");
    const log = join(homeDir, "rpc.log");
    const appServer = client("login-pending", { AGENT_FAKE_LOG: log });
    const login = await appServer.beginLogin("headless");
    const controller = new AbortController();
    const waiting = appServer.waitForLogin(login.loginId, 1_000, controller.signal);

    controller.abort();

    await expect(waiting).resolves.toEqual({ state: "failed", error: "Setup cancelled." });
    await new Promise((resolve) => setTimeout(resolve, 20));
    expect(readFileSync(log, "utf8")).toContain("account/login/cancel");
    await appServer.stop();
  });

  it("normalizes streamed agent and tool events", async () => {
    const homeDir = temp("agent-codex-stream-");
    const store = new Store(homeDir);
    const appServer = client("normal");
    const backend = new CodexBackend(config(homeDir), store, appServer);
    const events = await collect(backend, turn(store, homeDir));

    expect(events.map((event) => event.type)).toEqual(["tool_start", "tool_end", "text_delta", "done"]);
    expect(events.find((event) => event.type === "text_delta")).toMatchObject({ delta: "Hello from Codex." });
    expect(store.backendSession(turn(store, homeDir).session.id, "codex")).toBe("thread-2");
    await backend.close();
    store.close();
  });

  it("streams Opus through private Codex realtime for runtime-owned transcription", async () => {
    const homeDir = temp("agent-codex-voice-");
    const log = join(homeDir, "rpc.log");
    const audioPath = join(homeDir, "voice.ogg");
    writeFileSync(audioPath, Buffer.from("T2dnUwACAAAAAAAAAAA4TQibAAAAABbLz/IBE09wdXNIZWFkAQE4AYC7AAAAAABPZ2dTAAAAAAAAAAAAADhNCJsBAAAACYU5GQE8T3B1c1RhZ3MMAAAATGF2ZjYzLjEuMTAyAQAAABwAAABlbmNvZGVyPUxhdmM2My4xLjEwMiBsaWJvcHVzT2dnUwAEuAgAAAAAAAA4TQibAgAAAASvZ7YDDRYOCINtgtAc/epJ/gE/wAinGl2KmC5fbwXLShrtt/PI1gXBXsAIBm0zkArsfUCzkSIpxA==", "base64"));
    const store = new Store(homeDir);
    const accepted: string[] = [];
    const sent: number[] = [];
    const backend = new CodexBackend(config(homeDir), store, client("normal", { AGENT_FAKE_LOG: log }), () => ({
      offer: async () => "fake-offer",
      accept: async (sdp) => { accepted.push(sdp); },
      sendAudio: async (audio) => { sent.push(audio.frames.length); },
      close: async () => undefined,
    }));

    await expect(backend.transcribeAudio({
      id: "voice-1", kind: "audio", name: "voice.ogg", mimeType: "audio/ogg",
      size: 214, path: audioPath, createdAt: new Date(0).toISOString(),
    })).resolves.toBe("Hello from Codex.");

    const requests = readFileSync(log, "utf8").trim().split("\n")
      .map((line) => JSON.parse(line) as { method: string; params: Record<string, unknown> });
    expect(requests.some((request) => request.method === "turn/start")).toBe(false);
    expect(requests.find((request) => request.method === "thread/realtime/start")?.params).toMatchObject({
      outputModality: "audio",
      includeStartupContext: false,
      clientManagedHandoffs: true,
      version: "v3",
      transport: { type: "webrtc", sdp: "fake-offer" },
    });
    expect(accepted).toEqual(["fake-answer"]);
    expect(sent[0]).toBeGreaterThan(0);
    expect(requests.some((request) => request.method === "thread/realtime/appendAudio")).toBe(false);
    expect(requests.at(-1)?.method).toBe("thread/realtime/stop");
    expect(readFileSync(log, "utf8")).not.toContain("OPENAI_API_KEY");
    await backend.close();
    store.close();
  });

  it("copies generated images into one backend-neutral artifact event", async () => {
    const homeDir = temp("agent-codex-artifact-");
    const generated = join(homeDir, "generated.png");
    writeFileSync(generated, "png-data");
    const store = new Store(homeDir);
    const backend = new CodexBackend(config(homeDir), store, client("image", { AGENT_FAKE_ARTIFACT: generated }));
    const events = await collect(backend, turn(store, homeDir, null));
    const event = events.find((candidate) => candidate.type === "artifact");

    expect(event).toMatchObject({ type: "artifact", artifact: { kind: "image", name: "generated.png", mimeType: "image/png" } });
    expect(event?.type === "artifact" && event.artifact.path).not.toBe(generated);
    expect(event?.type === "artifact" && existsSync(event.artifact.path)).toBe(true);
    await backend.close();
    store.close();
  });

  it("pins Sol-high coding work and Luna-high coordination without exposing native subagents", async () => {
    const homeDir = temp("agent-codex-model-policy-");
    const log = join(homeDir, "rpc.log");
    const store = new Store(homeDir);
    const backend = new CodexBackend(config(homeDir), store, client("normal", { AGENT_FAKE_LOG: log }));

    await collect(backend, turn(store, homeDir));

    const requests = readFileSync(log, "utf8").trim().split("\n")
      .map((line) => JSON.parse(line) as { method: string; params: Record<string, unknown> });
    const threads = requests.filter((request) => request.method === "thread/start");
    const turns = requests.filter((request) => request.method === "turn/start");
    expect(threads.map((request) => [request.params.model, request.params.sandbox, request.params.ephemeral])).toEqual([
      ["gpt-5.6-sol", "workspace-write", true],
      ["gpt-5.6-luna", "read-only", false],
    ]);
    expect(turns.map((request) => [request.params.model, request.params.effort])).toEqual([
      ["gpt-5.6-sol", "high"],
      ["gpt-5.6-luna", "high"],
    ]);
    expect(readFileSync(log, "utf8")).not.toContain("gpt-6-astra");
    await backend.close();
    store.close();
  });

  it("starts Astra-high only when the route records an explicit request", async () => {
    const homeDir = temp("agent-codex-astra-policy-");
    const log = join(homeDir, "rpc.log");
    const store = new Store(homeDir);
    const backend = new CodexBackend(config(homeDir), store, client("normal", { AGENT_FAKE_LOG: log }));
    const input = turn(store, homeDir, "astra");
    input.request.text = "Use Astra high to investigate this architecture";

    await collect(backend, input);

    const requests = readFileSync(log, "utf8").trim().split("\n")
      .map((line) => JSON.parse(line) as { method: string; params: Record<string, unknown> });
    expect(requests.filter((request) => request.method === "thread/start").map((request) => request.params.model)).toEqual([
      "gpt-6-astra",
      "gpt-5.6-luna",
    ]);
    expect(requests.filter((request) => request.method === "turn/start").map((request) => request.params.effort)).toEqual(["high", "high"]);
    await backend.close();
    store.close();
  });

  it("uses the unchanged Agent session, transcript, and client event contract", async () => {
    const homeDir = temp("agent-codex-runtime-");
    const store = new Store(homeDir);
    store.setSetting("backend", "codex");
    const appServer = client("normal");
    const codex = new CodexBackend(config(homeDir), store, appServer);
    const responses: AgentBackend = {
      kind: "responses", label: "responses", isConfigured: () => false,
      async *run() { yield { type: "done", responseId: null }; },
    };
    const runtime = new AgentRuntime(config(homeDir), store, new BackendRegistry(store, responses, codex));
    const events = [];
    for await (const event of runtime.run({ text: "Fix the test", cwd: homeDir, channel: "api" })) events.push(event);

    expect(events[0]).toMatchObject({ type: "session", backend: "codex" });
    expect(events.map((event) => event.type)).toEqual(["session", "tool_start", "tool_end", "text_delta", "done"]);
    const session = events[0]?.type === "session" ? events[0].session : null;
    expect(session && store.getMessages(session.id).map((message) => message.role)).toEqual(["user", "tool", "assistant"]);
    await codex.close();
    store.close();
  });

  it("interrupts an active turn through turn/interrupt", async () => {
    const homeDir = temp("agent-codex-cancel-");
    const log = join(homeDir, "rpc.log");
    const store = new Store(homeDir);
    const appServer = client("cancel", { AGENT_FAKE_LOG: log });
    const backend = new CodexBackend(config(homeDir), store, appServer);
    const controller = new AbortController();
    const input = { ...turn(store, homeDir), signal: controller.signal };
    const running = collect(backend, input);
    setTimeout(() => controller.abort(), 50);

    await expect(running).rejects.toMatchObject({ name: "AbortError" });
    await new Promise((resolve) => setTimeout(resolve, 30));
    expect(readFileSync(log, "utf8")).toContain("turn/interrupt");
    await backend.close();
    store.close();
  });

  it("restarts app-server and resumes the opaque Codex thread", async () => {
    const homeDir = temp("agent-codex-reconnect-");
    const marker = join(homeDir, "restart.marker");
    const log = join(homeDir, "rpc.log");
    const store = new Store(homeDir);
    const appServer = client("reconnect", { AGENT_FAKE_MARKER: marker, AGENT_FAKE_LOG: log });
    const backend = new CodexBackend(config(homeDir), store, appServer);
    const events = await collect(backend, turn(store, homeDir));

    expect(events).toContainEqual({ type: "text_delta", delta: "Hello from Codex." });
    expect(readFileSync(log, "utf8").match(/"method":"thread\/start"/g)?.length).toBeGreaterThanOrEqual(2);
    await backend.close();
    store.close();
  });

  it("does not replace a missing Codex thread", async () => {
    const homeDir = temp("agent-codex-missing-thread-");
    const log = join(homeDir, "rpc.log");
    const store = new Store(homeDir);
    const input = turn(store, homeDir, null);
    store.bindBackendSession(input.session.id, "codex", "missing-thread-id");
    const backend = new CodexBackend(config(homeDir), store, client("missing-thread", { AGENT_FAKE_LOG: log }));

    await expect(collect(backend, input)).rejects.toBeInstanceOf(CodexRpcError);

    expect(readFileSync(log, "utf8")).toContain("thread/resume");
    expect(readFileSync(log, "utf8")).not.toContain("thread/start");
    expect(store.backendSession(input.session.id, "codex")).toBe("missing-thread-id");
    await backend.close();
    store.close();
  });

  it("reports expired authentication distinctly", async () => {
    const homeDir = temp("agent-codex-auth-");
    const store = new Store(homeDir);
    const backend = new CodexBackend(config(homeDir), store, client("expired"));
    await expect(collect(backend, turn(store, homeDir))).rejects.toBeInstanceOf(CodexAuthenticationError);
    await backend.close();
    store.close();
  });

  it("reports exhausted included allowance without using an API key", async () => {
    const homeDir = temp("agent-codex-limit-");
    const store = new Store(homeDir);
    const backend = new CodexBackend(config(homeDir), store, client("exhausted"));
    await expect(collect(backend, turn(store, homeDir))).rejects.toBeInstanceOf(CodexAllowanceError);
    await backend.close();
    store.close();
  });

  it("uses API-key mode only after it was explicitly selected", async () => {
    const homeDir = temp("agent-codex-explicit-api-");
    const store = new Store(homeDir);
    const backend = (kind: "codex" | "responses", configured: boolean): AgentBackend => ({
      kind,
      label: kind,
      isConfigured: () => configured,
      async *run() { yield { type: "done", responseId: null }; },
    });
    const responses = backend("responses", true);
    const registry = new BackendRegistry(store, responses, backend("codex", false));

    await expect(registry.resolve()).rejects.toBeInstanceOf(BackendUnavailableError);
    store.setSetting("backend", "responses");
    await expect(registry.resolve()).resolves.toBe(responses);
    store.setSetting("backend", "codex");
    await expect(new BackendRegistry(store, responses).resolve()).rejects.toBeInstanceOf(BackendUnavailableError);
    store.close();
  });
});
