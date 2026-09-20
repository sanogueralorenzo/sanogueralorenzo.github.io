import { randomUUID } from "node:crypto";
import { createInterface } from "node:readline/promises";
import { RuntimeClient } from "../client/client.js";
import { loadConfig } from "../core/config.js";
import type { RuntimeEvent } from "../core/types.js";
import { RuntimeSupervisor } from "./supervisor.js";

const ansi = {
  dim: (text: string) => process.stdout.isTTY ? `\u001b[2m${text}\u001b[22m` : text,
  cyan: (text: string) => process.stdout.isTTY ? `\u001b[36m${text}\u001b[39m` : text,
  red: (text: string) => process.stdout.isTTY ? `\u001b[31m${text}\u001b[39m` : text,
};

export async function runChat(options: { dev: boolean }): Promise<void> {
  const config = loadConfig();
  const client = new RuntimeClient(config.homeDir);
  let promptActive = false;
  const status = (message: string) => {
    process.stdout.write(`${promptActive ? "\n" : ""}${ansi.dim(`· ${message}`)}\n`);
  };
  const supervisor = new RuntimeSupervisor(client, options.dev, status);
  await supervisor.start();

  console.log(`${ansi.cyan("Agent")} ${ansi.dim("— quiet help for ongoing work")}`);
  if (options.dev) console.log(ansi.dim("Hot reload is on. Runtime state survives code changes."));
  console.log(ansi.dim("/new  /status  /help  /quit\n"));

  const rl = createInterface({ input: process.stdin, output: process.stdout });
  let sessionId: string | undefined;
  let fresh = false;
  let activeRequestId: string | null = null;
  let interrupted = false;

  const onSigint = () => {
    if (activeRequestId) {
      interrupted = true;
      void client.cancel(activeRequestId);
    } else {
      rl.close();
    }
  };
  process.on("SIGINT", onSigint);

  try {
    while (true) {
      promptActive = true;
      const input = (await rl.question(ansi.cyan("› "))).trim();
      promptActive = false;
      if (!input) continue;
      if (input === "/quit") break;
      if (input === "/help") {
        console.log("Talk normally. Agent chooses context, model, memory, and tools automatically. Ctrl-C stops the current response.");
        continue;
      }
      if (input === "/new") {
        sessionId = undefined;
        fresh = true;
        status("New conversation ready.");
        continue;
      }
      if (input === "/status") {
        const [data, setup] = await Promise.all([
          client.sessions(),
          client.setupStatus(),
        ]);
        const current = data.sessions.find((session) => session.id === sessionId);
        const billing = setup.selectedBackend === "codex"
          ? `ChatGPT${setup.codex.planType ? ` ${setup.codex.planType}` : ""}`
          : "API-key billing";
        status(current
          ? `${current.title} · ${billing} · saved ${new Date(current.updatedAt).toLocaleTimeString()}`
          : `Runtime connected · ${billing}. Session will be selected automatically.`);
        continue;
      }
      if (input.startsWith("/")) {
        console.log(ansi.red("Unknown command. Try /help."));
        continue;
      }

      activeRequestId = randomUUID();
      interrupted = false;
      let wroteText = false;
      try {
        await client.chat({
          text: input,
          cwd: process.cwd(),
          ...(sessionId ? { sessionId } : {}),
          ...(fresh ? { fresh: true } : {}),
          channel: "cli",
        }, (event: RuntimeEvent) => {
          if (event.type === "session") {
            sessionId = event.session.id;
            fresh = false;
          } else if (event.type === "text_delta") {
            process.stdout.write(event.delta);
            wroteText = true;
          } else if (event.type === "tool_start") {
            process.stdout.write(`${wroteText ? "\n" : ""}${ansi.dim(`· ${event.name}`)}\n`);
            wroteText = false;
          } else if (event.type === "status") {
            process.stdout.write(`${wroteText ? "\n" : ""}${ansi.dim(`· ${event.message}`)}\n`);
            wroteText = false;
          } else if (event.type === "artifact") {
            process.stdout.write(`${wroteText ? "\n" : ""}${ansi.dim(`· ${event.artifact.name}`)} ${event.artifact.path}\n`);
            wroteText = false;
          } else if (event.type === "error") {
            process.stdout.write(`${wroteText ? "\n" : ""}${ansi.red(event.message)}\n`);
            wroteText = false;
          }
        }, activeRequestId);
        if (wroteText) process.stdout.write("\n");
      } catch (error) {
        console.log(ansi.red(error instanceof Error ? error.message : String(error)));
        if (!interrupted) status("The runtime connection changed. Your saved session will resume on the next message.");
        await client.waitUntilHealthy().catch(() => undefined);
      } finally {
        activeRequestId = null;
      }
    }
  } finally {
    process.off("SIGINT", onSigint);
    rl.close();
    await supervisor.stop();
  }
}
