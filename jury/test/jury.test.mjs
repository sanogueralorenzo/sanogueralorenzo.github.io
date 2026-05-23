import test from "node:test";
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { mkdtemp, rm, readFile, appendFile, cp, stat } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const repoRoot = resolve(__dirname, "../..");
const cliPath = join(repoRoot, "jury/bin/jury.mjs");
const fixturesDir = join(repoRoot, "jury/fixtures/verdicts");
const invalidSchemaDir = join(repoRoot, "jury/fixtures/schemas");
const ciQuickstartFixturesDir = join(repoRoot, "jury/examples/ci/fixtures/quickstart");
const releasePath = join(repoRoot, "jury/release.json");
const fixedEnv = { ...process.env, JURY_NOW: "2026-05-23T00:00:00.000Z" };
const skipNestedCiAdoptionTests = process.env.JURY_SKIP_CI_ADOPTION_NESTED === "1";

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
    const transcript = JSON.parse(await readFile(join(cwd, "jury-demo-transcript.json"), "utf8"));

    assert.equal(result.exitCode, 0);
    assert.equal(payload.ok, true);
    assert.equal(payload.retryVerdict.decision, "retry");
    assert.equal(verdict.decision, "accept");
    assert.deepEqual(transcript.map((step) => step.step), [
      "claim_created",
      "check_created",
      "evidence_collected",
      "objection_opened",
      "first_verdict",
      "objection_resolved",
      "check_passed",
      "final_verdict",
    ]);
    assert.equal(transcript.find((step) => step.step === "first_verdict").decision, "retry");
    assert.equal(transcript.find((step) => step.step === "final_verdict").decision, "accept");
  } finally {
    await rm(stateDir, { recursive: true, force: true });
    await rm(cwd, { recursive: true, force: true });
  }
});

