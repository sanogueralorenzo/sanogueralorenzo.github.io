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

test("context exports promoted precedent in a stable JSON envelope", async () => {
  const stateDir = await mkdtemp(join(tmpdir(), "precedent-context-test-"));

  try {
    await promoteWebhookPrecedent(stateDir);

    const context = await runJson([
      "context",
      "--state-dir",
      stateDir,
      "--task",
      "add webhook handler",
      "--scope",
      "feature:webhooks",
      "--changed-files",
      "features/webhooks/providers/stripe.ts",
      "--json",
    ]);

    assert.equal(context.schema_version, "precedent.context.v1");
    assert.match(context.contextBlock, /Precedent:/u);
    assert.equal(context.injections.length, 1);
    assert.equal(context.injections[0].id, "prec_webhook_replay_boundary");
    assert.ok(context.injections[0].matchReasons.length > 0);
    assert.equal(context.deliveryReceipt, null);
    assert.deepEqual(context.suppressedInjections, []);
    assert.equal(context.source.command, "context");
  } finally {
    await rm(stateDir, { force: true, recursive: true });
  }
});

test("context supports task files and markdown output", async () => {
  const stateDir = await mkdtemp(join(tmpdir(), "precedent-context-test-"));

  try {
    await promoteWebhookPrecedent(stateDir);

    const taskFile = join(stateDir, "task.txt");
    await writeFile(taskFile, "add webhook handler");
    const result = await runProcess([
      "context",
      "--state-dir",
      stateDir,
      "--task-file",
      taskFile,
      "--scope",
      "feature:webhooks",
      "--format",
      "markdown",
    ]);

    assert.equal(result.exitCode, 0);
    assert.match(result.stdout, /^Precedent:/u);
    assert.doesNotMatch(result.stdout, /schema_version/u);
  } finally {
    await rm(stateDir, { force: true, recursive: true });
  }
});

test("context and inject suppress text-only unanchored precedent matches", async () => {
  const stateDir = await mkdtemp(join(tmpdir(), "precedent-context-test-"));

  try {
    await promoteWebhookPrecedent(stateDir);

    const genericTask = "run test webhooks provider boundary nullable payload helpers";
    const context = await runJson([
      "context",
      "--state-dir",
      stateDir,
      "--task",
      genericTask,
      "--json",
    ]);

    assert.equal(context.contextBlock, "");
    assert.deepEqual(context.injections, []);
    assert.equal(context.suppressedInjections[0].reason, "applicability_unanchored");
    assert.equal(context.suppressedInjections[0].applicabilityReceipt.status, "unanchored");

    const inject = await runJson([
      "inject",
      "--state-dir",
      stateDir,
      "--task",
      genericTask,
      "--json",
    ]);
    assert.deepEqual(inject.injections, []);
    assert.equal(inject.suppressedInjections[0].reason, "applicability_unanchored");

    const warrant = await runJson([
      "warrant",
      "--state-dir",
      stateDir,
      "--session",
      "generic-session",
      "--event-id",
      "generic-warrant",
      "--task",
      genericTask,
      "--json",
    ]);
    assert.deepEqual(warrant.sources.precedentIds, []);
    assert.deepEqual(warrant.requiredEvidence, []);
  } finally {
    await rm(stateDir, { force: true, recursive: true });
  }
});

test("context suppresses repeated session injections", async () => {
  const stateDir = await mkdtemp(join(tmpdir(), "precedent-context-test-"));

  try {
    await promoteWebhookPrecedent(stateDir);

    const args = [
      "context",
      "--state-dir",
      stateDir,
      "--task",
      "add webhook handler",
      "--scope",
      "feature:webhooks",
      "--session",
      "demo",
      "--json",
    ];
    const first = await runJson(args);
    const second = await runJson(args);

    assert.equal(first.injections.length, 1);
    assert.deepEqual(first.suppressedInjections, []);
    assert.deepEqual(second.injections, []);
    assert.equal(second.suppressedInjections.length, 1);
    assert.equal(second.contextBlock, "");
  } finally {
    await rm(stateDir, { force: true, recursive: true });
  }
});

test("context emits stable delivery receipts for runtime attribution", async () => {
  const stateDir = await mkdtemp(join(tmpdir(), "precedent-context-test-"));

  try {
    await promoteWebhookPrecedent(stateDir);

    const args = [
      "context",
      "--state-dir",
      stateDir,
      "--task",
      "add webhook handler",
      "--scope",
      "feature:webhooks",
      "--session",
      "delivery-session",
      "--event-id",
      "turn-1",
      "--json",
    ];
    const first = await runJson(args);
    const retried = await runJson(args);

    assert.equal(first.injections.length, 1);
    assert.match(first.deliveryReceipt.deliveryId, /^del_[a-f0-9]+$/u);
    assert.deepEqual(first.deliveryReceipt.injectedPrecedentIds, ["prec_webhook_replay_boundary"]);
    assert.equal(first.deliveryReceipt.sessionId, "delivery-session");
    assert.equal(first.deliveryReceipt.eventId, "turn-1");
    assert.equal(retried.deduped, true);
    assert.deepEqual(retried.deliveryReceipt, first.deliveryReceipt);
  } finally {
    await rm(stateDir, { force: true, recursive: true });
  }
});

