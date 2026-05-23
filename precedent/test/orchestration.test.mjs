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

test("orchestration.after_idle drains safe promotion trials idempotently", async () => {
  const stateDir = await mkdtemp(join(tmpdir(), "precedent-orchestration-test-"));

  try {
    await runJson(["init", "--state-dir", stateDir, "--json"]);
    const validation = await recordSafePromotionTrial(stateDir, "success");
    assert.equal(validation.promotionTrials.length, 1);

    const reportBefore = await runJson(["report", "--state-dir", stateDir, "--json"]);
    assert.equal(reportBefore.promotionTrialQueue.ready, 1);

    const idle = await hook(stateDir, {
      schema_version: "precedent.v1",
      hook: "orchestration.after_idle",
      sessionId: "idle",
      eventId: "idle-1",
    });
    const repeated = await hook(stateDir, {
      schema_version: "precedent.v1",
      hook: "orchestration.after_idle",
      sessionId: "idle",
      eventId: "idle-1",
    });

    assert.equal(idle.schema_version, "precedent.orchestration.v1");
    assert.equal(idle.recorded, true);
    assert.equal(idle.idle.status, "drained");
    assert.equal(idle.idle.promotion.processed, 1);
    assert.equal(idle.idle.promotion.results[0].status, "promoted");
    assert.equal(idle.idle.promotion.queue.completed, 1);
    assert.equal(repeated.deduped, true);
    assert.equal(repeated.idle.promotion.processed, 1);

    const pending = await runJson(["promote-pending", "--state-dir", stateDir, "--json"]);
    assert.equal(pending.processed, 0);
    assert.equal(pending.queue.completed, 1);

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

    const sessionEvents = await readJsonLines(join(stateDir, "sessions/idle.jsonl"));
    assert.equal(sessionEvents.filter((event) => event.eventId === "idle-1").length, 1);
  } finally {
    await rm(stateDir, { force: true, recursive: true });
  }
});

test("orchestration.after_idle leaves unsafe promotion trials blocked", async () => {
  const stateDir = await mkdtemp(join(tmpdir(), "precedent-orchestration-test-"));

  try {
    await runJson(["init", "--state-dir", stateDir, "--json"]);
    await recordFailedSession(stateDir, "failed", "node -e \"process.exit(1)\"");
    await hook(stateDir, {
      schema_version: "precedent.v1",
      hook: "outcome.after_task",
      sessionId: "failed",
      success: false,
      status: "failure",
      notes: "agent used the wrong test command",
    });
    await hook(stateDir, {
      schema_version: "precedent.v1",
      hook: "context.before_turn",
      sessionId: "passing",
      task: "add webhook handler",
      scope: "feature:webhooks",
      changedFiles: ["features/webhooks/providers/stripe.ts"],
    });
    await hook(stateDir, {
      schema_version: "precedent.v1",
      hook: "validation.after_run",
      sessionId: "passing",
      command: "node -e \"process.exit(0)\"",
      exitCode: 0,
    });

    const idle = await hook(stateDir, {
      schema_version: "precedent.v1",
      hook: "orchestration.after_idle",
      sessionId: "idle",
      eventId: "idle-blocked",
    });

    assert.equal(idle.idle.promotion.processed, 1);
    assert.equal(idle.idle.promotion.results[0].status, "blocked");
    assert.equal(idle.idle.promotion.queue.blocked, 1);

    const events = await readJsonLines(join(stateDir, "events.jsonl"));
    assert.equal(events.some((event) => event.type === "promotion_trial_started"), false);
  } finally {
    await rm(stateDir, { force: true, recursive: true });
  }
});

test("orchestration.after_idle finalizes unfinished sessions", async () => {
  const stateDir = await mkdtemp(join(tmpdir(), "precedent-orchestration-test-"));

  try {
    await promoteWebhookPrecedent(stateDir);
    const warrant = await runJson([
      "warrant",
      "--state-dir",
      stateDir,
      "--session",
      "unfinished",
      "--event-id",
      "warrant-1",
      "--task",
      "add webhook handler",
      "--scope",
      "feature:webhooks",
      "--changed-files",
      "features/webhooks/providers/stripe.ts",
      "--json",
    ]);

    const idle = await hook(stateDir, {
      schema_version: "precedent.v1",
      hook: "orchestration.after_idle",
      sessionId: "unfinished",
      eventId: "idle-finalize",
      warrantId: warrant.warrantId,
    });
    const repeated = await hook(stateDir, {
      schema_version: "precedent.v1",
      hook: "orchestration.after_idle",
      sessionId: "unfinished",
      eventId: "idle-finalize",
      warrantId: warrant.warrantId,
    });

    assert.equal(idle.idle.finalization.status, "blocked");
    assert.equal(idle.idle.finalization.decision, "validate");
    assert.deepEqual(idle.idle.finalization.nextAction, {
      type: "run_validation",
      commands: ["pnpm test:webhooks"],
      followUpHook: "validation.after_run",
      refinalize: true,
    });
    assert.match(idle.idle.finalization.contextBlock, /Required command: pnpm test:webhooks/u);
    assert.equal(idle.idle.finalization.recorded, true);
    assert.equal(idle.idle.finalization.queuedAction.status, "ready");
    assert.equal(idle.idle.finalization.queuedAction.actionType, "run_validation");
    assert.deepEqual(idle.idle.finalization.queuedAction.commands, ["pnpm test:webhooks"]);
    assert.equal(repeated.deduped, true);
    assert.equal(repeated.idle.finalization.recorded, true);
    assert.equal(repeated.idle.finalization.queuedAction.deduped, false);

    const sessionEvents = await readJsonLines(join(stateDir, "sessions/unfinished.jsonl"));
    assert.equal(sessionEvents.filter((event) => event.eventId === "idle-finalize:finalize.before_response").length, 1);
    assert.equal(sessionEvents.filter((event) => event.hook === "finalize.before_response").length, 1);
    const nextActions = await readJsonLines(join(stateDir, "next_actions.jsonl"));
    assert.equal(nextActions.length, 1);
    assert.equal(nextActions[0].status, "ready");
    const report = await runJson(["report", "--state-dir", stateDir, "--json"]);
    assert.equal(report.nextActionQueue.ready, 1);
  } finally {
    await rm(stateDir, { force: true, recursive: true });
  }
});

