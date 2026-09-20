import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { afterEach, describe, expect, it } from "vitest";
import { CodexAppServer } from "../codex/app-server.js";
import type { OpenAIModelClient } from "../core/model.js";
import { Store } from "../core/store.js";
import { BackendSetupService } from "./service.js";

const fixture = join(dirname(fileURLToPath(import.meta.url)), "..", "codex", "test-fixtures", "fake-app-server.mjs");
const paths: string[] = [];

afterEach(() => {
  for (const path of paths.splice(0)) rmSync(path, { recursive: true, force: true });
});

function model(configured: boolean): OpenAIModelClient {
  return {
    isConfigured: () => configured,
    setApiKey: async () => undefined,
  } as unknown as OpenAIModelClient;
}

describe("BackendSetupService", () => {
  it("reports the ChatGPT plan and available included usage", async () => {
    const homeDir = mkdtempSync(join(tmpdir(), "a1r-setup-"));
    paths.push(homeDir);
    const store = new Store(homeDir);
    const codex = new CodexAppServer({
      command: process.execPath,
      args: [fixture],
      installed: true,
      env: { ...process.env, A1R_FAKE_SCENARIO: "normal" },
    });
    const service = new BackendSetupService(store, model(false), codex, () => undefined);
    const status = await service.status();

    expect(status.codex).toMatchObject({ installed: true, connected: true, planType: "plus", allowanceAvailable: true });
    expect(status.codex.usage[0]).toMatchObject({ name: "Codex", remainingPercent: 78 });
    await service.selectBackend("codex");
    expect(store.getSetting("backend")).toBe("codex");
    await codex.stop();
    store.close();
  });

  it("preserves API-key mode when Codex is unavailable", async () => {
    const homeDir = mkdtempSync(join(tmpdir(), "a1r-setup-fallback-"));
    paths.push(homeDir);
    const store = new Store(homeDir);
    const codex = new CodexAppServer({ command: "missing-codex", installed: false });
    const service = new BackendSetupService(store, model(true), codex, () => undefined);
    const status = await service.status();

    expect(status).toMatchObject({ configured: true, selectedBackend: "responses", openAIConfigured: true });
    expect(status.codex.installed).toBe(false);
    await service.selectBackend("responses");
    expect(store.getSetting("backend")).toBe("responses");
    store.close();
  });

  it("offers the saved API-key fallback when included allowance is exhausted", async () => {
    const homeDir = mkdtempSync(join(tmpdir(), "a1r-setup-exhausted-"));
    paths.push(homeDir);
    const store = new Store(homeDir);
    store.setSetting("backend", "codex");
    const codex = new CodexAppServer({
      command: process.execPath,
      args: [fixture],
      installed: true,
      env: { ...process.env, A1R_FAKE_SCENARIO: "exhausted" },
    });
    const service = new BackendSetupService(store, model(true), codex, () => undefined);
    const status = await service.status();

    expect(status).toMatchObject({ configured: false, selectedBackend: "codex", openAIConfigured: true });
    expect(status.codex.allowanceAvailable).toBe(false);
    await service.selectBackend("responses");
    expect(store.getSetting("backend")).toBe("responses");
    await codex.stop();
    store.close();
  });
});
