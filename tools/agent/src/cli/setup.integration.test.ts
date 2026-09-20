import { chmodSync, existsSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { afterEach, describe, expect, it, vi } from "vitest";
import { Store } from "../conversation/store.js";
import { temporary } from "../test-support.js";
import { SETUP_CHOICES, SETUP_PROMPT, setupAgent } from "./setup.js";

const fixture = join(dirname(fileURLToPath(import.meta.url)), "..", "codex", "test-fixtures", "fake-app-server.mjs");

afterEach(() => {
  vi.restoreAllMocks();
  vi.unstubAllEnvs();
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
) {
  const homeDir = temporary("agent-cli-setup-");
  const rpcLog = join(homeDir, "rpc.log");
  let seededSessionId: string | null = null;
  if (options.initialBackend || options.seedState) {
    const seed = new Store(homeDir, "agent.sqlite", { recoverRuns: false });
    if (options.initialBackend) seed.setSetting("backend", options.initialBackend);
    if (options.seedState) {
      const session = seed.resolveSession({ scopeKey: "project:preserved", kind: "coding", cwd: homeDir, title: "Preserve me" });
      seededSessionId = session.id;
      seed.addMessage(session.id, "user", "Preserved transcript");
      seed.remember("project:preserved", "Preserved memory");
      seed.bindBackendSession(session.id, "codex", "preserved-thread");
    }
    seed.close();
  }
  vi.stubEnv("AGENT_HOME", homeDir);
  vi.stubEnv("AGENT_CODEX_COMMAND", options.installed === false ? join(homeDir, "missing-codex") : executable(homeDir));
  vi.stubEnv("AGENT_FAKE_SCENARIO", options.scenario ?? "normal");
  vi.stubEnv("AGENT_FAKE_LOG", rpcLog);
  if (options.browserOpens) {
    const browserCommand = join(homeDir, process.platform === "darwin" ? "open" : "xdg-open");
    writeFileSync(browserCommand, "#!/bin/sh\nexit 0\n");
    chmodSync(browserCommand, 0o700);
    vi.stubEnv("PATH", homeDir);
  } else {
    vi.stubEnv("PATH", ""); // Prevent the test from opening a real browser.
  }
  vi.stubEnv("OPENAI_API_KEY", options.apiConfigured ? "sk-test-explicit-choice" : "");
  const output: string[] = [];
  vi.spyOn(console, "log").mockImplementation((...values) => output.push(values.join(" ")));
  vi.spyOn(process.stdout, "write").mockImplementation((value) => {
    output.push(String(value));
    return true;
  });
  let error: Error | null = null;
  try {
    await setupAgent(args);
  } catch (cause) {
    error = cause instanceof Error ? cause : new Error(String(cause));
  }
  const setupRpc = existsSync(rpcLog) ? readFileSync(rpcLog, "utf8") : "";
  let backend: string | null = null;
  let statePreserved = seededSessionId === null;
  if (existsSync(join(homeDir, "agent.sqlite"))) {
    const store = new Store(homeDir, "agent.sqlite", { recoverRuns: false });
    backend = store.getSetting("backend");
    if (seededSessionId) {
      statePreserved = store.getSession(seededSessionId)?.title === "Preserve me"
        && store.getMessages(seededSessionId)[0]?.content === "Preserved transcript"
        && store.searchMemories("project:preserved", "Preserved memory")[0]?.content === "Preserved memory"
        && store.backendSession(seededSessionId, "codex") === "preserved-thread";
    }
    store.close();
  }
  return { output: output.join("\n"), rpc: setupRpc, backend, error, statePreserved };
}

describe.sequential("CLI subscription setup", () => {
  it("offers exactly browser, headless device, and API-key setup", () => {
    expect(SETUP_CHOICES.map((choice) => choice.id)).toEqual(["browser", "headless", "api"]);
    expect(SETUP_CHOICES.map((choice) => choice.label)).toEqual([
      "Set up with ChatGPT browser",
      "Set up headless or remote device (one-time code)",
      "Set up with OpenAI API key (independent usage-based billing)",
    ]);
    expect(SETUP_PROMPT).toBe("Select 1–3 (Enter for 1): ");
  });

  it.each([
    ["saved ChatGPT login", ["--chatgpt"], {}, "codex", ["Connect Agent", "Connect Success"], [], ["account/login/start"]],
    ["browser", ["--chatgpt"], { scenario: "login-success", browserOpens: true }, "codex", ["Connect Agent", "Connect Success"], ['"type":"chatgpt"'], ["https://auth.openai.com/fake", "chatgptDeviceCode", "useHostedLoginSuccessPage"]],
    ["browser without opener", ["--chatgpt"], { scenario: "login-success" }, "codex", ["Connect Agent", "Open: https://auth.openai.com/fake", "Connect Success"], [], []],
    ["headless", ["--headless"], { scenario: "login-success" }, "codex", ["Connect Agent", "Open: https://auth.openai.com/codex/device", "Code: Agent-TEST", "Connect Success"], ['"type":"chatgptDeviceCode"'], []],
    ["API key", ["--api-key"], { apiConfigured: true }, "responses", ["Connect Agent", "Connect Success"], [], ["account/login/start"]],
  ] as const)("connects with %s", async (_name, args, options, backend, lines, includes, excludes) => {
    const result = await runSetup([...args], options);
    expect(result.error).toBeNull();
    expect(result.backend).toBe(backend);
    expect(result.output.split("\n").filter((line) => line.trim())).toEqual(lines);
    for (const text of includes) expect(result.rpc).toContain(text);
    for (const text of excludes) expect(`${result.output}\n${result.rpc}`).not.toContain(text);
  });

  it("rejects removed setup options", async () => {
    const result = await runSetup(["--device-code"]);

    expect(result.error?.message).toBe("Unknown setup option: --device-code");
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
  ])("preserves the prior backend and all Agent state when headless login is %s", async (scenario, message) => {
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

  it("fails clearly when Codex is missing without selecting another backend", async () => {
    const result = await runSetup(["--chatgpt"], { installed: false });

    expect(result.error?.message).toMatch(/Install the Codex CLI/);
    expect(result.backend).toBeNull();
    expect(result.output).not.toContain("Use API-key billing");
  });
});
