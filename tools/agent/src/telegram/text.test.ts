import { afterEach, describe, expect, it, vi } from "vitest";
import { keepTelegramTyping, splitTelegramText } from "./text.js";
afterEach(() => vi.useRealTimers());

describe("Telegram helpers", () => {
  it("splits long messages without losing text", () => {
    const text = `${"word ".repeat(900)}\n\nDone.`.trim();
    const chunks = splitTelegramText(text, 500);
    expect(chunks.every((chunk) => chunk.length <= 500)).toBe(true);
    expect(chunks.join(" ").replace(/\s+/g, " ")).toBe(text.replace(/\s+/g, " "));
  });

  it("keeps the activity indicator alive without publishing draft text", async () => {
    vi.useFakeTimers();
    const send = vi.fn(async () => undefined);
    const stop = keepTelegramTyping(send, 4_000);
    expect(send).toHaveBeenCalledTimes(1);
    await vi.advanceTimersByTimeAsync(8_100);
    expect(send).toHaveBeenCalledTimes(3);
    stop();
    await vi.advanceTimersByTimeAsync(8_000);
    expect(send).toHaveBeenCalledTimes(3);
  });
});
