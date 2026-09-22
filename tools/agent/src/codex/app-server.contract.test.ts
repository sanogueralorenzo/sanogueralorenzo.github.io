import { lstatSync, readFileSync, symlinkSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import { cleanup, temporary } from "../test-support.js";
import { CodexAppServer, createAgentCodexAppServer, prepareAgentCodexHome, utilityInstructionsPath } from "./app-server.js";

const fixture = join(dirname(fileURLToPath(import.meta.url)), "test-fixtures", "fake-app-server.mjs");

function client(scenario: string, extra: NodeJS.ProcessEnv = {}): CodexAppServer {
  const appServer = new CodexAppServer({
    command: process.execPath,
    args: [fixture],
    env: { ...process.env, AGENT_FAKE_SCENARIO: scenario, ...extra },
  });
  cleanup(() => appServer.stop());
  return appServer;
}

const requests = (log: string) => readFileSync(log, "utf8").trim().split("\n")
  .map((line) => JSON.parse(line) as { method: string; params: Record<string, unknown> });

describe("Codex profile and login", () => {
  it("runs production app-server in a private, locked-down Agent profile", async () => {
    const homeDir = temporary("agent-codex-profile-");
    const envLog = join(homeDir, "env.json");
    const rpcLog = join(homeDir, "rpc.log");
    const appServer = createAgentCodexAppServer(
      { homeDir, codexCommand: process.execPath },
      {
        args: [fixture],
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
    cleanup(() => appServer.stop());
    await appServer.account(false);
    expect(JSON.parse(readFileSync(envLog, "utf8"))).toEqual({
      CODEX_HOME: join(homeDir, "codex"),
      CODEX_SQLITE_HOME: join(homeDir, "codex"),
      CODEX_ACCESS_TOKEN: null,
      OPENAI_API_KEY: null,
    });
    expect(lstatSync(join(homeDir, "codex")).mode & 0o777).toBe(0o700);
    const instructions = join(homeDir, "codex", "instructions.md");
    expect(readFileSync(instructions, "utf8")).toContain("You are Agent, a direct, concise assistant");
    expect(readFileSync(instructions, "utf8")).toContain("delegate to one writer, run read-only reviewers in parallel, consolidate valid findings, then delegate revisions to one fresh writer");
    const utilityInstructions = utilityInstructionsPath(homeDir);
    expect(readFileSync(utilityInstructions, "utf8")).toBe("Follow the instructions supplied for this thread.\n");
    expect(lstatSync(utilityInstructions).mode & 0o777).toBe(0o600);
    expect(readFileSync(join(homeDir, "codex", "config.toml"), "utf8")).toBe(
      `service_tier = "fast"\nmodel_instructions_file = ${JSON.stringify(instructions)}\nmodel_verbosity = "low"\nmodel_reasoning_summary = "concise"\n\n[agents]\nenabled = true\nmax_concurrent_threads_per_session = 8\n`,
    );
    expect(lstatSync(join(homeDir, "codex", "config.toml")).mode & 0o777).toBe(0o600);
    expect(lstatSync(instructions).mode & 0o777).toBe(0o600);
    const initialized = requests(rpcLog).find((message) => message.method === "initialize");
    expect(initialized?.params.capabilities).toEqual({ experimentalApi: true, requestAttestation: false });
  });

  it("refuses a symbolic-link credential profile", () => {
    const homeDir = temporary("agent-codex-profile-link-");
    const target = temporary("agent-codex-profile-target-");
    symlinkSync(target, join(homeDir, "codex"));
    expect(() => prepareAgentCodexHome(homeDir)).toThrow(/real directory/);
  });

  it("always configures fast processing with only the service tier", () => {
    const homeDir = temporary("agent-codex-fast-");
    prepareAgentCodexHome(homeDir);
    const config = readFileSync(join(homeDir, "codex", "config.toml"), "utf8");
    expect(config.match(/^service_tier = "fast"$/gm)).toHaveLength(1);
    expect(config).not.toContain("fast_mode");
    prepareAgentCodexHome(homeDir);
    expect(readFileSync(join(homeDir, "codex", "config.toml"), "utf8")).toBe(config);
  });

  it.each([
    ["browser", "chatgpt", { type: "chatgpt", loginId: "login-1", authUrl: "https://auth.openai.com/fake" }],
    ["headless", "chatgptDeviceCode", {
      type: "chatgptDeviceCode", loginId: "login-1", verificationUrl: "https://auth.openai.com/codex/device", userCode: "Agent-TEST",
    }],
  ] as const)("starts the explicit %s login flow", async (mode, requestType, expected) => {
    const homeDir = temporary(`agent-codex-${mode}-`);
    const log = join(homeDir, "rpc.log");
    const appServer = client("login-success", { AGENT_FAKE_LOG: log });
    const login = await appServer.beginLogin(mode);
    expect(login).toEqual(expected);
    const request = requests(log).find((message) => message.method === "account/login/start");
    expect(request?.params).toEqual({ type: requestType });
    await expect(appServer.waitForLogin(login.loginId, 1_000)).resolves.toEqual({ state: "complete" });
  });

  it("stores API-key authentication in the same private Codex profile", async () => {
    const homeDir = temporary("agent-codex-api-key-");
    const log = join(homeDir, "rpc.log");
    const appServer = client("expired", { AGENT_FAKE_LOG: log });
    await appServer.loginWithApiKey("sk-test-secret");
    await expect(appServer.account()).resolves.toEqual({ account: { type: "apiKey" } });
    expect(requests(log).find((message) => message.method === "account/login/start")?.params)
      .toEqual({ type: "apiKey", apiKey: "[redacted]" });
    expect(readFileSync(log, "utf8")).not.toContain("sk-test-secret");
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
    const homeDir = temporary("agent-codex-login-cancel-");
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

  it("shares one restart when concurrent sessions lose the app-server", async () => {
    const homeDir = temporary("agent-codex-restart-");
    const log = join(homeDir, "rpc.log");
    const appServer = client("normal", { AGENT_FAKE_LOG: log });
    await appServer.account();
    await Promise.all([appServer.restart(), appServer.restart()]);
    await expect(appServer.account()).resolves.toBeDefined();
    expect(requests(log).filter((message) => message.method === "initialize")).toHaveLength(2);
  });

  it("waits for initialization before sending concurrent requests", async () => {
    const homeDir = temporary("agent-codex-concurrent-start-");
    const log = join(homeDir, "rpc.log");
    const appServer = client("normal", { AGENT_FAKE_LOG: log });
    await Promise.all([appServer.account(), appServer.account()]);
    expect(requests(log).map((message) => message.method)).toEqual(["initialize", "initialized", "account/read", "account/read"]);
  });
});
