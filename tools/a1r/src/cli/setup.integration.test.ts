import { chmodSync, existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
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

async function runSetup(
  args: string[],
  options: { scenario?: string; installed?: boolean } = {},
): Promise<{ output: string; rpc: string; backend: string | null; error: Error | null }> {
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
  process.env.A1R_CODEX_COMMAND = options.installed === false ? join(homeDir, "missing-codex") : executable(homeDir);
  process.env.A1R_FAKE_SCENARIO = options.scenario ?? "normal";
  process.env.A1R_FAKE_LOG = rpcLog;
  process.env.PATH = ""; // Prevent the test from opening a real browser.
  const output: string[] = [];
  vi.spyOn(console, "log").mockImplementation((...values) => output.push(values.join(" ")));
  vi.spyOn(process.stdout, "write").mockImplementation((value) => {
    output.push(String(value));
    return true;
  });
  let error: Error | null = null;
  try {
    try {
      await setupA1R(args);
    } catch (cause) {
      error = cause instanceof Error ? cause : new Error(String(cause));
    }
    let backend: string | null = null;
    if (existsSync(join(homeDir, "a1r.sqlite"))) {
      const store = new Store(homeDir, "a1r.sqlite", { recoverRuns: false });
      backend = store.getSetting("backend");
      store.close();
    }
    return {
      output: output.join("\n"),
      rpc: existsSync(rpcLog) ? readFileSync(rpcLog, "utf8") : "",
      backend,
      error,
    };
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

    expect(result.error).toBeNull();
    expect(result.backend).toBe("codex");
    expect(result.output).toContain("A1R-specific ChatGPT login");
    expect(result.output).toContain("reuse its private ChatGPT login");
    expect(result.rpc).not.toContain("account/login/start");
  });

  it("opens only browser login for a disconnected private profile", async () => {
    const result = await runSetup(["--chatgpt"], { scenario: "login-success" });

    expect(result.error).toBeNull();
    expect(result.backend).toBe("codex");
    expect(result.output).toContain("Open this official ChatGPT sign-in page");
    expect(result.output).toContain("https://auth.openai.com/fake");
    expect(result.rpc).toContain('"type":"chatgpt"');
    expect(result.rpc).not.toContain("chatgptDeviceCode");
  });

  it("rejects the removed device-code option before starting app-server", async () => {
    const result = await runSetup(["--device-code"]);

    expect(result.error?.message).toMatch(/Device-code login has been removed/);
    expect(result.backend).toBeNull();
    expect(result.rpc).toBe("");
  });

  it("fails a cancelled or failed browser login without selecting API-key billing", async () => {
    const result = await runSetup(["--chatgpt"], { scenario: "login-failed" });

    expect(result.error?.message).toBe("browser sign-in failed");
    expect(result.backend).toBeNull();
    expect(result.output).not.toContain("Use API-key billing");
    expect(result.rpc).toContain("account/login/start");
  });

  it("fails clearly when Codex is missing without selecting another backend", async () => {
    const result = await runSetup(["--chatgpt"], { installed: false });

    expect(result.error?.message).toMatch(/requires the official Codex CLI/);
    expect(result.backend).toBeNull();
    expect(result.output).not.toContain("Use API-key billing");
  });
});
