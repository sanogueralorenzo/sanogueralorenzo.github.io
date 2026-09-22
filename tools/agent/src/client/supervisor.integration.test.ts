import { readFileSync, statSync, utimesSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { afterEach, describe, expect, it, vi } from "vitest";
import { RuntimeClient } from "./client.js";
import { Store } from "../conversation/store.js";
import { temporary } from "../test-support.js";
import { RuntimeSupervisor } from "./supervisor.js";

afterEach(() => vi.unstubAllEnvs());

async function verifyReload(watchedFile: string): Promise<void> {
  const homeDir = temporary("agent-hot-reload-");
  const store = new Store(homeDir);
  const session = store.createSession({ cwd: homeDir, title: "Reload-safe session" });
  store.addMessage(session.id, "user", "Keep this transcript");
  store.remember(`project:${homeDir}`, "Keep this memory");
  store.bindCodexThread(session.id, "thread-persisted");
  store.close();

  vi.stubEnv("AGENT_HOME", homeDir);
  vi.stubEnv("AGENT_PORT", "0");
  const client = new RuntimeClient(homeDir);
  const supervisor = new RuntimeSupervisor(client, true, () => undefined);
  const original = statSync(watchedFile);
  try {
    await supervisor.start();
    const originalPid = JSON.parse(readFileSync(join(homeDir, "runtime.json"), "utf8")).pid as number;
    writeFileSync(join(homeDir, "codex", "profile.marker"), "private profile survives\n");
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

  const recovered = new Store(homeDir);
  expect(recovered.getSession(session.id)?.title).toBe("Reload-safe session");
  expect(recovered.getSession(session.id)?.cwd).toBe(homeDir);
  expect(recovered.getMessages(session.id)[0]?.content).toBe("Keep this transcript");
  expect(recovered.searchMemories(`project:${homeDir}`, "this memory")[0]).toBe("Keep this memory");
  expect(recovered.codexThread(session.id)).toBe("thread-persisted");
  expect(readFileSync(join(homeDir, "codex", "profile.marker"), "utf8")).toBe("private profile survives\n");
  recovered.close();
}

const sourceRoot = join(dirname(fileURLToPath(import.meta.url)), "..");

describe.sequential("hot reload", () => {
  it("restores Agent state, its private profile, and opaque thread binding", async () => {
    await verifyReload(join(sourceRoot, "codex", "backend.ts"));
  }, 15_000);
});
