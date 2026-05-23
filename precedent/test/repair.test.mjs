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

test("repair.before_retry emits validation repair once", async () => {
  const stateDir = await mkdtemp(join(tmpdir(), "precedent-repair-test-"));

  try {
    await runJson(["init", "--state-dir", stateDir, "--json"]);
    await runJson(["hook", "--state-dir", stateDir, "--json"], {
      schema_version: "precedent.v1",
      hook: "validation.after_run",
      sessionId: "demo",
      command: "pnpm test:webhooks",
      exitCode: 1,
      stderr: "missing nullable payload",
      failureSignals: ["non_zero_exit"],
    });

    const repair = await repairBeforeRetry(stateDir, "demo");
    assert.equal(repair.recorded, true);
    assert.match(repair.repairBlock, /Precedent repair:/u);
    assert.match(repair.repairBlock, /pnpm test:webhooks/u);
    assert.equal(repair.repairSource.kind, "failed_validation");

    const repeated = await repairBeforeRetry(stateDir, "demo");
    assert.equal(repeated.recorded, false);
    assert.equal(repeated.repairBlock, "");
    assert.equal(repeated.suppressedRepairs[0].reason, "no_repair_candidate");
  } finally {
    await rm(stateDir, { force: true, recursive: true });
  }
});

test("repair.before_retry reuses latest diff repair prompt", async () => {
  const stateDir = await mkdtemp(join(tmpdir(), "precedent-repair-test-"));

  try {
    await promoteAndInjectWebhookPrecedent(stateDir, "demo");
    await runJson(["hook", "--state-dir", stateDir, "--json"], {
      schema_version: "precedent.v1",
      hook: "diff.after_edit",
      sessionId: "demo",
      changedFiles: ["features/billing/refunds.ts"],
    });

    const repair = await repairBeforeRetry(stateDir, "demo");
    assert.equal(repair.recorded, true);
    assert.match(repair.repairBlock, /Precedent repair:/u);
    assert.match(repair.repairBlock, /features\/billing\/refunds\.ts/u);
    assert.equal(repair.repairSource.kind, "diff_repair");
    assert.equal(repair.repairSource.guardId, "guard_webhook_paths");
  } finally {
    await rm(stateDir, { force: true, recursive: true });
  }
});

test("repair.before_retry emits outcome repair for failed outcomes", async () => {
  const stateDir = await mkdtemp(join(tmpdir(), "precedent-repair-test-"));

  try {
    await runJson(["init", "--state-dir", stateDir, "--json"]);
    await runJson(["hook", "--state-dir", stateDir, "--json"], {
      schema_version: "precedent.v1",
      hook: "outcome.after_task",
      sessionId: "demo",
      success: false,
      status: "failed_review",
      notes: "review still finds the path leak",
      changedFiles: ["features/billing/refunds.ts"],
    });

    const repair = await repairBeforeRetry(stateDir, "demo");
    assert.equal(repair.recorded, true);
    assert.match(repair.repairBlock, /failed_review/u);
    assert.match(repair.repairBlock, /features\/billing\/refunds\.ts/u);
    assert.equal(repair.repairSource.kind, "failed_outcome");
  } finally {
    await rm(stateDir, { force: true, recursive: true });
  }
});

test("repair.before_retry returns empty repair on clean sessions", async () => {
  const stateDir = await mkdtemp(join(tmpdir(), "precedent-repair-test-"));

  try {
    await runJson(["init", "--state-dir", stateDir, "--json"]);
    await runJson(["hook", "--state-dir", stateDir, "--json"], {
      schema_version: "precedent.v1",
      hook: "validation.after_run",
      sessionId: "demo",
      command: "pnpm test:webhooks",
      exitCode: 0,
    });

    const repair = await repairBeforeRetry(stateDir, "demo");
    assert.equal(repair.recorded, false);
    assert.equal(repair.repairBlock, "");
    assert.equal(repair.repairSource, null);
  } finally {
    await rm(stateDir, { force: true, recursive: true });
  }
});

async function repairBeforeRetry(stateDir, sessionId) {
  return runJson(["hook", "--state-dir", stateDir, "--json"], {
    schema_version: "precedent.v1",
    hook: "repair.before_retry",
    sessionId,
    nextSessionId: `${sessionId}-retry`,
  });
}

async function promoteAndInjectWebhookPrecedent(stateDir, sessionId) {
  await promoteWebhookPrecedent(stateDir);
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
    sessionId,
    "--json",
  ]);
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
