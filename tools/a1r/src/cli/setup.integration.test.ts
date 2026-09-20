import { chmodSync, existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { afterEach, describe, expect, it, vi } from "vitest";
import { Store } from "../core/store.js";
import {
  SETUP_CHOICES,
  SETUP_SELECTOR_HINT,
  renderSetupSelector,
  setupA1R,
  setupSelectorTransition,
} from "./setup.js";

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
  options: {
    scenario?: string;
    installed?: boolean;
    initialBackend?: "codex" | "responses";
    seedState?: boolean;
    apiConfigured?: boolean;
    browserOpens?: boolean;
  } = {},
): Promise<{ output: string; rpc: string; backend: string | null; error: Error | null; statePreserved: boolean }> {
  const homeDir = mkdtempSync(join(tmpdir(), "a1r-cli-setup-"));
  roots.push(homeDir);
  const rpcLog = join(homeDir, "rpc.log");
  let seededSessionId: string | null = null;
  if (options.initialBackend || options.seedState) {
    const seed = new Store(homeDir, "a1r.sqlite", { recoverRuns: false });
    if (options.initialBackend) seed.setSetting("backend", options.initialBackend);
    if (options.seedState) {
      const session = seed.resolveSession({ scopeKey: "project:preserved", kind: "coding", cwd: homeDir, title: "Preserve me" });
      seededSessionId = session.id;
      seed.addMessage(session.id, "user", "Preserved transcript");
      seed.remember("project:preserved", "Preserved memory", session.id);
      seed.bindBackendSession(session.id, "codex", "preserved-thread");
      seed.linkGateway("telegram", "owner-1", session.id);
    }
    seed.close();
  }
  const previous = {
    home: process.env.A1R_HOME,
    command: process.env.A1R_CODEX_COMMAND,
    scenario: process.env.A1R_FAKE_SCENARIO,
    log: process.env.A1R_FAKE_LOG,
    path: process.env.PATH,
    openAIKey: process.env.OPENAI_API_KEY,
  };
  process.env.A1R_HOME = homeDir;
  process.env.A1R_CODEX_COMMAND = options.installed === false ? join(homeDir, "missing-codex") : executable(homeDir);
  process.env.A1R_FAKE_SCENARIO = options.scenario ?? "normal";
  process.env.A1R_FAKE_LOG = rpcLog;
  if (options.browserOpens) {
    const browserCommand = join(homeDir, process.platform === "darwin" ? "open" : "xdg-open");
    writeFileSync(browserCommand, "#!/bin/sh\nexit 0\n");
    chmodSync(browserCommand, 0o700);
    process.env.PATH = homeDir;
  } else {
    process.env.PATH = ""; // Prevent the test from opening a real browser.
  }
  if (options.apiConfigured) process.env.OPENAI_API_KEY = "sk-test-explicit-choice";
  else delete process.env.OPENAI_API_KEY;
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
    let statePreserved = seededSessionId === null;
    if (existsSync(join(homeDir, "a1r.sqlite"))) {
      const store = new Store(homeDir, "a1r.sqlite", { recoverRuns: false });
      backend = store.getSetting("backend");
      if (seededSessionId) {
        statePreserved = store.getSession(seededSessionId)?.title === "Preserve me"
          && store.getMessages(seededSessionId)[0]?.content === "Preserved transcript"
          && store.searchMemories("project:preserved", "Preserved memory")[0]?.content === "Preserved memory"
          && store.backendSession(seededSessionId, "codex") === "preserved-thread"
          && store.gatewaySession("telegram", "owner-1")?.id === seededSessionId;
      }
      store.close();
    }
    return {
      output: output.join("\n"),
      rpc: existsSync(rpcLog) ? readFileSync(rpcLog, "utf8") : "",
      backend,
      error,
      statePreserved,
    };
  } finally {
    if (previous.home === undefined) delete process.env.A1R_HOME; else process.env.A1R_HOME = previous.home;
    if (previous.command === undefined) delete process.env.A1R_CODEX_COMMAND; else process.env.A1R_CODEX_COMMAND = previous.command;
    if (previous.scenario === undefined) delete process.env.A1R_FAKE_SCENARIO; else process.env.A1R_FAKE_SCENARIO = previous.scenario;
    if (previous.log === undefined) delete process.env.A1R_FAKE_LOG; else process.env.A1R_FAKE_LOG = previous.log;
    if (previous.path === undefined) delete process.env.PATH; else process.env.PATH = previous.path;
    if (previous.openAIKey === undefined) delete process.env.OPENAI_API_KEY; else process.env.OPENAI_API_KEY = previous.openAIKey;
  }
}

