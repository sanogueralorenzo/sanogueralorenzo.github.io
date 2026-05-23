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

test("attach emits a stable zero-touch adapter contract", async () => {
  const stateDir = await mkdtemp(join(tmpdir(), "precedent-attach-test-"));

  try {
    const taskFile = join(stateDir, "task.txt");
    await writeFile(taskFile, "add webhook handler");

    const first = await runJson([
      "attach",
      "--state-dir",
      stateDir,
      "--runtime",
      "codex",
      "--task-file",
      taskFile,
      "--scope",
      "feature:webhooks",
      "--changed-files",
      "features/webhooks/providers/stripe.ts",
      "--json",
    ]);
    const second = await runJson([
      "attach",
      "--state-dir",
      stateDir,
      "--runtime",
      "codex",
      "--task-file",
      taskFile,
      "--scope",
      "feature:webhooks",
      "--changed-files",
      "features/webhooks/providers/stripe.ts",
      "--json",
    ]);

    assert.equal(first.schema_version, "precedent.adapter.v1");
    assert.equal(first.runtime, "codex");
    assert.equal(first.sessionId, second.sessionId);
    assert.equal(first.adapter.beforeTurn.injectFrom, "contextBlock");
    assert.equal(first.adapter.beforeTurn.failurePolicy, "fail_open");
    assert.deepEqual(first.adapter.afterValidation.stdin.hook, "validation.after_run");
    assert.equal(first.adapter.afterValidation.stdin.attributedPrecedents, "$ATTRIBUTED_PRECEDENTS");
    assert.deepEqual(first.adapter.afterDiff.stdin.hook, "diff.after_edit");
    assert.equal(first.adapter.afterDiff.stdin.diffSummary, "$DIFF_SUMMARY");
    assert.equal(first.adapter.afterDiff.stdin.unifiedDiff, "$UNIFIED_DIFF");
    assert.equal(first.adapter.afterDiff.stdin.attributedPrecedents, "$ATTRIBUTED_PRECEDENTS");
    assert.deepEqual(first.adapter.afterReview.stdin.hook, "review.after_feedback");
    assert.deepEqual(first.adapter.afterReview.stdin.sessionId, first.sessionId);
    assert.deepEqual(first.adapter.afterOutcome.stdin.sessionId, first.sessionId);
    assert.equal(first.adapter.afterOutcome.stdin.task, "add webhook handler");
    assert.equal(first.adapter.afterOutcome.stdin.scope, "feature:webhooks");
    assert.deepEqual(first.adapter.afterOutcome.stdin.changedFiles, ["features/webhooks/providers/stripe.ts"]);
    assert.equal(first.adapter.afterOutcome.stdin.attributedPrecedents, "$ATTRIBUTED_PRECEDENTS");
  } finally {
    await rm(stateDir, { force: true, recursive: true });
  }
});

test("attach contract drives injection and outcome attribution", async () => {
  const stateDir = await mkdtemp(join(tmpdir(), "precedent-attach-test-"));

  try {
    await promoteWebhookPrecedent(stateDir);
    const taskFile = join(stateDir, "task.txt");
    await writeFile(taskFile, "add webhook handler");
    const adapter = await runJson([
      "attach",
      "--state-dir",
      stateDir,
      "--session",
      "demo",
      "--task-file",
      taskFile,
      "--scope",
      "feature:webhooks",
      "--changed-files",
      "features/webhooks/providers/stripe.ts",
      "--json",
    ]);

    const firstTurn = await runJsonFromCommand(adapter.adapter.beforeTurn.command);
    const secondTurn = await runJsonFromCommand(adapter.adapter.beforeTurn.command);
    assert.equal(firstTurn.injections.length, 1);
    assert.equal(firstTurn.injections[0].id, "prec_webhook_replay_boundary");
    assert.equal(secondTurn.injections.length, 0);
    assert.equal(secondTurn.suppressedInjections.length, 1);

    await runJsonFromCommand(adapter.adapter.afterValidation.command, {
      schema_version: "precedent.v1",
      hook: "validation.after_run",
      sessionId: adapter.sessionId,
      command: "pnpm test:webhooks",
      exitCode: 0,
      stdout: "passed",
    });
    await runJsonFromCommand(adapter.adapter.afterOutcome.command, {
      schema_version: "precedent.v1",
      hook: "outcome.after_task",
      sessionId: adapter.sessionId,
      success: true,
      status: "success",
      notes: "adapter completed",
    });

    const trace = await runJson(["observe", "--state-dir", stateDir, "--session", adapter.sessionId, "--json"]);
    assert.equal(trace.observed.traceId, "session-demo");

    const report = await runJson(["report", "--state-dir", stateDir, "--json"]);
    const health = report.precedentHealth.find((entry) => entry.id === "prec_webhook_replay_boundary");
    assert.equal(health.injectionCount, 1);
    assert.equal(health.successCount, 1);
  } finally {
    await rm(stateDir, { force: true, recursive: true });
  }
});

async function promoteWebhookPrecedent(stateDir) {
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
  await runJson(["observe", "--state-dir", stateDir, "--trace", traceOut, "--json"]);
}

function runJson(args, stdinJson = null) {
  return runProcess(args, stdinJson).then((result) => {
    if (result.exitCode !== 0) {
      throw new Error(`precedent ${args.join(" ")} failed\n${result.stderr}`);
    }

    return JSON.parse(result.stdout);
  });
}

function runJsonFromCommand(command, stdinJson = null) {
  assert.equal(command[0], "node");
  assert.equal(command[1], "precedent/bin/precedent.mjs");
  return runJson(command.slice(2), stdinJson);
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
