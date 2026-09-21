import { describe, expect, it } from "vitest";
import { temporary } from "../test-support.js";
import { Store } from "./store.js";

function createStore(): Store {
  return new Store(temporary("agent-store-"));
}

describe("Store", () => {
  it("resumes a session by scope and persists its transcript", () => {
    const store = createStore();
    const first = store.resolveSession({ scopeKey: "assistant:local", cwd: "/tmp/example" });
    store.addMessage(first.id, "user", "hello");
    const resumed = store.resolveSession({ scopeKey: "assistant:local", cwd: "/tmp/example" });

    expect(resumed.id).toBe(first.id);
    expect(store.getMessages(first.id)).toMatchObject([{ role: "user", content: "hello" }]);
    store.close();
  });

  it("stores and retrieves relevant memories", () => {
    const store = createStore();
    store.remember("personal", "Mario prefers concise answers");
    store.remember("personal", "The garden is watered on Sunday");

    expect(store.searchMemories("personal", "answer concisely", 1)[0]).toContain("concise");
    expect(store.searchMemories("personal", "unrelated zebra phrase", 8)).toEqual([]);
    store.close();
  });

  it("recovers checkpointed output after an unclean runtime stop", () => {
    const path = temporary("agent-store-");
    const first = new Store(path);
    const session = first.resolveSession({ scopeKey: "assistant:local" });
    const run = first.startRun(session.id);
    first.checkpointRun(run, "partial answer");
    first.close();

    const recovered = new Store(path);
    expect(recovered.getMessages(session.id).at(-1)?.content).toContain("partial answer\n\n[interrupted]");
    recovered.close();
  });

  it("rotates a backend thread and its compaction count atomically", () => {
    const store = createStore();
    const session = store.resolveSession({ scopeKey: "assistant:local" });
    store.bindBackendSession(session.id, "codex", "thread-1");
    store.addBackendCompactions(session.id, "codex", 3);

    expect(store.rotateBackendSession(session.id, "codex", "stale-thread", "thread-2")).toBe(false);
    expect(store.backendSession(session.id, "codex")).toBe("thread-1");
    expect(store.backendCompactions(session.id, "codex")).toBe(3);

    expect(store.rotateBackendSession(session.id, "codex", "thread-1", "thread-2")).toBe(true);
    expect(store.backendSession(session.id, "codex")).toBe("thread-2");
    expect(store.backendCompactions(session.id, "codex")).toBe(0);
    store.close();
  });
});
