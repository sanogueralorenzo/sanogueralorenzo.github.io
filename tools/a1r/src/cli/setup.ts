import { spawnSync } from "node:child_process";
import { createInterface } from "node:readline/promises";
import { createA1RCodexAppServer } from "../codex/app-server.js";
import { loadConfig } from "../core/config.js";
import { readSecret, writeSecret } from "../core/credentials.js";
import { OpenAIModelClient } from "../core/model.js";
import { Store } from "../core/store.js";
import { BackendSetupService, type SetupStatus } from "../setup/service.js";

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

function showUsage(status: SetupStatus): void {
  if (status.codex.planType) console.log(`Plan: ${status.codex.planType}`);
  for (const usage of status.codex.usage) {
    const reset = usage.resetsAt ? ` · resets ${new Date(usage.resetsAt * 1_000).toLocaleString()}` : "";
    console.log(`${usage.name}: ${Math.round(usage.remainingPercent)}% available${reset}`);
  }
  if (status.codex.allowanceAvailable === false) console.log("Included Codex allowance is currently exhausted.");
}

function openBrowser(url: string): boolean {
  const command = process.platform === "darwin" ? "open" : process.platform === "win32" ? "rundll32" : "xdg-open";
  const args = process.platform === "win32" ? ["url.dll,FileProtocolHandler", url] : [url];
  try {
    const result = spawnSync(command, args, { stdio: "ignore" });
    return !result.error && result.status === 0;
  } catch {
    return false;
  }
}

async function apiKeySetup(service: BackendSetupService, homeDir: string, alreadyConfigured = false): Promise<void> {
  console.log("\nUse API-key billing\n");
  if (alreadyConfigured) {
    await service.selectBackend("responses");
    console.log("Selected the saved OpenAI API key. A1R will use usage-based API billing.");
    return;
  }
  console.log("Create an API key at https://platform.openai.com/api-keys, then paste it here.");
  const key = await readSecretLine("API key (hidden): ");
  if (!key.startsWith("sk-")) throw new Error("That does not look like an OpenAI API key.");
  process.stdout.write("Checking key… ");
  await service.setOpenAIKey(key);
  console.log(`connected. API-key mode selected; saved in macOS Keychain or a private file under ${homeDir}.`);
}

export const SETUP_CHOICES = [
  { id: "browser", label: "Continue with ChatGPT in a browser (recommended — uses included Codex allowance)" },
  { id: "headless", label: "Set up a headless or remote device (one-time code)" },
  { id: "api", label: "Use an OpenAI API key (independent usage-based billing)" },
] as const;

type SetupChoice = typeof SETUP_CHOICES[number]["id"];

async function chooseDefault(): Promise<SetupChoice> {
  if (!process.stdin.isTTY) return "browser";
  const rl = createInterface({ input: process.stdin, output: process.stdout });
  SETUP_CHOICES.forEach((choice, index) => console.log(`${index + 1}. ${choice.label}`));
  const answer = (await rl.question("Choice [1]: ")).trim();
  rl.close();
  return answer === "2" ? "headless" : answer === "3" ? "api" : "browser";
}

export async function setupA1R(args: string[] = []): Promise<void> {
  const unknown = args.filter((arg) => arg !== "--chatgpt" && arg !== "--headless" && arg !== "--api-key");
  if (unknown.includes("--device-code")) {
    throw new Error("Use `a1r setup --headless` for device-code login.");
  }
  if (unknown.length > 0) throw new Error(`Unknown setup option: ${unknown[0]}`);
  const forcedChoices = [args.includes("--chatgpt"), args.includes("--headless"), args.includes("--api-key")]
    .filter(Boolean).length;
  if (forcedChoices > 1) {
    throw new Error("Choose exactly one setup method: browser, headless device, or API key.");
  }

  const config = loadConfig();
  const store = new Store(config.homeDir, "a1r.sqlite", { recoverRuns: false });
  const model = new OpenAIModelClient(config, readSecret("openai", config.homeDir));
  const codex = createA1RCodexAppServer(config);
  const service = new BackendSetupService(
    store,
    model,
    codex,
    (key) => { writeSecret("openai", key, config.homeDir); },
  );

  try {
    console.log("\nConnect A1R\n");
    const before = await service.status();
    if (before.codex.connected) {
      console.log("An A1R-specific ChatGPT login is available in A1R's private Codex profile.");
      showUsage(before);
    } else if (!before.codex.installed) {
      console.log("The official Codex CLI is not installed, so ChatGPT subscription mode is unavailable.");
    }

    const choice: SetupChoice = args.includes("--api-key")
      ? "api"
      : args.includes("--headless") ? "headless" : args.includes("--chatgpt") ? "browser" : await chooseDefault();
    if (choice === "api") {
      await apiKeySetup(service, config.homeDir, before.openAIConfigured);
      return;
    }
    if (!before.codex.installed) {
      throw new Error("ChatGPT setup requires the official Codex CLI. Install it, then choose browser or headless setup again. To explicitly use API billing instead, run `a1r setup --api-key`.");
    }
    if (before.codex.connected) {
      if (before.codex.allowanceAvailable === false) {
        throw new Error("Included Codex usage is unavailable right now. Try again after it resets, or explicitly run `a1r setup --api-key` to choose API billing.");
      }
      await service.selectBackend("codex");
      console.log("A1R will reuse its private ChatGPT login. No global Codex login or API billing key is used.");
      return;
    }

    const login = await service.startCodexLogin(choice);
    if (choice === "browser" && login.type === "chatgpt") {
      console.log(`\nOpen this official ChatGPT sign-in page:\n${login.authUrl}`);
      if (openBrowser(login.authUrl)) console.log("Your browser has been opened. Finish sign-in there; A1R will show a local confirmation page when complete.");
    } else if (choice === "headless" && login.type === "chatgptDeviceCode") {
      console.log(`\nOn any device, open this official ChatGPT page:\n${login.verificationUrl}`);
      console.log(`Enter this one-time code: ${login.userCode}`);
      console.log("The login will be stored only in this device's private A1R profile.");
    } else {
      throw new Error(`Codex app-server returned the wrong login flow for ${choice} setup.`);
    }
    process.stdout.write("Waiting for ChatGPT… ");
    const controller = new AbortController();
    const cancel = () => controller.abort();
    process.once("SIGINT", cancel);
    const result = await codex.waitForLogin(login.loginId, 5 * 60_000, controller.signal)
      .finally(() => process.off("SIGINT", cancel));
    if (result.state !== "complete") {
      console.log("not connected.");
      const retry = choice === "headless" ? "a1r setup --headless" : "a1r setup --chatgpt";
      throw new Error(result.error ?? `ChatGPT ${choice} login was not completed. Run \`${retry}\` to try again.`);
    }
    await service.codexLoginStatus(login.loginId);
    console.log("connected.");
    const after = await service.status();
    showUsage(after);
    console.log("A1R will continue with ChatGPT using its private Codex profile. Authentication and subscription accounting stay inside Codex app-server.");
  } finally {
    await codex.stop();
    store.close();
  }
}
