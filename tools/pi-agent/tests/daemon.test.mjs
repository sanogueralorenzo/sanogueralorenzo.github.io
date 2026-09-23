import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { appendFileSync, chmodSync, existsSync, mkdtempSync, readFileSync, readdirSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const stateDir = mkdtempSync(join(tmpdir(), "pi-agent-test-"));
process.env.PI_AGENT_STATE_DIR = stateDir;
process.env.PI_AGENT_PI_COMMAND = join(here, "fake-pi.mjs");
chmodSync(process.env.PI_AGENT_PI_COMMAND, 0o755);
const { ensureDaemon, request } = await import("../protocol.mjs");
const source = randomUUID();
const eventsPath = join(stateDir, "events", `${source}.jsonl`);
const events = () => existsSync(eventsPath) ? readFileSync(eventsPath, "utf8").trim().split("\n").map(JSON.parse) : [];
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

async function until(predicate, timeout = 8000) {
  const deadline = Date.now() + timeout;
  while (Date.now() < deadline) {
    const result = predicate();
    if (result) return result;
    await sleep(40);
  }
  throw new Error("Timed out waiting for daemon event");
}
function alive(pid) {
  try { process.kill(pid, 0); return true; }
  catch (error) { return error.code !== "ESRCH"; }
}
async function restart(signal = "SIGTERM", partialEvent = false) {
  const pid = Number(readFileSync(join(stateDir, "daemon.pid"), "utf8"));
  process.kill(pid, signal);
  await until(() => !alive(pid));
  if (partialEvent) appendFileSync(eventsPath, '{"incomplete":');
  const socket = await ensureDaemon();
  socket.end();
}
async function stop() {
  if (existsSync(join(stateDir, "daemon.pid"))) {
    process.kill(Number(readFileSync(join(stateDir, "daemon.pid"), "utf8")), "SIGTERM");
    await until(() => !existsSync(join(stateDir, "daemon.pid")));
  }
}

test("routing and a worker survive supervisor restarts without duplicate delivery", async () => {
  try {
    const socket = await ensureDaemon(); socket.end();
    const accepted = await request({ type: "dispatch", source, cwd: tmpdir(), text: "SLOW_ROUTE SLOW_WORKER ANSWER_ONE" });
    assert.ok(accepted.requestId);
    await until(() => events().some((event) => event.type === "routing"));
    await restart("SIGTERM", true);
    assert.ok(readdirSync(join(stateDir, "events")).some((name) => name.includes(".partial-")));
    const first = await until(() => events().find((event) => event.type === "running"));
    const jobId = first.jobId;
    const jobPath = join(stateDir, "jobs", `${jobId}.json`);
    const worker = JSON.parse(readFileSync(jobPath, "utf8"));
    await restart("SIGKILL");
    process.kill(worker.pid, 0);
    await until(() => events().some((event) => event.type === "settled" && event.jobId === jobId));
    const completed = events().filter((event) => event.type === "complete" && event.jobId === jobId);
    assert.equal(completed.length, 1);
    assert.match(completed[0].text, /ANSWER_ONE/);
    assert.equal((await request({ type: "list", source })).jobs.length, 1);

    await request({ type: "followup", source, jobId, text: "PROGRESS SLOW_WORKER ANSWER_TWO" });
    await request({ type: "followup", source, jobId, text: "ANSWER_THREE" });
    await until(() => events().filter((event) => event.type === "complete" && event.jobId === jobId).length === 3);
    const answers = events().filter((event) => event.type === "complete" && event.jobId === jobId).map((event) => event.text);
    assert.deepEqual(answers, ["ANSWER_ONE", "ANSWER_TWO", "ANSWER_THREE"]);
    assert.equal(events().filter((event) => event.type === "progress" && event.jobId === jobId).length, 1);

    const beforeCancel = events().at(-1).seq;
    await request({ type: "followup", source, jobId, text: "SLOW_WORKER ANSWER_CANCEL" });
    await until(() => events().some((event) => event.seq > beforeCancel && event.type === "running" && event.jobId === jobId));
    await request({ type: "cancel", source, jobId });
    await until(() => events().some((event) => event.seq > beforeCancel && event.type === "cancelled" && event.jobId === jobId));
    assert.equal(events().filter((event) => event.seq > beforeCancel && event.type === "complete" && event.jobId === jobId).length, 0);
    await request({ type: "followup", source, jobId, text: "ANSWER_AFTER_CANCEL" });
    await until(() => events().some((event) => event.seq > beforeCancel && event.type === "complete" && event.jobId === jobId));
    assert.match(events().filter((event) => event.seq > beforeCancel && event.type === "complete" && event.jobId === jobId).at(-1).text, /ANSWER_AFTER_CANCEL/);
  } finally {
    await stop();
    rmSync(stateDir, { recursive: true, force: true });
  }
});
