import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import { CodexAppServer } from "../codex/app-server.js";
import type { OpenAIModelClient } from "../openai/model.js";
import { Store } from "../conversation/store.js";
import type { BackendKind } from "../conversation/types.js";
import { cleanup, temporary } from "../test-support.js";
import { BackendSetupService } from "./service.js";

const fakeServer = join(dirname(fileURLToPath(import.meta.url)), "..", "codex", "test-fixtures", "fake-app-server.mjs");

function setup(scenario: string | null, apiKey = false, selected?: BackendKind) {
  const homeDir = temporary("agent-setup-");
  const store = new Store(homeDir);
  if (selected) store.setSetting("backend", selected);
  const codex = scenario === null
    ? new CodexAppServer({ command: "missing-codex", installed: false })
    : new CodexAppServer({
      command: process.execPath,
      args: [fakeServer],
      installed: true,
      env: { ...process.env, AGENT_FAKE_SCENARIO: scenario },
    });
  const model = { isConfigured: () => apiKey, setApiKey: async () => undefined } as unknown as OpenAIModelClient;
  cleanup(async () => { await codex.stop(); store.close(); });
  return { store, service: new BackendSetupService(store, model, codex, () => undefined) };
}

describe("BackendSetupService", () => {
  it("reports a ChatGPT connection", async () => {
    const { store, service } = setup("normal");
    const status = await service.status();
    expect(status.codex).toMatchObject({ installed: true, connected: true, planType: "plus" });
    await service.selectBackend("codex");
    expect(store.getSetting("backend")).toBe("codex");
  });

  it("preserves explicitly selected API-key mode when Codex is unavailable", async () => {
    const { store, service } = setup(null, true, "responses");
    await expect(service.status()).resolves.toMatchObject({
      configured: true, selectedBackend: "responses", openAIConfigured: true, codex: { installed: false },
    });
    await service.selectBackend("responses");
    expect(store.getSetting("backend")).toBe("responses");
  });

  it("does not select a saved API key unless the user explicitly chooses it", async () => {
    const { store, service } = setup(null, true);
    await expect(service.status()).resolves.toMatchObject({ configured: false, selectedBackend: null, openAIConfigured: true });
    expect(store.getSetting("backend")).toBeNull();
  });

  it("reports a selected Codex backend as disconnected when its login has expired", async () => {
    const { store, service } = setup("expired", false, "codex");
    await expect(service.status()).resolves.toMatchObject({ configured: false, selectedBackend: "codex", codex: { connected: false } });
    await expect(service.selectBackend("codex")).rejects.toThrow(/Continue with ChatGPT/);
    expect(store.getSetting("backend")).toBe("codex");
  });

  it("switches to a saved API key only when explicitly selected", async () => {
    const { store, service } = setup("exhausted", true, "codex");
    const status = await service.status();
    expect(status).toMatchObject({ configured: true, selectedBackend: "codex", openAIConfigured: true });
    await service.selectBackend("responses");
    expect(store.getSetting("backend")).toBe("responses");
  });
});
