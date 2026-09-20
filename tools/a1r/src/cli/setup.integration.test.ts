import { chmodSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { afterEach, describe, expect, it, vi } from "vitest";
import { Store } from "../core/store.js";
import { setupA1R } from "./setup.js";

const fixture = join(dirname(fileURLToPath(import.meta.url)), "..", "codex", "test-fixtures", "fake-app-server.mjs");
const roots: string[] = [];

afterEach(() => {
  vi.restoreAllMocks();
  for (const root of roots.splice(0)) rmSync(root, { recursive: true, force: true });
});

function executable(homeDir: string): string {
  const path = join(homeDir, "fake-codex");
  writeFileSync(path, `#!/bin/sh\nif [ "$1" = "--version" ]; then echo "fake-codex 1"; exit 0; fi\nexec "${process.execPath}" "${fixture}"\n`);
  chmodSync(path, 0o700);
  return path;
}

async function runSetup(args: string[]): Promise<{ output: string; rpc: string }> {
  const homeDir = mkdtempSync(join(tmpdir(), "a1r-cli-setup-"));
  roots.push(homeDir);
  const rpcLog = join(homeDir, "rpc.log");
  const previous = {
    home: process.env.A1R_HOME,
    command: process.env.A1R_CODEX_COMMAND,
    scenario: process.env.A1R_FAKE_SCENARIO,
    log: process.env.A1R_FAKE_LOG,
    path: process.env.PATH,
  };
  process.env.A1R_HOME = homeDir;
  process.env.A1R_CODEX_COMMAND = executable(homeDir);
  process.env.A1R_FAKE_SCENARIO = "normal";
  process.env.A1R_FAKE_LOG = rpcLog;
  process.env.PATH = ""; // Prevent the test from opening a real browser.
  const output: string[] = [];
  vi.spyOn(console, "log").mockImplementation((...values) => output.push(values.join(" ")));
  vi.spyOn(process.stdout, "write").mockImplementation((value) => {
    output.push(String(value));
    return true;
  });
  try {
    await setupA1R(args);
    const store = new Store(homeDir, "a1r.sqlite", { recoverRuns: false });
    expect(store.getSetting("backend")).toBe("codex");
    store.close();
    return { output: output.join("\n"), rpc: readFileSync(rpcLog, "utf8") };
  } finally {
    if (previous.home === undefined) delete process.env.A1R_HOME; else process.env.A1R_HOME = previous.home;
    if (previous.command === undefined) delete process.env.A1R_CODEX_COMMAND; else process.env.A1R_CODEX_COMMAND = previous.command;
    if (previous.scenario === undefined) delete process.env.A1R_FAKE_SCENARIO; else process.env.A1R_FAKE_SCENARIO = previous.scenario;
    if (previous.log === undefined) delete process.env.A1R_FAKE_LOG; else process.env.A1R_FAKE_LOG = previous.log;
    if (previous.path === undefined) delete process.env.PATH; else process.env.PATH = previous.path;
  }
}

describe.sequential("CLI subscription setup", () => {
  it("reuses an existing A1R-specific login transparently during ordinary setup", async () => {
    const result = await runSetup(["--chatgpt"]);

    expect(result.output).toContain("A1R-specific ChatGPT login");
    expect(result.output).toContain("reuse its private ChatGPT login");
    expect(result.rpc).not.toContain("account/login/start");
  });

  it("forces and displays device-code login even when A1R is already connected", async () => {
    const result = await runSetup(["--device-code"]);

    expect(result.output).toContain("Starting a fresh device-code login for A1R");
    expect(result.output).toContain("https://auth.openai.com/codex/device");
    expect(result.output).toContain("Enter code: A1R-TEST");
    expect(result.rpc).toContain("account/login/start");
  });
});
