import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { afterEach, describe, expect, it } from "vitest";
import { BackendRegistry, BackendUnavailableError, type AgentBackend, type BackendTurn } from "../core/backend.js";
import { Store } from "../core/store.js";
import type { RuntimeConfig } from "../core/types.js";
import { A1RRuntime } from "../core/runtime.js";
import { CodexAppServer } from "./app-server.js";
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
    env: { ...process.env, A1R_FAKE_SCENARIO: scenario, ...extra },
  });
}

function config(homeDir: string): RuntimeConfig {
  return {
    homeDir,
    host: "127.0.0.1",
    port: 0,
    models: { fast: "fast", standard: "standard", deep: "deep" },
    maxToolRounds: 4,
    maxHistoryMessages: 20,
    codexCommand: "codex",
  };
}

function turn(store: Store, homeDir: string): BackendTurn {
  const session = store.resolveSession({ scopeKey: "project:test", kind: "coding", cwd: homeDir, title: "test" });
  return {
    request: { text: "Fix the test", cwd: homeDir, channel: "api" },
    session,
    route: { kind: "coding", tier: "standard", reasons: [], allowTools: true, allowDelegation: true },
    instructions: "Act as A1R. Use the supplied memory.",
    memoryScope: `project:${homeDir}`,
  };
}

async function collect(backend: CodexBackend, input: BackendTurn) {
  const events = [];
  for await (const event of backend.run(input)) events.push(event);
  return events;
}

describe("Codex app-server contract", () => {
  it("supports browser and device-code login without handling tokens", async () => {
    for (const mode of ["browser", "device"] as const) {
      const appServer = client("login-success");
      const login = await appServer.beginLogin(mode);
      expect(login.loginId).toBe("login-1");
      if (mode === "browser") expect(login.type === "chatgpt" && login.authUrl).toContain("auth.openai.com");
      else expect(login.type === "chatgptDeviceCode" && login.userCode).toBe("A1R-TEST");
      await expect(appServer.waitForLogin(login.loginId, 1_000)).resolves.toEqual({ state: "complete" });
      await appServer.stop();
    }
  });

  it("surfaces a failed login without exposing credentials", async () => {
    const appServer = client("login-failed");
    const login = await appServer.beginLogin("device");
    await expect(appServer.waitForLogin(login.loginId, 1_000)).resolves.toEqual({ state: "failed", error: "expired code" });
    await appServer.stop();
  });

  it("normalizes streamed agent and tool events", async () => {
    const homeDir = temp("a1r-codex-stream-");
    const store = new Store(homeDir);
    const appServer = client("normal");
    const backend = new CodexBackend(config(homeDir), store, appServer);
    const events = await collect(backend, turn(store, homeDir));

    expect(events.map((event) => event.type)).toEqual(["tool_start", "tool_end", "text_delta", "done"]);
    expect(events.find((event) => event.type === "text_delta")).toMatchObject({ delta: "Hello from Codex." });
    expect(store.backendSession(turn(store, homeDir).session.id, "codex")).toBe("thread-1");
    await backend.close();
    store.close();
  });

  it("uses the unchanged A1R session, transcript, and client event contract", async () => {
    const homeDir = temp("a1r-codex-runtime-");
    const store = new Store(homeDir);
    store.setSetting("backend", "codex");
    const appServer = client("normal");
    const codex = new CodexBackend(config(homeDir), store, appServer);
    const responses: AgentBackend = {
      kind: "responses", label: "responses", isConfigured: () => false,
      async *run() { yield { type: "done", responseId: null }; },
    };
    const runtime = new A1RRuntime(config(homeDir), store, new BackendRegistry(store, responses, codex));
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
    const homeDir = temp("a1r-codex-cancel-");
    const log = join(homeDir, "rpc.log");
    const store = new Store(homeDir);
    const appServer = client("cancel", { A1R_FAKE_LOG: log });
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
    const homeDir = temp("a1r-codex-reconnect-");
    const marker = join(homeDir, "restart.marker");
    const log = join(homeDir, "rpc.log");
    const store = new Store(homeDir);
    const appServer = client("reconnect", { A1R_FAKE_MARKER: marker, A1R_FAKE_LOG: log });
    const backend = new CodexBackend(config(homeDir), store, appServer);
    const events = await collect(backend, turn(store, homeDir));

    expect(events).toContainEqual({ type: "status", message: "Codex restarted. Resuming your A1R session…" });
    expect(events).toContainEqual({ type: "text_delta", delta: "Hello from Codex." });
    expect(readFileSync(log, "utf8")).toContain("thread/resume");
    await backend.close();
    store.close();
  });

  it("reports expired authentication distinctly", async () => {
    const homeDir = temp("a1r-codex-auth-");
    const store = new Store(homeDir);
    const backend = new CodexBackend(config(homeDir), store, client("expired"));
    await expect(collect(backend, turn(store, homeDir))).rejects.toBeInstanceOf(CodexAuthenticationError);
    await backend.close();
    store.close();
  });

  it("reports exhausted included allowance without using an API key", async () => {
    const homeDir = temp("a1r-codex-limit-");
    const store = new Store(homeDir);
    const backend = new CodexBackend(config(homeDir), store, client("exhausted"));
    await expect(collect(backend, turn(store, homeDir))).rejects.toBeInstanceOf(CodexAllowanceError);
    await backend.close();
    store.close();
  });

  it("keeps API-key mode as the remembered fallback", async () => {
    const homeDir = temp("a1r-codex-fallback-");
    const store = new Store(homeDir);
    const backend = (kind: "codex" | "responses", configured: boolean): AgentBackend => ({
      kind,
      label: kind,
      isConfigured: () => configured,
      async *run() { yield { type: "done", responseId: null }; },
    });
    const responses = backend("responses", true);
    const registry = new BackendRegistry(store, responses, backend("codex", false));

    await expect(registry.resolve()).resolves.toBe(responses);
    store.setSetting("backend", "responses");
    await expect(registry.resolve()).resolves.toBe(responses);
    store.setSetting("backend", "codex");
    await expect(new BackendRegistry(store, responses).resolve()).rejects.toBeInstanceOf(BackendUnavailableError);
    store.close();
  });
});
