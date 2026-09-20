import { describe, expect, it, vi } from "vitest";
import type { RunEnvelope, RuntimeEvent } from "../conversation/types.js";
import { MAX_ATTACHMENT_BYTES } from "../workspace/assets.js";
import { checkTelegramVoiceSize, isTelegramOwner, telegramFailure, TelegramTurns } from "./turn.js";

function client(run: object | null = { id: "r1", origin: "telegram", startSequence: 1 }) {
  return {
    submit: vi.fn(async () => run),
    stop: vi.fn(async () => true),
  };
}

const envelope = (sequence: number, event: RuntimeEvent, runId = "r1"): RunEnvelope => ({ runId, sequence, event });

describe("Telegram turns", () => {
  it("allows only the private owner", () => {
    expect(isTelegramOwner("42", "private", 42)).toBe(true);
    expect(isTelegramOwner("42", "group", 42)).toBe(false);
    expect(isTelegramOwner("42", "private", 7)).toBe(false);
  });

  it("uses centralized submit, busy, and stop semantics", async () => {
    const runtime = client();
    const turns = new TelegramTurns(runtime);
    await expect(turns.submit(async () => ({ text: "hello" }))).resolves.toBe(true);
    expect(runtime.submit).toHaveBeenCalledWith({ text: "hello", channel: "telegram" });
    await expect(turns.stop()).resolves.toBe(true);
    expect(runtime.stop).toHaveBeenCalledOnce();
    await expect(new TelegramTurns(client(null)).submit(async () => ({ text: "busy" }))).resolves.toBe(false);
  });

  it("delivers a run initiated on another client with chunked text and artifacts", () => {
    const turns = new TelegramTurns(client());
    const artifact = { id: "a1", kind: "image" as const, name: "result.png", mimeType: "image/png", size: 3, path: "/tmp/result.png" };
    expect(turns.consume(envelope(1, { type: "turn", text: "create it", channel: "macos", hasAttachments: false }))).toBeNull();
    expect(turns.consume(envelope(2, { type: "text_delta", delta: `${"word ".repeat(900)}Done.` }))).toBeNull();
    expect(turns.consume(envelope(3, { type: "artifact", artifact }))).toBeNull();
    const result = turns.consume(envelope(4, { type: "done", sessionId: "s1" }));
    expect(result?.chunks.length).toBeGreaterThan(1);
    expect(result?.chunks.every((chunk) => chunk.length <= 4096)).toBe(true);
    expect(result?.artifacts).toEqual([artifact]);
  });

  it("preserves partial text when the runtime reconnects", () => {
    const turns = new TelegramTurns(client());
    turns.consume(envelope(1, { type: "turn", text: "hello", channel: "cli", hasAttachments: false }));
    turns.consume(envelope(2, { type: "text_delta", delta: "Partial answer" }));
    expect(turns.interrupt()).toMatchObject({ chunks: [expect.stringContaining("Partial answer\n\nInterrupted")] });
    expect(turns.interrupt()).toBeNull();
  });

  it("passes runtime errors and preparation failures through concise messages", () => {
    const turns = new TelegramTurns(client());
    turns.consume(envelope(1, { type: "turn", text: "hello", channel: "telegram", hasAttachments: false }));
    expect(turns.consume(envelope(2, { type: "error", message: "Interrupted. Your session is saved." })))
      .toMatchObject({ chunks: ["Interrupted. Your session is saved."] });
    expect(telegramFailure(new Error("Voice note exceeds the 25 MB limit."))).toContain("25 MB");
    expect(telegramFailure(new Error("network"))).toBe("I could not start that response. Please try again.");
  });

  it("enforces the voice limit before and after download", () => {
    expect(() => checkTelegramVoiceSize(MAX_ATTACHMENT_BYTES)).not.toThrow();
    expect(() => checkTelegramVoiceSize(MAX_ATTACHMENT_BYTES + 1)).toThrow("25 MB");
  });
});
