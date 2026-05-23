import test from "node:test";
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { chmod, mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
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
    assert.equal(first.identity.source, "task_hash_fallback");
    assert.equal(first.identity.fallback, true);
    assert.deepEqual(first.adapter.lifecycle.map((phase) => phase.phase), [
      "beforeTurn",
      "beforeEdit",
      "afterValidation",
      "afterDiff",
      "afterReview",
      "beforeRetry",
      "afterRetry",
      "beforeResponse",
      "afterOutcome",
    ]);
    assert.deepEqual(first.adapter.lifecycle.map((phase) => phase.hook), [
      "context.before_turn",
      undefined,
      "validation.after_run",
      "diff.after_edit",
      "review.after_feedback",
      "repair.before_retry",
      "repair.after_retry",
      "finalize.before_response",
      "outcome.after_task",
    ]);
    assert.deepEqual(first.adapter.lifecycle.filter((phase) => phase.required).map((phase) => phase.phase), [
      "beforeTurn",
      "beforeResponse",
      "afterOutcome",
    ]);
    assert.equal(first.adapter.lifecycle[0].injectFrom, "contextBlock");
    assert.equal(first.adapter.lifecycle[5].injectFrom, "repairBlock");
    assert.equal(first.adapter.lifecycle[7].injectFrom, "contextBlock");
    assert.deepEqual(first.adapter.warrant.command.slice(0, 5), [
      "node",
      "precedent/bin/precedent.mjs",
      "warrant",
      "--state-dir",
      stateDir,
    ]);
    assert.ok(first.adapter.warrant.output.includes("warrantId"));
    assert.equal(first.adapter.beforeTurn.injectFrom, "contextBlock");
    assert.equal(first.adapter.beforeTurn.eventId, "$EVENT_ID");
    assert.ok(first.adapter.beforeTurn.output.includes("candidateHints"));
    assert.ok(first.adapter.beforeTurn.output.includes("deliveryReceipt"));
    assert.ok(first.adapter.beforeTurn.output.includes("deduped"));
    assert.equal(first.adapter.beforeTurn.failurePolicy, "fail_open");
    assert.deepEqual(first.adapter.afterValidation.stdin.hook, "validation.after_run");
    assert.equal(first.adapter.afterValidation.stdin.eventId, "$EVENT_ID");
    assert.equal(first.adapter.afterValidation.stdin.deliveryId, "$DELIVERY_ID");
    assert.equal(first.adapter.afterValidation.stdin.warrantId, "$WARRANT_ID");
    assert.equal(first.adapter.afterValidation.stdin.attributedPrecedents, "$ATTRIBUTED_PRECEDENTS");
    assert.ok(first.adapter.afterValidation.output.includes("promotionTrials"));
    assert.deepEqual(first.adapter.afterDiff.stdin.hook, "diff.after_edit");
    assert.equal(first.adapter.afterDiff.stdin.eventId, "$EVENT_ID");
    assert.equal(first.adapter.afterDiff.stdin.deliveryId, "$DELIVERY_ID");
    assert.equal(first.adapter.afterDiff.stdin.warrantId, "$WARRANT_ID");
    assert.equal(first.adapter.afterDiff.stdin.diffSummary, "$DIFF_SUMMARY");
    assert.equal(first.adapter.afterDiff.stdin.unifiedDiff, "$UNIFIED_DIFF");
    assert.equal(first.adapter.afterDiff.stdin.attributedPrecedents, "$ATTRIBUTED_PRECEDENTS");
    assert.deepEqual(first.adapter.afterReview.stdin.hook, "review.after_feedback");
    assert.equal(first.adapter.afterReview.stdin.eventId, "$EVENT_ID");
    assert.deepEqual(first.adapter.afterReview.stdin.sessionId, first.sessionId);
    assert.deepEqual(first.adapter.afterOutcome.stdin.sessionId, first.sessionId);
    assert.equal(first.adapter.afterOutcome.stdin.eventId, "$EVENT_ID");
    assert.equal(first.adapter.afterOutcome.stdin.deliveryId, "$DELIVERY_ID");
    assert.equal(first.adapter.afterOutcome.stdin.warrantId, "$WARRANT_ID");
    assert.equal(first.adapter.afterOutcome.stdin.task, "add webhook handler");
    assert.equal(first.adapter.afterOutcome.stdin.scope, "feature:webhooks");
    assert.deepEqual(first.adapter.afterOutcome.stdin.changedFiles, ["features/webhooks/providers/stripe.ts"]);
    assert.equal(first.adapter.afterOutcome.stdin.attributedPrecedents, "$ATTRIBUTED_PRECEDENTS");
    assert.deepEqual(first.adapter.beforeRetry.stdin.hook, "repair.before_retry");
    assert.equal(first.adapter.beforeRetry.stdin.eventId, "$EVENT_ID");
    assert.equal(first.adapter.beforeRetry.stdin.nextSessionId, "$NEXT_SESSION_ID");
    assert.equal(first.adapter.beforeRetry.injectFrom, "repairBlock");
    assert.deepEqual(first.adapter.afterRetry.stdin.hook, "repair.after_retry");
    assert.equal(first.adapter.afterRetry.stdin.eventId, "$EVENT_ID");
    assert.equal(first.adapter.afterRetry.stdin.repairId, "$REPAIR_ID");
    assert.equal(first.adapter.afterRetry.stdin.repairSessionId, "$REPAIR_SESSION_ID");
    assert.deepEqual(first.adapter.beforeResponse.stdin.hook, "finalize.before_response");
    assert.equal(first.adapter.beforeResponse.stdin.eventId, "$EVENT_ID");
    assert.equal(first.adapter.beforeResponse.stdin.deliveryId, "$DELIVERY_ID");
    assert.equal(first.adapter.beforeResponse.stdin.warrantId, "$WARRANT_ID");
    assert.equal(first.adapter.beforeResponse.injectFrom, "contextBlock");
    assert.ok(first.adapter.beforeResponse.output.includes("decision"));
    assert.ok(first.adapter.beforeResponse.output.includes("nextAction"));
    assert.deepEqual(first.adapter.promotionTrial.command, [
      "node",
      "precedent/bin/precedent.mjs",
      "promotion-trial",
      "--state-dir",
      stateDir,
      "--candidate",
      "$CANDIDATE_ID",
      "--baseline-command",
      "$BASELINE_COMMAND",
      "--trace-out",
      "$TRACE_OUT",
      "--json",
    ]);
    assert.deepEqual(first.adapter.promotionTrial.output, ["ok", "candidateId", "replay", "replayPath", "tracePath", "observed", "promoted", "rejected", "replayAudit"]);
    assert.deepEqual(first.adapter.promotionPending.command, [
      "node",
      "precedent/bin/precedent.mjs",
      "promote-pending",
      "--state-dir",
      stateDir,
      "--json",
    ]);
    assert.ok(first.adapter.promotionPending.output.includes("queue"));

    const report = await runJson(["report", "--state-dir", stateDir, "--json"]);
    assert.equal(report.runtimeWiringHealth.fallbackAttachments, 1);
    assert.equal(report.runtimeWiringHealth.needsAttention, 1);
    assert.deepEqual(report.runtimeWiringHealth.details.fallbackAttachments, [first.sessionId]);
  } finally {
    await rm(stateDir, { force: true, recursive: true });
  }
});

