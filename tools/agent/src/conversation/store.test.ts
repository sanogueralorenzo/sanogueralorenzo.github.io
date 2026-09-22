import { describe, expect, it } from "vitest";
import { temporary } from "../test-support.js";
import { Store } from "./store.js";

function createStore(): Store {
  return new Store(temporary("agent-store-"));
}

describe("Store", () => {
  it("keeps sessions distinct and persists their transcripts", () => {
    const store = createStore();
    const first = store.createSession({ cwd: "/tmp/example" });
    store.addMessage(first.id, "user", "hello");
    const second = store.createSession({ cwd: "/tmp/example" });

    expect(second.id).not.toBe(first.id);
    expect(store.getSession(first.id)).toMatchObject({ id: first.id, cwd: first.cwd, title: first.title });
    expect(store.getMessages(first.id)).toMatchObject([{ role: "user", content: "hello" }]);
    store.close();
  });

  it("persists Telegram's selected session and follows navigation", () => {
    const directory = temporary("agent-telegram-binding-");
    const store = new Store(directory);
    const source = store.createSession();
    const target = store.createSession();
    store.bindTelegramSession("42", source.id);
    store.close();

    const reopened = new Store(directory);
    expect(reopened.telegramSession("42")).toBe(source.id);
    reopened.redirectSession(source.id, target.id);
    expect(reopened.telegramSession("42")).toBe(target.id);
    expect(reopened.getSession(source.id)).toBeNull();
    reopened.close();
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
    const session = first.createSession();
    const run = first.startRun(session.id);
    first.checkpointRun(run, "partial answer");
    first.close();

    const recovered = new Store(path);
    expect(recovered.getMessages(session.id).at(-1)?.content).toContain("partial answer\n\n[interrupted]");
    expect(recovered.latestRun()).toMatchObject({ id: run, sessionId: session.id, state: "interrupted" });
    recovered.close();

    const reopened = new Store(path);
    expect(reopened.getMessages(session.id)).toHaveLength(1);
    reopened.close();
  });

  it("retains only the latest run state for reconnect reconciliation", () => {
    const store = createStore();
    const session = store.createSession();
    store.startRun(session.id, "first");
    store.finishRun("first", "complete");
    expect(store.latestRun()).toMatchObject({ id: "first", state: "complete", output: "" });
    store.startRun(session.id, "second");
    expect(store.latestRun()).toMatchObject({ id: "second", state: "running" });
    store.finishRun("second", "interrupted");
    expect(store.latestRun()).toMatchObject({ id: "second", state: "interrupted", output: "" });
    expect(store.db.prepare("SELECT COUNT(*) AS count FROM runs").get()).toMatchObject({ count: 1 });
    store.close();
  });

  it("commits the final answer and terminal state together", () => {
    const path = temporary("agent-store-");
    const store = new Store(path);
    const session = store.createSession();
    store.startRun(session.id, "r1");
    store.checkpointRun("r1", "draft");
    store.finishRun("r1", "complete", "final answer");
    store.close();

    const reopened = new Store(path);
    expect(reopened.getMessages(session.id)).toEqual([{ role: "assistant", content: "final answer" }]);
    expect(reopened.latestRun()).toMatchObject({ id: "r1", state: "complete", output: "" });
    reopened.close();
  });

  it("rotates a Codex thread and its compaction count atomically", () => {
    const store = createStore();
    const session = store.createSession();
    store.bindCodexThread(session.id, "thread-1");
    store.addCodexCompactions(session.id, 3);

    expect(store.rotateCodexThread(session.id, "stale-thread", "thread-2", "stale handoff")).toBe(false);
    expect(store.codexThread(session.id)).toBe("thread-1");
    expect(store.codexCompactions(session.id)).toBe(3);

    expect(store.rotateCodexThread(session.id, "thread-1", "thread-2", "Current objective and next action")).toBe(true);
    expect(store.codexThread(session.id)).toBe("thread-2");
    expect(store.codexCompactions(session.id)).toBe(0);
    expect(store.sessionCards()[0]?.preview).toContain("Current objective and next action");
    expect(store.readConversation(session.id).handoff).toBe("Current objective and next action");
    store.close();
  });

  it("lists short previews and reads one conversation in pages without tool messages", () => {
    const store = createStore();
    const session = store.createSession({ title: "Telegram work" });
    for (let number = 1; number <= 11; number += 1) {
      store.addMessage(session.id, "user", `Message ${number}: ${"detail ".repeat(40)}`);
      store.addMessage(session.id, "tool", "command: complete");
    }

    const card = store.sessionCards()[0]!;
    expect(card).toMatchObject({ id: session.id, title: "Telegram work" });
    expect(card.preview.length).toBe(200);
    expect(JSON.stringify(card)).not.toContain("Message 10");

    const first = store.readConversation(session.id);
    expect(first.messages).toHaveLength(8);
    expect(first.messages[0]?.content).toContain("Message 4:");
    expect(first.nextBefore).not.toBeNull();
    const older = store.readConversation(session.id, first.nextBefore!);
    expect(older.messages.map((message) => message.content.slice(0, 9)))
      .toEqual(["Message 1", "Message 2", "Message 3"]);
    expect(older.nextBefore).toBeNull();
    store.close();
  });
});