test("documented core flow commands stay in sync with CLI behavior", async () => {
  const stateDir = await tempState();
  const cwd = await tempState();

  try {
    const cliDoc = await readFile(join(repoRoot, "jury/CLI.md"), "utf8");
    const match = cliDoc.match(/## Core Flow\n\n```shell\n([\s\S]*?)\n```/);

    assert.ok(match, "CLI.md must contain a Core Flow shell block");

    const commands = match[1].split("\n").filter((line) => line.startsWith("node jury/bin/jury.mjs "));
    const verdictPath = join(cwd, "verdict.json");
    const bundlePath = join(cwd, "review-bundle.json");

    for (const command of commands) {
      const result = await runShell(materializeDocCommand(command, stateDir, verdictPath, bundlePath), repoRoot);

      assert.equal(result.exitCode, 0, `${command}\nstdout:\n${result.stdout}\nstderr:\n${result.stderr}`);
    }

    const verdict = JSON.parse(await readFile(verdictPath, "utf8"));
    const bundle = JSON.parse(await readFile(bundlePath, "utf8"));
    assert.equal(verdict.decision, "accept");
    assert.equal(bundle.schema_version, "jury.review_bundle.v1");
    assert.equal(bundle.claim_id, "claim_ready");
  } finally {
    await rm(stateDir, { recursive: true, force: true });
    await rm(cwd, { recursive: true, force: true });
  }
});

test("quickstart commands produce a portable CI review from a clean checkout", { skip: skipNestedCiAdoptionTests }, async () => {
  const checkout = await copyJuryCheckout();

  try {
    const quickstart = await readFile(join(checkout, "jury/QUICKSTART.md"), "utf8");
    const commands = extractShellBlock(quickstart, "Jury Quickstart");
    const replayCommands = extractShellBlock(quickstart, "To replay the portable bundle");

    assert.equal(commands[0], "npm --prefix jury test");

    for (const command of commands) {
      const result = await runShell(command, checkout, nestedCiAdoptionEnv());

      assert.equal(result.exitCode, 0, `${command}\nstdout:\n${result.stdout}\nstderr:\n${result.stderr}`);
    }

    await assertAcceptedCiReview(checkout, ".jury", "verdict.json", "review-bundle.json", "gate.json");
    await assertQuickstartFixturesMatch(checkout);

    for (const command of replayCommands) {
      const result = await runShell(command, checkout);

      assert.equal(result.exitCode, 0, `${command}\nstdout:\n${result.stdout}\nstderr:\n${result.stderr}`);
    }

    const importedVerdict = JSON.parse(await readFile(join(checkout, "imported-verdict.json"), "utf8"));
    assert.equal(importedVerdict.decision, "accept");
  } finally {
    await rm(checkout, { recursive: true, force: true });
  }
});

test("GitHub Actions example builds the documented verdict and review bundle", { skip: skipNestedCiAdoptionTests }, async () => {
  const checkout = await copyJuryCheckout();

  try {
    const workflow = await readFile(join(checkout, "jury/examples/ci/jury-review-gate.yml"), "utf8");
    const commands = extractWorkflowRunBlock(workflow, "Build Jury verdict and bundle");
    const testCommand = extractWorkflowSingleLineRun(workflow, "Run Jury tests");

    assert.ok(workflow.includes("actions/upload-artifact@v4"));

    const testResult = await runShell(testCommand, checkout, nestedCiAdoptionEnv());
    assert.equal(testResult.exitCode, 0, `${testCommand}\nstdout:\n${testResult.stdout}\nstderr:\n${testResult.stderr}`);

    for (const command of commands) {
      const result = await runShell(command, checkout);

      assert.equal(result.exitCode, 0, `${command}\nstdout:\n${result.stdout}\nstderr:\n${result.stderr}`);
    }

    await assertAcceptedCiReview(checkout, ".jury", "verdict.json", "review-bundle.json", "gate.json");
    await assertQuickstartFixturesMatch(checkout);
  } finally {
    await rm(checkout, { recursive: true, force: true });
  }
});

test("CI example README points to the copyable workflow and portable artifacts", { skip: skipNestedCiAdoptionTests }, async () => {
  const readme = await readFile(join(repoRoot, "jury/examples/ci/README.md"), "utf8");

  assert.ok(readme.includes("jury-review-gate.yml"));
  assert.ok(readme.includes("review-bundle.json"));
  assert.ok(readme.includes("gate.json"));
  assert.ok(readme.includes("actions/upload-artifact@v4"));
});

test("troubleshooting failure examples stay executable", async () => {
  const checkout = await copyJuryCheckout();

  try {
    const guide = await readFile(join(checkout, "jury/TROUBLESHOOTING.md"), "utf8");
    const cases = [
      ["Retry Example", "verdict.retry.json", "gate.retry.json", "review-bundle.retry.json", "retry"],
      ["Reject Example", "verdict.reject.json", "gate.reject.json", "review-bundle.reject.json", "reject"],
    ];

    for (const [heading, verdictFile, gateFile, bundleFile, decision] of cases) {
      for (const command of extractShellBlock(guide, heading)) {
        const result = await runShell(command, checkout);

        assert.equal(result.exitCode, 0, `${heading}: ${command}\nstdout:\n${result.stdout}\nstderr:\n${result.stderr}`);
      }

      const verdict = JSON.parse(await readFile(join(checkout, verdictFile), "utf8"));
      const gate = JSON.parse(await readFile(join(checkout, gateFile), "utf8"));
      const bundle = JSON.parse(await readFile(join(checkout, bundleFile), "utf8"));

      assert.equal(verdict.decision, decision);
      assert.equal(gate.ok, false);
      assert.equal(gate.decision, decision);
      assert.equal(bundle.schema_version, "jury.review_bundle.v1");
      assert.equal(bundle.records.verdicts.at(-1).decision, decision);
    }
  } finally {
    await rm(checkout, { recursive: true, force: true });
  }
});

test("troubleshooting guide documents gate and bundle inspection fields", async () => {
  const guide = await readFile(join(repoRoot, "jury/TROUBLESHOOTING.md"), "utf8");
  const readme = await readFile(join(repoRoot, "jury/README.md"), "utf8");
  const checklist = await readFile(join(repoRoot, "jury/RELEASE_CHECKLIST.md"), "utf8");

  for (const field of ["ok", "decision", "reason", "missing_fields", "unresolved_objections", "next_actions"]) {
    assert.ok(guide.includes(`\`${field}\``), `TROUBLESHOOTING.md should describe gate.${field}`);
  }

  for (const field of ["claim_id", "records.claims", "records.checks", "records.evidence", "records.objections", "records.verdicts"]) {
    assert.ok(guide.includes(`\`${field}\``), `TROUBLESHOOTING.md should describe bundle.${field}`);
  }

  assert.ok(readme.includes("TROUBLESHOOTING.md"));
  assert.ok(checklist.includes("TROUBLESHOOTING.md"));
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

test("check validates explicit schema fixtures", async () => {
  const stateDir = await tempState();

  try {
    await runJson(["init", "--state-dir", stateDir]);

    const healthy = await runJson(["check", "--state-dir", stateDir, "--strict"]);
    assert.ok(healthy.checks.some((check) => check.name === "schema_files" && check.ok === true));

    const invalid = await runProcess(["check", "--state-dir", stateDir, "--schema-dir", invalidSchemaDir, "--strict", "--json"]);
    const payload = JSON.parse(invalid.stdout);

    assert.equal(invalid.exitCode, 1);
    assert.ok(payload.checks.some((check) => check.name === "schema_files" && check.ok === false && check.message.includes("required")));
  } finally {
    await rm(stateDir, { recursive: true, force: true });
  }
});

test("deterministic critics raise tests, security, and scope objections", async () => {
  const stateDir = await tempState();

  try {
    await runJson(["init", "--state-dir", stateDir]);
    const claim = await runJson(["claim", "create", "--state-dir", stateDir, "--summary", "database cleanup is ready", "--scope", "src/checkout"]);

    const tests = await runJson(["critic", "run", "--state-dir", stateDir, "--claim", claim.id, "--role", "tests"]);
    assert.equal(tests.objections[0].id, `obj_${claim.id}_tests_missing_test_evidence`);
    assert.equal(tests.objections[0].severity, "high");

    await runJson(["evidence", "add", "--state-dir", stateDir, "--claim", claim.id, "--type", "command", "--command", "delete_accounts --tenant prod", "--exit-code", "0"]);
    const security = await runJson(["critic", "run", "--state-dir", stateDir, "--claim", claim.id, "--role", "security"]);
    assert.equal(security.objections[0].id, `obj_${claim.id}_security_risky_evidence`);
    assert.equal(security.objections[0].severity, "critical");

    const scope = await runJson(["critic", "run", "--state-dir", stateDir, "--claim", claim.id, "--role", "scope", "--changed-files", "src/billing/delete.ts"]);
    assert.equal(scope.objections[0].id, `obj_${claim.id}_scope_out_of_scope_changes`);
    assert.match(scope.objections[0].summary, /src\/billing\/delete\.ts/);
  } finally {
    await rm(stateDir, { recursive: true, force: true });
  }
});

test("gate explains exact missing fields and unresolved objections when state is provided", async () => {
  const stateDir = await tempState();

  try {
    await runJson(["init", "--state-dir", stateDir]);
    const claim = await runJson(["claim", "create", "--state-dir", stateDir, "--summary", "vague claim"]);
    const objection = await runJson(["critic", "run", "--state-dir", stateDir, "--claim", claim.id, "--role", "scope"]);
    await runJson(["judge", "--state-dir", stateDir, "--claim", claim.id, "--out", join(stateDir, "verdict.json")]);

    const result = await runProcess(["gate", "--state-dir", stateDir, "--claim", claim.id, "--verdict", join(stateDir, "verdict.json"), "--json"]);
    const payload = JSON.parse(result.stdout);

    assert.equal(result.exitCode, 1);
    assert.deepEqual(payload.missing_fields, ["evidence", "claim.scope"]);
    assert.deepEqual(payload.unresolved_objections, [{
      id: objection.objections[0].id,
      severity: "medium",
      summary: "The claim has no explicit scope.",
    }]);
  } finally {
    await rm(stateDir, { recursive: true, force: true });
  }
});

test("claim transitions are explicit, validated, and append-only", async () => {
  const stateDir = await tempState();

  try {
    await runJson(["init", "--state-dir", stateDir]);
    const claim = await runJson(["claim", "create", "--state-dir", stateDir, "--summary", "checkout fix is ready"]);
    const screening = await runJson(["claim", "transition", "--state-dir", stateDir, "--claim", claim.id, "--status", "screening", "--reason", "review accepted"]);
    const inReview = await runJson(["claim", "transition", "--state-dir", stateDir, "--claim", claim.id, "--status", "in_review"]);

    assert.equal(screening.version, 2);
    assert.equal(inReview.version, 3);
    assert.equal(inReview.status, "in_review");

    const invalid = await runProcess(["claim", "transition", "--state-dir", stateDir, "--claim", claim.id, "--status", "archived", "--json"]);
    assert.equal(invalid.exitCode, 1);
    assert.match(invalid.stderr, /invalid claim transition: in_review -> archived/);

    const lines = (await readFile(join(stateDir, "claims.jsonl"), "utf8")).trim().split("\n");
    assert.equal(lines.length, 3);
  } finally {
    await rm(stateDir, { recursive: true, force: true });
  }
});

test("durable check records influence verdicts and remain append-only", async () => {
  const stateDir = await tempState();

  try {
    await runJson(["init", "--state-dir", stateDir]);
    const claim = await runJson(["claim", "create", "--state-dir", stateDir, "--summary", "checkout fix is ready", "--scope", "src/checkout"]);
    await runJson(["evidence", "add", "--state-dir", stateDir, "--claim", claim.id, "--type", "command", "--command", "npm test", "--exit-code", "0"]);
    const check = await runJson(["check", "add", "--state-dir", stateDir, "--claim", claim.id, "--type", "verifier", "--summary", "regression tests pass"]);

    const retry = await runJson(["judge", "--state-dir", stateDir, "--claim", claim.id]);
    assert.equal(retry.decision, "retry");
    assert.deepEqual(retry.check_ids, [check.id]);
    assert.ok(retry.next_actions.some((action) => action.includes(check.id)));

    await runJson(["check", "update", "--state-dir", stateDir, "--id", check.id, "--status", "passed", "--resolution", "npm test passed"]);
    const accept = await runJson(["judge", "--state-dir", stateDir, "--claim", claim.id, "--out", join(stateDir, "verdict.json")]);
    assert.equal(accept.decision, "accept");
    assert.deepEqual(accept.check_ids, [check.id]);

    const gate = await runJson(["gate", "--state-dir", stateDir, "--claim", claim.id, "--verdict", join(stateDir, "verdict.json")]);
    assert.equal(gate.ok, true);
    assert.deepEqual(gate.unresolved_objections, []);

    const lines = (await readFile(join(stateDir, "checks.jsonl"), "utf8")).trim().split("\n");
    assert.equal(lines.length, 2);
  } finally {
    await rm(stateDir, { recursive: true, force: true });
  }
});

test("check rejects malformed durable check records", async () => {
  const stateDir = await tempState();

  try {
    await runJson(["init", "--state-dir", stateDir]);
    await appendFile(join(stateDir, "checks.jsonl"), `${JSON.stringify({
      schema_version: "jury.check.v1",
      id: "check_bad",
      claim_id: "claim_bad",
      type: "verifier",
      required: true,
      status: "passed",
      assigned_to: "verifier:local",
      summary: "bad check",
      evidence_ids: [],
      created_at: "2026-05-23T00:00:00.000Z",
      updated_at: "2026-05-23T00:00:00.000Z",
    })}\n`);

    const result = await runProcess(["check", "--state-dir", stateDir, "--strict", "--json"]);
    const payload = JSON.parse(result.stdout);

    assert.equal(result.exitCode, 1);
    assert.ok(payload.checks.some((check) => check.name === "checks" && check.ok === false && check.message.includes("check.resolution")));
  } finally {
    await rm(stateDir, { recursive: true, force: true });
  }
});

test("check reports malformed cross-references across claims and verdicts", async () => {
  const stateDir = await tempState();

  try {
    await runJson(["init", "--state-dir", stateDir]);
    const claim = await runJson(["claim", "create", "--state-dir", stateDir, "--id", "claim_one", "--summary", "claim one"]);
    const other = await runJson(["claim", "create", "--state-dir", stateDir, "--id", "claim_two", "--summary", "claim two"]);
    const evidence = await runJson(["evidence", "add", "--state-dir", stateDir, "--claim", other.id, "--type", "manual", "--source", "note", "--summary", "other evidence"]);

    await appendFile(join(stateDir, "checks.jsonl"), `${JSON.stringify({
      schema_version: "jury.check.v1",
      id: "check_bad_ref",
      claim_id: claim.id,
      type: "verifier",
      required: true,
      status: "pending",
      assigned_to: "verifier:local",
      summary: "bad reference",
      evidence_ids: [evidence.id, "ev_missing"],
      resolution: null,
      created_at: "2026-05-23T00:00:00.000Z",
      updated_at: "2026-05-23T00:00:00.000Z",
    })}\n`);
    await appendFile(join(stateDir, "verdicts.jsonl"), `${JSON.stringify({
      schema_version: "jury.verdict.v1",
      id: "verdict_bad_ref",
      claim_id: claim.id,
      claim_version: 99,
      decision: "accept",
      reason: "bad fixture",
      next_actions: [],
      evidence_ids: [evidence.id],
      objection_ids: ["obj_missing"],
      waiver_ids: [],
      check_ids: ["check_missing"],
      decided_by: "judge:test",
      decided_at: "2026-05-23T00:00:00.000Z",
    })}\n`);

    const result = await runProcess(["check", "--state-dir", stateDir, "--strict", "--json"]);
    const payload = JSON.parse(result.stdout);
    const consistency = payload.checks.find((check) => check.name === "state_consistency");

    assert.equal(result.exitCode, 1);
    assert.equal(consistency.ok, false);
    assert.match(consistency.message, /check check_bad_ref evidence_ids references missing record ev_missing/);
    assert.match(consistency.message, /check check_bad_ref evidence_ids references ev_claim_two_note from claim claim_two/);
    assert.match(consistency.message, /verdict verdict_bad_ref claim_version 99 does not match current claim version 1/);
    assert.match(consistency.message, /verdict verdict_bad_ref objection_ids references missing record obj_missing/);
    assert.match(consistency.message, /verdict verdict_bad_ref check_ids references missing record check_missing/);
  } finally {
    await rm(stateDir, { recursive: true, force: true });
  }
});

test("gate reports CI-friendly consistency diagnostics for stale verdicts", async () => {
  const stateDir = await tempState();

  try {
    await runJson(["init", "--state-dir", stateDir]);
    const claim = await runJson(["claim", "create", "--state-dir", stateDir, "--id", "claim_ci", "--summary", "CI change is ready", "--scope", "jury"]);
    await runJson(["evidence", "add", "--state-dir", stateDir, "--claim", claim.id, "--type", "command", "--command", "node --test jury/test/*.test.mjs", "--exit-code", "0"]);
    await runJson(["judge", "--state-dir", stateDir, "--claim", claim.id, "--out", join(stateDir, "verdict.json")]);
    await runJson(["claim", "transition", "--state-dir", stateDir, "--claim", claim.id, "--status", "screening"]);

    const result = await runProcess(["gate", "--state-dir", stateDir, "--claim", claim.id, "--verdict", join(stateDir, "verdict.json"), "--json"]);
    const payload = JSON.parse(result.stdout);

    assert.equal(result.exitCode, 1);
    assert.equal(payload.ok, false);
    assert.equal(payload.reason, "Verdict does not match current claim state.");
    assert.deepEqual(payload.consistency_errors, ["verdict.claim_version 1 does not match current claim version 2"]);
    assert.deepEqual(payload.missing_fields, []);
    assert.deepEqual(payload.unresolved_objections, []);
  } finally {
    await rm(stateDir, { recursive: true, force: true });
  }
});

test("release metadata references existing schemas, exports, and commands", async () => {
  const release = JSON.parse(await readFile(releasePath, "utf8"));
  const packageJson = JSON.parse(await readFile(join(repoRoot, "jury/package.json"), "utf8"));

  assert.equal(release.schema_version, "jury.release.v1");
  assert.equal(release.name, packageJson.name);
  assert.equal(release.version, packageJson.version);
  assert.equal(release.cli.entrypoint, "bin/jury.mjs");
  assert.deepEqual(release.state.files, [
    "claims.jsonl",
    "checks.jsonl",
    "evidence.jsonl",
    "objections.jsonl",
    "waivers.jsonl",
    "verdicts.jsonl",
  ]);

  for (const relativePath of Object.values(release.schemas)) {
    const schema = JSON.parse(await readFile(join(repoRoot, "jury", relativePath), "utf8"));
    assert.equal(schema.type, "object");
    assert.ok(Array.isArray(schema.required));
  }

  for (const relativePath of Object.values(release.exports)) {
    const artifact = JSON.parse(await readFile(join(repoRoot, "jury", relativePath), "utf8"));
    assert.match(artifact.schema_version, /^jury\.(check|verdict|review_bundle)\.v1$/);
  }

  for (const commandName of ["judge", "gate", "bundle export", "bundle import", "check", "demo code-change"]) {
    assert.ok(release.cli.commands.includes(commandName), `${commandName} must be listed`);
  }
});

test("review bundle exports from local state and imports into fresh state", async () => {
  const sourceDir = await tempState();
  const importedDir = await tempState();
  const cwd = await tempState();
  const verdictPath = join(cwd, "verdict.json");
  const bundlePath = join(cwd, "review-bundle.json");

  try {
    await runJson(["init", "--state-dir", sourceDir]);
    await runJson(["claim", "create", "--state-dir", sourceDir, "--id", "claim_bundle", "--summary", "bundle claim is ready", "--scope", "jury", "--impact", "high"]);
    await runJson(["check", "add", "--state-dir", sourceDir, "--id", "check_bundle_tests", "--claim", "claim_bundle", "--type", "verifier", "--summary", "tests must pass"]);
    await runJson(["evidence", "add", "--state-dir", sourceDir, "--id", "ev_bundle_tests", "--claim", "claim_bundle", "--type", "command", "--command", "node --test jury/test/*.test.mjs", "--exit-code", "0"]);
    await runJson(["check", "update", "--state-dir", sourceDir, "--id", "check_bundle_tests", "--status", "passed", "--evidence", "ev_bundle_tests", "--resolution", "tests passed"]);
    const verdict = await runJson(["judge", "--state-dir", sourceDir, "--claim", "claim_bundle", "--out", verdictPath]);
    const bundle = await runJson(["bundle", "export", "--state-dir", sourceDir, "--claim", "claim_bundle", "--out", bundlePath]);

    assert.equal(verdict.decision, "accept");
    assert.equal(bundle.schema_version, "jury.review_bundle.v1");
    assert.equal(bundle.records.claims.length, 1);
    assert.equal(bundle.records.checks.length, 2);
    assert.equal(bundle.records.evidence.length, 1);
    assert.equal(bundle.records.verdicts.length, 1);

    await runJson(["init", "--state-dir", importedDir]);
    const importedVerdictPath = join(cwd, "imported-verdict.json");
    const imported = await runJson(["bundle", "import", "--state-dir", importedDir, "--bundle", bundlePath, "--verdict-out", importedVerdictPath]);
    const importedVerdict = JSON.parse(await readFile(importedVerdictPath, "utf8"));
    const gate = await runJson(["gate", "--state-dir", importedDir, "--claim", "claim_bundle", "--verdict", importedVerdictPath]);
    const check = await runJson(["check", "--state-dir", importedDir, "--strict"]);

    assert.deepEqual(imported.imported, {
      claims: 1,
      checks: 2,
      evidence: 1,
      objections: 0,
      waivers: 0,
      verdicts: 1,
    });
    assert.equal(imported.verdictOut, importedVerdictPath);
    assert.equal(importedVerdict.id, verdict.id);
    assert.equal(gate.ok, true);
    assert.ok(check.checks.find((item) => item.name === "state_consistency").ok);
  } finally {
    await rm(sourceDir, { recursive: true, force: true });
    await rm(importedDir, { recursive: true, force: true });
    await rm(cwd, { recursive: true, force: true });
  }
});

test("exported check and verdict examples validate as portable CI artifacts", async () => {
  const stateDir = await tempState();
  const verdictOut = join(stateDir, "verdict.json");

  try {
    await runJson(["init", "--state-dir", stateDir]);
    await runJson(["claim", "create", "--state-dir", stateDir, "--id", "claim_ci_change", "--summary", "pull request is ready", "--scope", "jury"]);
    await runJson(["evidence", "add", "--state-dir", stateDir, "--id", "ev_ci_tests", "--claim", "claim_ci_change", "--type", "command", "--command", "node --test jury/test/*.test.mjs", "--exit-code", "0"]);
    const checkExample = JSON.parse(await readFile(join(repoRoot, "jury/examples/exports/check.passed.v1.json"), "utf8"));
    await appendFile(join(stateDir, "checks.jsonl"), `${JSON.stringify(checkExample)}\n`);
    await cp(join(repoRoot, "jury/examples/exports/verdict.accept.v1.json"), verdictOut);
    await appendFile(join(stateDir, "verdicts.jsonl"), `${JSON.stringify(JSON.parse(await readFile(verdictOut, "utf8")))}\n`);

    const gate = await runJson(["gate", "--state-dir", stateDir, "--claim", "claim_ci_change", "--verdict", verdictOut]);
    const check = await runJson(["check", "--state-dir", stateDir, "--strict"]);

    assert.equal(gate.ok, true);
    assert.ok(check.checks.find((item) => item.name === "state_consistency").ok);
  } finally {
    await rm(stateDir, { recursive: true, force: true });
  }
});

test("review bundle schema references the stable record schemas", async () => {
  const schema = JSON.parse(await readFile(join(repoRoot, "jury/schemas/review-bundle.schema.json"), "utf8"));
  const properties = schema.properties.records.properties;

  assert.equal(properties.claims.items.$ref, "claim.schema.json");
  assert.equal(properties.checks.items.$ref, "check.schema.json");
  assert.equal(properties.evidence.items.$ref, "evidence.schema.json");
  assert.equal(properties.objections.items.$ref, "objection.schema.json");
  assert.equal(properties.waivers.items.$ref, "waiver.schema.json");
  assert.equal(properties.verdicts.items.$ref, "verdict.schema.json");
});

test("migration doc preserves the release artifact contract", async () => {
  const migration = await readFile(join(repoRoot, "jury/MIGRATION.md"), "utf8");
  const release = JSON.parse(await readFile(releasePath, "utf8"));

  for (const artifact of release.ciArtifacts) {
    assert.ok(migration.includes(artifact), `MIGRATION.md should mention ${artifact}`);
  }

  assert.ok(migration.includes("verdict.json"));
  assert.ok(migration.includes(".jury/*.jsonl"));
  assert.ok(migration.includes("release.json"));
});

test("release checklist links the adoption path and valid artifacts", async () => {
  const checklistPath = join(repoRoot, "jury/RELEASE_CHECKLIST.md");
  const checklist = await readFile(checklistPath, "utf8");
  const readme = await readFile(join(repoRoot, "jury/README.md"), "utf8");
  const release = JSON.parse(await readFile(releasePath, "utf8"));
  const linkedTargets = [...checklist.matchAll(/\[[^\]]+\]\(([^)]+)\)/g)].map((match) => match[1]);

  for (const requiredLink of [
    "QUICKSTART.md",
    "examples/ci/jury-review-gate.yml",
    "examples/ci/fixtures/quickstart",
    "MIGRATION.md",
    "TROUBLESHOOTING.md",
    "MAINTAINER_HANDOFF.md",
    "examples/ci/fixtures/quickstart/verdict.json",
    "examples/ci/fixtures/quickstart/review-bundle.json",
    "examples/ci/fixtures/quickstart/gate.json",
  ]) {
    assert.ok(linkedTargets.includes(requiredLink), `RELEASE_CHECKLIST.md should link ${requiredLink}`);
  }

  for (const target of linkedTargets) {
    await stat(join(dirname(checklistPath), target));
  }

  for (const artifact of ["verdict.json", "gate.json", "review-bundle.json", ".jury/*.jsonl"]) {
    assert.ok(checklist.includes(artifact), `RELEASE_CHECKLIST.md should mention ${artifact}`);
    assert.ok(release.ciArtifacts.includes(artifact), `release.json should list ${artifact}`);
  }

  assert.ok(readme.includes("RELEASE_CHECKLIST.md"));

  const verdict = JSON.parse(await readFile(join(ciQuickstartFixturesDir, "verdict.json"), "utf8"));
  const bundle = JSON.parse(await readFile(join(ciQuickstartFixturesDir, "review-bundle.json"), "utf8"));
  const gate = JSON.parse(await readFile(join(ciQuickstartFixturesDir, "gate.json"), "utf8"));

  assert.equal(verdict.schema_version, "jury.verdict.v1");
  assert.equal(verdict.decision, "accept");
  assert.equal(bundle.schema_version, "jury.review_bundle.v1");
  assert.equal(bundle.claim_id, "claim_ci_change");
  assert.equal(gate.ok, true);
  assert.equal(gate.decision, "accept");
});

test("maintainer handoff references current adoption artifacts and validation commands", async () => {
  const handoffPath = join(repoRoot, "jury/MAINTAINER_HANDOFF.md");
  const handoff = await readFile(handoffPath, "utf8");
  const readme = await readFile(join(repoRoot, "jury/README.md"), "utf8");
  const checklist = await readFile(join(repoRoot, "jury/RELEASE_CHECKLIST.md"), "utf8");
  const linkedTargets = [...handoff.matchAll(/\[[^\]]+\]\(([^)]+)\)/g)].map((match) => match[1]);

  for (const requiredLink of [
    "QUICKSTART.md",
    "examples/ci/jury-review-gate.yml",
    "examples/ci/fixtures/quickstart",
    "MIGRATION.md",
    "RELEASE_CHECKLIST.md",
    "TROUBLESHOOTING.md",
  ]) {
    assert.ok(linkedTargets.includes(requiredLink), `MAINTAINER_HANDOFF.md should link ${requiredLink}`);
  }

  for (const target of linkedTargets) {
    await stat(join(dirname(handoffPath), target));
  }

  const commands = extractShellBlock(handoff, "Validation");
  assert.deepEqual(commands, [
    "npm --prefix jury test",
    "npm --prefix jury run check -- --state-dir /tmp/jury-maintainer-handoff --json",
  ]);

  for (const artifact of ["verdict.json", "gate.json", "review-bundle.json"]) {
    assert.ok(handoff.includes(artifact), `MAINTAINER_HANDOFF.md should mention ${artifact}`);
  }

  assert.match(handoff, /schema validation for imported `review-bundle\.json` files/);
  assert.match(handoff, /without mutating `\.jury\/`/);
  assert.ok(readme.includes("MAINTAINER_HANDOFF.md"));
  assert.ok(checklist.includes("MAINTAINER_HANDOFF.md"));
});

