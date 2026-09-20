import { describe, expect, it, vi } from "vitest";
import type { RuntimeEvent } from "../conversation/types.js";
import { MAX_ATTACHMENT_BYTES } from "../workspace/assets.js";
import { checkTelegramVoiceSize, isTelegramOwner, TelegramTurns } from "./turn.js";

function client(events: RuntimeEvent[] = [], failure?: Error) {
  return {
    isRunning: false,
    cancel: vi.fn(async () => true),
    async *events() {
      for (const event of events) yield event;
      if (failure) throw failure;
    },
  };
}

describe("Telegram turns", () => {
  it("allows only the private owner", () => {
    expect(isTelegramOwner("42", "private", 42)).toBe(true);
    expect(isTelegramOwner("42", "group", 42)).toBe(false);
    expect(isTelegramOwner("42", "private", 7)).toBe(false);
  });

  it("reports busy turns and delegates stop to the runtime client", async () => {
    const runtime = client();
    runtime.isRunning = true;
    const turns = new TelegramTurns(runtime);

    await expect(turns.run(async () => ({ text: "hello" }))).resolves.toEqual({ state: "busy" });
    await expect(turns.stop()).resolves.toBe(true);
    expect(runtime.cancel).toHaveBeenCalledOnce();
  });

  it("collects chunked text and artifacts from the shared stream", async () => {
    const artifact = { id: "a1", kind: "image" as const, name: "result.png", mimeType: "image/png", size: 3, path: "/tmp/result.png" };
    const turns = new TelegramTurns(client([
      { type: "text_delta", delta: `${"word ".repeat(900)}Done.` },
      { type: "artifact", artifact },
      { type: "done", sessionId: "s1" },
    ]));

    const result = await turns.run(async () => ({ text: "create it" }));
    expect(result.state).toBe("complete");
    if (result.state !== "complete") return;
    expect(result.chunks.length).toBeGreaterThan(1);
    expect(result.chunks.every((chunk) => chunk.length <= 4096)).toBe(true);
    expect(result.artifacts).toEqual([artifact]);
  });

  it("preserves partial text when the stream is interrupted", async () => {
    const turns = new TelegramTurns(client([
      { type: "text_delta", delta: "Partial answer" },
    ], new Error("disconnected")));

    await expect(turns.run(async () => ({ text: "hello" }))).resolves.toMatchObject({
      state: "complete",
      chunks: [expect.stringContaining("Partial answer\n\nInterrupted")],
    });
  });

  it("reports cancellation before any text as an interruption", async () => {
    const turns = new TelegramTurns(client([], new DOMException("stopped", "AbortError")));
    await expect(turns.run(async () => ({ text: "hello" }))).resolves.toMatchObject({
      state: "complete",
      chunks: [expect.stringMatching(/^Interrupted\./)],
    });
  });

  it("enforces the voice limit before and after download", () => {
    expect(() => checkTelegramVoiceSize(MAX_ATTACHMENT_BYTES)).not.toThrow();
    expect(() => checkTelegramVoiceSize(MAX_ATTACHMENT_BYTES + 1)).toThrow("25 MB");
  });
});