test("attach derives runtime-safe session ids from thread ids", async () => {
  const stateDir = await mkdtemp(join(tmpdir(), "precedent-attach-test-"));

  try {
    const sharedArgs = [
      "attach",
      "--state-dir",
      stateDir,
      "--runtime",
      "codex",
      "--task",
      "add webhook handler",
      "--scope",
      "feature:webhooks",
      "--changed-files",
      "features/webhooks/providers/stripe.ts",
      "--json",
    ];
    const firstThread = await runJson([...sharedArgs, "--thread-id", "thread-a"]);
    const sameThread = await runJson([...sharedArgs, "--thread-id", "thread-a"]);
    const secondThread = await runJson([...sharedArgs, "--thread-id", "thread-b"]);
    const explicitSession = await runJson([...sharedArgs, "--thread-id", "thread-a", "--session", "manual-session"]);

    assert.equal(firstThread.identity.source, "thread_id");
    assert.equal(firstThread.identity.threadId, "thread-a");
    assert.equal(firstThread.identity.fallback, false);
    assert.equal(firstThread.sessionId, sameThread.sessionId);
    assert.notEqual(firstThread.sessionId, secondThread.sessionId);
    assert.equal(explicitSession.sessionId, "manual-session");
    assert.equal(explicitSession.identity.source, "explicit_session");
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
    const retriedTurn = await runJsonFromCommand(adapter.adapter.beforeTurn.command);
    const secondTurn = await runJsonFromCommand(withEventId(adapter.adapter.beforeTurn.command, "turn-2"));
    assert.equal(firstTurn.injections.length, 1);
    assert.equal(firstTurn.injections[0].id, "prec_webhook_replay_boundary");
    assert.equal(retriedTurn.injections.length, 1);
    assert.equal(retriedTurn.deduped, true);
    assert.equal(retriedTurn.recorded, false);
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

test("attach-run thread ids isolate repeated injection suppression", async () => {
  const stateDir = await mkdtemp(join(tmpdir(), "precedent-attach-test-"));

  try {
    await promoteWebhookPrecedent(stateDir);
    const sharedArgs = [
      "attach-run",
      "--state-dir",
      stateDir,
      "--task",
      "add webhook handler",
      "--scope",
      "feature:webhooks",
      "--changed-files",
      "features/webhooks/providers/stripe.ts",
      "--validation-command",
      "node -e \"process.exit(0)\" # pnpm test:webhooks",
      "--json",
    ];
    const firstThread = await runJson([...sharedArgs, "--thread-id", "thread-a"]);
    const repeatedThread = await runJson([...sharedArgs, "--thread-id", "thread-a"]);
    const secondThread = await runJson([...sharedArgs, "--thread-id", "thread-b"]);

    assert.equal(firstThread.identity.source, "thread_id");
    assert.equal(firstThread.beforeTurn.injections.length, 1);
    assert.equal(repeatedThread.beforeTurn.injections.length, 0);
    assert.equal(repeatedThread.beforeTurn.suppressedInjections.length, 1);
    assert.equal(secondThread.beforeTurn.injections.length, 1);

    const report = await runJson(["report", "--state-dir", stateDir, "--json"]);
    const health = report.precedentHealth.find((entry) => entry.id === "prec_webhook_replay_boundary");
    assert.equal(health.injectionCount, 2);
    assert.equal(health.successCount, 2);
  } finally {
    await rm(stateDir, { force: true, recursive: true });
  }
});

test("attach-run executes an ordinary session with automatic attribution", async () => {
  const stateDir = await mkdtemp(join(tmpdir(), "precedent-attach-test-"));

  try {
    await promoteWebhookPrecedent(stateDir);

    const run = await runJson([
      "attach-run",
      "--state-dir",
      stateDir,
      "--session",
      "demo-run",
      "--task",
      "add webhook handler",
      "--scope",
      "feature:webhooks",
      "--changed-files",
      "features/webhooks/providers/stripe.ts",
      "--validation-command",
      "node -e \"process.exit(0)\" # pnpm test:webhooks",
      "--json",
    ]);

    assert.equal(run.schema_version, "precedent.attach_run.v1");
    assert.equal(run.sessionId, "demo-run");
    assert.deepEqual(run.attributedPrecedents, ["prec_webhook_replay_boundary"]);
    assert.equal(run.beforeTurn.injections.length, 1);
    assert.equal(run.warrant.sources.precedentIds[0], "prec_webhook_replay_boundary");
    assert.equal(run.warrant.requiredEvidence[0].command, "pnpm test:webhooks");
    assert.equal(run.validation.validation.exitCode, 0);
    assert.equal(run.finalization.decision, "ready");
    assert.equal(run.finalization.nextAction.type, "respond");
    assert.equal(run.outcome.outcome.success, true);
    assert.equal(run.learning.status, "no_signal");

    const report = await runJson(["report", "--state-dir", stateDir, "--json"]);
    const health = report.precedentHealth.find((entry) => entry.id === "prec_webhook_replay_boundary");
    assert.equal(health.injectionCount, 1);
    assert.equal(health.successCount, 1);
  } finally {
    await rm(stateDir, { force: true, recursive: true });
  }
});

test("attach-run retries are idempotent with an event prefix", async () => {
  const stateDir = await mkdtemp(join(tmpdir(), "precedent-attach-test-"));

  try {
    await promoteWebhookPrecedent(stateDir);
    const args = [
      "attach-run",
      "--state-dir",
      stateDir,
      "--session",
      "demo-run",
      "--event-prefix",
      "delivery-1",
      "--task",
      "add webhook handler",
      "--scope",
      "feature:webhooks",
      "--changed-files",
      "features/webhooks/providers/stripe.ts",
      "--validation-command",
      "node -e \"process.exit(0)\" # pnpm test:webhooks",
      "--json",
    ];

    const first = await runJson(args);
    const retry = await runJson(args);

    assert.equal(first.eventPrefix, "delivery-1");
    assert.equal(first.beforeTurn.recorded, true);
    assert.equal(first.warrant.recorded, true);
    assert.equal(first.validation.recorded, true);
    assert.equal(first.finalization.recorded, true);
    assert.equal(first.outcome.recorded, true);
    assert.equal(retry.beforeTurn.recorded, false);
    assert.equal(retry.beforeTurn.deduped, true);
    assert.equal(retry.warrant.recorded, false);
    assert.equal(retry.warrant.deduped, true);
    assert.equal(retry.validation.recorded, false);
    assert.equal(retry.validation.deduped, true);
    assert.equal(retry.finalization.recorded, false);
    assert.equal(retry.finalization.deduped, true);
    assert.equal(retry.outcome.recorded, false);
    assert.equal(retry.outcome.deduped, true);

    const sessionEvents = await readJsonLines(join(stateDir, "sessions/demo-run.jsonl"));
    assert.equal(sessionEvents.filter((event) => event.eventId === "delivery-1:context.before_turn").length, 1);
    assert.equal(sessionEvents.filter((event) => event.eventId === "delivery-1:warrant.issue").length, 1);
    assert.equal(sessionEvents.filter((event) => event.eventId === "delivery-1:validation.after_run").length, 1);
    assert.equal(sessionEvents.filter((event) => event.eventId === "delivery-1:finalize.before_response").length, 1);
    assert.equal(sessionEvents.filter((event) => event.eventId === "delivery-1:outcome.after_task").length, 1);

    const report = await runJson(["report", "--state-dir", stateDir, "--json"]);
    const health = report.precedentHealth.find((entry) => entry.id === "prec_webhook_replay_boundary");
    assert.equal(health.injectionCount, 1);
    assert.equal(health.successCount, 1);
  } finally {
    await rm(stateDir, { force: true, recursive: true });
  }
});

test("attach-run self-heals missing warrant validation once", async () => {
  const stateDir = await mkdtemp(join(tmpdir(), "precedent-attach-test-"));

  try {
    await promoteWebhookPrecedent(stateDir);
    const fakeBin = await fakePnpmBin(stateDir);
    const args = [
      "attach-run",
      "--state-dir",
      stateDir,
      "--session",
      "missing-required-validation",
      "--event-prefix",
      "self-heal-delivery",
      "--task",
      "add webhook handler",
      "--scope",
      "feature:webhooks",
      "--changed-files",
      "features/webhooks/providers/stripe.ts",
      "--validation-command",
      "node --check precedent/bin/precedent.mjs",
      "--json",
    ];

    const run = await runJson(args, null, { PATH: `${fakeBin}:${process.env.PATH}` });
    const retry = await runJson(args, null, { PATH: `${fakeBin}:${process.env.PATH}` });

    assert.equal(run.validation.validation.exitCode, 0);
    assert.equal(run.selfHealing.status, "recovered");
    assert.equal(run.selfHealing.validations.length, 1);
    assert.equal(run.selfHealing.validations[0].validation.command, "pnpm test:webhooks");
    assert.equal(run.selfHealing.validations[0].validation.exitCode, 0);
    assert.equal(run.selfHealing.finalization.decision, "ready");
    assert.equal(run.finalization.decision, "ready");
    assert.deepEqual(run.finalization.nextAction, { type: "respond" });
    assert.equal(run.outcome.outcome.success, true);
    assert.equal(retry.selfHealing.validations[0].deduped, true);
    assert.equal(retry.selfHealing.finalization.deduped, true);

    const sessionEvents = await readJsonLines(join(stateDir, "sessions/missing-required-validation.jsonl"));
    assert.equal(sessionEvents.filter((event) => event.eventId?.startsWith("self-heal-delivery:validation.after_run:self_heal:")).length, 1);
    assert.equal(sessionEvents.filter((event) => event.eventId === "self-heal-delivery:finalize.before_response:self_heal").length, 1);
  } finally {
    await rm(stateDir, { force: true, recursive: true });
  }
});

test("attach-run does not self-heal unsafe validation commands", async () => {
  const stateDir = await mkdtemp(join(tmpdir(), "precedent-attach-test-"));

  try {
    await promoteWebhookPrecedent(stateDir);
    const precedentsPath = join(stateDir, "precedents.jsonl");
    const precedents = await readJsonLines(precedentsPath);
    precedents[0].guards = precedents[0].guards.map((guard) =>
      guard.type === "required_validation_command"
        ? { ...guard, command: "node -e process.exit(0)" }
        : guard);
    await writeFile(precedentsPath, `${precedents.map((precedent) => JSON.stringify(precedent)).join("\n")}\n`);

    const run = await runJson([
      "attach-run",
      "--state-dir",
      stateDir,
      "--session",
      "unsafe-required-validation",
      "--task",
      "add webhook handler",
      "--scope",
      "feature:webhooks",
      "--changed-files",
      "features/webhooks/providers/stripe.ts",
      "--validation-command",
      "node --check precedent/bin/precedent.mjs",
      "--json",
    ]);

    assert.equal(run.validation.validation.exitCode, 0);
    assert.equal(run.finalization.decision, "validate");
    assert.equal(run.selfHealing.status, "blocked_unsafe_command");
    assert.equal(run.selfHealing.blockedCommands[0].reason, "unsafe_shell_syntax");
    assert.deepEqual(run.selfHealing.validations, []);
    assert.equal(run.outcome.outcome.success, false);
  } finally {
    await rm(stateDir, { force: true, recursive: true });
  }
});

test("attach-run failed validation creates a replay-gated learning candidate", async () => {
  const stateDir = await mkdtemp(join(tmpdir(), "precedent-attach-test-"));

  try {
    await runJson(["init", "--state-dir", stateDir, "--json"]);

    const run = await runJson([
      "attach-run",
      "--state-dir",
      stateDir,
      "--session",
      "failed-run",
      "--event-prefix",
      "failed-delivery",
      "--task",
      "add webhook handler",
      "--scope",
      "feature:webhooks",
      "--changed-files",
      "features/webhooks/providers/stripe.ts",
      "--validation-command",
      "node --check precedent/examples/missing-safe-baseline.mjs",
      "--json",
    ]);

    assert.deepEqual(run.attributedPrecedents, []);
    assert.equal(run.validation.validation.exitCode, 1);
    assert.equal(run.outcome.outcome.success, false);
    assert.equal(run.learning.status, "candidate");
    assert.deepEqual(run.learning.candidateIds, ["cand_feature_webhooks_wrong_test_command"]);
    assert.equal(run.learning.replayRequired, true);

    const candidates = await readJsonLines(join(stateDir, "candidates.jsonl"));
    assert.equal(candidates.length, 1);
    assert.equal(candidates[0].id, "cand_feature_webhooks_wrong_test_command");
  } finally {
    await rm(stateDir, { force: true, recursive: true });
  }
});

test("attach-run auto-promotes queued validation replay plans", async () => {
  const stateDir = await mkdtemp(join(tmpdir(), "precedent-attach-test-"));

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
      "node --check precedent/examples/missing-safe-baseline.mjs",
      "--json",
    ]);

    const run = await runJson([
      "attach-run",
      "--state-dir",
      stateDir,
      "--session",
      "success-run",
      "--event-prefix",
      "success-delivery",
      "--task",
      "add webhook handler",
      "--scope",
      "feature:webhooks",
      "--changed-files",
      "features/webhooks/providers/stripe.ts",
      "--validation-command",
      "node --check precedent/bin/precedent.mjs",
      "--auto-promote",
      "--json",
    ]);

    assert.equal(run.validation.promotionTrials.length, 1);
    assert.equal(run.finalization.decision, "ready");
    assert.equal(run.autoPromotion.processed, 1);
    assert.equal(run.autoPromotion.results[0].status, "promoted");
    assert.equal(run.autoPromotion.queue.completed, 1);

    const retry = await runJson(["promote-pending", "--state-dir", stateDir, "--json"]);
    assert.equal(retry.processed, 0);
    assert.equal(retry.queue.completed, 1);

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
    assert.equal(context.injections[0].id, "cand_feature_webhooks_wrong_test_command");

    const report = await runJson(["report", "--state-dir", stateDir, "--json"]);
    assert.equal(report.promotionTrialQueue.completed, 1);
    const check = await runJson(["check", "--state-dir", stateDir, "--strict", "--json"]);
    assert.equal(check.ok, true);
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

async function fakePnpmBin(stateDir) {
  const binDir = join(stateDir, "fake-bin");
  const pnpmPath = join(binDir, "pnpm");
  await mkdir(binDir, { recursive: true });
  await writeFile(pnpmPath, "#!/bin/sh\nif [ \"$1\" = \"test:webhooks\" ]; then exit 0; fi\nexit 1\n");
  await chmod(pnpmPath, 0o755);
  return binDir;
}

function runJson(args, stdinJson = null, env = {}) {
  return runProcess(args, stdinJson, env).then((result) => {
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

function withEventId(command, eventId) {
  return command.map((part) => part === "$EVENT_ID" ? eventId : part);
}

function runProcess(args, stdinJson = null, env = {}) {
  return new Promise((resolvePromise, reject) => {
    const child = spawn(process.execPath, [cliPath, ...args], {
      cwd: repoRoot,
      env: { ...process.env, ...env },
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