test("next-action claim and completion receipts are leased and reported", async () => {
  const stateDir = await mkdtemp(join(tmpdir(), "precedent-orchestration-test-"));

  try {
    await promoteWebhookPrecedent(stateDir);
    const warrant = await runJson([
      "warrant",
      "--state-dir",
      stateDir,
      "--session",
      "claimable",
      "--event-id",
      "warrant-1",
      "--task",
      "add webhook handler",
      "--scope",
      "feature:webhooks",
      "--changed-files",
      "features/webhooks/providers/stripe.ts",
      "--json",
    ]);
    await hook(stateDir, {
      schema_version: "precedent.v1",
      hook: "orchestration.after_idle",
      sessionId: "claimable",
      eventId: "idle-claimable",
      warrantId: warrant.warrantId,
    });

    const claim = await runJson([
      "next-action",
      "--state-dir",
      stateDir,
      "--claim",
      "--claimed-by",
      "runtime-host",
      "--json",
    ]);
    const empty = await runJson(["next-action", "--state-dir", stateDir, "--claim", "--json"]);

    assert.equal(claim.status, "claimed");
    assert.equal(claim.action.status, "ready");
    assert.equal(claim.action.actionType, "run_validation");
    assert.equal(claim.claim.status, "running");
    assert.equal(claim.claim.claimedBy, "runtime-host");
    assert.match(claim.claim.runId, /^next_run_/u);
    assert.equal(empty.status, "none");
    assert.equal(empty.reason, "no_ready_actions");

    const running = await runJson(["report", "--state-dir", stateDir, "--json"]);
    assert.equal(running.nextActionQueue.running, 1);

    await hook(stateDir, {
      schema_version: "precedent.v1",
      hook: "validation.after_run",
      sessionId: "claimable",
      eventId: "next-action-validation",
      command: "pnpm test:webhooks",
      exitCode: 0,
    });
    const completed = await runJson([
      "next-action",
      "--state-dir",
      stateDir,
      "--complete",
      "--id",
      claim.action.id,
      "--run-id",
      claim.claim.runId,
      "--evidence-event-id",
      "next-action-validation",
      "--json",
    ]);
    assert.equal(completed.status, "completed");
    assert.equal(completed.receipt.runId, claim.claim.runId);
    assert.equal(completed.receipt.evidenceStatus, "accepted");
    assert.equal(completed.receipt.evidence.exitCode, 0);

    const report = await runJson(["report", "--state-dir", stateDir, "--json"]);
    assert.equal(report.nextActionQueue.completed, 1);
    assert.equal(report.nextActionQueue.running, 0);
    assert.equal(report.nextActionQueue.items[0].evidenceEventId, "next-action-validation");
  } finally {
    await rm(stateDir, { force: true, recursive: true });
  }
});

