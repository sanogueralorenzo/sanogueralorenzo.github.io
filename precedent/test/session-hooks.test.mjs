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

test("session hooks compile normal conversation events into an observable trace", async () => {
  const stateDir = await mkdtemp(join(tmpdir(), "precedent-session-test-"));

  try {
    await runPrecedent(["init", "--state-dir", stateDir, "--json"]);

    const beforeTurn = await runPrecedent(["hook", "--state-dir", stateDir, "--json"], {
      schema_version: "precedent.v1",
      hook: "context.before_turn",
      sessionId: "demo",
      task: "add webhook handler",
      scope: "feature:webhooks",
      changedFiles: ["features/webhooks/providers/stripe.ts"],
    });
    assert.equal(beforeTurn.ok, true);
    assert.equal(beforeTurn.sessionId, "demo");
    assert.equal(beforeTurn.contextBlock, "");

    const validation = await runPrecedent(["hook", "--state-dir", stateDir, "--json"], {
      schema_version: "precedent.v1",
      hook: "validation.after_run",
      sessionId: "demo",
      command: "pnpm test:webhooks",
      exitCode: 1,
      stderr: "nullable payload test failed",
    });
    assert.equal(validation.recorded, true);
    assert.deepEqual(validation.validation.failureSignals, ["non_zero_exit", "stderr_output"]);
    assert.match(validation.validation.stderrPath, /validation_after_run\.stderr\.txt$/u);

    const diff = await runPrecedent(["hook", "--state-dir", stateDir, "--json"], {
      schema_version: "precedent.v1",
      hook: "diff.after_edit",
      sessionId: "demo",
      changedFiles: [
        "features/webhooks/providers/stripe.ts",
        "features/webhooks/providers/github.ts",
        "features/billing/refunds.ts",
        "scripts/setup.ts",
        "README.md",
        "docs/webhooks.md",
      ],
    });
    assert.equal(diff.recorded, true);
    assert.deepEqual(diff.diff.breadthSignals, ["many_files_touched", "multiple_top_level_scopes"]);

    const outcome = await runPrecedent(["hook", "--state-dir", stateDir, "--json"], {
      schema_version: "precedent.v1",
      hook: "outcome.after_task",
      sessionId: "demo",
      success: false,
      retries: 2,
      tokenEstimate: 4100,
      notes: "Agent used the wrong test command and missed nullable payload handling.",
    });
    assert.equal(outcome.recorded, true);
    assert.equal(outcome.outcome.status, "failure");
    assert.equal(outcome.outcome.retries, 2);

    const observed = await runPrecedent([
      "observe",
      "--state-dir",
      stateDir,
      "--session",
      "demo",
      "--json",
    ]);
    assert.equal(observed.ok, true);
    assert.equal(observed.observed.traceId, "session-demo");
    assert.equal(observed.observed.scope, "feature:webhooks");
    assert.equal(observed.observed.promotionStatus, "none");
    assert.match(observed.observed.failures[0], /pnpm test:webhooks/u);

    const trace = JSON.parse(await readFile(join(stateDir, "traces/session-demo.json"), "utf8"));
    assert.equal(trace.session.eventCount, 4);
    assert.deepEqual(trace.session.hooks, [
      "context.before_turn",
      "validation.after_run",
      "diff.after_edit",
      "outcome.after_task",
    ]);
    assert.equal(trace.hooks["validation.after_run"].result, "exit 1");

    const compiled = await runPrecedent(["compile", "--state-dir", stateDir, "--json"]);
    assert.equal(compiled.candidates.length, 1);
    assert.deepEqual(compiled.candidates[0].failure_types, [
      "wrong_test_command",
      "wrong_repo_slice",
      "missed_contract",
    ]);
  } finally {
    await rm(stateDir, { force: true, recursive: true });
  }
});

function runPrecedent(args, stdinJson = null) {
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
