import { existsSync, lstatSync, mkdtempSync, readFileSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { afterEach, describe, expect, it } from "vitest";
import { BackendRegistry, BackendUnavailableError, type AgentBackend, type BackendTurn } from "../conversation/backend.js";
import { Store } from "../conversation/store.js";
import type { RuntimeConfig } from "../conversation/types.js";
import { AgentRuntime } from "../conversation/runtime.js";
import { CodexAppServer, CodexRpcError, createAgentCodexAppServer, prepareAgentCodexHome } from "./app-server.js";
import { CodexAllowanceError, CodexAuthenticationError, CodexBackend } from "./backend.js";

const fixture = join(dirname(fileURLToPath(import.meta.url)), "test-fixtures", "fake-app-server.mjs");
const paths: string[] = [];
const clients: CodexAppServer[] = [];
const stores: Store[] = [];

afterEach(async () => {
  await Promise.all(clients.splice(0).map((client) => client.stop()));
  for (const store of stores.splice(0)) store.close();
  for (const path of paths.splice(0)) rmSync(path, { recursive: true, force: true });
});

function temp(name: string): string {
  const path = mkdtempSync(join(tmpdir(), name));
  paths.push(path);
  return path;
}

function client(scenario: string, extra: NodeJS.ProcessEnv = {}): CodexAppServer {
  const appServer = new CodexAppServer({
    command: process.execPath,
    args: [fixture],
    installed: true,
    requestTimeoutMs: 2_000,
    env: { ...process.env, AGENT_FAKE_SCENARIO: scenario, ...extra },
  });
  clients.push(appServer);
  return appServer;
}

function trackedStore(homeDir: string): Store {
  const value = new Store(homeDir);
  stores.push(value);
  return value;
}

const requests = (log: string) => readFileSync(log, "utf8").trim().split("\n")
  .map((line) => JSON.parse(line) as { method: string; params: Record<string, unknown> });

function config(homeDir: string): RuntimeConfig {
  return {
    homeDir,
    host: "127.0.0.1",
    port: 0,
    codexCommand: "codex",
  };
}

function turn(store: Store, homeDir: string, worker: BackendTurn["route"]["worker"] = "coding"): BackendTurn {
  const session = store.resolveSession({ scopeKey: "project:test", kind: "coding", cwd: homeDir, title: "test" });
  return {
    request: { text: "Fix the test", cwd: homeDir, channel: "api" },
    session,
    route: { kind: "coding", worker },
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

function backendFixture(scenario = "normal", extra: NodeJS.ProcessEnv = {}, worker: BackendTurn["route"]["worker"] = "coding") {
  const homeDir = temp("agent-codex-");
  const log = join(homeDir, "rpc.log");
  const store = trackedStore(homeDir);
  const backend = new CodexBackend(config(homeDir), store, client(scenario, { AGENT_FAKE_LOG: log, ...extra }));
  return { homeDir, log, store, backend, input: turn(store, homeDir, worker) };
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
    clients.push(appServer);

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
    const initialized = requests(rpcLog).find((message) => message.method === "initialize");
    expect(initialized?.params.capabilities).toEqual({ experimentalApi: true, requestAttestation: false });
    await appServer.beginLogin("browser");
    await appServer.beginLogin("headless");
    const loginRequests = requests(rpcLog).filter((message) => message.method === "account/login/start");
    expect(loginRequests.map((request) => request.params.type)).toEqual(["chatgpt", "chatgptDeviceCode"]);
  });

  it("refuses a symbolic-link credential profile", () => {
    const homeDir = temp("agent-codex-profile-link-");
    const target = temp("agent-codex-profile-target-");
    symlinkSync(target, join(homeDir, "codex"));
    expect(() => prepareAgentCodexHome(homeDir)).toThrow(/real directory/);
  });

  it.each([
    ["browser", "chatgpt", { type: "chatgpt", loginId: "login-1", authUrl: "https://auth.openai.com/fake" }],
    ["headless", "chatgptDeviceCode", {
      type: "chatgptDeviceCode", loginId: "login-1", verificationUrl: "https://auth.openai.com/codex/device", userCode: "Agent-TEST",
    }],
  ] as const)("starts the explicit %s login flow", async (mode, requestType, expected) => {
    const homeDir = temp(`agent-codex-${mode}-`);
    const log = join(homeDir, "rpc.log");
    const appServer = client("login-success", { AGENT_FAKE_LOG: log });
    const login = await appServer.beginLogin(mode);

    expect(login).toEqual(expected);
    const request = requests(log).find((message) => message.method === "account/login/start");
    expect(request?.params).toEqual({ type: requestType });
    await expect(appServer.waitForLogin(login.loginId, 1_000)).resolves.toEqual({ state: "complete" });
  });

  it.each([
    ["browser", "device-response"],
    ["headless", "browser-response"],
  ] as const)("never substitutes another flow for %s login", async (mode, scenario) => {
    await expect(client(scenario).beginLogin(mode)).rejects.toThrow(new RegExp(`valid ${mode} login`));
  });

  it.each([
    ["browser", "login-failed", "ChatGPT sign-in failed"],
    ["headless", "login-expired", "The one-time code expired"],
    ["headless", "login-cancelled", "ChatGPT sign-in was cancelled"],
  ] as const)("surfaces %s login failure state without exposing credentials", async (mode, scenario, error) => {
    const appServer = client(scenario);
    const login = await appServer.beginLogin(mode);
    await expect(appServer.waitForLogin(login.loginId, 1_000)).resolves.toEqual({ state: "failed", error });
  });

  it("times out a pending headless login clearly", async () => {
    const appServer = client("login-pending");
    const login = await appServer.beginLogin("headless");
    await expect(appServer.waitForLogin(login.loginId, 10)).resolves.toEqual({ state: "failed", error: "Login timed out. Run setup again." });
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
  });

  it("normalizes streamed agent and tool events", async () => {
    const { store, backend, input } = backendFixture();
    const events = await collect(backend, input);

    expect(events.map((event) => event.type)).toEqual(["tool_start", "tool_end", "text_delta", "done"]);
    expect(events.find((event) => event.type === "text_delta")).toMatchObject({ delta: "Hello from Codex." });
    expect(store.backendSession(input.session.id, "codex")).toBe("thread-2");
  });

  it("streams Opus through private Codex realtime for runtime-owned transcription", async () => {
    const homeDir = temp("agent-codex-voice-");
    const log = join(homeDir, "rpc.log");
    const audioPath = join(homeDir, "voice.ogg");
    writeFileSync(audioPath, Buffer.from("T2dnUwACAAAAAAAAAAA4TQibAAAAABbLz/IBE09wdXNIZWFkAQE4AYC7AAAAAABPZ2dTAAAAAAAAAAAAADhNCJsBAAAACYU5GQE8T3B1c1RhZ3MMAAAATGF2ZjYzLjEuMTAyAQAAABwAAABlbmNvZGVyPUxhdmM2My4xLjEwMiBsaWJvcHVzT2dnUwAEuAgAAAAAAAA4TQibAgAAAASvZ7YDDRYOCINtgtAc/epJ/gE/wAinGl2KmC5fbwXLShrtt/PI1gXBXsAIBm0zkArsfUCzkSIpxA==", "base64"));
    const store = trackedStore(homeDir);
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
      size: 214, path: audioPath,
    })).resolves.toBe("Hello from Codex.");

    const rpc = requests(log);
    expect(rpc.some((request) => request.method === "turn/start")).toBe(false);
    expect(rpc.find((request) => request.method === "thread/realtime/start")?.params).toMatchObject({
      outputModality: "audio",
      includeStartupContext: false,
      clientManagedHandoffs: true,
      version: "v3",
      transport: { type: "webrtc", sdp: "fake-offer" },
    });
    expect(accepted).toEqual(["fake-answer"]);
    expect(sent[0]).toBeGreaterThan(0);
    expect(rpc.some((request) => request.method === "thread/realtime/appendAudio")).toBe(false);
    expect(rpc.at(-1)?.method).toBe("thread/realtime/stop");
    expect(readFileSync(log, "utf8")).not.toContain("OPENAI_API_KEY");
  });

  it("copies generated images into one backend-neutral artifact event", async () => {
    const homeDir = temp("agent-codex-artifact-");
    const generated = join(homeDir, "generated.png");
    writeFileSync(generated, "png-data");
    const store = trackedStore(homeDir);
    const backend = new CodexBackend(config(homeDir), store, client("image", { AGENT_FAKE_ARTIFACT: generated }));
    const events = await collect(backend, turn(store, homeDir, null));
    const event = events.find((candidate) => candidate.type === "artifact");

    expect(event).toMatchObject({ type: "artifact", artifact: { kind: "image", name: "generated.png", mimeType: "image/png" } });
    expect(event?.type === "artifact" && event.artifact.path).not.toBe(generated);
    expect(event?.type === "artifact" && existsSync(event.artifact.path)).toBe(true);
  });

  it("pins Sol-high coding work and Luna-high coordination without exposing native subagents", async () => {
    const { backend, input, log } = backendFixture();
    await collect(backend, input);

    const rpc = requests(log);
    const threads = rpc.filter((request) => request.method === "thread/start");
    const turns = rpc.filter((request) => request.method === "turn/start");
    expect(threads.map((request) => [request.params.model, request.params.sandbox, request.params.ephemeral])).toEqual([
      ["gpt-5.6-sol", "workspace-write", true],
      ["gpt-5.6-luna", "read-only", false],
    ]);
    expect(turns.map((request) => [request.params.model, request.params.effort])).toEqual([
      ["gpt-5.6-sol", "high"],
      ["gpt-5.6-luna", "high"],
    ]);
    expect(readFileSync(log, "utf8")).not.toContain("gpt-6-astra");
  });

  it("starts Astra-high only when the route records an explicit request", async () => {
    const { backend, input, log } = backendFixture("normal", {}, "astra");
    input.request.text = "Use Astra high to investigate this architecture";

    await collect(backend, input);

    const rpc = requests(log);
    expect(rpc.filter((request) => request.method === "thread/start").map((request) => request.params.model)).toEqual([
      "gpt-6-astra",
      "gpt-5.6-luna",
    ]);
    expect(rpc.filter((request) => request.method === "turn/start").map((request) => request.params.effort)).toEqual(["high", "high"]);
  });

  it("uses the unchanged Agent session, transcript, and client event contract", async () => {
    const homeDir = temp("agent-codex-runtime-");
    const store = trackedStore(homeDir);
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

    expect(events[0]).toMatchObject({ type: "session" });
    expect(events.map((event) => event.type)).toEqual(["session", "tool_start", "tool_end", "text_delta", "done"]);
    const session = events[0]?.type === "session" ? events[0].session : null;
    expect(session && store.getMessages(session.id).map((message) => message.role)).toEqual(["user", "tool", "assistant"]);
  });

  it("interrupts an active turn through turn/interrupt", async () => {
    const homeDir = temp("agent-codex-cancel-");
    const log = join(homeDir, "rpc.log");
    const store = trackedStore(homeDir);
    const appServer = client("cancel", { AGENT_FAKE_LOG: log });
    const backend = new CodexBackend(config(homeDir), store, appServer);
    const controller = new AbortController();
    const input = { ...turn(store, homeDir), signal: controller.signal };
    const running = collect(backend, input);
    setTimeout(() => controller.abort(), 50);

    await expect(running).rejects.toMatchObject({ name: "AbortError" });
    await new Promise((resolve) => setTimeout(resolve, 30));
    expect(readFileSync(log, "utf8")).toContain("turn/interrupt");
  });

  it("restarts app-server and resumes the opaque Codex thread", async () => {
    const homeDir = temp("agent-codex-reconnect-");
    const marker = join(homeDir, "restart.marker");
    const log = join(homeDir, "rpc.log");
    const store = trackedStore(homeDir);
    const appServer = client("reconnect", { AGENT_FAKE_MARKER: marker, AGENT_FAKE_LOG: log });
    const backend = new CodexBackend(config(homeDir), store, appServer);
    const events = await collect(backend, turn(store, homeDir));

    expect(events).toContainEqual({ type: "text_delta", delta: "Hello from Codex." });
    expect(readFileSync(log, "utf8").match(/"method":"thread\/start"/g)?.length).toBeGreaterThanOrEqual(2);
  });

  it("does not replace a missing Codex thread", async () => {
    const homeDir = temp("agent-codex-missing-thread-");
    const log = join(homeDir, "rpc.log");
    const store = trackedStore(homeDir);
    const input = turn(store, homeDir, null);
    store.bindBackendSession(input.session.id, "codex", "missing-thread-id");
    const backend = new CodexBackend(config(homeDir), store, client("missing-thread", { AGENT_FAKE_LOG: log }));

    await expect(collect(backend, input)).rejects.toBeInstanceOf(CodexRpcError);

    expect(readFileSync(log, "utf8")).toContain("thread/resume");
    expect(readFileSync(log, "utf8")).not.toContain("thread/start");
    expect(store.backendSession(input.session.id, "codex")).toBe("missing-thread-id");
  });

  it.each([
    ["expired", CodexAuthenticationError],
    ["exhausted", CodexAllowanceError],
  ])("classifies %s account failures", async (scenario, ErrorType) => {
    const { backend, input } = backendFixture(scenario);
    await expect(collect(backend, input)).rejects.toBeInstanceOf(ErrorType);
  });

  it("uses API-key mode only after it was explicitly selected", async () => {
    const homeDir = temp("agent-codex-explicit-api-");
    const store = trackedStore(homeDir);
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
  });
});