function tempState() {
  return mkdtemp(join(tmpdir(), "jury-test-"));
}

function nestedCiAdoptionEnv() {
  return { ...fixedEnv, JURY_SKIP_CI_ADOPTION_NESTED: "1" };
}

async function copyJuryCheckout() {
  const checkout = await tempState();
  await cp(join(repoRoot, "jury"), join(checkout, "jury"), { recursive: true });
  return checkout;
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

function materializeDocCommand(command, stateDir, verdictPath) {
  let materialized = command;

  materialized = materialized.replace("--out verdict.json", `--out ${shellQuote(verdictPath)}`);
  materialized = materialized.replace("--verdict verdict.json", `--verdict ${shellQuote(verdictPath)}`);
  materialized = materialized.replace("--out review-bundle.json", `--out ${shellQuote(join(dirname(verdictPath), "review-bundle.json"))}`);

  if (!materialized.includes("--state-dir ")) {
    materialized += ` --state-dir ${shellQuote(stateDir)}`;
  }

  materialized += " --json";
  return materialized;
}

function runShell(command, cwd = repoRoot, env = fixedEnv) {
  return new Promise((resolveProcess) => {
    const child = spawn(command, {
      cwd,
      env,
      shell: true,
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

async function assertAcceptedCiReview(cwd, stateDir, verdictPath, bundlePath, gatePath) {
  const verdict = JSON.parse(await readFile(join(cwd, verdictPath), "utf8"));
  const bundle = JSON.parse(await readFile(join(cwd, bundlePath), "utf8"));
  const gate = JSON.parse(await readFile(join(cwd, gatePath), "utf8"));
  const check = await runShell(`node jury/bin/jury.mjs check --state-dir ${shellQuote(stateDir)} --strict --json`, cwd);

  assert.equal(verdict.decision, "accept");
  assert.equal(bundle.schema_version, "jury.review_bundle.v1");
  assert.equal(bundle.claim_id, "claim_ci_change");
  assert.equal(gate.ok, true);
  assert.equal(gate.decision, "accept");
  assert.equal(check.exitCode, 0, check.stderr);
  assert.ok(JSON.parse(check.stdout).checks.every((item) => item.ok));
}

async function assertQuickstartFixturesMatch(cwd) {
  for (const filename of ["verdict.json", "review-bundle.json", "gate.json"]) {
    const generated = JSON.parse(await readFile(join(cwd, filename), "utf8"));
    const expected = JSON.parse(await readFile(join(ciQuickstartFixturesDir, filename), "utf8"));

    assert.deepEqual(generated, expected, `${filename} should match quickstart fixture`);
  }
}

function extractShellBlock(markdown, heading) {
  const headingIndex = markdown.indexOf(heading);
  assert.notEqual(headingIndex, -1, `${heading} heading should exist`);

  const blockStart = markdown.indexOf("```shell\n", headingIndex);
  assert.notEqual(blockStart, -1, `${heading} shell block should exist`);

  const contentStart = blockStart + "```shell\n".length;
  const blockEnd = markdown.indexOf("\n```", contentStart);
  assert.notEqual(blockEnd, -1, `${heading} shell block should close`);

  return markdown.slice(contentStart, blockEnd).split("\n").filter(Boolean);
}

function extractWorkflowRunBlock(workflow, stepName) {
  const lines = workflow.split("\n");
  const nameIndex = lines.findIndex((line) => line.trim() === `- name: ${stepName}`);
  assert.notEqual(nameIndex, -1, `${stepName} step should exist`);

  const runIndex = lines.findIndex((line, index) => index > nameIndex && line.trim() === "run: |");
  assert.notEqual(runIndex, -1, `${stepName} run block should exist`);

  const commands = [];
  for (const line of lines.slice(runIndex + 1)) {
    if (!line.startsWith("          ")) {
      break;
    }
    commands.push(line.slice(10));
  }

  return commands.filter(Boolean);
}

function extractWorkflowSingleLineRun(workflow, stepName) {
  const lines = workflow.split("\n");
  const nameIndex = lines.findIndex((line) => line.trim() === `- name: ${stepName}`);
  assert.notEqual(nameIndex, -1, `${stepName} step should exist`);

  const runLine = lines.find((line, index) => index > nameIndex && line.trim().startsWith("run: "));
  assert.ok(runLine, `${stepName} run command should exist`);

  return runLine.trim().slice("run: ".length);
}

function shellQuote(value) {
  return `'${String(value).replaceAll("'", "'\\''")}'`;
}
