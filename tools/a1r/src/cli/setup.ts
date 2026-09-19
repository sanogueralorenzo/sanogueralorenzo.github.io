import { createInterface } from "node:readline/promises";
import OpenAI from "openai";
import { loadConfig } from "../core/config.js";
import { writeSecret } from "../core/credentials.js";

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

export async function setupOpenAI(): Promise<void> {
  const config = loadConfig();
  console.log("\nConnect A1R to OpenAI\n");
  console.log("Create an API key at https://platform.openai.com/api-keys, then paste it here.");
  const key = await readSecretLine("API key (hidden): ");
  if (!key.startsWith("sk-")) throw new Error("That does not look like an OpenAI API key.");
  process.stdout.write("Checking key… ");
  const client = new OpenAI({ apiKey: key });
  await client.models.list();
  const location = writeSecret("openai", key, config.homeDir);
  console.log(`connected. Saved in ${location === "keychain" ? "macOS Keychain" : "a private local file"}.`);
}
