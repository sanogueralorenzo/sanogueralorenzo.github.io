import { describe, expect, it, vi } from "vitest";
import type { RunEnvelope, RuntimeEvent, RuntimeSnapshot } from "../conversation/types.js";
import { MAX_ATTACHMENT_BYTES } from "../workspace/assets.js";
import { checkTelegramVoiceSize, isTelegramOwner, telegramFailure, TelegramTurns } from "./turn.js";

function client(run: object | null = { id: "r1", origin: "telegram" }) {
  return {
    submit: vi.fn(async () => run),
    stop: vi.fn(async () => true),
  };
}

const envelope = (event: RuntimeEvent, runId = "r1"): RunEnvelope => ({ runId, event });

describe("Telegram turns", () => {
  it("allows only the private owner", () => {
    expect(isTelegramOwner("42", "private", 42)).toBe(true);
    expect(isTelegramOwner("42", "group", 42)).toBe(false);
    expect(isTelegramOwner("42", "private", 7)).toBe(false);
  });

  it("uses centralized submit, busy, and stop semantics", async () => {
    const runtime = client();
    const turns = new TelegramTurns(runtime);
    await expect(turns.submit(async () => ({ text: "hello" }))).resolves.toEqual({ accepted: true, recovered: null });
    expect(runtime.submit).toHaveBeenCalledWith({ text: "hello", channel: "telegram" });
    await expect(turns.stop()).resolves.toBe(true);
    expect(runtime.stop).toHaveBeenCalledOnce();
    await expect(new TelegramTurns(client(null)).submit(async () => ({ text: "busy" }))).resolves.toEqual({ accepted: false, recovered: null });
  });

  it("starts the next accepted message as a new conversation", async () => {
    const runtime = client(null);
    const turns = new TelegramTurns(runtime);
    turns.newConversation();

    await expect(turns.submit(async () => ({ text: "busy" }))).resolves.toEqual({ accepted: false, recovered: null });
    runtime.submit.mockResolvedValue({ id: "r2", origin: "telegram" });
    await expect(turns.submit(async () => ({ text: "new topic" }))).resolves.toEqual({ accepted: true, recovered: null });
    await expect(turns.submit(async () => ({ text: "continue" }))).resolves.toEqual({ accepted: true, recovered: null });

    expect(runtime.submit).toHaveBeenNthCalledWith(1, { text: "busy", fresh: true, channel: "telegram" });
    expect(runtime.submit).toHaveBeenNthCalledWith(2, { text: "new topic", fresh: true, channel: "telegram" });
    expect(runtime.submit).toHaveBeenNthCalledWith(3, { text: "continue", channel: "telegram" });
  });

  it("delivers a run initiated on another client with chunked text and artifacts", () => {
    const turns = new TelegramTurns(client());
    const artifact = { id: "a1", kind: "image" as const, name: "result.png", mimeType: "image/png", size: 3, path: "/tmp/result.png" };
    expect(turns.consume(envelope({ type: "turn", text: "create it", channel: "macos", hasAttachments: false }))).toBeNull();
    expect(turns.consume(envelope({ type: "text_delta", delta: `${"word ".repeat(900)}Done.` }))).toBeNull();
    expect(turns.consume(envelope({ type: "artifact", artifact }))).toBeNull();
    const result = turns.consume(envelope({ type: "done", sessionId: "s1" }));
    expect(result?.chunks.length).toBeGreaterThan(1);
    expect(result?.chunks.every((chunk) => chunk.length <= 4096)).toBe(true);
    expect(result?.artifacts).toEqual([artifact]);
  });

  it("reports shared conversation navigation", () => {
    const turns = new TelegramTurns(client());
    turns.consume(envelope({ type: "turn", text: "the bot work", channel: "macos", hasAttachments: false }));
    turns.consume(envelope({
      type: "navigate",
      session: { id: "s1", scopeKey: "assistant:local", cwd: null, title: "Telegram reconnects", updatedAt: new Date().toISOString() },
      url: "agent://sessions/s1",
    }));
    expect(turns.consume(envelope({ type: "done", sessionId: "s1" })))
      .toMatchObject({ chunks: ["Resumed “Telegram reconnects”."] });
  });

  it("continues an active run from its snapshot without duplicating text", () => {
    const turns = new TelegramTurns(client());
    turns.consume(envelope({ type: "turn", text: "hello", channel: "cli", hasAttachments: false }));
    turns.consume(envelope({ type: "text_delta", delta: "Partial answer" }));
    const snapshot: RuntimeSnapshot = {
      transcript: null,
      activeRun: {
        run: { id: "r1", origin: "cli" },
        turn: { type: "turn", text: "hello", channel: "cli", hasAttachments: false },
        session: null,
        output: "Partial answer plus",
        artifacts: [],
        navigation: null,
      },
      lastRun: null,
    };
    expect(turns.reconcile(snapshot)).toBeNull();
    turns.consume(envelope({ type: "text_delta", delta: " more" }));
    expect(turns.consume(envelope({ type: "done", sessionId: "s1" })))
      .toMatchObject({ chunks: ["Partial answer plus more"] });
  });

  it("delivers a completed turn missed during reconnect only if it was pending", () => {
    const turns = new TelegramTurns(client());
    turns.consume(envelope({ type: "turn", text: "hello", channel: "cli", hasAttachments: false }));
    const snapshot: RuntimeSnapshot = {
      transcript: {
        session: { id: "s1", scopeKey: "assistant:local", cwd: null, title: "Hello", updatedAt: new Date().toISOString() },
        messages: [{ role: "user", content: "hello" }, { role: "assistant", content: "Saved answer" }],
      },
      activeRun: null,
      lastRun: { id: "r1", sessionId: "s1", state: "complete" },
    };
    expect(turns.reconcile(snapshot)).toMatchObject({ chunks: ["Saved answer"] });
    expect(turns.reconcile(snapshot)).toBeNull();
  });

  it("recovers a run that finished before its submit response arrived", async () => {
    const turns = new TelegramTurns(client());
    const snapshot: RuntimeSnapshot = {
      transcript: {
        session: { id: "s1", scopeKey: "assistant:local", cwd: null, title: "Hello", updatedAt: new Date().toISOString() },
        messages: [{ role: "user", content: "hello" }, { role: "assistant", content: "Saved answer" }],
      },
      activeRun: null,
      lastRun: { id: "r1", sessionId: "s1", state: "complete" },
    };
    expect(turns.reconcile(snapshot)).toBeNull();
    await expect(turns.submit(async () => ({ text: "hello" }))).resolves.toMatchObject({
      accepted: true,
      recovered: { chunks: ["Saved answer"] },
    });
    expect(turns.reconcile(snapshot)).toBeNull();
  });

  it("passes runtime errors and preparation failures through concise messages", () => {
    const turns = new TelegramTurns(client());
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
