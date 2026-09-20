import { beforeEach, describe, expect, it, vi } from "vitest";

const mocks = vi.hoisted(() => ({
  installService: vi.fn(),
  readSecret: vi.fn(),
  requestRestart: vi.fn(),
  setup: vi.fn(),
}));

vi.mock("../cli/setup.js", () => ({
  readSecretLine: vi.fn(),
  setupAgent: mocks.setup,
}));

vi.mock("../local/credentials.js", () => ({
  readSecret: mocks.readSecret,
  writeSecret: vi.fn(),
}));

vi.mock("./service.js", () => ({
  installTelegramBackgroundService: mocks.installService,
  requestTelegramRestart: mocks.requestRestart,
}));

import { runTelegramCommand } from "./command.js";

describe("Telegram guided setup", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mocks.setup.mockRejectedValue(new Error("stop after backend setup"));
  });

  it.each([
    ["browser", ["--chatgpt"]],
    ["headless device", ["--headless"]],
    ["API key", ["--api-key"]],
  ])("forwards the explicit %s choice to the shared setup", async (_label, args) => {
    await expect(runTelegramCommand(["setup", ...args])).rejects.toThrow("stop after backend setup");
    expect(mocks.setup).toHaveBeenCalledExactlyOnceWith(args, false);
  });

  it("lets shared setup skip an existing connection", async () => {
    await expect(runTelegramCommand(["setup"])).rejects.toThrow("stop after backend setup");
    expect(mocks.setup).toHaveBeenCalledExactlyOnceWith([], true);
  });

  it("starts the configured background service and returns", async () => {
    mocks.readSecret.mockReturnValue("telegram-token");

    await expect(runTelegramCommand([])).resolves.toBeUndefined();

    expect(mocks.installService).toHaveBeenCalledOnce();
  });

  it("records a model-requested restart without reinstalling the service", async () => {
    await expect(runTelegramCommand(["restart"])).resolves.toBeUndefined();

    expect(mocks.requestRestart).toHaveBeenCalledOnce();
    expect(mocks.installService).not.toHaveBeenCalled();
  });
});
