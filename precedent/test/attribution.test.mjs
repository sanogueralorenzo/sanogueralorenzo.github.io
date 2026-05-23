import test from "node:test";
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const repoRoot = resolve(__dirname, "../..");
const cliPath = join(repoRoot, "precedent/bin/precedent.mjs");

test("report and explain attribute task outcomes to injected precedent", async () => {
  const stateDir = await mkdtemp(join(tmpdir(), "precedent-attribution-test-"));

  try {
    await promoteWebhookPrecedent(stateDir);

    await runJson([
      "context",
      "--state-dir",
      stateDir,
      "--task",
      "add webhook handler",
      "--scope",
      "feature:webhooks",
      "--session",
      "success-session",
      "--json",
    ]);
    await runJson(["hook", "--state-dir", stateDir, "--json"], {
      schema_version: "precedent.v1",
      hook: "outcome.after_task",
      sessionId: "success-session",
      success: true,
      notes: "passed",
    });

    await runJson([
      "context",
      "--state-dir",
      stateDir,
      "--task",
      "add webhook handler",
      "--scope",
      "feature:webhooks",
      "--session",
      "failure-session",
      "--json",
    ]);
    await runJson(["hook", "--state-dir", stateDir, "--json"], {
      schema_version: "precedent.v1",
      hook: "outcome.after_task",
      sessionId: "failure-session",
      success: false,
      notes: "failed",
    });

    const report = await runJson(["report", "--state-dir", stateDir, "--json"]);
    const health = report.precedentHealth.find((item) => item.id === "prec_webhook_replay_boundary");
    assert.equal(health.injectionCount, 2);
    assert.equal(health.successCount, 1);
    assert.equal(health.failureCount, 1);
    assert.equal(health.counterexampleCount, 1);
    assert.ok(health.lastCounterexampleAt);
    assert.equal(health.suppressionCount, 0);
    assert.ok(health.lastOutcomeAt);

    const explained = await runJson([
      "explain",
      "--state-dir",
      stateDir,
      "--id",
      "prec_webhook_replay_boundary",
      "--json",
    ]);
    assert.equal(explained.outcomes.successCount, 1);
    assert.equal(explained.outcomes.failureCount, 1);
    assert.equal(explained.counterexamples.length, 1);
    assert.equal(explained.counterexamples[0].type, "attributed_failure");
    assert.equal(explained.counterexamples[0].reason, "failure");
  } finally {
    await rm(stateDir, { force: true, recursive: true });
  }
});

test("suppressed repeated injections do not count as active uses", async () => {
  const stateDir = await mkdtemp(join(tmpdir(), "precedent-attribution-test-"));

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
    assert.equal(second.suppressedInjections.length, 1);

    await runJson(["hook", "--state-dir", stateDir, "--json"], {
      schema_version: "precedent.v1",
      hook: "outcome.after_task",
      sessionId: "demo",
      success: true,
      notes: "passed",
    });

    const report = await runJson(["report", "--state-dir", stateDir, "--json"]);
    const health = report.precedentHealth.find((item) => item.id === "prec_webhook_replay_boundary");
    assert.equal(health.injectionCount, 1);
    assert.equal(health.successCount, 1);
    assert.equal(health.suppressionCount, 1);
  } finally {
    await rm(stateDir, { force: true, recursive: true });
  }
});

test("explicit attributed precedents preserve outcome attribution across sessions", async () => {
  const stateDir = await mkdtemp(join(tmpdir(), "precedent-attribution-test-"));

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
      "--session",
      "loop-session",
      "--json",
    ]);
    assert.equal(context.injections.length, 1);

    await runJson(["hook", "--state-dir", stateDir, "--json"], {
      schema_version: "precedent.v1",
      hook: "outcome.after_task",
      sessionId: "loop-session-attempt-1",
      success: true,
      notes: "passed",
      attributedPrecedents: context.injections.map((injection) => injection.id),
    });

    const report = await runJson(["report", "--state-dir", stateDir, "--json"]);
    const health = report.precedentHealth.find((item) => item.id === "prec_webhook_replay_boundary");
    assert.equal(health.injectionCount, 1);
    assert.equal(health.successCount, 1);
    assert.equal(health.failureCount, 0);
  } finally {
    await rm(stateDir, { force: true, recursive: true });
  }
});

test("delivery receipts preserve outcome attribution across runtime sessions", async () => {
  const stateDir = await mkdtemp(join(tmpdir(), "precedent-attribution-test-"));

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
      "--session",
      "delivery-origin",
      "--event-id",
      "turn-1",
      "--json",
    ]);
    assert.equal(context.injections.length, 1);
    assert.ok(context.deliveryReceipt.deliveryId);

    await runJson(["hook", "--state-dir", stateDir, "--json"], {
      schema_version: "precedent.v1",
      hook: "outcome.after_task",
      sessionId: "delivery-outcome",
      deliveryId: context.deliveryReceipt.deliveryId,
      success: true,
      notes: "passed",
    });

    const report = await runJson(["report", "--state-dir", stateDir, "--json"]);
    const health = report.precedentHealth.find((item) => item.id === "prec_webhook_replay_boundary");
    assert.equal(health.injectionCount, 1);
    assert.equal(health.successCount, 1);
    assert.equal(health.failureCount, 0);
  } finally {
    await rm(stateDir, { force: true, recursive: true });
  }
});

