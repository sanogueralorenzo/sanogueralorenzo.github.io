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

test("review feedback creates missed-contract candidates", async () => {
  const stateDir = await mkdtemp(join(tmpdir(), "precedent-review-test-"));

  try {
    await runJson(["init", "--state-dir", stateDir, "--json"]);
    await recordReviewFailure(stateDir, "failed", "missed nullable payload contract");
    const outcome = await hook(stateDir, {
      schema_version: "precedent.v1",
      hook: "outcome.after_task",
      sessionId: "failed",
      success: false,
      notes: "review requested changes",
    });

    assert.equal(outcome.learning.status, "candidate");
    assert.deepEqual(outcome.learning.candidateIds, ["cand_feature_webhooks_missed_contract"]);

    const trace = JSON.parse(await readFile(join(stateDir, "traces/session-failed.json"), "utf8"));
    assert.deepEqual(trace.hooks["review.after_feedback"].comments, ["missed nullable payload contract"]);

    const candidates = await readJsonLines(join(stateDir, "candidates.jsonl"));
    assert.equal(candidates.length, 1);
    assert.equal(candidates[0].id, "cand_feature_webhooks_missed_contract");
    assert.ok(candidates[0].evidence.includes("review-comment: missed nullable payload contract"));

    const beforePromotion = await runJson([
      "inject",
      "--state-dir",
      stateDir,
      "--task",
      "fix webhook payload contract",
      "--scope",
      "feature:webhooks",
      "--json",
    ]);
    assert.deepEqual(beforePromotion.injections, []);
  } finally {
    await rm(stateDir, { force: true, recursive: true });
  }
});

test("review feedback participates in session-pair promotion", async () => {
  const stateDir = await mkdtemp(join(tmpdir(), "precedent-review-test-"));

  try {
    await runJson(["init", "--state-dir", stateDir, "--json"]);
    await recordReviewFailure(stateDir, "failed", "missed nullable payload contract");
    await hook(stateDir, {
      schema_version: "precedent.v1",
      hook: "outcome.after_task",
      sessionId: "failed",
      success: false,
    });
    await recordCleanSuccess(stateDir, "success");

    const compiled = await runJson(["compile", "--state-dir", stateDir, "--promote-session-pairs", "--json"]);
    assert.equal(compiled.promoted.length, 1);
    assert.equal(compiled.promoted[0].id, "prec_feature_webhooks_missed_contract");

    const precedents = await readJsonLines(join(stateDir, "precedents.jsonl"));
    assert.equal(precedents.length, 1);
    assert.ok(precedents[0].evidence.includes("review-comment: missed nullable payload contract"));
    assert.equal(precedents[0].promotion.baseline_failures, 1);
    assert.equal(precedents[0].promotion.rerun_failures, 0);
  } finally {
    await rm(stateDir, { force: true, recursive: true });
  }
});

test("review feedback redacts secrets across session learning state", async () => {
  const stateDir = await mkdtemp(join(tmpdir(), "precedent-review-test-"));

  try {
    await runJson(["init", "--state-dir", stateDir, "--json"]);
    await recordReviewFailure(stateDir, "secret", "missed nullable payload contract with ghp_1234567890abcdef1234567890abcdef1234");
    await hook(stateDir, {
      schema_version: "precedent.v1",
      hook: "outcome.after_task",
      sessionId: "secret",
      success: false,
    });

    const stored = [
      await readFile(join(stateDir, "sessions/secret.jsonl"), "utf8"),
      await readFile(join(stateDir, "traces/session-secret.json"), "utf8"),
      await readFile(join(stateDir, "candidates.jsonl"), "utf8"),
    ].join("\n");
    assert.doesNotMatch(stored, /ghp_1234567890abcdef/u);
    assert.match(stored, /\[REDACTED:github_token\]/u);
  } finally {
    await rm(stateDir, { force: true, recursive: true });
  }
});

test("review hook can be disabled by config", async () => {
  const stateDir = await mkdtemp(join(tmpdir(), "precedent-review-test-"));
  const configPath = join(stateDir, "config.json");

  try {
    await runJson(["init", "--state-dir", stateDir, "--json"]);
    await writeFile(configPath, JSON.stringify({
      schema_version: "precedent.config.v1",
      stateDir,
      enabledHooks: ["context.before_turn", "outcome.after_task"],
    }));

    const result = await runProcess(["hook", "--state-dir", stateDir, "--json"], {
      schema_version: "precedent.v1",
      hook: "review.after_feedback",
      sessionId: "demo",
      comments: ["missed nullable payload contract"],
    });

    assert.equal(result.exitCode, 1);
    assert.match(result.stderr, /disabled hook: review\.after_feedback/u);
  } finally {
    await rm(stateDir, { force: true, recursive: true });
  }
});

async function recordReviewFailure(stateDir, sessionId, comment) {
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
    hook: "review.after_feedback",
    sessionId,
    comments: [comment],
    changedFiles: ["features/webhooks/providers/stripe.ts"],
  });
}

async function recordCleanSuccess(stateDir, sessionId) {
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
    command: "pnpm test:webhooks",
    exitCode: 0,
  });
  await hook(stateDir, {
    schema_version: "precedent.v1",
    hook: "outcome.after_task",
    sessionId,
    success: true,
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
