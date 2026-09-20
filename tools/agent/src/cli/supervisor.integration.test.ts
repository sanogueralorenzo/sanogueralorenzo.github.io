import { readFileSync, statSync, utimesSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { afterEach, describe, expect, it, vi } from "vitest";
import { RuntimeClient } from "../client/client.js";
import { Store } from "../conversation/store.js";
import type { BackendKind } from "../conversation/types.js";
import { temporary } from "../test-support.js";
import { RuntimeSupervisor } from "./supervisor.js";

afterEach(() => vi.unstubAllEnvs());

async function verifyReload(backend: BackendKind, watchedFile: string): Promise<void> {
  const homeDir = temporary(`agent-hot-${backend}-`);
  const store = new Store(homeDir);
  const session = store.resolveSession({ scopeKey: `project:${homeDir}`, kind: "coding", cwd: homeDir, title: "Reload-safe session" });
  store.addMessage(session.id, "user", "Keep this transcript");
  store.remember(`project:${homeDir}`, "Keep this memory");
  store.setSetting("backend", backend);
  if (backend === "codex") store.bindBackendSession(session.id, "codex", "thread-persisted");
  store.close();

  vi.stubEnv("AGENT_HOME", homeDir);
  vi.stubEnv("AGENT_PORT", "0");
  const client = new RuntimeClient(homeDir);
  const supervisor = new RuntimeSupervisor(client, true, () => undefined);
  const original = statSync(watchedFile);
  try {
    await supervisor.start();
    const originalPid = JSON.parse(readFileSync(join(homeDir, "runtime.json"), "utf8")).pid as number;
    if (backend === "codex") writeFileSync(join(homeDir, "codex", "profile.marker"), "private profile survives\n");
    const changed = new Date(Date.now() + 1_000);
    utimesSync(watchedFile, changed, changed);
    await vi.waitFor(async () => {
      const pid = JSON.parse(readFileSync(join(homeDir, "runtime.json"), "utf8")).pid as number;
      expect(pid).not.toBe(originalPid);
      expect(await client.healthy()).toBe(true);
    }, { timeout: 10_000, interval: 50 });
  } finally {
    await supervisor.stop();
    utimesSync(watchedFile, original.atime, original.mtime);
  }

  const recovered = new Store(homeDir, "agent.sqlite", { recoverRuns: false });
  expect(recovered.getSetting("backend")).toBe(backend);
  expect(recovered.getSession(session.id)?.title).toBe("Reload-safe session");
  expect(recovered.getSession(session.id)?.cwd).toBe(homeDir);
  expect(recovered.getMessages(session.id)[0]?.content).toBe("Keep this transcript");
  expect(recovered.searchMemories(`project:${homeDir}`, "this memory")[0]?.content).toBe("Keep this memory");
  if (backend === "codex") expect(recovered.backendSession(session.id, "codex")).toBe("thread-persisted");
  if (backend === "codex") expect(readFileSync(join(homeDir, "codex", "profile.marker"), "utf8")).toBe("private profile survives\n");
  recovered.close();
}

const sourceRoot = join(dirname(fileURLToPath(import.meta.url)), "..");

describe.sequential("hot reload", () => {
  it("restores Responses mode state", async () => {
    await verifyReload("responses", join(sourceRoot, "conversation", "backend.ts"));
  }, 15_000);

  it("restores Codex mode and its opaque thread binding", async () => {
    await verifyReload("codex", join(sourceRoot, "codex", "backend.ts"));
  }, 15_000);
});
