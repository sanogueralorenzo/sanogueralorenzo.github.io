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

test("diff.after_edit executes active promoted path guards", async () => {
  const stateDir = await mkdtemp(join(tmpdir(), "precedent-guards-test-"));

  try {
    await promoteAndInjectWebhookPrecedent(stateDir, "demo");

    const diff = await runJson(["hook", "--state-dir", stateDir, "--json"], {
      schema_version: "precedent.v1",
      hook: "diff.after_edit",
      sessionId: "demo",
      changedFiles: ["features/billing/refunds.ts"],
    });

    assert.equal(diff.guardResult.ok, false);
    assert.equal(diff.guardResult.failed.length, 1);
    assert.equal(diff.guardResult.failed[0].guardId, "guard_webhook_paths");
    assert.deepEqual(diff.guardResult.failed[0].evidence, ["features/billing/refunds.ts"]);
    assert.match(diff.contextBlock, /Precedent guard:/u);

    const inside = await runJson(["hook", "--state-dir", stateDir, "--json"], {
      schema_version: "precedent.v1",
      hook: "diff.after_edit",
      sessionId: "demo",
      changedFiles: ["features/webhooks/providers/stripe.ts"],
    });
    assert.equal(inside.guardResult.ok, true);
    assert.equal(inside.guardResult.passed[0].guardId, "guard_webhook_paths");
  } finally {
    await rm(stateDir, { force: true, recursive: true });
  }
});

test("validation.after_run executes active required command guards", async () => {
  const stateDir = await mkdtemp(join(tmpdir(), "precedent-guards-test-"));

  try {
    await promoteAndInjectWebhookPrecedent(stateDir, "demo");

    const wrong = await runJson(["hook", "--state-dir", stateDir, "--json"], {
      schema_version: "precedent.v1",
      hook: "validation.after_run",
      sessionId: "demo",
      command: "pnpm test",
      exitCode: 0,
    });
    assert.equal(wrong.guardResult.ok, false);
    assert.equal(wrong.guardResult.failed[0].guardId, "guard_webhook_validation");

    const right = await runJson(["hook", "--state-dir", stateDir, "--json"], {
      schema_version: "precedent.v1",
      hook: "validation.after_run",
      sessionId: "demo",
      command: "pnpm test:webhooks",
      exitCode: 0,
    });
    assert.equal(right.guardResult.ok, true);
    assert.equal(right.guardResult.passed[0].guardId, "guard_webhook_validation");
  } finally {
    await rm(stateDir, { force: true, recursive: true });
  }
});

test("guards are ignored until their precedent is injected", async () => {
  const stateDir = await mkdtemp(join(tmpdir(), "precedent-guards-test-"));

  try {
    await promoteWebhookPrecedent(stateDir);
    const diff = await runJson(["hook", "--state-dir", stateDir, "--json"], {
      schema_version: "precedent.v1",
      hook: "diff.after_edit",
      sessionId: "demo",
      changedFiles: ["features/billing/refunds.ts"],
    });

    assert.equal(diff.guardResult.ok, true);
    assert.equal(diff.guardResult.checked, 0);
  } finally {
    await rm(stateDir, { force: true, recursive: true });
  }
});

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
  const observed = await runJson(["observe", "--state-dir", stateDir, "--trace", traceOut, "--json"]);
  assert.equal(observed.promoted.guards.length, 2);
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
