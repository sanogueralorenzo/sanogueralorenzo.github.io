import test from "node:test";
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { mkdtemp, readFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const repoRoot = resolve(__dirname, "../..");
const cliPath = join(repoRoot, "precedent/bin/precedent.mjs");

test("loop processes JSONL hook events and keeps running after malformed input", async () => {
  const stateDir = await mkdtemp(join(tmpdir(), "precedent-loop-test-"));

  try {
    await runJson(["init", "--state-dir", stateDir, "--json"]);

    const responses = await runLoop(stateDir, [
      {
        schema_version: "precedent.v1",
        hook: "context.before_turn",
        sessionId: "demo",
        eventId: "turn-1",
        task: "add webhook handler",
        scope: "feature:webhooks",
        changedFiles: ["features/webhooks/providers/stripe.ts"],
      },
      "{bad json",
      {
        schema_version: "precedent.v1",
        hook: "validation.after_run",
        sessionId: "demo",
        eventId: "validation-1",
        command: "pnpm test:webhooks",
        exitCode: 0,
        stdout: "passed",
      },
      {
        schema_version: "precedent.v1",
        hook: "outcome.after_task",
        sessionId: "demo",
        eventId: "outcome-1",
        success: true,
      },
    ]);

    assert.equal(responses.length, 4);
    assert.equal(responses[0].ok, true);
    assert.equal(responses[0].hook, "context.before_turn");
    assert.equal(responses[1].ok, false);
    assert.match(responses[1].error, /invalid JSON/u);
    assert.equal(responses[2].ok, true);
    assert.equal(responses[2].validation.exitCode, 0);
    assert.equal(responses[3].ok, true);
    assert.equal(responses[3].outcome.success, true);
  } finally {
    await rm(stateDir, { force: true, recursive: true });
  }
});

test("loop preserves event-id idempotency across retried deliveries", async () => {
  const stateDir = await mkdtemp(join(tmpdir(), "precedent-loop-test-"));

  try {
    await runJson(["init", "--state-dir", stateDir, "--json"]);
    const traceOut = join(stateDir, "webhook-replay-trace.json");
    await runJson([
      "replay",
      "--state-dir",
      stateDir,
      "--case",
      "precedent/examples/replay/webhook-case.json",
      "--trace-out",
      traceOut,
      "--json",
    ]);
    await runJson(["observe", "--state-dir", stateDir, "--trace", traceOut, "--json"]);

    const event = {
      schema_version: "precedent.v1",
      hook: "context.before_turn",
      sessionId: "demo",
      eventId: "turn-1",
      task: "add another webhook handler",
      scope: "feature:webhooks",
      changedFiles: ["features/webhooks/providers/refund.ts"],
    };
    const responses = await runLoop(stateDir, [event, event]);

    assert.equal(responses.length, 2);
    assert.equal(responses[0].recorded, true);
    assert.equal(responses[0].deduped, false);
    assert.equal(responses[0].injections.length, 1);
    assert.equal(responses[1].recorded, false);
    assert.equal(responses[1].deduped, true);
    assert.deepEqual(responses[1].injections, responses[0].injections);
    assert.equal(responses[1].contextBlock, responses[0].contextBlock);

    const sessionEvents = await readJsonLines(join(stateDir, "sessions/demo.jsonl"));
    assert.equal(sessionEvents.filter((item) => item.eventId === "turn-1").length, 1);

    const globalEvents = await readJsonLines(join(stateDir, "events.jsonl"));
    assert.equal(globalEvents.filter((item) => item.eventId === "turn-1").length, 1);
  } finally {
    await rm(stateDir, { force: true, recursive: true });
  }
});

function runLoop(stateDir, items) {
  const input = items
    .map((item) => typeof item === "string" ? item : JSON.stringify(item))
    .join("\n");

  return runProcess(["loop", "--state-dir", stateDir, "--json"], `${input}\n`).then((result) => {
    if (result.exitCode !== 0) {
      throw new Error(`precedent loop failed\n${result.stderr}`);
    }

    return result.stdout
      .split("\n")
      .filter((line) => line.trim().length > 0)
      .map((line) => JSON.parse(line));
  });
}

function runJson(args, stdin = "") {
  return runProcess(args, stdin).then((result) => {
    if (result.exitCode !== 0) {
      throw new Error(`precedent ${args.join(" ")} failed\n${result.stderr}`);
    }

    return JSON.parse(result.stdout);
  });
}

function runProcess(args, stdin = "") {
  return new Promise((resolvePromise, reject) => {
    const child = spawn(process.execPath, [cliPath, ...args], {
      cwd: repoRoot,
      stdio: ["pipe", "pipe", "pipe"],
    });
    let stdout = "";
    let stderr = "";

    child.stdout.setEncoding("utf8");
    child.stderr.setEncoding("utf8");
    child.stdout.on("data", (chunk) => {
      stdout += chunk;
    });
    child.stderr.on("data", (chunk) => {
      stderr += chunk;
    });
    child.on("error", reject);
    child.on("close", (exitCode) => {
      resolvePromise({ exitCode, stdout, stderr });
    });
    child.stdin.end(stdin);
  });
}

async function readJsonLines(path) {
  const content = await readFile(path, "utf8");

  return content
    .split("\n")
    .filter((line) => line.trim().length > 0)
    .map((line) => JSON.parse(line));
}
