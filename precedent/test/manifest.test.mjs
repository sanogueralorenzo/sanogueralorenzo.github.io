import test from "node:test";
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const repoRoot = resolve(__dirname, "../..");
const cliPath = resolve(repoRoot, "precedent/bin/precedent.mjs");

test("manifest emits a generic runtime hook contract", async () => {
  const manifest = await runJson(["manifest", "--json"]);

  assert.equal(manifest.schema_version, "precedent.manifest.v1");
  assert.equal(manifest.runtime, "generic");
  assert.equal(manifest.hooks["context.before_turn"].injectFrom, "contextBlock");
  assert.equal(manifest.hooks["context.before_turn"].failurePolicy, "fail_open");
  assert.deepEqual(manifest.hooks["context.before_turn"].output, ["schema_version", "contextBlock", "injections", "suppressedInjections", "revisionBriefs", "source"]);
  assert.deepEqual(manifest.hooks["review.after_feedback"].stdin, ["schema_version", "hook", "sessionId", "comments", "changedFiles", "reviewer"]);
  assert.equal(manifest.hooks["review.after_feedback"].failurePolicy, "fail_open");
  assert.deepEqual(manifest.hooks["validation.after_run"].stdin, ["schema_version", "hook", "sessionId", "command", "exitCode", "durationMs", "stdout", "stderr", "failureSignals", "attributedPrecedents"]);
  assert.deepEqual(manifest.hooks["validation.after_run"].output, ["ok", "hook", "sessionId", "recorded", "sessionEventPath", "validation", "guardResult", "contextBlock"]);
  assert.deepEqual(manifest.hooks["diff.after_edit"].stdin, ["schema_version", "hook", "sessionId", "changedFiles", "linesAdded", "linesDeleted", "breadthSignals", "diffSummary", "unifiedDiff", "attributedPrecedents"]);
  assert.deepEqual(manifest.hooks["diff.after_edit"].output, ["ok", "hook", "sessionId", "recorded", "sessionEventPath", "diff", "guardResult", "repairPrompt", "contextBlock"]);
  assert.deepEqual(manifest.hooks["outcome.after_task"].stdin, ["schema_version", "hook", "sessionId", "success", "status", "task", "scope", "changedFiles", "retries", "tokenEstimate", "notes", "attributedPrecedents", "precedent", "replay"]);
  assert.deepEqual(manifest.hooks["repair.before_retry"].stdin, ["schema_version", "hook", "sessionId", "nextSessionId", "task", "finalMessage", "scope", "changedFiles", "retry", "attributedPrecedents"]);
  assert.deepEqual(manifest.hooks["repair.before_retry"].output, ["schema_version", "ok", "hook", "sessionId", "recorded", "sessionEventPath", "repairId", "repairBlock", "repairSource", "suppressedRepairs"]);
  assert.equal(manifest.hooks["repair.before_retry"].injectFrom, "repairBlock");
  assert.deepEqual(manifest.hooks["repair.after_retry"].stdin, ["schema_version", "hook", "sessionId", "repairId", "repairSessionId", "attributedPrecedents"]);
  assert.deepEqual(manifest.hooks["repair.after_retry"].output, ["schema_version", "ok", "hook", "sessionId", "recorded", "sessionEventPath", "repairReceipt", "suppressedRepairs"]);
  assert.deepEqual(manifest.hooks["context.before_turn"].command, [
    "node",
    "precedent/bin/precedent.mjs",
    "context",
    "--state-dir",
    ".precedent",
    "--task-file",
    "$TASK_FILE",
    "--scope",
    "$SCOPE",
    "--changed-files",
    "$CHANGED_FILES",
    "--session",
    "$SESSION_ID",
    "--format",
    "json",
  ]);
});

test("manifest reflects state dir and codex runtime", async () => {
  const manifest = await runJson([
    "manifest",
    "--runtime",
    "codex",
    "--state-dir",
    "/tmp/precedent-manifest",
    "--json",
  ]);

  assert.equal(manifest.runtime, "codex");
  assert.equal(manifest.stateDir, "/tmp/precedent-manifest");
  assert.equal(manifest.hooks["context.before_turn"].command[4], "/tmp/precedent-manifest");
  assert.deepEqual(manifest.hooks["validation.after_run"].command, [
    "node",
    "precedent/bin/precedent.mjs",
    "hook",
    "--state-dir",
    "/tmp/precedent-manifest",
    "--json",
  ]);
});

test("manifest rejects unknown runtimes", async () => {
  const result = await runProcess(["manifest", "--runtime", "other", "--json"]);

  assert.equal(result.exitCode, 1);
  assert.match(result.stderr, /unsupported runtime: other/u);
});

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
