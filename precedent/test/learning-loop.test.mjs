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

test("failed outcome automatically writes a trace and candidate", async () => {
  const stateDir = await mkdtemp(join(tmpdir(), "precedent-learning-test-"));

  try {
    await runJson(["init", "--state-dir", stateDir, "--json"]);
    await recordFailedWebhookSession(stateDir, "failed");

    const outcome = await hook(stateDir, {
      schema_version: "precedent.v1",
      hook: "outcome.after_task",
      sessionId: "failed",
      success: false,
      status: "failure",
      notes: "agent used the wrong test command",
    });

    assert.equal(outcome.learning.status, "candidate");
    assert.equal(outcome.learning.traceId, "session-failed");
    assert.deepEqual(outcome.learning.candidateIds, ["cand_feature_webhooks_wrong_test_command"]);
    assert.equal(outcome.learning.promotionStatus, "not_promoted");
    assert.equal(outcome.learning.replayRequired, true);

    const trace = JSON.parse(await readFile(join(stateDir, "traces/session-failed.json"), "utf8"));
    assert.ok(trace.failures.some((failure) => failure.includes("wrong test command")));

    const candidates = await readJsonLines(join(stateDir, "candidates.jsonl"));
    assert.equal(candidates.length, 1);
    assert.equal(candidates[0].id, "cand_feature_webhooks_wrong_test_command");
    assert.deepEqual(candidates[0].source_traces, ["session-failed"]);
  } finally {
    await rm(stateDir, { force: true, recursive: true });
  }
});

test("learned candidates stay non-injectable until replay promotion", async () => {
  const stateDir = await mkdtemp(join(tmpdir(), "precedent-learning-test-"));

  try {
    await runJson(["init", "--state-dir", stateDir, "--json"]);
    await recordFailedWebhookSession(stateDir, "failed");
    await hook(stateDir, {
      schema_version: "precedent.v1",
      hook: "outcome.after_task",
      sessionId: "failed",
      success: false,
      status: "failure",
      notes: "wrong test command",
    });

    const beforePromotion = await runJson([
      "inject",
      "--state-dir",
      stateDir,
      "--task",
      "add webhook handler",
      "--scope",
      "feature:webhooks",
      "--json",
    ]);
    assert.deepEqual(beforePromotion.injections, []);

    const traceOut = join(stateDir, "replay-trace.json");
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

    const afterPromotion = await runJson([
      "inject",
      "--state-dir",
      stateDir,
      "--task",
      "add webhook handler",
      "--scope",
      "feature:webhooks",
      "--json",
    ]);
    assert.equal(afterPromotion.injections.length, 1);
    assert.equal(afterPromotion.injections[0].id, "prec_webhook_replay_boundary");
  } finally {
    await rm(stateDir, { force: true, recursive: true });
  }
});

test("repeated failed outcomes merge candidate source traces", async () => {
  const stateDir = await mkdtemp(join(tmpdir(), "precedent-learning-test-"));

  try {
    await runJson(["init", "--state-dir", stateDir, "--json"]);
    await recordFailedWebhookSession(stateDir, "failed");
    for (let index = 0; index < 2; index += 1) {
      await hook(stateDir, {
        schema_version: "precedent.v1",
        hook: "outcome.after_task",
        sessionId: "failed",
        success: false,
        status: "failure",
        notes: "wrong test command",
      });
    }

    const candidates = await readJsonLines(join(stateDir, "candidates.jsonl"));
    assert.equal(candidates.length, 1);
    assert.deepEqual(candidates[0].source_traces, ["session-failed"]);
  } finally {
    await rm(stateDir, { force: true, recursive: true });
  }
});

