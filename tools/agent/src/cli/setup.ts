import { spawnSync } from "node:child_process";
import { createInterface } from "node:readline/promises";
import { createAgentCodexAppServer } from "../codex/app-server.js";
import { loadConfig } from "../local/config.js";
import { readSecret, writeSecret } from "../local/credentials.js";
import { OpenAIModelClient } from "../openai/model.js";
import { Store } from "../conversation/store.js";
import { BackendSetupService } from "../setup/service.js";

export async function readSecretLine(prompt: string): Promise<string> {
  if (!process.stdin.isTTY) {
    const rl = createInterface({ input: process.stdin, output: process.stdout });
    const value = await rl.question(prompt);
    rl.close();
    return value.trim();
  }

  process.stdout.write(prompt);
  process.stdin.setRawMode(true);
  process.stdin.resume();
  process.stdin.setEncoding("utf8");
  return new Promise((resolve, reject) => {
    let value = "";
    const finish = () => {
      process.stdin.off("data", onData);
      process.stdin.setRawMode(false);
      process.stdin.pause();
      process.stdout.write("\n");
      resolve(value.trim());
    };
    const onData = (chunk: string) => {
      if (chunk === "\r" || chunk === "\n") finish();
      else if (chunk === "\u0003") {
        process.stdin.setRawMode(false);
        reject(new Error("Setup cancelled."));
      } else if (chunk === "\u007f") {
        value = value.slice(0, -1);
      } else {
        value += chunk;
      }
    };
    process.stdin.on("data", onData);
  });
}

function openBrowser(url: string): boolean {
  const command = process.platform === "darwin" ? "open" : process.platform === "win32" ? "rundll32" : "xdg-open";
  const args = process.platform === "win32" ? ["url.dll,FileProtocolHandler", url] : [url];
  const result = spawnSync(command, args, { stdio: "ignore" });
  return !result.error && result.status === 0;
}

async function apiKeySetup(service: BackendSetupService, alreadyConfigured = false): Promise<void> {
  if (alreadyConfigured) await service.selectBackend("responses");
  else {
    const key = await readSecretLine("OpenAI API key: ");
    if (!key.startsWith("sk-")) throw new Error("That does not look like an OpenAI API key.");
    await service.setOpenAIKey(key);
  }
  console.log("Connect Success");
}

export const SETUP_CHOICES = [
  { id: "browser", label: "Set up with ChatGPT browser" },
  { id: "headless", label: "Set up headless or remote device (one-time code)" },
  { id: "api", label: "Set up with OpenAI API key (independent usage-based billing)" },
] as const;
export const SETUP_PROMPT = "Select 1–3 (Enter for 1): ";

type SetupChoice = typeof SETUP_CHOICES[number]["id"];

async function chooseDefault(): Promise<SetupChoice> {
  if (!process.stdin.isTTY) return "browser";
  const rl = createInterface({ input: process.stdin, output: process.stdout });
  SETUP_CHOICES.forEach((choice, index) => console.log(`${index + 1}. ${choice.label}`));
  const answer = (await rl.question(SETUP_PROMPT)).trim();
  rl.close();
  const choice = SETUP_CHOICES[Number(answer || "1") - 1]?.id;
  if (!choice) throw new Error("Choose 1, 2, or 3.");
  return choice;
}

function createSetupContext() {
  const config = loadConfig();
  const store = new Store(config.homeDir, "agent.sqlite", { recoverRuns: false });
  const model = new OpenAIModelClient(readSecret("openai", config.homeDir));
  const codex = createAgentCodexAppServer(config);
  const service = new BackendSetupService(
    store,
    model,
    codex,
    (key) => { writeSecret("openai", key, config.homeDir); },
  );
  return { store, codex, service };
}

export async function setupAgent(args: string[] = [], skipIfConfigured = false): Promise<void> {
  const flags = { "--chatgpt": "browser", "--headless": "headless", "--api-key": "api" } as const;
  const unknown = args.find((arg) => !(arg in flags));
  if (unknown) throw new Error(`Unknown setup option: ${unknown}`);
  const requested = args.map((arg) => flags[arg as keyof typeof flags]);
  if (new Set(requested).size > 1) {
    throw new Error("Choose exactly one setup method: browser, headless device, or API key.");
  }

  const { store, codex, service } = createSetupContext();

  try {
    const before = await service.status();
    if (skipIfConfigured && requested.length === 0 && before.configured) return;
    console.log("\nConnect Agent\n");

    const choice: SetupChoice = requested[0] ?? await chooseDefault();
    if (choice === "api") {
      await apiKeySetup(service, before.openAIConfigured);
      return;
    }
    if (!before.codex.installed) {
      throw new Error("Install the Codex CLI and retry, or run `agent setup --api-key`.");
    }
    if (before.codex.connected) {
      await service.selectBackend("codex");
      console.log("Connect Success");
      return;
    }

    const login = await service.startCodexLogin(choice);
    if (choice === "browser" && login.type === "chatgpt") {
      if (!openBrowser(login.authUrl)) console.log(`Open: ${login.authUrl}`);
    } else if (choice === "headless" && login.type === "chatgptDeviceCode") {
      console.log(`Open: ${login.verificationUrl}`);
      console.log(`Code: ${login.userCode}`);
    } else {
      throw new Error(`Codex app-server returned the wrong login flow for ${choice} setup.`);
    }
    const controller = new AbortController();
    const cancel = () => controller.abort();
    process.once("SIGINT", cancel);
    const result = await service.waitForCodexLogin(login.loginId, controller.signal)
      .finally(() => process.off("SIGINT", cancel));
    if (result.state !== "complete") {
      const retry = choice === "headless" ? "agent setup --headless" : "agent setup --chatgpt";
      throw new Error(result.error ?? `ChatGPT ${choice} login was not completed. Run \`${retry}\` to try again.`);
    }
    console.log("Connect Success");
  } finally {
    await codex.stop();
    store.close();
  }
}
