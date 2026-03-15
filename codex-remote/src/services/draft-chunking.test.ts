import { describe, expect, it } from "vitest";
import { resolveTelegramDraftStreamingChunking } from "./draft-chunking.js";

describe("resolveTelegramDraftStreamingChunking", () => {
  it("uses OpenClaw-aligned defaults", () => {
    const chunking = resolveTelegramDraftStreamingChunking();
    expect(chunking).toEqual({
      minChars: 200,
      maxChars: 800,
      breakPreference: "paragraph"
    });
  });
});

