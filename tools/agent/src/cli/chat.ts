import { createInterface } from "node:readline/promises";
import { RuntimeClient, RuntimeProtocolError } from "../client/client.js";
import type { RunEnvelope, RuntimeSnapshot } from "../conversation/types.js";
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
  let activeOutput = "";
  let activeArtifacts = new Set<string>();
  let wroteText = false;
  let stopping = false;
  let fatalError: Error | undefined;
  let hasConnected = false;
  let latestSnapshot: RuntimeSnapshot | undefined;
  const observerController = new AbortController();
  const completed = new Set<string>();
  const waiters = new Map<string, () => void>();
  let connected!: () => void;
  let failConnection!: (error: Error) => void;
  const firstConnection = new Promise<void>((resolve, reject) => { connected = resolve; failConnection = reject; });

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
  const restore = (snapshot: RuntimeSnapshot) => {
    latestSnapshot = snapshot;
    if (!fresh && snapshot.transcript) sessionId = snapshot.transcript.session.id;
    const active = snapshot.activeRun;
    if (!active) {
      if (activeRunId) {
        const saved = snapshot.lastRun?.id === activeRunId
          ? snapshot.transcript?.messages.at(-1)
          : null;
        if (saved?.role === "assistant" && saved.content.startsWith(activeOutput)) {
          process.stdout.write(saved.content.slice(activeOutput.length));
          if (saved.content.length > activeOutput.length) process.stdout.write("\n");
        } else status("Response ended while reconnecting. You can try again.");
        finish(activeRunId);
        activeRunId = undefined;
        activeOutput = "";
        activeArtifacts = new Set();
        wroteText = false;
      }
      return;
    }
    if (activeRunId && activeRunId !== active.run.id) finish(activeRunId);
    if (activeRunId !== active.run.id) render({ runId: active.run.id, event: active.turn });
    if (active.navigation && sessionId !== active.navigation.session.id) status(`Resumed “${active.navigation.session.title}”.`);
    if (active.session) sessionId = active.session.id;
    const missing = active.output.startsWith(activeOutput) ? active.output.slice(activeOutput.length) : `\n${active.output}`;
    if (missing) process.stdout.write(missing);
    activeOutput = active.output;
    wroteText = Boolean(active.output);
    for (const artifact of active.artifacts) {
      if (activeArtifacts.has(artifact.id)) continue;
      process.stdout.write(`${wroteText ? "\n" : ""}${ansi.dim(`· ${artifact.name}`)} ${artifact.path}\n`);
      activeArtifacts.add(artifact.id);
      wroteText = false;
    }
  };
  const render = ({ runId, event }: RunEnvelope) => {
    if (event.type === "snapshot") {
      restore(event.snapshot);
      return;
    }
    if (event.type === "turn") {
      activeRunId = runId;
      activeOutput = "";
      activeArtifacts = new Set();
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
    } else if (event.type === "navigate") {
      sessionId = event.session.id;
      fresh = false;
      status(`Resumed “${event.session.title}”.`);
    } else if (event.type === "text_delta") {
      process.stdout.write(event.delta);
      activeOutput += event.delta;
      wroteText = true;
    } else if (event.type === "tool_start") {
      process.stdout.write(`${wroteText ? "\n" : ""}${ansi.dim(`· ${event.name}`)}\n`);
      wroteText = false;
    } else if (event.type === "status") {
      process.stdout.write(`${wroteText ? "\n" : ""}${ansi.dim(`· ${event.message}`)}\n`);
      wroteText = false;
    } else if (event.type === "artifact") {
      process.stdout.write(`${wroteText ? "\n" : ""}${ansi.dim(`· ${event.artifact.name}`)} ${event.artifact.path}\n`);
      activeArtifacts.add(event.artifact.id);
      wroteText = false;
    } else if (event.type === "error") {
      process.stdout.write(`${wroteText ? "\n" : ""}${ansi.red(event.message)}\n`);
      wroteText = false;
      activeRunId = undefined;
      activeOutput = "";
      activeArtifacts = new Set();
      finish(runId);
    } else if (event.type === "done") {
      if (wroteText) process.stdout.write("\n");
      wroteText = false;
      activeRunId = undefined;
      activeOutput = "";
      activeArtifacts = new Set();
      finish(runId);
    }
  };

  const observe = async () => {
    while (!stopping) {
      try {
        const events = await client.events(observerController.signal);
        for await (const event of events) {
          render(event);
          if (event.event.type === "snapshot") {
            hasConnected = true;
            connected();
          }
        }
      } catch (error) {
        if (stopping) return;
        if (error instanceof RuntimeProtocolError) {
          if (hasConnected) {
            fatalError = error;
            stopping = true;
            for (const resolve of waiters.values()) resolve();
            waiters.clear();
            rl.close();
          } else failConnection(error);
          return;
        }
        status("Reconnecting…");
        await client.waitUntilHealthy().catch(() => undefined);
      }
    }
  };
  const observer = observe();

  const onSigint = () => {
    if (activeRunId) {
      void client.stop();
    } else {
      rl.close();
    }
  };
  process.on("SIGINT", onSigint);

  try {
    await firstConnection;
    while (true) {
      promptActive = true;
      let input: string;
      try { input = (await rl.question(ansi.cyan("› "))).trim(); }
      catch (error) { throw fatalError ?? error; }
      if (fatalError) throw fatalError;
      promptActive = false;
      if (!input) continue;
      if (input === "/quit") break;
      if (input === "/help") {
        console.log("Talk normally. Ctrl-C stops the current response.");
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
        if (!completed.has(run.id)) {
          const alreadyObserving = activeRunId === run.id;
          activeRunId = run.id;
          if (!alreadyObserving && (latestSnapshot?.activeRun?.run.id === run.id || latestSnapshot?.lastRun?.id === run.id)) {
            restore(latestSnapshot);
          }
        }
        await waitFor(run.id);
        if (fatalError) throw fatalError;
        if (activeRunId === run.id) activeRunId = undefined;
      } catch (error) {
        if (fatalError) throw fatalError;
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
