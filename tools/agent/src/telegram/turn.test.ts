import { describe, expect, it, vi } from "vitest";
import type { RunEnvelope, RuntimeEvent, RuntimeSnapshot } from "../conversation/types.js";
import { MAX_ATTACHMENT_BYTES } from "../workspace/assets.js";
import { checkTelegramVoiceSize, isTelegramOwner, telegramFailure, TelegramTurns } from "./turn.js";

const session = { id: "s1", cwd: null, title: "Hello", updatedAt: new Date().toISOString() };

function client(run: object | null = { id: "r1", sessionId: "s1", origin: "telegram" }) {
  let selected = "s1";
  return {
    submit: vi.fn(async () => run),
    stop: vi.fn(async () => true),
    telegramSession: vi.fn(async (_ownerId: string, options: { fresh?: boolean; sessionId?: string } = {}) => {
      if (options.fresh) selected = "s2";
      if (options.sessionId) selected = options.sessionId;
      return { ...session, id: selected };
    }),
    transcript: vi.fn(async () => ({ session, messages: [{ role: "user", content: "hello" }, { role: "assistant", content: "Saved answer" }] })),
  };
}

const envelope = (event: RuntimeEvent, runId = "r1", sessionId = "s1"): RunEnvelope => ({ sessionId, runId, event });
const turnsFor = (runtime = client()) => new TelegramTurns(runtime, () => "42");

