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

test("replay emits verified evidence that can promote and inject precedent", async () => {
  const stateDir = await mkdtemp(join(tmpdir(), "precedent-replay-test-"));

  try {
    await runPrecedent(["init", "--state-dir", stateDir, "--json"]);

    const beforePromotion = await runPrecedent([
      "hook",
      "before-turn",
      "--state-dir",
      stateDir,
      "--task",
      "add another webhook handler",
      "--scope",
      "feature:webhooks",
      "--json",
    ]);
    assert.equal(beforePromotion.injected, false);
    assert.deepEqual(beforePromotion.injections, []);

    const traceOut = join(stateDir, "webhook-replay-trace.json");
    const replay = await runPrecedent([
      "replay",
      "--state-dir",
      stateDir,
      "--case",
      "precedent/examples/replay/webhook-case.json",
      "--trace-out",
      traceOut,
      "--json",
    ]);
    assert.equal(replay.replay.improved, true);
    assert.equal(replay.trace.replay.verified, true);
    assert.equal(replay.trace.replay.promotion.baseline_failures, 1);
    assert.equal(replay.trace.replay.promotion.rerun_failures, 0);

    const observed = await runPrecedent([
      "observe",
      "--state-dir",
      stateDir,
      "--trace",
      traceOut,
      "--json",
    ]);
    assert.equal(observed.observed.promotionStatus, "promoted");
    assert.equal(observed.promoted.promotion_status, "promoted");
    assert.equal(observed.promoted.promotion.baseline_failures, 1);
    assert.equal(observed.promoted.promotion.rerun_failures, 0);
    assert.equal(observed.promoted.replay.id, "webhook-replay-improves");
    assert.equal(observed.promoted.replay.baseline_failures, 1);
    assert.equal(observed.promoted.replay.rerun_failures, 0);
    assert.equal(observed.promoted.replay.baseline_exit_code, 1);
    assert.equal(observed.promoted.replay.rerun_exit_code, 0);
    assert.match(observed.promoted.replay.artifact_sha256, /^[a-f0-9]{64}$/u);
    assert.equal(observed.observed.promotionAction, "created");

    const observedAgain = await runPrecedent([
      "observe",
      "--state-dir",
      stateDir,
      "--trace",
      traceOut,
      "--json",
    ]);
    assert.equal(observedAgain.observed.promotionAction, "unchanged");

    const afterPromotion = await runPrecedent([
      "hook",
      "before-turn",
      "--state-dir",
      stateDir,
      "--task",
      "add another webhook handler",
      "--scope",
      "feature:webhooks",
      "--changed-files",
      "features/webhooks/providers/refund.ts",
      "--json",
    ]);
    assert.equal(afterPromotion.injected, true);
    assert.equal(afterPromotion.injections.length, 1);
    assert.equal(afterPromotion.injections[0].id, "prec_webhook_replay_boundary");
    assert.deepEqual(afterPromotion.injections[0].matchReasons.map((reason) => reason.type), [
      "text_overlap",
      "scope_match",
      "path_match",
    ]);
    assert.equal(afterPromotion.injections[0].matchReasons[1].scope, "feature:webhooks");
    assert.match(afterPromotion.block, /Precedent:/u);

    const explained = await runPrecedent([
      "explain",
      "--state-dir",
      stateDir,
      "--id",
      "prec_webhook_replay_boundary",
      "--json",
    ]);
    assert.equal(explained.promotionStatus, "promoted");
    assert.match(explained.promotionReason, /1 baseline failure\(s\) to 0 rerun failure\(s\)/u);
    assert.equal(explained.source.traceId, "webhook-replay-improves-replay");
    assert.equal(explained.source.replayId, "webhook-replay-improves");
    assert.equal(explained.replay.failureDelta, 1);
    assert.equal(explained.replay.receipt.id, "webhook-replay-improves");
    assert.equal(explained.matching.scope, "feature:webhooks");
    assert.deepEqual(explained.matching.paths, ["features/webhooks", "webhooks/providers"]);
    assert.ok(explained.evidence.includes("replay: baseline exited 1"));
    assert.equal(explained.injections.length, 1);
    assert.equal(explained.injections[0].task, "add another webhook handler");

    const report = await runPrecedent(["report", "--state-dir", stateDir, "--json"]);
    assert.equal(report.replays, 1);
    assert.equal(report.precedents, 1);
    assert.equal(report.auditHealth.verified, 1);
    assert.equal(report.auditHealth.needsAttention, 0);
    assert.equal(report.replayAudit[0].precedentId, "prec_webhook_replay_boundary");
    assert.equal(report.replayAudit[0].status, "verified");
    assert.equal(report.replayAudit[0].failureDelta, 1);
    assert.equal(report.replayAudit[0].expectedSha256, observed.promoted.replay.artifact_sha256);
    assert.equal(report.replayAudit[0].actualSha256, observed.promoted.replay.artifact_sha256);

    const precedents = await readJsonLines(join(stateDir, "precedents.jsonl"));
    assert.equal(precedents.length, 1);
    assert.equal(precedents[0].id, "prec_webhook_replay_boundary");
  } finally {
    await rm(stateDir, { force: true, recursive: true });
  }
});

