import { describe, expect, it } from "vitest";
import { TELEGRAM_PAIRING_TTL_MS, pairingExpiresAt, pairingHash, splitTelegramText } from "./text.js";

describe("Telegram helpers", () => {
  it("splits long messages without losing text", () => {
    const text = `${"word ".repeat(900)}\n\nDone.`.trim();
    const chunks = splitTelegramText(text, 500);
    expect(chunks.every((chunk) => chunk.length <= 500)).toBe(true);
    expect(chunks.join(" ").replace(/\s+/g, " ")).toBe(text.replace(/\s+/g, " "));
  });

  it("hashes pairing codes deterministically", () => {
    expect(pairingHash("hello")).toBe(pairingHash("hello"));
    expect(pairingHash("hello")).not.toBe(pairingHash("world"));
  });

  it("expires pairing links after three minutes", () => {
    const now = Date.UTC(2026, 8, 19, 12, 0, 0);

    expect(TELEGRAM_PAIRING_TTL_MS).toBe(180_000);
    expect(pairingExpiresAt(now)).toBe("2026-09-19T12:03:00.000Z");
  });
});
