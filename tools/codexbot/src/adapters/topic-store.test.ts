import { mkdtemp, readFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, describe, expect, it } from "vitest";
import { TopicStore } from "./topic-store.js";

const temporaryDirectories: string[] = [];

afterEach(async () => {
  await Promise.all(temporaryDirectories.splice(0).map((directory) => rm(directory, { recursive: true, force: true })));
});

describe("TopicStore", () => {
  it("keeps topic bindings isolated and persists concurrent writes", async () => {
    const directory = await mkdtemp(join(tmpdir(), "codexbot-topics-"));
    temporaryDirectories.push(directory);
    const store = new TopicStore(join(directory, "nested", "topics.json"));

    await Promise.all([
      store.set("-100", 11, { threadId: "thread-11", title: "Build", cwd: "/repo" }),
      store.set("-100", 12, { threadId: "thread-12", title: "Review", cwd: "/repo" }),
    ]);

    expect(await store.get("-100", 11)).toEqual({ threadId: "thread-11", title: "Build", cwd: "/repo" });
    expect(await store.get("-100", 12)).toEqual({ threadId: "thread-12", title: "Review", cwd: "/repo" });
    expect(JSON.parse(await readFile(join(directory, "nested", "topics.json"), "utf8"))).toEqual({
      "-100:11": { threadId: "thread-11", title: "Build", cwd: "/repo" },
      "-100:12": { threadId: "thread-12", title: "Review", cwd: "/repo" },
    });

    expect(await store.remove("-100", 11)).toBe(true);
    expect(await store.get("-100", 11)).toBeNull();
    expect(await store.remove("-100", 11)).toBe(false);
  });
});
