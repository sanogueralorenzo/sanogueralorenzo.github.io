import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach } from "vitest";

const cleanups: Array<() => unknown | Promise<unknown>> = [];

afterEach(async () => {
  while (cleanups.length) await cleanups.pop()!();
});

export function cleanup(action: () => unknown | Promise<unknown>): void {
  cleanups.push(action);
}

export function temporary(prefix: string): string {
  const path = mkdtempSync(join(tmpdir(), prefix));
  cleanup(() => rmSync(path, { recursive: true, force: true }));
  return path;
}
