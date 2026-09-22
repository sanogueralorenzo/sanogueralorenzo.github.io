import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import { CodexAppServer } from "../codex/app-server.js";
import { cleanup } from "../test-support.js";
import { AgentSetupService } from "./service.js";

const fakeServer = join(dirname(fileURLToPath(import.meta.url)), "..", "codex", "test-fixtures", "fake-app-server.mjs");

function setup(scenario: string | null) {
  const codex = scenario === null
    ? new CodexAppServer({ command: "missing-codex" })
    : new CodexAppServer({
      command: process.execPath,
      args: [fakeServer],
      env: { ...process.env, AGENT_FAKE_SCENARIO: scenario },
    });
  const service = new AgentSetupService(codex);
  cleanup(() => { codex.stop(); });
  return { service };
}

describe("AgentSetupService", () => {
  it.each([
    ["normal", { configured: true, authMode: "chatgpt", codex: { installed: true, connected: true } }],
    ["api-account", { configured: true, authMode: "apiKey", codex: { installed: true, connected: true } }],
    ["expired", { configured: false, authMode: null, codex: { installed: true, connected: false } }],
    [null, { configured: false, authMode: null, codex: { installed: false, connected: false } }],
  ] as const)("reports the active %s account", async (scenario, expected) => {
    await expect(setup(scenario).service.status()).resolves.toEqual(expected);
  });

  it("switches from ChatGPT to API-key auth inside the same app-server", async () => {
    const { service } = setup("normal");
    await service.connectApiKey("sk-test");
    await expect(service.status()).resolves.toMatchObject({ configured: true, authMode: "apiKey" });
  });

  it("does not silently choose another auth mode when ChatGPT login fails", async () => {
    const { service } = setup("login-failed");
    const login = await service.startCodexLogin("browser");
    await expect(service.waitForCodexLogin(login.loginId)).resolves.toEqual({ state: "failed", error: "ChatGPT sign-in failed" });
    await expect(service.status()).resolves.toMatchObject({ configured: false, authMode: null });
  });
});
