import { spawn } from "node:child_process";
import { randomUUID } from "node:crypto";
import { appendFileSync, chmodSync, closeSync, existsSync, mkdirSync, openSync, readFileSync, readdirSync, renameSync, rmSync, statSync, truncateSync, watch, writeFileSync } from "node:fs";
import { createServer } from "node:net";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { socketPath, stateDir } from "./protocol.mjs";
import { safeDisplay } from "./security.mjs";

const here = dirname(fileURLToPath(import.meta.url));
const jobsDir = join(stateDir, "jobs");
const requestsDir = join(stateDir, "requests");
const eventsDir = join(stateDir, "events");
const sessionsDir = join(stateDir, "sessions");
const lockPath = join(stateDir, "daemon.pid");
const model = process.env.PI_AGENT_MODEL || "openai-codex/gpt-5.6-sol";
const utilityModel = process.env.PI_AGENT_UTILITY_MODEL || "openai-codex/gpt-5.6-luna";
const piCommand = process.env.PI_AGENT_PI_COMMAND || "pi";
const jobs = new Map();
const requests = new Map();
const sequences = new Map();
const eventKeys = new Map();
const subscribers = new Map();
const running = new Map();
const summaries = new Map();
const children = new Set();
const safeId = (value) => typeof value === "string" && /^[0-9a-f-]{36}$/i.test(value);
const promptFile = (name) => join(here, "prompts", `${name}.md`);
const readPrompt = (name) => readFileSync(promptFile(name), "utf8");

for (const dir of [stateDir, jobsDir, requestsDir, eventsDir, sessionsDir]) mkdirSync(dir, { recursive: true, mode: 0o700 });
chmodSync(stateDir, 0o700);
for (let attempt = 0; attempt < 2; attempt++) {
  try { writeFileSync(lockPath, String(process.pid), { flag: "wx", mode: 0o600 }); break; }
  catch (error) {
    if (error.code !== "EEXIST") throw error;
    const owner = Number(readFileSync(lockPath, "utf8"));
    try { process.kill(owner, 0); process.exit(0); }
    catch (signalError) { if (signalError.code !== "ESRCH") throw signalError; }
    rmSync(lockPath, { force: true });
    if (attempt === 1) throw new Error("Could not acquire daemon lock");
  }
}

function saveJob(job) {
  const path = join(jobsDir, `${job.id}.json`);
  const temp = `${path}.${process.pid}.tmp`;
  writeFileSync(temp, JSON.stringify(job), { mode: 0o600 });
  renameSync(temp, path);
  jobs.set(job.id, job);
}
function saveRequest(request) {
  const path = join(requestsDir, `${request.id}.json`);
  const temp = `${path}.${process.pid}.tmp`;
  writeFileSync(temp, JSON.stringify(request), { mode: 0o600 });
  renameSync(temp, path);
  requests.set(request.id, request);
}

function eventsPath(source) { return join(eventsDir, `${source}.jsonl`); }
function eventsFor(source) {
  const path = eventsPath(source);
  if (!existsSync(path)) return [];
  return readFileSync(path, "utf8").split("\n").filter(Boolean).map((line) => JSON.parse(line));
}
function emit(source, event) {
  if (event.key && eventKeys.has(event.key)) return eventKeys.get(event.key);
  const seq = (sequences.get(source) || 0) + 1;
  sequences.set(source, seq);
  const entry = { source, seq, at: new Date().toISOString(), ...event,
    ...(event.text ? { text: safeDisplay(event.text) } : {}),
    ...(event.title ? { title: safeDisplay(event.title) } : {}) };
  appendFileSync(eventsPath(source), `${JSON.stringify(entry)}\n`, { mode: 0o600 });
  if (event.key) eventKeys.set(event.key, entry);
  for (const socket of subscribers.get(source) || []) socket.write(`${JSON.stringify({ kind: "event", ...entry })}\n`);
  return entry;
}
function update(job, state, extra = {}) {
  job.state = state;
  job.updatedAt = new Date().toISOString();
  saveJob(job);
  emit(job.source, { type: state, jobId: job.id, title: job.title, agent: job.agent,
    text: extra.text || `${job.title}: ${state}` });
}

