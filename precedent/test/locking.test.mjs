import test from "node:test";
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const repoRoot = resolve(__dirname, "../..");
const cliPath = join(repoRoot, "precedent/bin/precedent.mjs");

test("concurrent observe calls serialize ledger promotion", async () => {
  const stateDir = await mkdtemp(join(tmpdir(), "precedent-lock-test-"));

  try {
    const traceOut = await promoteReplayTrace(stateDir);
    const observes = await Promise.all(Array.from({ length: 6 }, () => runJson([
      "observe",
      "--state-dir",
      stateDir,
      "--trace",
      traceOut,
      "--json",
    ])));

    assert.ok(observes.some((result) => result.observed.promotionAction === "created"));
    assert.ok(observes.every((result) => ["created", "unchanged"].includes(result.observed.promotionAction)));

    const precedents = await readJsonLines(join(stateDir, "precedents.jsonl"));
    assert.equal(precedents.length, 1);
    assert.equal(precedents[0].id, "prec_webhook_replay_boundary");

    const check = await runJson(["check", "--state-dir", stateDir, "--strict", "--json"]);
    assert.equal(check.ok, true);
  } finally {
    await rm(stateDir, { force: true, recursive: true });
  }
});

test("concurrent context calls preserve one session injection", async () => {
  const stateDir = await mkdtemp(join(tmpdir(), "precedent-lock-test-"));

  try {
    await promoteWebhookPrecedent(stateDir);
    const contexts = await Promise.all(Array.from({ length: 6 }, (_unused, index) => runJson([
      "context",
      "--state-dir",
      stateDir,
      "--task",
      "add webhook handler",
      "--scope",
      "feature:webhooks",
      "--changed-files",
      "features/webhooks/providers/stripe.ts",
      "--session",
      "demo",
      "--event-id",
      `turn-${index}`,
      "--json",
    ])));

    assert.equal(contexts.filter((result) => result.injections.length === 1).length, 1);
    assert.equal(contexts.filter((result) => result.suppressedInjections.length === 1).length, 5);
    const delivered = contexts.find((result) => result.deliveryReceipt);
    await hook(stateDir, {
      schema_version: "precedent.v1",
      hook: "context.after_inject",
      sessionId: "demo",
      eventId: "ack-1",
      deliveryId: delivered.deliveryReceipt.deliveryId,
      contextBlockHash: delivered.contextBlockHash,
      inserted: true,
    });

    const sessionEvents = await readJsonLines(join(stateDir, "sessions/demo.jsonl"));
    assert.equal(sessionEvents.length, 7);
    assert.equal(sessionEvents.filter((event) => (event.injections ?? []).length === 1).length, 1);

    const check = await runJson(["check", "--state-dir", stateDir, "--strict", "--json"]);
    assert.equal(check.ok, true);
  } finally {
    await rm(stateDir, { force: true, recursive: true });
  }
});

function hook(stateDir, event) {
  return runJsonWithInput(["hook", "--state-dir", stateDir, "--json"], event);
}

test("strict check fails on leftover state lock or atomic temp file", async () => {
  const stateDir = await mkdtemp(join(tmpdir(), "precedent-lock-test-"));

  try {
    await runJson(["init", "--state-dir", stateDir, "--json"]);
    await writeFile(join(stateDir, "events.jsonl.123.tmp"), "");
    const result = await runProcess(["check", "--state-dir", stateDir, "--strict", "--json"]);
    const payload = JSON.parse(result.stdout);

    assert.equal(result.exitCode, 1);
    assert.ok(payload.checks.some((check) => check.name === "atomic_temp_files" && check.ok === false));
  } finally {
    await rm(stateDir, { force: true, recursive: true });
  }
});

async function promoteWebhookPrecedent(stateDir) {
  const traceOut = await promoteReplayTrace(stateDir);
  await runJson(["observe", "--state-dir", stateDir, "--trace", traceOut, "--json"]);
}

async function promoteReplayTrace(stateDir) {
  await runJson(["init", "--state-dir", stateDir, "--json"]);
  const traceOut = join(stateDir, "trace.json");
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

  return traceOut;
}

async function readJsonLines(path) {
  const content = await readFile(path, "utf8");
  return content
    .split("\n")
    .filter((line) => line.trim().length > 0)
    .map((line) => JSON.parse(line));
}

function runJson(args) {
  return runProcess(args).then((result) => {
    if (result.exitCode !== 0) {
      throw new Error(`precedent ${args.join(" ")} failed\n${result.stderr}`);
    }

    return JSON.parse(result.stdout);
  });
}

function runJsonWithInput(args, stdinJson) {
  return runProcess(args, stdinJson).then((result) => {
    if (result.exitCode !== 0) {
      throw new Error(`precedent ${args.join(" ")} failed\n${result.stderr}`);
    }

    return JSON.parse(result.stdout);
  });
}

function runProcess(args, stdinJson = null) {
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
      resolvePromise({
        exitCode,
        stdout,
        stderr,
      });
    });

    if (stdinJson) {
      child.stdin.end(`${JSON.stringify(stdinJson)}\n`);
    } else {
      child.stdin.end();
    }
  });
}
