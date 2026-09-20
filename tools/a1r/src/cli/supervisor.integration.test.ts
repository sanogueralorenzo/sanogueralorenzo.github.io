import { mkdtempSync, readFileSync, rmSync, statSync, utimesSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { afterEach, describe, expect, it } from "vitest";
import { RuntimeClient } from "../client/client.js";
import { Store } from "../core/store.js";
import type { BackendKind } from "../core/types.js";
import { RuntimeSupervisor } from "./supervisor.js";

const roots: string[] = [];

afterEach(() => {
  for (const root of roots.splice(0)) rmSync(root, { recursive: true, force: true });
});

async function verifyReload(backend: BackendKind, watchedFile: string): Promise<void> {
  const homeDir = mkdtempSync(join(tmpdir(), `a1r-hot-${backend}-`));
  roots.push(homeDir);
  const store = new Store(homeDir);
  const session = store.resolveSession({ scopeKey: `project:${homeDir}`, kind: "coding", cwd: homeDir, title: "Reload-safe session" });
  store.addMessage(session.id, "user", "Keep this transcript");
  store.remember(`project:${homeDir}`, "Keep this memory", session.id);
  store.setSetting("backend", backend);
  if (backend === "codex") store.bindBackendSession(session.id, "codex", "thread-persisted");
  store.close();

  const previousHome = process.env.A1R_HOME;
  const previousPort = process.env.A1R_PORT;
  process.env.A1R_HOME = homeDir;
  process.env.A1R_PORT = "0";
  const statuses: string[] = [];
  const supervisor = new RuntimeSupervisor(new RuntimeClient(homeDir), true, (message) => statuses.push(message));
  const original = statSync(watchedFile);
  try {
    await supervisor.start();
    if (backend === "codex") writeFileSync(join(homeDir, "codex", "profile.marker"), "private profile survives\n");
    const changed = new Date(Date.now() + 1_000);
    utimesSync(watchedFile, changed, changed);
    const deadline = Date.now() + 10_000;
    while (!statuses.includes("Runtime reloaded. Session restored.") && Date.now() < deadline) {
      await new Promise((resolve) => setTimeout(resolve, 50));
    }
    expect(statuses).toContain("Runtime reloaded. Session restored.");
  } finally {
    await supervisor.stop();
    utimesSync(watchedFile, original.atime, original.mtime);
    if (previousHome === undefined) delete process.env.A1R_HOME;
    else process.env.A1R_HOME = previousHome;
    if (previousPort === undefined) delete process.env.A1R_PORT;
    else process.env.A1R_PORT = previousPort;
  }

  const recovered = new Store(homeDir, "a1r.sqlite", { recoverRuns: false });
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
    await verifyReload("responses", join(sourceRoot, "core", "backend.ts"));
  }, 15_000);

  it("restores Codex mode and its opaque thread binding", async () => {
    await verifyReload("codex", join(sourceRoot, "codex", "backend.ts"));
  }, 15_000);
});
