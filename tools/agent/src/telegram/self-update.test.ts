import { mkdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it, vi } from "vitest";
import { temporary } from "../test-support.js";
import { acknowledgeUpdate, pendingUpdateOwner, TelegramSelfUpdate } from "./self-update.js";

function fixture(): { projectRoot: string; homeDir: string; source: string } {
  const root = temporary("agent-self-update-");
  const projectRoot = join(root, "project");
  const homeDir = join(root, "home");
  const source = join(projectRoot, "src", "main.ts");
  mkdirSync(join(projectRoot, "src"), { recursive: true });
  writeFileSync(source, "export const version = 1;\n");
  writeFileSync(join(projectRoot, "package.json"), "{}\n");
  return { projectRoot, homeDir, source };
}

type UpdateOptions = ConstructorParameters<typeof TelegramSelfUpdate>[0];

function updateHarness(options: Partial<UpdateOptions> = {}, onStop?: () => void) {
  const files = fixture();
  let finish!: () => void;
  const stopped = new Promise<void>((resolve) => { finish = resolve; });
  let value!: TelegramSelfUpdate;
  value = new TelegramSelfUpdate({
    ...files,
    ownerId: () => undefined,
    debounceMs: 5,
    verify: async () => undefined,
    requestRuntimeRestart: async () => true,
    stopGateway: async () => { onStop?.(); value.stop(); finish(); },
    ...options,
  });
  return { ...files, updater: value, stopped };
}

describe("Telegram self-update", () => {
  it("waits for the active reply, verifies a stable build, and restarts once", async () => {
    const order: string[] = [];
    const { updater, homeDir, stopped } = updateHarness({
      ownerId: () => "42",
      verify: async () => { order.push("verify"); },
      requestRuntimeRestart: async () => {
        order.push("runtime");
        return true;
      },
    }, () => order.push("gateway"));

    expect(updater.beginTurn()).toBe(true);
    updater.noteChange();
    await new Promise((resolve) => setTimeout(resolve, 20));
    expect(order).toEqual([]);

    updater.endTurn();
    await stopped;

    expect(order).toEqual(["verify", "runtime", "gateway"]);
    expect(pendingUpdateOwner(homeDir)).toBe("42");
    acknowledgeUpdate(homeDir);
    expect(pendingUpdateOwner(homeDir)).toBeNull();
  });

  it("re-verifies when source content changes during the check", async () => {
    let checks = 0;
    let instance!: TelegramSelfUpdate;
    let harness!: ReturnType<typeof updateHarness>;
    harness = updateHarness({
      verify: async () => {
        checks += 1;
        if (checks === 1) {
          writeFileSync(harness.source, "export const version = 2;\n");
          instance.noteChange();
        }
      },
    });
    instance = harness.updater;

    instance.noteChange();
    await harness.stopped;

    expect(checks).toBe(2);
  });

  it("keeps the current process available when verification fails", async () => {
    const restart = vi.fn(async () => true);
    const failure = vi.fn();
    const { updater } = updateHarness({
      ownerId: () => "42",
      verify: async () => { throw new Error("tests failed"); },
      requestRuntimeRestart: restart,
      onFailure: failure,
    });

    updater.noteChange();
    await vi.waitFor(() => expect(failure).toHaveBeenCalledWith("tests failed"));

    expect(restart).not.toHaveBeenCalled();
    expect(updater.beginTurn()).toBe(true);
    updater.endTurn();
    updater.stop();
  });

  it("cancels verification when the background service is replaced", async () => {
    let verificationStarted!: () => void;
    const started = new Promise<void>((resolve) => { verificationStarted = resolve; });
    let verificationAborted!: () => void;
    const aborted = new Promise<void>((resolve) => { verificationAborted = resolve; });
    const restart = vi.fn(async () => true);
    const { updater } = updateHarness({
      verify: async (signal) => {
        verificationStarted();
        await new Promise<void>((_resolve, reject) => signal.addEventListener("abort", () => {
          verificationAborted();
          reject(new DOMException("Aborted", "AbortError"));
        }, { once: true }));
      },
      requestRuntimeRestart: restart,
    });

    updater.noteChange();
    await started;
    updater.stop();
    await aborted;
    await new Promise((resolve) => setTimeout(resolve, 10));

    expect(restart).not.toHaveBeenCalled();
  });
});
