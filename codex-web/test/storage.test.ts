import assert from "node:assert/strict";
import { mkdtemp } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { FileStore } from "../src/storage.js";

test("FileStore creates sessions and replays events after an id", async () => {
  const store = new FileStore(await mkdtemp(join(tmpdir(), "codex-web-store-")));
  await store.load();

  const { session } = await store.createSession({ title: "Work", cwd: "/tmp/project" });
  await store.appendEvent(session.id, "message.user", { text: "hello" });
  await store.appendEvent(session.id, "codex.event", { label: "future" }, { type: "future.event" });

  const replay = await store.eventsAfter(session.id, 1);
  assert.equal(replay.length, 2);
  assert.equal(replay[0]?.type, "message.user");
  assert.deepEqual(replay[1]?.raw, { type: "future.event" });
});