function piProcess(args, cwd, onEvent) {
  const child = spawn(piCommand, args, { cwd, detached: true, stdio: ["ignore", "pipe", "pipe"], env: process.env });
  children.add(child);
  let buffer = "", stderr = "", lastText = "", errorText = "";
  child.stdout.on("data", (chunk) => {
    buffer += chunk.toString();
    let newline;
    while ((newline = buffer.indexOf("\n")) >= 0) {
      const line = buffer.slice(0, newline);
      buffer = buffer.slice(newline + 1);
      try {
        const event = JSON.parse(line);
        if (event.type === "message_end" && event.message?.role === "assistant") {
          const text = (event.message.content || []).filter((part) => part.type === "text")
            .map((part) => part.text).join("\n").trim();
          if (text) lastText = text;
          if (event.message.stopReason === "error") errorText = event.message.errorMessage || "Model error";
        }
        onEvent?.(event);
      } catch { /* Ignore malformed child output; its exit status remains authoritative. */ }
    }
  });
  child.stderr.on("data", (chunk) => { stderr = (stderr + chunk.toString()).slice(-4000); });
  const done = new Promise((resolve) => {
    child.once("error", (error) => { children.delete(child); errorText = error.message; resolve({ code: 1, text: lastText, error: errorText }); });
    child.once("close", (code) => { children.delete(child); resolve({ code: code ?? 1, text: lastText, error: errorText || stderr.trim() }); });
  });
  return { child, done };
}

async function utility(promptName, input, cwd = here) {
  const args = ["--mode", "json", "--print", "--no-session", "--no-extensions", "--no-skills",
    "--no-tools", "--model", utilityModel, "--system-prompt", promptFile(promptName),
    "--append-system-prompt", promptFile("base"), "--", input];
  const result = await piProcess(args, cwd).done;
  if (result.code || !result.text) throw new Error(result.error || `${promptName} returned no text`);
  return result.text;
}

function routeText(text) {
  const raw = text.trim().replace(/^```(?:json)?\s*/i, "").replace(/\s*```$/, "");
  const parsed = JSON.parse(raw);
  if (!Array.isArray(parsed.routes) || parsed.routes.length < 1 || parsed.routes.length > 4) throw new Error("Coordinator returned invalid routes");
  return parsed.routes.map((route) => {
    if (!["worker", "scout", "reviewer"].includes(route.agent) || typeof route.title !== "string" ||
      !route.title.trim() || typeof route.task !== "string" || !route.task.trim() ||
      (route.jobId != null && !safeId(route.jobId))) throw new Error("Coordinator returned an invalid route");
    return { agent: route.agent, title: safeDisplay(route.title.trim().slice(0, 80)), task: route.task.trim(), jobId: route.jobId };
  });
}

async function summarize(job, kind, text, key) {
  if (eventKeys.has(key)) return;
  const runId = key.slice(0, 36);
  if (job.runId !== runId) return;
  const prior = job.lastSummary || "";
  const input = `Task: ${job.title}\nCurrent request: ${job.activeTask || job.original}\nEvent: ${kind}` +
    (kind === "progress" && prior ? `\nEarlier update (avoid repetition): ${prior}` : "") +
    `\nCurrent child event (authoritative quoted data):\n${text.slice(-6000)}`;
  const summary = safeDisplay((await utility("reporter", input, job.cwd)).trim());
  if (job.runId !== runId || ["cancelling", "cancelled"].includes(job.state)) return;
  if (!summary || (summary === prior && kind === "progress")) return;
  emit(job.source, { type: kind === "complete" ? "complete" : kind === "failed" ? "failed" : "progress",
    key, jobId: job.id, title: job.title, agent: job.agent, text: summary });
  job.lastSummary = summary;
  saveJob(job);
}
function enqueueSummary(job, kind, text, key) {
  const prior = summaries.get(job.id) || Promise.resolve();
  const next = prior.then(() => summarize(job, kind, text, key)).catch((error) => {
    if (job.runId !== key.slice(0, 36) || ["cancelling", "cancelled"].includes(job.state)) return;
    const fallback = safeDisplay(`Summary unavailable (${error.message}). Child ${kind}: ${text.slice(0, 1600)}`);
    emit(job.source, { type: kind, jobId: job.id, title: job.title, key, text: fallback });
    job.lastSummary = fallback;
    saveJob(job);
  });
  summaries.set(job.id, next);
  return next;
}

