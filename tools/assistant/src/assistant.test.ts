import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { SessionManager } from "@earendil-works/pi-coding-agent";
import { Assistant } from "./assistant.ts";
import { PiService } from "./pi.ts";
import { State, now } from "./state.ts";

test("Go ahead replies queue in the referenced conversation, including transcript replies", () => {
  const dir = mkdtempSync(join(tmpdir(), "assistant-reply-"));
  const state = new State(dir, () => {});
  try {
    for (const id of ["session-1", "session-2"]) {
      state.data.sessions.push({ id, title: id, cwd: dir, file: id, status: "running", createdAt: now() });
    }
    const request = state.message("Review this");
    const entry = state.entry(request, "Review", "session-1");
    state.update(entry, "I recommend improving the messages.", "result", "ready", request.id, "home-reply");
    const app = Object.create(Assistant.prototype) as Assistant;
    Object.assign(app, {
      state, active: new Map(), drain: () => {},
      pi: { transcript: (file: string) => file === "session-1"
        ? [{ id: "transcript-reply", role: "assistant", replyable: true, text: "I can make that change." }] : [] },
    });

    for (const replyToId of ["home-reply", "transcript-reply"]) {
      app.submitSession("session-1", "Go ahead.", "followUp", { replyToId });
      const turn = state.data.turns.at(-1)!;
      assert.equal(turn.sessionId, "session-1");
      assert.equal(turn.replyToId, replyToId);
      assert.equal(turn.text, "Go ahead.");
      assert.equal(turn.status, "queued");
      assert.equal(state.data.messages.at(-1)?.replyToId, replyToId);
      assert.throws(() => app.submitSession("session-2", "Go ahead.", "followUp", { replyToId }), /not in this conversation/);
    }
    assert.equal(state.data.turns.length, 2);
    assert.throws(() => app.submitSession("session-1", "Go ahead.", "followUp", { replyToId: "missing" }), /not in this conversation/);
  } finally {
    state.db.close();
    rmSync(dir, { recursive: true, force: true });
  }
});

test("transcripts preserve reply IDs and distinguish completed replies from tool commentary", () => {
  const dir = mkdtempSync(join(tmpdir(), "assistant-transcript-"));
  try {
    const manager = SessionManager.create(dir, dir);
    manager.appendMessage({ role: "user", content: "Review this", timestamp: Date.now() });
    const message = {
      role: "assistant" as const, content: [{ type: "text" as const, text: "I can improve this." }],
      api: "openai-responses" as const, provider: "openai", model: "test", timestamp: Date.now(),
      usage: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, totalTokens: 0,
        cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0 } },
    };
    const commentaryId = manager.appendMessage({ ...message, stopReason: "toolUse" });
    const replyId = manager.appendMessage({ ...message, stopReason: "stop" });
    const transcript = PiService.prototype.transcript(manager.getSessionFile()!);
    assert.equal(transcript.find((item) => item.id === commentaryId)?.replyable, false);
    assert.equal(transcript.find((item) => item.id === replyId)?.replyable, true);
    assert.equal(transcript.find((item) => item.role === "user")?.replyable, false);
    assert.equal(manager.getBranch().at(-1)?.id, replyId);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});
