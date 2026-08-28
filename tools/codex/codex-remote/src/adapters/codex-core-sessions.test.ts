import { execFile } from "node:child_process";
import { beforeEach, describe, expect, it, vi } from "vitest";

vi.mock("node:child_process", () => ({
  execFile: vi.fn(),
}));

import { ensureThreadTitleWatcherStarted } from "./codex-core-sessions.js";

const mockedExecFile = vi.mocked(execFile);

describe("ensureThreadTitleWatcherStarted", () => {
  beforeEach(() => {
    mockedExecFile.mockReset();
  });

  it("starts codex-core thread title watcher for the configured home", async () => {
    mockedExecFile.mockImplementation((_file, _args, _options, callback) => {
      if (typeof callback !== "function") {
        throw new Error("expected callback");
      }
      callback(null, "Thread-titles watcher running (PID 123)\n", "");
      return {} as ReturnType<typeof execFile>;
    });

    await ensureThreadTitleWatcherStarted("/tmp/codex-home");

    expect(mockedExecFile).toHaveBeenCalledWith(
      "codex-core",
      [
        "sessions",
        "watch",
        "thread-titles",
        "start",
        "--home",
        "/tmp/codex-home",
      ],
      { maxBuffer: 10 * 1024 * 1024 },
      expect.any(Function)
    );
  });
});
