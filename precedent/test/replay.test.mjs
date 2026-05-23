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
    assert.match(afterPromotion.block, /Precedent:/u);

    const report = await runPrecedent(["report", "--state-dir", stateDir, "--json"]);
    assert.equal(report.replays, 1);
    assert.equal(report.precedents, 1);

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

async function readJsonLines(path) {
  const content = await readFile(path, "utf8");

  return content
    .split("\n")
    .filter((line) => line.trim().length > 0)
    .map((line) => JSON.parse(line));
}