function canRun(job) {
  if (running.size >= 4) return false;
  if (job.agent !== "worker") return true;
  return ![...running.values()].some((item) => item.job.agent === "worker" && item.job.cwd === job.cwd);
}
function drain() {
  for (const job of jobs.values()) {
    if (job.state === "queued" && canRun(job)) runJob(job);
  }
}
function workerOutput(job) { return join(jobsDir, `${job.id}.${job.runId}.stdout.jsonl`); }
function workerError(job) { return join(jobsDir, `${job.id}.${job.runId}.stderr.log`); }
function isAlive(pid) {
  if (!Number.isSafeInteger(pid) || pid <= 0) return false;
  try { process.kill(pid, 0); return true; }
  catch (error) { return error.code !== "ESRCH"; }
}
async function finishJob(job, state) {
  if (job.state !== "running") return;
  const runId = job.runId;
  const key = `${runId}:complete`;
  const error = existsSync(workerError(job)) ? readFileSync(workerError(job), "utf8").slice(-2000).trim() : "";
  const output = job.lastOutput || job.error || error || "No result was returned";
  await enqueueSummary(job, state, output, key);
  if (job.state !== "running" || job.runId !== runId) return;
  emit(job.source, { type: "settled", key: `${runId}:settled`, jobId: job.id, title: job.title,
    agent: job.agent, state, text: `${job.title}: ${state}.` });
  running.get(job.id)?.close();
  running.delete(job.id);
  delete job.pid;
  delete job.activeTask;
  job.state = job.pending.length ? "queued" : state;
  job.updatedAt = new Date().toISOString();
  saveJob(job);
  drain();
}
function attachWorker(job, child) {
  const path = workerOutput(job);
  const runId = job.runId;
  let busy = false, closed = false, childExited = false, needsScan = false;
  async function scan() {
    if (busy) { needsScan = true; return; }
    if (closed || job.runId !== runId) return;
    busy = true;
    try {
      if (job.state === "cancelling") {
        if (childExited || !isAlive(job.pid)) {
          running.get(job.id)?.close();
          running.delete(job.id);
          delete job.pid;
          update(job, "cancelled", { text: `${job.title} cancelled.` });
          drain();
        }
        return;
      }
      if (job.state !== "running") return;
      if (existsSync(path)) {
        while (job.state === "running" && job.runId === runId) {
          const raw = readFileSync(path);
          let cursor = job.offset || 0;
          while (cursor < raw.length && job.state === "running" && job.runId === runId) {
            const newline = raw.indexOf(10, cursor);
            if (newline < 0) break;
            const start = cursor;
            cursor = newline + 1;
            try {
              const event = JSON.parse(raw.subarray(start, newline).toString("utf8"));
              if (event.type === "message_end" && event.message?.role === "assistant") {
                const prose = (event.message.content || []).filter((part) => part.type === "text")
                  .map((part) => part.text).join("\n").trim();
                if (prose) job.lastOutput = prose;
                if (["error", "aborted"].includes(event.message.stopReason)) job.error = event.message.errorMessage || event.message.stopReason;
                if (prose.length >= 25 && !["stop", "error", "aborted"].includes(event.message.stopReason)) {
                  await enqueueSummary(job, "progress", prose, `${job.runId}:${start}`);
                }
              }
              if (event.type === "agent_settled") {
                job.offset = cursor;
                saveJob(job);
                await finishJob(job, job.error ? "failed" : "complete");
                return;
              }
            } catch (error) {
              job.error = `Could not read child event: ${error.message}`;
            }
            if (job.runId !== runId) return;
            job.offset = cursor;
            saveJob(job);
          }
          if (statSync(path).size <= raw.length) break;
        }
      }
      if (job.state === "running" && (childExited || !isAlive(job.pid))) {
        await finishJob(job, "failed");
      }
    } finally {
      busy = false;
      if (needsScan && !closed) { needsScan = false; queueMicrotask(() => void scan()); }
    }
  }
  const watcher = watch(path, () => void scan());
  const interval = setInterval(() => void scan(), 5000);
  running.set(job.id, { job, close: () => { closed = true; watcher.close(); clearInterval(interval); } });
  child?.once("close", () => { childExited = true; void scan(); });
  child?.once("error", (error) => { job.error = error.message; childExited = true; void scan(); });
  void scan();
}
function runJob(job) {
  const task = job.pending.shift();
  if (!task) return update(job, "failed", { text: `${job.title} had no queued request.` });
  job.state = "running";
  job.runId = randomUUID();
  job.activeTask = task;
  job.offset = 0;
  job.lastOutput = "";
  job.lastSummary = "";
  job.error = "";
  job.updatedAt = new Date().toISOString();
  saveJob(job);
  const instructions = `${readPrompt("base")}\n\n${readPrompt(job.agent)}`;
  const instructionPath = join(jobsDir, `${job.id}.instructions.md`);
  writeFileSync(instructionPath, instructions, { mode: 0o600 });
  const args = ["--mode", "json", "--print", "--session-id", job.id, "--session-dir", sessionsDir,
    "--no-extensions", "--model", model, "--append-system-prompt", instructionPath];
  if (job.agent !== "worker") args.push("--tools", "read,grep,find,ls");
  args.push("--", task);
  const stdout = openSync(workerOutput(job), "wx", 0o600);
  const stderr = openSync(workerError(job), "wx", 0o600);
  const child = spawn(piCommand, args, { cwd: job.cwd, detached: true, stdio: ["ignore", stdout, stderr], env: process.env });
  closeSync(stdout);
  closeSync(stderr);
  child.unref();
  job.pid = child.pid;
  saveJob(job);
  attachWorker(job, child);
  emit(job.source, { type: "running", jobId: job.id, title: job.title, agent: job.agent,
    text: `${job.title} started.` });
}

