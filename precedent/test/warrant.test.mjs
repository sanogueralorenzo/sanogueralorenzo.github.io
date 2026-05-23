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

test("warrant emits a stable edit contract", async () => {
  const stateDir = await mkdtemp(join(tmpdir(), "precedent-warrant-test-"));

  try {
    await promoteWebhookPrecedent(stateDir);
    const args = [
      "warrant",
      "--state-dir",
      stateDir,
      "--session",
      "warrant-session",
      "--event-id",
      "turn-1-warrant",
      "--task",
      "add webhook handler",
      "--scope",
      "feature:webhooks",
      "--changed-files",
      "features/webhooks/providers/stripe.ts",
      "--json",
    ];
    const first = await runJson(args);
    const retried = await runJson(args);

    assert.equal(first.schema_version, "precedent.warrant.v1");
    assert.match(first.warrantId, /^wrn_[a-f0-9]+$/u);
    assert.equal(first.sessionId, "warrant-session");
    assert.equal(first.eventId, "turn-1-warrant");
    assert.match(first.contextBlock, /^Precedent:/u);
    assert.ok(first.allowed.paths.includes("features/webhooks"));
    assert.equal(first.allowed.maxFiles, 6);
    assert.equal(first.requiredEvidence[0].command, "pnpm test:webhooks");
    assert.deepEqual(first.sources.precedentIds, ["prec_webhook_replay_boundary"]);
    assert.equal(first.deliveryReceipt.injectedPrecedentIds[0], "prec_webhook_replay_boundary");
    assert.equal(retried.deduped, true);
    assert.equal(retried.warrantId, first.warrantId);
  } finally {
    await rm(stateDir, { force: true, recursive: true });
  }
});

test("warrant warns on escaped diffs and too many files", async () => {
  const stateDir = await mkdtemp(join(tmpdir(), "precedent-warrant-test-"));

  try {
    await promoteWebhookPrecedent(stateDir);
    const warrant = await issueWebhookWarrant(stateDir, "diff-session");

    const diff = await hook(stateDir, {
      schema_version: "precedent.v1",
      hook: "diff.after_edit",
      sessionId: "diff-session",
      eventId: "diff-1",
      warrantId: warrant.warrantId,
      changedFiles: [
        "features/webhooks/providers/stripe.ts",
        "features/billing/refunds.ts",
        "docs/a.md",
        "docs/b.md",
        "docs/c.md",
        "docs/d.md",
        "docs/e.md",
      ],
    });

    assert.equal(diff.warrantResult.status, "violated");
    assert.ok(diff.warrantResult.violations.some((item) => item.type === "path_escape"));
    assert.ok(diff.warrantResult.violations.some((item) => item.type === "max_files"));
  } finally {
    await rm(stateDir, { force: true, recursive: true });
  }
});

test("finalize.before_response gates missing validation and repairs", async () => {
  const stateDir = await mkdtemp(join(tmpdir(), "precedent-warrant-test-"));

  try {
    await promoteWebhookPrecedent(stateDir);
    const validateWarrant = await issueWebhookWarrant(stateDir, "finalize-validate-session");

    const missing = await hook(stateDir, {
      schema_version: "precedent.v1",
      hook: "finalize.before_response",
      sessionId: "finalize-validate-session",
      eventId: "finalize-1",
      warrantId: validateWarrant.warrantId,
    });
    const retried = await hook(stateDir, {
      schema_version: "precedent.v1",
      hook: "finalize.before_response",
      sessionId: "finalize-validate-session",
      eventId: "finalize-1",
      warrantId: validateWarrant.warrantId,
    });

    assert.equal(missing.schema_version, "precedent.finalize.v1");
    assert.equal(missing.decision, "validate");
    assert.equal(missing.finalization.missingEvidence[0].command, "pnpm test:webhooks");
    assert.match(missing.contextBlock, /Required command: pnpm test:webhooks/u);
    assert.equal(retried.deduped, true);
    assert.equal(retried.decision, "validate");

    const repairWarrant = await issueWebhookWarrant(stateDir, "finalize-repair-session");
    await hook(stateDir, {
      schema_version: "precedent.v1",
      hook: "diff.after_edit",
      sessionId: "finalize-repair-session",
      eventId: "diff-1",
      warrantId: repairWarrant.warrantId,
      changedFiles: ["features/billing/refunds.ts"],
    });
    const repair = await hook(stateDir, {
      schema_version: "precedent.v1",
      hook: "finalize.before_response",
      sessionId: "finalize-repair-session",
      eventId: "finalize-1",
      warrantId: repairWarrant.warrantId,
    });

    assert.equal(repair.decision, "repair");
    assert.ok(repair.finalization.violations.some((item) => item.type === "path_escape"));
    assert.match(repair.contextBlock, /Repair the turn before the final response/u);
  } finally {
    await rm(stateDir, { force: true, recursive: true });
  }
});