test("context excludes rejected precedent", async () => {
  const stateDir = await mkdtemp(join(tmpdir(), "precedent-context-test-"));

  try {
    await runJson(["init", "--state-dir", stateDir, "--json"]);
    await runJson([
      "observe",
      "--state-dir",
      stateDir,
      "--trace",
      "precedent/examples/webhook-trace-no-improvement.json",
      "--json",
    ]);

    const context = await runJson([
      "context",
      "--state-dir",
      stateDir,
      "--task",
      "add webhook handler",
      "--scope",
      "feature:webhooks",
      "--json",
    ]);

    assert.equal(context.contextBlock, "");
    assert.deepEqual(context.injections, []);
  } finally {
    await rm(stateDir, { force: true, recursive: true });
  }
});

test("context surfaces non-injectable candidate hints", async () => {
  const stateDir = await mkdtemp(join(tmpdir(), "precedent-context-test-"));

  try {
    await runJson(["init", "--state-dir", stateDir, "--json"]);
    await runJson([
      "attach-run",
      "--state-dir",
      stateDir,
      "--session",
      "failed-run",
      "--task",
      "add webhook handler",
      "--scope",
      "feature:webhooks",
      "--changed-files",
      "features/webhooks/providers/stripe.ts",
      "--validation-command",
      "node -e \"console.error('wrong test command'); process.exit(1)\"",
      "--json",
    ]);

    const context = await runJson([
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
      "next-run",
      "--json",
    ]);

    assert.equal(context.contextBlock, "");
    assert.deepEqual(context.injections, []);
    assert.equal(context.candidateHints.length, 1);
    assert.equal(context.candidateHints[0].candidateId, "cand_feature_webhooks_wrong_test_command");
    assert.equal(context.candidateHints[0].replayRequired, true);
    assert.deepEqual(context.candidateHints[0].failureTypes, ["wrong_test_command"]);
    assert.deepEqual(context.candidateHints[0].sourceTraces, ["session-failed-run"]);
    assert.equal(context.candidateHints[0].promotionTrial.readiness, "needs_rerun_command");
    assert.ok(context.candidateHints[0].promotionTrial.command.includes("promotion-trial"));
    assert.match(context.candidateHints[0].artifact.path, /artifacts\/cand_feature_webhooks_wrong_test_command\/SKILL\.md$/u);
    assert.ok(context.candidateHints[0].artifact.command.includes("artifact"));
    assert.equal(context.candidateHints[0].artifact.injectable, false);

    const eventFile = join(stateDir, "before-turn.json");
    await writeFile(eventFile, JSON.stringify({
      schema_version: "precedent.v1",
      hook: "context.before_turn",
      sessionId: "hook-run",
      task: "add webhook handler",
      scope: "feature:webhooks",
      changedFiles: ["features/webhooks/providers/stripe.ts"],
    }));
    const hook = await runJson(["hook", "--state-dir", stateDir, "--event-file", eventFile, "--json"]);
    assert.equal(hook.contextBlock, "");
    assert.deepEqual(hook.injections, []);
    assert.equal(hook.candidateHints.length, 1);
    assert.equal(hook.candidateHints[0].candidateId, "cand_feature_webhooks_wrong_test_command");

    const report = await runJson(["report", "--state-dir", stateDir, "--json"]);
    assert.equal(report.candidateHintQueue.total, 1);
    assert.equal(report.candidateHintQueue.blocked, 1);
    assert.equal(report.candidateHintQueue.items[0].candidateId, "cand_feature_webhooks_wrong_test_command");
    assert.match(report.candidateHintQueue.items[0].artifact.path, /artifacts\/cand_feature_webhooks_wrong_test_command\/SKILL\.md$/u);

    const generic = await runJson([
      "context",
      "--state-dir",
      stateDir,
      "--task",
      "wrong test command webhook provider boundary",
      "--json",
    ]);
    assert.deepEqual(generic.candidateHints, []);
  } finally {
    await rm(stateDir, { force: true, recursive: true });
  }
});

test("context and inject suppress promoted precedents with failed replay audit", async () => {
  const stateDir = await mkdtemp(join(tmpdir(), "precedent-context-test-"));

  try {
    await promoteWebhookPrecedent(stateDir);
    const precedents = await readJsonLines(join(stateDir, "precedents.jsonl"));
    const replayPath = precedents[0].replay.path;
    const replay = JSON.parse(await readFile(replayPath, "utf8"));
    replay.promotion.baseline_failures = 9;
    await writeFile(replayPath, `${JSON.stringify(replay, null, 2)}\n`);

    const context = await runJson([
      "context",
      "--state-dir",
      stateDir,
      "--task",
      "add webhook handler",
      "--scope",
      "feature:webhooks",
      "--json",
    ]);
    assert.equal(context.contextBlock, "");
    assert.deepEqual(context.injections, []);
    assert.equal(context.suppressedInjections[0].reason, "replay_audit_failed");
    assert.equal(context.suppressedInjections[0].replayAuditStatus, "hash_mismatch");

    const inject = await runJson([
      "inject",
      "--state-dir",
      stateDir,
      "--task",
      "add webhook handler",
      "--scope",
      "feature:webhooks",
      "--json",
    ]);
    assert.deepEqual(inject.injections, []);
    assert.equal(inject.suppressedInjections[0].reason, "replay_audit_failed");
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

function runProcess(args) {
  return new Promise((resolvePromise, reject) => {
    const child = spawn(process.execPath, [cliPath, ...args], {
      cwd: repoRoot,
      stdio: ["ignore", "pipe", "pipe"],
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
  });
}
