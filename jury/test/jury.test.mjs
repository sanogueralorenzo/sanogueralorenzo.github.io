import test from "node:test";
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { mkdtemp, rm, readFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const repoRoot = resolve(__dirname, "../..");
const cliPath = join(repoRoot, "jury/bin/jury.mjs");
const fixturesDir = join(repoRoot, "jury/fixtures/verdicts");
const fixedEnv = { ...process.env, JURY_NOW: "2026-05-23T00:00:00.000Z" };

test("judge accepts a claim with passing evidence and no blocking objections", async () => {
  const stateDir = await tempState();

  try {
    await runJson(["init", "--state-dir", stateDir]);
    const claim = await runJson(["claim", "create", "--state-dir", stateDir, "--summary", "checkout fix is ready", "--impact", "high"]);
    await runJson(["evidence", "add", "--state-dir", stateDir, "--claim", claim.id, "--type", "command", "--command", "npm test", "--exit-code", "0"]);

    const verdict = await runJson(["judge", "--state-dir", stateDir, "--claim", claim.id]);

    assert.equal(verdict.schema_version, "jury.verdict.v1");
    assert.equal(verdict.decision, "accept");
    assert.equal(verdict.evidence_ids.length, 1);
    assert.deepEqual(verdict.objection_ids, []);
  } finally {
    await rm(stateDir, { recursive: true, force: true });
  }
});

test("judge rejects a claim with failed command evidence", async () => {
  const stateDir = await tempState();

  try {
    await runJson(["init", "--state-dir", stateDir]);
    const claim = await runJson(["claim", "create", "--state-dir", stateDir, "--summary", "billing deploy is ready"]);
    await runJson(["evidence", "add", "--state-dir", stateDir, "--claim", claim.id, "--type", "command", "--command", "npm run smoke", "--exit-code", "1"]);

    const verdict = await runJson(["judge", "--state-dir", stateDir, "--claim", claim.id]);

    assert.equal(verdict.decision, "reject");
    assert.match(verdict.reason, /evidence failed/i);
  } finally {
    await rm(stateDir, { recursive: true, force: true });
  }
});

test("judge retries a claim with an unresolved blocking objection", async () => {
  const stateDir = await tempState();

  try {
    await runJson(["init", "--state-dir", stateDir]);
    const claim = await runJson(["claim", "create", "--state-dir", stateDir, "--summary", "report is ready"]);
    await runJson(["evidence", "add", "--state-dir", stateDir, "--claim", claim.id, "--type", "citation", "--source", "report.md", "--summary", "citation scan passed", "--status", "passed"]);
    const objection = await runJson(["objection", "add", "--state-dir", stateDir, "--claim", claim.id, "--summary", "one cited source is stale", "--severity", "high"]);

    const verdict = await runJson(["judge", "--state-dir", stateDir, "--claim", claim.id]);

    assert.equal(verdict.decision, "retry");
    assert.deepEqual(verdict.objection_ids, [objection.id]);
    assert.ok(verdict.next_actions.some((action) => action.includes(objection.id)));
  } finally {
    await rm(stateDir, { recursive: true, force: true });
  }
});

test("judge emits human_decision when explicit approval is required", async () => {
  const stateDir = await tempState();

  try {
    await runJson(["init", "--state-dir", stateDir]);
    const claim = await runJson(["claim", "create", "--state-dir", stateDir, "--summary", "agent may run cleanup tool", "--impact", "critical"]);
    await runJson(["evidence", "add", "--state-dir", stateDir, "--claim", claim.id, "--type", "tool_call_preview", "--source", "delete_accounts --tenant test", "--summary", "tool call preview", "--status", "passed"]);

    const verdict = await runJson(["judge", "--state-dir", stateDir, "--claim", claim.id, "--require-human-approval", "true"]);

    assert.equal(verdict.decision, "human_decision");
    assert.match(verdict.reason, /Human approval/);
  } finally {
    await rm(stateDir, { recursive: true, force: true });
  }
});

test("gate exits non-zero unless the verdict accepts the claim", async () => {
  const stateDir = await tempState();

  try {
    await runJson(["init", "--state-dir", stateDir]);
    const claim = await runJson(["claim", "create", "--state-dir", stateDir, "--summary", "claim with no evidence"]);
    await runJson(["judge", "--state-dir", stateDir, "--claim", claim.id, "--out", join(stateDir, "verdict.json")]);

    const result = await runProcess(["gate", "--verdict", join(stateDir, "verdict.json")]);
    const payload = JSON.parse(result.stdout);

    assert.equal(result.exitCode, 1);
    assert.equal(payload.ok, false);
    assert.equal(payload.decision, "retry");
  } finally {
    await rm(stateDir, { recursive: true, force: true });
  }
});

test("demo code-change writes an accepted verdict file", async () => {
  const stateDir = await tempState();
  const cwd = await tempState();

  try {
    const result = await runProcess(["demo", "code-change", "--state-dir", stateDir], cwd);
    const payload = JSON.parse(result.stdout);
    const verdict = JSON.parse(await readFile(join(cwd, "verdict.json"), "utf8"));

    assert.equal(result.exitCode, 0);
    assert.equal(payload.ok, true);
    assert.equal(verdict.decision, "accept");
  } finally {
    await rm(stateDir, { recursive: true, force: true });
    await rm(cwd, { recursive: true, force: true });
  }
});

test("fixture verdicts cover accept, reject, retry, and human_decision gate paths", async () => {
  const cases = [
    ["accept.json", 0, true, "accept"],
    ["reject.json", 1, false, "reject"],
    ["retry.json", 1, false, "retry"],
    ["human_decision.json", 1, false, "human_decision"],
  ];

  for (const [fixture, exitCode, ok, decision] of cases) {
    const result = await runProcess(["gate", "--verdict", join(fixturesDir, fixture)]);
    const payload = JSON.parse(result.stdout);

    assert.equal(result.exitCode, exitCode);
    assert.equal(payload.ok, ok);
    assert.equal(payload.decision, decision);
  }
});

function tempState() {
  return mkdtemp(join(tmpdir(), "jury-test-"));
}

function runJson(args, cwd = repoRoot) {
  return runProcess([...args, "--json"], cwd).then((result) => {
    if (result.exitCode !== 0) {
      throw new Error(`jury ${args.join(" ")} failed\nstdout:\n${result.stdout}\nstderr:\n${result.stderr}`);
    }

    return JSON.parse(result.stdout);
  });
}

function runProcess(args, cwd = repoRoot) {
  return new Promise((resolveProcess) => {
    const child = spawn(process.execPath, [cliPath, ...args], {
      cwd,
      env: fixedEnv,
      stdio: ["ignore", "pipe", "pipe"],
    });
    let stdout = "";
    let stderr = "";

    child.stdout.on("data", (chunk) => {
      stdout += chunk.toString();
    });
    child.stderr.on("data", (chunk) => {
      stderr += chunk.toString();
    });
    child.on("close", (exitCode) => {
      resolveProcess({ exitCode, stdout, stderr });
    });
  });
}
