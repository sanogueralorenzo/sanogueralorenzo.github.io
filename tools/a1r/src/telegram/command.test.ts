import { beforeEach, describe, expect, it, vi } from "vitest";

const setup = vi.hoisted(() => vi.fn());

vi.mock("../cli/setup.js", () => ({
  readSecretLine: vi.fn(),
  setupA1R: setup,
}));

import { runTelegramCommand } from "./command.js";

describe("Telegram guided setup", () => {
  beforeEach(() => {
    setup.mockReset();
    setup.mockRejectedValue(new Error("stop after backend setup"));
  });

  it.each([
    ["browser", ["--chatgpt"]],
    ["headless device", ["--headless"]],
    ["API key", ["--api-key"]],
  ])("forwards the explicit %s choice to the shared setup", async (_label, args) => {
    await expect(runTelegramCommand(["setup", ...args])).rejects.toThrow("stop after backend setup");
    expect(setup).toHaveBeenCalledExactlyOnceWith(args);
  });

  it("uses the shared three-choice prompt when no setup flag is supplied", async () => {
    await expect(runTelegramCommand(["setup"])).rejects.toThrow("stop after backend setup");
    expect(setup).toHaveBeenCalledExactlyOnceWith([]);
  });
});
