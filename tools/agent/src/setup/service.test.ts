import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { afterEach, describe, expect, it } from "vitest";
import { CodexAppServer } from "../codex/app-server.js";
import type { OpenAIModelClient } from "../core/model.js";
import { Store } from "../core/store.js";
import type { BackendKind } from "../core/types.js";
import { BackendSetupService } from "./service.js";

const fakeServer = join(dirname(fileURLToPath(import.meta.url)), "..", "codex", "test-fixtures", "fake-app-server.mjs");
const fixtures: Array<{ homeDir: string; store: Store; codex: CodexAppServer }> = [];

afterEach(async () => {
  for (const fixture of fixtures.splice(0)) {
    await fixture.codex.stop();
    fixture.store.close();
    rmSync(fixture.homeDir, { recursive: true, force: true });
  }
});

function setup(scenario: string | null, apiKey = false, selected?: BackendKind) {
  const homeDir = mkdtempSync(join(tmpdir(), "agent-setup-"));
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
  fixtures.push({ homeDir, store, codex });
  return { store, service: new BackendSetupService(store, model, codex, () => undefined) };
}

describe("BackendSetupService", () => {
  it("reports ChatGPT connection and included usage", async () => {
    const { store, service } = setup("normal");
    const status = await service.status();
    expect(status.codex).toMatchObject({ installed: true, connected: true, planType: "plus", allowanceAvailable: true });
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

  it("requires the current Codex usage API", async () => {
    const { service } = setup("missing-rate-limits", false, "codex");
    await expect(service.status()).resolves.toMatchObject({
      configured: false,
      selectedBackend: "codex",
      codex: { connected: true, allowanceAvailable: null, error: expect.stringContaining("unsupported fake method") },
    });
  });

  it("switches to a saved API key only when explicitly selected", async () => {
    const { store, service } = setup("exhausted", true, "codex");
    const status = await service.status();
    expect(status).toMatchObject({ configured: false, selectedBackend: "codex", openAIConfigured: true });
    expect(status.codex.allowanceAvailable).toBe(false);
    await service.selectBackend("responses");
    expect(store.getSetting("backend")).toBe("responses");
  });
});
