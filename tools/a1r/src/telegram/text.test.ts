import { describe, expect, it } from "vitest";
import { pairingHash, splitTelegramText } from "./text.js";

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
});
