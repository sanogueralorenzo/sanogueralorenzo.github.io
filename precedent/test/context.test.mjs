import test from "node:test";
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const repoRoot = resolve(__dirname, "../..");
const cliPath = join(repoRoot, "precedent/bin/precedent.mjs");

test("context exports promoted precedent in a stable JSON envelope", async () => {
  const stateDir = await mkdtemp(join(tmpdir(), "precedent-context-test-"));

  try {
    await promoteWebhookPrecedent(stateDir);

    const context = await runJson([
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

    assert.equal(context.schema_version, "precedent.context.v1");
    assert.match(context.contextBlock, /Precedent:/u);
    assert.equal(context.injections.length, 1);
    assert.equal(context.injections[0].id, "prec_webhook_replay_boundary");
    assert.ok(context.injections[0].matchReasons.length > 0);
    assert.deepEqual(context.suppressedInjections, []);
    assert.equal(context.source.command, "context");
  } finally {
    await rm(stateDir, { force: true, recursive: true });
  }
});

test("context supports task files and markdown output", async () => {
  const stateDir = await mkdtemp(join(tmpdir(), "precedent-context-test-"));

  try {
    await promoteWebhookPrecedent(stateDir);

    const taskFile = join(stateDir, "task.txt");
    await writeFile(taskFile, "add webhook handler");
    const result = await runProcess([
      "context",
      "--state-dir",
      stateDir,
      "--task-file",
      taskFile,
      "--scope",
      "feature:webhooks",
      "--format",
      "markdown",
    ]);

    assert.equal(result.exitCode, 0);
    assert.match(result.stdout, /^Precedent:/u);
    assert.doesNotMatch(result.stdout, /schema_version/u);
  } finally {
    await rm(stateDir, { force: true, recursive: true });
  }
});

test("context suppresses repeated session injections", async () => {
  const stateDir = await mkdtemp(join(tmpdir(), "precedent-context-test-"));

  try {
    await promoteWebhookPrecedent(stateDir);

    const args = [
      "context",
      "--state-dir",
      stateDir,
      "--task",
      "add webhook handler",
      "--scope",
      "feature:webhooks",
      "--session",
      "demo",
      "--json",
    ];
    const first = await runJson(args);
    const second = await runJson(args);

    assert.equal(first.injections.length, 1);
    assert.deepEqual(first.suppressedInjections, []);
    assert.deepEqual(second.injections, []);
    assert.equal(second.suppressedInjections.length, 1);
    assert.equal(second.contextBlock, "");
  } finally {
    await rm(stateDir, { force: true, recursive: true });
  }
});

test("context excludes rejected precedent", async () => {
  const stateDir = await mkdtemp(join(tmpdir(), "precedent-context-test-"));

  try {
    await runJson(["init", "--state-dir", stateDir, "--json"]);
    await runJson([
      "observe",
      "--state-dir",
      stateDir,
      "--trace",
      "precedent/examples/webhook-trace-no-improvement.json",
      "--json",
    ]);

    const context = await runJson([
      "context",
      "--state-dir",
      stateDir,
      "--task",
      "add webhook handler",
      "--scope",
      "feature:webhooks",
      "--json",
    ]);

    assert.equal(context.contextBlock, "");
    assert.deepEqual(context.injections, []);
  } finally {
    await rm(stateDir, { force: true, recursive: true });
  }
});

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
