import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { SessionManager, type AgentSessionEvent } from "@earendil-works/pi-coding-agent";
import { Assistant } from "./assistant.ts";
import { PiService } from "./pi.ts";
import { State, now } from "./state.ts";

test("thumbs-up reactions queue one approval in the referenced conversation", () => {
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
      const options = { replyToId, reaction: "thumbs-up" as const };
      app.submitSession("session-1", "ignored", "followUp", options);
      const turn = state.data.turns.at(-1)!;
      assert.equal(turn.sessionId, "session-1");
      assert.equal(turn.replyToId, replyToId);
      assert.equal(turn.text, "Yes, go ahead.");
      assert.equal(turn.status, "queued");
      assert.equal(state.data.messages.at(-1)?.replyToId, replyToId);
      assert.equal(state.data.messages.at(-1)?.reaction, "thumbs-up");
      app.submitSession("session-1", "ignored", "followUp", options);
      assert.throws(() => app.submitSession("session-2", "ignored", "followUp", options), /not in this conversation/);
    }
    assert.equal(state.data.turns.length, 2);
    assert.throws(() => app.submitSession("session-1", "Go ahead.", "followUp", { replyToId: "missing" }), /not in this conversation/);
    assert.throws(() => app.submitSession("session-1", "ignored", "steer", { replyToId: "home-reply", reaction: "thumbs-up" }), /React to an assistant reply/);
    assert.throws(() => app.submitSession("session-1", "ignored", "followUp", { replyToId: request.id, reaction: "thumbs-up" }), /React to an assistant reply/);
    app.submitSession("session-1", "Yes, go ahead.", "followUp", { replyToId: "home-reply" });
    assert.equal(state.data.messages.at(-1)?.reaction, undefined);
    const reopened = new State(dir, () => {});
    try {
      assert.equal(reopened.data.messages.filter((message) => message.reaction === "thumbs-up").length, 2);
    } finally { reopened.db.close(); }
  } finally {
    state.db.close();
    rmSync(dir, { recursive: true, force: true });
  }
});

test("session replies retain the selected context when queued or steering active work", () => {
  const dir = mkdtempSync(join(tmpdir(), "assistant-context-"));
  const state = new State(dir, () => {});
  try {
    state.data.sessions.push({ id: "session", title: "Context", cwd: dir, file: "session", status: "running", createdAt: now() });
    const prompts: string[] = [];
    const active = new Map();
    const app = Object.create(Assistant.prototype) as Assistant;
    Object.assign(app, {
      state, active, drain: () => {},
      pi: { transcript: () => [
        { id: "earlier", role: "assistant", replyable: true, text: "First proposal.\nIts details." },
        { id: "latest", role: "assistant", replyable: true, text: "Another proposal." },
      ] },
    });
    app.submitSession("session", "Change this one", "followUp", { replyToId: "earlier" });
    const turn = state.data.turns.at(-1)!;
    assert.equal(turn.replyToId, "earlier");
    assert.equal(turn.text, "Change this one");
    assert.equal(state.data.messages.at(-1)?.replyToId, "earlier");

    active.set("session", { turn, session: { steer: (prompt: string) => { prompts.push(prompt); return Promise.resolve(); } } });
    app.submitSession("session", "Focus on this proposal", "steer", { replyToId: "earlier" });
    assert.equal(prompts[0], "In reply to this earlier assistant message:\n> First proposal.\n> Its details.\n\nFocus on this proposal");
    app.submitSession("session", "Now this one", "steer", { replyToId: "latest" });
    assert.equal(prompts[1], "In reply to this earlier assistant message:\n> Another proposal.\n\nNow this one");
    app.submitSession("session", "Ordinary steering", "steer");
    assert.equal(prompts[2], "Ordinary steering");
  } finally {
    state.db.close();
    rmSync(dir, { recursive: true, force: true });
  }
});

test("queued replies and approvals deliver the selected earlier context to the session", async () => {
  const dir = mkdtempSync(join(tmpdir(), "assistant-queued-context-"));
  const state = new State(dir, () => {});
  try {
    state.data.sessions.push({ id: "session", title: "Context", cwd: dir, file: "session", status: "idle", createdAt: now() });
    const prompts: string[] = [];
    const reactions: unknown[] = [];
    const suggested: string[] = [];
    let listener: (event: AgentSessionEvent) => void;
    let completed: () => void;
    const session = {
      subscribe: (callback: typeof listener) => { listener = callback; },
      sessionManager: {
        appendCustomEntry: (_type: string, data: unknown) => reactions.push(data),
        getBranch: () => [{ type: "message", id: "result", message: { role: "assistant" } }],
      },
      prompt: async (text: string) => {
        prompts.push(text);
        listener({ type: "message_end", message: { role: "user", content: text, timestamp: Date.now() } });
        listener({ type: "message_end", message: {
          role: "assistant", content: [{ type: "text", text: "Done." }], stopReason: "stop",
        } } as AgentSessionEvent);
      },
    };
    const app = Object.create(Assistant.prototype) as Assistant;
    Object.assign(app, {
      state, concurrency: 1, active: new Map(), starting: new Set(), pendingStops: new Set(), listeners: new Set(),
      pi: {
        suggestions: { get: async (_sessionId: string, replyId: string) => { suggested.push(replyId); return null; } },
        transcript: () => [
          { id: "earlier", role: "assistant", replyable: true, text: "First proposal.\nIts details." },
          { id: "latest", role: "assistant", replyable: true, text: "Another proposal." },
        ],
        open: async () => session,
        onSearchActivity: () => {},
        dispose: () => completed(),
      },
    });
    const cases: { text: string; reaction?: "thumbs-up" }[] = [
      { text: "Change this proposal" }, { text: "ignored", reaction: "thumbs-up" },
    ];
    for (const { text, reaction } of cases) {
      const finished = new Promise<void>((resolve) => { completed = resolve; });
      app.submitSession("session", text, "followUp", { replyToId: "earlier", reaction });
      await finished;
      assert.equal(prompts.at(-1), `In reply to this earlier assistant message:\n> First proposal.\n> Its details.\n\n${reaction ? "Yes, go ahead." : text}`);
      assert.equal(state.data.sessions[0].status, "idle");
      assert.equal(state.data.turns.length, 0);
    }
    assert.deepEqual(reactions, [{ reaction: "thumbs-up", replyToId: "earlier" }]);
    assert.deepEqual(suggested, ["result", "result"]);
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
    manager.appendCustomEntry("assistant-reaction", { reaction: "thumbs-up", replyToId: replyId });
    const reactionId = manager.appendMessage({ role: "user", content: "Yes, go ahead.", timestamp: Date.now() });
    const manualId = manager.appendMessage({ role: "user", content: "Yes, go ahead.", timestamp: Date.now() });
    const transcript = PiService.prototype.transcript(manager.getSessionFile()!);
    assert.equal(transcript.find((item) => item.id === commentaryId)?.replyable, false);
    assert.equal(transcript.find((item) => item.id === replyId)?.replyable, true);
    assert.equal(transcript.find((item) => item.role === "user")?.replyable, false);
    assert.equal(transcript.find((item) => item.id === reactionId)?.reaction, "thumbs-up");
    assert.equal(transcript.find((item) => item.id === reactionId)?.text, "Yes, go ahead.");
    assert.equal(transcript.find((item) => item.id === manualId)?.reaction, undefined);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});
