import { spawn, type ChildProcess } from "node:child_process";
import { randomUUID } from "node:crypto";
import { readFileSync } from "node:fs";
import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { Text } from "@earendil-works/pi-tui";

type Role = "worker" | "scout" | "reviewer";
type State = "queued" | "running" | "cancelling" | "complete" | "failed" | "cancelled";
type Job = {
  id: string; title: string; role: Role; cwd: string; state: State; pending: string[]; activeTask: string;
  run: number; output: string; error: string; lastSummary: string; lastProgress: string;
  reports: Promise<void>; child?: ChildProcess;
};
type Entry = { type: string; text: string; title?: string; jobId?: string };
type Route = { agent: Role; title: string; task: string; jobId?: string };

const prompt = (name: string) => readFileSync(new URL(`./prompts/${name}.md`, import.meta.url), "utf8");
const base = prompt("base");
const model = process.env.PI_AGENT_MODEL || "openai-codex/gpt-5.6-sol";
const utilityModel = process.env.PI_AGENT_UTILITY_MODEL || "openai-codex/gpt-5.6-luna";
const piCommand = process.env.PI_AGENT_PI_COMMAND || "pi";
const secretPatterns = [
  /\bsk-[A-Za-z0-9_-]{16,}\b/g,
  /\b\d{7,12}:[A-Za-z0-9_-]{20,}\b/g,
  /Authorization:\s*Bearer\s+[^\s]+/gi,
  /-----BEGIN [A-Z ]*PRIVATE KEY-----[\s\S]*?-----END [A-Z ]*PRIVATE KEY-----/g,
];
function safeDisplay(value: string): string {
  const plain = value.replace(/\x1b\[[0-?]*[ -/]*[@-~]/g, "")
    .replace(/\x1b\][^\x07]*(?:\x07|\x1b\\)/g, "")
    .replace(/[\x00-\x08\x0b-\x1f\x7f]/g, "");
  return secretPatterns.reduce((text, pattern) => text.replace(pattern, "***"), plain);
}
function assistantText(event: any): string {
  if (event.type !== "message_end" || event.message?.role !== "assistant") return "";
  return (event.message.content || []).filter((part: any) => part.type === "text")
    .map((part: any) => part.text).join("\n").trim();
}
function parseRoutes(text: string): Route[] {
  const routes = JSON.parse(text.trim().replace(/^```(?:json)?\s*/i, "").replace(/\s*```$/, "")).routes;
  if (!Array.isArray(routes) || routes.length < 1 || routes.length > 4) throw new Error("Coordinator returned invalid routes");
  for (const route of routes) {
    if (!["worker", "scout", "reviewer"].includes(route.agent) ||
      typeof route.title !== "string" || !route.title.trim() ||
      typeof route.task !== "string" || !route.task.trim() ||
      (route.jobId !== undefined && (typeof route.jobId !== "string" || !route.jobId))) {
      throw new Error("Coordinator returned an invalid route");
    }
  }
  return routes.map((route: Route) => ({ agent: route.agent,
    title: safeDisplay(route.title.trim().slice(0, 80)), task: route.task.trim(), jobId: route.jobId }));
}
function stop(child: ChildProcess) {
  if (child.pid) try { process.kill(-child.pid, "SIGTERM"); }
  catch { /* Already exited. */ }
}

