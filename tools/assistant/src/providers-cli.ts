import { homedir } from "node:os";
import { join } from "node:path";
import { createInterface } from "node:readline/promises";
import { Writable } from "node:stream";
import type { AuthPrompt } from "@earendil-works/pi-ai";
import { assistantModels, Providers } from "./providers.ts";

export async function login(args: string[]) {
  const directory = join(homedir(), ".assistant");
  const providers = new Providers(directory, await assistantModels(directory));
  try {
    const catalog = (await providers.snapshot()).providers.filter(provider => provider.methods.length);
    if (!args.length || (args.length === 1 && args[0] === "--help")) {
      console.log("Usage: npm run login -- <provider> [oauth|api_key]\n");
      for (const provider of catalog) console.log(`${provider.id} — ${provider.name} (${provider.methods.map(method => method.id).join(", ")})`);
      return;
    }
    if (args.length > 2) throw new Error("Usage: npm run login -- <provider> [oauth|api_key]");
    const provider = catalog.find(provider => provider.id === args[0]);
    if (!provider) throw new Error("Unknown provider. Run npm run login to list providers.");
    const method = args[1] || provider.methods[0].id;
    if (!provider.methods.some(item => item.id === method)) throw new Error(`Supported methods: ${provider.methods.map(item => item.id).join(", ")}`);

    const controller = new AbortController();
    const cancel = () => controller.abort(new DOMException("Login cancelled", "AbortError"));
    const signal = AbortSignal.any([controller.signal, AbortSignal.timeout(10 * 60_000)]);
    let hidden = false;
    const output = new Writable({ write(chunk, _encoding, done) { if (!hidden) process.stdout.write(chunk); done(); } });
    const terminal = createInterface({ input: process.stdin, output, terminal: !!process.stdin.isTTY });
    terminal.on("SIGINT", cancel);
    terminal.on("close", cancel);
    process.once("SIGINT", cancel);
    process.once("SIGTERM", cancel);
    async function prompt(prompt: AuthPrompt): Promise<string> {
      const promptSignal = prompt.signal ? AbortSignal.any([signal, prompt.signal]) : signal;
      if (prompt.type === "select") {
        console.log(`\n${prompt.message}`);
        prompt.options.forEach((option, index) => console.log(`  ${index + 1}. ${option.label}`));
        while (true) {
          const value = await terminal.question("Choose a number: ", { signal: promptSignal });
          const option = prompt.options.find(option => option.id === value.trim()) || prompt.options[Number(value) - 1];
          if (option) return option.id;
          console.log("Choose one of the listed options.");
        }
      }
      const question = terminal.question(`${prompt.message}${prompt.placeholder ? ` (${prompt.placeholder})` : ""}: `, { signal: promptSignal });
      hidden = prompt.type === "secret";
      try { return (await question).trim(); }
      finally { if (hidden) process.stdout.write("\n"); hidden = false; }
    }
    try {
      console.log(`Connecting ${provider.name} using ${method}…`);
      await providers.connect(provider.id, method, {
        signal, prompt,
        notify(event) {
          if (event.type === "auth_url") console.log(`\n${event.instructions || "Open this link in your browser:"}\n${event.url}`);
          else if (event.type === "device_code") console.log(`\n${event.verificationUri}\nCode: ${event.userCode}`);
          else console.log(event.message);
        },
      });
      console.log(`Connected ${provider.name}. Saved to ${directory}. Restart Assistant if it is already running.`);
    } catch (error) { throw signal.aborted ? signal.reason : error; }
    finally {
      terminal.off("close", cancel);
      terminal.close();
      process.off("SIGINT", cancel);
      process.off("SIGTERM", cancel);
    }
  } finally { await providers.close(); }
}
