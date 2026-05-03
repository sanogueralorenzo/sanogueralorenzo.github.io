import assert from "node:assert/strict";
import { chmod, mkdtemp, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { createApp } from "../src/server.js";

test("server creates a session, runs a message, and replays SSE events", async () => {
  const root = await mkdtemp(join(tmpdir(), "codex-web-server-"));
  const codexBin = join(root, "fake-codex.sh");
  await writeFile(
    codexBin,
    [
      "#!/usr/bin/env bash",
      "set -euo pipefail",
      "if [[ \"${1:-}\" == \"--version\" ]]; then echo 'codex-cli test'; exit 0; fi",
      "last=''",
      "while [[ $# -gt 0 ]]; do",
      "  if [[ \"$1\" == \"--output-last-message\" ]]; then shift; last=\"$1\"; fi",
      "  shift || true",
      "done",
      "cat >/dev/null",
      "echo '{\"type\":\"assistant_message\",\"text\":\"hello\",\"session_id\":\"thread-1\"}'",
      "echo '{\"type\":\"future_event\",\"value\":7}'",
      "printf 'done' > \"$last\"",
    ].join("\n"),
  );
  await chmod(codexBin, 0o755);

  const app = await createApp({
    host: "127.0.0.1",
    port: 0,
    dataDir: join(root, "data"),
    codexBin,
    publicDir: join(process.cwd(), "public"),
  });
  await new Promise<void>((resolve) => app.listen(0, "127.0.0.1", resolve));
  const address = app.address();
  assert(address && typeof address === "object");
  const base = `http://127.0.0.1:${address.port}`;

  try {
    const info = await fetch(`${base}/api/info`).then((response) => response.json() as Promise<{ version: string }>);
    assert.equal(info.version, "codex-cli test");

    const session = await fetch(`${base}/api/sessions`, {
      method: "POST",
      body: JSON.stringify({ title: "Test" }),
    }).then((response) => response.json() as Promise<{ id: string }>);

    const stream = await fetch(`${base}/api/sessions/${session.id}/events`);
    assert.equal(stream.status, 200);

    const posted = await fetch(`${base}/api/sessions/${session.id}/messages`, {
      method: "POST",
      body: JSON.stringify({ text: "hi" }),
    });
    assert.equal(posted.status, 202);

    const events = await readSse(stream, 8);
    assert(events.some((event) => event.includes("assistant.output")), events.join("\n---\n"));
    assert(events.some((event) => event.includes("codex.event")), events.join("\n---\n"));
    assert(events.some((event) => event.includes("final.answer")), events.join("\n---\n"));
  } finally {
    await new Promise<void>((resolve) => app.close(() => resolve()));
  }
});

async function readSse(response: Response, eventCount: number): Promise<string[]> {
  assert(response.body);
  const reader = response.body.pipeThrough(new TextDecoderStream()).getReader();
  let buffer = "";
  const events: string[] = [];
  while (events.length < eventCount) {
    const read = await reader.read();
    if (read.done) break;
    buffer += read.value;
    const parts = buffer.split("\n\n");
    buffer = parts.pop() ?? "";
    events.push(...parts.filter(Boolean));
  }
  reader.cancel().catch(() => undefined);
  return events;
}