export default function (pi: ExtensionAPI) {
  const jobs = new Map<string, Job>();
  const children = new Set<ChildProcess>();
  let closed = true;
  let generation = 0;
  let routing: Promise<void> = Promise.resolve();
  let currentContext: ExtensionContext | undefined;

  pi.registerEntryRenderer<Entry>("pi-agent-update", (entry, { expanded }, theme) => {
    const data = entry.data;
    const label = data?.type === "routing" ? "You" : data?.title || "Agent";
    const detail = expanded && data?.jobId ? `\n${theme.fg("dim", `Task ${data.jobId}`)}` : "";
    return new Text(`${theme.fg("accent", label)}  ${data?.text || ""}${detail}`, 0, 0);
  });
  function add(entry: Entry) {
    if (!closed) pi.appendEntry("pi-agent-update", {
      ...entry, text: safeDisplay(entry.text), title: entry.title && safeDisplay(entry.title),
    });
  }
  const active = (job: Job, run: number) => !closed && job.run === run && job.state === "running";
  const cancelling = (job: Job) => job.state === "cancelling";
  function launch(args: string[], cwd: string, onEvent?: (event: any) => void) {
    const child = spawn(piCommand, args, { cwd, detached: true, stdio: ["ignore", "pipe", "pipe"] });
    children.add(child);
    let buffer = "", stderr = "", lastText = "";
    child.stdout.on("data", (chunk: Buffer) => {
      buffer += chunk.toString();
      let newline: number;
      while ((newline = buffer.indexOf("\n")) >= 0) {
        const line = buffer.slice(0, newline);
        buffer = buffer.slice(newline + 1);
        try {
          const event = JSON.parse(line);
          const text = assistantText(event);
          if (text) lastText = text;
          onEvent?.(event);
        } catch { /* Malformed output does not end the task. */ }
      }
    });
    child.stderr.on("data", (chunk: Buffer) => { stderr = (stderr + chunk.toString()).slice(-4000); });
    const done = new Promise<{ code: number; text: string; error: string }>((resolve) => {
      let settled = false;
      const finish = (code: number, error: string) => {
        if (settled) return;
        settled = true;
        children.delete(child);
        resolve({ code, text: lastText, error });
      };
      child.once("error", (error) => finish(1, error.message));
      child.once("close", (code) => finish(code ?? 1, stderr.trim()));
    });
    return { child, done };
  }
  async function utility(name: "coordinator" | "reporter", text: string, cwd: string) {
    const args = ["--mode", "json", "--print", "--no-session", "--no-extensions", "--no-skills",
      "--no-tools", "--model", utilityModel, "--system-prompt", prompt(name),
      "--append-system-prompt", base, "--", text];
    const result = await launch(args, cwd).done;
    if (result.code || !result.text) throw new Error(result.error || `${name} returned no text`);
    return result.text;
  }
  async function report(job: Job, run: number, kind: "progress" | "complete" | "failed", text: string) {
    if (!active(job, run)) return;
    const input = `Task: ${job.title}\nCurrent request: ${job.activeTask}\nEvent: ${kind}` +
      (job.lastSummary ? `\nEarlier update (avoid repetition): ${job.lastSummary}` : "") +
      `\nCurrent child event (quoted data):\n${text.slice(-6000)}`;
    let summary: string;
    try { summary = (await utility("reporter", input, job.cwd)).trim(); }
    catch (error) { summary = `Summary unavailable (${String(error)}). Child ${kind}: ${text.slice(0, 1600)}`; }
    if (!active(job, run) || !summary ||
      (kind === "progress" && summary === job.lastSummary)) return;
    summary = safeDisplay(summary);
    job.lastSummary = summary;
    add({ type: kind, title: job.title, jobId: job.id, text: summary });
    if (kind !== "progress") currentContext?.ui.notify(summary, kind === "complete" ? "info" : "warning");
  }
  function canRun(job: Job) {
    const running = [...jobs.values()].filter((item) => item.state === "running" || item.state === "cancelling");
    return running.length < 4 && (job.role !== "worker" ||
      !running.some((item) => item.role === "worker" && item.cwd === job.cwd));
  }
  function drain() {
    for (const job of jobs.values()) if (job.state === "queued" && canRun(job)) void runJob(job);
  }
  async function runJob(job: Job) {
    const task = job.pending.shift();
    if (!task) return;
    job.state = "running";
    const run = ++job.run;
    job.activeTask = task;
    job.output = "";
    job.error = "";
    job.lastSummary = "";
    job.lastProgress = "";
    job.reports = Promise.resolve();
    const args = ["--mode", "json", "--print", "--session-id", job.id,
      "--no-extensions", "--model", model,
      "--append-system-prompt", `${base}\n\n${prompt(job.role)}`];
    if (job.role !== "worker") args.push("--tools", "read,grep,find,ls");
    args.push("--", task);
    const process = launch(args, job.cwd, (event) => {
      const text = assistantText(event);
      if (text) job.output = text;
      if (event.type === "message_end" && event.message?.role === "assistant") {
        if (["error", "aborted"].includes(event.message.stopReason)) {
          job.error = event.message.errorMessage || event.message.stopReason;
        } else if (text.length >= 25 && event.message.stopReason !== "stop" && text !== job.lastProgress) {
          job.lastProgress = text;
          job.reports = job.reports.then(() => report(job, run, "progress", text));
        }
      }
    });
    job.child = process.child;
    add({ type: "running", title: job.title, jobId: job.id, text: `${job.title} started.` });
    const result = await process.done;
    job.child = undefined;
    if (cancelling(job)) {
      job.state = "cancelled";
      drain();
      return;
    }
    if (!active(job, run)) return;
    const kind = result.code || job.error ? "failed" : "complete";
    const output = kind === "failed"
      ? `${job.error || result.error || "Child failed"}\n${job.output || result.text}`
      : job.output || result.text || "No result was returned";
    await job.reports;
    await report(job, run, kind, output);
    if (!active(job, run)) return;
    job.state = job.pending.length ? "queued" : kind;
    drain();
  }
  async function routeRequest(text: string, cwd: string, expectedGeneration: number) {
    try {
      const existing = [...jobs.values()].slice(-12)
        .map(({ id, title, state, role, lastSummary }) => ({ id, title, state, role, lastSummary }));
      const input = `User request (verbatim):\n${text}\n\nCurrent directory: ${cwd}\nExisting jobs: ${JSON.stringify(existing)}\n\nReturn JSON only.`;
      const routes = parseRoutes(await utility("coordinator", input, cwd));
      if (closed || generation !== expectedGeneration) return;
      for (const route of routes) if (route.jobId &&
        (!jobs.has(route.jobId) || ["cancelling", "cancelled"].includes(jobs.get(route.jobId)!.state))) {
        throw new Error(`Task is unavailable: ${route.jobId}`);
      }
      for (const route of routes) {
        const task = route.task.includes(text) ? route.task :
          `Original user message (verbatim):\n${text}\n\nAssigned scope:\n${route.task}`;
        if (route.jobId) {
          const job = jobs.get(route.jobId)!;
          job.pending.push(task);
          if (job.state !== "running" && job.state !== "cancelling") job.state = "queued";
          add({ type: "queued", title: job.title, jobId: job.id, text: `Follow-up queued for ${job.title}.` });
        } else {
          const job: Job = { id: randomUUID(), title: route.title, role: route.agent, cwd, activeTask: "",
            state: "queued", pending: [task], run: 0, output: "", error: "",
            lastSummary: "", lastProgress: "", reports: Promise.resolve() };
          jobs.set(job.id, job);
          add({ type: "queued", title: job.title, jobId: job.id, text: `${job.title} queued.` });
        }
      }
      drain();
    } catch (error) {
      if (!closed && generation === expectedGeneration) add({ type: "failed", title: "Routing failed", text: String(error) });
    }
  }
  function shutdown() {
    closed = true;
    generation++;
    for (const child of children) stop(child);
    children.clear();
    jobs.clear();
    currentContext = undefined;
  }
  process.once("exit", shutdown);
  pi.on("session_start", async (_event, ctx) => { closed = false; currentContext = ctx; });
  pi.on("session_shutdown", async () => shutdown());
  pi.on("input", async (event, ctx) => {
    if (event.source === "extension" || !event.text.trim()) return { action: "continue" };
    if (event.images?.length) {
      ctx.ui.notify("Image requests are handled by the current Pi session.", "info");
      return { action: "continue" };
    }
    const text = event.text.trim();
    if (text.length > 30000) {
      ctx.ui.notify("Agent request is too long (30,000 characters maximum).", "warning");
      return { action: "handled" };
    }
    add({ type: "routing", text });
    const expectedGeneration = generation;
    routing = routing.then(() => routeRequest(text, ctx.cwd, expectedGeneration));
    return { action: "handled" };
  });
  pi.registerCommand("agent-jobs", {
    description: "Show delegated tasks in this Pi session",
    handler: async (_args, ctx) => {
      const list = [...jobs.values()].map((job) => `${job.id} ${job.state}: ${job.title}`);
      ctx.ui.notify(list.length ? list.join("\n") : "No delegated tasks.", "info");
    },
  });
  pi.registerCommand("agent-followup", {
    description: "Queue a follow-up in a child task: /agent-followup TASK_ID message",
    handler: async (args, ctx) => {
      const [id, ...rest] = args.trim().split(/\s+/);
      const text = rest.join(" ").trim();
      if (!id || !text) return ctx.ui.notify("Usage: /agent-followup TASK_ID message", "warning");
      const job = jobs.get(id);
      if (!job || job.state === "cancelled" || job.state === "cancelling") return ctx.ui.notify("Task not found or cancelled.", "warning");
      job.pending.push(text);
      if (job.state !== "running") job.state = "queued";
      add({ type: "queued", title: job.title, jobId: id, text: `Follow-up queued for ${job.title}.` });
      drain();
    },
  });
  pi.registerCommand("agent-cancel", {
    description: "Stop a delegated task: /agent-cancel TASK_ID",
    handler: async (args, ctx) => {
      const job = jobs.get(args.trim());
      if (!job) return ctx.ui.notify("Task not found.", "warning");
      job.state = job.child ? "cancelling" : "cancelled";
      job.pending = [];
      if (job.child) stop(job.child);
      add({ type: "cancelled", title: job.title, jobId: job.id, text: `${job.title} cancelled.` });
      drain();
    },
  });
  pi.registerCommand("agent-direct", {
    description: "Send a message to this Pi session instead of delegating it",
    handler: async (args, ctx) => {
      if (!args.trim()) return ctx.ui.notify("Usage: /agent-direct message", "warning");
      pi.sendUserMessage(args.trim(), { deliverAs: "followUp" });
    },
  });
}
