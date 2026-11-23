import { spawn } from "node:child_process";
import { createInterface } from "node:readline";

export function startCli(command: string, args: string[], cwd: string, signal: AbortSignal) {
  signal.throwIfAborted();
  const env = { ...process.env };
  delete env.CLAUDECODE;
  delete env.CLAUDE_CODE_ENTRYPOINT;
  delete env.ANTIGRAVITY_CLI_SESSION_ID;
  const child = spawn(command, args, { cwd, env, stdio: ["pipe", "pipe", "pipe"] });
  const lines = createInterface({ input: child.stdout, crlfDelay: Infinity });
  let failure: NodeJS.ErrnoException | undefined;
  let stopping: NodeJS.Timeout | undefined;
  let closed = false;
  let stderr = "";
  const exit = new Promise<number | null>(resolve => {
    child.once("error", error => { failure = error; });
    child.once("close", code => {
      closed = true;
      clearTimeout(stopping);
      signal.removeEventListener("abort", stop);
      resolve(code);
    });
  });
  child.stdin.on("error", () => {});
  child.stderr.setEncoding("utf8").on("data", (chunk: string) => { stderr = (stderr + chunk).slice(-4096); });

  function stop() {
    if (closed || stopping) return;
    child.stdin.end();
    if (child.kill("SIGTERM")) stopping = setTimeout(() => { child.kill("SIGKILL"); }, 1000).unref();
  }
  signal.addEventListener("abort", stop, { once: true });

  async function* events() {
    for await (const line of lines) {
      signal.throwIfAborted();
      if (line.startsWith("{")) yield JSON.parse(line);
    }
  }
  async function result() {
    const code = await exit;
    signal.throwIfAborted();
    if (failure?.code === "ENOENT") throw new Error(`Install ${command} on the Agent host`);
    if (/authentication required|not logged in|please (?:log|sign) in|unauthorized/i.test(stderr)) {
      throw new Error(`Sign in to ${command} on the Agent host`);
    }
    if (failure || code !== 0) throw new Error(`${command} exited without completing the turn`);
  }
  return {
    events, result,
    send: (value: unknown) => child.stdin.write(JSON.stringify(value) + "\n"),
    end: () => child.stdin.end(),
    stop: async () => { stop(); lines.close(); await exit; },
  };
}

export async function cliStatus(command: string, args: string[], cwd: string, signal: AbortSignal) {
  return await new Promise<string | undefined>(resolve => {
    const child = spawn(command, args, { cwd, signal, stdio: ["ignore", "pipe", "ignore"] });
    let stdout = "";
    child.stdout.setEncoding("utf8").on("data", chunk => { stdout = (stdout + chunk).slice(-16384); });
    child.once("error", () => resolve(undefined));
    child.once("close", code => resolve(code === 0 ? stdout : undefined));
  });
}