const routing = new Set();
async function routeRequest(request) {
  if (routing.has(request.id) || request.state === "done" || request.state === "failed") return;
  routing.add(request.id);
  try {
    if (!request.plan) {
      const existing = [...jobs.values()].filter((job) => job.source === request.source)
        .map(({ id, title, state, agent, lastSummary }) => ({ id, title, state, agent, lastSummary })).slice(-12);
      const input = `User request (verbatim):\n${request.text}\n\nCurrent directory: ${request.cwd}\nExisting jobs: ${JSON.stringify(existing)}\n\nReturn JSON only.`;
      const routed = routeText(await utility("coordinator", input, request.cwd));
      for (const route of routed) {
        if (route.jobId && jobs.get(route.jobId)?.source !== request.source) throw new Error(`Unknown task ${route.jobId}`);
      }
      request.plan = routed.map((route) => ({ ...route, createdJobId: route.jobId ? undefined : randomUUID() }));
      request.state = "planned";
      saveRequest(request);
    }
    for (const [index, route] of request.plan.entries()) {
      const appliedKey = `${request.id}:${index}`;
      const task = route.task.includes(request.text) ? route.task :
        `Original user message (verbatim):\n${request.text}\n\nAssigned scope:\n${route.task}`;
      if (route.jobId) {
        const job = jobs.get(route.jobId);
        if (!job) throw new Error(`Task disappeared: ${route.jobId}`);
        if (!job.appliedRoutes?.includes(appliedKey)) {
          job.pending.push(task);
          job.appliedRoutes = [...(job.appliedRoutes || []), appliedKey];
          if (job.state !== "running") job.state = "queued";
          saveJob(job);
        }
        emit(job.source, { type: "queued", key: `${appliedKey}:queued`, jobId: job.id, title: job.title, agent: job.agent,
          text: `Follow-up queued for ${job.title}.` });
      } else {
        let job = jobs.get(route.createdJobId);
        if (!job) {
          job = { id: route.createdJobId, source: request.source, cwd: request.cwd, agent: route.agent,
            title: route.title, original: request.text, pending: [task], state: "queued",
            createdAt: new Date().toISOString(), updatedAt: new Date().toISOString(), lastSummary: "" };
          saveJob(job);
        }
        emit(job.source, { type: "queued", key: `${appliedKey}:queued`, jobId: job.id, title: job.title, agent: job.agent,
          text: `${job.title} queued.` });
      }
    }
    request.state = "done";
    saveRequest(request);
    drain();
  } catch (error) {
    if (!request.plan) { request.state = "failed"; saveRequest(request); }
    emit(request.source, { type: "failed", key: `${request.id}:failed`, requestId: request.id,
      title: "Routing failed", text: error.message });
  } finally {
    routing.delete(request.id);
  }
}

