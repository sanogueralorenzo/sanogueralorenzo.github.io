import { chmodSync, existsSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it, vi } from "vitest";
import { Store } from "../conversation/store.js";
import { temporary } from "../test-support.js";
import { SETUP_CHOICES, SETUP_PROMPT, setupAgent } from "./setup.js";

const fixture = join(dirname(fileURLToPath(import.meta.url)), "..", "codex", "test-fixtures", "fake-app-server.mjs");

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
    seedState?: boolean;
    browserOpens?: boolean;
  } = {},
  skipIfConfigured = false,
) {
  const homeDir = temporary("agent-cli-setup-");
  const rpcLog = join(homeDir, "rpc.log");
  let seededSessionId: string | null = null;
  if (options.seedState) {
    const seed = new Store(homeDir);
    const session = seed.createSession({ cwd: homeDir, title: "Preserve me" });
    seededSessionId = session.id;
    seed.addMessage(session.id, "user", "Preserved transcript");
    seed.remember("project:preserved", "Preserved memory");
    seed.bindCodexThread(session.id, "preserved-thread");
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
  const output: string[] = [];
  vi.spyOn(console, "log").mockImplementation((...values) => output.push(values.join(" ")));
  vi.spyOn(process.stdout, "write").mockImplementation((value) => {
    output.push(String(value));
    return true;
  });
  let error: Error | null = null;
  try {
    await setupAgent(args, skipIfConfigured);
  } catch (cause) {
    error = cause instanceof Error ? cause : new Error(String(cause));
  }
  const setupRpc = existsSync(rpcLog) ? readFileSync(rpcLog, "utf8") : "";
  let statePreserved = seededSessionId === null;
  if (existsSync(join(homeDir, "agent.sqlite"))) {
    const store = new Store(homeDir);
    if (seededSessionId) {
      statePreserved = store.getSession(seededSessionId)?.title === "Preserve me"
        && store.getMessages(seededSessionId)[0]?.content === "Preserved transcript"
        && store.searchMemories("project:preserved", "Preserved memory")[0] === "Preserved memory"
        && store.codexThread(seededSessionId) === "preserved-thread";
    }
    store.close();
  }
  return { output: output.join("\n"), rpc: setupRpc, error, statePreserved, databaseExists: existsSync(join(homeDir, "agent.sqlite")) };
}

describe.sequential("CLI setup", () => {
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
    ["saved ChatGPT login", ["--chatgpt"], {}, ["Connect Agent", "Connect Success"], [], ["account/login/start"]],
    ["browser", ["--chatgpt"], { scenario: "login-success", browserOpens: true }, ["Connect Agent", "Connect Success"], ['"type":"chatgpt"'], ["https://auth.openai.com/fake", "chatgptDeviceCode", "useHostedLoginSuccessPage"]],
    ["browser without opener", ["--chatgpt"], { scenario: "login-success" }, ["Connect Agent", "Open: https://auth.openai.com/fake", "Connect Success"], [], []],
    ["headless", ["--headless"], { scenario: "login-success" }, ["Connect Agent", "Open: https://auth.openai.com/codex/device", "Code: Agent-TEST", "Connect Success"], ['"type":"chatgptDeviceCode"'], []],
  ] as const)("connects with %s", async (_name, args, options, lines, includes, excludes) => {
    const result = await runSetup([...args], options);
    expect(result.error).toBeNull();
    expect(result.databaseExists).toBe(false);
    expect(result.output.split("\n").filter((line) => line.trim())).toEqual(lines);
    for (const text of includes) expect(result.rpc).toContain(text);
    for (const text of excludes) expect(`${result.output}\n${result.rpc}`).not.toContain(text);
  });

  it("stays silent when a client reuses an already configured connection", async () => {
    const result = await runSetup([], {}, true);
    expect(result.error).toBeNull();
    expect(result.output).toBe("");
  });

  it("fails a cancelled or failed browser login without selecting another auth mode", async () => {
    const result = await runSetup(["--chatgpt"], { scenario: "login-failed" });
    expect(result.error?.message).toBe("ChatGPT sign-in failed");
    expect(result.output).not.toContain("Use API-key billing");
    expect(result.rpc).toContain("account/login/start");
  });

  it.each([
    ["login-expired", "The one-time code expired"],
    ["login-cancelled", "ChatGPT sign-in was cancelled"],
  ])("preserves all Agent state when headless login is %s", async (scenario, message) => {
    const result = await runSetup(["--headless"], {
      scenario,
      seedState: true,
    });
    expect(result.error?.message).toBe(message);
    expect(result.statePreserved).toBe(true);
    expect(result.output).not.toContain("Use API-key billing");
  });

  it("fails clearly when Codex is missing without selecting another backend", async () => {
    const result = await runSetup(["--chatgpt"], { installed: false });
    expect(result.error?.message).toMatch(/Install the Codex CLI/);
    expect(result.output).not.toContain("Use API-key billing");
  });
});