test("observing an improved precedent id updates the existing ledger record", async () => {
  const stateDir = await mkdtemp(join(tmpdir(), "precedent-replay-test-"));

  try {
    await runPrecedent(["init", "--state-dir", stateDir, "--json"]);

    const traceOut = join(stateDir, "webhook-replay-trace.json");
    await runPrecedent([
      "replay",
      "--state-dir",
      stateDir,
      "--case",
      "precedent/examples/replay/webhook-case.json",
      "--trace-out",
      traceOut,
      "--json",
    ]);
    const firstObserved = await runPrecedent([
      "observe",
      "--state-dir",
      stateDir,
      "--trace",
      traceOut,
      "--json",
    ]);

    const betterTrace = JSON.parse(await readFile(traceOut, "utf8"));
    betterTrace.id = "webhook-replay-better";
    betterTrace.replay.promotion.baseline_failures = 2;
    betterTrace.precedent.evidence.push("replay: second baseline failure avoided");
    const betterTraceOut = join(stateDir, "webhook-replay-better-trace.json");
    await writeFile(betterTraceOut, JSON.stringify(betterTrace, null, 2));

    const observedBetter = await runPrecedent([
      "observe",
      "--state-dir",
      stateDir,
      "--trace",
      betterTraceOut,
      "--json",
    ]);
    assert.equal(observedBetter.observed.promotionAction, "updated");
    assert.equal(observedBetter.promoted.promotion.baseline_failures, 2);

    const precedents = await readJsonLines(join(stateDir, "precedents.jsonl"));
    assert.equal(precedents.length, 1);
    assert.equal(precedents[0].promotion.baseline_failures, 2);
    assert.ok(precedents[0].evidence.includes("replay: second baseline failure avoided"));
    assert.equal(precedents[0].created_at, firstObserved.promoted.created_at);
    assert.equal(precedents[0].updated_at, observedBetter.promoted.updated_at);
  } finally {
    await rm(stateDir, { force: true, recursive: true });
  }
});

test("replay can promote a ledger candidate without a handcrafted case file", async () => {
  const stateDir = await mkdtemp(join(tmpdir(), "precedent-replay-test-"));

  try {
    await runPrecedent(["init", "--state-dir", stateDir, "--json"]);
    await writeFile(join(stateDir, "candidates.jsonl"), `${JSON.stringify({
      id: "cand_webhook_replacement",
      status: "candidate",
      scope: "feature:webhooks",
      trigger: "add another webhook handler",
      lesson: "Use the replacement webhook boundary from the successful repair session.",
      artifact: "skill",
      paths: ["features/webhooks"],
      source_traces: ["session-success"],
      failure_types: ["repair_efficacy_replacement"],
      evidence: ["successful validation: node -e \"process.exit(0)\" exited 0"],
      injection: "Use the successful webhook repair boundary before editing webhook handlers.",
      promotion_required: "Replay before promotion.",
    })}\n`);

    const traceOut = join(stateDir, "candidate-replay-trace.json");
    const replay = await runPrecedent([
      "replay",
      "--state-dir",
      stateDir,
      "--candidate",
      "cand_webhook_replacement",
      "--baseline-command",
      "node -e \"process.exit(1)\"",
      "--trace-out",
      traceOut,
      "--json",
    ]);

    assert.equal(replay.replay.candidateId, "cand_webhook_replacement");
    assert.equal(replay.replay.improved, true);
    assert.match(replay.trace.replay.artifact_sha256, /^[a-f0-9]{64}$/u);
    assert.equal(replay.trace.replay.baseline.exitCode, 1);
    assert.equal(replay.trace.replay.rerun.exitCode, 0);
    assert.equal(replay.trace.precedent.id, "cand_webhook_replacement");
    assert.equal(replay.trace.replay.promotion.baseline_failures, 1);
    assert.equal(replay.trace.replay.promotion.rerun_failures, 0);

    const observed = await runPrecedent([
      "observe",
      "--state-dir",
      stateDir,
      "--trace",
      traceOut,
      "--json",
    ]);
    assert.equal(observed.observed.promotionStatus, "promoted");
    assert.equal(observed.promoted.id, "cand_webhook_replacement");
    assert.equal(observed.promoted.replay.id, "candidate-cand_webhook_replacement");
    assert.equal(observed.promoted.replay.baseline_exit_code, 1);
    assert.equal(observed.promoted.replay.rerun_exit_code, 0);
    assert.match(observed.promoted.replay.artifact_sha256, /^[a-f0-9]{64}$/u);

    const injected = await runPrecedent([
      "context",
      "--state-dir",
      stateDir,
      "--task",
      "add another webhook handler",
      "--scope",
      "feature:webhooks",
      "--changed-files",
      "features/webhooks/provider.ts",
      "--json",
    ]);
    assert.equal(injected.injections[0].id, "cand_webhook_replacement");
  } finally {
    await rm(stateDir, { force: true, recursive: true });
  }
});