for (const file of readdirSync(jobsDir).filter((name) => name.endsWith(".json"))) {
  try {
    const job = JSON.parse(readFileSync(join(jobsDir, file), "utf8"));
    if (!safeId(job.id) || !safeId(job.source)) continue;
    jobs.set(job.id, job);
  } catch { /* Ignore an incomplete or unrelated file. */ }
}
for (const file of readdirSync(requestsDir).filter((name) => name.endsWith(".json"))) {
  try {
    const request = JSON.parse(readFileSync(join(requestsDir, file), "utf8"));
    if (safeId(request.id) && safeId(request.source)) requests.set(request.id, request);
  } catch { /* Ignore an incomplete or unrelated file. */ }
}
for (const file of readdirSync(eventsDir).filter((name) => name.endsWith(".jsonl"))) {
  const source = file.slice(0, -6);
  if (safeId(source)) {
    const path = eventsPath(source);
    const raw = readFileSync(path);
    const completeBytes = raw.lastIndexOf(10) + 1;
    if (completeBytes < raw.length) {
      writeFileSync(`${path}.partial-${Date.now()}`, raw.subarray(completeBytes), { mode: 0o600 });
      truncateSync(path, completeBytes);
    }
    const events = eventsFor(source);
    sequences.set(source, events.at(-1)?.seq || 0);
    for (const event of events) if (event.key) eventKeys.set(event.key, event);
  }
}
for (const job of jobs.values()) {
  if (job.state === "running" || job.state === "cancelling") {
    if (job.runId && existsSync(workerOutput(job))) attachWorker(job, null);
    else if (job.state === "cancelling") update(job, "cancelled", { text: `${job.title} cancelled.` });
    else update(job, "interrupted", { text: `${job.title} stopped before its output file was ready. Resume it explicitly.` });
  }
}
for (const request of requests.values()) if (["routing", "planned"].includes(request.state)) void routeRequest(request);

