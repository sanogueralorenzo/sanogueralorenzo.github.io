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
    ? new CodexAppServer({ command: "missing-codex" })
    : new CodexAppServer({
      command: process.execPath,
      args: [fakeServer],
      env: { ...process.env, AGENT_FAKE_SCENARIO: scenario },
    });
  const model = { isConfigured: () => apiKey, setApiKey: async () => undefined } as unknown as OpenAIModelClient;
  cleanup(async () => { await codex.stop(); store.close(); });
  return { store, service: new BackendSetupService(store, model, codex, () => undefined) };
}

describe("BackendSetupService", () => {
  it.each([
    ["connected ChatGPT", "normal", false, undefined, { codex: { installed: true, connected: true } }, "codex", null, "codex"],
    ["selected API key without Codex", null, true, "responses", { configured: true, selectedBackend: "responses", openAIConfigured: true, codex: { installed: false } }, "responses", null, "responses"],
    ["unselected saved API key", null, true, undefined, { configured: false, selectedBackend: null, openAIConfigured: true }, undefined, null, null],
    ["expired selected ChatGPT", "expired", false, "codex", { configured: false, selectedBackend: "codex", codex: { connected: false } }, "codex", "Continue with ChatGPT", "codex"],
    ["explicit switch to API key", "exhausted", true, "codex", { configured: true, selectedBackend: "codex", openAIConfigured: true }, "responses", null, "responses"],
  ] as const)("handles %s", async (_name, scenario, apiKey, selected, status, choice, error, stored) => {
    const { store, service } = setup(scenario, apiKey, selected);
    await expect(service.status()).resolves.toMatchObject(status);
    if (choice && error) await expect(service.selectBackend(choice)).rejects.toThrow(error);
    else if (choice) await service.selectBackend(choice);
    expect(store.getSetting("backend")).toBe(stored);
  });
});
