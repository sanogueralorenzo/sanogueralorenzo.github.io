import { beforeEach, describe, expect, it, vi } from "vitest";

const mocks = vi.hoisted(() => ({
  configured: vi.fn(),
  readSecretLine: vi.fn(),
  setup: vi.fn(),
}));

vi.mock("../cli/setup.js", () => ({
  isA1RConfigured: mocks.configured,
  readSecretLine: mocks.readSecretLine,
  setupA1R: mocks.setup,
}));

import { runTelegramCommand } from "./command.js";

describe("Telegram guided setup", () => {
  beforeEach(() => {
    mocks.configured.mockReset().mockResolvedValue(false);
    mocks.readSecretLine.mockReset().mockRejectedValue(new Error("stop at Telegram setup"));
    mocks.setup.mockReset().mockRejectedValue(new Error("stop after backend setup"));
  });

  it.each([
    ["browser", ["--chatgpt"]],
    ["headless device", ["--headless"]],
    ["API key", ["--api-key"]],
  ])("forwards the explicit %s choice to the shared setup", async (_label, args) => {
    mocks.configured.mockResolvedValue(true);
    await expect(runTelegramCommand(["setup", ...args])).rejects.toThrow("stop after backend setup");
    expect(mocks.setup).toHaveBeenCalledExactlyOnceWith(args);
    expect(mocks.configured).not.toHaveBeenCalled();
  });

  it("uses the shared three-choice prompt when A1R is not configured", async () => {
    await expect(runTelegramCommand(["setup"])).rejects.toThrow("stop after backend setup");
    expect(mocks.configured).toHaveBeenCalledOnce();
    expect(mocks.setup).toHaveBeenCalledExactlyOnceWith([]);
  });

  it("skips backend setup when A1R already has a usable connection", async () => {
    mocks.configured.mockResolvedValue(true);

    await expect(runTelegramCommand(["setup"])).rejects.toThrow("stop at Telegram setup");

    expect(mocks.configured).toHaveBeenCalledOnce();
    expect(mocks.setup).not.toHaveBeenCalled();
    expect(mocks.readSecretLine).toHaveBeenCalledWith("Bot token (hidden): ");
  });
});
