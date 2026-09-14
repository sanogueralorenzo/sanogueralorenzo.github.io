import { describe, expect, it } from "vitest";
import { sendTextChunks } from "./telegram-text.js";

describe("sendTextChunks", () => {
  it("sends a single short message", async () => {
    const sent: string[] = [];
    await sendTextChunks(async (text) => {
      sent.push(text);
    }, "short");

    expect(sent).toEqual(["short"]);
  });

  it("splits long text into multiple chunks", async () => {
    const sent: string[] = [];
    const long = `Header\n${"word ".repeat(1400)}`.trim();

    await sendTextChunks(async (text) => {
      sent.push(text);
    }, long);

    expect(sent.length).toBeGreaterThan(1);
    expect(sent.join(" ")).toContain("Header");
    expect(sent.join(" ").replace(/\s+/g, " ").trim()).toContain("word word word");
  });
});