test("orchestration.after_idle re-surfaces blocked finalization without duplicating it", async () => {
  const stateDir = await mkdtemp(join(tmpdir(), "precedent-orchestration-test-"));

  try {
    await promoteWebhookPrecedent(stateDir);
    const warrant = await runJson([
      "warrant",
      "--state-dir",
      stateDir,
      "--session",
      "blocked-finalization",
      "--event-id",
      "warrant-1",
      "--task",
      "add webhook handler",
      "--scope",
      "feature:webhooks",
      "--changed-files",
      "features/webhooks/providers/stripe.ts",
      "--json",
    ]);
    const blocked = await hook(stateDir, {
      schema_version: "precedent.v1",
      hook: "finalize.before_response",
      sessionId: "blocked-finalization",
      eventId: "finalize-1",
      warrantId: warrant.warrantId,
    });
    const idle = await hook(stateDir, {
      schema_version: "precedent.v1",
      hook: "orchestration.after_idle",
      sessionId: "blocked-finalization",
      eventId: "idle-1",
      warrantId: warrant.warrantId,
    });

    assert.equal(blocked.decision, "validate");
    assert.equal(idle.idle.finalization.status, "blocked");
    assert.equal(idle.idle.finalization.reason, "blocked_finalization_pending");
    assert.deepEqual(idle.idle.finalization.nextAction, blocked.nextAction);
    assert.equal(idle.idle.finalization.queuedAction.status, "ready");
    assert.equal(idle.idle.finalization.queuedAction.deduped, false);
    assert.equal(idle.idle.finalization.recorded, false);

    const sessionEvents = await readJsonLines(join(stateDir, "sessions/blocked-finalization.jsonl"));
    assert.equal(sessionEvents.filter((event) => event.hook === "finalize.before_response").length, 1);
    const nextActions = await readJsonLines(join(stateDir, "next_actions.jsonl"));
    assert.equal(nextActions.length, 1);

    await hook(stateDir, {
      schema_version: "precedent.v1",
      hook: "validation.after_run",
      sessionId: "blocked-finalization",
      eventId: "validation-1",
      warrantId: warrant.warrantId,
      command: "pnpm test:webhooks",
      exitCode: 0,
    });
    const ready = await hook(stateDir, {
      schema_version: "precedent.v1",
      hook: "finalize.before_response",
      sessionId: "blocked-finalization",
      eventId: "finalize-2",
      warrantId: warrant.warrantId,
    });
    const report = await runJson(["report", "--state-dir", stateDir, "--json"]);

    assert.equal(ready.decision, "ready");
    assert.equal(report.finalizationHealth.pending, 0);
    assert.equal(report.finalizationHealth.bypassed, 0);
  } finally {
    await rm(stateDir, { force: true, recursive: true });
  }
});

test("orchestration.after_idle skips already finalized sessions", async () => {
  const stateDir = await mkdtemp(join(tmpdir(), "precedent-orchestration-test-"));

  try {
    await runJson(["init", "--state-dir", stateDir, "--json"]);
    await hook(stateDir, {
      schema_version: "precedent.v1",
      hook: "context.before_turn",
      sessionId: "done",
      task: "add webhook handler",
      scope: "feature:webhooks",
      changedFiles: ["features/webhooks/providers/stripe.ts"],
    });
    await hook(stateDir, {
      schema_version: "precedent.v1",
      hook: "finalize.before_response",
      sessionId: "done",
      eventId: "finalize-done",
    });

    const idle = await hook(stateDir, {
      schema_version: "precedent.v1",
      hook: "orchestration.after_idle",
      sessionId: "done",
      eventId: "idle-done",
    });

    assert.equal(idle.idle.finalization.status, "not_needed");
    assert.equal(idle.idle.finalization.reason, "already_finalized");

    const sessionEvents = await readJsonLines(join(stateDir, "sessions/done.jsonl"));
    assert.equal(sessionEvents.filter((event) => event.hook === "finalize.before_response").length, 1);
  } finally {
    await rm(stateDir, { force: true, recursive: true });
  }
});

async function recordSafePromotionTrial(stateDir, sessionId) {
  await recordFailedSession(stateDir, "failed", "node --check precedent/examples/missing-safe-baseline.mjs");
  await hook(stateDir, {
    schema_version: "precedent.v1",
    hook: "outcome.after_task",
    sessionId: "failed",
    success: false,
    status: "failure",
    notes: "agent used the wrong test command",
  });
  await hook(stateDir, {
    schema_version: "precedent.v1",
    hook: "context.before_turn",
    sessionId,
    task: "add webhook handler",
    scope: "feature:webhooks",
    changedFiles: ["features/webhooks/providers/stripe.ts"],
  });
  return hook(stateDir, {
    schema_version: "precedent.v1",
    hook: "validation.after_run",
    sessionId,
    eventId: `${sessionId}-validation`,
    command: "node --check precedent/bin/precedent.mjs",
    exitCode: 0,
  });
}

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

async function recordFailedSession(stateDir, sessionId, command) {
  await hook(stateDir, {
    schema_version: "precedent.v1",
    hook: "context.before_turn",
    sessionId,
    task: "add webhook handler",
    scope: "feature:webhooks",
    changedFiles: ["features/webhooks/providers/stripe.ts"],
  });
  await hook(stateDir, {
    schema_version: "precedent.v1",
    hook: "validation.after_run",
    sessionId,
    command,
    exitCode: 1,
    stderr: "wrong test command",
  });
}

function hook(stateDir, event) {
  return runJson(["hook", "--state-dir", stateDir, "--json"], event);
}

async function readJsonLines(path) {
  const content = await readFile(path, "utf8");
  return content
    .split("\n")
    .filter((line) => line.trim().length > 0)
    .map((line) => JSON.parse(line));
}

function runJson(args, stdinJson = null) {
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
      resolvePromise({ exitCode, stdout, stderr });
    });

    if (stdinJson) {
      child.stdin.end(`${JSON.stringify(stdinJson)}\n`);
    } else {
      child.stdin.end();
    }
  });
}