test("finalize.before_response allows satisfied warrant responses", async () => {
  const stateDir = await mkdtemp(join(tmpdir(), "precedent-warrant-test-"));

  try {
    await promoteWebhookPrecedent(stateDir);
    const warrant = await issueWebhookWarrant(stateDir, "finalize-ready-session");

    await hook(stateDir, {
      schema_version: "precedent.v1",
      hook: "validation.after_run",
      sessionId: "finalize-ready-session",
      eventId: "validation-1",
      warrantId: warrant.warrantId,
      command: "pnpm test:webhooks",
      exitCode: 0,
    });
    const ready = await hook(stateDir, {
      schema_version: "precedent.v1",
      hook: "finalize.before_response",
      sessionId: "finalize-ready-session",
      eventId: "finalize-1",
      warrantId: warrant.warrantId,
    });

    assert.equal(ready.decision, "ready");
    assert.equal(ready.contextBlock, "");
    assert.deepEqual(ready.finalization.missingEvidence, []);
    assert.deepEqual(ready.finalization.violations, []);
  } finally {
    await rm(stateDir, { force: true, recursive: true });
  }
});

test("warrant closes satisfied outcomes with validation evidence", async () => {
  const stateDir = await mkdtemp(join(tmpdir(), "precedent-warrant-test-"));

  try {
    await promoteWebhookPrecedent(stateDir);
    const warrant = await issueWebhookWarrant(stateDir, "satisfied-session");

    const validation = await hook(stateDir, {
      schema_version: "precedent.v1",
      hook: "validation.after_run",
      sessionId: "satisfied-session",
      eventId: "validation-1",
      warrantId: warrant.warrantId,
      command: "pnpm test:webhooks",
      exitCode: 0,
    });
    assert.equal(validation.warrantResult.status, "satisfied");

    const outcome = await hook(stateDir, {
      schema_version: "precedent.v1",
      hook: "outcome.after_task",
      sessionId: "satisfied-session",
      eventId: "outcome-1",
      warrantId: warrant.warrantId,
      success: true,
    });
    assert.equal(outcome.outcome.warrantStatus.status, "satisfied");

    const report = await runJson(["report", "--state-dir", stateDir, "--json"]);
    assert.equal(report.warrantHealth.issued, 1);
    assert.equal(report.warrantHealth.satisfied, 1);
    assert.equal(report.warrantHealth.needsAttention, 0);
  } finally {
    await rm(stateDir, { force: true, recursive: true });
  }
});

test("strict check fails unresolved warrant outcomes", async () => {
  const stateDir = await mkdtemp(join(tmpdir(), "precedent-warrant-test-"));

  try {
    await promoteWebhookPrecedent(stateDir);
    const warrant = await issueWebhookWarrant(stateDir, "unresolved-session");

    await hook(stateDir, {
      schema_version: "precedent.v1",
      hook: "outcome.after_task",
      sessionId: "unresolved-session",
      eventId: "outcome-1",
      warrantId: warrant.warrantId,
      success: true,
    });

    const result = await runProcess(["check", "--state-dir", stateDir, "--strict", "--json"]);
    const payload = JSON.parse(result.stdout);
    const warrantCheck = payload.checks.find((check) => check.name === "warrant");

    assert.equal(result.exitCode, 1);
    assert.equal(warrantCheck.ok, false);
    assert.equal(warrantCheck.unresolved, 1);
  } finally {
    await rm(stateDir, { force: true, recursive: true });
  }
});

async function issueWebhookWarrant(stateDir, sessionId) {
  return runJson([
    "warrant",
    "--state-dir",
    stateDir,
    "--session",
    sessionId,
    "--event-id",
    "turn-1-warrant",
    "--task",
    "add webhook handler",
    "--scope",
    "feature:webhooks",
    "--changed-files",
    "features/webhooks/providers/stripe.ts",
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

function hook(stateDir, event) {
  return runJson(["hook", "--state-dir", stateDir, "--json"], event);
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