describe("Telegram turns", () => {
  it("allows only the private owner", () => {
    expect(isTelegramOwner("42", "private", 42)).toBe(true);
    expect(isTelegramOwner("42", "group", 42)).toBe(false);
    expect(isTelegramOwner("42", "private", 7)).toBe(false);
  });

  it("uses centralized submit, busy, and stop semantics", async () => {
    const runtime = client();
    const turns = turnsFor(runtime);
    await expect(turns.submit(async () => ({ text: "hello" }))).resolves.toEqual({ accepted: true, recovered: [] });
    expect(runtime.submit).toHaveBeenCalledWith({ text: "hello", sessionId: "s1", channel: "telegram" });
    await expect(turns.stop()).resolves.toBe(true);
    expect(runtime.stop).toHaveBeenCalledWith("r1");
    await expect(turnsFor(client(null)).submit(async () => ({ text: "busy" }))).resolves.toEqual({ accepted: false, recovered: [] });
  });

  it("starts the next accepted message as a new conversation", async () => {
    const runtime = client(null);
    const turns = turnsFor(runtime);
    await turns.newConversation();

    await expect(turns.submit(async () => ({ text: "busy" }))).resolves.toEqual({ accepted: false, recovered: [] });
    runtime.submit.mockResolvedValue({ id: "r2", sessionId: "s2", origin: "telegram" });
    await expect(turns.submit(async () => ({ text: "new topic" }))).resolves.toEqual({ accepted: true, recovered: [] });
    await expect(turns.submit(async () => ({ text: "continue" }))).resolves.toEqual({ accepted: true, recovered: [] });

    expect(runtime.telegramSession).toHaveBeenNthCalledWith(1, "42", { fresh: true });
    expect(runtime.telegramSession).toHaveBeenNthCalledWith(2, "42");
    expect(runtime.submit).toHaveBeenNthCalledWith(1, { text: "busy", sessionId: "s2", channel: "telegram" });
    expect(runtime.submit).toHaveBeenNthCalledWith(2, { text: "new topic", sessionId: "s2", channel: "telegram" });
    expect(runtime.submit).toHaveBeenNthCalledWith(3, { text: "continue", sessionId: "s2", channel: "telegram" });
  });

  it("switches Telegram to an existing conversation and keeps subsequent turns there", async () => {
    const runtime = client();
    const turns = turnsFor(runtime);
    await turns.ensureSession();
    const selected = await turns.selectConversation("s2");
    expect(selected.id).toBe("s2");
    expect(runtime.telegramSession).toHaveBeenCalledWith("42", { sessionId: "s2" });
    await turns.submit(async () => ({ text: "continue" }));
    expect(runtime.submit).toHaveBeenCalledWith({ text: "continue", sessionId: "s2", channel: "telegram" });
  });

  it("keeps an active reply when the selected conversation is picked again", async () => {
    const turns = turnsFor();
    await turns.ensureSession();
    turns.consume(envelope({ type: "turn", text: "hello", channel: "cli", hasAttachments: false }));
    await turns.selectConversation("s1");
    turns.consume(envelope({ type: "text_delta", delta: "Still here" }));
    expect(turns.consume(envelope({ type: "done", sessionId: "s1" })))
      .toMatchObject({ chunks: ["Still here"] });
  });

  it("delivers a run initiated on another client with chunked text and artifacts", async () => {
    const turns = turnsFor();
    await turns.ensureSession();
    const artifact = { id: "a1", kind: "image" as const, name: "result.png", mimeType: "image/png", size: 3, path: "/tmp/result.png" };
    expect(turns.consume(envelope({ type: "turn", text: "create it", channel: "macos", hasAttachments: false }))).toBeNull();
    expect(turns.consume(envelope({ type: "text_delta", delta: `${"word ".repeat(900)}Done.` }))).toBeNull();
    expect(turns.consume(envelope({ type: "artifact", artifact }))).toBeNull();
    const result = turns.consume(envelope({ type: "done", sessionId: "s1" }));
    expect(result?.chunks.length).toBeGreaterThan(1);
    expect(result?.chunks.every((chunk) => chunk.length <= 4096)).toBe(true);
    expect(result?.artifacts).toEqual([artifact]);
  });

  it("reports shared conversation navigation", async () => {
    const turns = turnsFor();
    await turns.ensureSession();
    turns.consume(envelope({ type: "turn", text: "the bot work", channel: "macos", hasAttachments: false }));
    turns.consume(envelope({
      type: "navigate",
      session: { id: "s1", cwd: null, title: "Telegram reconnects", updatedAt: new Date().toISOString() },
      url: "agent://sessions/s1",
    }));
    expect(turns.consume(envelope({ type: "done", sessionId: "s1" })))
      .toMatchObject({ chunks: ["Resumed “Telegram reconnects”."] });
  });

  it("continues in the opened conversation after navigation", async () => {
    const runtime = client();
    const turns = turnsFor(runtime);
    await turns.submit(async () => ({ text: "open earlier work" }));
    turns.consume(envelope({ type: "turn", text: "open earlier work", channel: "telegram", hasAttachments: false }));
    turns.consume(envelope({
      type: "navigate",
      session: { ...session, id: "s2", title: "Earlier work" },
      url: "agent://sessions/s2",
    }));
    turns.consume(envelope({ type: "done", sessionId: "s2" }));
    runtime.submit.mockResolvedValue({ id: "r2", sessionId: "s2", origin: "telegram" });
    runtime.telegramSession.mockResolvedValue({ ...session, id: "s2" });
    await turns.submit(async () => ({ text: "continue" }));
    expect(runtime.submit).toHaveBeenLastCalledWith({ text: "continue", sessionId: "s2", channel: "telegram" });
  });

  it("restores the selected active run after a gateway restart", async () => {
    const runtime = client();
    const turns = turnsFor(runtime);
    await turns.ensureSession();
    const snapshot: RuntimeSnapshot = {
      sessions: [{ ...session, activeRunId: "r1" }],
      transcript: { session, messages: [{ role: "user", content: "hello" }] },
      activeRuns: [{
        run: { id: "r1", sessionId: "s1", origin: "macos" },
        turn: { type: "turn", text: "hello", channel: "macos", hasAttachments: false },
        session, output: "Working", artifacts: [], navigation: null,
      }],
      lastRuns: [],
    };
    expect(await turns.reconcile(snapshot)).toEqual([]);
    expect(turns.hasActiveRun()).toBe(true);
    expect(await turns.stop()).toBe(true);
    expect(runtime.stop).toHaveBeenCalledWith("r1");
    expect(turns.consume(envelope({ type: "done", sessionId: "s1" }))).toMatchObject({ chunks: ["Working"] });
    expect(turns.hasActiveRun()).toBe(false);
  });

  it("does not deliver another session's turns into the selected Telegram conversation", async () => {
    const turns = turnsFor();
    await turns.ensureSession();
    await turns.reconcile({ sessions: [{ ...session, activeRunId: null }], transcript: { session, messages: [] }, activeRuns: [], lastRuns: [] });
    expect(turns.consume(envelope({ type: "turn", text: "other", channel: "cli", hasAttachments: false }, "r2", "s2"))).toBeNull();
    expect(turns.consume(envelope({ type: "text_delta", delta: "secret" }, "r2", "s2"))).toBeNull();
    expect(turns.consume(envelope({ type: "done", sessionId: "s2" }, "r2", "s2"))).toBeNull();
    expect(turns.hasActiveRun()).toBe(false);
  });

  it("continues an active run from its snapshot without duplicating text", async () => {
    const turns = turnsFor();
    await turns.ensureSession();
    turns.consume(envelope({ type: "turn", text: "hello", channel: "cli", hasAttachments: false }));
    turns.consume(envelope({ type: "text_delta", delta: "Partial answer" }));
    const snapshot: RuntimeSnapshot = {
      sessions: [], transcript: null,
      activeRuns: [{
        run: { id: "r1", sessionId: "s1", origin: "cli" },
        turn: { type: "turn", text: "hello", channel: "cli", hasAttachments: false },
        session: null,
        output: "Partial answer plus",
        artifacts: [],
        navigation: null,
      }],
      lastRuns: [],
    };
    expect(await turns.reconcile(snapshot)).toEqual([]);
    turns.consume(envelope({ type: "text_delta", delta: " more" }));
    expect(turns.consume(envelope({ type: "done", sessionId: "s1" })))
      .toMatchObject({ chunks: ["Partial answer plus more"] });
  });

  it("delivers a completed turn missed during reconnect only if it was pending", async () => {
    const turns = turnsFor();
    await turns.ensureSession();
    turns.consume(envelope({ type: "turn", text: "hello", channel: "cli", hasAttachments: false }));
    const snapshot: RuntimeSnapshot = {
      sessions: [], transcript: {
        session,
        messages: [{ role: "user", content: "hello" }, { role: "assistant", content: "Saved answer" }],
      },
      activeRuns: [],
      lastRuns: [{ id: "r1", sessionId: "s1", state: "complete" }],
    };
    expect(await turns.reconcile(snapshot)).toMatchObject([{ chunks: ["Saved answer"] }]);
    expect(await turns.reconcile(snapshot)).toEqual([]);
  });

  it("recovers a run that finished before its submit response arrived", async () => {
    const turns = turnsFor();
    await turns.ensureSession();
    const snapshot: RuntimeSnapshot = {
      sessions: [], transcript: {
        session,
        messages: [{ role: "user", content: "hello" }, { role: "assistant", content: "Saved answer" }],
      },
      activeRuns: [],
      lastRuns: [{ id: "r1", sessionId: "s1", state: "complete" }],
    };
    expect(await turns.reconcile(snapshot)).toEqual([]);
    await expect(turns.submit(async () => ({ text: "hello" }))).resolves.toMatchObject({
      accepted: true,
      recovered: [{ chunks: ["Saved answer"] }],
    });
    expect(await turns.reconcile(snapshot)).toEqual([]);
  });

  it("passes runtime errors and preparation failures through concise messages", async () => {
    const turns = turnsFor();
    await turns.ensureSession();
    turns.consume(envelope({ type: "turn", text: "hello", channel: "telegram", hasAttachments: false }));
    expect(turns.consume(envelope({ type: "error", message: "Interrupted. Your session is saved." })))
      .toMatchObject({ chunks: ["Interrupted. Your session is saved."] });
    expect(telegramFailure(new Error("Voice note exceeds the 25 MB limit."))).toContain("25 MB");
    expect(telegramFailure(new Error("network"))).toBe("I could not start that response. Please try again.");
  });

  it("enforces the voice limit before and after download", () => {
    expect(() => checkTelegramVoiceSize(MAX_ATTACHMENT_BYTES)).not.toThrow();
    expect(() => checkTelegramVoiceSize(MAX_ATTACHMENT_BYTES + 1)).toThrow("25 MB");
  });
});