function handle(socket, message) {
  if (message.type === "subscribe" && safeId(message.source)) {
    const after = Number.isSafeInteger(message.after) && message.after >= 0 ? message.after : 0;
    socket.write(`${JSON.stringify({ ok: true })}\n`);
    for (const event of eventsFor(message.source)) if (event.seq > after) socket.write(`${JSON.stringify({ kind: "event", replay: true, ...event })}\n`);
    if (!subscribers.has(message.source)) subscribers.set(message.source, new Set());
    subscribers.get(message.source).add(socket);
    socket.on("close", () => subscribers.get(message.source)?.delete(socket));
    return;
  }
  if (message.type === "dispatch" && safeId(message.source) && typeof message.text === "string" &&
      message.text.trim() && message.text.length < 30000 && typeof message.cwd === "string" &&
      existsSync(message.cwd) && statSync(message.cwd).isDirectory()) {
    const request = { id: randomUUID(), source: message.source, cwd: message.cwd, text: message.text.trim(),
      state: "routing", createdAt: new Date().toISOString() };
    saveRequest(request);
    emit(message.source, { type: "routing", key: `${request.id}:routing`, requestId: request.id,
      text: request.text, title: "Routing request" });
    socket.end(`${JSON.stringify({ ok: true, requestId: request.id })}\n`);
    void routeRequest(request);
    return;
  }
  if (message.type === "followup" && safeId(message.source) && safeId(message.jobId) &&
      typeof message.text === "string" && message.text.trim()) {
    const job = jobs.get(message.jobId);
    if (!job || job.source !== message.source) return socket.end(`${JSON.stringify({ ok: false, error: "Task not found" })}\n`);
    job.pending.push(message.text.trim());
    if (job.state !== "running") job.state = "queued";
    saveJob(job);
    emit(job.source, { type: "queued", jobId: job.id, title: job.title, agent: job.agent,
      text: `Follow-up queued for ${job.title}.` });
    drain();
    return socket.end(`${JSON.stringify({ ok: true, jobId: job.id })}\n`);
  }
  if (message.type === "resume" && safeId(message.source) && safeId(message.jobId)) {
    const job = jobs.get(message.jobId);
    if (!job || job.source !== message.source || job.state !== "interrupted" || !job.activeTask) {
      return socket.end(`${JSON.stringify({ ok: false, error: "Task is not interrupted or cannot be resumed" })}\n`);
    }
    job.pending.unshift(job.activeTask);
    job.state = "queued";
    saveJob(job);
    emit(job.source, { type: "queued", jobId: job.id, title: job.title, agent: job.agent,
      text: `${job.title} queued to resume.` });
    drain();
    return socket.end(`${JSON.stringify({ ok: true })}\n`);
  }
  if (message.type === "cancel" && safeId(message.source) && safeId(message.jobId)) {
    const job = jobs.get(message.jobId);
    if (!job || job.source !== message.source) return socket.end(`${JSON.stringify({ ok: false, error: "Task not found" })}\n`);
    job.pending = [];
    if (job.state === "running" || job.state === "cancelling") {
      update(job, "cancelling", { text: `Cancelling ${job.title}.` });
      if (job.pid) try { process.kill(-job.pid, "SIGTERM"); } catch { /* Already stopped. */ }
    } else {
      update(job, "cancelled", { text: `${job.title} cancelled.` });
      drain();
    }
    return socket.end(`${JSON.stringify({ ok: true })}\n`);
  }
  if (message.type === "list" && safeId(message.source)) {
    const selected = [...jobs.values()].filter((job) => job.source === message.source)
      .map(({ id, title, state, agent, updatedAt }) => ({ id, title, state, agent, updatedAt }));
    return socket.end(`${JSON.stringify({ ok: true, jobs: selected })}\n`);
  }
  socket.end(`${JSON.stringify({ ok: false, error: "Invalid request" })}\n`);
}

if (existsSync(socketPath)) rmSync(socketPath, { force: true });
const server = createServer((socket) => {
  let buffer = "";
  socket.on("data", (chunk) => {
    buffer += chunk.toString();
    if (buffer.length > 40000) return socket.destroy();
    const newline = buffer.indexOf("\n");
    if (newline < 0) return;
    try { handle(socket, JSON.parse(buffer.slice(0, newline))); }
    catch (error) { socket.end(`${JSON.stringify({ ok: false, error: error.message })}\n`); }
  });
});
server.listen(socketPath, () => { chmodSync(socketPath, 0o600); drain(); });
process.on("SIGTERM", () => {
  for (const child of children) {
    if (child.pid) try { process.kill(-child.pid, "SIGTERM"); } catch { /* Already stopped. */ }
  }
  server.close();
  rmSync(socketPath, { force: true });
  rmSync(lockPath, { force: true });
  process.exit(0);
});
