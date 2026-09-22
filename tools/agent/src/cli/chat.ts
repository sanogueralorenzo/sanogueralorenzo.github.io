import { basename } from "node:path";
import { createInterface } from "node:readline/promises";
import { RuntimeClient, RuntimeProtocolError } from "../client/client.js";
import { loadConfig } from "../local/config.js";
import { RuntimeSupervisor } from "../client/supervisor.js";
import { ansi, CliOutput } from "./output.js";

export async function runChat(options: { dev: boolean }): Promise<void> {
  const config = loadConfig();
  const client = new RuntimeClient(config.homeDir);
  let promptActive = false;
  const status = (message: string) => {
    process.stdout.write(`${promptActive ? "\n" : ""}${ansi.dim(`· ${message}`)}\n`);
  };
  const supervisor = new RuntimeSupervisor(client, options.dev, status);
  await supervisor.start();
  const selected = await client.openSession({ fresh: true });
  const sessionId = selected.id;

  console.log(`${ansi.cyan("Agent")} ${ansi.dim(`— ${selected.title}${selected.cwd ? ` · ${basename(selected.cwd)}` : ""}`)}`);
  if (options.dev) console.log(ansi.dim("Hot reload is on. Runtime state survives code changes."));
  console.log(ansi.dim("/new  /status  /help  /quit\n"));

  const rl = createInterface({ input: process.stdin, output: process.stdout });
  let stopping = false;
  let fatalError: Error | undefined;
  let hasConnected = false;
  const observerController = new AbortController();
  let streamController: AbortController | undefined;
  let streamReady = Promise.resolve();
  let markStreamReady: () => void = () => undefined;
  const output = new CliOutput(sessionId, status, (id) => void changeSession(id), () => promptActive);
  async function changeSession(id: string): Promise<void> {
    output.sessionId = id;
    streamReady = new Promise<void>((resolve) => { markStreamReady = resolve; });
    streamController?.abort();
    await streamReady;
  }
  let connected!: () => void;
  let failConnection!: (error: Error) => void;
  const firstConnection = new Promise<void>((resolve, reject) => { connected = resolve; failConnection = reject; });
  const observe = async () => {
    while (!stopping) {
      const current = new AbortController();
      streamController = current;
      const stopStream = () => current.abort();
      observerController.signal.addEventListener("abort", stopStream, { once: true });
      try {
        const events = await client.events(current.signal, output.sessionId, output.activeRunId);
        for await (const event of events) {
          output.render(event);
          if (event.event.type === "snapshot") {
            hasConnected = true;
            connected();
            markStreamReady();
          }
        }
      } catch (error) {
        if (stopping) return;
        if (current.signal.aborted) continue;
        if (error instanceof RuntimeProtocolError) {
          if (hasConnected) {
            fatalError = error;
            stopping = true;
            output.resolveWaiters();
            rl.close();
          } else failConnection(error);
          return;
        }
        status("Reconnecting…");
        await client.waitUntilHealthy().catch(() => undefined);
      } finally {
        observerController.signal.removeEventListener("abort", stopStream);
      }
    }
  };
  const observer = observe();

  const onSigint = () => {
    if (output.activeRunId) {
      void client.stop(output.activeRunId);
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
        console.log("Talk normally, including to open an earlier conversation. /new starts fresh; Ctrl-C stops this response.");
        continue;
      }
      if (input === "/new") {
        const session = await client.openSession({ fresh: true });
        await changeSession(session.id);
        status("New conversation ready.");
        continue;
      }
      if (input === "/status") {
        const [data, setup] = await Promise.all([
          client.sessions(),
          client.setupStatus(),
        ]);
        const current = data.sessions.find((session) => session.id === output.sessionId);
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
          sessionId: output.sessionId,
          channel: "cli",
        });
        if (!run) {
          status("Agent is already working. Ctrl-C stops the active response.");
          continue;
        }
        output.submitted(run.id);
        await output.waitFor(run.id);
        if (fatalError) throw fatalError;
        output.release(run.id);
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
