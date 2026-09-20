import { createInterface } from "node:readline/promises";
import { RuntimeClient } from "../client/client.js";
import type { RunEnvelope } from "../conversation/types.js";
import { loadConfig } from "../local/config.js";
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
  let activeRunId: string | undefined;
  let wroteText = false;
  let stopping = false;
  const observerController = new AbortController();
  const completed = new Set<string>();
  const waiters = new Map<string, () => void>();
  let connected!: () => void;
  const firstConnection = new Promise<void>((resolve) => { connected = resolve; });

  const finish = (runId: string) => {
    const waiter = waiters.get(runId);
    if (waiter) {
      waiters.delete(runId);
      waiter();
    } else {
      completed.add(runId);
    }
  };
  const waitFor = (runId: string) => {
    if (completed.delete(runId)) return Promise.resolve();
    return new Promise<void>((resolve) => waiters.set(runId, resolve));
  };
  const render = ({ runId, event }: RunEnvelope) => {
    if (event.type === "turn") {
      activeRunId = runId;
      wroteText = false;
      if (event.channel !== "cli") {
        const input = event.text.trim() || (event.hasAttachments ? "Voice message" : "Message");
        process.stdout.write(`${promptActive ? "\n" : ""}${ansi.cyan(event.channel)} › ${input}\n`);
      }
    } else if (activeRunId !== runId) {
      return;
    } else if (event.type === "session") {
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
      activeRunId = undefined;
      finish(runId);
    } else if (event.type === "done") {
      if (wroteText) process.stdout.write("\n");
      wroteText = false;
      activeRunId = undefined;
      finish(runId);
    }
  };

  const observe = async () => {
    while (!stopping) {
      try {
        const events = await client.events(observerController.signal);
        connected();
        for await (const event of events) render(event);
      } catch {
        if (stopping) return;
        if (activeRunId) {
          status("The runtime restarted. Your saved session was restored.");
          finish(activeRunId);
          activeRunId = undefined;
        }
        await client.waitUntilHealthy().catch(() => undefined);
      }
    }
  };
  const observer = observe();
  await firstConnection;

  const onSigint = () => {
    if (activeRunId) {
      void client.stop();
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
        console.log("Talk normally. Agent keeps context, memory, and tools with the conversation. Ctrl-C stops the current response.");
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
        const billing = setup.authMode === "chatgpt" ? "ChatGPT" : "API-key billing";
        status(current
          ? `${current.title} · ${billing} · saved ${new Date(current.updatedAt).toLocaleTimeString()}`
          : `Runtime connected · ${billing}. Session will be selected automatically.`);
        continue;
      }
      if (input.startsWith("/")) {
        console.log(ansi.red("Unknown command. Try /help."));
        continue;
      }

      try {
        const run = await client.submit({
          text: input,
          cwd: process.cwd(),
          ...(sessionId ? { sessionId } : {}),
          ...(fresh ? { fresh: true } : {}),
          channel: "cli",
        });
        if (!run) {
          status("Agent is already working. Ctrl-C stops the active response.");
          continue;
        }
        activeRunId = run.id;
        await waitFor(run.id);
      } catch (error) {
        console.log(ansi.red(error instanceof Error ? error.message : String(error)));
        status("The runtime connection changed. Your saved session will resume on the next message.");
      }
    }
  } finally {
    stopping = true;
    observerController.abort();
    await observer;
    process.off("SIGINT", onSigint);
    rl.close();
    await supervisor.stop();
  }
}
