import { mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it, vi } from "vitest";
import { temporary } from "../test-support.js";
import { TelegramReload } from "./reload.js";

function harness() {
  const projectRoot = temporary("agent-telegram-reload-");
  const dist = join(projectRoot, "dist");
  const marker = join(dist, ".ready");
  mkdirSync(dist);
  writeFileSync(marker, "1\n");
  const restart = vi.fn(async () => undefined);
  const reload = new TelegramReload({ projectRoot, restart, intervalMs: 5 });
  reload.start();
  return { projectRoot, marker, reload, restart };
}

describe("Telegram reload", () => {
  it("restarts once for a completed build", async () => {
    const { marker, reload, restart } = harness();
    writeFileSync(marker, "2\n");
    await vi.waitFor(() => expect(restart).toHaveBeenCalledOnce());
    writeFileSync(marker, "2\n");
    await new Promise((resolve) => setTimeout(resolve, 20));
    expect(restart).toHaveBeenCalledOnce();
    reload.stop();
  });

  it("waits until the active response is delivered", async () => {
    const { marker, reload, restart } = harness();
    reload.turnStarted();
    writeFileSync(marker, "2\n");
    await new Promise((resolve) => setTimeout(resolve, 20));
    expect(restart).not.toHaveBeenCalled();
    reload.turnDelivered();
    await vi.waitFor(() => expect(restart).toHaveBeenCalledOnce());
    reload.stop();
  });

  it("ignores incomplete builds without a readiness marker", async () => {
    const { projectRoot, marker, reload, restart } = harness();
    rmSync(marker);
    writeFileSync(join(projectRoot, "dist", "partial.js"), "broken");
    await new Promise((resolve) => setTimeout(resolve, 20));
    expect(restart).not.toHaveBeenCalled();
    reload.stop();
  });

  it("keeps development lifecycle messages out of Telegram", () => {
    const gateway = readFileSync(join(fileURLToPath(new URL(".", import.meta.url)), "gateway.ts"), "utf8");
    expect(gateway).not.toMatch(/updated and reconnected|failed verification|Applying an Agent update/);
  });
});