describe.sequential("CLI subscription setup", () => {
  it("offers exactly browser, headless device, and API-key setup", () => {
    expect(SETUP_CHOICES.map((choice) => choice.id)).toEqual(["browser", "headless", "api"]);
    expect(SETUP_CHOICES.map((choice) => choice.label)).toEqual([
      "Set up with ChatGPT browser",
      "Set up headless or remote device (one-time code)",
      "Set up with OpenAI API key (independent usage-based billing)",
    ]);
    expect(renderSetupSelector(0)).toBe([
      "> 1. Set up with ChatGPT browser",
      "  2. Set up headless or remote device (one-time code)",
      "  3. Set up with OpenAI API key (independent usage-based billing)",
      "",
      SETUP_SELECTOR_HINT,
      "",
    ].join("\n"));
  });

  it("supports arrow navigation, number shortcuts, Enter, and cancellation", () => {
    expect(setupSelectorTransition(0, "\u001b[B")).toEqual({ selectedIndex: 1, action: "move" });
    expect(setupSelectorTransition(0, "\u001b[A")).toEqual({ selectedIndex: 2, action: "move" });
    expect(setupSelectorTransition(0, "3")).toEqual({ selectedIndex: 2, action: "confirm" });
    expect(setupSelectorTransition(0, "\r")).toEqual({ selectedIndex: 0, action: "confirm" });
    expect(setupSelectorTransition(0, "\u0003")).toEqual({ selectedIndex: 0, action: "cancel" });
  });

  it("reuses an existing A1R-specific login transparently during ordinary setup", async () => {
    const result = await runSetup(["--chatgpt"]);

    expect(result.error).toBeNull();
    expect(result.backend).toBe("codex");
    expect(result.output.split("\n").filter((line) => line.trim())).toEqual(["Connect A1R", "Connect Success"]);
    expect(result.rpc).not.toContain("account/login/start");
  });

  it("opens browser login without printing its URL or setup commentary", async () => {
    const result = await runSetup(["--chatgpt"], { scenario: "login-success", browserOpens: true });

    expect(result.error).toBeNull();
    expect(result.backend).toBe("codex");
    expect(result.output.split("\n").filter((line) => line.trim())).toEqual(["Connect A1R", "Connect Success"]);
    expect(result.output).not.toContain("https://auth.openai.com/fake");
    expect(result.rpc).toContain('"type":"chatgpt"');
    expect(result.rpc).not.toContain("chatgptDeviceCode");
    expect(result.rpc).not.toContain("useHostedLoginSuccessPage");
  });

  it("prints the browser URL only when it cannot open a browser", async () => {
    const result = await runSetup(["--chatgpt"], { scenario: "login-success" });

    expect(result.error).toBeNull();
    expect(result.output).toContain("Open: https://auth.openai.com/fake");
    expect(result.output).toContain("Connect Success");
  });

  it("displays the one-time code only for explicit headless setup", async () => {
    const result = await runSetup(["--headless"], { scenario: "login-success" });

    expect(result.error).toBeNull();
    expect(result.backend).toBe("codex");
    expect(result.output.split("\n").filter((line) => line.trim())).toEqual([
      "Connect A1R",
      "Open: https://auth.openai.com/codex/device",
      "Code: A1R-TEST",
      "Connect Success",
    ]);
    expect(result.rpc).toContain('"type":"chatgptDeviceCode"');
  });

  it("directs the old device-code flag to the headless option", async () => {
    const result = await runSetup(["--device-code"]);

    expect(result.error?.message).toMatch(/setup --headless/);
    expect(result.backend).toBeNull();
    expect(result.rpc).toBe("");
  });

  it("fails a cancelled or failed browser login without selecting API-key billing", async () => {
    const result = await runSetup(["--chatgpt"], { scenario: "login-failed" });

    expect(result.error?.message).toBe("ChatGPT sign-in failed");
    expect(result.backend).toBeNull();
    expect(result.output).not.toContain("Use API-key billing");
    expect(result.rpc).toContain("account/login/start");
  });

  it.each([
    ["login-expired", "The one-time code expired"],
    ["login-cancelled", "ChatGPT sign-in was cancelled"],
  ])("preserves the prior backend and all A1R state when headless login is %s", async (scenario, message) => {
    const result = await runSetup(["--headless"], {
      scenario,
      initialBackend: "responses",
      seedState: true,
    });

    expect(result.error?.message).toBe(message);
    expect(result.backend).toBe("responses");
    expect(result.statePreserved).toBe(true);
    expect(result.output).not.toContain("Use API-key billing");
  });

  it("selects API-key mode only when explicitly requested", async () => {
    const result = await runSetup(["--api-key"], { apiConfigured: true });

    expect(result.error).toBeNull();
    expect(result.backend).toBe("responses");
    expect(result.output.split("\n").filter((line) => line.trim())).toEqual(["Connect A1R", "Connect Success"]);
    expect(result.rpc).not.toContain("account/login/start");
  });

  it("fails clearly when Codex is missing without selecting another backend", async () => {
    const result = await runSetup(["--chatgpt"], { installed: false });

    expect(result.error?.message).toMatch(/Install the Codex CLI/);
    expect(result.backend).toBeNull();
    expect(result.output).not.toContain("Use API-key billing");
  });
});