test("replay without improvement is observed but not promoted", async () => {
  const stateDir = await mkdtemp(join(tmpdir(), "precedent-replay-test-"));

  try {
    await runPrecedent(["init", "--state-dir", stateDir, "--json"]);

    const traceOut = join(stateDir, "webhook-no-improvement-trace.json");
    const replay = await runPrecedent([
      "replay",
      "--state-dir",
      stateDir,
      "--case",
      "precedent/examples/replay/webhook-no-improvement-case.json",
      "--trace-out",
      traceOut,
      "--json",
    ]);
    assert.equal(replay.replay.improved, false);
    assert.equal(replay.trace.replay.promotion.baseline_failures, 1);
    assert.equal(replay.trace.replay.promotion.rerun_failures, 1);

    const observed = await runPrecedent([
      "observe",
      "--state-dir",
      stateDir,
      "--trace",
      traceOut,
      "--json",
    ]);
    assert.equal(observed.observed.promotionStatus, "rejected");
    assert.equal(observed.promoted, null);
    assert.deepEqual(observed.rejected.reasons, [
      "precedent.promotion must show baseline_failures greater than rerun_failures",
    ]);

    const explained = await runPrecedent([
      "explain",
      "--state-dir",
      stateDir,
      "--id",
      "prec_webhook_replay_no_improvement",
      "--json",
    ]);
    assert.equal(explained.promotionStatus, "rejected");
    assert.match(explained.promotionReason, /baseline_failures greater than rerun_failures/u);
    assert.equal(explained.replay.baselineFailures, 1);
    assert.equal(explained.replay.rerunFailures, 1);
    assert.deepEqual(explained.injections, []);
    assert.equal(explained.rejectionEvents.length, 1);

    const inject = await runPrecedent([
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
  } finally {
    await rm(stateDir, { force: true, recursive: true });
  }
});

test("observe rejects promoted traces without typed replay receipts", async () => {
  const stateDir = await mkdtemp(join(tmpdir(), "precedent-replay-test-"));

  try {
    await runPrecedent(["init", "--state-dir", stateDir, "--json"]);
    const traceOut = join(stateDir, "string-evidence-trace.json");
    await writeFile(traceOut, JSON.stringify({
      schema_version: "precedent.v1",
      id: "string-evidence-trace",
      task: "add webhook handler",
      scope: "feature:webhooks",
      outcome: "success",
      changedFiles: ["features/webhooks/provider.ts"],
      failures: [],
      precedent: {
        id: "prec_string_evidence",
        scope: "feature:webhooks",
        trigger: "add webhook handler",
        lesson: "Use string-only promotion evidence.",
        artifact: "skill",
        paths: ["features/webhooks"],
        evidence: ["looks good"],
        injection: "String-only evidence should not promote.",
        promotion: {
          baseline_failures: 1,
          rerun_failures: 0,
        },
      },
    }, null, 2));

    const observed = await runPrecedent([
      "observe",
      "--state-dir",
      stateDir,
      "--trace",
      traceOut,
      "--json",
    ]);

    assert.equal(observed.observed.promotionStatus, "rejected");
    assert.equal(observed.promoted, null);
    assert.ok(observed.rejected.reasons.includes("precedent.replay.id is required for promotion"));
  } finally {
    await rm(stateDir, { force: true, recursive: true });
  }
});

test("explain fails clearly for unknown precedent ids", async () => {
  const stateDir = await mkdtemp(join(tmpdir(), "precedent-replay-test-"));

  try {
    await runPrecedent(["init", "--state-dir", stateDir, "--json"]);

    const result = await runPrecedentResult([
      "explain",
      "--state-dir",
      stateDir,
      "--id",
      "prec_missing",
      "--json",
    ]);
    assert.equal(result.exitCode, 1);
    assert.match(result.stderr, /unknown precedent id: prec_missing/u);
  } finally {
    await rm(stateDir, { force: true, recursive: true });
  }
});

function runPrecedent(args) {
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
      if (exitCode !== 0) {
        reject(new Error(`precedent ${args.join(" ")} failed\n${stderr}`));
        return;
      }

      resolvePromise(JSON.parse(stdout));
    });
  });
}

function runPrecedentResult(args) {
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

async function readJsonLines(path) {
  const content = await readFile(path, "utf8");

  return content
    .split("\n")
    .filter((line) => line.trim().length > 0)
    .map((line) => JSON.parse(line));
}
