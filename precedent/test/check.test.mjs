import test from "node:test";
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { appendFile, mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const repoRoot = resolve(__dirname, "../..");
const cliPath = join(repoRoot, "precedent/bin/precedent.mjs");

test("check passes for healthy state", async () => {
  const stateDir = await mkdtemp(join(tmpdir(), "precedent-check-test-"));

  try {
    await promoteWebhookPrecedent(stateDir);
    const result = await runJson(["check", "--state-dir", stateDir, "--json"]);

    assert.equal(result.ok, true);
    assert.ok(result.checks.every((check) => check.ok));
  } finally {
    await rm(stateDir, { force: true, recursive: true });
  }
});

test("check fails for malformed precedent JSONL", async () => {
  const stateDir = await mkdtemp(join(tmpdir(), "precedent-check-test-"));

  try {
    await runJson(["init", "--state-dir", stateDir, "--json"]);
    await appendFile(join(stateDir, "precedents.jsonl"), "{bad json\n");

    const result = await runProcess(["check", "--state-dir", stateDir, "--json"]);
    const payload = JSON.parse(result.stdout);

    assert.equal(result.exitCode, 1);
    assert.equal(payload.ok, false);
    assert.ok(payload.checks.some((check) => check.name === "precedents" && check.ok === false));
  } finally {
    await rm(stateDir, { force: true, recursive: true });
  }
});

test("check fails for promoted precedent without evidence", async () => {
  const stateDir = await mkdtemp(join(tmpdir(), "precedent-check-test-"));

  try {
    await runJson(["init", "--state-dir", stateDir, "--json"]);
    await appendFile(join(stateDir, "precedents.jsonl"), `${JSON.stringify({
      id: "prec_bad",
      promotion_status: "promoted",
      evidence: [],
      promotion: {
        baseline_failures: 1,
        rerun_failures: 0,
      },
    })}\n`);

    const result = await runProcess(["check", "--state-dir", stateDir, "--json"]);
    const payload = JSON.parse(result.stdout);

    assert.equal(result.exitCode, 1);
    assert.ok(payload.checks.some((check) => check.message?.includes("has no evidence")));
  } finally {
    await rm(stateDir, { force: true, recursive: true });
  }
});

test("check fails for promoted precedent without improvement", async () => {
  const stateDir = await mkdtemp(join(tmpdir(), "precedent-check-test-"));

  try {
    await runJson(["init", "--state-dir", stateDir, "--json"]);
    await appendFile(join(stateDir, "precedents.jsonl"), `${JSON.stringify({
      id: "prec_no_improvement",
      promotion_status: "promoted",
      evidence: ["test: no improvement"],
      promotion: {
        baseline_failures: 1,
        rerun_failures: 1,
      },
    })}\n`);

    const result = await runProcess(["check", "--state-dir", stateDir, "--json"]);
    const payload = JSON.parse(result.stdout);

    assert.equal(result.exitCode, 1);
    assert.ok(payload.checks.some((check) => check.message?.includes("baseline_failures greater than rerun_failures")));
  } finally {
    await rm(stateDir, { force: true, recursive: true });
  }
});

test("check fails for promoted precedent without replay receipt", async () => {
  const stateDir = await mkdtemp(join(tmpdir(), "precedent-check-test-"));

  try {
    await runJson(["init", "--state-dir", stateDir, "--json"]);
    await appendFile(join(stateDir, "precedents.jsonl"), `${JSON.stringify({
      id: "prec_no_replay_receipt",
      promotion_status: "promoted",
      evidence: ["verified by replay"],
      promotion: {
        baseline_failures: 1,
        rerun_failures: 0,
      },
    })}\n`);

    const result = await runProcess(["check", "--state-dir", stateDir, "--json"]);
    const payload = JSON.parse(result.stdout);
    const report = await runJson(["report", "--state-dir", stateDir, "--json"]);

    assert.equal(report.auditHealth.missingReceipt, 1);
    assert.equal(report.replayAudit[0].status, "missing_receipt");
    assert.equal(result.exitCode, 1);
    assert.ok(payload.checks.some((check) => check.name === "promoted_precedent_replay" && check.message?.includes("replay.id is required")));
    assert.ok(payload.checks.some((check) => check.name === "promoted_precedent_replay" && check.message?.includes("replay.path is required")));
    assert.ok(payload.checks.some((check) => check.name === "promoted_precedent_replay" && check.message?.includes("artifact_sha256 is required")));
  } finally {
    await rm(stateDir, { force: true, recursive: true });
  }
});

test("report surfaces replay audit failures without failing", async () => {
  const stateDir = await mkdtemp(join(tmpdir(), "precedent-check-test-"));

  try {
    await runJson(["init", "--state-dir", stateDir, "--json"]);
    await appendFile(join(stateDir, "precedents.jsonl"), `${JSON.stringify({
      id: "prec_missing_artifact",
      promotion_status: "promoted",
      evidence: ["verified by replay"],
      replay: {
        id: "missing-replay",
        path: join(stateDir, "replays/missing-replay/replay.json"),
        artifact_sha256: "a".repeat(64),
        baseline_failures: 1,
        rerun_failures: 0,
        baseline_exit_code: 1,
        rerun_exit_code: 0,
      },
      promotion: {
        baseline_failures: 1,
        rerun_failures: 0,
        baseline_exit_code: 1,
        rerun_exit_code: 0,
      },
    })}\n`);
    await appendFile(join(stateDir, "precedents.jsonl"), `${JSON.stringify({
      id: "prec_outside_state",
      promotion_status: "promoted",
      evidence: ["verified by replay"],
      replay: {
        id: "outside-replay",
        path: join(tmpdir(), "outside-replay.json"),
        artifact_sha256: "b".repeat(64),
        baseline_failures: 1,
        rerun_failures: 0,
        baseline_exit_code: 1,
        rerun_exit_code: 0,
      },
      promotion: {
        baseline_failures: 1,
        rerun_failures: 0,
        baseline_exit_code: 1,
        rerun_exit_code: 0,
      },
    })}\n`);

    const report = await runJson(["report", "--state-dir", stateDir, "--json"]);

    assert.equal(report.auditHealth.needsAttention, 2);
    assert.equal(report.auditHealth.missingArtifact, 1);
    assert.equal(report.auditHealth.outsideState, 1);
    assert.equal(report.replayAudit.find((entry) => entry.precedentId === "prec_missing_artifact").status, "missing_artifact");
    assert.equal(report.replayAudit.find((entry) => entry.precedentId === "prec_outside_state").status, "outside_state");
  } finally {
    await rm(stateDir, { force: true, recursive: true });
  }
});

test("check fails for raw secret-like values in state", async () => {
  const stateDir = await mkdtemp(join(tmpdir(), "precedent-check-test-"));

  try {
    await runJson(["init", "--state-dir", stateDir, "--json"]);
    await writeFile(join(stateDir, "events.jsonl"), `${JSON.stringify({
      token: "ghp_1234567890abcdef1234567890abcdef1234",
    })}\n`);

    const result = await runProcess(["check", "--state-dir", stateDir, "--json"]);
    const payload = JSON.parse(result.stdout);

    assert.equal(result.exitCode, 1);
    assert.ok(payload.checks.some((check) => check.name === "raw_secret_scan" && check.ok === false));
  } finally {
    await rm(stateDir, { force: true, recursive: true });
  }
});

test("check validates nested replay artifacts", async () => {
  const stateDir = await mkdtemp(join(tmpdir(), "precedent-check-test-"));

  try {
    await promoteWebhookPrecedent(stateDir);
    await writeFile(join(stateDir, "replays/webhook-replay-improves/replay.json"), `${JSON.stringify({
      id: "webhook-replay-improves",
      baseline: { exitCode: 1 },
      rerun: { exitCode: 0 },
      improved: true,
    })}\n`);

    const result = await runProcess(["check", "--state-dir", stateDir, "--strict", "--json"]);
    const payload = JSON.parse(result.stdout);

    assert.equal(result.exitCode, 1);
    assert.ok(payload.checks.some((check) => check.name === "replay" && check.ok === false && check.message.includes("promotion.baseline_failures")));
  } finally {
    await rm(stateDir, { force: true, recursive: true });
  }
});

test("check validates promoted precedent replay receipts", async () => {
  const stateDir = await mkdtemp(join(tmpdir(), "precedent-check-test-"));

  try {
    await runJson(["init", "--state-dir", stateDir, "--json"]);
    await recordSessionPair(stateDir);
    await runJson(["compile", "--state-dir", stateDir, "--promote-session-pairs", "--json"]);
    await writeFile(join(stateDir, "replays/session-pair-session-failed-session-session-success-session/replay.json"), `${JSON.stringify({
      id: "session-pair-session-failed-session-session-success-session",
      baseline: { exitCode: 1 },
      rerun: { exitCode: 0 },
      improved: true,
      promotion: {
        baseline_failures: 2,
        rerun_failures: 0,
      },
    })}\n`);

    const result = await runProcess(["check", "--state-dir", stateDir, "--strict", "--json"]);
    const payload = JSON.parse(result.stdout);
    const report = await runJson(["report", "--state-dir", stateDir, "--json"]);

    assert.equal(report.auditHealth.hashMismatch, 1);
    assert.equal(report.replayAudit[0].status, "hash_mismatch");
    assert.equal(result.exitCode, 1);
    assert.ok(payload.checks.some((check) => check.name === "promoted_precedent_replay" && check.ok === false && check.message.includes("artifact hash")));
    assert.ok(payload.checks.some((check) => check.name === "promoted_precedent_replay" && check.ok === false && check.message.includes("baseline failure count")));
  } finally {
    await rm(stateDir, { force: true, recursive: true });
  }
});

test("check validates normal candidate ledger entries", async () => {
  const stateDir = await mkdtemp(join(tmpdir(), "precedent-check-test-"));

  try {
    await runJson(["init", "--state-dir", stateDir, "--json"]);
    await hook(stateDir, {
      schema_version: "precedent.v1",
      hook: "context.before_turn",
      sessionId: "failed-candidate",
      task: "add webhook handler",
      scope: "feature:webhooks",
      changedFiles: ["features/webhooks/providers/stripe.ts"],
    });
    await hook(stateDir, {
      schema_version: "precedent.v1",
      hook: "validation.after_run",
      sessionId: "failed-candidate",
      command: "pnpm test",
      exitCode: 1,
      stderr: "wrong test command",
    });
    await hook(stateDir, {
      schema_version: "precedent.v1",
      hook: "outcome.after_task",
      sessionId: "failed-candidate",
      success: false,
      status: "failure",
      notes: "wrong test command",
    });

    const result = await runJson(["check", "--state-dir", stateDir, "--json"]);

    assert.equal(result.ok, true);
    assert.ok(result.checks.some((check) => check.name === "candidate_ledger" && check.ok === true && check.checked === 1));
  } finally {
    await rm(stateDir, { force: true, recursive: true });
  }
});

test("check validates replacement candidate evidence and target", async () => {
  const stateDir = await mkdtemp(join(tmpdir(), "precedent-check-test-"));

  try {
    await promoteWebhookPrecedent(stateDir);
    await writeCandidateTrace(stateDir, "session-replacement");
    await appendFile(join(stateDir, "candidates.jsonl"), `${JSON.stringify(replacementCandidate({
      id: "cand_replace_prec_webhook_replay_boundary_demo",
      replaces: ["prec_webhook_replay_boundary"],
      source_traces: ["session-replacement"],
    }))}\n`);

    const result = await runJson(["check", "--state-dir", stateDir, "--json"]);

    assert.equal(result.ok, true);
    assert.ok(result.checks.some((check) => check.name === "candidate_ledger" && check.ok === true && check.checked === 1));
  } finally {
    await rm(stateDir, { force: true, recursive: true });
  }
});

test("check fails replacement candidates without replacement evidence", async () => {
  const stateDir = await mkdtemp(join(tmpdir(), "precedent-check-test-"));

  try {
    await promoteWebhookPrecedent(stateDir);
    await writeCandidateTrace(stateDir, "session-replacement");
    await appendFile(join(stateDir, "candidates.jsonl"), `${JSON.stringify(replacementCandidate({
      id: "cand_replace_bad",
      replaces: ["prec_webhook_replay_boundary"],
      source_traces: ["session-replacement"],
      evidence: ["repair counterexamples: 2"],
    }))}\n`);

    const result = await runProcess(["check", "--state-dir", stateDir, "--json"]);
    const payload = JSON.parse(result.stdout);

    assert.equal(result.exitCode, 1);
    assert.ok(payload.checks.some((check) => check.name === "candidate_ledger" && check.message.includes("successful validation evidence")));
  } finally {
    await rm(stateDir, { force: true, recursive: true });
  }
});

test("check fails replacement candidates with unknown targets or traces", async () => {
  const stateDir = await mkdtemp(join(tmpdir(), "precedent-check-test-"));

  try {
    await promoteWebhookPrecedent(stateDir);
    await appendFile(join(stateDir, "candidates.jsonl"), `${JSON.stringify(replacementCandidate({
      id: "cand_replace_unknown",
      replaces: ["prec_missing"],
      source_traces: ["session-missing"],
    }))}\n`);

    const result = await runProcess(["check", "--state-dir", stateDir, "--json"]);
    const payload = JSON.parse(result.stdout);

    assert.equal(result.exitCode, 1);
    assert.ok(payload.checks.some((check) => check.name === "candidate_ledger" && check.message.includes("source trace session-missing is missing")));
    assert.ok(payload.checks.some((check) => check.name === "candidate_ledger" && check.message.includes("replaces unknown promoted precedent prec_missing")));
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

async function writeCandidateTrace(stateDir, id) {
  await writeFile(join(stateDir, "traces", `${id}.json`), `${JSON.stringify({
    schema_version: "precedent.v1",
    id,
    sessionId: id.replace(/^session-/u, ""),
    outcome: "success",
    failures: [],
    changedFiles: ["features/webhooks/providers/stripe.ts"],
  })}\n`);
}

function replacementCandidate(overrides) {
  return {
    id: "cand_replace_prec_webhook_replay_boundary_demo",
    status: "candidate",
    reason: "repair_efficacy_replacement",
    replaces: ["prec_webhook_replay_boundary"],
    scope: "feature:webhooks",
    source_traces: ["session-replacement"],
    failure_types: ["repair_efficacy_replacement"],
    evidence: [
      "repair counterexamples: 2",
      "successful validation: pnpm test:webhooks exited 0",
    ],
    injection: "Prefer the validated replacement.",
    promotion_required: "Replay before promotion.",
    ...overrides,
  };
}

function runJson(args) {
  return runProcess(args).then((result) => {
    if (result.exitCode !== 0) {
      throw new Error(`precedent ${args.join(" ")} failed\n${result.stderr}`);
    }

    return JSON.parse(result.stdout);
  });
}

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
    hook: "validation.after_run",
    sessionId: "success-session",
    command: "pnpm test:webhooks",
    exitCode: 0,
  });
  await hook(stateDir, {
    schema_version: "precedent.v1",
    hook: "outcome.after_task",
    sessionId: "success-session",
    success: true,
    status: "success",
  });
}

function hook(stateDir, event) {
  return runProcess(["hook", "--state-dir", stateDir, "--json"], event).then((result) => {
    if (result.exitCode !== 0) {
      throw new Error(`hook failed\n${result.stderr}`);
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
