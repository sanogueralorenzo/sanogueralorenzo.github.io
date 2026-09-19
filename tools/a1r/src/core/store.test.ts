import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, describe, expect, it } from "vitest";
import { Store } from "./store.js";

const paths: string[] = [];

afterEach(() => {
  for (const path of paths.splice(0)) rmSync(path, { recursive: true, force: true });
});

function createStore(): Store {
  const path = mkdtempSync(join(tmpdir(), "a1r-store-"));
  paths.push(path);
  return new Store(path);
}

describe("Store", () => {
  it("resumes a session by scope and persists its transcript", () => {
    const store = createStore();
    const first = store.resolveSession({ scopeKey: "project:/tmp/example", kind: "coding", cwd: "/tmp/example" });
    store.addMessage(first.id, "user", "hello");
    const resumed = store.resolveSession({ scopeKey: "project:/tmp/example", kind: "coding", cwd: "/tmp/example" });

    expect(resumed.id).toBe(first.id);
    expect(store.getMessages(first.id)).toMatchObject([{ role: "user", content: "hello" }]);
    store.close();
  });

  it("stores and retrieves relevant memories", () => {
    const store = createStore();
    store.remember("personal", "Mario prefers concise answers");
    store.remember("personal", "The garden is watered on Sunday");

    expect(store.searchMemories("personal", "answer concisely", 1)[0]?.content).toContain("concise");
    expect(store.searchMemories("personal", "unrelated zebra phrase", 8)).toEqual([]);
    store.close();
  });

  it("links gateway identities to a shared session", () => {
    const store = createStore();
    const session = store.resolveSession({ scopeKey: "telegram:42", kind: "personal" });
    store.linkGateway("telegram", "42", session.id);

    expect(store.gatewaySession("telegram", "42")?.id).toBe(session.id);
    store.close();
  });

  it("recovers checkpointed output after an unclean runtime stop", () => {
    const path = mkdtempSync(join(tmpdir(), "a1r-store-"));
    paths.push(path);
    const first = new Store(path);
    const session = first.resolveSession({ scopeKey: "personal:local", kind: "personal" });
    const run = first.startRun(session.id);
    first.checkpointRun(run, "partial answer");
    first.close();

    const recovered = new Store(path);
    expect(recovered.getMessages(session.id).at(-1)?.content).toContain("partial answer\n\n[interrupted]");
    recovered.close();
  });
});
