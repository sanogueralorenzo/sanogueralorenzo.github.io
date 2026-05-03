import assert from "node:assert/strict";
import { test } from "node:test";
import { mapCodexLine } from "../src/codex.js";

test("maps unknown Codex JSONL to raw codex events", () => {
  const event = mapCodexLine('{"type":"new_future_event","value":42}');

  assert.equal(event.type, "codex.event");
  assert.deepEqual(event.raw, { type: "new_future_event", value: 42 });
});

test("maps assistant and command output to app-facing events", () => {
  assert.equal(mapCodexLine('{"type":"assistant_message","text":"Hi"}').type, "assistant.output");
  assert.equal(mapCodexLine('{"type":"command_execution","output":"ok"}').type, "tool.output");
});
