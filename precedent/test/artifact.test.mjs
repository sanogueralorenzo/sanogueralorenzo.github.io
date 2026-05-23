import test from "node:test";
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { appendFile, mkdtemp, readFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const repoRoot = resolve(__dirname, "../..");
const cliPath = join(repoRoot, "precedent/bin/precedent.mjs");

test("artifact renders deterministic non-injectable candidate skill preview", async () => {
  const stateDir = await mkdtemp(join(tmpdir(), "precedent-artifact-test-"));

  try {
    await createFailedCandidate(stateDir);

    const first = await runJson([
      "artifact",
      "--state-dir",
      stateDir,
      "--candidate",
      "cand_feature_webhooks_wrong_test_command",
      "--json",
    ]);
    const second = await runJson([
      "artifact",
      "--state-dir",
      stateDir,
      "--candidate",
      "cand_feature_webhooks_wrong_test_command",
      "--json",
    ]);
    const content = await readFile(first.artifactPath, "utf8");

    assert.equal(first.schema_version, "precedent.artifact.v1");
    assert.equal(first.injectable, false);
    assert.equal(first.promotable, false);
    assert.equal(first.artifactPath, second.artifactPath);
    assert.equal(first.artifactSha256, second.artifactSha256);
    assert.deepEqual(first.regenerateCommand, second.regenerateCommand);
    assert.match(content, /^# Candidate Skill: cand_feature_webhooks_wrong_test_command/u);
    assert.match(content, /Status: preview only\. Not injectable until replay promotion succeeds\./u);
    assert.match(content, /Replay the task with this candidate injected/u);
    assert.match(content, /wrong_test_command/u);

    const report = await runJson(["report", "--state-dir", stateDir, "--json"]);
    assert.equal(report.artifactHealth.rendered, 1);
    assert.equal(report.artifactHealth.stale, 0);
  } finally {
    await rm(stateDir, { force: true, recursive: true });
  }
});

test("artifact redacts candidate secrets before writing", async () => {
  const stateDir = await mkdtemp(join(tmpdir(), "precedent-artifact-test-"));
  const secret = "ghp_1234567890abcdef1234567890abcdef1234";

  try {
    await runJson(["init", "--state-dir", stateDir, "--json"]);
    await appendFile(join(stateDir, "candidates.jsonl"), `${JSON.stringify({
      id: "cand_secret_preview",
      status: "candidate",
      scope: "feature:webhooks",
      trigger: `debug token ${secret}`,
      lesson: `Never expose ${secret}`,
      artifact: "skill",
      paths: ["features/webhooks"],
      source_traces: ["session-secret"],
      failure_types: ["wrong_test_command"],
      evidence: [`stdout contained ${secret}`],
      injection: `Do not repeat ${secret}.`,
      promotion_required: "Replay before promotion.",
    })}\n`);

    const artifact = await runJson([
      "artifact",
      "--state-dir",
      stateDir,
      "--candidate",
      "cand_secret_preview",
      "--json",
    ]);
    const content = await readFile(artifact.artifactPath, "utf8");

    assert.doesNotMatch(content, new RegExp(secret, "u"));
    assert.match(content, /\[REDACTED:github_token\]/u);
  } finally {
    await rm(stateDir, { force: true, recursive: true });
  }
});

test("artifact fails clearly for unknown candidate", async () => {
  const stateDir = await mkdtemp(join(tmpdir(), "precedent-artifact-test-"));

  try {
    await runJson(["init", "--state-dir", stateDir, "--json"]);

    const result = await runProcess([
      "artifact",
      "--state-dir",
      stateDir,
      "--candidate",
      "cand_missing",
      "--json",
    ]);

    assert.equal(result.exitCode, 1);
    assert.match(result.stderr, /unknown candidate id: cand_missing/u);
  } finally {
    await rm(stateDir, { force: true, recursive: true });
  }
});

async function createFailedCandidate(stateDir) {
  await runJson(["init", "--state-dir", stateDir, "--json"]);
  await runJson([
    "attach-run",
    "--state-dir",
    stateDir,
    "--session",
    "failed-run",
    "--task",
    "add webhook handler",
    "--scope",
    "feature:webhooks",
    "--changed-files",
    "features/webhooks/providers/stripe.ts",
    "--validation-command",
    "node -e \"console.error('wrong test command'); process.exit(1)\"",
    "--json",
  ]);
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
