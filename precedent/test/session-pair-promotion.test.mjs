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

test("compile promotes analogous failed and successful ordinary sessions", async () => {
  const stateDir = await mkdtemp(join(tmpdir(), "precedent-pair-test-"));

  try {
    await runJson(["init", "--state-dir", stateDir, "--json"]);
    await recordSessionPair(stateDir);

    const compiled = await runJson(["compile", "--state-dir", stateDir, "--promote-session-pairs", "--json"]);
    assert.equal(compiled.promoted.length, 1);
    assert.equal(compiled.promoted[0].id, "prec_feature_webhooks_wrong_test_command_wrong_repo_slice");

    const precedents = await readJsonLines(join(stateDir, "precedents.jsonl"));
    assert.equal(precedents.length, 1);
    assert.equal(precedents[0].promotion.baseline_failures, 1);
    assert.equal(precedents[0].promotion.rerun_failures, 0);
    assert.deepEqual(precedents[0].source_traces, ["session-failed-session", "session-success-session"]);
    assert.ok(precedents[0].evidence.some((item) => item.includes("failed validation: pnpm test exited 1")));
    assert.ok(precedents[0].evidence.some((item) => item.includes("successful validation: pnpm test:webhooks exited 0")));
    assert.ok(precedents[0].guards.some((guard) => guard.type === "required_validation_command"));
    assert.ok(precedents[0].guards.some((guard) => guard.type === "changed_files_within_paths"));

    const context = await runJson([
      "context",
      "--state-dir",
      stateDir,
      "--task",
      "add webhook handler",
      "--scope",
      "feature:webhooks",
      "--changed-files",
      "features/webhooks/providers/github.ts",
      "--json",
    ]);
    assert.equal(context.injections.length, 1);
    assert.equal(context.injections[0].id, "prec_feature_webhooks_wrong_test_command_wrong_repo_slice");
  } finally {
    await rm(stateDir, { force: true, recursive: true });
  }
});

test("session-pair promotion is idempotent", async () => {
  const stateDir = await mkdtemp(join(tmpdir(), "precedent-pair-test-"));

  try {
    await runJson(["init", "--state-dir", stateDir, "--json"]);
    await recordSessionPair(stateDir);
    await runJson(["compile", "--state-dir", stateDir, "--promote-session-pairs", "--json"]);
    const second = await runJson(["compile", "--state-dir", stateDir, "--promote-session-pairs", "--json"]);

    assert.equal(second.promoted.length, 1);
    assert.equal(second.promoted[0].action, "unchanged");
    const precedents = await readJsonLines(join(stateDir, "precedents.jsonl"));
    assert.equal(precedents.length, 1);
    assert.deepEqual(precedents[0].source_traces, ["session-failed-session", "session-success-session"]);
  } finally {
    await rm(stateDir, { force: true, recursive: true });
  }
});

async function recordSessionPair(stateDir) {
  await hook(stateDir, {
    schema_version: "precedent.v1",
    hook: "context.before_turn",
    sessionId: "failed-session",
    task: "add webhook handler",
    scope: "feature:webhooks",
    changedFiles: ["features/webhooks/providers/stripe.ts"],
  });
  await hook(stateDir, {
    schema_version: "precedent.v1",
    hook: "diff.after_edit",
    sessionId: "failed-session",
    changedFiles: ["features/billing/refunds.ts"],
    breadthSignals: ["wrong repo slice"],
  });
  await hook(stateDir, {
    schema_version: "precedent.v1",
    hook: "validation.after_run",
    sessionId: "failed-session",
    command: "pnpm test",
    exitCode: 1,
    stderr: "wrong test command",
  });
  await hook(stateDir, {
    schema_version: "precedent.v1",
    hook: "outcome.after_task",
    sessionId: "failed-session",
    success: false,
    status: "failure",
    notes: "edited outside webhook boundary and ran the wrong test command",
  });

  await hook(stateDir, {
    schema_version: "precedent.v1",
    hook: "context.before_turn",
    sessionId: "success-session",
    task: "add webhook handler",
    scope: "feature:webhooks",
    changedFiles: ["features/webhooks/providers/github.ts"],
  });
  await hook(stateDir, {
    schema_version: "precedent.v1",
    hook: "diff.after_edit",
    sessionId: "success-session",
    changedFiles: ["features/webhooks/providers/github.ts"],
  });
  await hook(stateDir, {
    schema_version: "precedent.v1",
    hook: "validation.after_run",
    sessionId: "success-session",
    command: "pnpm test:webhooks",
    exitCode: 0,
    stdout: "passed",
  });
  await hook(stateDir, {
    schema_version: "precedent.v1",
    hook: "outcome.after_task",
    sessionId: "success-session",
    success: true,
    status: "success",
    notes: "passed with narrow validation",
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
