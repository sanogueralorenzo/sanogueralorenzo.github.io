import { beforeEach, describe, expect, it, vi } from "vitest";
import { loadRuntimeConfig } from "./config.js";

describe("loadRuntimeConfig", () => {
  beforeEach(() => {
    vi.unstubAllEnvs();
    vi.stubEnv("TELEGRAM_BOT_TOKEN", "test-token");
  });

  it("refuses to start without a Telegram chat allowlist", () => {
    expect(() => loadRuntimeConfig()).toThrow(
      "TELEGRAM_ALLOWED_CHAT_IDS"
    );
  });

  it("refuses to start with an empty Telegram chat allowlist", () => {
    vi.stubEnv("TELEGRAM_ALLOWED_CHAT_IDS", " , ");

    expect(() => loadRuntimeConfig()).toThrow(
      "TELEGRAM_ALLOWED_CHAT_IDS"
    );
  });

  it("parses and trims multiple allowed chat IDs", () => {
    vi.stubEnv("TELEGRAM_ALLOWED_CHAT_IDS", "123, -456,123");

    expect([...loadRuntimeConfig().allowedChatIds]).toEqual(["123", "-456"]);
  });
});