test("stale precedents are suppressed until a later attributed success", async () => {
  const stateDir = await mkdtemp(join(tmpdir(), "precedent-attribution-test-"));

  try {
    await promoteWebhookPrecedent(stateDir);
    await recordAttributedOutcome(stateDir, "failure-one", false);
    await recordAttributedOutcome(stateDir, "failure-two", false);

    const staleReport = await runJson(["report", "--state-dir", stateDir, "--json"]);
    const staleHealth = staleReport.precedentHealth.find((item) => item.id === "prec_webhook_replay_boundary");
    assert.equal(staleHealth.status, "stale");
    assert.equal(staleHealth.failureCount, 2);
    assert.equal(staleHealth.failureRate, 1);
    assert.ok(staleHealth.lastFailureAt);
    assert.ok(staleHealth.retireReasons.some((reason) => reason.includes("2 attributed failure")));

    const suppressed = await runJson([
      "context",
      "--state-dir",
      stateDir,
      "--task",
      "add webhook handler",
      "--scope",
      "feature:webhooks",
      "--json",
    ]);
    assert.deepEqual(suppressed.injections, []);
    assert.equal(suppressed.suppressedInjections.length, 1);
    assert.equal(suppressed.suppressedInjections[0].reason, "stale");
    assert.deepEqual(suppressed.revisionBriefs, []);

    const included = await runJson([
      "context",
      "--state-dir",
      stateDir,
      "--task",
      "add webhook handler",
      "--scope",
      "feature:webhooks",
      "--include-stale",
      "--json",
    ]);
    assert.equal(included.injections.length, 1);

    await recordAttributedOutcome(stateDir, "recovered", true, true);
    const activeReport = await runJson(["report", "--state-dir", stateDir, "--json"]);
    const activeHealth = activeReport.precedentHealth.find((item) => item.id === "prec_webhook_replay_boundary");
    assert.equal(activeHealth.status, "active");
    assert.ok(activeHealth.lastSuccessAt);

    const activeContext = await runJson([
      "context",
      "--state-dir",
      stateDir,
      "--task",
      "add webhook handler",
      "--scope",
      "feature:webhooks",
      "--json",
    ]);
    assert.equal(activeContext.injections.length, 1);
  } finally {
    await rm(stateDir, { force: true, recursive: true });
  }
});

test("retired precedents stay suppressed even when stale precedents are included", async () => {
  const stateDir = await mkdtemp(join(tmpdir(), "precedent-attribution-test-"));

  try {
    await promoteWebhookPrecedent(stateDir);
    await recordAttributedOutcome(stateDir, "failure-one", false);
    await recordAttributedOutcome(stateDir, "failure-two", false);
    await recordAttributedOutcome(stateDir, "failure-three", false, true);
    await recordAttributedOutcome(stateDir, "failure-four", false, true);

    const report = await runJson(["report", "--state-dir", stateDir, "--json"]);
    const health = report.precedentHealth.find((item) => item.id === "prec_webhook_replay_boundary");
    assert.equal(health.status, "retired");
    assert.equal(health.failureCount, 4);

    const context = await runJson([
      "context",
      "--state-dir",
      stateDir,
      "--task",
      "add webhook handler",
      "--scope",
      "feature:webhooks",
      "--include-stale",
      "--json",
    ]);
    assert.deepEqual(context.injections, []);
    assert.equal(context.suppressedInjections.length, 1);
    assert.equal(context.suppressedInjections[0].reason, "retired");
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

async function recordAttributedOutcome(stateDir, sessionId, success, includeStale = false) {
  await runJson([
    "context",
    "--state-dir",
    stateDir,
    "--task",
    "add webhook handler",
    "--scope",
    "feature:webhooks",
    "--session",
    sessionId,
    ...(includeStale ? ["--include-stale"] : []),
    "--json",
  ]);
  await runJson(["hook", "--state-dir", stateDir, "--json"], {
    schema_version: "precedent.v1",
    hook: "outcome.after_task",
    sessionId,
    success,
    notes: success ? "passed" : "failed",
  });
}

function runJson(args, stdinJson = null) {
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
      if (exitCode !== 0) {
        reject(new Error(`precedent ${args.join(" ")} failed\n${stderr}`));
        return;
      }

      resolvePromise(JSON.parse(stdout));
    });

    if (stdinJson) {
      child.stdin.end(`${JSON.stringify(stdinJson)}\n`);
    } else {
      child.stdin.end();
    }
  });
}
