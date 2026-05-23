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

test("passing validation emits a replay-plan promotion trial for matching candidates", async () => {
  const stateDir = await mkdtemp(join(tmpdir(), "precedent-replay-plan-test-"));

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

    const candidates = await readJsonLines(join(stateDir, "candidates.jsonl"));
    assert.equal(candidates.length, 1);
    assert.equal(candidates[0].replayPlan.baseline.command, "node -e \"process.exit(1)\"");
    assert.equal(candidates[0].replayPlan.baseline.exitCode, 1);
    assert.equal(candidates[0].replayPlan.baseline.sourceTrace, "session-failed");
    assert.equal(candidates[0].replayPlan.baseline.sourceSession, "failed");

    const context = await hook(stateDir, {
      schema_version: "precedent.v1",
      hook: "context.before_turn",
      sessionId: "passing",
      task: "add webhook handler",
      scope: "feature:webhooks",
      changedFiles: ["features/webhooks/providers/stripe.ts"],
    });
    assert.equal(context.contextBlock, "");
    assert.equal(context.candidateHints.length, 1);
    assert.equal(context.candidateHints[0].promotionTrial.baselineCommand, "node -e \"process.exit(1)\"");
    assert.equal(context.candidateHints[0].artifact.injectable, false);

    const validation = await hook(stateDir, {
      schema_version: "precedent.v1",
      hook: "validation.after_run",
      sessionId: "passing",
      eventId: "passing-validation",
      command: "node -e \"process.exit(0)\"",
      exitCode: 0,
    });
    const retried = await hook(stateDir, {
      schema_version: "precedent.v1",
      hook: "validation.after_run",
      sessionId: "passing",
      eventId: "passing-validation",
      command: "node -e \"process.exit(0)\"",
      exitCode: 0,
    });

    assert.equal(validation.contextBlock, "");
    assert.equal(validation.promotionTrials.length, 1);
    assert.deepEqual(retried.promotionTrials, validation.promotionTrials);
    assert.equal(retried.deduped, true);
    assert.equal(validation.promotionTrials[0].candidateId, "cand_feature_webhooks_wrong_test_command");
    assert.equal(validation.promotionTrials[0].baselineCommand, "node -e \"process.exit(1)\"");
    assert.equal(validation.promotionTrials[0].rerunCommand, "node -e \"process.exit(0)\"");
    assert.equal(validation.promotionTrials[0].injectable, false);
    assert.equal(validation.promotionTrials[0].autoExecute, false);
    assert.deepEqual(validation.promotionTrials[0].command.slice(0, 7), [
      "node",
      "precedent/bin/precedent.mjs",
      "promotion-trial",
      "--state-dir",
      stateDir,
      "--candidate",
      "cand_feature_webhooks_wrong_test_command",
    ]);

    const trial = await runJson(validation.promotionTrials[0].command.slice(2));
    assert.equal(trial.promoted.id, "cand_feature_webhooks_wrong_test_command");

    const promotedContext = await runJson([
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
    assert.equal(promotedContext.injections[0].id, "cand_feature_webhooks_wrong_test_command");
  } finally {
    await rm(stateDir, { force: true, recursive: true });
  }
});

test("passing validation does not route non-matching candidate replay plans", async () => {
  const stateDir = await mkdtemp(join(tmpdir(), "precedent-replay-plan-test-"));

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
      sessionId: "billing",
      task: "add refund screen",
      scope: "feature:billing",
      changedFiles: ["features/billing/refunds.ts"],
    });

    const validation = await hook(stateDir, {
      schema_version: "precedent.v1",
      hook: "validation.after_run",
      sessionId: "billing",
      command: "node -e \"process.exit(0)\"",
      exitCode: 0,
    });
    assert.deepEqual(validation.promotionTrials, []);
  } finally {
    await rm(stateDir, { force: true, recursive: true });
  }
});

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