test("clean successful outcome records no learning candidate", async () => {
  const stateDir = await mkdtemp(join(tmpdir(), "precedent-learning-test-"));

  try {
    await runJson(["init", "--state-dir", stateDir, "--json"]);
    await hook(stateDir, {
      schema_version: "precedent.v1",
      hook: "context.before_turn",
      sessionId: "clean",
      task: "add webhook handler",
      scope: "feature:webhooks",
      changedFiles: ["features/webhooks/providers/stripe.ts"],
    });
    await hook(stateDir, {
      schema_version: "precedent.v1",
      hook: "validation.after_run",
      sessionId: "clean",
      command: "pnpm test:webhooks",
      exitCode: 0,
    });
    const outcome = await hook(stateDir, {
      schema_version: "precedent.v1",
      hook: "outcome.after_task",
      sessionId: "clean",
      success: true,
      status: "success",
    });

    assert.equal(outcome.learning.status, "no_signal");
    assert.deepEqual(outcome.learning.candidateIds, []);
    assert.equal(outcome.learning.replayRequired, false);

    const candidates = await readJsonLines(join(stateDir, "candidates.jsonl"));
    assert.deepEqual(candidates, []);
  } finally {
    await rm(stateDir, { force: true, recursive: true });
  }
});

test("learned traces and candidates keep stored secrets redacted", async () => {
  const stateDir = await mkdtemp(join(tmpdir(), "precedent-learning-test-"));

  try {
    await runJson(["init", "--state-dir", stateDir, "--json"]);
    await hook(stateDir, {
      schema_version: "precedent.v1",
      hook: "context.before_turn",
      sessionId: "secret",
      task: "add webhook handler",
      scope: "feature:webhooks",
    });
    await hook(stateDir, {
      schema_version: "precedent.v1",
      hook: "validation.after_run",
      sessionId: "secret",
      command: "pnpm test:webhooks",
      exitCode: 1,
      stderr: "failed with ghp_1234567890abcdef1234567890abcdef1234",
    });
    await hook(stateDir, {
      schema_version: "precedent.v1",
      hook: "outcome.after_task",
      sessionId: "secret",
      success: false,
      status: "failure",
      notes: "password=supersecretvalue leaked",
    });

    const stored = [
      await readFile(join(stateDir, "traces/session-secret.json"), "utf8"),
      await readFile(join(stateDir, "candidates.jsonl"), "utf8"),
    ].join("\n");
    assert.doesNotMatch(stored, /ghp_1234567890abcdef/u);
    assert.doesNotMatch(stored, /supersecretvalue/u);
    assert.match(stored, /\[REDACTED:github_token\]/u);
    assert.match(stored, /\[REDACTED:credential\]/u);
  } finally {
    await rm(stateDir, { force: true, recursive: true });
  }
});

test("context export sessions preserve task scope and paths for learning", async () => {
  const stateDir = await mkdtemp(join(tmpdir(), "precedent-learning-test-"));

  try {
    await runJson(["init", "--state-dir", stateDir, "--json"]);
    await runJson([
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
      "exported",
      "--json",
    ]);
    await hook(stateDir, {
      schema_version: "precedent.v1",
      hook: "validation.after_run",
      sessionId: "exported",
      command: "pnpm test",
      exitCode: 1,
      stderr: "wrong test command",
    });
    const outcome = await hook(stateDir, {
      schema_version: "precedent.v1",
      hook: "outcome.after_task",
      sessionId: "exported",
      success: false,
      status: "failure",
      notes: "agent used the wrong test command",
    });

    assert.deepEqual(outcome.learning.candidateIds, ["cand_feature_webhooks_wrong_test_command"]);

    const trace = JSON.parse(await readFile(join(stateDir, "traces/session-exported.json"), "utf8"));
    assert.equal(trace.task, "add webhook handler");
    assert.equal(trace.scope, "feature:webhooks");
    assert.deepEqual(trace.changedFiles, ["features/webhooks/providers/stripe.ts"]);
  } finally {
    await rm(stateDir, { force: true, recursive: true });
  }
});

async function recordFailedWebhookSession(stateDir, sessionId) {
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
    command: "pnpm test",
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
