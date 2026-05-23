import test from "node:test";
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { createHash, generateKeyPairSync } from "node:crypto";
import { mkdtemp, rm, readFile, writeFile, appendFile, cp, stat, mkdir } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const repoRoot = resolve(__dirname, "../..");
const cliPath = join(repoRoot, "jury/bin/jury.mjs");
const fixturesDir = join(repoRoot, "jury/fixtures/verdicts");
const invalidSchemaDir = join(repoRoot, "jury/fixtures/schemas");
const ciQuickstartFixturesDir = join(repoRoot, "jury/examples/ci/fixtures/quickstart");
const ciKeyPolicyFixturesDir = join(repoRoot, "jury/examples/ci/fixtures/key-policy");
const ciKeyPolicyRotationFixturesDir = join(repoRoot, "jury/examples/ci/fixtures/key-policy-rotation");
const ciPackageReleaseFixturesDir = join(repoRoot, "jury/examples/ci/fixtures/package-release");
const codeChangeAdoptionFixturesDir = join(repoRoot, "jury/examples/code-change-adoption");
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

test("code-change adoption fixture produces portable retry and accept evidence", async () => {
  const checkout = await copyJuryCheckout();

  try {
    const fixtureReadme = await readFile(join(checkout, "jury/examples/code-change-adoption/README.md"), "utf8");
    const rootReadme = await readFile(join(checkout, "jury/README.md"), "utf8");
    const examplesReadme = await readFile(join(checkout, "jury/examples/README.md"), "utf8");
    const commands = extractShellBlock(fixtureReadme, "Code-Change Adoption Flow");

    assert.ok(rootReadme.includes("examples/code-change-adoption"));
    assert.ok(examplesReadme.includes("code-change-adoption"));
    for (const requiredCommand of ["init", "claim create", "evidence add", "critic run", "judge", "gate", "bundle export", "bundle preflight", "check"]) {
      assert.ok(commands.some((command) => command.includes(`jury.mjs ${requiredCommand}`)), `fixture should run ${requiredCommand}`);
    }

    for (const command of commands) {
      const result = await runShell(command, checkout);

      assert.equal(result.exitCode, 0, `${command}\nstdout:\n${result.stdout}\nstderr:\n${result.stderr}`);
    }

    const verdict = JSON.parse(await readFile(join(checkout, "verdict.retry.json"), "utf8"));
    const gate = JSON.parse(await readFile(join(checkout, "gate.retry.json"), "utf8"));
    const bundle = JSON.parse(await readFile(join(checkout, "review-bundle.retry.json"), "utf8"));
    const acceptedVerdict = JSON.parse(await readFile(join(checkout, "verdict.accept.json"), "utf8"));
    const acceptedGate = JSON.parse(await readFile(join(checkout, "gate.accept.json"), "utf8"));
    const acceptedBundle = JSON.parse(await readFile(join(checkout, "review-bundle.accept.json"), "utf8"));

    assert.equal(verdict.decision, "retry");
    assert.deepEqual(verdict.evidence_ids, ["ev_jury_tests"]);
    assert.deepEqual(verdict.objection_ids, ["obj_claim_checkout_ready_scope_out_of_scope_changes"]);
    assert.ok(verdict.next_actions.some((action) => action.includes("docs/checkout-notes.md")));
    assert.equal(gate.ok, false);
    assert.equal(gate.decision, "retry");
    assert.deepEqual(gate.unresolved_objections.map((item) => item.id), ["obj_claim_checkout_ready_scope_out_of_scope_changes"]);
    assert.deepEqual(gate.next_actions, verdict.next_actions);
    assert.equal(bundle.schema_version, "jury.review_bundle.v1");
    assert.equal(bundle.claim_id, "claim_checkout_ready");
    assert.equal(bundle.provenance.revision, "code-change-adoption-fixture");
    assert.equal(bundle.records.evidence[0].command, "npm --prefix jury test");
    assert.equal(bundle.records.objections[0].raised_by, "critic:scope");
    assert.equal(bundle.records.verdicts[0].decision, "retry");
    assert.equal(acceptedVerdict.decision, "accept");
    assert.deepEqual(acceptedVerdict.next_actions, []);
    assert.deepEqual(acceptedVerdict.evidence_ids, ["ev_jury_tests", "ev_scope_corrected"]);
    assert.deepEqual(acceptedVerdict.objection_ids, ["obj_claim_checkout_ready_scope_out_of_scope_changes"]);
    assert.equal(acceptedGate.ok, true);
    assert.equal(acceptedGate.decision, "accept");
    assert.deepEqual(acceptedGate.unresolved_objections, []);
    assert.equal(acceptedBundle.schema_version, "jury.review_bundle.v1");
    assert.equal(acceptedBundle.claim_id, "claim_checkout_ready");
    assert.equal(acceptedBundle.records.evidence.find((item) => item.id === "ev_scope_corrected").source, "changed-files:jury/bin/jury.mjs");
    assert.equal(acceptedBundle.records.objections.at(-1).status, "resolved");
    assert.match(acceptedBundle.records.objections.at(-1).resolution, /Removed docs\/checkout-notes\.md/);
    assert.equal(acceptedBundle.records.verdicts.find((item) => item.id === "verdict_claim_checkout_ready_accept").decision, "accept");
    assert.equal(acceptedBundle.records.verdicts.find((item) => item.id === "verdict_claim_checkout_ready_retry").decision, "retry");

    for (const filename of ["verdict.retry.json", "gate.retry.json", "review-bundle.retry.json", "verdict.accept.json", "gate.accept.json", "review-bundle.accept.json"]) {
      const generated = JSON.parse(await readFile(join(checkout, filename), "utf8"));
      const expected = JSON.parse(await readFile(join(checkout, "jury/examples/code-change-adoption", filename), "utf8"));

      assert.deepEqual(generated, expected, `${filename} should match code-change adoption fixture`);
    }
  } finally {
    await rm(checkout, { recursive: true, force: true });
  }
});

test("code-change adoption reusable workflow publishes retry and accept bundles", { skip: skipNestedCiAdoptionTests }, async () => {
  const checkout = await copyJuryCheckout();
  const secretDir = await tempState();

  try {
    const workflow = await readFile(join(checkout, "jury/examples/ci/jury-code-change-adoption.yml"), "utf8");
    const testCommand = extractWorkflowSingleLineRun(workflow, "Run Jury tests");
    const writeKeyCommands = extractWorkflowRunBlock(workflow, "Write Jury code-change signing key");
    const commands = extractWorkflowRunBlock(workflow, "Build Jury code-change adoption fixture");
    const cleanupCommand = extractWorkflowSingleLineRun(workflow, "Remove Jury code-change signing key");
    const uploadPaths = extractWorkflowUploadPaths(workflow);
    const pair = generateKeyPairSync("rsa", {
      modulusLength: 2048,
      privateKeyEncoding: { type: "pkcs8", format: "pem" },
      publicKeyEncoding: { type: "spki", format: "pem" },
    });
    const privateKeyPath = join(secretDir, "jury-code-change-private.pem");
    const publicKeyPath = join(secretDir, "jury-code-change-public.pem");
    const env = {
      ...nestedCiAdoptionEnv(),
      JURY_STATE_DIR: ".jury-code-change",
      JURY_CI_PRIVATE_KEY: pair.privateKey,
      JURY_PRIVATE_KEY_PATH: privateKeyPath,
      JURY_ATTESTATION_KEY_ID: "ci-code-change-adoption",
    };

    await writeFile(publicKeyPath, pair.publicKey);

    assert.deepEqual(new Set(uploadPaths), new Set([
      "verdict.retry.json",
      "gate.retry.json",
      "review-bundle.retry.json",
      "review-bundle.retry.signed.json",
      "verdict.accept.json",
      "gate.accept.json",
      "review-bundle.accept.json",
      "review-bundle.accept.signed.json",
      "${{ inputs.state-dir }}/*.jsonl",
    ]));
    assert.ok(workflow.includes("secrets.JURY_CI_PRIVATE_KEY"));
    assert.ok(workflow.includes("${{ runner.temp }}/jury-code-change-private.pem"));
    assert.ok(workflow.includes("--attest-private-key \"$JURY_PRIVATE_KEY_PATH\""));
    assert.ok(workflow.includes("review-bundle.retry.signed.json"));
    assert.ok(workflow.includes("review-bundle.accept.signed.json"));
    assert.ok(workflow.includes("if: always()"));
    assert.ok(!workflow.includes("BEGIN PRIVATE KEY"));

    const testResult = await runShell(testCommand, checkout, env);
    assert.equal(testResult.exitCode, 0, `${testCommand}\nstdout:\n${testResult.stdout}\nstderr:\n${testResult.stderr}`);

    for (const command of writeKeyCommands) {
      const result = await runShell(command, checkout, env);

      assert.equal(result.exitCode, 0, `${command}\nstdout:\n${result.stdout}\nstderr:\n${result.stderr}`);
    }

    for (const command of commands) {
      const result = await runShell(command, checkout, env);

      assert.equal(result.exitCode, 0, `${command}\nstdout:\n${result.stdout}\nstderr:\n${result.stderr}`);
    }

    for (const filename of ["verdict.retry.json", "gate.retry.json", "review-bundle.retry.json", "verdict.accept.json", "gate.accept.json", "review-bundle.accept.json"]) {
      const generated = JSON.parse(await readFile(join(checkout, filename), "utf8"));
      const expected = JSON.parse(await readFile(join(checkout, "jury/examples/code-change-adoption", filename), "utf8"));

      assert.deepEqual(generated, expected, `${filename} should match code-change adoption fixture`);
    }

    const retryBundle = JSON.parse(await readFile(join(checkout, "review-bundle.retry.json"), "utf8"));
    const acceptedBundle = JSON.parse(await readFile(join(checkout, "review-bundle.accept.json"), "utf8"));
    const signedRetryBundle = JSON.parse(await readFile(join(checkout, "review-bundle.retry.signed.json"), "utf8"));
    const signedAcceptedBundle = JSON.parse(await readFile(join(checkout, "review-bundle.accept.signed.json"), "utf8"));
    const { attestation: signedRetryAttestation, ...signedRetryPayload } = signedRetryBundle;
    const { attestation: signedAcceptedAttestation, ...signedAcceptedPayload } = signedAcceptedBundle;

    assert.equal(acceptedBundle.records.verdicts.find((item) => item.id === "verdict_claim_checkout_ready_accept").decision, "accept");
    assert.deepEqual(signedRetryPayload, retryBundle);
    assert.deepEqual(signedAcceptedPayload, acceptedBundle);
    assert.equal(signedRetryAttestation.type, "rsa-sha256");
    assert.equal(signedRetryAttestation.key_id, "ci-code-change-adoption");
    assert.equal(signedAcceptedAttestation.type, "rsa-sha256");
    assert.equal(signedAcceptedAttestation.key_id, "ci-code-change-adoption");

    const signedRetryVerify = await runShell(`node jury/bin/jury.mjs bundle preflight --bundle review-bundle.retry.signed.json --require-attestation true --verify-attestation-public-key ${shellQuote(publicKeyPath)} --expect-attestation-key-id ci-code-change-adoption`, checkout, fixedEnv);
    const signedAcceptVerify = await runShell(`node jury/bin/jury.mjs bundle preflight --bundle review-bundle.accept.signed.json --require-attestation true --verify-attestation-public-key ${shellQuote(publicKeyPath)} --expect-attestation-key-id ci-code-change-adoption`, checkout, fixedEnv);

    assert.equal(signedRetryVerify.exitCode, 0, signedRetryVerify.stderr);
    assert.equal(JSON.parse(signedRetryVerify.stdout).ok, true);
    assert.equal(signedAcceptVerify.exitCode, 0, signedAcceptVerify.stderr);
    assert.equal(JSON.parse(signedAcceptVerify.stdout).ok, true);

    const downstreamImport = await runProcess([
      "bundle", "import",
      "--state-dir", join(checkout, ".jury-code-change-downstream"),
      "--bundle", join(checkout, "review-bundle.accept.json"),
      "--verdict-out", join(checkout, "downstream-verdict.accept.json"),
    ], checkout);
    const downstreamGate = await runProcess([
      "gate",
      "--state-dir", join(checkout, ".jury-code-change-downstream"),
      "--claim", "claim_checkout_ready",
      "--verdict", join(checkout, "downstream-verdict.accept.json"),
    ], checkout);
    const downstreamCheck = await runProcess(["check", "--state-dir", join(checkout, ".jury-code-change-downstream"), "--strict"], checkout);

    assert.equal(downstreamImport.exitCode, 0, downstreamImport.stderr);
    assert.equal(downstreamGate.exitCode, 0, downstreamGate.stderr);
    assert.equal(JSON.parse(downstreamGate.stdout).decision, "accept");
    assert.equal(downstreamCheck.exitCode, 0, downstreamCheck.stderr);

    const signedRetryDownstreamImport = await runProcess([
      "bundle", "import",
      "--state-dir", join(checkout, ".jury-code-change-signed-retry-downstream"),
      "--bundle", join(checkout, "review-bundle.retry.signed.json"),
      "--require-attestation", "true",
      "--verify-attestation-public-key", publicKeyPath,
      "--expect-attestation-key-id", "ci-code-change-adoption",
      "--verdict-out", join(checkout, "downstream-verdict.retry.signed.json"),
    ], checkout);
    const signedRetryDownstreamGate = await runProcess([
      "gate",
      "--state-dir", join(checkout, ".jury-code-change-signed-retry-downstream"),
      "--claim", "claim_checkout_ready",
      "--verdict", join(checkout, "downstream-verdict.retry.signed.json"),
    ], checkout);
    const signedRetryDownstreamCheck = await runProcess(["check", "--state-dir", join(checkout, ".jury-code-change-signed-retry-downstream"), "--strict"], checkout);
    const signedDownstreamImport = await runProcess([
      "bundle", "import",
      "--state-dir", join(checkout, ".jury-code-change-signed-downstream"),
      "--bundle", join(checkout, "review-bundle.accept.signed.json"),
      "--require-attestation", "true",
      "--verify-attestation-public-key", publicKeyPath,
      "--expect-attestation-key-id", "ci-code-change-adoption",
      "--verdict-out", join(checkout, "downstream-verdict.accept.signed.json"),
    ], checkout);
    const signedDownstreamGate = await runProcess([
      "gate",
      "--state-dir", join(checkout, ".jury-code-change-signed-downstream"),
      "--claim", "claim_checkout_ready",
      "--verdict", join(checkout, "downstream-verdict.accept.signed.json"),
    ], checkout);
    const signedDownstreamCheck = await runProcess(["check", "--state-dir", join(checkout, ".jury-code-change-signed-downstream"), "--strict"], checkout);
    const cleanup = await runShell(cleanupCommand, checkout, env);

    assert.equal(signedRetryDownstreamImport.exitCode, 0, signedRetryDownstreamImport.stderr);
    assert.equal(signedRetryDownstreamGate.exitCode, 1, signedRetryDownstreamGate.stderr);
    assert.equal(JSON.parse(signedRetryDownstreamGate.stdout).decision, "retry");
    assert.equal(signedRetryDownstreamCheck.exitCode, 0, signedRetryDownstreamCheck.stderr);
    assert.equal(signedDownstreamImport.exitCode, 0, signedDownstreamImport.stderr);
    assert.equal(signedDownstreamGate.exitCode, 0, signedDownstreamGate.stderr);
    assert.equal(JSON.parse(signedDownstreamGate.stdout).decision, "accept");
    assert.equal(signedDownstreamCheck.exitCode, 0, signedDownstreamCheck.stderr);
    assert.equal(cleanup.exitCode, 0, cleanup.stderr);
    await assertPathMissing(privateKeyPath);
  } finally {
    await rm(checkout, { recursive: true, force: true });
    await rm(secretDir, { recursive: true, force: true });
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

test("signed producer workflow signs a live review bundle with an external key", { skip: skipNestedCiAdoptionTests }, async () => {
  const checkout = await copyJuryCheckout();
  const secretDir = await tempState();

  try {
    const workflow = await readFile(join(checkout, "jury/examples/ci/jury-signed-review-gate.yml"), "utf8");
    const testCommand = extractWorkflowSingleLineRun(workflow, "Run Jury tests");
    const writeKeyCommands = extractWorkflowRunBlock(workflow, "Write Jury signing key");
    const commands = extractWorkflowRunBlock(workflow, "Build signed Jury verdict and bundle");
    const cleanupCommand = extractWorkflowSingleLineRun(workflow, "Remove Jury signing key");
    const pair = generateKeyPairSync("rsa", {
      modulusLength: 2048,
      privateKeyEncoding: { type: "pkcs8", format: "pem" },
      publicKeyEncoding: { type: "spki", format: "pem" },
    });
    const privateKeyPath = join(secretDir, "jury-ci-private.pem");
    const publicKeyPath = join(secretDir, "jury-ci-public.pem");
    const env = {
      ...nestedCiAdoptionEnv(),
      JURY_CI_PRIVATE_KEY: pair.privateKey,
      JURY_PRIVATE_KEY_PATH: privateKeyPath,
      JURY_ATTESTATION_KEY_ID: "ci-producer",
    };

    await writeFile(publicKeyPath, pair.publicKey);

    assert.ok(workflow.includes("secrets.JURY_CI_PRIVATE_KEY"));
    assert.ok(workflow.includes("${{ runner.temp }}/jury-ci-private.pem"));
    assert.ok(workflow.includes("--attest-private-key \"$JURY_PRIVATE_KEY_PATH\""));
    assert.ok(workflow.includes("review-bundle.signed.json"));
    assert.ok(workflow.includes("if: always()"));
    assert.ok(!workflow.includes("BEGIN PRIVATE KEY"));

    const testResult = await runShell(testCommand, checkout, env);
    assert.equal(testResult.exitCode, 0, `${testCommand}\nstdout:\n${testResult.stdout}\nstderr:\n${testResult.stderr}`);

    for (const command of writeKeyCommands) {
      const result = await runShell(command, checkout, env);

      assert.equal(result.exitCode, 0, `${command}\nstdout:\n${result.stdout}\nstderr:\n${result.stderr}`);
    }

    for (const command of commands) {
      const result = await runShell(command, checkout, env);

      assert.equal(result.exitCode, 0, `${command}\nstdout:\n${result.stdout}\nstderr:\n${result.stderr}`);
    }

    const bundle = JSON.parse(await readFile(join(checkout, "review-bundle.signed.json"), "utf8"));
    assert.equal(bundle.attestation.type, "rsa-sha256");
    assert.equal(bundle.attestation.key_id, "ci-producer");

    const verify = await runShell(`node jury/bin/jury.mjs bundle preflight --bundle review-bundle.signed.json --verify-attestation-public-key ${shellQuote(publicKeyPath)}`, checkout, fixedEnv);
    assert.equal(verify.exitCode, 0, verify.stderr);
    assert.equal(JSON.parse(verify.stdout).ok, true);

    const cleanup = await runShell(cleanupCommand, checkout, env);
    assert.equal(cleanup.exitCode, 0, cleanup.stderr);
    await assertPathMissing(privateKeyPath);
  } finally {
    await rm(secretDir, { recursive: true, force: true });
    await rm(checkout, { recursive: true, force: true });
  }
});

test("signed artifact handoff workflow verifies a downloaded producer artifact", { skip: skipNestedCiAdoptionTests }, async () => {
  const checkout = await copyJuryCheckout();
  const secretDir = await tempState();

  try {
    const workflow = await readFile(join(checkout, "jury/examples/ci/jury-signed-artifact-handoff.yml"), "utf8");
    const writeKeyCommands = extractWorkflowRunBlock(workflow, "Write Jury signing key");
    const producerCommands = extractWorkflowRunBlock(workflow, "Build signed Jury artifact");
    const commands = extractWorkflowRunBlock(workflow, "Verify downloaded Jury artifact");
    const artifactDir = join(checkout, "jury-review-artifact");
    const privateKeyPath = join(secretDir, "ci-private.pem");
    const pair = generateKeyPairSync("rsa", {
      modulusLength: 2048,
      privateKeyEncoding: { type: "pkcs8", format: "pem" },
      publicKeyEncoding: { type: "spki", format: "pem" },
    });
    const env = {
      ...fixedEnv,
      JURY_BUNDLE_PATH: "jury-review-artifact/review-bundle.signed.json",
      JURY_KEY_POLICY_PATH: "jury/examples/ci/fixtures/key-policy/jury-key-policy.json",
      JURY_STATE_DIR: ".jury-downstream",
      JURY_VERDICT_OUT: "downstream-verdict.json",
      JURY_GATE_OUT: "downstream-gate.json",
      JURY_CLAIM_ID: "claim_ci_change",
      JURY_CI_PRIVATE_KEY: pair.privateKey,
      JURY_PRIVATE_KEY_PATH: privateKeyPath,
      JURY_ATTESTATION_KEY_ID: "ci-fixture",
    };

    assert.ok(workflow.includes("needs: produce-signed-review"));
    assert.ok(workflow.includes("actions/download-artifact@v4"));
    assert.ok(workflow.includes("name: jury-signed-review"));
    assert.ok(workflow.includes("path: jury-review-artifact"));
    assert.ok(workflow.includes("--key-policy \"$JURY_KEY_POLICY_PATH\""));
    assert.ok(workflow.includes("--require-attestation true"));
    assert.ok(!workflow.includes("bundle preflight --bundle review-bundle.signed.json --key-policy"));

    await writeFile(join(checkout, "jury/examples/ci/fixtures/key-policy/ci-public.pem"), pair.publicKey);

    for (const command of writeKeyCommands) {
      const result = await runShell(command, checkout, env);

      assert.equal(result.exitCode, 0, `${command}\nstdout:\n${result.stdout}\nstderr:\n${result.stderr}`);
    }

    for (const command of producerCommands) {
      const result = await runShell(command, checkout, env);

      assert.equal(result.exitCode, 0, `${command}\nstdout:\n${result.stdout}\nstderr:\n${result.stderr}`);
    }

    await mkdir(artifactDir, { recursive: true });
    await cp(join(checkout, "review-bundle.signed.json"), join(artifactDir, "review-bundle.signed.json"));

    for (const command of commands) {
      const result = await runShell(command, checkout, env);

      assert.equal(result.exitCode, 0, `${command}\nstdout:\n${result.stdout}\nstderr:\n${result.stderr}`);
    }

    const importedVerdict = JSON.parse(await readFile(join(checkout, "downstream-verdict.json"), "utf8"));
    const gate = JSON.parse(await readFile(join(checkout, "downstream-gate.json"), "utf8"));
    assert.equal(importedVerdict.decision, "accept");
    assert.equal(gate.ok, true);
    assert.equal(gate.decision, "accept");
  } finally {
    await rm(secretDir, { recursive: true, force: true });
    await rm(checkout, { recursive: true, force: true });
  }
});

test("trusted bundle workflow verifies and imports the signed key-policy fixture", { skip: skipNestedCiAdoptionTests }, async () => {
  const checkout = await copyJuryCheckout();

  try {
    const workflow = await readFile(join(checkout, "jury/examples/ci/jury-trusted-bundle-verify.yml"), "utf8");
    const driftCommand = extractWorkflowSingleLineRun(workflow, "Check key-policy fixtures");
    const commands = extractWorkflowRunBlock(workflow, "Verify trusted Jury bundle");
    const env = {
      ...fixedEnv,
      JURY_BUNDLE_PATH: "jury/examples/ci/fixtures/key-policy/review-bundle.signed.json",
      JURY_KEY_POLICY_PATH: "jury/examples/ci/fixtures/key-policy/jury-key-policy.json",
      JURY_STATE_DIR: ".jury-trusted",
      JURY_VERDICT_OUT: "imported-verdict.json",
      JURY_GATE_OUT: "trusted-gate.json",
      JURY_CLAIM_ID: "claim_ci_change",
    };

    assert.ok(workflow.includes("workflow_call"));
    assert.ok(workflow.includes("actions/upload-artifact@v4"));

    const driftResult = await runShell(driftCommand, checkout, env);
    assert.equal(driftResult.exitCode, 0, `${driftCommand}\nstdout:\n${driftResult.stdout}\nstderr:\n${driftResult.stderr}`);

    for (const command of commands) {
      const result = await runShell(command, checkout, env);

      assert.equal(result.exitCode, 0, `${command}\nstdout:\n${result.stdout}\nstderr:\n${result.stderr}`);
    }

    const importedVerdict = JSON.parse(await readFile(join(checkout, "imported-verdict.json"), "utf8"));
    const gate = JSON.parse(await readFile(join(checkout, "trusted-gate.json"), "utf8"));
    assert.equal(importedVerdict.decision, "accept");
    assert.equal(gate.ok, true);
    assert.equal(gate.decision, "accept");
  } finally {
    await rm(checkout, { recursive: true, force: true });
  }
});

test("package manifest workflow runs before publication", { skip: skipNestedCiAdoptionTests }, async () => {
  const checkout = await copyJuryCheckout();

  try {
    const workflow = await readFile(join(checkout, "jury/examples/ci/jury-package-manifest-check.yml"), "utf8");
    const command = extractWorkflowSingleLineRun(workflow, "Check Jury package manifest");
    const env = {
      ...fixedEnv,
      JURY_PACKAGE_DIR: "jury",
    };

    assert.ok(workflow.includes("workflow_call"));
    assert.ok(workflow.includes("package-dir:"));
    assert.ok(workflow.includes("node-version:"));
    assert.ok(workflow.includes("actions/setup-node@v4"));
    assert.equal(command, 'npm --prefix "$JURY_PACKAGE_DIR" run package:manifest:check');

    const result = await runShell(command, checkout, env);
    assert.equal(result.exitCode, 0, `${command}\nstdout:\n${result.stdout}\nstderr:\n${result.stderr}`);
    assert.equal(JSON.parse(result.stdout.slice(result.stdout.indexOf("{"))).ok, true);
  } finally {
    await rm(checkout, { recursive: true, force: true });
  }
});

test("release workflow requires package manifest before npm publication", async () => {
  const workflowPath = join(repoRoot, "jury/examples/ci/jury-npm-publish.yml");
  const workflow = await readFile(workflowPath, "utf8");
  const fixtureCommand = extractWorkflowSingleLineRun(workflow, "Check Jury package release evidence fixtures");
  const driftCommand = extractWorkflowSingleLineRun(workflow, "Check Jury package release archive manifest drift");
  const exportManifestCommand = extractWorkflowSingleLineRun(workflow, "Export Jury package release archive manifest");
  const replayCommand = extractWorkflowSingleLineRun(workflow, "Replay Jury package release evidence audits");
  const replayManifestCommand = extractWorkflowSingleLineRun(workflow, "Replay Jury package release archive manifest");
  const remediationAuditHandoffReplayCommands = extractWorkflowRunBlock(workflow, "Replay Jury package release remediation audit handoff");
  const replaySummaryCommands = extractWorkflowRunBlock(workflow, "Summarize Jury package release replay artifacts");
  const replaySummaryDiagnosticsCommands = extractWorkflowRunBlock(workflow, "Diagnose Jury package release replay summary");
  const replaySummaryDiagnosticsRetentionHandoffCommands = extractWorkflowRunBlock(workflow, "Record Jury package release replay diagnostics retention handoff");
  const replaySummaryDiagnosticsRetentionHandoffReplayCommands = extractWorkflowRunBlock(workflow, "Replay Jury package release replay diagnostics retention handoff");
  const replaySummaryExpiryHandoffReplayCommands = extractWorkflowRunBlock(workflow, "Replay Jury package release replay summary expiry handoff");
  const dryRunCommands = extractWorkflowRunBlock(workflow, "Create Jury package dry-run record");
  const verifyCommands = extractWorkflowRunBlock(workflow, "Verify Jury package dry-run record");
  const publishCommands = extractWorkflowRunBlock(workflow, "Publish Jury package");
  const uploadPaths = extractWorkflowUploadPaths(workflow);

  assert.ok(workflow.includes("workflow_dispatch"));
  assert.ok(workflow.includes("dry_run_reviewer:"));
  assert.ok(workflow.includes("Person who reviewed the verified dry-run package summary"));
  assert.ok(workflow.includes("permissions:"));
  assert.ok(workflow.includes("id-token: write"));
  assert.ok(workflow.includes("package-manifest:"));
  assert.ok(workflow.includes("uses: ./.github/workflows/jury-package-manifest-check.yml"));
  assert.ok(workflow.includes("package-release-fixtures:"));
  assert.ok(workflow.includes("fixtures:package-release:check"));
  assert.ok(workflow.includes("fixtures:package-release:drift"));
  assert.ok(workflow.includes("dry-run-publication:"));
  assert.ok(workflow.includes("- package-manifest"));
  assert.ok(workflow.includes("needs:"));
  assert.ok(workflow.includes("needs: package-release-fixtures"));
  assert.ok(workflow.includes("actions/upload-artifact@v4"));
  assert.ok(workflow.includes("actions/download-artifact@v4"));
  assert.ok(workflow.includes("Upload Jury package release evidence audits"));
  assert.ok(workflow.includes("Check Jury package release archive manifest drift"));
  assert.ok(workflow.includes("Export Jury package release archive manifest"));
  assert.ok(workflow.includes("Upload Jury package release archive manifest"));
  assert.ok(workflow.includes("Download Jury package release archive manifest"));
  assert.ok(workflow.includes("Download Jury package release evidence audits"));
  assert.ok(workflow.includes("Replay Jury package release evidence audits"));
  assert.ok(workflow.includes("Replay Jury package release archive manifest"));
  assert.ok(workflow.includes("Replay Jury package release remediation audit handoff"));
  assert.ok(workflow.includes("Summarize Jury package release replay artifacts"));
  assert.ok(workflow.includes("Diagnose Jury package release replay summary"));
  assert.ok(workflow.includes("Record Jury package release replay diagnostics retention handoff"));
  assert.ok(workflow.includes("Replay Jury package release replay diagnostics retention handoff"));
  assert.ok(workflow.includes("Replay Jury package release replay summary expiry handoff"));
  assert.ok(workflow.includes("Upload Jury package release replay summary"));
  assert.ok(workflow.includes("jury-package-release-evidence"));
  assert.ok(workflow.includes("jury-package-release-archive-manifest"));
  assert.ok(workflow.includes("jury-package-release-replay-summary"));
  assert.ok(workflow.includes("jury-package-release-replay-summary.md"));
  assert.ok(workflow.includes("JURY_PACKAGE_RELEASE_MANIFEST_PATH"));
  assert.ok(workflow.includes("JURY_PACKAGE_RELEASE_REPLAY_SUMMARY_PATH"));
  assert.ok(workflow.includes("JURY_PACKAGE_RELEASE_REPLAY_SUMMARY_DIAGNOSTICS_PATH"));
  assert.ok(workflow.includes("JURY_PACKAGE_RELEASE_REPLAY_SUMMARY_DIAGNOSTICS_RETENTION_HANDOFF_PATH"));
  assert.ok(workflow.includes("jury-package-release-replay-summary-diagnostics.json"));
  assert.ok(workflow.includes("jury-package-release-replay-summary-diagnostics-retention-handoff.json"));
  assert.ok(workflow.includes("jury-package-release-replay-summary-expiry-handoff.json"));
  assert.ok(workflow.includes("retained-package-release-evidence-manifest.json"));
  assert.ok(workflow.includes("package-release-evidence-replay:"));
  assert.ok(workflow.includes("jury-package-dry-run"));
  assert.ok(workflow.includes("retention-days: 90"));
  assert.ok(workflow.includes("rollback-audit.json"));
  assert.ok(workflow.includes("replacement-patch-audit.json"));
  assert.ok(workflow.includes("archive-drift-remediation-audit.json"));
  assert.ok(workflow.includes("archive-drift-remediation-audit-handoff.json"));
  assert.ok(workflow.includes("jury-pack-dry-run.json"));
  assert.ok(workflow.includes("jury-pack-dry-run-record.json"));
  assert.ok(workflow.includes("GITHUB_STEP_SUMMARY"));
  assert.ok(workflow.includes("JURY_DRY_RUN_REVIEWER: ${{ inputs.dry_run_reviewer }}"));
  assert.ok(workflow.includes("reviewedBy"));
  assert.ok(workflow.includes("- package-manifest"));
  assert.ok(workflow.includes("NODE_AUTH_TOKEN: ${{ secrets.NPM_TOKEN }}"));
  assert.ok(workflow.indexOf("package-release-fixtures:") < workflow.indexOf("dry-run-publication:"));
  assert.ok(workflow.indexOf("package-release-fixtures:") < workflow.indexOf("package-release-evidence-replay:"));
  assert.ok(workflow.indexOf("package-release-evidence-replay:") < workflow.indexOf("dry-run-publication:"));
  assert.ok(workflow.indexOf("dry-run-publication:") < workflow.indexOf("publish:"));
  assert.ok(workflow.indexOf("Check Jury package release evidence fixtures") < workflow.indexOf("Create Jury package dry-run record"));
  assert.ok(workflow.indexOf("Check Jury package release evidence fixtures") < workflow.indexOf("Check Jury package release archive manifest drift"));
  assert.ok(workflow.indexOf("Check Jury package release archive manifest drift") < workflow.indexOf("Export Jury package release archive manifest"));
  assert.ok(workflow.indexOf("Export Jury package release archive manifest") < workflow.indexOf("Upload Jury package release archive manifest"));
  assert.ok(workflow.indexOf("Upload Jury package release evidence audits") < workflow.indexOf("Create Jury package dry-run record"));
  assert.ok(workflow.indexOf("Upload Jury package release archive manifest") < workflow.indexOf("Create Jury package dry-run record"));
  assert.ok(workflow.indexOf("Download Jury package release evidence audits") < workflow.indexOf("Replay Jury package release evidence audits"));
  assert.ok(workflow.indexOf("Download Jury package release archive manifest") < workflow.indexOf("Replay Jury package release archive manifest"));
  assert.ok(workflow.indexOf("Replay Jury package release evidence audits") < workflow.indexOf("Create Jury package dry-run record"));
  assert.ok(workflow.indexOf("Replay Jury package release archive manifest") < workflow.indexOf("Create Jury package dry-run record"));
  assert.ok(workflow.indexOf("Replay Jury package release remediation audit handoff") < workflow.indexOf("Create Jury package dry-run record"));
  assert.ok(workflow.indexOf("Replay Jury package release archive manifest") < workflow.indexOf("Summarize Jury package release replay artifacts"));
  assert.ok(workflow.indexOf("Replay Jury package release archive manifest") < workflow.indexOf("Replay Jury package release remediation audit handoff"));
  assert.ok(workflow.indexOf("Replay Jury package release remediation audit handoff") < workflow.indexOf("Summarize Jury package release replay artifacts"));
  assert.ok(workflow.indexOf("Summarize Jury package release replay artifacts") < workflow.indexOf("Create Jury package dry-run record"));
  assert.ok(workflow.indexOf("Summarize Jury package release replay artifacts") < workflow.indexOf("Diagnose Jury package release replay summary"));
  assert.ok(workflow.indexOf("Diagnose Jury package release replay summary") < workflow.indexOf("Record Jury package release replay diagnostics retention handoff"));
  assert.ok(workflow.indexOf("Record Jury package release replay diagnostics retention handoff") < workflow.indexOf("Upload Jury package release replay summary"));
  assert.ok(workflow.indexOf("Record Jury package release replay diagnostics retention handoff") < workflow.indexOf("Replay Jury package release replay diagnostics retention handoff"));
  assert.ok(workflow.indexOf("Replay Jury package release replay diagnostics retention handoff") < workflow.indexOf("Upload Jury package release replay summary"));
  assert.ok(workflow.indexOf("Replay Jury package release replay diagnostics retention handoff") < workflow.indexOf("Replay Jury package release replay summary expiry handoff"));
  assert.ok(workflow.indexOf("Replay Jury package release replay summary expiry handoff") < workflow.indexOf("Upload Jury package release replay summary"));
  assert.ok(workflow.indexOf("Diagnose Jury package release replay summary") < workflow.indexOf("Upload Jury package release replay summary"));
  assert.ok(workflow.indexOf("Record Jury package release replay diagnostics retention handoff") < workflow.indexOf("Create Jury package dry-run record"));
  assert.ok(workflow.indexOf("Replay Jury package release replay diagnostics retention handoff") < workflow.indexOf("Create Jury package dry-run record"));
  assert.ok(workflow.indexOf("Replay Jury package release replay summary expiry handoff") < workflow.indexOf("Create Jury package dry-run record"));
  assert.ok(workflow.indexOf("Diagnose Jury package release replay summary") < workflow.indexOf("Create Jury package dry-run record"));
  assert.ok(workflow.indexOf("Summarize Jury package release replay artifacts") < workflow.indexOf("Upload Jury package release replay summary"));
  assert.ok(workflow.indexOf("Upload Jury package release replay summary") < workflow.indexOf("Create Jury package dry-run record"));
  assert.ok(workflow.indexOf("Download Jury package dry-run record") < workflow.indexOf("Verify Jury package dry-run record"));
  assert.ok(workflow.indexOf("Verify Jury package dry-run record") < workflow.indexOf("NODE_AUTH_TOKEN"));
  assert.ok(workflow.indexOf("needs: package-release-fixtures") < workflow.indexOf("npm publish --provenance --access public"));
  assert.ok(workflow.indexOf("- package-release-evidence-replay") < workflow.indexOf("npm publish --provenance --access public"));
  assert.ok(workflow.indexOf("- package-manifest") < workflow.indexOf("npm publish --provenance --access public"));
  assert.equal(fixtureCommand, 'npm --prefix "$JURY_PACKAGE_DIR" run fixtures:package-release:check');
  assert.equal(driftCommand, 'npm --prefix "$JURY_PACKAGE_DIR" run fixtures:package-release:drift');
  assert.equal(exportManifestCommand, 'npm --prefix "$JURY_PACKAGE_DIR" run fixtures:package-release:check -- --fixture-dir "$JURY_PACKAGE_RELEASE_EVIDENCE_DIR" --manifest-out ../retained-package-release-evidence-manifest.json');
  assert.equal(replayCommand, 'npm --prefix jury run fixtures:package-release:check -- --fixture-dir "$JURY_PACKAGE_RELEASE_EVIDENCE_DIR"');
  assert.equal(replayManifestCommand, 'npm --prefix jury run fixtures:package-release:check -- --fixture-dir "$JURY_PACKAGE_RELEASE_EVIDENCE_DIR" --verify-manifest "$JURY_PACKAGE_RELEASE_MANIFEST_PATH"');
  assert.deepEqual(remediationAuditHandoffReplayCommands, [
    '(cd jury && node -e \'const fs=require("node:fs"); const evidenceDir=process.env.JURY_PACKAGE_RELEASE_EVIDENCE_DIR; const manifestPath=process.env.JURY_PACKAGE_RELEASE_MANIFEST_PATH; const manifest=JSON.parse(fs.readFileSync(manifestPath,"utf8")); const audit=JSON.parse(fs.readFileSync(`${evidenceDir}/archive-drift-remediation-audit.json`,"utf8")); const handoff=JSON.parse(fs.readFileSync(`${evidenceDir}/archive-drift-remediation-audit-handoff.json`,"utf8")); const requiredWith=["archive-drift-remediation-audit.json","rollback-audit.json","replacement-patch-audit.json","retained-package-release-evidence-manifest.json","jury-package-release-replay-summary-diagnostics-retention-handoff.json"]; const drift=(audit.drift?.evidence??[]).map((item)=>item.path); const restored=(audit.remediation?.restoredEvidence??[]).map((item)=>item.path); const commands=audit.verification?.commands??[]; const errors=[]; if (handoff.schema_version!=="jury.package_release_remediation_audit_handoff.v1") errors.push("schema_version must equal jury.package_release_remediation_audit_handoff.v1"); if (handoff.sourceAudit!=="archive-drift-remediation-audit.json") errors.push("sourceAudit must be archive-drift-remediation-audit.json"); if (handoff.sourceManifest!=="retained-package-release-evidence-manifest.json") errors.push("sourceManifest must be retained-package-release-evidence-manifest.json"); for (const item of requiredWith) if (!(handoff.retainedWith??[]).includes(item)) errors.push(`retainedWith missing ${item}`); if (handoff.failedPackageVersion!==manifest.failed?.packageVersion) errors.push("failedPackageVersion must match retained manifest failed packageVersion"); if (handoff.failedTarballName!==manifest.failed?.tarballName) errors.push("failedTarballName must match retained manifest failed tarballName"); if (handoff.replacementPackageVersion!==manifest.replacement?.packageVersion) errors.push("replacementPackageVersion must match retained manifest replacement packageVersion"); if (JSON.stringify(handoff.driftEvidence)!==JSON.stringify(drift)) errors.push("driftEvidence must match remediation audit drift evidence"); if (JSON.stringify(handoff.restoredEvidence)!==JSON.stringify(restored)) errors.push("restoredEvidence must match remediation audit restored evidence"); if (JSON.stringify(handoff.verificationCommands)!==JSON.stringify(commands)) errors.push("verificationCommands must match remediation audit verification commands"); if (handoff.manifestRegenerated!==audit.remediation?.regeneratedManifest) errors.push("manifestRegenerated must match remediation audit regenerated manifest"); if (handoff.diffReviewed!==audit.remediation?.diffReviewed) errors.push("diffReviewed must match remediation audit diff review"); if (handoff.runId!==manifest.provenance?.runId) errors.push("runId must match retained manifest provenance"); if (handoff.sourceRevision!==manifest.provenance?.sourceRevision) errors.push("sourceRevision must match retained manifest provenance"); if (handoff.reviewedBy!==audit.approval?.approvedBy) errors.push("reviewedBy must match archive drift remediation approver"); if (handoff.approvedAt!==audit.approval?.approvedAt) errors.push("approvedAt must match archive drift remediation approval time"); if (errors.length) throw new Error(`remediation audit handoff replay failed: ${errors.join("; ")}`); console.log(JSON.stringify({ok:true, failedPackageVersion:handoff.failedPackageVersion, replacementPackageVersion:handoff.replacementPackageVersion, runId:handoff.runId, reviewedBy:handoff.reviewedBy}, null, 2));\')',
  ]);
  assert.ok(uploadPaths.includes("jury/examples/ci/fixtures/package-release/rollback-audit.json"));
  assert.ok(uploadPaths.includes("jury/examples/ci/fixtures/package-release/replacement-patch-audit.json"));
  assert.ok(uploadPaths.includes("jury/examples/ci/fixtures/package-release/archive-drift-remediation-audit.json"));
  assert.ok(uploadPaths.includes("jury/examples/ci/fixtures/package-release/archive-drift-remediation-audit-handoff.json"));
  assert.ok(uploadPaths.includes("jury/examples/ci/fixtures/package-release/failed-npm-view.json"));
  assert.ok(uploadPaths.includes("jury/examples/ci/fixtures/package-release/replacement-npm-view.json"));
  assert.ok(uploadPaths.includes("jury/examples/ci/fixtures/package-release/jury-package-release-replay-summary.md"));
  assert.ok(uploadPaths.includes("jury/examples/ci/fixtures/package-release/jury-package-release-replay-summary-diagnostics.json"));
  assert.ok(uploadPaths.includes("jury/examples/ci/fixtures/package-release/jury-package-release-replay-summary-diagnostics-retention-handoff.json"));
  assert.ok(uploadPaths.includes("jury/examples/ci/fixtures/package-release/jury-package-release-replay-summary-expiry-handoff.json"));
  assert.ok(uploadPaths.includes("retained-package-release-evidence-manifest.json"));
  assert.ok(uploadPaths.includes("jury-package-release-replay-summary.md"));
  assert.ok(uploadPaths.includes("jury-package-release-replay-summary-diagnostics.json"));
  assert.ok(uploadPaths.includes("jury-package-release-replay-summary-diagnostics-retention-handoff.json"));
  assert.deepEqual(dryRunCommands, [
    '(cd "$JURY_PACKAGE_DIR" && npm pack --dry-run --json) > jury-pack-dry-run.json',
    'node -e \'const fs=require("node:fs"); const [pack]=JSON.parse(fs.readFileSync("jury-pack-dry-run.json","utf8")); fs.writeFileSync("jury-pack-dry-run-record.json", JSON.stringify({ packageVersion: pack.version, tarballName: pack.filename }, null, 2) + "\\n");\'',
  ]);
  assert.deepEqual(verifyCommands, [
    'node -e \'const fs=require("node:fs"); const pkg=JSON.parse(fs.readFileSync("jury/package.json","utf8")); const record=JSON.parse(fs.readFileSync("jury-pack-dry-run-record.json","utf8")); const reviewer=(process.env.JURY_DRY_RUN_REVIEWER||"").trim(); const expectedTarball=`sanogueralorenzo-jury-${pkg.version}.tgz`; if (!reviewer) throw new Error("JURY_DRY_RUN_REVIEWER must identify who reviewed the dry-run package summary"); if (record.packageVersion !== pkg.version) throw new Error(`packageVersion ${record.packageVersion} did not match ${pkg.version}`); if (record.tarballName !== expectedTarball) throw new Error(`tarballName ${record.tarballName} did not match ${expectedTarball}`); if (process.env.GITHUB_STEP_SUMMARY) fs.appendFileSync(process.env.GITHUB_STEP_SUMMARY, `### Jury package dry-run\\n\\n- packageVersion: ${record.packageVersion}\\n- tarballName: ${record.tarballName}\\n- reviewedBy: ${reviewer}\\n`);\'',
  ]);
  assert.deepEqual(replaySummaryCommands, [
    '(cd jury && node -e \'const fs=require("node:fs"); const evidenceDir=process.env.JURY_PACKAGE_RELEASE_EVIDENCE_DIR; const manifestPath=process.env.JURY_PACKAGE_RELEASE_MANIFEST_PATH; const summaryPath=process.env.JURY_PACKAGE_RELEASE_REPLAY_SUMMARY_PATH; const manifest=JSON.parse(fs.readFileSync(manifestPath,"utf8")); const remediation=JSON.parse(fs.readFileSync(`${evidenceDir}/archive-drift-remediation-audit.json`,"utf8")); const failedEvidence=remediation.failed.archiveEvidence.join(", "); const replacementEvidence=remediation.replacement.archiveEvidence.join(", "); const summary=`### Jury package release replay\\n\\n- failedPackageVersion: ${manifest.failed.packageVersion}\\n- failedTarballName: ${manifest.failed.tarballName}\\n- replacementPackageVersion: ${manifest.replacement.packageVersion}\\n- failedArchiveEvidence: ${failedEvidence}\\n- replacementArchiveEvidence: ${replacementEvidence}\\n- remediationApprovedBy: ${remediation.approval.approvedBy}\\n`; if (summaryPath) fs.writeFileSync(summaryPath, summary); if (process.env.GITHUB_STEP_SUMMARY) fs.appendFileSync(process.env.GITHUB_STEP_SUMMARY, summary); else console.log(summary);\')',
  ]);
  assert.deepEqual(replaySummaryDiagnosticsCommands, [
    '(cd jury && node -e \'const fs=require("node:fs"); const evidenceDir=process.env.JURY_PACKAGE_RELEASE_EVIDENCE_DIR; const manifestPath=process.env.JURY_PACKAGE_RELEASE_MANIFEST_PATH; const summaryPath=process.env.JURY_PACKAGE_RELEASE_REPLAY_SUMMARY_PATH; const diagnosticsPath=process.env.JURY_PACKAGE_RELEASE_REPLAY_SUMMARY_DIAGNOSTICS_PATH; const manifest=JSON.parse(fs.readFileSync(manifestPath,"utf8")); const remediation=JSON.parse(fs.readFileSync(`${evidenceDir}/archive-drift-remediation-audit.json`,"utf8")); const summary=fs.readFileSync(summaryPath,"utf8"); const checkedLines=["### Jury package release replay",`- failedPackageVersion: ${manifest.failed.packageVersion}`,`- failedTarballName: ${manifest.failed.tarballName}`,`- replacementPackageVersion: ${manifest.replacement.packageVersion}`,`- failedArchiveEvidence: ${remediation.failed.archiveEvidence.join(", ")}`,`- replacementArchiveEvidence: ${remediation.replacement.archiveEvidence.join(", ")}`,`- remediationApprovedBy: ${remediation.approval.approvedBy}`]; const missing=checkedLines.filter((line)=>!summary.includes(line)); if (missing.length) throw new Error(`replay summary diagnostics missing lines: ${missing.join(", ")}`); const diagnostics={schema_version:"jury.package_release_replay_summary_diagnostics.v1",sourceJob:"package-release-evidence-replay",summaryArtifact:"jury-package-release-replay-summary",summaryFile:"jury-package-release-replay-summary.md",failedPackageVersion:manifest.failed.packageVersion,failedTarballName:manifest.failed.tarballName,replacementPackageVersion:manifest.replacement.packageVersion,failedArchiveEvidence:remediation.failed.archiveEvidence,replacementArchiveEvidence:remediation.replacement.archiveEvidence,remediationApprovedBy:remediation.approval.approvedBy,checkedLines}; fs.writeFileSync(diagnosticsPath, `${JSON.stringify(diagnostics,null,2)}\\n`); console.log(JSON.stringify({ok:true, diagnosticsPath}, null, 2));\')',
  ]);
  assert.deepEqual(replaySummaryDiagnosticsRetentionHandoffCommands, [
    '(cd jury && node -e \'const fs=require("node:fs"); const evidenceDir=process.env.JURY_PACKAGE_RELEASE_EVIDENCE_DIR; const manifestPath=process.env.JURY_PACKAGE_RELEASE_MANIFEST_PATH; const diagnosticsPath=process.env.JURY_PACKAGE_RELEASE_REPLAY_SUMMARY_DIAGNOSTICS_PATH; const handoffPath=process.env.JURY_PACKAGE_RELEASE_REPLAY_SUMMARY_DIAGNOSTICS_RETENTION_HANDOFF_PATH; const manifest=JSON.parse(fs.readFileSync(manifestPath,"utf8")); const diagnostics=JSON.parse(fs.readFileSync(diagnosticsPath,"utf8")); const remediation=JSON.parse(fs.readFileSync(`${evidenceDir}/archive-drift-remediation-audit.json`,"utf8")); const retained=JSON.parse(fs.readFileSync(`${evidenceDir}/jury-package-release-replay-summary-diagnostics-retention-handoff.json`,"utf8")); const artifact=(manifest.provenance?.artifacts??[]).find((item)=>item.name==="jury-package-release-replay-summary"); const reviewedBy=(remediation.approval?.approvedBy||"").trim(); const errors=[]; if (!reviewedBy) errors.push("archive-drift-remediation-audit approval.approvedBy must identify who reviewed diagnostics retention"); if (diagnostics.schema_version!=="jury.package_release_replay_summary_diagnostics.v1") errors.push("diagnostics schema_version must equal jury.package_release_replay_summary_diagnostics.v1"); if (artifact?.sourceJob!=="package-release-evidence-replay") errors.push("jury-package-release-replay-summary sourceJob must be package-release-evidence-replay"); if (artifact?.retentionDays!==90) errors.push("jury-package-release-replay-summary retentionDays must be 90"); if (!artifact?.files?.includes("jury-package-release-replay-summary-diagnostics.json")) errors.push("jury-package-release-replay-summary files must include diagnostics JSON"); const handoff={schema_version:"jury.package_release_replay_summary_diagnostics_retention_handoff.v1",reason:"jury-package-release-replay-summary-diagnostics retained with failed and replacement release archives",sourceArtifact:"jury-package-release-replay-summary",sourceJob:"package-release-evidence-replay",retentionDays:90,diagnosticsSchemaVersion:diagnostics.schema_version,retainedDiagnostics:"jury-package-release-replay-summary-diagnostics.json",summaryFile:diagnostics.summaryFile,retainedWith:["retained-package-release-evidence-manifest.json","jury-package-release-replay-summary.md","archive-drift-remediation-audit.json"],failedPackageVersion:diagnostics.failedPackageVersion,failedTarballName:diagnostics.failedTarballName,replacementPackageVersion:diagnostics.replacementPackageVersion,runId:manifest.provenance.runId,sourceRevision:manifest.provenance.sourceRevision,reviewedBy}; const stable=(value)=>JSON.stringify(value,Object.keys(value).sort()); if (stable(handoff)!==stable(retained)) errors.push("generated diagnostics retention handoff must match retained archive evidence"); if (errors.length) throw new Error(`replay summary diagnostics retention handoff failed: ${errors.join("; ")}`); fs.writeFileSync(handoffPath, `${JSON.stringify(handoff,null,2)}\\n`); console.log(JSON.stringify({ok:true,handoffPath,reviewedBy}, null, 2));\')',
  ]);
  assert.deepEqual(replaySummaryDiagnosticsRetentionHandoffReplayCommands, [
    '(cd jury && node -e \'const fs=require("node:fs"); const evidenceDir=process.env.JURY_PACKAGE_RELEASE_EVIDENCE_DIR; const manifestPath=process.env.JURY_PACKAGE_RELEASE_MANIFEST_PATH; const diagnosticsPath=process.env.JURY_PACKAGE_RELEASE_REPLAY_SUMMARY_DIAGNOSTICS_PATH; const handoffPath=process.env.JURY_PACKAGE_RELEASE_REPLAY_SUMMARY_DIAGNOSTICS_RETENTION_HANDOFF_PATH; const manifest=JSON.parse(fs.readFileSync(manifestPath,"utf8")); const diagnostics=JSON.parse(fs.readFileSync(diagnosticsPath,"utf8")); const handoff=JSON.parse(fs.readFileSync(handoffPath,"utf8")); const retained=JSON.parse(fs.readFileSync(`${evidenceDir}/jury-package-release-replay-summary-diagnostics-retention-handoff.json`,"utf8")); const remediation=JSON.parse(fs.readFileSync(`${evidenceDir}/archive-drift-remediation-audit.json`,"utf8")); const artifact=(manifest.provenance?.artifacts??[]).find((item)=>item.name==="jury-package-release-replay-summary"); const expected={schema_version:"jury.package_release_replay_summary_diagnostics_retention_handoff.v1",reason:"jury-package-release-replay-summary-diagnostics retained with failed and replacement release archives",sourceArtifact:"jury-package-release-replay-summary",sourceJob:"package-release-evidence-replay",retentionDays:90,diagnosticsSchemaVersion:diagnostics.schema_version,retainedDiagnostics:"jury-package-release-replay-summary-diagnostics.json",summaryFile:diagnostics.summaryFile,failedPackageVersion:diagnostics.failedPackageVersion,failedTarballName:diagnostics.failedTarballName,replacementPackageVersion:diagnostics.replacementPackageVersion,runId:manifest.provenance?.runId,sourceRevision:manifest.provenance?.sourceRevision,reviewedBy:remediation.approval?.approvedBy}; const errors=[]; for (const [field,value] of Object.entries(expected)) if (handoff[field]!==value) errors.push(`${field} must match retained diagnostics evidence`); for (const item of ["retained-package-release-evidence-manifest.json","jury-package-release-replay-summary.md","archive-drift-remediation-audit.json"]) if (!(handoff.retainedWith??[]).includes(item)) errors.push(`retainedWith missing ${item}`); if (artifact?.sourceJob!=="package-release-evidence-replay") errors.push("jury-package-release-replay-summary sourceJob must be package-release-evidence-replay"); if (artifact?.retentionDays!==90) errors.push("jury-package-release-replay-summary retentionDays must be 90"); if (!artifact?.files?.includes("jury-package-release-replay-summary-diagnostics.json")) errors.push("jury-package-release-replay-summary files must include diagnostics JSON"); if (!artifact?.files?.includes("jury-package-release-replay-summary-diagnostics-retention-handoff.json")) errors.push("jury-package-release-replay-summary files must include diagnostics retention handoff"); const stable=(value)=>JSON.stringify(value,Object.keys(value).sort()); if (stable(handoff)!==stable(retained)) errors.push("generated diagnostics retention handoff must match retained archive evidence"); if (errors.length) throw new Error(`replay summary diagnostics retention handoff replay failed: ${errors.join("; ")}`); console.log(JSON.stringify({ok:true,handoffPath,reviewedBy:handoff.reviewedBy}, null, 2));\')',
  ]);
  assert.equal(replaySummaryExpiryHandoffReplayCommands.length, 1);
  assert.ok(replaySummaryExpiryHandoffReplayCommands[0].includes("jury-package-release-replay-summary-expiry-handoff.json"));
  assert.ok(replaySummaryExpiryHandoffReplayCommands[0].includes("replay summary expiry handoff replay failed"));
  assert.ok(replaySummaryExpiryHandoffReplayCommands[0].includes("jury-package-release-evidence files must include replay summary expiry handoff"));
  assert.deepEqual(publishCommands, [
    'test -n "$NODE_AUTH_TOKEN"',
    'cd "$JURY_PACKAGE_DIR"',
    "npm publish --provenance --access public",
  ]);

  const checkout = await copyJuryCheckout();
  try {
    const fixtureCheck = await runShell(fixtureCommand, checkout, { ...fixedEnv, JURY_PACKAGE_DIR: "jury" });
    assert.equal(fixtureCheck.exitCode, 0, `${fixtureCommand}\nstdout:\n${fixtureCheck.stdout}\nstderr:\n${fixtureCheck.stderr}`);
    assert.equal(JSON.parse(fixtureCheck.stdout.slice(fixtureCheck.stdout.indexOf("{"))).ok, true);
    const driftCheck = await runShell(driftCommand, checkout, { ...fixedEnv, JURY_PACKAGE_DIR: "jury" });
    assert.equal(driftCheck.exitCode, 0, `${driftCommand}\nstdout:\n${driftCheck.stdout}\nstderr:\n${driftCheck.stderr}`);
    assert.ok(JSON.parse(driftCheck.stdout.slice(driftCheck.stdout.indexOf("{"))).archiveDriftManifest.endsWith("/jury/examples/ci/fixtures/package-release/retained-package-release-evidence-manifest.json"));
    const exportManifest = await runShell(exportManifestCommand, checkout, {
      ...fixedEnv,
      JURY_PACKAGE_DIR: "jury",
      JURY_PACKAGE_RELEASE_EVIDENCE_DIR: "examples/ci/fixtures/package-release",
    });
    assert.equal(exportManifest.exitCode, 0, `${exportManifestCommand}\nstdout:\n${exportManifest.stdout}\nstderr:\n${exportManifest.stderr}`);
    assert.equal(JSON.parse(exportManifest.stdout.slice(exportManifest.stdout.indexOf("{"))).manifestOut, "../retained-package-release-evidence-manifest.json");

    const replayDir = join(checkout, "package-release-evidence");
    const replayManifestDir = join(checkout, "package-release-manifest");
    await mkdir(replayDir, { recursive: true });
    for (const uploadPath of uploadPaths.filter((path) => path.startsWith("jury/examples/ci/fixtures/package-release/"))) {
      await cp(join(checkout, uploadPath), join(replayDir, uploadPath.replace("jury/examples/ci/fixtures/package-release/", "")));
    }
    await mkdir(replayManifestDir);
    await cp(join(checkout, "retained-package-release-evidence-manifest.json"), join(replayManifestDir, "retained-package-release-evidence-manifest.json"));
    const replayCheck = await runShell(replayCommand, checkout, {
      ...fixedEnv,
      JURY_PACKAGE_RELEASE_EVIDENCE_DIR: "../package-release-evidence",
    });
    assert.equal(replayCheck.exitCode, 0, `${replayCommand}\nstdout:\n${replayCheck.stdout}\nstderr:\n${replayCheck.stderr}`);
    assert.equal(JSON.parse(replayCheck.stdout.slice(replayCheck.stdout.indexOf("{"))).ok, true);
    const replayManifestCheck = await runShell(replayManifestCommand, checkout, {
      ...fixedEnv,
      JURY_PACKAGE_RELEASE_EVIDENCE_DIR: "../package-release-evidence",
      JURY_PACKAGE_RELEASE_MANIFEST_PATH: "../package-release-manifest/retained-package-release-evidence-manifest.json",
    });
    assert.equal(replayManifestCheck.exitCode, 0, `${replayManifestCommand}\nstdout:\n${replayManifestCheck.stdout}\nstderr:\n${replayManifestCheck.stderr}`);
    assert.equal(JSON.parse(replayManifestCheck.stdout.slice(replayManifestCheck.stdout.indexOf("{"))).verifiedManifest, "../package-release-manifest/retained-package-release-evidence-manifest.json");

    const remediationAuditHandoffReplay = await runShell(remediationAuditHandoffReplayCommands.join("\n"), checkout, {
      ...fixedEnv,
      JURY_PACKAGE_RELEASE_EVIDENCE_DIR: "../package-release-evidence",
      JURY_PACKAGE_RELEASE_MANIFEST_PATH: "../package-release-manifest/retained-package-release-evidence-manifest.json",
    });
    assert.equal(remediationAuditHandoffReplay.exitCode, 0, `${remediationAuditHandoffReplayCommands.join("\n")}\nstdout:\n${remediationAuditHandoffReplay.stdout}\nstderr:\n${remediationAuditHandoffReplay.stderr}`);
    assert.equal(JSON.parse(remediationAuditHandoffReplay.stdout).reviewedBy, "release-maintainer@example.com");

    const retainedRemediationAuditHandoffPath = join(replayDir, "archive-drift-remediation-audit-handoff.json");
    const retainedRemediationAuditHandoff = JSON.parse(await readFile(retainedRemediationAuditHandoffPath, "utf8"));
    retainedRemediationAuditHandoff.runId = "different-release-run";
    await writeFile(retainedRemediationAuditHandoffPath, `${JSON.stringify(retainedRemediationAuditHandoff, null, 2)}\n`);
    const invalidRemediationAuditHandoffReplay = await runShell(remediationAuditHandoffReplayCommands.join("\n"), checkout, {
      ...fixedEnv,
      JURY_PACKAGE_RELEASE_EVIDENCE_DIR: "../package-release-evidence",
      JURY_PACKAGE_RELEASE_MANIFEST_PATH: "../package-release-manifest/retained-package-release-evidence-manifest.json",
    });
    assert.equal(invalidRemediationAuditHandoffReplay.exitCode, 1);
    assert.match(invalidRemediationAuditHandoffReplay.stderr, /remediation audit handoff replay failed: runId must match retained manifest provenance/);
    retainedRemediationAuditHandoff.runId = "example-release-run-1001";
    await writeFile(retainedRemediationAuditHandoffPath, `${JSON.stringify(retainedRemediationAuditHandoff, null, 2)}\n`);

    const replaySummaryPath = join(checkout, "package-release-replay-summary.md");
    const replaySummary = await runShell(replaySummaryCommands.join("\n"), checkout, {
      ...fixedEnv,
      GITHUB_STEP_SUMMARY: replaySummaryPath,
      JURY_PACKAGE_RELEASE_EVIDENCE_DIR: "../package-release-evidence",
      JURY_PACKAGE_RELEASE_MANIFEST_PATH: "../package-release-manifest/retained-package-release-evidence-manifest.json",
      JURY_PACKAGE_RELEASE_REPLAY_SUMMARY_PATH: "../jury-package-release-replay-summary.md",
    });
    assert.equal(replaySummary.exitCode, 0, `${replaySummaryCommands.join("\n")}\nstdout:\n${replaySummary.stdout}\nstderr:\n${replaySummary.stderr}`);
    const replaySummaryText = await readFile(replaySummaryPath, "utf8");
    assert.ok(replaySummaryText.includes("### Jury package release replay"));
    assert.ok(replaySummaryText.includes("- failedPackageVersion: 0.1.0"));
    assert.ok(replaySummaryText.includes("- failedTarballName: sanogueralorenzo-jury-0.1.0.tgz"));
    assert.ok(replaySummaryText.includes("- replacementPackageVersion: 0.1.1"));
    assert.ok(replaySummaryText.includes("- failedArchiveEvidence: downstream-failure-gate.json, failed-npm-view.json, rollback-audit.json"));
    assert.ok(replaySummaryText.includes("- replacementArchiveEvidence: replacement-downstream-gate.json, replacement-npm-view.json, replacement-patch-audit.json"));
    assert.ok(replaySummaryText.includes("- remediationApprovedBy: release-maintainer@example.com"));
    assert.equal(await readFile(join(checkout, "jury-package-release-replay-summary.md"), "utf8"), replaySummaryText);

    const replaySummaryDiagnostics = await runShell(replaySummaryDiagnosticsCommands.join("\n"), checkout, {
      ...fixedEnv,
      JURY_PACKAGE_RELEASE_EVIDENCE_DIR: "../package-release-evidence",
      JURY_PACKAGE_RELEASE_MANIFEST_PATH: "../package-release-manifest/retained-package-release-evidence-manifest.json",
      JURY_PACKAGE_RELEASE_REPLAY_SUMMARY_PATH: "../jury-package-release-replay-summary.md",
      JURY_PACKAGE_RELEASE_REPLAY_SUMMARY_DIAGNOSTICS_PATH: "../jury-package-release-replay-summary-diagnostics.json",
    });
    assert.equal(replaySummaryDiagnostics.exitCode, 0, `${replaySummaryDiagnosticsCommands.join("\n")}\nstdout:\n${replaySummaryDiagnostics.stdout}\nstderr:\n${replaySummaryDiagnostics.stderr}`);
    const replaySummaryDiagnosticsPayload = JSON.parse(await readFile(join(checkout, "jury-package-release-replay-summary-diagnostics.json"), "utf8"));
    assert.equal(replaySummaryDiagnosticsPayload.schema_version, "jury.package_release_replay_summary_diagnostics.v1");
    assert.equal(replaySummaryDiagnosticsPayload.sourceJob, "package-release-evidence-replay");
    assert.equal(replaySummaryDiagnosticsPayload.failedPackageVersion, "0.1.0");
    assert.equal(replaySummaryDiagnosticsPayload.failedTarballName, "sanogueralorenzo-jury-0.1.0.tgz");
    assert.equal(replaySummaryDiagnosticsPayload.replacementPackageVersion, "0.1.1");
    assert.deepEqual(replaySummaryDiagnosticsPayload.failedArchiveEvidence, ["downstream-failure-gate.json", "failed-npm-view.json", "rollback-audit.json"]);
    assert.deepEqual(replaySummaryDiagnosticsPayload.replacementArchiveEvidence, ["replacement-downstream-gate.json", "replacement-npm-view.json", "replacement-patch-audit.json"]);
    assert.ok(replaySummaryDiagnosticsPayload.checkedLines.includes("- remediationApprovedBy: release-maintainer@example.com"));

    const replaySummaryDiagnosticsRetentionHandoff = await runShell(replaySummaryDiagnosticsRetentionHandoffCommands.join("\n"), checkout, {
      ...fixedEnv,
      JURY_PACKAGE_RELEASE_EVIDENCE_DIR: "../package-release-evidence",
      JURY_PACKAGE_RELEASE_MANIFEST_PATH: "../package-release-manifest/retained-package-release-evidence-manifest.json",
      JURY_PACKAGE_RELEASE_REPLAY_SUMMARY_DIAGNOSTICS_PATH: "../jury-package-release-replay-summary-diagnostics.json",
      JURY_PACKAGE_RELEASE_REPLAY_SUMMARY_DIAGNOSTICS_RETENTION_HANDOFF_PATH: "../jury-package-release-replay-summary-diagnostics-retention-handoff.json",
    });
    assert.equal(replaySummaryDiagnosticsRetentionHandoff.exitCode, 0, `${replaySummaryDiagnosticsRetentionHandoffCommands.join("\n")}\nstdout:\n${replaySummaryDiagnosticsRetentionHandoff.stdout}\nstderr:\n${replaySummaryDiagnosticsRetentionHandoff.stderr}`);
    const replaySummaryDiagnosticsRetentionHandoffPayload = JSON.parse(await readFile(join(checkout, "jury-package-release-replay-summary-diagnostics-retention-handoff.json"), "utf8"));
    assert.equal(replaySummaryDiagnosticsRetentionHandoffPayload.schema_version, "jury.package_release_replay_summary_diagnostics_retention_handoff.v1");
    assert.equal(replaySummaryDiagnosticsRetentionHandoffPayload.sourceArtifact, "jury-package-release-replay-summary");
    assert.equal(replaySummaryDiagnosticsRetentionHandoffPayload.sourceJob, "package-release-evidence-replay");
    assert.equal(replaySummaryDiagnosticsRetentionHandoffPayload.retentionDays, 90);
    assert.equal(replaySummaryDiagnosticsRetentionHandoffPayload.diagnosticsSchemaVersion, "jury.package_release_replay_summary_diagnostics.v1");
    assert.equal(replaySummaryDiagnosticsRetentionHandoffPayload.retainedDiagnostics, "jury-package-release-replay-summary-diagnostics.json");
    assert.equal(replaySummaryDiagnosticsRetentionHandoffPayload.failedPackageVersion, "0.1.0");
    assert.equal(replaySummaryDiagnosticsRetentionHandoffPayload.failedTarballName, "sanogueralorenzo-jury-0.1.0.tgz");
    assert.equal(replaySummaryDiagnosticsRetentionHandoffPayload.replacementPackageVersion, "0.1.1");
    assert.equal(replaySummaryDiagnosticsRetentionHandoffPayload.runId, "example-release-run-1001");
    assert.equal(replaySummaryDiagnosticsRetentionHandoffPayload.sourceRevision, "example-release-revision");
    assert.equal(replaySummaryDiagnosticsRetentionHandoffPayload.reviewedBy, "release-maintainer@example.com");

    const replaySummaryDiagnosticsRetentionHandoffReplay = await runShell(replaySummaryDiagnosticsRetentionHandoffReplayCommands.join("\n"), checkout, {
      ...fixedEnv,
      JURY_PACKAGE_RELEASE_EVIDENCE_DIR: "../package-release-evidence",
      JURY_PACKAGE_RELEASE_MANIFEST_PATH: "../package-release-manifest/retained-package-release-evidence-manifest.json",
      JURY_PACKAGE_RELEASE_REPLAY_SUMMARY_DIAGNOSTICS_PATH: "../jury-package-release-replay-summary-diagnostics.json",
      JURY_PACKAGE_RELEASE_REPLAY_SUMMARY_DIAGNOSTICS_RETENTION_HANDOFF_PATH: "../jury-package-release-replay-summary-diagnostics-retention-handoff.json",
    });
    assert.equal(replaySummaryDiagnosticsRetentionHandoffReplay.exitCode, 0, `${replaySummaryDiagnosticsRetentionHandoffReplayCommands.join("\n")}\nstdout:\n${replaySummaryDiagnosticsRetentionHandoffReplay.stdout}\nstderr:\n${replaySummaryDiagnosticsRetentionHandoffReplay.stderr}`);
    assert.equal(JSON.parse(replaySummaryDiagnosticsRetentionHandoffReplay.stdout).reviewedBy, "release-maintainer@example.com");

    const replaySummaryExpiryHandoffReplay = await runShell(replaySummaryExpiryHandoffReplayCommands.join("\n"), checkout, {
      ...fixedEnv,
      JURY_PACKAGE_RELEASE_EVIDENCE_DIR: "../package-release-evidence",
      JURY_PACKAGE_RELEASE_MANIFEST_PATH: "../package-release-manifest/retained-package-release-evidence-manifest.json",
      JURY_PACKAGE_RELEASE_REPLAY_SUMMARY_PATH: "../jury-package-release-replay-summary.md",
    });
    assert.equal(replaySummaryExpiryHandoffReplay.exitCode, 0, `${replaySummaryExpiryHandoffReplayCommands.join("\n")}\nstdout:\n${replaySummaryExpiryHandoffReplay.stdout}\nstderr:\n${replaySummaryExpiryHandoffReplay.stderr}`);
    assert.equal(JSON.parse(replaySummaryExpiryHandoffReplay.stdout).reviewedBy, "release-maintainer@example.com");

    const retainedReplaySummaryExpiryHandoffPath = join(replayDir, "jury-package-release-replay-summary-expiry-handoff.json");
    const retainedReplaySummaryExpiryHandoff = JSON.parse(await readFile(retainedReplaySummaryExpiryHandoffPath, "utf8"));
    retainedReplaySummaryExpiryHandoff.replacementPackageVersion = "0.1.2";
    await writeFile(retainedReplaySummaryExpiryHandoffPath, `${JSON.stringify(retainedReplaySummaryExpiryHandoff, null, 2)}\n`);
    const invalidReplaySummaryExpiryHandoffReplay = await runShell(replaySummaryExpiryHandoffReplayCommands.join("\n"), checkout, {
      ...fixedEnv,
      JURY_PACKAGE_RELEASE_EVIDENCE_DIR: "../package-release-evidence",
      JURY_PACKAGE_RELEASE_MANIFEST_PATH: "../package-release-manifest/retained-package-release-evidence-manifest.json",
      JURY_PACKAGE_RELEASE_REPLAY_SUMMARY_PATH: "../jury-package-release-replay-summary.md",
    });
    assert.equal(invalidReplaySummaryExpiryHandoffReplay.exitCode, 1);
    assert.match(invalidReplaySummaryExpiryHandoffReplay.stderr, /replay summary expiry handoff replay failed: replacementPackageVersion must match retained manifest replacement packageVersion/);
    await cp(
      join(checkout, "jury/examples/ci/fixtures/package-release/jury-package-release-replay-summary-expiry-handoff.json"),
      retainedReplaySummaryExpiryHandoffPath,
    );

    replaySummaryDiagnosticsRetentionHandoffPayload.runId = "different-release-run";
    await writeFile(join(checkout, "jury-package-release-replay-summary-diagnostics-retention-handoff.json"), `${JSON.stringify(replaySummaryDiagnosticsRetentionHandoffPayload, null, 2)}\n`);
    const invalidReplaySummaryDiagnosticsRetentionHandoffReplay = await runShell(replaySummaryDiagnosticsRetentionHandoffReplayCommands.join("\n"), checkout, {
      ...fixedEnv,
      JURY_PACKAGE_RELEASE_EVIDENCE_DIR: "../package-release-evidence",
      JURY_PACKAGE_RELEASE_MANIFEST_PATH: "../package-release-manifest/retained-package-release-evidence-manifest.json",
      JURY_PACKAGE_RELEASE_REPLAY_SUMMARY_DIAGNOSTICS_PATH: "../jury-package-release-replay-summary-diagnostics.json",
      JURY_PACKAGE_RELEASE_REPLAY_SUMMARY_DIAGNOSTICS_RETENTION_HANDOFF_PATH: "../jury-package-release-replay-summary-diagnostics-retention-handoff.json",
    });
    assert.equal(invalidReplaySummaryDiagnosticsRetentionHandoffReplay.exitCode, 1);
    assert.match(invalidReplaySummaryDiagnosticsRetentionHandoffReplay.stderr, /replay summary diagnostics retention handoff replay failed: runId must match retained diagnostics evidence/);
    replaySummaryDiagnosticsRetentionHandoffPayload.runId = "example-release-run-1001";
    await writeFile(join(checkout, "jury-package-release-replay-summary-diagnostics-retention-handoff.json"), `${JSON.stringify(replaySummaryDiagnosticsRetentionHandoffPayload, null, 2)}\n`);

    const retainedReplaySummaryDiagnosticsRetentionHandoffPath = join(replayDir, "jury-package-release-replay-summary-diagnostics-retention-handoff.json");
    const retainedReplaySummaryDiagnosticsRetentionHandoff = JSON.parse(await readFile(retainedReplaySummaryDiagnosticsRetentionHandoffPath, "utf8"));
    retainedReplaySummaryDiagnosticsRetentionHandoff.reviewedBy = "different-maintainer@example.com";
    await writeFile(retainedReplaySummaryDiagnosticsRetentionHandoffPath, `${JSON.stringify(retainedReplaySummaryDiagnosticsRetentionHandoff, null, 2)}\n`);
    const mismatchedReplaySummaryDiagnosticsRetentionHandoff = await runShell(replaySummaryDiagnosticsRetentionHandoffCommands.join("\n"), checkout, {
      ...fixedEnv,
      JURY_PACKAGE_RELEASE_EVIDENCE_DIR: "../package-release-evidence",
      JURY_PACKAGE_RELEASE_MANIFEST_PATH: "../package-release-manifest/retained-package-release-evidence-manifest.json",
      JURY_PACKAGE_RELEASE_REPLAY_SUMMARY_DIAGNOSTICS_PATH: "../jury-package-release-replay-summary-diagnostics.json",
      JURY_PACKAGE_RELEASE_REPLAY_SUMMARY_DIAGNOSTICS_RETENTION_HANDOFF_PATH: "../jury-package-release-replay-summary-diagnostics-retention-handoff.json",
    });
    assert.equal(mismatchedReplaySummaryDiagnosticsRetentionHandoff.exitCode, 1);
    assert.match(mismatchedReplaySummaryDiagnosticsRetentionHandoff.stderr, /generated diagnostics retention handoff must match retained archive evidence/);
    await cp(
      join(checkout, "jury/examples/ci/fixtures/package-release/jury-package-release-replay-summary-diagnostics-retention-handoff.json"),
      retainedReplaySummaryDiagnosticsRetentionHandoffPath,
    );

    await writeFile(join(checkout, "jury-package-release-replay-summary.md"), replaySummaryText.replace("- replacementPackageVersion: 0.1.1", "- replacementPackageVersion: 0.1.2"));
    const driftedReplaySummaryDiagnostics = await runShell(replaySummaryDiagnosticsCommands.join("\n"), checkout, {
      ...fixedEnv,
      JURY_PACKAGE_RELEASE_EVIDENCE_DIR: "../package-release-evidence",
      JURY_PACKAGE_RELEASE_MANIFEST_PATH: "../package-release-manifest/retained-package-release-evidence-manifest.json",
      JURY_PACKAGE_RELEASE_REPLAY_SUMMARY_PATH: "../jury-package-release-replay-summary.md",
      JURY_PACKAGE_RELEASE_REPLAY_SUMMARY_DIAGNOSTICS_PATH: "../jury-package-release-replay-summary-diagnostics.json",
    });
    assert.equal(driftedReplaySummaryDiagnostics.exitCode, 1);
    assert.match(driftedReplaySummaryDiagnostics.stderr, /replay summary diagnostics missing lines: - replacementPackageVersion: 0\.1\.1/);
    await writeFile(join(checkout, "jury-package-release-replay-summary.md"), replaySummaryText);

    const dryRun = await runShell(dryRunCommands.join("\n"), checkout, { ...fixedEnv, JURY_PACKAGE_DIR: "jury" });
    assert.equal(dryRun.exitCode, 0, `${dryRunCommands.join("\n")}\nstdout:\n${dryRun.stdout}\nstderr:\n${dryRun.stderr}`);

    const record = JSON.parse(await readFile(join(checkout, "jury-pack-dry-run-record.json"), "utf8"));
    assert.deepEqual(record, {
      packageVersion: "0.1.0",
      tarballName: "sanogueralorenzo-jury-0.1.0.tgz",
    });

    const summaryPath = join(checkout, "github-step-summary.md");
    const missingReviewer = await runShell(verifyCommands.join("\n"), checkout, { ...fixedEnv, GITHUB_STEP_SUMMARY: summaryPath });
    assert.equal(missingReviewer.exitCode, 1);
    assert.match(missingReviewer.stderr, /JURY_DRY_RUN_REVIEWER must identify who reviewed/);

    const verify = await runShell(verifyCommands.join("\n"), checkout, {
      ...fixedEnv,
      GITHUB_STEP_SUMMARY: summaryPath,
      JURY_DRY_RUN_REVIEWER: "release-owner",
    });
    assert.equal(verify.exitCode, 0, `${verifyCommands.join("\n")}\nstdout:\n${verify.stdout}\nstderr:\n${verify.stderr}`);
    const summary = await readFile(summaryPath, "utf8");
    assert.ok(summary.includes("### Jury package dry-run"));
    assert.ok(summary.includes("- packageVersion: 0.1.0"));
    assert.ok(summary.includes("- tarballName: sanogueralorenzo-jury-0.1.0.tgz"));
    assert.ok(summary.includes("- reviewedBy: release-owner"));
  } finally {
    await rm(checkout, { recursive: true, force: true });
  }
});

test("CI example README points to the copyable workflow and portable artifacts", { skip: skipNestedCiAdoptionTests }, async () => {
  const readme = await readFile(join(repoRoot, "jury/examples/ci/README.md"), "utf8");

  assert.ok(readme.includes("../../CI_ADOPTION.md"));
  assert.ok(readme.includes("jury-review-gate.yml"));
  assert.ok(readme.includes("jury-signed-review-gate.yml"));
  assert.ok(readme.includes("jury-signed-artifact-handoff.yml"));
  assert.ok(readme.includes("jury-trusted-bundle-verify.yml"));
  assert.ok(readme.includes("jury-package-manifest-check.yml"));
  assert.ok(readme.includes("jury-npm-publish.yml"));
  assert.ok(readme.includes("actions/download-artifact@v4"));
  assert.ok(readme.includes("secrets.JURY_CI_PRIVATE_KEY"));
  assert.ok(readme.includes("review-bundle.json"));
  assert.ok(readme.includes("review-bundle.signed.json"));
  assert.ok(readme.includes("gate.json"));
  assert.ok(readme.includes("fixtures/key-policy"));
  assert.ok(readme.includes("fixtures/key-policy-rotation"));
  assert.ok(readme.includes("jury.key_policy.v1"));
  assert.ok(readme.includes("actions/upload-artifact@v4"));
  assert.ok(readme.includes("uses: ./.github/workflows/jury-trusted-bundle-verify.yml"));
  assert.ok(readme.includes('npm --prefix "$JURY_PACKAGE_DIR" run package:manifest:check'));
  assert.ok(readme.includes('npm --prefix "$JURY_PACKAGE_DIR" run fixtures:package-release:check'));
  assert.ok(readme.includes("jury-package-release-evidence"));
  assert.ok(readme.includes("jury-package-release-archive-manifest"));
  assert.ok(readme.includes("rollback, replacement, and archive drift remediation audit examples"));
  assert.ok(readme.includes("package-release-evidence-replay"));
  assert.ok(readme.includes("--fixture-dir"));
  assert.ok(readme.includes('--verify-manifest "$JURY_PACKAGE_RELEASE_MANIFEST_PATH"'));
  assert.ok(readme.includes("JURY_PACKAGE_RELEASE_MANIFEST_PATH"));
  assert.ok(readme.includes("needs: package-manifest"));
  assert.ok(readme.includes("needs: package-release-evidence-replay"));
  assert.ok(readme.includes("before any publication dry run"));
  assert.ok(readme.includes("writes a `GITHUB_STEP_SUMMARY` section for failed and replacement release archive evidence"));
  assert.ok(readme.includes("saves the same content as `jury-package-release-replay-summary.md`"));
  assert.ok(readme.includes("jury-package-release-replay-summary"));
  assert.ok(readme.includes("dry-run-publication"));
  assert.ok(readme.includes("jury-package-dry-run"));
  assert.ok(readme.includes("retention-days: 90"));
  assert.ok(readme.includes("at least 180 days after replacement downstream verification passes"));
  assert.ok(readme.includes("retained artifact provenance"));
  assert.ok(readme.includes("source revision"));
  assert.ok(readme.includes("retained-package-release-evidence-manifest.json"));
  assert.ok(readme.includes("NODE_AUTH_TOKEN"));
  assert.ok(readme.includes("GITHUB_STEP_SUMMARY"));
  assert.ok(readme.includes("dry_run_reviewer"));
  assert.ok(readme.includes("reviewedBy"));
  assert.ok(readme.includes("npm view @sanogueralorenzo/jury@<packageVersion> version dist.tarball --json"));
  assert.ok(readme.includes("npm publish --provenance --access public"));
});

test("CI adoption guide chooses the supported workflow paths", async () => {
  const guidePath = join(repoRoot, "jury/CI_ADOPTION.md");
  const guide = await readFile(guidePath, "utf8");
  const readme = await readFile(join(repoRoot, "jury/README.md"), "utf8");
  const ciReadme = await readFile(join(repoRoot, "jury/examples/ci/README.md"), "utf8");
  const linkedTargets = [...guide.matchAll(/\[[^\]]+\]\(([^)]+)\)/g)].map((match) => match[1]);

  for (const requiredLink of [
    "examples/ci/jury-review-gate.yml",
    "examples/ci/jury-signed-review-gate.yml",
    "examples/ci/jury-signed-artifact-handoff.yml",
    "examples/ci/jury-trusted-bundle-verify.yml",
    "examples/ci/fixtures/key-policy",
    "examples/ci/fixtures/key-policy-rotation",
    "QUICKSTART.md",
  ]) {
    assert.ok(linkedTargets.includes(requiredLink), `CI_ADOPTION.md should link ${requiredLink}`);
  }

  for (const target of linkedTargets) {
    await stat(join(dirname(guidePath), target));
  }

  for (const choice of [
    "Single-job verdict and portable review state",
    "Single producer job with signed output",
    "Producer and consumer jobs in one workflow",
    "Reusable downstream verifier",
    "actions/download-artifact@v4",
    "secrets.JURY_CI_PRIVATE_KEY",
    "npm --prefix jury run fixtures:key-policy:check",
  ]) {
    assert.ok(guide.includes(choice), `CI_ADOPTION.md should mention ${choice}`);
  }

  assert.ok(readme.includes("CI_ADOPTION.md"));
  assert.ok(ciReadme.includes("../../CI_ADOPTION.md"));
});

test("key policy CI fixtures verify and import a signed review bundle", async () => {
  const stateDir = await tempState();
  const downstreamDir = await tempState();
  const bundlePath = join(ciKeyPolicyFixturesDir, "review-bundle.signed.json");
  const policyPath = join(ciKeyPolicyFixturesDir, "jury-key-policy.json");
  const untrustedProducerPolicyPath = join(ciKeyPolicyFixturesDir, "jury-key-policy.untrusted-producer.json");
  const publicKeyPath = join(ciKeyPolicyFixturesDir, "ci-public.pem");
  const readme = await readFile(join(ciKeyPolicyFixturesDir, "README.md"), "utf8");
  const bundle = JSON.parse(await readFile(bundlePath, "utf8"));
  const policy = JSON.parse(await readFile(policyPath, "utf8"));
  const untrustedProducerPolicy = JSON.parse(await readFile(untrustedProducerPolicyPath, "utf8"));
  const publicKey = await readFile(publicKeyPath, "utf8");

  try {
    assert.equal(bundle.schema_version, "jury.review_bundle.v1");
    assert.equal(bundle.attestation.type, "rsa-sha256");
    assert.equal(bundle.attestation.key_id, "ci-fixture");
    assert.equal(policy.schema_version, "jury.key_policy.v1");
    assert.equal(policy.producers[0].keys[0].public_key_path, "ci-public.pem");
    assert.equal(untrustedProducerPolicy.producers[0].source, "retired-ci");
    assert.equal(untrustedProducerPolicy.producers[0].revision_pattern, "^retired$");
    assert.match(publicKey, /BEGIN PUBLIC KEY/);
    assert.ok(readme.includes("bundle preflight --bundle"));
    assert.ok(readme.includes("bundle import --state-dir"));
    assert.ok(readme.includes("jury-key-policy.untrusted-producer.json"));
    assert.ok(readme.includes("fixtures:key-policy"));
    assert.ok(readme.includes("fixtures:key-policy:check"));

    const preflight = await runProcess(["bundle", "preflight", "--bundle", bundlePath, "--key-policy", policyPath]);
    const preflightPayload = JSON.parse(preflight.stdout);

    assert.equal(preflight.exitCode, 0, preflight.stderr);
    assert.equal(preflightPayload.ok, true);
    assert.deepEqual(preflightPayload.key_policy.matching_producers.map((producer) => producer.producer_index), [0]);
    assert.deepEqual(preflightPayload.key_policy.considered_keys.map((key) => key.status), ["verified"]);

    const imported = await runProcess(["bundle", "import", "--state-dir", stateDir, "--bundle", bundlePath, "--key-policy", policyPath, "--verdict-out", join(stateDir, "imported-verdict.json")]);
    const importedPayload = JSON.parse(imported.stdout);
    const gate = await runProcess(["gate", "--state-dir", stateDir, "--claim", "claim_ci_change", "--verdict", join(stateDir, "imported-verdict.json")]);

    assert.equal(imported.exitCode, 0, imported.stderr);
    assert.equal(importedPayload.ok, true);
    assert.equal(gate.exitCode, 0, gate.stderr);
    assert.equal(JSON.parse(gate.stdout).ok, true);

    const copiedFixtureDir = join(downstreamDir, "key-policy");
    await cp(ciKeyPolicyFixturesDir, copiedFixtureDir, { recursive: true });

    const copiedPreflight = await runProcess(["bundle", "preflight", "--bundle", join(copiedFixtureDir, "review-bundle.signed.json"), "--key-policy", join(copiedFixtureDir, "jury-key-policy.json")]);
    const copiedImportDir = join(downstreamDir, "imported-state");
    const copiedImport = await runProcess(["bundle", "import", "--state-dir", copiedImportDir, "--bundle", join(copiedFixtureDir, "review-bundle.signed.json"), "--key-policy", join(copiedFixtureDir, "jury-key-policy.json"), "--verdict-out", join(downstreamDir, "imported-verdict.json")]);

    assert.equal(copiedPreflight.exitCode, 0, copiedPreflight.stderr);
    assert.equal(JSON.parse(copiedPreflight.stdout).key_policy.considered_keys[0].status, "verified");
    assert.equal(copiedImport.exitCode, 0, copiedImport.stderr);

    const untrustedProducer = await runProcess(["bundle", "preflight", "--bundle", bundlePath, "--key-policy", untrustedProducerPolicyPath]);
    const untrustedProducerPayload = JSON.parse(untrustedProducer.stdout);

    assert.equal(untrustedProducer.exitCode, 1);
    assert.match(untrustedProducerPayload.errors.join("\n"), /no trusted producer/);
    assert.deepEqual(untrustedProducerPayload.key_policy.matching_producers, []);
    assert.deepEqual(untrustedProducerPayload.key_policy.considered_keys, []);

    const driftCheck = await runShell("npm --prefix jury run fixtures:key-policy:check", repoRoot, {
      ...fixedEnv,
      GITHUB_REPOSITORY: "owner/repo",
      GITHUB_SHA: "abc123",
      GITHUB_WORKFLOW: "CI",
      GITHUB_RUN_ID: "1",
    });
    assert.equal(driftCheck.exitCode, 0, driftCheck.stderr);
    assert.match(driftCheck.stdout, /key-policy fixtures are in sync/);
  } finally {
    await rm(stateDir, { recursive: true, force: true });
    await rm(downstreamDir, { recursive: true, force: true });
  }
});

test("key policy rotation fixtures accept old and new keys during overlap", async () => {
  const oldBundlePath = join(ciKeyPolicyRotationFixturesDir, "review-bundle.old.signed.json");
  const newBundlePath = join(ciKeyPolicyRotationFixturesDir, "review-bundle.new.signed.json");
  const policyPath = join(ciKeyPolicyRotationFixturesDir, "jury-key-policy.rotation.json");
  const revokedPolicyPath = join(ciKeyPolicyRotationFixturesDir, "jury-key-policy.revoked-old.json");
  const readme = await readFile(join(ciKeyPolicyRotationFixturesDir, "README.md"), "utf8");
  const oldBundle = JSON.parse(await readFile(oldBundlePath, "utf8"));
  const newBundle = JSON.parse(await readFile(newBundlePath, "utf8"));
  const policy = JSON.parse(await readFile(policyPath, "utf8"));
  const revokedPolicy = JSON.parse(await readFile(revokedPolicyPath, "utf8"));

  assert.equal(policy.schema_version, "jury.key_policy.v1");
  assert.deepEqual(policy.producers[0].keys.map((key) => key.key_id), ["ci-old", "ci-new"]);
  assert.equal(revokedPolicy.producers[0].keys[0].revoked_at, "2026-06-01T00:00:00.000Z");
  assert.match(revokedPolicy.producers[0].keys[0].revoked_reason, /migration window closed/);
  assert.equal(policy.producers[0].keys[0].valid_until, "2026-06-01T00:00:00.000Z");
  assert.equal(policy.producers[0].keys[1].valid_from, "2026-05-15T00:00:00.000Z");
  assert.equal(oldBundle.attestation.key_id, "ci-old");
  assert.equal(newBundle.attestation.key_id, "ci-new");
  assert.ok(readme.includes("migration window"));
  assert.ok(readme.includes("May 15, 2026 through June 1, 2026"));
  assert.ok(readme.includes("fails preflight because `ci-old` is revoked"));

  const oldPreflight = await runProcess(["bundle", "preflight", "--bundle", oldBundlePath, "--key-policy", policyPath]);
  const newPreflight = await runProcess(["bundle", "preflight", "--bundle", newBundlePath, "--key-policy", policyPath]);
  const revokedOldPreflight = await runProcess(["bundle", "preflight", "--bundle", oldBundlePath, "--key-policy", revokedPolicyPath]);
  const revokedNewPreflight = await runProcess(["bundle", "preflight", "--bundle", newBundlePath, "--key-policy", revokedPolicyPath]);
  const oldPayload = JSON.parse(oldPreflight.stdout);
  const newPayload = JSON.parse(newPreflight.stdout);
  const revokedOldPayload = JSON.parse(revokedOldPreflight.stdout);
  const revokedNewPayload = JSON.parse(revokedNewPreflight.stdout);

  assert.equal(oldPreflight.exitCode, 0, oldPreflight.stderr);
  assert.equal(newPreflight.exitCode, 0, newPreflight.stderr);
  assert.equal(revokedOldPreflight.exitCode, 1);
  assert.equal(revokedNewPreflight.exitCode, 0, revokedNewPreflight.stderr);
  assert.deepEqual(oldPayload.key_policy.considered_keys.map((key) => [key.key_id, key.status]), [["ci-old", "verified"], ["ci-new", "not_selected"]]);
  assert.deepEqual(newPayload.key_policy.considered_keys.map((key) => [key.key_id, key.status]), [["ci-old", "not_selected"], ["ci-new", "verified"]]);
  assert.match(revokedOldPayload.errors.join("\n"), /ci-old is revoked/);
  assert.deepEqual(revokedOldPayload.key_policy.considered_keys.map((key) => [key.key_id, key.status]), [["ci-old", "revoked"], ["ci-new", "not_selected"]]);
  assert.deepEqual(revokedNewPayload.key_policy.considered_keys.map((key) => [key.key_id, key.status]), [["ci-old", "not_selected"], ["ci-new", "verified"]]);

  const driftCheck = await runShell("npm --prefix jury run fixtures:key-policy:check");
  assert.equal(driftCheck.exitCode, 0, driftCheck.stderr);
});

test("package release evidence fixtures cover rollback and replacement audits", async () => {
  const readFixture = (name) => readFile(join(ciPackageReleaseFixturesDir, name), "utf8").then(JSON.parse);
  const readme = await readFile(join(ciPackageReleaseFixturesDir, "README.md"), "utf8");
  const linkedTargets = [...readme.matchAll(/\[[^\]]+\]\(([^)]+)\)/g)].map((match) => match[1]);
  const dryRunRecord = await readFixture("jury-pack-dry-run-record.json");
  const failedNpmView = await readFixture("failed-npm-view.json");
  const failedGate = await readFixture("downstream-failure-gate.json");
  const rollbackAudit = await readFixture("rollback-audit.json");
  const replacementNpmView = await readFixture("replacement-npm-view.json");
  const replacementGate = await readFixture("replacement-downstream-gate.json");
  const replacementAudit = await readFixture("replacement-patch-audit.json");
  const retainedArchiveManifest = await readFixture("retained-package-release-evidence-manifest.json");
  const remediationAudit = await readFixture("archive-drift-remediation-audit.json");
  const remediationAuditHandoff = await readFixture("archive-drift-remediation-audit-handoff.json");
  const replaySummaryDiagnosticsRetentionHandoff = await readFixture("jury-package-release-replay-summary-diagnostics-retention-handoff.json");
  const replaySummaryExpiryHandoff = await readFixture("jury-package-release-replay-summary-expiry-handoff.json");
  const publicationNotes = await readFile(join(repoRoot, "jury/PUBLISHING.md"), "utf8");
  const replacementCommands = extractShellBlock(publicationNotes, "Replacement Patch Evidence");

  assert.ok(readme.includes("rollback-audit.json"));
  assert.ok(readme.includes("replacement-patch-audit.json"));
  assert.ok(readme.includes("retained-package-release-evidence-manifest.json"));
  assert.ok(readme.includes("archive-drift-remediation-audit.json"));
  assert.ok(readme.includes("archive-drift-remediation-audit-handoff.json"));
  assert.ok(readme.includes("package-release-remediation-audit.schema.json"));
  assert.ok(readme.includes("package-release-remediation-audit-handoff.schema.json"));
  assert.ok(readme.includes("Archive Drift Remediation Audit"));
  assert.ok(readme.includes("If the remediation audit handoff schema fails"));
  assert.ok(readme.includes("required schema version, `sourceAudit`, `sourceManifest`, retained companion records"));
  assert.ok(readme.includes("npm --prefix jury run fixtures:package-release:check"));
  assert.ok(readme.includes("downstream verification passes"));
  assert.ok(readme.includes("jury.package_release_retention.v1"));
  assert.ok(readme.includes("retention.provenance"));
  assert.ok(readme.includes("source revision"));
  assert.ok(readme.includes("retentionDays: 90"));
  assert.ok(readme.includes("--manifest-out examples/ci/fixtures/package-release/retained-package-release-evidence-manifest.json"));
  assert.ok(readme.includes("--verify-manifest examples/ci/fixtures/package-release/retained-package-release-evidence-manifest.json"));
  assert.ok(readme.includes("npm --prefix jury run fixtures:package-release:drift"));
  assert.ok(readme.includes("manifest drifts from the failed or replacement release archive evidence"));
  assert.ok(readme.includes("archive evidence digests"));
  assert.ok(readme.includes("jury.package_release_archive_manifest.v1"));
  assert.ok(readme.includes("package-release-archive-manifest.schema.json"));
  assert.ok(readme.includes("Release Archive Manifest"));
  assert.ok(readme.includes("Replay Summary Diagnostics Retention Handoff"));
  assert.ok(readme.includes("package-release-replay-summary-diagnostics-retention-handoff.schema.json"));
  assert.ok(readme.includes("90-day artifact expiry"));
  assert.ok(readme.includes("180 days after replacement downstream verification passes"));
  for (const target of linkedTargets) {
    await stat(join(ciPackageReleaseFixturesDir, target));
  }
  assert.equal(rollbackAudit.schema_version, "jury.package_release_evidence.v1");
  assert.equal(rollbackAudit.audit_type, "failed-publication-rollback");
  assert.equal(replacementAudit.schema_version, "jury.package_release_evidence.v1");
  assert.equal(replacementAudit.audit_type, "replacement-patch-supersedence");
  assert.equal(retainedArchiveManifest.schema_version, "jury.package_release_archive_manifest.v1");
  assert.equal(retainedArchiveManifest.failed.rollbackAudit, "rollback-audit.json");
  assert.equal(retainedArchiveManifest.replacement.replacementAudit, "replacement-patch-audit.json");
  assert.deepEqual(retainedArchiveManifest.provenance.artifacts.map((artifact) => artifact.name), [
    "jury-package-dry-run",
    "jury-package-release-evidence",
    "jury-package-release-replay-summary",
  ]);
  assert.equal(remediationAudit.schema_version, "jury.package_release_remediation_audit.v1");
  assert.equal(remediationAudit.audit_type, "retained-archive-drift-remediation");
  assert.equal(remediationAudit.failed.packageVersion, dryRunRecord.packageVersion);
  assert.equal(remediationAudit.failed.tarballName, dryRunRecord.tarballName);
  assert.equal(remediationAudit.replacement.packageVersion, replacementAudit.replacement.packageVersion);
  assert.deepEqual(remediationAudit.drift.evidence.map((item) => item.path), ["downstream-failure-gate.json", "replacement-downstream-gate.json"]);
  assert.deepEqual(remediationAudit.drift.evidence.map((item) => item.archive), ["failed-publication", "replacement-patch"]);
  assert.ok(remediationAudit.remediation.restoredEvidence.some((item) => item.path === "downstream-failure-gate.json" && item.archive === "failed-publication"));
  assert.ok(remediationAudit.remediation.restoredEvidence.some((item) => item.path === "replacement-downstream-gate.json" && item.archive === "replacement-patch"));
  assert.equal(remediationAudit.remediation.policy, "restore-before-regenerate");
  assert.equal(remediationAudit.remediation.diffReviewed, true);
  assert.ok(remediationAudit.verification.commands.some((command) => command.includes("--verify-manifest")));
  assert.ok(remediationAudit.verification.commands.some((command) => command.includes("archiveEvidence SHA-256 helper")));
  assert.ok(remediationAudit.verification.commands.some((command) => command.includes("dry-run identity helper")));
  assert.ok(remediationAudit.verification.commands.some((command) => command.includes("fixtures:package-release:drift")));
  assert.equal(remediationAudit.record.location, "release record or incident archive");
  assert.equal(remediationAuditHandoff.schema_version, "jury.package_release_remediation_audit_handoff.v1");
  assert.equal(remediationAuditHandoff.sourceAudit, "archive-drift-remediation-audit.json");
  assert.equal(remediationAuditHandoff.sourceManifest, "retained-package-release-evidence-manifest.json");
  assert.ok(remediationAuditHandoff.retainedWith.includes("archive-drift-remediation-audit.json"));
  assert.equal(remediationAuditHandoff.failedPackageVersion, dryRunRecord.packageVersion);
  assert.equal(remediationAuditHandoff.failedTarballName, dryRunRecord.tarballName);
  assert.equal(remediationAuditHandoff.replacementPackageVersion, replacementAudit.replacement.packageVersion);
  assert.deepEqual(remediationAuditHandoff.driftEvidence, remediationAudit.drift.evidence.map((item) => item.path));
  assert.deepEqual(remediationAuditHandoff.restoredEvidence, remediationAudit.remediation.restoredEvidence.map((item) => item.path));
  assert.deepEqual(remediationAuditHandoff.verificationCommands, remediationAudit.verification.commands);
  assert.equal(remediationAuditHandoff.approvedAt, remediationAudit.approval.approvedAt);
  assert.deepEqual(retainedArchiveManifest.archiveEvidence.map((item) => item.path), [
    "jury-pack-dry-run-record.json",
    "failed-npm-view.json",
    "downstream-failure-gate.json",
    "rollback-audit.json",
    "replacement-npm-view.json",
    "replacement-downstream-gate.json",
    "replacement-patch-audit.json",
    "archive-drift-remediation-audit.json",
    "archive-drift-remediation-audit-handoff.json",
    "jury-package-release-replay-summary.md",
    "jury-package-release-replay-summary-diagnostics.json",
    "jury-package-release-replay-summary-diagnostics-retention-handoff.json",
    "jury-package-release-replay-summary-expiry-handoff.json",
  ]);
  assert.ok(retainedArchiveManifest.archiveEvidence.every((item) => /^sha256:[a-f0-9]{64}$/.test(item.sha256)));
  const archiveEvidenceDigests = new Map(retainedArchiveManifest.archiveEvidence.map((item) => [item.path, item.sha256]));
  for (const path of ["downstream-failure-gate.json", "replacement-downstream-gate.json"]) {
    const bytes = await readFile(join(ciPackageReleaseFixturesDir, path));
    assert.equal(archiveEvidenceDigests.get(path), `sha256:${createHash("sha256").update(bytes).digest("hex")}`);
  }
  assert.equal(rollbackAudit.retention.policy, "jury.package_release_retention.v1");
  assert.equal(replacementAudit.retention.policy, "jury.package_release_retention.v1");
  assert.equal(rollbackAudit.retention.storage, "release record or incident archive");
  assert.equal(replacementAudit.retention.storage, "release record or incident archive");
  assert.equal(rollbackAudit.retention.retainUntil, "180 days after replacement downstream verification passes");
  assert.equal(replacementAudit.retention.retainUntil, "180 days after replacement downstream verification passes");
  assert.equal(rollbackAudit.retention.provenance.source, "github-actions");
  assert.equal(replacementAudit.retention.provenance.source, "github-actions");
  assert.equal(rollbackAudit.retention.provenance.workflow, "jury-npm-publish.yml");
  assert.equal(replacementAudit.retention.provenance.workflow, "jury-npm-publish.yml");
  assert.equal(rollbackAudit.retention.provenance.runId, replacementAudit.retention.provenance.runId);
  assert.equal(rollbackAudit.retention.provenance.sourceRevision, replacementAudit.retention.provenance.sourceRevision);
  const rollbackProvenance = new Map(rollbackAudit.retention.provenance.artifacts.map((artifact) => [artifact.name, artifact]));
  const replacementProvenance = new Map(replacementAudit.retention.provenance.artifacts.map((artifact) => [artifact.name, artifact]));
  assert.equal(rollbackProvenance.get("jury-package-dry-run").sourceJob, "dry-run-publication");
  assert.equal(rollbackProvenance.get("jury-package-dry-run").retentionDays, 90);
  assert.ok(rollbackProvenance.get("jury-package-dry-run").files.includes("jury-pack-dry-run-record.json"));
  assert.equal(replacementProvenance.get("jury-package-release-evidence").sourceJob, "package-release-fixtures");
  assert.equal(replacementProvenance.get("jury-package-release-evidence").retentionDays, 90);
  assert.ok(replacementProvenance.get("jury-package-release-evidence").files.includes("downstream-failure-gate.json"));
  assert.ok(replacementProvenance.get("jury-package-release-evidence").files.includes("replacement-patch-audit.json"));
  assert.ok(replacementProvenance.get("jury-package-release-evidence").files.includes("archive-drift-remediation-audit.json"));
  assert.ok(replacementProvenance.get("jury-package-release-evidence").files.includes("jury-package-release-replay-summary.md"));
  assert.ok(replacementProvenance.get("jury-package-release-evidence").files.includes("jury-package-release-replay-summary-diagnostics-retention-handoff.json"));
  assert.ok(replacementProvenance.get("jury-package-release-evidence").files.includes("jury-package-release-replay-summary-expiry-handoff.json"));
  assert.equal(rollbackProvenance.get("jury-package-release-replay-summary").sourceJob, "package-release-evidence-replay");
  assert.equal(replacementProvenance.get("jury-package-release-replay-summary").retentionDays, 90);
  assert.ok(replacementProvenance.get("jury-package-release-replay-summary").files.includes("jury-package-release-replay-summary.md"));
  assert.ok(replacementProvenance.get("jury-package-release-replay-summary").files.includes("jury-package-release-replay-summary-diagnostics-retention-handoff.json"));
  assert.ok(rollbackAudit.retention.artifacts.includes("jury-package-dry-run"));
  assert.ok(rollbackAudit.retention.artifacts.includes("jury-package-release-evidence"));
  assert.ok(rollbackAudit.retention.artifacts.includes("jury-package-release-replay-summary"));
  assert.ok(rollbackAudit.retention.artifacts.includes("downstream-failure-gate.json"));
  assert.ok(rollbackAudit.retention.artifacts.includes("jury-package-release-replay-summary.md"));
  assert.ok(rollbackAudit.retention.artifacts.includes("jury-package-release-replay-summary-diagnostics.json"));
  assert.ok(rollbackAudit.retention.artifacts.includes("jury-package-release-replay-summary-diagnostics-retention-handoff.json"));
  assert.ok(rollbackAudit.retention.artifacts.includes("jury-package-release-replay-summary-expiry-handoff.json"));
  assert.ok(rollbackAudit.retention.artifacts.includes("GITHUB_STEP_SUMMARY"));
  assert.ok(replacementAudit.retention.artifacts.includes("jury-package-release-replay-summary"));
  assert.ok(replacementAudit.retention.artifacts.includes("downstream-failure-gate.json"));
  assert.ok(replacementAudit.retention.artifacts.includes("replacement-npm-view.json"));
  assert.ok(replacementAudit.retention.artifacts.includes("replacement-downstream-gate.json"));
  assert.ok(replacementAudit.retention.artifacts.includes("replacement-patch-audit.json"));
  assert.ok(replacementAudit.retention.artifacts.includes("jury-package-release-replay-summary.md"));
  assert.ok(replacementAudit.retention.artifacts.includes("jury-package-release-replay-summary-diagnostics.json"));
  assert.ok(replacementAudit.retention.artifacts.includes("jury-package-release-replay-summary-diagnostics-retention-handoff.json"));
  assert.ok(replacementAudit.retention.artifacts.includes("jury-package-release-replay-summary-expiry-handoff.json"));
  assert.equal(replaySummaryDiagnosticsRetentionHandoff.schema_version, "jury.package_release_replay_summary_diagnostics_retention_handoff.v1");
  assert.equal(replaySummaryDiagnosticsRetentionHandoff.failedPackageVersion, dryRunRecord.packageVersion);
  assert.equal(replaySummaryDiagnosticsRetentionHandoff.failedTarballName, dryRunRecord.tarballName);
  assert.equal(replaySummaryDiagnosticsRetentionHandoff.replacementPackageVersion, replacementAudit.replacement.packageVersion);
  assert.equal(replaySummaryExpiryHandoff.schema_version, "jury.package_release_replay_summary_expiry_handoff.v1");
  assert.equal(replaySummaryExpiryHandoff.failedPackageVersion, dryRunRecord.packageVersion);
  assert.equal(replaySummaryExpiryHandoff.replacementPackageVersion, replacementAudit.replacement.packageVersion);
  assert.equal(replaySummaryExpiryHandoff.reviewedBy, remediationAudit.approval.approvedBy);
  assert.equal(replaySummaryDiagnosticsRetentionHandoff.runId, rollbackAudit.retention.provenance.runId);
  assert.equal(replaySummaryDiagnosticsRetentionHandoff.sourceRevision, rollbackAudit.retention.provenance.sourceRevision);
  assert.equal(replaySummaryDiagnosticsRetentionHandoff.reviewedBy, remediationAudit.approval.approvedBy);
  assert.equal(rollbackAudit.failed.packageVersion, dryRunRecord.packageVersion);
  assert.equal(rollbackAudit.failed.tarballName, dryRunRecord.tarballName);
  assert.equal(replacementAudit.failed.packageVersion, dryRunRecord.packageVersion);
  assert.equal(replacementAudit.failed.tarballName, dryRunRecord.tarballName);
  assert.equal(failedNpmView.version, dryRunRecord.packageVersion);
  assert.ok(failedNpmView.dist.tarball.endsWith(dryRunRecord.tarballName));
  assert.equal(failedGate.ok, false);
  assert.equal(failedGate.decision, "reject");
  assert.equal(rollbackAudit.deprecation.allowed, true);
  assert.ok(rollbackAudit.deprecation.command.includes("@sanogueralorenzo/jury@0.1.0"));
  assert.equal(rollbackAudit.requiredNextAudit, "replacement-patch-audit.json");
  assert.notEqual(replacementAudit.replacement.packageVersion, dryRunRecord.packageVersion);
  assert.equal(replacementNpmView.version, replacementAudit.replacement.packageVersion);
  assert.equal(replacementNpmView.dist.tarball, replacementAudit.replacement.distTarball);
  assert.ok(!replacementAudit.replacement.distTarball.endsWith(dryRunRecord.tarballName));
  assert.equal(replacementGate.ok, true);
  assert.equal(replacementGate.decision, "accept");
  assert.ok(replacementAudit.checks.includes("replacement downstream verification passed"));
  assert.ok(replacementCommands[1].startsWith("node -e "));
  assert.ok(!replacementCommands[1].includes("npm view"));

  const fixtureAudit = await runShell(replacementCommands[1], ciPackageReleaseFixturesDir);
  assert.equal(fixtureAudit.exitCode, 0, fixtureAudit.stderr);
  assert.deepEqual(JSON.parse(fixtureAudit.stdout), {
    failedPackageVersion: "0.1.0",
    failedTarballName: "sanogueralorenzo-jury-0.1.0.tgz",
    replacementPackageVersion: "0.1.1",
    replacementTarball: "https://registry.npmjs.org/@sanogueralorenzo/jury/-/sanogueralorenzo-jury-0.1.1.tgz",
  });

  const fixtureCheck = await runShell("npm --prefix jury run fixtures:package-release:check");
  assert.equal(fixtureCheck.exitCode, 0, fixtureCheck.stderr);
  const fixtureCheckPayload = JSON.parse(fixtureCheck.stdout.slice(fixtureCheck.stdout.indexOf("{")));
  assert.equal(fixtureCheckPayload.ok, true);
  assert.equal(fixtureCheckPayload.manifestOut, null);
  assert.equal(fixtureCheckPayload.archiveDriftManifest, null);
  assert.equal(fixtureCheckPayload.schema, "schemas/package-release-evidence.schema.json");
  assert.equal(fixtureCheckPayload.archiveManifestSchema, "schemas/package-release-archive-manifest.schema.json");
  assert.equal(fixtureCheckPayload.remediationAuditSchema, "schemas/package-release-remediation-audit.schema.json");
  assert.equal(fixtureCheckPayload.remediationAuditHandoffSchema, "schemas/package-release-remediation-audit-handoff.schema.json");
  assert.equal(fixtureCheckPayload.replaySummaryDiagnosticsSchema, "schemas/package-release-replay-summary-diagnostics.schema.json");
  assert.equal(fixtureCheckPayload.replaySummaryDiagnosticsRetentionHandoffSchema, "schemas/package-release-replay-summary-diagnostics-retention-handoff.schema.json");
  assert.equal(fixtureCheckPayload.replaySummaryExpiryHandoffSchema, "schemas/package-release-replay-summary-expiry-handoff.schema.json");
  assert.deepEqual(fixtureCheckPayload.fixtures, [
    "rollback-audit.json",
    "replacement-patch-audit.json",
    "archive-drift-remediation-audit.json",
    "archive-drift-remediation-audit-handoff.json",
    "jury-package-release-replay-summary.md",
    "jury-package-release-replay-summary-diagnostics.json",
    "jury-package-release-replay-summary-diagnostics-retention-handoff.json",
    "jury-package-release-replay-summary-expiry-handoff.json",
  ]);
  const fixtureDriftCheck = await runShell("npm --prefix jury run fixtures:package-release:drift");
  assert.equal(fixtureDriftCheck.exitCode, 0, fixtureDriftCheck.stderr);
  assert.equal(JSON.parse(fixtureDriftCheck.stdout.slice(fixtureDriftCheck.stdout.indexOf("{"))).archiveDriftManifest, join(ciPackageReleaseFixturesDir, "retained-package-release-evidence-manifest.json"));
  const fixtureManifestCheck = await runShell(`npm --prefix jury run fixtures:package-release:check -- --verify-manifest ${shellQuote(join(ciPackageReleaseFixturesDir, "retained-package-release-evidence-manifest.json"))}`);
  assert.equal(fixtureManifestCheck.exitCode, 0, fixtureManifestCheck.stderr);
  assert.equal(JSON.parse(fixtureManifestCheck.stdout.slice(fixtureManifestCheck.stdout.indexOf("{"))).verifiedManifest, join(ciPackageReleaseFixturesDir, "retained-package-release-evidence-manifest.json"));
  const documentedFixtureCommands = extractShellBlock(readme, "Validation");
  assert.equal(documentedFixtureCommands[1], "npm --prefix jury run fixtures:package-release:check -- --manifest-out examples/ci/fixtures/package-release/retained-package-release-evidence-manifest.json");
  assert.equal(documentedFixtureCommands[2], "npm --prefix jury run fixtures:package-release:check -- --verify-manifest examples/ci/fixtures/package-release/retained-package-release-evidence-manifest.json");
  assert.equal(documentedFixtureCommands[3], "npm --prefix jury run fixtures:package-release:drift");
  const documentedFixtureCheckout = await copyJuryCheckout();
  try {
    for (const command of documentedFixtureCommands) {
      const documentedCheck = await runShell(command, documentedFixtureCheckout);
      assert.equal(documentedCheck.exitCode, 0, documentedCheck.stderr);
    }
    const documentedManifest = JSON.parse(await readFile(join(
      documentedFixtureCheckout,
      "jury/examples/ci/fixtures/package-release/retained-package-release-evidence-manifest.json",
    ), "utf8"));
    assert.deepEqual(documentedManifest, retainedArchiveManifest);
  } finally {
    await rm(documentedFixtureCheckout, { recursive: true, force: true });
  }

  const manifestDir = await tempState();
  try {
    const manifestPath = join(manifestDir, "retained-package-release-evidence-manifest.json");
    const manifestCheck = await runShell(`npm --prefix jury run fixtures:package-release:check -- --fixture-dir ${shellQuote(ciPackageReleaseFixturesDir)} --manifest-out ${shellQuote(manifestPath)}`);
    assert.equal(manifestCheck.exitCode, 0, manifestCheck.stderr);
    assert.equal(JSON.parse(manifestCheck.stdout.slice(manifestCheck.stdout.indexOf("{"))).manifestOut, manifestPath);
    const verifiedManifestCheck = await runShell(`npm --prefix jury run fixtures:package-release:check -- --fixture-dir ${shellQuote(ciPackageReleaseFixturesDir)} --verify-manifest ${shellQuote(manifestPath)}`);
    assert.equal(verifiedManifestCheck.exitCode, 0, verifiedManifestCheck.stderr);
    assert.equal(JSON.parse(verifiedManifestCheck.stdout.slice(verifiedManifestCheck.stdout.indexOf("{"))).verifiedManifest, manifestPath);
    const manifest = JSON.parse(await readFile(manifestPath, "utf8"));

    assert.equal(manifest.schema_version, "jury.package_release_archive_manifest.v1");
    assert.equal(manifest.package, "@sanogueralorenzo/jury");
    assert.deepEqual(manifest.failed, {
      packageVersion: "0.1.0",
      tarballName: "sanogueralorenzo-jury-0.1.0.tgz",
      dryRunRecord: "jury-pack-dry-run-record.json",
      npmView: "failed-npm-view.json",
      downstreamGate: "downstream-failure-gate.json",
      rollbackAudit: "rollback-audit.json",
      deprecation: rollbackAudit.deprecation,
    });
    assert.equal(manifest.replacement.packageVersion, "0.1.1");
    assert.equal(manifest.replacement.replacementAudit, "replacement-patch-audit.json");
    assert.equal(manifest.retention.policy, "jury.package_release_retention.v1");
    assert.equal(manifest.retention.retainUntil, "180 days after replacement downstream verification passes");
    assert.ok(manifest.retention.artifacts.includes("replacement-patch-audit.json"));
    assert.equal(manifest.provenance.source, "github-actions");
    assert.equal(manifest.provenance.workflow, "jury-npm-publish.yml");
    assert.equal(manifest.provenance.runId, rollbackAudit.retention.provenance.runId);
    assert.equal(manifest.provenance.sourceRevision, rollbackAudit.retention.provenance.sourceRevision);
    assert.deepEqual(manifest.provenance.artifacts.map((artifact) => artifact.name), [
      "jury-package-dry-run",
      "jury-package-release-evidence",
      "jury-package-release-replay-summary",
    ]);
    assert.ok(manifest.archiveEvidence.some((item) => item.path === "downstream-failure-gate.json"));
    assert.ok(manifest.archiveEvidence.some((item) => item.path === "replacement-downstream-gate.json"));
    assert.deepEqual(manifest, retainedArchiveManifest);

    const missingProvenanceArtifactManifest = structuredClone(manifest);
    missingProvenanceArtifactManifest.provenance.artifacts = missingProvenanceArtifactManifest.provenance.artifacts.filter((artifact) => artifact.name !== "jury-package-release-evidence");
    await writeFile(manifestPath, `${JSON.stringify(missingProvenanceArtifactManifest, null, 2)}\n`);
    const missingProvenanceArtifactCheck = await runShell(`npm --prefix jury run fixtures:package-release:check -- --fixture-dir ${shellQuote(ciPackageReleaseFixturesDir)} --verify-manifest ${shellQuote(manifestPath)}`);
    assert.equal(missingProvenanceArtifactCheck.exitCode, 1);
    assert.match(missingProvenanceArtifactCheck.stderr, /retained-package-release-evidence-manifest\.json\.provenance\.artifacts must contain an item matching required archive evidence/);

    manifest.schema_version = "jury.package_release_archive_manifest.invalid";
    manifest.provenance.runId = "different-release-run";
    await writeFile(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`);
    const invalidManifestCheck = await runShell(`npm --prefix jury run fixtures:package-release:check -- --fixture-dir ${shellQuote(ciPackageReleaseFixturesDir)} --verify-manifest ${shellQuote(manifestPath)}`);
    assert.equal(invalidManifestCheck.exitCode, 1);
    assert.match(invalidManifestCheck.stderr, /retained-package-release-evidence-manifest\.json does not match retained package release evidence/);
    assert.match(invalidManifestCheck.stderr, /retained-package-release-evidence-manifest\.json\.schema_version must equal jury\.package_release_archive_manifest\.v1/);
    assert.match(invalidManifestCheck.stderr, /retained-package-release-evidence-manifest\.json\.provenance\.runId must match retained evidence provenance/);
  } finally {
    await rm(manifestDir, { recursive: true, force: true });
  }

  const invalidDir = await tempState();
  try {
    const copiedFixtureDir = join(invalidDir, "package-release");
    await cp(ciPackageReleaseFixturesDir, copiedFixtureDir, { recursive: true });
    const invalidReplacementAuditPath = join(copiedFixtureDir, "replacement-patch-audit.json");
    const invalidReplacementAudit = JSON.parse(await readFile(invalidReplacementAuditPath, "utf8"));
    delete invalidReplacementAudit.checks;
    await writeFile(invalidReplacementAuditPath, `${JSON.stringify(invalidReplacementAudit, null, 2)}\n`);

    const invalidFixtureCheck = await runShell(`npm --prefix jury run fixtures:package-release:check -- --fixture-dir ${shellQuote(copiedFixtureDir)}`);
    assert.equal(invalidFixtureCheck.exitCode, 1);
    assert.match(invalidFixtureCheck.stderr, /replacement-patch-audit\.json\.checks is required/);

    await rm(copiedFixtureDir, { recursive: true, force: true });
    await cp(ciPackageReleaseFixturesDir, copiedFixtureDir, { recursive: true });
    const invalidRollbackAuditPath = join(copiedFixtureDir, "rollback-audit.json");
    const invalidRollbackAudit = JSON.parse(await readFile(invalidRollbackAuditPath, "utf8"));
    invalidRollbackAudit.retention.artifacts = invalidRollbackAudit.retention.artifacts.filter((artifact) => artifact !== "jury-package-release-evidence");
    await writeFile(invalidRollbackAuditPath, `${JSON.stringify(invalidRollbackAudit, null, 2)}\n`);

    const invalidRetentionCheck = await runShell(`npm --prefix jury run fixtures:package-release:check -- --fixture-dir ${shellQuote(copiedFixtureDir)}`);
    assert.equal(invalidRetentionCheck.exitCode, 1);
    assert.match(invalidRetentionCheck.stderr, /rollback retention must include jury-package-release-evidence/);

    await rm(copiedFixtureDir, { recursive: true, force: true });
    await cp(ciPackageReleaseFixturesDir, copiedFixtureDir, { recursive: true });
    const malformedRollbackAuditPath = join(copiedFixtureDir, "rollback-audit.json");
    const malformedRollbackAudit = JSON.parse(await readFile(malformedRollbackAuditPath, "utf8"));
    delete malformedRollbackAudit.retention.artifacts;
    await writeFile(malformedRollbackAuditPath, `${JSON.stringify(malformedRollbackAudit, null, 2)}\n`);
    const manifestPath = join(invalidDir, "retained-package-release-evidence-manifest.json");
    await writeFile(manifestPath, JSON.stringify({ schema_version: "jury.package_release_archive_manifest.v1" }));

    const malformedManifestVerify = await runShell(`npm --prefix jury run fixtures:package-release:check -- --fixture-dir ${shellQuote(copiedFixtureDir)} --verify-manifest ${shellQuote(manifestPath)}`);
    assert.equal(malformedManifestVerify.exitCode, 1);
    assert.match(malformedManifestVerify.stderr, /rollback-audit\.json\.retention\.artifacts is required/);
    assert.match(malformedManifestVerify.stderr, /retained package release archive manifest could not be built/);
    assert.doesNotMatch(malformedManifestVerify.stderr, /TypeError/);

    await rm(copiedFixtureDir, { recursive: true, force: true });
    await cp(ciPackageReleaseFixturesDir, copiedFixtureDir, { recursive: true });
    const invalidStorageAuditPath = join(copiedFixtureDir, "replacement-patch-audit.json");
    const invalidStorageAudit = JSON.parse(await readFile(invalidStorageAuditPath, "utf8"));
    invalidStorageAudit.retention.storage = "temporary CI artifact";
    await writeFile(invalidStorageAuditPath, `${JSON.stringify(invalidStorageAudit, null, 2)}\n`);

    const invalidStorageCheck = await runShell(`npm --prefix jury run fixtures:package-release:check -- --fixture-dir ${shellQuote(copiedFixtureDir)}`);
    assert.equal(invalidStorageCheck.exitCode, 1);
    assert.match(invalidStorageCheck.stderr, /replacement-patch-audit\.json\.retention\.storage must equal release record or incident archive/);
    assert.match(invalidStorageCheck.stderr, /replacement retention storage must be release record or incident archive/);

    await rm(copiedFixtureDir, { recursive: true, force: true });
    await cp(ciPackageReleaseFixturesDir, copiedFixtureDir, { recursive: true });
    const invalidProvenanceAuditPath = join(copiedFixtureDir, "replacement-patch-audit.json");
    const invalidProvenanceAudit = JSON.parse(await readFile(invalidProvenanceAuditPath, "utf8"));
    const evidenceArtifact = invalidProvenanceAudit.retention.provenance.artifacts.find((artifact) => artifact.name === "jury-package-release-evidence");
    evidenceArtifact.files = evidenceArtifact.files.filter((file) => file !== "replacement-downstream-gate.json");
    await writeFile(invalidProvenanceAuditPath, `${JSON.stringify(invalidProvenanceAudit, null, 2)}\n`);

    const invalidProvenanceCheck = await runShell(`npm --prefix jury run fixtures:package-release:check -- --fixture-dir ${shellQuote(copiedFixtureDir)}`);
    assert.equal(invalidProvenanceCheck.exitCode, 1);
    assert.match(invalidProvenanceCheck.stderr, /replacement retention provenance jury-package-release-evidence must include replacement-downstream-gate\.json/);

    await rm(copiedFixtureDir, { recursive: true, force: true });
    await cp(ciPackageReleaseFixturesDir, copiedFixtureDir, { recursive: true });
    const mismatchedProvenanceAuditPath = join(copiedFixtureDir, "replacement-patch-audit.json");
    const mismatchedProvenanceAudit = JSON.parse(await readFile(mismatchedProvenanceAuditPath, "utf8"));
    mismatchedProvenanceAudit.retention.provenance.runId = "different-release-run";
    mismatchedProvenanceAudit.retention.provenance.sourceRevision = "different-release-revision";
    await writeFile(mismatchedProvenanceAuditPath, `${JSON.stringify(mismatchedProvenanceAudit, null, 2)}\n`);

    const mismatchedProvenanceCheck = await runShell(`npm --prefix jury run fixtures:package-release:check -- --fixture-dir ${shellQuote(copiedFixtureDir)}`);
    assert.equal(mismatchedProvenanceCheck.exitCode, 1);
    assert.match(mismatchedProvenanceCheck.stderr, /rollback and replacement retention provenance runId must match/);
    assert.match(mismatchedProvenanceCheck.stderr, /rollback and replacement retention provenance sourceRevision must match/);

    await rm(copiedFixtureDir, { recursive: true, force: true });
    await cp(ciPackageReleaseFixturesDir, copiedFixtureDir, { recursive: true });
    const driftedRollbackAuditPath = join(copiedFixtureDir, "rollback-audit.json");
    const driftedReplacementAuditPath = join(copiedFixtureDir, "replacement-patch-audit.json");
    const driftedRollbackAudit = JSON.parse(await readFile(driftedRollbackAuditPath, "utf8"));
    const driftedReplacementAudit = JSON.parse(await readFile(driftedReplacementAuditPath, "utf8"));
    driftedRollbackAudit.retention.provenance.sourceRevision = "different-release-revision";
    driftedReplacementAudit.retention.provenance.sourceRevision = "different-release-revision";
    await writeFile(driftedRollbackAuditPath, `${JSON.stringify(driftedRollbackAudit, null, 2)}\n`);
    await writeFile(driftedReplacementAuditPath, `${JSON.stringify(driftedReplacementAudit, null, 2)}\n`);

    const archiveDriftCheck = await runShell(`npm --prefix jury run fixtures:package-release:check -- --fixture-dir ${shellQuote(copiedFixtureDir)} --check-archive-drift`);
    assert.equal(archiveDriftCheck.exitCode, 1);
    assert.match(archiveDriftCheck.stderr, /retained-package-release-evidence-manifest\.json archive drift detected against retained package release evidence/);
    assert.match(archiveDriftCheck.stderr, /retained-package-release-evidence-manifest\.json\.provenance\.sourceRevision must match retained evidence provenance/);

    await rm(copiedFixtureDir, { recursive: true, force: true });
    await cp(ciPackageReleaseFixturesDir, copiedFixtureDir, { recursive: true });
    const driftedFailedGatePath = join(copiedFixtureDir, "downstream-failure-gate.json");
    const driftedFailedGate = JSON.parse(await readFile(driftedFailedGatePath, "utf8"));
    driftedFailedGate.reason = "failed downstream gate changed after archive";
    await writeFile(driftedFailedGatePath, `${JSON.stringify(driftedFailedGate, null, 2)}\n`);

    const failedGateDriftCheck = await runShell(`npm --prefix jury run fixtures:package-release:check -- --fixture-dir ${shellQuote(copiedFixtureDir)} --check-archive-drift`);
    assert.equal(failedGateDriftCheck.exitCode, 1);
    assert.match(failedGateDriftCheck.stderr, /retained-package-release-evidence-manifest\.json archive drift detected against retained package release evidence/);
    assert.match(failedGateDriftCheck.stderr, /retained-package-release-evidence-manifest\.json\.archiveEvidence downstream-failure-gate\.json sha256 must match retained evidence/);

    await rm(copiedFixtureDir, { recursive: true, force: true });
    await cp(ciPackageReleaseFixturesDir, copiedFixtureDir, { recursive: true });
    const driftedReplacementGatePath = join(copiedFixtureDir, "replacement-downstream-gate.json");
    const driftedReplacementGate = JSON.parse(await readFile(driftedReplacementGatePath, "utf8"));
    driftedReplacementGate.reason = "replacement downstream gate changed after archive";
    await writeFile(driftedReplacementGatePath, `${JSON.stringify(driftedReplacementGate, null, 2)}\n`);

    const replacementGateDriftCheck = await runShell(`npm --prefix jury run fixtures:package-release:check -- --fixture-dir ${shellQuote(copiedFixtureDir)} --check-archive-drift`);
    assert.equal(replacementGateDriftCheck.exitCode, 1);
    assert.match(replacementGateDriftCheck.stderr, /retained-package-release-evidence-manifest\.json archive drift detected against retained package release evidence/);
    assert.match(replacementGateDriftCheck.stderr, /retained-package-release-evidence-manifest\.json\.archiveEvidence replacement-downstream-gate\.json sha256 must match retained evidence/);

    await rm(copiedFixtureDir, { recursive: true, force: true });
    await cp(ciPackageReleaseFixturesDir, copiedFixtureDir, { recursive: true });
    const invalidRemediationAuditPath = join(copiedFixtureDir, "archive-drift-remediation-audit.json");
    const invalidRemediationAudit = JSON.parse(await readFile(invalidRemediationAuditPath, "utf8"));
    invalidRemediationAudit.drift.evidence.find((item) => item.path === "downstream-failure-gate.json").archive = "replacement-patch";
    invalidRemediationAudit.drift.evidence = invalidRemediationAudit.drift.evidence.filter((item) => item.path !== "replacement-downstream-gate.json");
    invalidRemediationAudit.remediation.restoredEvidence.find((item) => item.path === "replacement-downstream-gate.json").archive = "failed-publication";
    invalidRemediationAudit.remediation.diffReviewed = false;
    await writeFile(invalidRemediationAuditPath, `${JSON.stringify(invalidRemediationAudit, null, 2)}\n`);

    const invalidRemediationCheck = await runShell(`npm --prefix jury run fixtures:package-release:check -- --fixture-dir ${shellQuote(copiedFixtureDir)}`);
    assert.equal(invalidRemediationCheck.exitCode, 1);
    assert.match(invalidRemediationCheck.stderr, /archive drift remediation audit must include failed publication downstream gate drift/);
    assert.match(invalidRemediationCheck.stderr, /archive drift remediation audit must include replacement downstream gate drift/);
    assert.match(invalidRemediationCheck.stderr, /archive drift remediation audit must restore replacement downstream gate evidence/);
    assert.match(invalidRemediationCheck.stderr, /archive drift remediation diffReviewed must be true/);

    await rm(copiedFixtureDir, { recursive: true, force: true });
    await cp(ciPackageReleaseFixturesDir, copiedFixtureDir, { recursive: true });
    const invalidRemediationHandoffPath = join(copiedFixtureDir, "archive-drift-remediation-audit-handoff.json");
    const invalidRemediationHandoff = JSON.parse(await readFile(invalidRemediationHandoffPath, "utf8"));
    invalidRemediationHandoff.schema_version = "jury.package_release_remediation_audit_handoff.invalid";
    invalidRemediationHandoff.replacementPackageVersion = "0.1.2";
    invalidRemediationHandoff.driftEvidence = ["downstream-failure-gate.json"];
    invalidRemediationHandoff.retainedWith = invalidRemediationHandoff.retainedWith.filter((item) => item !== "archive-drift-remediation-audit.json");
    invalidRemediationHandoff.retainedWith.push("missing-retained-file.json");
    invalidRemediationHandoff.runId = "different-release-run";
    invalidRemediationHandoff.sourceRevision = "different-source-revision";
    invalidRemediationHandoff.reviewedBy = "different-maintainer@example.com";
    invalidRemediationHandoff.approvedAt = "not-a-date";
    delete invalidRemediationHandoff.sourceAudit;
    await writeFile(invalidRemediationHandoffPath, `${JSON.stringify(invalidRemediationHandoff, null, 2)}\n`);

    const invalidRemediationHandoffCheck = await runShell(`npm --prefix jury run fixtures:package-release:check -- --fixture-dir ${shellQuote(copiedFixtureDir)}`);
    assert.equal(invalidRemediationHandoffCheck.exitCode, 1);
    assert.match(invalidRemediationHandoffCheck.stderr, /archive-drift-remediation-audit-handoff\.json\.sourceAudit is required/);
    assert.match(invalidRemediationHandoffCheck.stderr, /archive-drift-remediation-audit-handoff\.json\.schema_version must equal jury\.package_release_remediation_audit_handoff\.v1/);
    assert.match(invalidRemediationHandoffCheck.stderr, /archive-drift-remediation-audit-handoff\.json\.driftEvidence must contain an item matching required archive evidence/);
    assert.match(invalidRemediationHandoffCheck.stderr, /archive-drift-remediation-audit-handoff\.json\.approvedAt must match/);
    assert.match(invalidRemediationHandoffCheck.stderr, /archive drift remediation audit handoff retainedWith must include archive-drift-remediation-audit\.json/);
    assert.match(invalidRemediationHandoffCheck.stderr, /archive drift remediation audit handoff retainedWith missing-retained-file\.json is not retained package release evidence/);
    assert.match(invalidRemediationHandoffCheck.stderr, /archive drift remediation audit handoff replacementPackageVersion must match replacement audit/);
    assert.match(invalidRemediationHandoffCheck.stderr, /archive drift remediation audit handoff driftEvidence must match remediation audit drift evidence/);
    assert.match(invalidRemediationHandoffCheck.stderr, /archive drift remediation audit handoff runId must match retained artifact provenance/);
    assert.match(invalidRemediationHandoffCheck.stderr, /archive drift remediation audit handoff sourceRevision must match retained artifact provenance/);
    assert.match(invalidRemediationHandoffCheck.stderr, /archive drift remediation audit handoff reviewedBy must match remediation approver/);
    assert.match(invalidRemediationHandoffCheck.stderr, /archive drift remediation audit handoff approvedAt must match remediation approval time/);

    await rm(copiedFixtureDir, { recursive: true, force: true });
    await cp(ciPackageReleaseFixturesDir, copiedFixtureDir, { recursive: true });
    const invalidReplayDiagnosticsPath = join(copiedFixtureDir, "jury-package-release-replay-summary-diagnostics.json");
    const invalidReplayDiagnostics = JSON.parse(await readFile(invalidReplayDiagnosticsPath, "utf8"));
    invalidReplayDiagnostics.schema_version = "jury.package_release_replay_summary_diagnostics.invalid";
    invalidReplayDiagnostics.replacementPackageVersion = "0.1.2";
    invalidReplayDiagnostics.failedArchiveEvidence = ["rollback-audit.json"];
    invalidReplayDiagnostics.checkedLines = invalidReplayDiagnostics.checkedLines.filter((line) => !line.includes("replacementPackageVersion"));
    await writeFile(invalidReplayDiagnosticsPath, `${JSON.stringify(invalidReplayDiagnostics, null, 2)}\n`);

    const invalidReplayDiagnosticsCheck = await runShell(`npm --prefix jury run fixtures:package-release:check -- --fixture-dir ${shellQuote(copiedFixtureDir)}`);
    assert.equal(invalidReplayDiagnosticsCheck.exitCode, 1);
    assert.match(invalidReplayDiagnosticsCheck.stderr, /jury-package-release-replay-summary-diagnostics\.json\.schema_version must equal jury\.package_release_replay_summary_diagnostics\.v1/);
    assert.match(invalidReplayDiagnosticsCheck.stderr, /replay summary diagnostics replacementPackageVersion must match replacement audit/);
    assert.match(invalidReplayDiagnosticsCheck.stderr, /replay summary diagnostics failedArchiveEvidence must match remediation audit/);
    assert.match(invalidReplayDiagnosticsCheck.stderr, /replay summary diagnostics checkedLines must include - replacementPackageVersion: 0\.1\.1/);

    await rm(copiedFixtureDir, { recursive: true, force: true });
    await cp(ciPackageReleaseFixturesDir, copiedFixtureDir, { recursive: true });
    const invalidDiagnosticsRetentionHandoffPath = join(copiedFixtureDir, "jury-package-release-replay-summary-diagnostics-retention-handoff.json");
    const invalidDiagnosticsRetentionHandoff = JSON.parse(await readFile(invalidDiagnosticsRetentionHandoffPath, "utf8"));
    invalidDiagnosticsRetentionHandoff.schema_version = "jury.package_release_replay_summary_diagnostics_retention_handoff.invalid";
    invalidDiagnosticsRetentionHandoff.replacementPackageVersion = "0.1.2";
    invalidDiagnosticsRetentionHandoff.runId = "different-release-run";
    invalidDiagnosticsRetentionHandoff.reviewedBy = "different-maintainer@example.com";
    delete invalidDiagnosticsRetentionHandoff.retainedDiagnostics;
    await writeFile(invalidDiagnosticsRetentionHandoffPath, `${JSON.stringify(invalidDiagnosticsRetentionHandoff, null, 2)}\n`);

    const invalidDiagnosticsRetentionHandoffCheck = await runShell(`npm --prefix jury run fixtures:package-release:check -- --fixture-dir ${shellQuote(copiedFixtureDir)}`);
    assert.equal(invalidDiagnosticsRetentionHandoffCheck.exitCode, 1);
    assert.match(invalidDiagnosticsRetentionHandoffCheck.stderr, /jury-package-release-replay-summary-diagnostics-retention-handoff\.json\.retainedDiagnostics is required/);
    assert.match(invalidDiagnosticsRetentionHandoffCheck.stderr, /jury-package-release-replay-summary-diagnostics-retention-handoff\.json\.schema_version must equal jury\.package_release_replay_summary_diagnostics_retention_handoff\.v1/);
    assert.match(invalidDiagnosticsRetentionHandoffCheck.stderr, /replay summary diagnostics retention handoff replacementPackageVersion must match replacement audit/);
    assert.match(invalidDiagnosticsRetentionHandoffCheck.stderr, /replay summary diagnostics retention handoff runId must match retained artifact provenance/);
    assert.match(invalidDiagnosticsRetentionHandoffCheck.stderr, /replay summary diagnostics retention handoff reviewedBy must match remediation approver/);

    await rm(copiedFixtureDir, { recursive: true, force: true });
    await cp(ciPackageReleaseFixturesDir, copiedFixtureDir, { recursive: true });
    const invalidExpiryHandoffPath = join(copiedFixtureDir, "jury-package-release-replay-summary-expiry-handoff.json");
    const invalidExpiryHandoff = JSON.parse(await readFile(invalidExpiryHandoffPath, "utf8"));
    invalidExpiryHandoff.schema_version = "jury.package_release_replay_summary_expiry_handoff.invalid";
    invalidExpiryHandoff.reason = "temporary artifact was not promoted";
    invalidExpiryHandoff.expiredAfterDays = 30;
    invalidExpiryHandoff.extraDebugField = true;
    delete invalidExpiryHandoff.reviewedBy;
    await writeFile(invalidExpiryHandoffPath, `${JSON.stringify(invalidExpiryHandoff, null, 2)}\n`);

    const invalidExpiryHandoffCheck = await runShell(`npm --prefix jury run fixtures:package-release:check -- --fixture-dir ${shellQuote(copiedFixtureDir)}`);
    assert.equal(invalidExpiryHandoffCheck.exitCode, 1);
    assert.match(invalidExpiryHandoffCheck.stderr, /jury-package-release-replay-summary-expiry-handoff\.json\.reviewedBy is required/);
    assert.match(invalidExpiryHandoffCheck.stderr, /jury-package-release-replay-summary-expiry-handoff\.json\.schema_version must equal jury\.package_release_replay_summary_expiry_handoff\.v1/);
    assert.match(invalidExpiryHandoffCheck.stderr, /jury-package-release-replay-summary-expiry-handoff\.json\.reason must equal jury-package-release-replay-summary artifact expired before promotion/);
    assert.match(invalidExpiryHandoffCheck.stderr, /jury-package-release-replay-summary-expiry-handoff\.json\.expiredAfterDays must equal 90/);
    assert.match(invalidExpiryHandoffCheck.stderr, /jury-package-release-replay-summary-expiry-handoff\.json\.extraDebugField is not allowed/);

    await rm(copiedFixtureDir, { recursive: true, force: true });
    await cp(ciPackageReleaseFixturesDir, copiedFixtureDir, { recursive: true });
    for (const auditName of ["rollback-audit.json", "replacement-patch-audit.json"]) {
      const auditPath = join(copiedFixtureDir, auditName);
      const audit = JSON.parse(await readFile(auditPath, "utf8"));
      audit.retention.artifacts = audit.retention.artifacts.filter((artifact) => artifact !== "jury-package-release-replay-summary-expiry-handoff.json");
      await writeFile(auditPath, `${JSON.stringify(audit, null, 2)}\n`);
    }
    const missingExpiryHandoffRetentionCheck = await runShell(`npm --prefix jury run fixtures:package-release:check -- --fixture-dir ${shellQuote(copiedFixtureDir)}`);
    assert.equal(missingExpiryHandoffRetentionCheck.exitCode, 1);
    assert.match(missingExpiryHandoffRetentionCheck.stderr, /rollback retention must include jury-package-release-replay-summary-expiry-handoff\.json/);
    assert.match(missingExpiryHandoffRetentionCheck.stderr, /replacement retention must include jury-package-release-replay-summary-expiry-handoff\.json/);
  } finally {
    await rm(invalidDir, { recursive: true, force: true });
  }
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
  const ciReadme = await readFile(join(repoRoot, "jury/examples/ci/README.md"), "utf8");
  const checklist = await readFile(join(repoRoot, "jury/RELEASE_CHECKLIST.md"), "utf8");
  const publishing = await readFile(join(repoRoot, "jury/PUBLISHING.md"), "utf8");

  for (const field of ["ok", "decision", "reason", "missing_fields", "unresolved_objections", "next_actions"]) {
    assert.ok(guide.includes(`\`${field}\``), `TROUBLESHOOTING.md should describe gate.${field}`);
  }

  for (const field of ["claim_id", "producer", "provenance", "attestation", "records.claims", "records.checks", "records.evidence", "records.objections", "records.verdicts"]) {
    assert.ok(guide.includes(`\`${field}\``), `TROUBLESHOOTING.md should describe bundle.${field}`);
  }

  assert.ok(readme.includes("TROUBLESHOOTING.md"));
  assert.ok(checklist.includes("TROUBLESHOOTING.md"));
  assert.ok(checklist.includes("package manifest failure"));
  assert.ok(publishing.includes("TROUBLESHOOTING.md"));
  assert.ok(guide.includes("jury-key-policy.untrusted-producer.json"));
  assert.ok(guide.includes("key policy has no trusted producer"));
  assert.ok(guide.includes("Dry-Run Publication Artifact Failure"));
  assert.ok(guide.includes("stale or mismatched dry-run publication artifact"));
  assert.ok(guide.includes("jury-package-dry-run"));
  assert.ok(guide.includes("jury-pack-dry-run.json"));
  assert.ok(guide.includes("jury-pack-dry-run-record.json"));
  assert.ok(guide.includes("packageVersion did not match"));
  assert.ok(guide.includes("tarballName did not match"));
  assert.ok(guide.includes("NODE_AUTH_TOKEN"));
  assert.ok(guide.includes("Published Package Verification Failure"));
  assert.ok(guide.includes("published package fails downstream verification"));
  assert.ok(guide.includes("Treat the version as immutable"));
  assert.ok(guide.includes("npm view @sanogueralorenzo/jury@<packageVersion> version dist.tarball --json"));
  assert.ok(guide.includes("npm deprecate @sanogueralorenzo/jury@<packageVersion>"));
  assert.ok(guide.includes("Do not rerun `npm publish` for the same `packageVersion`"));
  assert.ok(guide.includes("publish a new patch version"));
  assert.ok(guide.includes("replacement patch evidence"));
  assert.ok(guide.includes("replacement `packageVersion`"));
  assert.ok(guide.includes("replacement `dist.tarball`"));
  assert.ok(guide.includes("downstream verification pass for the replacement"));
  assert.ok(guide.includes("failed-version deprecation result"));
  assert.ok(guide.includes("Package Manifest Failure"));
  assert.ok(guide.includes("npm --prefix jury run package:manifest:check"));
  assert.ok(guide.includes("--pack-manifest npm-pack.json"));
  assert.ok(guide.includes("checked_paths"));
  assert.ok(guide.includes("missing"));
  assert.ok(guide.includes("examples/ci/jury-trusted-bundle-verify.yml"));
  assert.ok(guide.includes("examples/ci/fixtures/key-policy"));
  assert.ok(guide.includes("Package Release Evidence Replay Failure"));
  assert.ok(guide.includes("package-release-evidence-replay"));
  assert.ok(guide.includes("jury-package-release-evidence"));
  assert.ok(guide.includes("JURY_PACKAGE_RELEASE_EVIDENCE_DIR"));
  assert.ok(guide.includes("--fixture-dir <downloaded-artifact-dir>"));
  assert.ok(guide.includes("missing package release evidence files"));
  assert.ok(guide.includes("archive drift remediation audit files"));
  assert.ok(guide.includes("replacement-patch-audit.json.checks is required"));
  assert.ok(guide.includes("archive-drift-remediation-audit-handoff.json` with `jury-pack-dry-run-record.json"));
  assert.ok(guide.includes("dry-run-publication"));
  assert.ok(guide.includes("Retained Package Release Manifest Replay Failure"));
  assert.ok(guide.includes("retained package release manifest replay failed"));
  assert.ok(guide.includes("Retained Package Release Archive Drift Remediation"));
  assert.ok(guide.includes("retained package release archive drift check failed"));
  assert.ok(guide.includes("fixtures:package-release:drift"));
  assert.ok(guide.includes("--verify-manifest <retained-manifest>"));
  assert.ok(guide.includes("retained-package-release-evidence-manifest.json"));
  assert.ok(guide.includes("archive drift detected against retained package release evidence"));
  assert.ok(guide.includes("archiveEvidence"));
  assert.ok(guide.includes("SHA-256 mismatch"));
  assert.ok(guide.includes("Treat drift as a release-record incident"));
  assert.ok(guide.includes("remediate the failed publication archive evidence first"));
  assert.ok(guide.includes("remediate the replacement patch archive evidence first"));
  assert.ok(guide.includes("dry-run identity helper"));
  assert.ok(guide.includes("packageVersion` and `tarballName` across `jury-pack-dry-run-record.json`"));
  assert.ok(guide.includes("record the remediation in `archive-drift-remediation-audit.json`"));
  assert.ok(guide.includes("Remediation Audit Replay Failure"));
  assert.ok(guide.includes("Remediation Audit Handoff Schema Failure"));
  assert.ok(guide.includes("archive drift remediation audit must record approving maintainer"));
  assert.ok(guide.includes("archive drift remediation audit must verify the retained manifest"));
  assert.ok(guide.includes("archive drift remediation audit missing verification commands"));
  assert.ok(guide.includes("archive drift remediation audit handoff schema failure"));
  assert.ok(guide.includes("jury.package_release_remediation_audit_handoff.v1"));
  assert.ok(guide.includes("retainedWith missing archive-drift-remediation-audit.json"));
  assert.ok(guide.includes("Remediation Audit Handoff CI Workflow Enforcement Failure"));
  assert.ok(guide.includes("Replay Jury package release remediation audit handoff"));
  assert.ok(guide.includes("Replay Jury package release remediation audit handoff step is missing"));
  assert.ok(guide.includes("remediation audit handoff CI workflow enforcement failed"));
  assert.ok(guide.includes("Replay Artifact Summary Failure"));
  assert.ok(guide.includes("Replay Summary CI Workflow Diagnostics Failure"));
  assert.ok(guide.includes("Replay Summary Diagnostics Retention Handoff Failure"));
  assert.ok(guide.includes("Replay Summary Diagnostics Retention Handoff CI Replay Enforcement Failure"));
  assert.ok(guide.includes("Replay Jury package release replay diagnostics retention handoff step is missing"));
  assert.ok(guide.includes("Replay Summary Diagnostics Retention Handoff Schema Failure"));
  assert.ok(guide.includes("Replay Summary Retention Failure"));
  assert.ok(guide.includes("Replay Summary Artifact Expiry Remediation Handoff"));
  assert.ok(guide.includes("Replay Summary Expiry Handoff Schema Failure"));
  assert.ok(guide.includes("Replay Summary Expiry Handoff CI Workflow Enforcement Failure"));
  assert.ok(guide.includes("Replay Jury package release replay summary expiry handoff"));
  assert.ok(guide.includes("replay summary expiry handoff CI workflow enforcement failed"));
  assert.ok(guide.includes("missing replay summary lines"));
  assert.ok(guide.includes("replay summary retention incomplete"));
  assert.ok(guide.includes("jury.package_release_replay_summary_expiry_handoff.v1"));
  assert.ok(guide.includes("jury.package_release_replay_summary_diagnostics_retention_handoff.v1"));
  assert.ok(guide.includes("failed package identity, replacement package identity, retained archive evidence lists, and remediation approver"));
  assert.ok(guide.includes("diagnosticsSchemaVersion must match diagnostics schema_version"));
  assert.ok(guide.includes("diagnostics retention handoff replay must run after handoff generation"));
  assert.ok(guide.includes("schema_version must equal jury.package_release_archive_manifest.v1"));
  assert.ok(guide.includes("must contain an item matching required archive evidence"));
  assert.ok(guide.includes("missing retained archive evidence"));
  assert.ok(guide.includes("replacement-patch-audit.json is required in package release evidence directory"));
  assert.ok(guide.includes("missing retained package release evidence files"));
  assert.ok(guide.includes("is required for retained package release manifest verification"));
  assert.ok(ciReadme.includes("JURY_PACKAGE_RELEASE_EVIDENCE_DIR"));
  assert.ok(checklist.includes("If package release evidence replay fails"));
  assert.ok(checklist.includes("If retained package release manifest replay fails"));
  assert.ok(publishing.includes("package release evidence replay failure"));
  assert.ok(publishing.includes("retained package release manifest replay failure"));

  const manifestCommands = extractShellBlock(guide, "Package Manifest Failure");
  assert.deepEqual(manifestCommands, ["npm --prefix jury run package:manifest:check"]);
  const manifestCheck = await runShell(manifestCommands[0]);
  assert.equal(manifestCheck.exitCode, 0, manifestCheck.stderr);
  assert.equal(JSON.parse(manifestCheck.stdout.slice(manifestCheck.stdout.indexOf("{"))).ok, true);

  const evidenceReplayCommands = extractShellBlock(guide, "Package Release Evidence Replay Failure");
  assert.deepEqual(evidenceReplayCommands, [
    "npm --prefix jury run fixtures:package-release:check -- --fixture-dir <downloaded-artifact-dir>",
    'node -e \'const fs=require("node:fs"); const dir=process.argv[1]; const required=["README.md","jury-pack-dry-run-record.json","failed-npm-view.json","downstream-failure-gate.json","rollback-audit.json","replacement-npm-view.json","replacement-downstream-gate.json","replacement-patch-audit.json","archive-drift-remediation-audit.json","archive-drift-remediation-audit-handoff.json","jury-package-release-replay-summary.md","jury-package-release-replay-summary-diagnostics.json","jury-package-release-replay-summary-diagnostics-retention-handoff.json","jury-package-release-replay-summary-expiry-handoff.json"]; const missing=required.filter((file)=>!fs.existsSync(`${dir}/${file}`)); if (missing.length) throw new Error(`missing package release evidence files: ${missing.join(", ")}`); console.log(JSON.stringify({ok:true, artifact:"jury-package-release-evidence", files: required}, null, 2));\' <downloaded-artifact-dir>',
  ]);
  const replayRoot = await tempState();
  const replayDir = join(replayRoot, "package-release-evidence");
  try {
    await cp(ciPackageReleaseFixturesDir, replayDir, { recursive: true });

    const replayCheck = await runShell(evidenceReplayCommands[0].replace("<downloaded-artifact-dir>", shellQuote(replayDir)));
    assert.equal(replayCheck.exitCode, 0, replayCheck.stderr);
    assert.equal(JSON.parse(replayCheck.stdout.slice(replayCheck.stdout.indexOf("{"))).ok, true);

    const fileCheck = await runShell(evidenceReplayCommands[1].replace("<downloaded-artifact-dir>", shellQuote(replayDir)));
    assert.equal(fileCheck.exitCode, 0, fileCheck.stderr);
    assert.equal(JSON.parse(fileCheck.stdout).artifact, "jury-package-release-evidence");

    await rm(join(replayDir, "replacement-patch-audit.json"));
    const missingFileCheck = await runShell(evidenceReplayCommands[1].replace("<downloaded-artifact-dir>", shellQuote(replayDir)));
    assert.equal(missingFileCheck.exitCode, 1);
    assert.match(missingFileCheck.stderr, /missing package release evidence files: replacement-patch-audit\.json/);
  } finally {
    await rm(replayRoot, { recursive: true, force: true });
  }

  const retainedManifestCommands = extractShellBlock(guide, "Retained Package Release Manifest Replay Failure");
  assert.deepEqual(retainedManifestCommands, [
    "npm --prefix jury run fixtures:package-release:check -- --fixture-dir <retained-evidence-dir> --verify-manifest <retained-manifest>",
    "npm --prefix jury run fixtures:package-release:drift",
    'node -e \'const fs=require("node:fs"); const dir=process.argv[1]; const required=["README.md","jury-pack-dry-run-record.json","failed-npm-view.json","downstream-failure-gate.json","rollback-audit.json","replacement-npm-view.json","replacement-downstream-gate.json","replacement-patch-audit.json","archive-drift-remediation-audit.json","archive-drift-remediation-audit-handoff.json","jury-package-release-replay-summary.md","jury-package-release-replay-summary-diagnostics.json","jury-package-release-replay-summary-diagnostics-retention-handoff.json","jury-package-release-replay-summary-expiry-handoff.json"]; const missing=required.filter((file)=>!fs.existsSync(`${dir}/${file}`)); if (missing.length) throw new Error(`missing retained package release evidence files: ${missing.join(", ")}`); console.log(JSON.stringify({ok:true, artifact:"retained-package-release-evidence", files: required}, null, 2));\' <retained-evidence-dir>',
    'node -e \'const fs=require("node:fs"); const manifest=JSON.parse(fs.readFileSync(process.argv[1],"utf8")); const summary={schema_version:manifest.schema_version,failedPackageVersion:manifest.failed?.packageVersion,replacementPackageVersion:manifest.replacement?.packageVersion,retentionArtifacts:manifest.retention?.artifacts,provenanceArtifacts:(manifest.provenance?.artifacts??[]).map((artifact)=>artifact.name)}; console.log(JSON.stringify(summary,null,2));\' <retained-manifest>',
    'node -e \'const fs=require("node:fs"); const manifest=JSON.parse(fs.readFileSync(process.argv[1],"utf8")); const required=["jury-package-dry-run","jury-package-release-evidence","jury-package-release-replay-summary","rollback-audit.json","replacement-patch-audit.json","archive-drift-remediation-audit.json","archive-drift-remediation-audit-handoff.json","jury-package-release-replay-summary-diagnostics.json","jury-package-release-replay-summary-diagnostics-retention-handoff.json","jury-package-release-replay-summary-expiry-handoff.json"]; const missing=required.filter((artifact)=>!manifest.retention?.artifacts?.includes(artifact)); const provenanceMissing=["jury-package-dry-run","jury-package-release-evidence","jury-package-release-replay-summary"].filter((name)=>!(manifest.provenance?.artifacts??[]).some((artifact)=>artifact.name===name)); if (missing.length || provenanceMissing.length) throw new Error(`missing retained archive evidence: retention=${missing.join(", ") || "none"} provenance=${provenanceMissing.join(", ") || "none"}`); console.log(JSON.stringify({ok:true, retentionArtifacts: required, provenanceArtifacts:["jury-package-dry-run","jury-package-release-evidence","jury-package-release-replay-summary"]}, null, 2));\' <retained-manifest>',
  ]);
  const manifestReplayRoot = await tempState();
  const retainedEvidenceDir = join(manifestReplayRoot, "retained-evidence");
  const retainedManifestPath = join(manifestReplayRoot, "retained-package-release-evidence-manifest.json");
  try {
    await cp(ciPackageReleaseFixturesDir, retainedEvidenceDir, { recursive: true });
    const exportManifest = await runShell(`npm --prefix jury run fixtures:package-release:check -- --fixture-dir ${shellQuote(retainedEvidenceDir)} --manifest-out ${shellQuote(retainedManifestPath)}`);
    assert.equal(exportManifest.exitCode, 0, exportManifest.stderr);
    const retainedCommand = (command) => command
      .replaceAll("<retained-evidence-dir>", shellQuote(retainedEvidenceDir))
      .replaceAll("<retained-manifest>", shellQuote(retainedManifestPath));

    const manifestReplay = await runShell(retainedCommand(retainedManifestCommands[0]));
    assert.equal(manifestReplay.exitCode, 0, manifestReplay.stderr);
    const manifestDriftCheck = await runShell(retainedManifestCommands[1]);
    assert.equal(manifestDriftCheck.exitCode, 0, manifestDriftCheck.stderr);
    const missingManifestReplay = await runShell(retainedManifestCommands[0]
      .replaceAll("<retained-evidence-dir>", shellQuote(retainedEvidenceDir))
      .replaceAll("<retained-manifest>", shellQuote(join(manifestReplayRoot, "missing-retained-manifest.json"))));
    assert.equal(missingManifestReplay.exitCode, 1);
    assert.match(missingManifestReplay.stderr, /missing-retained-manifest\.json is required for retained package release manifest verification/);
    assert.doesNotMatch(missingManifestReplay.stderr, /ENOENT/);
    const retainedFileCheck = await runShell(retainedCommand(retainedManifestCommands[2]));
    assert.equal(retainedFileCheck.exitCode, 0, retainedFileCheck.stderr);
    assert.equal(JSON.parse(retainedFileCheck.stdout).artifact, "retained-package-release-evidence");
    const manifestSummary = await runShell(retainedCommand(retainedManifestCommands[3]));
    assert.equal(manifestSummary.exitCode, 0, manifestSummary.stderr);
    assert.equal(JSON.parse(manifestSummary.stdout).schema_version, "jury.package_release_archive_manifest.v1");
    const retainedArchiveCheck = await runShell(retainedCommand(retainedManifestCommands[4]));
    assert.equal(retainedArchiveCheck.exitCode, 0, retainedArchiveCheck.stderr);
    assert.equal(JSON.parse(retainedArchiveCheck.stdout).ok, true);

    const remediationCommands = extractShellBlock(guide, "Retained Package Release Archive Drift Remediation");
    assert.deepEqual(remediationCommands, [
      "npm --prefix jury run fixtures:package-release:check -- --fixture-dir <retained-evidence-dir> --verify-manifest <retained-manifest>",
      'node -e \'const fs=require("node:fs"); const crypto=require("node:crypto"); const dir=process.argv[1]; const manifest=JSON.parse(fs.readFileSync(process.argv[2],"utf8")); const drift=(manifest.archiveEvidence??[]).filter((item)=>!fs.existsSync(`${dir}/${item.path}`)||`sha256:${crypto.createHash("sha256").update(fs.readFileSync(`${dir}/${item.path}`)).digest("hex")}`!==item.sha256).map((item)=>item.path); console.log(JSON.stringify({ok:drift.length===0, drift}, null, 2)); if (drift.length) process.exit(1);\' <retained-evidence-dir> <retained-manifest>',
      'node -e \'const fs=require("node:fs"); const dir=process.argv[1]; const manifest=JSON.parse(fs.readFileSync(process.argv[2],"utf8")); const record=JSON.parse(fs.readFileSync(`${dir}/jury-pack-dry-run-record.json`,"utf8")); const rollback=JSON.parse(fs.readFileSync(`${dir}/rollback-audit.json`,"utf8")); const replacement=JSON.parse(fs.readFileSync(`${dir}/replacement-patch-audit.json`,"utf8")); const errors=[]; if (record.packageVersion!==manifest.failed?.packageVersion) errors.push("dry-run packageVersion must match retained manifest failed packageVersion"); if (record.tarballName!==manifest.failed?.tarballName) errors.push("dry-run tarballName must match retained manifest failed tarballName"); if (rollback.failed?.packageVersion!==record.packageVersion || replacement.failed?.packageVersion!==record.packageVersion) errors.push("rollback and replacement audits must reference the dry-run packageVersion"); if (rollback.failed?.tarballName!==record.tarballName || replacement.failed?.tarballName!==record.tarballName) errors.push("rollback and replacement audits must reference the dry-run tarballName"); console.log(JSON.stringify({ok:errors.length===0, packageVersion:record.packageVersion, tarballName:record.tarballName, errors}, null, 2)); if (errors.length) process.exit(1);\' <retained-evidence-dir> <retained-manifest>',
      'tmp="$(mktemp -d)" && npm --prefix jury run fixtures:package-release:check -- --fixture-dir <retained-evidence-dir> --manifest-out "$tmp/retained-package-release-evidence-manifest.json" && diff -u <retained-manifest> "$tmp/retained-package-release-evidence-manifest.json"; rc=$?; rm -rf "$tmp"; exit $rc',
    ]);
    for (const command of remediationCommands) {
      const result = await runShell(retainedCommand(command));
      assert.equal(result.exitCode, 0, `${command}\nstdout:\n${result.stdout}\nstderr:\n${result.stderr}`);
    }

    const remediationAuditReplayCommands = extractShellBlock(guide, "Remediation Audit Replay Failure");
    assert.deepEqual(remediationAuditReplayCommands, [
      'node -e \'const fs=require("node:fs"); const audit=JSON.parse(fs.readFileSync(`${process.argv[1]}/archive-drift-remediation-audit.json`,"utf8")); if (!audit.approval?.approvedBy) throw new Error("archive drift remediation audit must record approving maintainer"); console.log(JSON.stringify({ok:true, approvedBy:audit.approval.approvedBy}, null, 2));\' <retained-evidence-dir>',
      'node -e \'const fs=require("node:fs"); const audit=JSON.parse(fs.readFileSync(`${process.argv[1]}/archive-drift-remediation-audit.json`,"utf8")); const commands=audit.verification?.commands??[]; const required=["--verify-manifest","archiveEvidence SHA-256 helper","dry-run identity helper","--manifest-out","fixtures:package-release:drift"]; const missing=required.filter((text)=>!commands.some((command)=>command.includes(text))); if (missing.length) throw new Error(`archive drift remediation audit missing verification commands: ${missing.join(", ")}`); console.log(JSON.stringify({ok:true, commands: required}, null, 2));\' <retained-evidence-dir>',
    ]);
    for (const command of remediationAuditReplayCommands) {
      const result = await runShell(retainedCommand(command));
      assert.equal(result.exitCode, 0, `${command}\nstdout:\n${result.stdout}\nstderr:\n${result.stderr}`);
    }

    const remediationAuditHandoffSchemaCommands = extractShellBlock(guide, "Remediation Audit Handoff Schema Failure");
    assert.deepEqual(remediationAuditHandoffSchemaCommands, [
      "npm --prefix jury run fixtures:package-release:check -- --fixture-dir <retained-evidence-dir>",
      'node -e \'const fs=require("node:fs"); const dir=process.argv[1]; const manifest=JSON.parse(fs.readFileSync(process.argv[2],"utf8")); const audit=JSON.parse(fs.readFileSync(`${dir}/archive-drift-remediation-audit.json`,"utf8")); const handoff=JSON.parse(fs.readFileSync(`${dir}/archive-drift-remediation-audit-handoff.json`,"utf8")); const requiredWith=["archive-drift-remediation-audit.json","rollback-audit.json","replacement-patch-audit.json","retained-package-release-evidence-manifest.json","jury-package-release-replay-summary-diagnostics-retention-handoff.json"]; const drift=(audit.drift?.evidence??[]).map((item)=>item.path); const restored=(audit.remediation?.restoredEvidence??[]).map((item)=>item.path); const commands=audit.verification?.commands??[]; const errors=[]; if (handoff.schema_version!=="jury.package_release_remediation_audit_handoff.v1") errors.push("schema_version must equal jury.package_release_remediation_audit_handoff.v1"); if (handoff.reason!=="archive-drift-remediation-audit retained with failed and replacement release archives") errors.push("reason must explain remediation audit retention with failed and replacement release archives"); if (handoff.sourceAudit!=="archive-drift-remediation-audit.json") errors.push("sourceAudit must be archive-drift-remediation-audit.json"); if (handoff.sourceManifest!=="retained-package-release-evidence-manifest.json") errors.push("sourceManifest must be retained-package-release-evidence-manifest.json"); for (const item of requiredWith) if (!(handoff.retainedWith??[]).includes(item)) errors.push(`retainedWith missing ${item}`); if (handoff.failedPackageVersion!==manifest.failed?.packageVersion) errors.push("failedPackageVersion must match retained manifest failed packageVersion"); if (handoff.failedTarballName!==manifest.failed?.tarballName) errors.push("failedTarballName must match retained manifest failed tarballName"); if (handoff.replacementPackageVersion!==manifest.replacement?.packageVersion) errors.push("replacementPackageVersion must match retained manifest replacement packageVersion"); if (JSON.stringify(handoff.driftEvidence)!==JSON.stringify(drift)) errors.push("driftEvidence must match remediation audit drift evidence"); if (JSON.stringify(handoff.restoredEvidence)!==JSON.stringify(restored)) errors.push("restoredEvidence must match remediation audit restored evidence"); if (JSON.stringify(handoff.verificationCommands)!==JSON.stringify(commands)) errors.push("verificationCommands must match remediation audit verification commands"); if (handoff.manifestRegenerated!==audit.remediation?.regeneratedManifest) errors.push("manifestRegenerated must match remediation audit regenerated manifest"); if (handoff.diffReviewed!==audit.remediation?.diffReviewed) errors.push("diffReviewed must match remediation audit diff review"); if (handoff.runId!==manifest.provenance?.runId) errors.push("runId must match retained manifest provenance"); if (handoff.sourceRevision!==manifest.provenance?.sourceRevision) errors.push("sourceRevision must match retained manifest provenance"); if (handoff.reviewedBy!==audit.approval?.approvedBy) errors.push("reviewedBy must match archive drift remediation approver"); if (handoff.approvedAt!==audit.approval?.approvedAt) errors.push("approvedAt must match archive drift remediation approval time"); if (errors.length) throw new Error(`archive drift remediation audit handoff schema failure: ${errors.join("; ")}`); console.log(JSON.stringify({ok:true, failedPackageVersion:handoff.failedPackageVersion, replacementPackageVersion:handoff.replacementPackageVersion, runId:handoff.runId, reviewedBy:handoff.reviewedBy}, null, 2));\' <retained-evidence-dir> <retained-manifest>',
    ]);
    for (const command of remediationAuditHandoffSchemaCommands) {
      const result = await runShell(retainedCommand(command));
      assert.equal(result.exitCode, 0, `${command}\nstdout:\n${result.stdout}\nstderr:\n${result.stderr}`);
    }
    const validRemediationAuditHandoffPath = join(retainedEvidenceDir, "archive-drift-remediation-audit-handoff.json");
    const validRemediationAuditHandoff = await readFile(validRemediationAuditHandoffPath, "utf8");
    const invalidRemediationAuditHandoff = JSON.parse(validRemediationAuditHandoff);
    invalidRemediationAuditHandoff.schema_version = "jury.package_release_remediation_audit_handoff.invalid";
    invalidRemediationAuditHandoff.retainedWith = invalidRemediationAuditHandoff.retainedWith.filter((item) => item !== "archive-drift-remediation-audit.json");
    invalidRemediationAuditHandoff.failedTarballName = "wrong.tgz";
    invalidRemediationAuditHandoff.replacementPackageVersion = "0.1.9";
    invalidRemediationAuditHandoff.driftEvidence = ["downstream-failure-gate.json"];
    invalidRemediationAuditHandoff.runId = "different-release-run";
    invalidRemediationAuditHandoff.sourceRevision = "different-source-revision";
    invalidRemediationAuditHandoff.reviewedBy = "different-maintainer@example.com";
    invalidRemediationAuditHandoff.approvedAt = "2026-05-24T00:00:00.000Z";
    await writeFile(validRemediationAuditHandoffPath, `${JSON.stringify(invalidRemediationAuditHandoff, null, 2)}\n`);
    const invalidRemediationAuditHandoffInspection = await runShell(retainedCommand(remediationAuditHandoffSchemaCommands[1]));
    assert.equal(invalidRemediationAuditHandoffInspection.exitCode, 1);
    assert.match(invalidRemediationAuditHandoffInspection.stderr, /schema_version must equal jury\.package_release_remediation_audit_handoff\.v1/);
    assert.match(invalidRemediationAuditHandoffInspection.stderr, /retainedWith missing archive-drift-remediation-audit\.json/);
    assert.match(invalidRemediationAuditHandoffInspection.stderr, /failedTarballName must match retained manifest failed tarballName/);
    assert.match(invalidRemediationAuditHandoffInspection.stderr, /replacementPackageVersion must match retained manifest replacement packageVersion/);
    assert.match(invalidRemediationAuditHandoffInspection.stderr, /driftEvidence must match remediation audit drift evidence/);
    assert.match(invalidRemediationAuditHandoffInspection.stderr, /runId must match retained manifest provenance/);
    assert.match(invalidRemediationAuditHandoffInspection.stderr, /sourceRevision must match retained manifest provenance/);
    assert.match(invalidRemediationAuditHandoffInspection.stderr, /reviewedBy must match archive drift remediation approver/);
    assert.match(invalidRemediationAuditHandoffInspection.stderr, /approvedAt must match archive drift remediation approval time/);
    await writeFile(validRemediationAuditHandoffPath, validRemediationAuditHandoff);

    const remediationAuditHandoffCiReplayCommands = extractShellBlock(guide, "Remediation Audit Handoff CI Workflow Enforcement Failure");
    assert.equal(remediationAuditHandoffCiReplayCommands.length, 2);
    const remediationAuditHandoffWorkflowOrdering = await runShell(remediationAuditHandoffCiReplayCommands[0]);
    assert.equal(remediationAuditHandoffWorkflowOrdering.exitCode, 0, remediationAuditHandoffWorkflowOrdering.stderr);
    assert.equal(JSON.parse(remediationAuditHandoffWorkflowOrdering.stdout).step, "Replay Jury package release remediation audit handoff");
    assert.equal(JSON.parse(remediationAuditHandoffWorkflowOrdering.stdout).dryRunNeeds, "package-release-evidence-replay");
    const missingRemediationHandoffWorkflowPath = join(manifestReplayRoot, "missing-remediation-handoff-workflow.yml");
    const missingRemediationHandoffWorkflow = (await readFile(join(repoRoot, "jury/examples/ci/jury-npm-publish.yml"), "utf8"))
      .replace("Replay Jury package release remediation audit handoff", "Replay Jury package release remediation audit handoff disabled");
    await writeFile(missingRemediationHandoffWorkflowPath, missingRemediationHandoffWorkflow);
    const missingRemediationHandoffWorkflowOrdering = await runShell(
      remediationAuditHandoffCiReplayCommands[0].replace("jury/examples/ci/jury-npm-publish.yml", shellQuote(missingRemediationHandoffWorkflowPath)),
    );
    assert.equal(missingRemediationHandoffWorkflowOrdering.exitCode, 1);
    assert.match(missingRemediationHandoffWorkflowOrdering.stderr, /Replay Jury package release remediation audit handoff step is missing/);
    const remediationAuditHandoffCiReplay = await runShell(retainedCommand(remediationAuditHandoffCiReplayCommands[1]));
    assert.equal(remediationAuditHandoffCiReplay.exitCode, 0, remediationAuditHandoffCiReplay.stderr);
    assert.equal(JSON.parse(remediationAuditHandoffCiReplay.stdout).reviewedBy, "release-maintainer@example.com");
    const invalidRemediationAuditHandoffCiReplayPath = join(retainedEvidenceDir, "archive-drift-remediation-audit-handoff.json");
    const invalidRemediationAuditHandoffCiReplay = JSON.parse(await readFile(invalidRemediationAuditHandoffCiReplayPath, "utf8"));
    invalidRemediationAuditHandoffCiReplay.sourceRevision = "different-source-revision";
    await writeFile(invalidRemediationAuditHandoffCiReplayPath, `${JSON.stringify(invalidRemediationAuditHandoffCiReplay, null, 2)}\n`);
    const invalidRemediationAuditHandoffCiReplayCheck = await runShell(retainedCommand(remediationAuditHandoffCiReplayCommands[1]));
    assert.equal(invalidRemediationAuditHandoffCiReplayCheck.exitCode, 1);
    assert.match(invalidRemediationAuditHandoffCiReplayCheck.stderr, /remediation audit handoff CI workflow enforcement failed: sourceRevision must match retained manifest provenance/);
    await writeFile(invalidRemediationAuditHandoffCiReplayPath, validRemediationAuditHandoff);

    const driftedReplacementGatePath = join(retainedEvidenceDir, "replacement-downstream-gate.json");
    const driftedReplacementGate = JSON.parse(await readFile(driftedReplacementGatePath, "utf8"));
    driftedReplacementGate.reason = "replacement downstream gate changed after archive";
    await writeFile(driftedReplacementGatePath, `${JSON.stringify(driftedReplacementGate, null, 2)}\n`);
    const remediationDigestCheck = await runShell(retainedCommand(remediationCommands[1]));
    assert.equal(remediationDigestCheck.exitCode, 1);
    assert.deepEqual(JSON.parse(remediationDigestCheck.stdout).drift, ["replacement-downstream-gate.json"]);
    await cp(join(ciPackageReleaseFixturesDir, "replacement-downstream-gate.json"), driftedReplacementGatePath);

    const driftedFailedGatePath = join(retainedEvidenceDir, "downstream-failure-gate.json");
    const driftedFailedGate = JSON.parse(await readFile(driftedFailedGatePath, "utf8"));
    driftedFailedGate.reason = "failed downstream gate changed after archive";
    await writeFile(driftedFailedGatePath, `${JSON.stringify(driftedFailedGate, null, 2)}\n`);
    const failedRemediationDigestCheck = await runShell(retainedCommand(remediationCommands[1]));
    assert.equal(failedRemediationDigestCheck.exitCode, 1);
    assert.deepEqual(JSON.parse(failedRemediationDigestCheck.stdout).drift, ["downstream-failure-gate.json"]);
    await cp(join(ciPackageReleaseFixturesDir, "downstream-failure-gate.json"), driftedFailedGatePath);

    const dryRunRecordPath = join(retainedEvidenceDir, "jury-pack-dry-run-record.json");
    const dryRunRecord = JSON.parse(await readFile(dryRunRecordPath, "utf8"));
    dryRunRecord.packageVersion = "0.1.9";
    await writeFile(dryRunRecordPath, `${JSON.stringify(dryRunRecord, null, 2)}\n`);
    const dryRunIdentityCheck = await runShell(retainedCommand(remediationCommands[2]));
    assert.equal(dryRunIdentityCheck.exitCode, 1);
    assert.ok(JSON.parse(dryRunIdentityCheck.stdout).errors.includes("dry-run packageVersion must match retained manifest failed packageVersion"));
    assert.ok(JSON.parse(dryRunIdentityCheck.stdout).errors.includes("rollback and replacement audits must reference the dry-run packageVersion"));
    await cp(join(ciPackageReleaseFixturesDir, "jury-pack-dry-run-record.json"), dryRunRecordPath);

    const remediationAuditPath = join(retainedEvidenceDir, "archive-drift-remediation-audit.json");
    const remediationAudit = JSON.parse(await readFile(remediationAuditPath, "utf8"));
    const missingApprovalAudit = structuredClone(remediationAudit);
    delete missingApprovalAudit.approval.approvedBy;
    await writeFile(remediationAuditPath, `${JSON.stringify(missingApprovalAudit, null, 2)}\n`);
    const missingApprovalCheck = await runShell(retainedCommand(remediationAuditReplayCommands[0]));
    assert.equal(missingApprovalCheck.exitCode, 1);
    assert.match(missingApprovalCheck.stderr, /archive drift remediation audit must record approving maintainer/);

    const missingCommandAudit = structuredClone(remediationAudit);
    missingCommandAudit.verification.commands = missingCommandAudit.verification.commands.filter((command) => !command.includes("--verify-manifest"));
    await writeFile(remediationAuditPath, `${JSON.stringify(missingCommandAudit, null, 2)}\n`);
    const missingVerificationCommandCheck = await runShell(retainedCommand(remediationAuditReplayCommands[1]));
    assert.equal(missingVerificationCommandCheck.exitCode, 1);
    assert.match(missingVerificationCommandCheck.stderr, /archive drift remediation audit missing verification commands: --verify-manifest/);
    await writeFile(remediationAuditPath, `${JSON.stringify(remediationAudit, null, 2)}\n`);

    const replaySummaryTroubleshootingCommands = extractShellBlock(guide, "Replay Artifact Summary Failure");
    assert.deepEqual(replaySummaryTroubleshootingCommands, [
      'node -e \'const fs=require("node:fs"); const dir=process.argv[1]; const manifest=JSON.parse(fs.readFileSync(process.argv[2],"utf8")); const remediation=JSON.parse(fs.readFileSync(`${dir}/archive-drift-remediation-audit.json`,"utf8")); const summary={failedPackageVersion:manifest.failed?.packageVersion,failedTarballName:manifest.failed?.tarballName,replacementPackageVersion:manifest.replacement?.packageVersion,failedArchiveEvidence:remediation.failed?.archiveEvidence,replacementArchiveEvidence:remediation.replacement?.archiveEvidence,remediationApprovedBy:remediation.approval?.approvedBy}; console.log(JSON.stringify(summary,null,2)); if (!summary.failedPackageVersion || !summary.failedTarballName || !summary.replacementPackageVersion || !summary.remediationApprovedBy) process.exit(1);\' <retained-evidence-dir> <retained-manifest>',
      'node -e \'const fs=require("node:fs"); const dir=process.argv[1]; const manifest=JSON.parse(fs.readFileSync(process.argv[2],"utf8")); const summary=fs.readFileSync(process.argv[3],"utf8"); const remediation=JSON.parse(fs.readFileSync(`${dir}/archive-drift-remediation-audit.json`,"utf8")); const required=[`- failedPackageVersion: ${manifest.failed.packageVersion}`,`- failedTarballName: ${manifest.failed.tarballName}`,`- replacementPackageVersion: ${manifest.replacement.packageVersion}`,`- failedArchiveEvidence: ${remediation.failed.archiveEvidence.join(", ")}`,`- replacementArchiveEvidence: ${remediation.replacement.archiveEvidence.join(", ")}`,`- remediationApprovedBy: ${remediation.approval.approvedBy}`]; const missing=required.filter((line)=>!summary.includes(line)); if (missing.length) throw new Error(`missing replay summary lines: ${missing.join(", ")}`); console.log(JSON.stringify({ok:true, checked:required}, null, 2));\' <retained-evidence-dir> <retained-manifest> <summary-file>',
    ]);
    const replaySummarySource = await runShell(retainedCommand(replaySummaryTroubleshootingCommands[0]));
    assert.equal(replaySummarySource.exitCode, 0, replaySummarySource.stderr);
    assert.deepEqual(JSON.parse(replaySummarySource.stdout), {
      failedPackageVersion: "0.1.0",
      failedTarballName: "sanogueralorenzo-jury-0.1.0.tgz",
      replacementPackageVersion: "0.1.1",
      failedArchiveEvidence: ["downstream-failure-gate.json", "failed-npm-view.json", "rollback-audit.json"],
      replacementArchiveEvidence: ["replacement-downstream-gate.json", "replacement-npm-view.json", "replacement-patch-audit.json"],
      remediationApprovedBy: "release-maintainer@example.com",
    });

    const replaySummaryPath = join(manifestReplayRoot, "package-release-replay-summary.md");
    await writeFile(replaySummaryPath, [
      "### Jury package release replay",
      "",
      "- failedPackageVersion: 0.1.0",
      "- failedTarballName: sanogueralorenzo-jury-0.1.0.tgz",
      "- replacementPackageVersion: 0.1.1",
      "- failedArchiveEvidence: downstream-failure-gate.json, failed-npm-view.json, rollback-audit.json",
      "- replacementArchiveEvidence: replacement-downstream-gate.json, replacement-npm-view.json, replacement-patch-audit.json",
      "- remediationApprovedBy: release-maintainer@example.com",
      "",
    ].join("\n"));
    const replaySummaryCheck = await runShell(retainedCommand(replaySummaryTroubleshootingCommands[1]).replace("<summary-file>", shellQuote(replaySummaryPath)));
    assert.equal(replaySummaryCheck.exitCode, 0, replaySummaryCheck.stderr);
    assert.equal(JSON.parse(replaySummaryCheck.stdout).ok, true);

    await writeFile(replaySummaryPath, "- failedPackageVersion: 0.1.0\n");
    const missingReplaySummaryLineCheck = await runShell(retainedCommand(replaySummaryTroubleshootingCommands[1]).replace("<summary-file>", shellQuote(replaySummaryPath)));
    assert.equal(missingReplaySummaryLineCheck.exitCode, 1);
    assert.match(missingReplaySummaryLineCheck.stderr, /missing replay summary lines: - failedTarballName: sanogueralorenzo-jury-0\.1\.0\.tgz/);

    await writeFile(replaySummaryPath, [
      "### Jury package release replay",
      "",
      "- failedPackageVersion: 0.1.0",
      "- failedTarballName: sanogueralorenzo-jury-0.1.0.tgz",
      "- replacementPackageVersion: 0.1.1",
      "- failedArchiveEvidence: downstream-failure-gate.json, failed-npm-view.json, rollback-audit.json",
      "- replacementArchiveEvidence: replacement-downstream-gate.json, replacement-npm-view.json, replacement-patch-audit.json",
      "- remediationApprovedBy: release-maintainer@example.com",
      "",
    ].join("\n"));

    const replaySummaryDiagnosticsCommands = extractShellBlock(guide, "Replay Summary CI Workflow Diagnostics Failure");
    assert.deepEqual(replaySummaryDiagnosticsCommands, [
      'node -e \'const fs=require("node:fs"); const diagnostics=JSON.parse(fs.readFileSync(process.argv[1],"utf8")); const required=["schema_version","sourceJob","summaryArtifact","summaryFile","failedPackageVersion","failedTarballName","replacementPackageVersion","failedArchiveEvidence","replacementArchiveEvidence","remediationApprovedBy","checkedLines"]; const missing=required.filter((field)=>diagnostics[field]===undefined); if (missing.length) throw new Error(`replay summary diagnostics missing fields: ${missing.join(", ")}`); if (diagnostics.schema_version!=="jury.package_release_replay_summary_diagnostics.v1") throw new Error("schema_version must equal jury.package_release_replay_summary_diagnostics.v1"); console.log(JSON.stringify({ok:true, sourceJob:diagnostics.sourceJob, summaryArtifact:diagnostics.summaryArtifact, summaryFile:diagnostics.summaryFile}, null, 2));\' <diagnostics-file>',
      'node -e \'const fs=require("node:fs"); const dir=process.argv[1]; const manifest=JSON.parse(fs.readFileSync(process.argv[2],"utf8")); const summary=fs.readFileSync(process.argv[3],"utf8"); const diagnostics=JSON.parse(fs.readFileSync(process.argv[4],"utf8")); const remediation=JSON.parse(fs.readFileSync(`${dir}/archive-drift-remediation-audit.json`,"utf8")); const expected={schema_version:"jury.package_release_replay_summary_diagnostics.v1",sourceJob:"package-release-evidence-replay",summaryArtifact:"jury-package-release-replay-summary",summaryFile:"jury-package-release-replay-summary.md",failedPackageVersion:manifest.failed.packageVersion,failedTarballName:manifest.failed.tarballName,replacementPackageVersion:manifest.replacement.packageVersion,failedArchiveEvidence:remediation.failed.archiveEvidence,replacementArchiveEvidence:remediation.replacement.archiveEvidence,remediationApprovedBy:remediation.approval.approvedBy,checkedLines:["### Jury package release replay",`- failedPackageVersion: ${manifest.failed.packageVersion}`,`- failedTarballName: ${manifest.failed.tarballName}`,`- replacementPackageVersion: ${manifest.replacement.packageVersion}`,`- failedArchiveEvidence: ${remediation.failed.archiveEvidence.join(", ")}`,`- replacementArchiveEvidence: ${remediation.replacement.archiveEvidence.join(", ")}`,`- remediationApprovedBy: ${remediation.approval.approvedBy}`]}; const errors=[]; for (const field of ["schema_version","sourceJob","summaryArtifact","summaryFile","failedPackageVersion","failedTarballName","replacementPackageVersion","remediationApprovedBy"]) if (diagnostics[field]!==expected[field]) errors.push(`${field} must match replay evidence`); for (const field of ["failedArchiveEvidence","replacementArchiveEvidence"]) if (JSON.stringify(diagnostics[field])!==JSON.stringify(expected[field])) errors.push(`${field} must match remediation audit`); for (const line of expected.checkedLines) { if (!diagnostics.checkedLines?.includes(line)) errors.push(`checkedLines missing ${line}`); if (!summary.includes(line)) errors.push(`summary missing ${line}`); } if (errors.length) throw new Error(`replay summary diagnostics mismatch: ${errors.join("; ")}`); console.log(JSON.stringify({ok:true, checkedLines:expected.checkedLines}, null, 2));\' <retained-evidence-dir> <retained-manifest> <summary-file> <diagnostics-file>',
    ]);
    const replaySummaryDiagnosticsPath = join(retainedEvidenceDir, "jury-package-release-replay-summary-diagnostics.json");
    const replaySummaryDiagnosticsFields = await runShell(replaySummaryDiagnosticsCommands[0].replace("<diagnostics-file>", shellQuote(replaySummaryDiagnosticsPath)));
    assert.equal(replaySummaryDiagnosticsFields.exitCode, 0, replaySummaryDiagnosticsFields.stderr);
    assert.equal(JSON.parse(replaySummaryDiagnosticsFields.stdout).summaryFile, "jury-package-release-replay-summary.md");
    const replaySummaryDiagnosticsCheck = await runShell(retainedCommand(replaySummaryDiagnosticsCommands[1])
      .replace("<summary-file>", shellQuote(replaySummaryPath))
      .replace("<diagnostics-file>", shellQuote(replaySummaryDiagnosticsPath)));
    assert.equal(replaySummaryDiagnosticsCheck.exitCode, 0, replaySummaryDiagnosticsCheck.stderr);
    assert.equal(JSON.parse(replaySummaryDiagnosticsCheck.stdout).ok, true);

    const invalidReplaySummaryDiagnosticsPath = join(manifestReplayRoot, "invalid-replay-summary-diagnostics.json");
    const invalidReplaySummaryDiagnostics = JSON.parse(await readFile(replaySummaryDiagnosticsPath, "utf8"));
    delete invalidReplaySummaryDiagnostics.summaryArtifact;
    await writeFile(invalidReplaySummaryDiagnosticsPath, `${JSON.stringify(invalidReplaySummaryDiagnostics, null, 2)}\n`);
    const missingReplaySummaryDiagnosticsField = await runShell(replaySummaryDiagnosticsCommands[0].replace("<diagnostics-file>", shellQuote(invalidReplaySummaryDiagnosticsPath)));
    assert.equal(missingReplaySummaryDiagnosticsField.exitCode, 1);
    assert.match(missingReplaySummaryDiagnosticsField.stderr, /replay summary diagnostics missing fields: summaryArtifact/);

    invalidReplaySummaryDiagnostics.summaryArtifact = "jury-package-release-replay-summary";
    invalidReplaySummaryDiagnostics.schema_version = "jury.package_release_replay_summary_diagnostics.invalid";
    await writeFile(invalidReplaySummaryDiagnosticsPath, `${JSON.stringify(invalidReplaySummaryDiagnostics, null, 2)}\n`);
    const invalidReplaySummaryDiagnosticsSchema = await runShell(replaySummaryDiagnosticsCommands[0].replace("<diagnostics-file>", shellQuote(invalidReplaySummaryDiagnosticsPath)));
    assert.equal(invalidReplaySummaryDiagnosticsSchema.exitCode, 1);
    assert.match(invalidReplaySummaryDiagnosticsSchema.stderr, /schema_version must equal jury\.package_release_replay_summary_diagnostics\.v1/);

    invalidReplaySummaryDiagnostics.replacementPackageVersion = "0.1.2";
    invalidReplaySummaryDiagnostics.checkedLines = invalidReplaySummaryDiagnostics.checkedLines.filter((line) => !line.includes("replacementPackageVersion"));
    await writeFile(invalidReplaySummaryDiagnosticsPath, `${JSON.stringify(invalidReplaySummaryDiagnostics, null, 2)}\n`);
    const driftedReplaySummaryDiagnostics = await runShell(retainedCommand(replaySummaryDiagnosticsCommands[1])
      .replace("<summary-file>", shellQuote(replaySummaryPath))
      .replace("<diagnostics-file>", shellQuote(invalidReplaySummaryDiagnosticsPath)));
    assert.equal(driftedReplaySummaryDiagnostics.exitCode, 1);
    assert.match(driftedReplaySummaryDiagnostics.stderr, /replay summary diagnostics mismatch: schema_version must match replay evidence/);
    assert.match(driftedReplaySummaryDiagnostics.stderr, /replacementPackageVersion must match replay evidence/);
    assert.match(driftedReplaySummaryDiagnostics.stderr, /checkedLines missing - replacementPackageVersion: 0\.1\.1/);

    const replaySummaryDiagnosticsRetentionCommands = extractShellBlock(guide, "Replay Summary Diagnostics Retention Handoff Failure");
    assert.deepEqual(replaySummaryDiagnosticsRetentionCommands, [
      'node -e \'const fs=require("node:fs"); const handoff=JSON.parse(fs.readFileSync(process.argv[1],"utf8")); const required=["schema_version","reason","sourceArtifact","sourceJob","retentionDays","diagnosticsSchemaVersion","retainedDiagnostics","summaryFile","retainedWith","failedPackageVersion","failedTarballName","replacementPackageVersion","runId","sourceRevision","reviewedBy"]; const missing=required.filter((field)=>handoff[field]===undefined); if (missing.length) throw new Error(`replay summary diagnostics retention handoff missing fields: ${missing.join(", ")}`); if (handoff.schema_version!=="jury.package_release_replay_summary_diagnostics_retention_handoff.v1") throw new Error("schema_version must equal jury.package_release_replay_summary_diagnostics_retention_handoff.v1"); console.log(JSON.stringify({ok:true, sourceArtifact:handoff.sourceArtifact, retainedDiagnostics:handoff.retainedDiagnostics, reviewedBy:handoff.reviewedBy}, null, 2));\' <diagnostics-retention-handoff-file>',
      'node -e \'const fs=require("node:fs"); const dir=process.argv[1]; const manifest=JSON.parse(fs.readFileSync(process.argv[2],"utf8")); const diagnostics=JSON.parse(fs.readFileSync(process.argv[3],"utf8")); const handoff=JSON.parse(fs.readFileSync(process.argv[4],"utf8")); const remediation=JSON.parse(fs.readFileSync(`${dir}/archive-drift-remediation-audit.json`,"utf8")); const artifact=(manifest.provenance?.artifacts??[]).find((item)=>item.name==="jury-package-release-replay-summary"); const expected={schema_version:"jury.package_release_replay_summary_diagnostics_retention_handoff.v1",reason:"jury-package-release-replay-summary-diagnostics retained with failed and replacement release archives",sourceArtifact:"jury-package-release-replay-summary",sourceJob:"package-release-evidence-replay",retentionDays:90,diagnosticsSchemaVersion:diagnostics.schema_version,retainedDiagnostics:"jury-package-release-replay-summary-diagnostics.json",summaryFile:diagnostics.summaryFile,failedPackageVersion:diagnostics.failedPackageVersion,failedTarballName:diagnostics.failedTarballName,replacementPackageVersion:diagnostics.replacementPackageVersion,runId:manifest.provenance?.runId,sourceRevision:manifest.provenance?.sourceRevision,reviewedBy:remediation.approval?.approvedBy}; const errors=[]; for (const field of Object.keys(expected)) if (handoff[field]!==expected[field]) errors.push(`${field} must match retained diagnostics evidence`); for (const item of ["retained-package-release-evidence-manifest.json","jury-package-release-replay-summary.md","archive-drift-remediation-audit.json"]) if (!(handoff.retainedWith??[]).includes(item)) errors.push(`retainedWith missing ${item}`); if (artifact?.sourceJob!=="package-release-evidence-replay") errors.push("jury-package-release-replay-summary sourceJob must be package-release-evidence-replay"); if (artifact?.retentionDays!==90) errors.push("jury-package-release-replay-summary retentionDays must be 90"); if (!artifact?.files?.includes("jury-package-release-replay-summary-diagnostics.json")) errors.push("replay summary artifact files missing diagnostics JSON"); if (!artifact?.files?.includes("jury-package-release-replay-summary-diagnostics-retention-handoff.json")) errors.push("replay summary artifact files missing diagnostics retention handoff"); if (errors.length) throw new Error(`replay summary diagnostics retention handoff mismatch: ${errors.join("; ")}`); console.log(JSON.stringify({ok:true, runId:handoff.runId, sourceRevision:handoff.sourceRevision, reviewedBy:handoff.reviewedBy}, null, 2));\' <retained-evidence-dir> <retained-manifest> <diagnostics-file> <diagnostics-retention-handoff-file>',
    ]);
    const replaySummaryDiagnosticsRetentionPath = join(retainedEvidenceDir, "jury-package-release-replay-summary-diagnostics-retention-handoff.json");
    const diagnosticsRetentionCommand = (command) => retainedCommand(command)
      .replace("<diagnostics-file>", shellQuote(replaySummaryDiagnosticsPath))
      .replace("<diagnostics-retention-handoff-file>", shellQuote(replaySummaryDiagnosticsRetentionPath));
    const diagnosticsRetentionFields = await runShell(diagnosticsRetentionCommand(replaySummaryDiagnosticsRetentionCommands[0]));
    assert.equal(diagnosticsRetentionFields.exitCode, 0, diagnosticsRetentionFields.stderr);
    assert.equal(JSON.parse(diagnosticsRetentionFields.stdout).retainedDiagnostics, "jury-package-release-replay-summary-diagnostics.json");
    const diagnosticsRetentionCheck = await runShell(diagnosticsRetentionCommand(replaySummaryDiagnosticsRetentionCommands[1]));
    assert.equal(diagnosticsRetentionCheck.exitCode, 0, diagnosticsRetentionCheck.stderr);
    assert.equal(JSON.parse(diagnosticsRetentionCheck.stdout).reviewedBy, "release-maintainer@example.com");

    const invalidDiagnosticsRetentionPath = join(manifestReplayRoot, "invalid-replay-summary-diagnostics-retention-handoff.json");
    const invalidDiagnosticsRetention = JSON.parse(await readFile(replaySummaryDiagnosticsRetentionPath, "utf8"));
    delete invalidDiagnosticsRetention.sourceArtifact;
    await writeFile(invalidDiagnosticsRetentionPath, `${JSON.stringify(invalidDiagnosticsRetention, null, 2)}\n`);
    const missingDiagnosticsRetentionField = await runShell(diagnosticsRetentionCommand(replaySummaryDiagnosticsRetentionCommands[0])
      .replace(shellQuote(replaySummaryDiagnosticsRetentionPath), shellQuote(invalidDiagnosticsRetentionPath)));
    assert.equal(missingDiagnosticsRetentionField.exitCode, 1);
    assert.match(missingDiagnosticsRetentionField.stderr, /replay summary diagnostics retention handoff missing fields: sourceArtifact/);

    invalidDiagnosticsRetention.sourceArtifact = "jury-package-release-replay-summary";
    invalidDiagnosticsRetention.schema_version = "jury.package_release_replay_summary_diagnostics_retention_handoff.invalid";
    invalidDiagnosticsRetention.runId = "different-release-run";
    invalidDiagnosticsRetention.retainedWith = ["archive-drift-remediation-audit.json"];
    await writeFile(invalidDiagnosticsRetentionPath, `${JSON.stringify(invalidDiagnosticsRetention, null, 2)}\n`);
    const invalidDiagnosticsRetentionCheck = await runShell(diagnosticsRetentionCommand(replaySummaryDiagnosticsRetentionCommands[1])
      .replace(shellQuote(replaySummaryDiagnosticsRetentionPath), shellQuote(invalidDiagnosticsRetentionPath)));
    assert.equal(invalidDiagnosticsRetentionCheck.exitCode, 1);
    assert.match(invalidDiagnosticsRetentionCheck.stderr, /replay summary diagnostics retention handoff mismatch: schema_version must match retained diagnostics evidence/);
    assert.match(invalidDiagnosticsRetentionCheck.stderr, /runId must match retained diagnostics evidence/);
    assert.match(invalidDiagnosticsRetentionCheck.stderr, /retainedWith missing retained-package-release-evidence-manifest\.json/);

    const replaySummaryDiagnosticsRetentionCiReplayCommands = extractShellBlock(guide, "Replay Summary Diagnostics Retention Handoff CI Replay Enforcement Failure");
    assert.deepEqual(replaySummaryDiagnosticsRetentionCiReplayCommands, [
      'node -e \'const fs=require("node:fs"); const workflow=fs.readFileSync(process.argv[1],"utf8"); const lines=workflow.split("\\n"); const step=(name)=>lines.findIndex((line)=>line.trim()===`- name: ${name}`); const record=step("Record Jury package release replay diagnostics retention handoff"); const replay=step("Replay Jury package release replay diagnostics retention handoff"); const upload=step("Upload Jury package release replay summary"); const dryRunJob=lines.findIndex((line)=>line==="  dry-run-publication:"); const dryRun=step("Create Jury package dry-run record"); const publish=lines.findIndex((line,index)=>index>dryRunJob && line==="  publish:"); const dryRunBlock=dryRunJob===-1 ? "" : lines.slice(dryRunJob, publish===-1 ? lines.length : publish).join("\\n"); if (replay===-1) throw new Error("Replay Jury package release replay diagnostics retention handoff step is missing"); if (!(record!==-1 && upload!==-1 && dryRun!==-1 && record<replay && replay<upload && replay<dryRun)) throw new Error("diagnostics retention handoff replay must run after handoff generation and before summary upload and dry-run publication"); if (!/needs:\\s*\\n\\s+- package-manifest\\s*\\n\\s+- package-release-evidence-replay/.test(dryRunBlock)) throw new Error("dry-run-publication must need package-release-evidence-replay so diagnostics retention handoff replay blocks dry-run publication"); console.log(JSON.stringify({ok:true, step:"Replay Jury package release replay diagnostics retention handoff", dryRunNeeds:"package-release-evidence-replay"}, null, 2));\' jury/examples/ci/jury-npm-publish.yml',
      'node -e \'const fs=require("node:fs"); const dir=process.argv[1]; const manifest=JSON.parse(fs.readFileSync(process.argv[2],"utf8")); const diagnostics=JSON.parse(fs.readFileSync(process.argv[3],"utf8")); const handoff=JSON.parse(fs.readFileSync(process.argv[4],"utf8")); const retained=JSON.parse(fs.readFileSync(`${dir}/jury-package-release-replay-summary-diagnostics-retention-handoff.json`,"utf8")); const remediation=JSON.parse(fs.readFileSync(`${dir}/archive-drift-remediation-audit.json`,"utf8")); const artifact=(manifest.provenance?.artifacts??[]).find((item)=>item.name==="jury-package-release-replay-summary"); const expected={schema_version:"jury.package_release_replay_summary_diagnostics_retention_handoff.v1",reason:"jury-package-release-replay-summary-diagnostics retained with failed and replacement release archives",sourceArtifact:"jury-package-release-replay-summary",sourceJob:"package-release-evidence-replay",retentionDays:90,diagnosticsSchemaVersion:diagnostics.schema_version,retainedDiagnostics:"jury-package-release-replay-summary-diagnostics.json",summaryFile:diagnostics.summaryFile,failedPackageVersion:diagnostics.failedPackageVersion,failedTarballName:diagnostics.failedTarballName,replacementPackageVersion:diagnostics.replacementPackageVersion,runId:manifest.provenance?.runId,sourceRevision:manifest.provenance?.sourceRevision,reviewedBy:remediation.approval?.approvedBy}; const errors=[]; for (const field of Object.keys(expected)) if (handoff[field]!==expected[field]) errors.push(`${field} must match retained diagnostics evidence`); for (const item of ["retained-package-release-evidence-manifest.json","jury-package-release-replay-summary.md","archive-drift-remediation-audit.json"]) if (!(handoff.retainedWith??[]).includes(item)) errors.push(`retainedWith missing ${item}`); if (artifact?.sourceJob!=="package-release-evidence-replay") errors.push("jury-package-release-replay-summary sourceJob must be package-release-evidence-replay"); if (artifact?.retentionDays!==90) errors.push("jury-package-release-replay-summary retentionDays must be 90"); if (!artifact?.files?.includes("jury-package-release-replay-summary-diagnostics.json")) errors.push("jury-package-release-replay-summary files must include diagnostics JSON"); if (!artifact?.files?.includes("jury-package-release-replay-summary-diagnostics-retention-handoff.json")) errors.push("jury-package-release-replay-summary files must include diagnostics retention handoff"); const stable=(value)=>JSON.stringify(value,Object.keys(value).sort()); if (stable(handoff)!==stable(retained)) errors.push("generated diagnostics retention handoff must match retained archive evidence"); if (errors.length) throw new Error(`replay summary diagnostics retention handoff CI replay enforcement failed: ${errors.join("; ")}`); console.log(JSON.stringify({ok:true, sourceArtifact:handoff.sourceArtifact, runId:handoff.runId, reviewedBy:handoff.reviewedBy}, null, 2));\' <retained-evidence-dir> <retained-manifest> <diagnostics-file> <diagnostics-retention-handoff-file>',
    ]);
    const workflowOrderingCheck = await runShell(replaySummaryDiagnosticsRetentionCiReplayCommands[0]);
    assert.equal(workflowOrderingCheck.exitCode, 0, workflowOrderingCheck.stderr);
    assert.equal(JSON.parse(workflowOrderingCheck.stdout).step, "Replay Jury package release replay diagnostics retention handoff");
    assert.equal(JSON.parse(workflowOrderingCheck.stdout).dryRunNeeds, "package-release-evidence-replay");
    const missingDiagnosticsRetentionWorkflowPath = join(manifestReplayRoot, "missing-diagnostics-retention-workflow.yml");
    const missingDiagnosticsRetentionWorkflow = (await readFile(join(repoRoot, "jury/examples/ci/jury-npm-publish.yml"), "utf8"))
      .replace("Replay Jury package release replay diagnostics retention handoff", "Replay Jury package release replay diagnostics retention handoff disabled");
    await writeFile(missingDiagnosticsRetentionWorkflowPath, missingDiagnosticsRetentionWorkflow);
    const missingDiagnosticsRetentionWorkflowOrdering = await runShell(
      replaySummaryDiagnosticsRetentionCiReplayCommands[0].replace("jury/examples/ci/jury-npm-publish.yml", shellQuote(missingDiagnosticsRetentionWorkflowPath)),
    );
    assert.equal(missingDiagnosticsRetentionWorkflowOrdering.exitCode, 1);
    assert.match(missingDiagnosticsRetentionWorkflowOrdering.stderr, /Replay Jury package release replay diagnostics retention handoff step is missing/);
    const ciReplayCommand = (command) => diagnosticsRetentionCommand(command)
      .replace(shellQuote(replaySummaryDiagnosticsRetentionPath), shellQuote(join(ciPackageReleaseFixturesDir, "jury-package-release-replay-summary-diagnostics-retention-handoff.json")));
    const diagnosticsRetentionCiReplay = await runShell(ciReplayCommand(replaySummaryDiagnosticsRetentionCiReplayCommands[1]));
    assert.equal(diagnosticsRetentionCiReplay.exitCode, 0, diagnosticsRetentionCiReplay.stderr);
    assert.equal(JSON.parse(diagnosticsRetentionCiReplay.stdout).runId, "example-release-run-1001");

    const invalidDiagnosticsRetentionCiReplayPath = join(manifestReplayRoot, "invalid-ci-replay-diagnostics-retention-handoff.json");
    const invalidDiagnosticsRetentionCiReplay = JSON.parse(await readFile(replaySummaryDiagnosticsRetentionPath, "utf8"));
    invalidDiagnosticsRetentionCiReplay.sourceRevision = "different-release-revision";
    await writeFile(invalidDiagnosticsRetentionCiReplayPath, `${JSON.stringify(invalidDiagnosticsRetentionCiReplay, null, 2)}\n`);
    const invalidDiagnosticsRetentionCiReplayCheck = await runShell(ciReplayCommand(replaySummaryDiagnosticsRetentionCiReplayCommands[1])
      .replace(shellQuote(join(ciPackageReleaseFixturesDir, "jury-package-release-replay-summary-diagnostics-retention-handoff.json")), shellQuote(invalidDiagnosticsRetentionCiReplayPath)));
    assert.equal(invalidDiagnosticsRetentionCiReplayCheck.exitCode, 1);
    assert.match(invalidDiagnosticsRetentionCiReplayCheck.stderr, /replay summary diagnostics retention handoff CI replay enforcement failed: sourceRevision must match retained diagnostics evidence/);

    const replaySummaryDiagnosticsRetentionSchemaCommands = extractShellBlock(guide, "Replay Summary Diagnostics Retention Handoff Schema Failure");
    assert.deepEqual(replaySummaryDiagnosticsRetentionSchemaCommands, [
      "npm --prefix jury run fixtures:package-release:check -- --fixture-dir <retained-evidence-dir>",
      'node -e \'const fs=require("node:fs"); const dir=process.argv[1]; const manifest=JSON.parse(fs.readFileSync(process.argv[2],"utf8")); const diagnostics=JSON.parse(fs.readFileSync(`${dir}/jury-package-release-replay-summary-diagnostics.json`,"utf8")); const handoff=JSON.parse(fs.readFileSync(`${dir}/jury-package-release-replay-summary-diagnostics-retention-handoff.json`,"utf8")); const remediation=JSON.parse(fs.readFileSync(`${dir}/archive-drift-remediation-audit.json`,"utf8")); const requiredWith=["retained-package-release-evidence-manifest.json","jury-package-release-replay-summary.md","archive-drift-remediation-audit.json"]; const errors=[]; if (handoff.schema_version!=="jury.package_release_replay_summary_diagnostics_retention_handoff.v1") errors.push("schema_version must equal jury.package_release_replay_summary_diagnostics_retention_handoff.v1"); if (handoff.reason!=="jury-package-release-replay-summary-diagnostics retained with failed and replacement release archives") errors.push("reason must explain diagnostics retention with failed and replacement release archives"); if (handoff.sourceArtifact!=="jury-package-release-replay-summary") errors.push("sourceArtifact must be jury-package-release-replay-summary"); if (handoff.sourceJob!=="package-release-evidence-replay") errors.push("sourceJob must be package-release-evidence-replay"); if (handoff.retentionDays!==90) errors.push("retentionDays must equal 90"); if (handoff.diagnosticsSchemaVersion!==diagnostics.schema_version) errors.push("diagnosticsSchemaVersion must match diagnostics schema_version"); if (handoff.retainedDiagnostics!=="jury-package-release-replay-summary-diagnostics.json") errors.push("retainedDiagnostics must be jury-package-release-replay-summary-diagnostics.json"); if (handoff.summaryFile!==diagnostics.summaryFile) errors.push("summaryFile must match diagnostics summaryFile"); for (const item of requiredWith) if (!(handoff.retainedWith??[]).includes(item)) errors.push(`retainedWith missing ${item}`); if (handoff.failedPackageVersion!==diagnostics.failedPackageVersion || handoff.failedPackageVersion!==manifest.failed?.packageVersion) errors.push("failedPackageVersion must match diagnostics and retained manifest"); if (handoff.failedTarballName!==diagnostics.failedTarballName || handoff.failedTarballName!==manifest.failed?.tarballName) errors.push("failedTarballName must match diagnostics and retained manifest"); if (handoff.replacementPackageVersion!==diagnostics.replacementPackageVersion || handoff.replacementPackageVersion!==manifest.replacement?.packageVersion) errors.push("replacementPackageVersion must match diagnostics and retained manifest"); if (handoff.runId!==manifest.provenance?.runId) errors.push("runId must match retained manifest provenance"); if (handoff.sourceRevision!==manifest.provenance?.sourceRevision) errors.push("sourceRevision must match retained manifest provenance"); if (!handoff.reviewedBy) errors.push("reviewedBy must identify the maintainer who reviewed diagnostics retention"); if (handoff.reviewedBy!==remediation.approval?.approvedBy) errors.push("reviewedBy must match archive drift remediation approver"); if (errors.length) throw new Error(`replay summary diagnostics retention handoff schema failure: ${errors.join("; ")}`); console.log(JSON.stringify({ok:true, failedPackageVersion:handoff.failedPackageVersion, replacementPackageVersion:handoff.replacementPackageVersion, runId:handoff.runId, reviewedBy:handoff.reviewedBy}, null, 2));\' <retained-evidence-dir> <retained-manifest>',
    ]);
    const diagnosticsRetentionSchemaReplay = await runShell(retainedCommand(replaySummaryDiagnosticsRetentionSchemaCommands[0]));
    assert.equal(diagnosticsRetentionSchemaReplay.exitCode, 0, diagnosticsRetentionSchemaReplay.stderr);
    const diagnosticsRetentionSchemaInspection = await runShell(retainedCommand(replaySummaryDiagnosticsRetentionSchemaCommands[1]));
    assert.equal(diagnosticsRetentionSchemaInspection.exitCode, 0, diagnosticsRetentionSchemaInspection.stderr);
    assert.deepEqual(JSON.parse(diagnosticsRetentionSchemaInspection.stdout), {
      ok: true,
      failedPackageVersion: "0.1.0",
      replacementPackageVersion: "0.1.1",
      runId: "example-release-run-1001",
      reviewedBy: "release-maintainer@example.com",
    });

    const retainedDiagnosticsRetentionHandoffPath = join(retainedEvidenceDir, "jury-package-release-replay-summary-diagnostics-retention-handoff.json");
    const retainedDiagnosticsRetentionHandoff = JSON.parse(await readFile(retainedDiagnosticsRetentionHandoffPath, "utf8"));
    retainedDiagnosticsRetentionHandoff.schema_version = "jury.package_release_replay_summary_diagnostics_retention_handoff.invalid";
    retainedDiagnosticsRetentionHandoff.diagnosticsSchemaVersion = "jury.package_release_replay_summary_diagnostics.invalid";
    retainedDiagnosticsRetentionHandoff.failedTarballName = "wrong.tgz";
    retainedDiagnosticsRetentionHandoff.runId = "different-release-run";
    retainedDiagnosticsRetentionHandoff.reviewedBy = "";
    await writeFile(retainedDiagnosticsRetentionHandoffPath, `${JSON.stringify(retainedDiagnosticsRetentionHandoff, null, 2)}\n`);
    const invalidDiagnosticsRetentionSchemaReplay = await runShell(retainedCommand(replaySummaryDiagnosticsRetentionSchemaCommands[0]));
    assert.equal(invalidDiagnosticsRetentionSchemaReplay.exitCode, 1);
    assert.match(invalidDiagnosticsRetentionSchemaReplay.stderr, /jury-package-release-replay-summary-diagnostics-retention-handoff\.json\.schema_version must equal jury\.package_release_replay_summary_diagnostics_retention_handoff\.v1/);
    assert.match(invalidDiagnosticsRetentionSchemaReplay.stderr, /jury-package-release-replay-summary-diagnostics-retention-handoff\.json\.reviewedBy must not be empty/);
    const invalidDiagnosticsRetentionSchemaInspection = await runShell(retainedCommand(replaySummaryDiagnosticsRetentionSchemaCommands[1]));
    assert.equal(invalidDiagnosticsRetentionSchemaInspection.exitCode, 1);
    assert.match(invalidDiagnosticsRetentionSchemaInspection.stderr, /replay summary diagnostics retention handoff schema failure: schema_version must equal jury\.package_release_replay_summary_diagnostics_retention_handoff\.v1/);
    assert.match(invalidDiagnosticsRetentionSchemaInspection.stderr, /diagnosticsSchemaVersion must match diagnostics schema_version/);
    assert.match(invalidDiagnosticsRetentionSchemaInspection.stderr, /failedTarballName must match diagnostics and retained manifest/);
    assert.match(invalidDiagnosticsRetentionSchemaInspection.stderr, /runId must match retained manifest provenance/);
    assert.match(invalidDiagnosticsRetentionSchemaInspection.stderr, /reviewedBy must identify the maintainer who reviewed diagnostics retention/);
    await cp(join(ciPackageReleaseFixturesDir, "jury-package-release-replay-summary-diagnostics-retention-handoff.json"), retainedDiagnosticsRetentionHandoffPath);

    const replaySummaryRetentionCommands = extractShellBlock(guide, "Replay Summary Retention Failure");
    assert.deepEqual(replaySummaryRetentionCommands, [
      'node -e \'const fs=require("node:fs"); const summaryPath=process.argv[1]; if (!fs.existsSync(summaryPath)) throw new Error("jury-package-release-replay-summary.md must be promoted before the 90-day artifact expiry"); const summary=fs.readFileSync(summaryPath,"utf8"); if (!summary.includes("### Jury package release replay")) throw new Error("jury-package-release-replay-summary.md missing Jury package release replay heading"); console.log(JSON.stringify({ok:true, summaryPath}, null, 2));\' <summary-file>',
      'node -e \'const fs=require("node:fs"); const manifest=JSON.parse(fs.readFileSync(process.argv[1],"utf8")); const artifact=(manifest.provenance?.artifacts??[]).find((item)=>item.name==="jury-package-release-replay-summary"); const errors=[]; if (!manifest.retention?.artifacts?.includes("jury-package-release-replay-summary")) errors.push("retention.artifacts missing jury-package-release-replay-summary"); if (!manifest.retention?.artifacts?.includes("jury-package-release-replay-summary.md")) errors.push("retention.artifacts missing jury-package-release-replay-summary.md"); if (!artifact) errors.push("provenance.artifacts missing jury-package-release-replay-summary"); if (artifact?.sourceJob!=="package-release-evidence-replay") errors.push("jury-package-release-replay-summary sourceJob must be package-release-evidence-replay"); if (artifact?.retentionDays!==90) errors.push("jury-package-release-replay-summary retentionDays must be 90"); if (!artifact?.files?.includes("jury-package-release-replay-summary.md")) errors.push("jury-package-release-replay-summary files must include jury-package-release-replay-summary.md"); if (errors.length) throw new Error(`replay summary retention incomplete: ${errors.join("; ")}`); console.log(JSON.stringify({ok:true, artifact}, null, 2));\' <retained-manifest>',
      'node -e \'const fs=require("node:fs"); const dir=process.argv[1]; const manifest=JSON.parse(fs.readFileSync(process.argv[2],"utf8")); const summary=fs.readFileSync(process.argv[3],"utf8"); const remediation=JSON.parse(fs.readFileSync(`${dir}/archive-drift-remediation-audit.json`,"utf8")); const expected=[`- failedPackageVersion: ${manifest.failed.packageVersion}`,`- failedTarballName: ${manifest.failed.tarballName}`,`- replacementPackageVersion: ${manifest.replacement.packageVersion}`,`- failedArchiveEvidence: ${remediation.failed.archiveEvidence.join(", ")}`,`- replacementArchiveEvidence: ${remediation.replacement.archiveEvidence.join(", ")}`,`- remediationApprovedBy: ${remediation.approval.approvedBy}`]; const missing=expected.filter((line)=>!summary.includes(line)); if (missing.length) throw new Error(`retained replay summary no longer matches retained archive evidence: ${missing.join(", ")}`); console.log(JSON.stringify({ok:true, checked:expected}, null, 2));\' <retained-evidence-dir> <retained-manifest> <summary-file>',
    ]);
    const retainedSummaryCommand = (command) => retainedCommand(command).replaceAll("<summary-file>", shellQuote(replaySummaryPath));
    const retainedSummaryExists = await runShell(retainedSummaryCommand(replaySummaryRetentionCommands[0]));
    assert.equal(retainedSummaryExists.exitCode, 0, retainedSummaryExists.stderr);
    assert.equal(JSON.parse(retainedSummaryExists.stdout).ok, true);
    const retainedSummaryProvenance = await runShell(retainedSummaryCommand(replaySummaryRetentionCommands[1]));
    assert.equal(retainedSummaryProvenance.exitCode, 0, retainedSummaryProvenance.stderr);
    assert.equal(JSON.parse(retainedSummaryProvenance.stdout).artifact.name, "jury-package-release-replay-summary");
    const retainedSummaryContent = await runShell(retainedSummaryCommand(replaySummaryRetentionCommands[2]));
    assert.equal(retainedSummaryContent.exitCode, 0, retainedSummaryContent.stderr);
    assert.equal(JSON.parse(retainedSummaryContent.stdout).ok, true);

    const missingRetainedSummary = await runShell(retainedSummaryCommand(replaySummaryRetentionCommands[0]).replace(shellQuote(replaySummaryPath), shellQuote(join(manifestReplayRoot, "missing-summary.md"))));
    assert.equal(missingRetainedSummary.exitCode, 1);
    assert.match(missingRetainedSummary.stderr, /jury-package-release-replay-summary\.md must be promoted before the 90-day artifact expiry/);

    const missingSummaryProvenanceManifestPath = join(manifestReplayRoot, "missing-summary-provenance-manifest.json");
    const missingSummaryProvenanceManifest = JSON.parse(await readFile(retainedManifestPath, "utf8"));
    missingSummaryProvenanceManifest.provenance.artifacts = missingSummaryProvenanceManifest.provenance.artifacts.filter((artifact) => artifact.name !== "jury-package-release-replay-summary");
    await writeFile(missingSummaryProvenanceManifestPath, `${JSON.stringify(missingSummaryProvenanceManifest, null, 2)}\n`);
    const missingSummaryProvenance = await runShell(retainedSummaryCommand(replaySummaryRetentionCommands[1]).replace(shellQuote(retainedManifestPath), shellQuote(missingSummaryProvenanceManifestPath)));
    assert.equal(missingSummaryProvenance.exitCode, 1);
    assert.match(missingSummaryProvenance.stderr, /replay summary retention incomplete: provenance\.artifacts missing jury-package-release-replay-summary/);

    const wrongSummarySourceJobManifestPath = join(manifestReplayRoot, "wrong-summary-source-job-manifest.json");
    const wrongSummarySourceJobManifest = JSON.parse(await readFile(retainedManifestPath, "utf8"));
    wrongSummarySourceJobManifest.provenance.artifacts.find((artifact) => artifact.name === "jury-package-release-replay-summary").sourceJob = "package-release-fixtures";
    await writeFile(wrongSummarySourceJobManifestPath, `${JSON.stringify(wrongSummarySourceJobManifest, null, 2)}\n`);
    const wrongSummarySourceJob = await runShell(retainedSummaryCommand(replaySummaryRetentionCommands[1]).replace(shellQuote(retainedManifestPath), shellQuote(wrongSummarySourceJobManifestPath)));
    assert.equal(wrongSummarySourceJob.exitCode, 1);
    assert.match(wrongSummarySourceJob.stderr, /jury-package-release-replay-summary sourceJob must be package-release-evidence-replay/);

    const wrongSummaryRetentionDaysManifestPath = join(manifestReplayRoot, "wrong-summary-retention-days-manifest.json");
    const wrongSummaryRetentionDaysManifest = JSON.parse(await readFile(retainedManifestPath, "utf8"));
    wrongSummaryRetentionDaysManifest.provenance.artifacts.find((artifact) => artifact.name === "jury-package-release-replay-summary").retentionDays = 7;
    await writeFile(wrongSummaryRetentionDaysManifestPath, `${JSON.stringify(wrongSummaryRetentionDaysManifest, null, 2)}\n`);
    const wrongSummaryRetentionDays = await runShell(retainedSummaryCommand(replaySummaryRetentionCommands[1]).replace(shellQuote(retainedManifestPath), shellQuote(wrongSummaryRetentionDaysManifestPath)));
    assert.equal(wrongSummaryRetentionDays.exitCode, 1);
    assert.match(wrongSummaryRetentionDays.stderr, /jury-package-release-replay-summary retentionDays must be 90/);

    const missingSummaryRetentionArtifactManifestPath = join(manifestReplayRoot, "missing-summary-retention-artifact-manifest.json");
    const missingSummaryRetentionArtifactManifest = JSON.parse(await readFile(retainedManifestPath, "utf8"));
    missingSummaryRetentionArtifactManifest.retention.artifacts = missingSummaryRetentionArtifactManifest.retention.artifacts.filter((artifact) => artifact !== "jury-package-release-replay-summary.md");
    await writeFile(missingSummaryRetentionArtifactManifestPath, `${JSON.stringify(missingSummaryRetentionArtifactManifest, null, 2)}\n`);
    const missingSummaryRetentionArtifact = await runShell(retainedSummaryCommand(replaySummaryRetentionCommands[1]).replace(shellQuote(retainedManifestPath), shellQuote(missingSummaryRetentionArtifactManifestPath)));
    assert.equal(missingSummaryRetentionArtifact.exitCode, 1);
    assert.match(missingSummaryRetentionArtifact.stderr, /retention\.artifacts missing jury-package-release-replay-summary\.md/);

    await writeFile(replaySummaryPath, [
      "### Jury package release replay",
      "",
      "- failedPackageVersion: 0.1.0",
      "- failedTarballName: sanogueralorenzo-jury-0.1.0.tgz",
      "- replacementPackageVersion: 0.1.2",
      "- failedArchiveEvidence: downstream-failure-gate.json, failed-npm-view.json, rollback-audit.json",
      "- replacementArchiveEvidence: replacement-downstream-gate.json, replacement-npm-view.json, replacement-patch-audit.json",
      "- remediationApprovedBy: release-maintainer@example.com",
      "",
    ].join("\n"));
    const driftedRetainedSummaryContent = await runShell(retainedSummaryCommand(replaySummaryRetentionCommands[2]));
    assert.equal(driftedRetainedSummaryContent.exitCode, 1);
    assert.match(driftedRetainedSummaryContent.stderr, /retained replay summary no longer matches retained archive evidence: - replacementPackageVersion: 0\.1\.1/);

    const replaySummaryExpiryCommands = extractShellBlock(guide, "Replay Summary Artifact Expiry Remediation Handoff");
    assert.deepEqual(replaySummaryExpiryCommands, [
      'node -e \'const fs=require("node:fs"); const dir=process.argv[1]; const manifest=JSON.parse(fs.readFileSync(process.argv[2],"utf8")); const summaryPath=process.argv[3]; const remediation=JSON.parse(fs.readFileSync(`${dir}/archive-drift-remediation-audit.json`,"utf8")); const summary=`### Jury package release replay\\n\\n- failedPackageVersion: ${manifest.failed.packageVersion}\\n- failedTarballName: ${manifest.failed.tarballName}\\n- replacementPackageVersion: ${manifest.replacement.packageVersion}\\n- failedArchiveEvidence: ${remediation.failed.archiveEvidence.join(", ")}\\n- replacementArchiveEvidence: ${remediation.replacement.archiveEvidence.join(", ")}\\n- remediationApprovedBy: ${remediation.approval.approvedBy}\\n`; fs.writeFileSync(summaryPath, summary); console.log(JSON.stringify({ok:true, summaryPath}, null, 2));\' <retained-evidence-dir> <retained-manifest> <summary-file>',
      'node -e \'const fs=require("node:fs"); const dir=process.argv[1]; const manifest=JSON.parse(fs.readFileSync(process.argv[2],"utf8")); const summary=fs.readFileSync(process.argv[3],"utf8"); const remediation=JSON.parse(fs.readFileSync(`${dir}/archive-drift-remediation-audit.json`,"utf8")); const expected=[`- failedPackageVersion: ${manifest.failed.packageVersion}`,`- failedTarballName: ${manifest.failed.tarballName}`,`- replacementPackageVersion: ${manifest.replacement.packageVersion}`,`- failedArchiveEvidence: ${remediation.failed.archiveEvidence.join(", ")}`,`- replacementArchiveEvidence: ${remediation.replacement.archiveEvidence.join(", ")}`,`- remediationApprovedBy: ${remediation.approval.approvedBy}`]; const missing=expected.filter((line)=>!summary.includes(line)); if (missing.length) throw new Error(`reconstructed replay summary missing retained archive evidence: ${missing.join(", ")}`); console.log(JSON.stringify({ok:true, checked:expected}, null, 2));\' <retained-evidence-dir> <retained-manifest> <summary-file>',
      'node -e \'const fs=require("node:fs"); const path=require("node:path"); const dir=process.argv[1]; const manifest=JSON.parse(fs.readFileSync(process.argv[2],"utf8")); const summaryPath=process.argv[3]; const handoffPath=process.argv[4]; const reviewedBy=(process.env.JURY_REPLAY_SUMMARY_REMEDIATION_REVIEWER||"").trim(); if (!fs.existsSync(summaryPath)) throw new Error("reconstructed replay summary file must exist before writing expiry handoff"); const summary=fs.readFileSync(summaryPath,"utf8"); const remediation=JSON.parse(fs.readFileSync(`${dir}/archive-drift-remediation-audit.json`,"utf8")); const expected=["### Jury package release replay",`- failedPackageVersion: ${manifest.failed.packageVersion}`,`- failedTarballName: ${manifest.failed.tarballName}`,`- replacementPackageVersion: ${manifest.replacement.packageVersion}`,`- failedArchiveEvidence: ${remediation.failed.archiveEvidence.join(", ")}`,`- replacementArchiveEvidence: ${remediation.replacement.archiveEvidence.join(", ")}`,`- remediationApprovedBy: ${remediation.approval.approvedBy}`]; const missing=expected.filter((line)=>!summary.includes(line)); if (missing.length) throw new Error(`reconstructed replay summary must be verified before writing expiry handoff: ${missing.join(", ")}`); if (!reviewedBy) throw new Error("JURY_REPLAY_SUMMARY_REMEDIATION_REVIEWER must identify who reviewed replay summary expiry remediation"); const handoff={schema_version:"jury.package_release_replay_summary_expiry_handoff.v1",reason:"jury-package-release-replay-summary artifact expired before promotion",sourceArtifact:"jury-package-release-replay-summary",expiredAfterDays:90,reconstructedSummary:path.basename(summaryPath),reconstructedFrom:["retained-package-release-evidence-manifest.json","archive-drift-remediation-audit.json"],failedPackageVersion:manifest.failed.packageVersion,replacementPackageVersion:manifest.replacement.packageVersion,reviewedBy}; fs.writeFileSync(handoffPath, `${JSON.stringify(handoff,null,2)}\\n`); console.log(JSON.stringify({ok:true,handoffPath,reviewedBy}, null, 2));\' <retained-evidence-dir> <retained-manifest> <summary-file> <handoff-file>',
    ]);
    const reconstructedSummaryPath = join(manifestReplayRoot, "jury-package-release-replay-summary.md");
    const expiryHandoffPath = join(manifestReplayRoot, "jury-package-release-replay-summary-expiry-handoff.json");
    const expiryCommand = (command) => retainedCommand(command)
      .replaceAll("<summary-file>", shellQuote(reconstructedSummaryPath))
      .replaceAll("<handoff-file>", shellQuote(expiryHandoffPath));
    const expiryCommandWithSummary = (command, summaryPath) => retainedCommand(command)
      .replaceAll("<summary-file>", shellQuote(summaryPath))
      .replaceAll("<handoff-file>", shellQuote(expiryHandoffPath));
    const reconstructedSummary = await runShell(expiryCommand(replaySummaryExpiryCommands[0]));
    assert.equal(reconstructedSummary.exitCode, 0, reconstructedSummary.stderr);
    assert.equal(JSON.parse(reconstructedSummary.stdout).ok, true);
    const reconstructedSummaryCheck = await runShell(expiryCommand(replaySummaryExpiryCommands[1]));
    assert.equal(reconstructedSummaryCheck.exitCode, 0, reconstructedSummaryCheck.stderr);
    assert.equal(JSON.parse(reconstructedSummaryCheck.stdout).ok, true);
    const missingExpiryReviewer = await runShell(expiryCommand(replaySummaryExpiryCommands[2]));
    assert.equal(missingExpiryReviewer.exitCode, 1);
    assert.match(missingExpiryReviewer.stderr, /JURY_REPLAY_SUMMARY_REMEDIATION_REVIEWER must identify who reviewed/);
    const missingExpirySummary = await runShell(expiryCommandWithSummary(
      replaySummaryExpiryCommands[2],
      join(manifestReplayRoot, "missing-jury-package-release-replay-summary.md"),
    ), repoRoot, {
      ...fixedEnv,
      JURY_REPLAY_SUMMARY_REMEDIATION_REVIEWER: "release-owner",
    });
    assert.equal(missingExpirySummary.exitCode, 1);
    assert.match(missingExpirySummary.stderr, /reconstructed replay summary file must exist before writing expiry handoff/);
    await writeFile(reconstructedSummaryPath, [
      "### Jury package release replay",
      "",
      "- failedPackageVersion: 0.1.0",
      "- failedTarballName: sanogueralorenzo-jury-0.1.0.tgz",
      "- replacementPackageVersion: 0.1.2",
      "- failedArchiveEvidence: downstream-failure-gate.json, failed-npm-view.json, rollback-audit.json",
      "- replacementArchiveEvidence: replacement-downstream-gate.json, replacement-npm-view.json, replacement-patch-audit.json",
      "- remediationApprovedBy: release-maintainer@example.com",
      "",
    ].join("\n"));
    const unverifiedExpirySummary = await runShell(expiryCommand(replaySummaryExpiryCommands[2]), repoRoot, {
      ...fixedEnv,
      JURY_REPLAY_SUMMARY_REMEDIATION_REVIEWER: "release-owner",
    });
    assert.equal(unverifiedExpirySummary.exitCode, 1);
    assert.match(unverifiedExpirySummary.stderr, /reconstructed replay summary must be verified before writing expiry handoff: - replacementPackageVersion: 0\.1\.1/);
    const restoredSummary = await runShell(expiryCommand(replaySummaryExpiryCommands[0]));
    assert.equal(restoredSummary.exitCode, 0, restoredSummary.stderr);
    const expiryHandoff = await runShell(expiryCommand(replaySummaryExpiryCommands[2]), repoRoot, {
      ...fixedEnv,
      JURY_REPLAY_SUMMARY_REMEDIATION_REVIEWER: "release-owner",
    });
    assert.equal(expiryHandoff.exitCode, 0, expiryHandoff.stderr);
    const expiryHandoffRecord = JSON.parse(await readFile(expiryHandoffPath, "utf8"));
    assert.deepEqual(expiryHandoffRecord, {
      schema_version: "jury.package_release_replay_summary_expiry_handoff.v1",
      reason: "jury-package-release-replay-summary artifact expired before promotion",
      sourceArtifact: "jury-package-release-replay-summary",
      expiredAfterDays: 90,
      reconstructedSummary: "jury-package-release-replay-summary.md",
      reconstructedFrom: ["retained-package-release-evidence-manifest.json", "archive-drift-remediation-audit.json"],
      failedPackageVersion: "0.1.0",
      replacementPackageVersion: "0.1.1",
      reviewedBy: "release-owner",
    });

    const replaySummaryExpirySchemaCommands = extractShellBlock(guide, "Replay Summary Expiry Handoff Schema Failure");
    assert.deepEqual(replaySummaryExpirySchemaCommands, [
      "npm --prefix jury run fixtures:package-release:check -- --fixture-dir <retained-evidence-dir>",
      'node -e \'const fs=require("node:fs"); const dir=process.argv[1]; const handoff=JSON.parse(fs.readFileSync(`${dir}/jury-package-release-replay-summary-expiry-handoff.json`,"utf8")); const manifest=JSON.parse(fs.readFileSync(process.argv[2],"utf8")); const remediation=JSON.parse(fs.readFileSync(`${dir}/archive-drift-remediation-audit.json`,"utf8")); const requiredFrom=["retained-package-release-evidence-manifest.json","archive-drift-remediation-audit.json"]; const errors=[]; if (handoff.schema_version!=="jury.package_release_replay_summary_expiry_handoff.v1") errors.push("schema_version must equal jury.package_release_replay_summary_expiry_handoff.v1"); if (handoff.reason!=="jury-package-release-replay-summary artifact expired before promotion") errors.push("reason must explain replay summary artifact expiry before promotion"); if (handoff.sourceArtifact!=="jury-package-release-replay-summary") errors.push("sourceArtifact must be jury-package-release-replay-summary"); if (handoff.expiredAfterDays!==90) errors.push("expiredAfterDays must equal 90"); if (handoff.reconstructedSummary!=="jury-package-release-replay-summary.md") errors.push("reconstructedSummary must be jury-package-release-replay-summary.md"); for (const item of requiredFrom) if (!(handoff.reconstructedFrom??[]).includes(item)) errors.push(`reconstructedFrom missing ${item}`); if (handoff.failedPackageVersion!==manifest.failed?.packageVersion) errors.push("failedPackageVersion must match retained manifest failed packageVersion"); if (handoff.replacementPackageVersion!==manifest.replacement?.packageVersion) errors.push("replacementPackageVersion must match retained manifest replacement packageVersion"); if (!handoff.reviewedBy) errors.push("reviewedBy must identify the maintainer who reviewed expiry remediation"); if (handoff.reviewedBy!==remediation.approval?.approvedBy) errors.push("reviewedBy must match archive drift remediation approver"); if (errors.length) throw new Error(`replay summary expiry handoff schema failure: ${errors.join("; ")}`); console.log(JSON.stringify({ok:true, failedPackageVersion:handoff.failedPackageVersion, replacementPackageVersion:handoff.replacementPackageVersion, reviewedBy:handoff.reviewedBy}, null, 2));\' <retained-evidence-dir> <retained-manifest>',
    ]);
    const expirySchemaReplay = await runShell(retainedCommand(replaySummaryExpirySchemaCommands[0]));
    assert.equal(expirySchemaReplay.exitCode, 0, expirySchemaReplay.stderr);
    const expirySchemaInspection = await runShell(retainedCommand(replaySummaryExpirySchemaCommands[1]));
    assert.equal(expirySchemaInspection.exitCode, 0, expirySchemaInspection.stderr);
    assert.deepEqual(JSON.parse(expirySchemaInspection.stdout), {
      ok: true,
      failedPackageVersion: "0.1.0",
      replacementPackageVersion: "0.1.1",
      reviewedBy: "release-maintainer@example.com",
    });
    const retainedExpiryHandoffPath = join(retainedEvidenceDir, "jury-package-release-replay-summary-expiry-handoff.json");
    const retainedExpiryHandoff = JSON.parse(await readFile(retainedExpiryHandoffPath, "utf8"));
    retainedExpiryHandoff.schema_version = "jury.package_release_replay_summary_expiry_handoff.invalid";
    retainedExpiryHandoff.reason = "temporary artifact was not promoted";
    retainedExpiryHandoff.expiredAfterDays = 30;
    retainedExpiryHandoff.reconstructedFrom = ["archive-drift-remediation-audit.json"];
    retainedExpiryHandoff.replacementPackageVersion = "0.1.2";
    retainedExpiryHandoff.reviewedBy = "";
    await writeFile(retainedExpiryHandoffPath, `${JSON.stringify(retainedExpiryHandoff, null, 2)}\n`);
    const invalidExpirySchemaReplay = await runShell(retainedCommand(replaySummaryExpirySchemaCommands[0]));
    assert.equal(invalidExpirySchemaReplay.exitCode, 1);
    assert.match(invalidExpirySchemaReplay.stderr, /jury-package-release-replay-summary-expiry-handoff\.json\.schema_version must equal jury\.package_release_replay_summary_expiry_handoff\.v1/);
    assert.match(invalidExpirySchemaReplay.stderr, /jury-package-release-replay-summary-expiry-handoff\.json\.expiredAfterDays must equal 90/);
    assert.match(invalidExpirySchemaReplay.stderr, /jury-package-release-replay-summary-expiry-handoff\.json\.reviewedBy must not be empty/);
    const invalidExpirySchemaInspection = await runShell(retainedCommand(replaySummaryExpirySchemaCommands[1]));
    assert.equal(invalidExpirySchemaInspection.exitCode, 1);
    assert.match(invalidExpirySchemaInspection.stderr, /replay summary expiry handoff schema failure: schema_version must equal jury\.package_release_replay_summary_expiry_handoff\.v1/);
    assert.match(invalidExpirySchemaInspection.stderr, /reason must explain replay summary artifact expiry before promotion/);
    assert.match(invalidExpirySchemaInspection.stderr, /expiredAfterDays must equal 90/);
    assert.match(invalidExpirySchemaInspection.stderr, /reconstructedFrom missing retained-package-release-evidence-manifest\.json/);
    assert.match(invalidExpirySchemaInspection.stderr, /replacementPackageVersion must match retained manifest replacement packageVersion/);
    assert.match(invalidExpirySchemaInspection.stderr, /reviewedBy must identify the maintainer who reviewed expiry remediation/);
    await cp(join(ciPackageReleaseFixturesDir, "jury-package-release-replay-summary-expiry-handoff.json"), retainedExpiryHandoffPath);

    const replaySummaryExpiryCiReplayCommands = extractShellBlock(guide, "Replay Summary Expiry Handoff CI Workflow Enforcement Failure");
    assert.equal(replaySummaryExpiryCiReplayCommands.length, 2);
    const replaySummaryExpiryWorkflowOrdering = await runShell(replaySummaryExpiryCiReplayCommands[0]);
    assert.equal(replaySummaryExpiryWorkflowOrdering.exitCode, 0, replaySummaryExpiryWorkflowOrdering.stderr);
    assert.equal(JSON.parse(replaySummaryExpiryWorkflowOrdering.stdout).step, "Replay Jury package release replay summary expiry handoff");
    assert.equal(JSON.parse(replaySummaryExpiryWorkflowOrdering.stdout).dryRunNeeds, "package-release-evidence-replay");
    const missingReplaySummaryExpiryWorkflowPath = join(manifestReplayRoot, "missing-replay-summary-expiry-workflow.yml");
    const missingReplaySummaryExpiryWorkflow = (await readFile(join(repoRoot, "jury/examples/ci/jury-npm-publish.yml"), "utf8"))
      .replace("Replay Jury package release replay summary expiry handoff", "Replay Jury package release replay summary expiry handoff disabled");
    await writeFile(missingReplaySummaryExpiryWorkflowPath, missingReplaySummaryExpiryWorkflow);
    const missingReplaySummaryExpiryWorkflowOrdering = await runShell(
      replaySummaryExpiryCiReplayCommands[0].replace("jury/examples/ci/jury-npm-publish.yml", shellQuote(missingReplaySummaryExpiryWorkflowPath)),
    );
    assert.equal(missingReplaySummaryExpiryWorkflowOrdering.exitCode, 1);
    assert.match(missingReplaySummaryExpiryWorkflowOrdering.stderr, /Replay Jury package release replay summary expiry handoff step is missing/);
    const expiryCiReplayCommand = (command) => retainedCommand(command)
      .replaceAll("<summary-file>", shellQuote(reconstructedSummaryPath));
    const replaySummaryExpiryCiReplay = await runShell(expiryCiReplayCommand(replaySummaryExpiryCiReplayCommands[1]));
    assert.equal(replaySummaryExpiryCiReplay.exitCode, 0, replaySummaryExpiryCiReplay.stderr);
    assert.equal(JSON.parse(replaySummaryExpiryCiReplay.stdout).reviewedBy, "release-maintainer@example.com");
    const invalidExpiryCiHandoff = JSON.parse(await readFile(retainedExpiryHandoffPath, "utf8"));
    invalidExpiryCiHandoff.reviewedBy = "different-maintainer@example.com";
    await writeFile(retainedExpiryHandoffPath, `${JSON.stringify(invalidExpiryCiHandoff, null, 2)}\n`);
    const invalidReplaySummaryExpiryCiReplay = await runShell(expiryCiReplayCommand(replaySummaryExpiryCiReplayCommands[1]));
    assert.equal(invalidReplaySummaryExpiryCiReplay.exitCode, 1);
    assert.match(invalidReplaySummaryExpiryCiReplay.stderr, /replay summary expiry handoff CI workflow enforcement failed: reviewedBy must match archive drift remediation approver/);
    await cp(join(ciPackageReleaseFixturesDir, "jury-package-release-replay-summary-expiry-handoff.json"), retainedExpiryHandoffPath);

    const manifest = JSON.parse(await readFile(retainedManifestPath, "utf8"));
    manifest.retention.artifacts = manifest.retention.artifacts.filter((artifact) => artifact !== "replacement-patch-audit.json");
    await writeFile(retainedManifestPath, `${JSON.stringify(manifest, null, 2)}\n`);
    const missingArchiveCheck = await runShell(retainedCommand(retainedManifestCommands[4]));
    assert.equal(missingArchiveCheck.exitCode, 1);
    assert.match(missingArchiveCheck.stderr, /missing retained archive evidence: retention=replacement-patch-audit\.json provenance=none/);

    await rm(join(retainedEvidenceDir, "failed-npm-view.json"));
    const missingFailedNpmViewCheck = await runShell(retainedCommand(retainedManifestCommands[2]));
    assert.equal(missingFailedNpmViewCheck.exitCode, 1);
    assert.match(missingFailedNpmViewCheck.stderr, /missing retained package release evidence files: failed-npm-view\.json/);

    await rm(join(retainedEvidenceDir, "replacement-patch-audit.json"));
    const missingRetainedFileReplay = await runShell(retainedCommand(retainedManifestCommands[0]));
    assert.equal(missingRetainedFileReplay.exitCode, 1);
    assert.match(missingRetainedFileReplay.stderr, /replacement-patch-audit\.json is required in package release evidence directory/);
    assert.doesNotMatch(missingRetainedFileReplay.stderr, /ENOENT/);
  } finally {
    await rm(manifestReplayRoot, { recursive: true, force: true });
  }

  const dryRunArtifactCommands = extractShellBlock(guide, "Dry-Run Publication Artifact Failure");
  assert.equal(dryRunArtifactCommands.length, 1);
  const checkout = await copyJuryCheckout();
  try {
    await writeFile(join(checkout, "jury-pack-dry-run-record.json"), JSON.stringify({
      packageVersion: "0.1.0",
      tarballName: "sanogueralorenzo-jury-0.1.0.tgz",
    }));
    const validRecord = await runShell(dryRunArtifactCommands[0], checkout);
    assert.equal(validRecord.exitCode, 0, validRecord.stderr);
    assert.deepEqual(JSON.parse(validRecord.stdout), {
      packageVersion: "0.1.0",
      tarballName: "sanogueralorenzo-jury-0.1.0.tgz",
    });

    await writeFile(join(checkout, "jury-pack-dry-run-record.json"), JSON.stringify({
      packageVersion: "0.0.0",
      tarballName: "sanogueralorenzo-jury-0.0.0.tgz",
    }));
    const staleRecord = await runShell(dryRunArtifactCommands[0], checkout);
    assert.equal(staleRecord.exitCode, 1);
    assert.match(staleRecord.stderr, /packageVersion 0\.0\.0 did not match 0\.1\.0/);
  } finally {
    await rm(checkout, { recursive: true, force: true });
  }

  const publishedFailureCommands = extractShellBlock(guide, "Published Package Verification Failure");
  assert.deepEqual(publishedFailureCommands, [
    "npm view @sanogueralorenzo/jury@<packageVersion> version dist.tarball --json",
    'npm deprecate @sanogueralorenzo/jury@<packageVersion> "Downstream Jury verification failed; use a later patch release."',
  ]);
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
  assert.equal(packageJson.private, true);
  assert.equal(packageJson.scripts["package:manifest:check"], "node scripts/check-package-manifest.mjs");
  assert.equal(packageJson.scripts["fixtures:package-release:check"], "node scripts/validate-package-release-fixtures.mjs");
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

  const guide = await readFile(join(repoRoot, "jury", release.ciAdoption.guide), "utf8");
  assert.ok(guide.includes("release.json"));
  assert.deepEqual(
    release.ciAdoption.workflows.map((workflow) => workflow.variant),
    [
      "unsigned-single-job",
      "signed-producer",
      "signed-artifact-handoff",
      "reusable-downstream-verifier",
      "reusable-code-change-adoption",
    ],
  );

  for (const workflow of release.ciAdoption.workflows) {
    assert.match(workflow.path, /^examples\/ci\/.+\.yml$/);
    const workflowYaml = await readFile(join(repoRoot, "jury", workflow.path), "utf8");
    assert.ok(guide.includes(workflow.path), `CI_ADOPTION.md should mention ${workflow.path}`);
    assert.ok(workflow.trustBoundary.length > 0, `${workflow.variant} must define a trust boundary`);
    assert.ok(workflow.artifacts.length > 0, `${workflow.variant} must list artifacts`);
    for (const artifactName of workflow.artifacts) {
      assert.ok(guide.includes(artifactName), `CI_ADOPTION.md should mention ${artifactName}`);
    }

    const uploadPaths = extractWorkflowUploadPaths(workflowYaml);
    if (workflow.variant === "reusable-downstream-verifier") {
      const defaults = extractWorkflowCallInputDefaults(workflowYaml);
      const defaultArtifacts = [
        defaults.get("verdict-out"),
        defaults.get("gate-out"),
        `${defaults.get("state-dir")}/*.jsonl`,
      ];

      assert.deepEqual(new Set(workflow.artifacts), new Set(defaultArtifacts));
      assert.deepEqual(new Set(uploadPaths), new Set([
        "${{ inputs.verdict-out }}",
        "${{ inputs.gate-out }}",
        "${{ inputs.state-dir }}/*.jsonl",
      ]));
    } else {
      assert.deepEqual(new Set(workflow.artifacts), new Set(uploadPaths));
    }
  }

  const publicationNotesPath = join(repoRoot, "jury", release.packagePublication.notes);
  const publicationNotes = await readFile(publicationNotesPath, "utf8");
  await stat(join(repoRoot, "jury", release.packagePublication.workflow));
  await stat(join(repoRoot, "jury", release.packagePublication.releaseWorkflow));
  assert.ok(publicationNotes.includes("private: true"));
  assert.ok(publicationNotes.includes("ciAdoption"));
  assert.ok(publicationNotes.includes(release.packagePublication.workflow));
  assert.ok(publicationNotes.includes(release.packagePublication.releaseWorkflow));
  assert.ok(publicationNotes.includes(release.packagePublication.manifestCheckCommand));
  assert.ok(publicationNotes.includes(release.packagePublication.packDryRunCommand));
  assert.ok(publicationNotes.includes("npm --prefix jury run fixtures:package-release:check"));
  assert.ok(publicationNotes.includes("jury-package-release-archive-manifest"));
  assert.ok(publicationNotes.includes("jury-package-release-replay-summary"));
  assert.ok(publicationNotes.includes("jury-package-release-replay-summary.md"));
  assert.ok(publicationNotes.includes("jury-package-release-replay-summary-diagnostics.json"));
  assert.ok(publicationNotes.includes("jury-package-release-replay-summary-diagnostics-retention-handoff.json"));
  assert.ok(publicationNotes.includes("jury-package-release-replay-summary-expiry-handoff.json"));
  assert.ok(publicationNotes.includes("schemas/package-release-replay-summary-diagnostics.schema.json"));
  assert.ok(publicationNotes.includes("schemas/package-release-replay-summary-diagnostics-retention-handoff.schema.json"));
  assert.ok(publicationNotes.includes("replay summary CI workflow diagnostics failure"));
  assert.ok(publicationNotes.includes("replay summary diagnostics retention handoff failure"));
  assert.ok(publicationNotes.includes("remediation audit handoff CI workflow enforcement"));
  assert.ok(publicationNotes.includes("replay summary diagnostics retention handoff CI replay enforcement failure"));
  assert.ok(publicationNotes.includes("replay summary expiry handoff CI workflow enforcement failure"));
  assert.ok(publicationNotes.includes("replays `jury-package-release-replay-summary-expiry-handoff.json`"));
  assert.ok(publicationNotes.includes("replay summary diagnostics retention handoff schema failure"));
  assert.ok(publicationNotes.includes("replays that generated handoff against the retained manifest"));
  assert.ok(publicationNotes.includes("replays `archive-drift-remediation-audit-handoff.json` against the retained manifest and remediation audit"));
  assert.ok(publicationNotes.includes("replay summary retention failure"));
  assert.ok(publicationNotes.includes("jury.package_release_replay_summary_expiry_handoff.v1"));
  assert.ok(publicationNotes.includes("schemas/package-release-replay-summary-expiry-handoff.schema.json"));
  assert.ok(publicationNotes.includes('JURY_PACKAGE_RELEASE_MANIFEST_PATH'));
  assert.ok(publicationNotes.includes("Dry-Run Publication Record"));
  assert.ok(publicationNotes.includes("jury-pack-dry-run.json"));
  assert.ok(publicationNotes.includes("jury-pack-dry-run-record.json"));
  assert.ok(publicationNotes.includes("jury-package-dry-run"));
  assert.ok(publicationNotes.includes("retention-days: 90"));
  assert.ok(publicationNotes.includes("90 days"));
  assert.ok(publicationNotes.includes("Release Evidence Retention Policy"));
  assert.ok(publicationNotes.includes("release record or incident archive"));
  assert.ok(publicationNotes.includes("180 days after replacement downstream verification passes"));
  assert.ok(publicationNotes.includes("artifact provenance"));
  assert.ok(publicationNotes.includes("github-actions"));
  assert.ok(publicationNotes.includes("jury-npm-publish.yml"));
  assert.ok(publicationNotes.includes("source revision"));
  assert.ok(publicationNotes.includes("run id"));
  assert.ok(publicationNotes.includes("retentionDays: 90"));
  assert.ok(publicationNotes.includes("--manifest-out retained-package-release-evidence-manifest.json"));
  assert.ok(publicationNotes.includes("--verify-manifest retained-package-release-evidence-manifest.json"));
  assert.ok(publicationNotes.includes("npm --prefix jury run fixtures:package-release:drift"));
  assert.ok(publicationNotes.includes("fails when the rollback audit, replacement audit, dry-run record, npm metadata, downstream gates, retention policy, artifact provenance, or archive evidence digest changes"));
  assert.ok(publicationNotes.includes("retained package release archive drift remediation section"));
  assert.ok(publicationNotes.includes("restore missing or changed archive evidence first"));
  assert.ok(publicationNotes.includes("record the approving maintainer before replacing the archived copy"));
  assert.ok(publicationNotes.includes("archive-drift-remediation-audit.json"));
  assert.ok(publicationNotes.includes("archive-drift-remediation-audit-handoff.json"));
  assert.ok(publicationNotes.includes("schemas/package-release-remediation-audit.schema.json"));
  assert.ok(publicationNotes.includes("schemas/package-release-remediation-audit-handoff.schema.json"));
  assert.ok(publicationNotes.includes("jury.package_release_archive_manifest.v1"));
  assert.ok(publicationNotes.includes("schemas/package-release-archive-manifest.schema.json"));
  assert.ok(publicationNotes.includes("dry-run-publication"));
  assert.ok(publicationNotes.includes("package-release-fixtures"));
  assert.ok(publicationNotes.includes("before any publication dry run"));
  assert.ok(publicationNotes.includes("jury-package-release-evidence"));
  assert.ok(publicationNotes.includes("retained-package-release-evidence-manifest.json"));
  assert.ok(publicationNotes.includes("examples/ci/fixtures/package-release/retained-package-release-evidence-manifest.json"));
  assert.ok(publicationNotes.includes("checked-in release archive fixture"));
  assert.ok(publicationNotes.includes("rollback and replacement audit examples"));
  assert.ok(publicationNotes.includes("package-release-evidence-replay"));
  assert.ok(publicationNotes.includes("failed package version, failed tarball name, replacement package version, failed archive evidence, replacement archive evidence, and remediation approver"));
  assert.ok(publicationNotes.includes("saves the same content as `jury-package-release-replay-summary.md`"));
  assert.ok(publicationNotes.includes("replay artifact summary failure"));
  assert.ok(publicationNotes.includes("--fixture-dir"));
  assert.ok(publicationNotes.includes("GITHUB_STEP_SUMMARY"));
  assert.ok(publicationNotes.includes("dry_run_reviewer"));
  assert.ok(publicationNotes.includes("Post-Publication Comparison"));
  assert.ok(publicationNotes.includes("Rollback After Downstream Verification Failure"));
  assert.ok(publicationNotes.includes("Replacement Patch Evidence"));
  assert.ok(publicationNotes.includes("npm view @sanogueralorenzo/jury@<packageVersion> version dist.tarball --json"));
  assert.ok(publicationNotes.includes("npm deprecate @sanogueralorenzo/jury@<packageVersion>"));
  assert.ok(publicationNotes.includes("npm view @sanogueralorenzo/jury@<replacementPackageVersion> version dist.tarball --json > replacement-npm-view.json"));
  assert.ok(publicationNotes.includes("Do not rerun publication for the same version"));
  assert.ok(publicationNotes.includes("ship a new patch version"));
  assert.ok(publicationNotes.includes("dist.tarball"));
  assert.ok(publicationNotes.includes("replacement `dist.tarball`"));
  assert.ok(publicationNotes.includes("replacement downstream verification pass"));
  assert.ok(publicationNotes.includes("failed-version deprecation result"));
  assert.ok(publicationNotes.includes("must end with the retained `tarballName`"));
  assert.ok(publicationNotes.includes("packageVersion"));
  assert.ok(publicationNotes.includes("tarballName"));
  assert.ok(publicationNotes.includes("reviewedBy"));
  assert.ok(publicationNotes.includes("sanogueralorenzo-jury-0.1.0.tgz"));
  assert.ok(publicationNotes.includes("If the version or tarball name does not match"));
  assert.ok(publicationNotes.includes("TROUBLESHOOTING.md"));
  assert.ok(publicationNotes.includes("secrets.NPM_TOKEN"));
  assert.ok(publicationNotes.includes("NODE_AUTH_TOKEN"));
  assert.ok(publicationNotes.includes("permissions.id-token: write"));
  assert.ok(publicationNotes.includes("npm publish --provenance --access public"));
  assert.ok(publicationNotes.includes("needs: package-manifest"));
  assert.ok(publicationNotes.includes("needs: package-release-evidence-replay"));
  assert.ok(publicationNotes.includes("downloaded dry-run record has verified"));
  assert.ok(publicationNotes.includes("package-release-fixtures"));
  assert.ok(publicationNotes.includes("package-manifest, package-release-fixtures, package-release-evidence-replay, and dry-run-publication jobs token-free"));
  assert.ok(publicationNotes.includes("--pack-manifest <npm-pack-json>"));
  assert.ok(publicationNotes.includes('"missing": ["CI_ADOPTION.md"]'));
  assert.ok(publicationNotes.includes('"missing": ["examples/ci/jury-trusted-bundle-verify.yml"]'));

  const comparisonCommands = extractShellBlock(publicationNotes, "Post-Publication Comparison");
  assert.deepEqual(comparisonCommands, [
    'node -e "const fs=require(\'node:fs\'); const record=JSON.parse(fs.readFileSync(\'jury-pack-dry-run-record.json\',\'utf8\')); console.log(JSON.stringify({packageVersion: record.packageVersion, tarballName: record.tarballName}, null, 2));"',
    "npm view @sanogueralorenzo/jury@<packageVersion> version dist.tarball --json",
  ]);
  const rollbackCommands = extractShellBlock(publicationNotes, "Rollback After Downstream Verification Failure");
  assert.deepEqual(rollbackCommands, [
    "npm view @sanogueralorenzo/jury@<packageVersion> version dist.tarball --json",
    'npm deprecate @sanogueralorenzo/jury@<packageVersion> "Downstream Jury verification failed; use a later patch release."',
  ]);
  const replacementCommands = extractShellBlock(publicationNotes, "Replacement Patch Evidence");
  assert.equal(replacementCommands[0], "npm view @sanogueralorenzo/jury@<replacementPackageVersion> version dist.tarball --json > replacement-npm-view.json");
  assert.match(replacementCommands[1], /replacement version must differ from failed packageVersion/);
  assert.match(replacementCommands[1], /replacement tarball must differ from failed tarballName/);
  const comparisonDir = await tempState();
  try {
    await writeFile(join(comparisonDir, "jury-pack-dry-run-record.json"), JSON.stringify({
      packageVersion: "0.1.0",
      tarballName: "sanogueralorenzo-jury-0.1.0.tgz",
    }));
    const comparisonRecord = await runShell(comparisonCommands[0], comparisonDir);
    assert.equal(comparisonRecord.exitCode, 0, comparisonRecord.stderr);
    assert.deepEqual(JSON.parse(comparisonRecord.stdout), {
      packageVersion: "0.1.0",
      tarballName: "sanogueralorenzo-jury-0.1.0.tgz",
    });
  } finally {
    await rm(comparisonDir, { recursive: true, force: true });
  }
  const replacementDir = await tempState();
  try {
    await writeFile(join(replacementDir, "jury-pack-dry-run-record.json"), JSON.stringify({
      packageVersion: "0.1.0",
      tarballName: "sanogueralorenzo-jury-0.1.0.tgz",
    }));
    await writeFile(join(replacementDir, "replacement-npm-view.json"), JSON.stringify({
      version: "0.1.1",
      dist: {
        tarball: "https://registry.npmjs.org/@sanogueralorenzo/jury/-/sanogueralorenzo-jury-0.1.1.tgz",
      },
    }));
    const replacementRecord = await runShell(replacementCommands[1], replacementDir);
    assert.equal(replacementRecord.exitCode, 0, replacementRecord.stderr);
    assert.deepEqual(JSON.parse(replacementRecord.stdout), {
      failedPackageVersion: "0.1.0",
      failedTarballName: "sanogueralorenzo-jury-0.1.0.tgz",
      replacementPackageVersion: "0.1.1",
      replacementTarball: "https://registry.npmjs.org/@sanogueralorenzo/jury/-/sanogueralorenzo-jury-0.1.1.tgz",
    });

    await writeFile(join(replacementDir, "replacement-npm-view.json"), JSON.stringify({
      version: "0.1.0",
      "dist.tarball": "https://registry.npmjs.org/@sanogueralorenzo/jury/-/sanogueralorenzo-jury-0.1.0.tgz",
    }));
    const staleReplacement = await runShell(replacementCommands[1], replacementDir);
    assert.equal(staleReplacement.exitCode, 1);
    assert.match(staleReplacement.stderr, /replacement version must differ from failed packageVersion/);
  } finally {
    await rm(replacementDir, { recursive: true, force: true });
  }

  for (const relativePath of release.packagePublication.requiredFiles) {
    await stat(join(repoRoot, "jury", relativePath));
    assert.ok(publicationNotes.includes(relativePath), `PUBLISHING.md should mention ${relativePath}`);
  }

  assert.ok(release.packagePublication.requiredFiles.includes(release.ciAdoption.guide));
  assert.ok(release.packagePublication.requiredFiles.includes(release.packagePublication.workflow));
  assert.ok(release.packagePublication.requiredFiles.includes(release.packagePublication.releaseWorkflow));
  for (const workflow of release.ciAdoption.workflows) {
    assert.ok(release.packagePublication.requiredFiles.includes(workflow.path), `package publication should require ${workflow.path}`);
  }

  const manifestCheck = await runShell("node jury/scripts/check-package-manifest.mjs");
  assert.equal(manifestCheck.exitCode, 0, manifestCheck.stderr);
  const manifestPayload = JSON.parse(manifestCheck.stdout);
  assert.equal(manifestPayload.ok, true);
  assert.deepEqual(manifestPayload.missing, []);

  const dryRunDir = await tempState();
  const dryRunPath = join(dryRunDir, "jury-pack-dry-run.json");
  try {
    const dryRun = await runShell(`(cd jury && npm pack --dry-run --json) > ${shellQuote(dryRunPath)}`);
    assert.equal(dryRun.exitCode, 0, dryRun.stderr);

    const [pack] = JSON.parse(await readFile(dryRunPath, "utf8"));
    const expectedRecord = {
      packageVersion: packageJson.version,
      tarballName: `sanogueralorenzo-jury-${packageJson.version}.tgz`,
    };
    const recordScript = `const [pack]=JSON.parse(require('node:fs').readFileSync(${JSON.stringify(dryRunPath)},'utf8')); console.log(JSON.stringify({packageVersion: pack.version, tarballName: pack.filename}, null, 2));`;
    const recordCommand = `node -e ${shellQuote(recordScript)}`;
    const record = await runShell(recordCommand);

    assert.equal(pack.version, expectedRecord.packageVersion);
    assert.equal(pack.filename, expectedRecord.tarballName);
    assert.equal(record.exitCode, 0, record.stderr);
    assert.deepEqual(JSON.parse(record.stdout), expectedRecord);
  } finally {
    await rm(dryRunDir, { recursive: true, force: true });
  }

  for (const relativePath of release.packagePublication.requiredFiles) {
    assert.ok(manifestPayload.checked_paths.includes(relativePath), `manifest check should cover ${relativePath}`);
  }

  for (const commandName of ["judge", "gate", "bundle export", "bundle preflight", "bundle import", "check", "demo code-change"]) {
    assert.ok(release.cli.commands.includes(commandName), `${commandName} must be listed`);
  }
});

test("package manifest check reports omitted CI adoption metadata files", async () => {
  const cwd = await tempState();
  const release = JSON.parse(await readFile(releasePath, "utf8"));
  const requiredPaths = [
    "package.json",
    "release.json",
    release.packagePublication.notes,
    release.ciAdoption.guide,
    ...release.ciAdoption.workflows.map((workflow) => workflow.path),
    ...release.packagePublication.requiredFiles,
  ];
  const packageId = `${release.name}@${release.version}`;

  try {
    const missingGuideManifest = join(cwd, "missing-guide-pack.json");
    await writeFile(missingGuideManifest, JSON.stringify([{
      id: packageId,
      files: packManifestFiles(requiredPaths.filter((relativePath) => relativePath !== release.ciAdoption.guide)),
    }]));

    const missingGuide = await runShell(`node jury/scripts/check-package-manifest.mjs --pack-manifest ${shellQuote(missingGuideManifest)}`);
    assert.equal(missingGuide.exitCode, 1);
    const missingGuidePayload = JSON.parse(missingGuide.stdout);
    assert.equal(missingGuidePayload.ok, false);
    assert.deepEqual(missingGuidePayload.missing, [release.ciAdoption.guide]);

    const missingWorkflowPath = "examples/ci/jury-trusted-bundle-verify.yml";
    const missingWorkflowManifest = join(cwd, "missing-workflow-pack.json");
    await writeFile(missingWorkflowManifest, JSON.stringify([{
      id: packageId,
      files: packManifestFiles(requiredPaths.filter((relativePath) => relativePath !== missingWorkflowPath)),
    }]));

    const missingWorkflow = await runShell(`node jury/scripts/check-package-manifest.mjs --pack-manifest ${shellQuote(missingWorkflowManifest)}`);
    assert.equal(missingWorkflow.exitCode, 1);
    const missingWorkflowPayload = JSON.parse(missingWorkflow.stdout);
    assert.equal(missingWorkflowPayload.ok, false);
    assert.deepEqual(missingWorkflowPayload.missing, [missingWorkflowPath]);
  } finally {
    await rm(cwd, { recursive: true, force: true });
  }
});

test("bundle preflight validates portable bundles without mutating state", async () => {
  const cwd = await tempState();
  const stateDir = join(cwd, "preflight-state");
  const bundlePath = join(repoRoot, "jury/examples/ci/fixtures/quickstart/review-bundle.json");

  try {
    const result = await runProcess(["bundle", "preflight", "--state-dir", stateDir, "--bundle", bundlePath]);
    const payload = JSON.parse(result.stdout);

    assert.equal(result.exitCode, 0);
    assert.deepEqual(payload, {
      ok: true,
      claim_id: "claim_ci_change",
      producer: {
        name: "@sanogueralorenzo/jury",
        version: "0.1.0",
        command: "bundle export",
      },
      provenance: {
        source: "local",
        revision: "unknown",
        workflow: null,
        run_id: null,
      },
      records: {
        claims: 3,
        checks: 2,
        evidence: 1,
        objections: 0,
        waivers: 0,
        verdicts: 1,
      },
      latest_verdict_id: "verdict_claim_ci_change_accept",
    });
    await assertPathMissing(stateDir);
  } finally {
    await rm(cwd, { recursive: true, force: true });
  }
});

test("bundle preflight and import reject invalid bundles before state mutation", async () => {
  const cwd = await tempState();
  const stateDir = join(cwd, "import-state");
  const invalidBundlePath = join(cwd, "invalid-review-bundle.json");

  try {
    const bundle = JSON.parse(await readFile(join(repoRoot, "jury/examples/ci/fixtures/quickstart/review-bundle.json"), "utf8"));
    bundle.records.checks.at(-1).evidence_ids = ["ev_missing"];
    bundle.records.evidence[0].claim_id = "claim_other";
    delete bundle.provenance.revision;
    delete bundle.records.verdicts[0].reason;
    await writeFile(invalidBundlePath, `${JSON.stringify(bundle, null, 2)}\n`);

    for (const command of ["preflight", "import"]) {
      const result = await runProcess(["bundle", command, "--state-dir", stateDir, "--bundle", invalidBundlePath]);
      const payload = JSON.parse(result.stdout);

      assert.equal(result.exitCode, 1);
      assert.equal(payload.ok, false);
      assert.ok(payload.errors.includes("bundle.provenance.revision must be a non-empty string"));
      assert.ok(payload.errors.includes("verdict.reason must be a non-empty string"));
      assert.ok(payload.errors.includes("bundle.records.evidence contains ev_ci_tests from claim claim_other, expected claim_ci_change"));
      assert.ok(payload.errors.includes("check check_ci_tests evidence_ids references missing record ev_missing"));
      await assertPathMissing(stateDir);
    }
  } finally {
    await rm(cwd, { recursive: true, force: true });
  }
});

test("bundle trust policy allows expected producers and rejects mismatches before import", async () => {
  const cwd = await tempState();
  const stateDir = join(cwd, "trusted-import-state");
  const bundlePath = join(repoRoot, "jury/examples/ci/fixtures/quickstart/review-bundle.json");
  const trustPolicy = [
    "--expect-producer-name", "@sanogueralorenzo/jury",
    "--expect-producer-version", "0.1.0",
    "--expect-source", "local",
    "--expect-revision-pattern", "^unknown$",
  ];

  try {
    const allowed = await runProcess(["bundle", "preflight", "--state-dir", stateDir, "--bundle", bundlePath, ...trustPolicy]);
    const allowedPayload = JSON.parse(allowed.stdout);

    assert.equal(allowed.exitCode, 0);
    assert.equal(allowedPayload.ok, true);
    await assertPathMissing(stateDir);

    const imported = await runProcess(["bundle", "import", "--state-dir", stateDir, "--bundle", bundlePath, ...trustPolicy]);
    const importedPayload = JSON.parse(imported.stdout);

    assert.equal(imported.exitCode, 0);
    assert.equal(importedPayload.ok, true);
    assert.equal(importedPayload.producer.name, "@sanogueralorenzo/jury");

    await rm(stateDir, { recursive: true, force: true });

    const rejected = await runProcess([
      "bundle", "import",
      "--state-dir", stateDir,
      "--bundle", bundlePath,
      "--expect-producer-name", "other-producer",
      "--expect-producer-version", "9.9.9",
      "--expect-source", "github.com/example/repo",
      "--expect-revision-pattern", "^[0-9a-f]{40}$",
    ]);
    const rejectedPayload = JSON.parse(rejected.stdout);

    assert.equal(rejected.exitCode, 1);
    assert.equal(rejectedPayload.ok, false);
    assert.ok(rejectedPayload.errors.includes("bundle.producer.name expected other-producer, got @sanogueralorenzo/jury"));
    assert.ok(rejectedPayload.errors.includes("bundle.producer.version expected 9.9.9, got 0.1.0"));
    assert.ok(rejectedPayload.errors.includes("bundle.provenance.source expected github.com/example/repo, got local"));
    assert.ok(rejectedPayload.errors.includes("bundle.provenance.revision must match ^[0-9a-f]{40}$, got unknown"));
    await assertPathMissing(stateDir);
  } finally {
    await rm(cwd, { recursive: true, force: true });
  }
});

test("bundle attestation signs exports and rejects bad or tampered signatures before import", async () => {
  const sourceDir = await tempState();
  const cwd = await tempState();
  const importDir = join(cwd, "signed-import-state");
  const signedBundlePath = join(cwd, "signed-review-bundle.json");
  const tamperedBundlePath = join(cwd, "tampered-review-bundle.json");

  try {
    await runJson(["init", "--state-dir", sourceDir]);
    await runJson(["claim", "create", "--state-dir", sourceDir, "--id", "claim_signed_bundle", "--summary", "signed bundle is ready", "--scope", "jury"]);
    await runJson(["evidence", "add", "--state-dir", sourceDir, "--id", "ev_signed_tests", "--claim", "claim_signed_bundle", "--type", "command", "--command", "npm --prefix jury test", "--exit-code", "0"]);
    const bundle = await runJson([
      "bundle", "export",
      "--state-dir", sourceDir,
      "--claim", "claim_signed_bundle",
      "--out", signedBundlePath,
      "--attest-key", "shared-secret",
      "--attestation-key-id", "ci",
    ]);

    assert.equal(bundle.attestation.type, "hmac-sha256");
    assert.equal(bundle.attestation.key_id, "ci");
    assert.equal(bundle.attestation.signed_at, "2026-05-23T00:00:00.000Z");
    assert.match(bundle.attestation.signature, /^[0-9a-f]{64}$/);

    const trusted = await runProcess([
      "bundle", "preflight",
      "--bundle", signedBundlePath,
      "--require-attestation", "true",
      "--verify-attestation-key", "shared-secret",
      "--expect-attestation-key-id", "ci",
    ]);

    assert.equal(trusted.exitCode, 0, trusted.stderr);
    assert.equal(JSON.parse(trusted.stdout).ok, true);

    const imported = await runProcess([
      "bundle", "import",
      "--state-dir", importDir,
      "--bundle", signedBundlePath,
      "--require-attestation", "true",
      "--verify-attestation-key", "shared-secret",
      "--expect-attestation-key-id", "ci",
    ]);

    assert.equal(imported.exitCode, 0, imported.stderr);
    assert.equal(JSON.parse(imported.stdout).ok, true);

    await rm(importDir, { recursive: true, force: true });

    const badKey = await runProcess(["bundle", "preflight", "--state-dir", importDir, "--bundle", signedBundlePath, "--verify-attestation-key", "wrong-secret"]);
    const badKeyPayload = JSON.parse(badKey.stdout);

    assert.equal(badKey.exitCode, 1);
    assert.ok(badKeyPayload.errors.includes("bundle.attestation.signature verification failed"));
    await assertPathMissing(importDir);

    const tampered = JSON.parse(await readFile(signedBundlePath, "utf8"));
    tampered.records.evidence[0].summary = "tampered evidence";
    await writeFile(tamperedBundlePath, `${JSON.stringify(tampered, null, 2)}\n`);

    const tamperedResult = await runProcess(["bundle", "import", "--state-dir", importDir, "--bundle", tamperedBundlePath, "--require-attestation", "true", "--verify-attestation-key", "shared-secret"]);
    const tamperedPayload = JSON.parse(tamperedResult.stdout);

    assert.equal(tamperedResult.exitCode, 1);
    assert.ok(tamperedPayload.errors.includes("bundle.attestation.signature verification failed"));
    await assertPathMissing(importDir);
  } finally {
    await rm(sourceDir, { recursive: true, force: true });
    await rm(cwd, { recursive: true, force: true });
  }
});

test("bundle asymmetric attestation verifies producer identity with a public key", async () => {
  const sourceDir = await tempState();
  const cwd = await tempState();
  const importDir = join(cwd, "asymmetric-import-state");
  const privateKeyPath = join(cwd, "ci-private.pem");
  const publicKeyPath = join(cwd, "ci-public.pem");
  const wrongPublicKeyPath = join(cwd, "wrong-public.pem");
  const ecPrivateKeyPath = join(cwd, "ec-private.pem");
  const ecPublicKeyPath = join(cwd, "ec-public.pem");
  const signedBundlePath = join(cwd, "asymmetric-review-bundle.json");
  const tamperedBundlePath = join(cwd, "asymmetric-tampered-review-bundle.json");

  try {
    const pair = generateKeyPairSync("rsa", {
      modulusLength: 2048,
      privateKeyEncoding: { type: "pkcs8", format: "pem" },
      publicKeyEncoding: { type: "spki", format: "pem" },
    });
    const wrongPair = generateKeyPairSync("rsa", {
      modulusLength: 2048,
      privateKeyEncoding: { type: "pkcs8", format: "pem" },
      publicKeyEncoding: { type: "spki", format: "pem" },
    });
    const ecPair = generateKeyPairSync("ec", {
      namedCurve: "P-256",
      privateKeyEncoding: { type: "pkcs8", format: "pem" },
      publicKeyEncoding: { type: "spki", format: "pem" },
    });
    await writeFile(privateKeyPath, pair.privateKey);
    await writeFile(publicKeyPath, pair.publicKey);
    await writeFile(wrongPublicKeyPath, wrongPair.publicKey);
    await writeFile(ecPrivateKeyPath, ecPair.privateKey);
    await writeFile(ecPublicKeyPath, ecPair.publicKey);

    await runJson(["init", "--state-dir", sourceDir]);
    await runJson(["claim", "create", "--state-dir", sourceDir, "--id", "claim_asymmetric_bundle", "--summary", "asymmetric bundle is ready", "--scope", "jury"]);
    await runJson(["evidence", "add", "--state-dir", sourceDir, "--id", "ev_asymmetric_tests", "--claim", "claim_asymmetric_bundle", "--type", "command", "--command", "npm --prefix jury test", "--exit-code", "0"]);
    const bundle = await runJson([
      "bundle", "export",
      "--state-dir", sourceDir,
      "--claim", "claim_asymmetric_bundle",
      "--out", signedBundlePath,
      "--attest-private-key", privateKeyPath,
      "--attestation-key-id", "ci-public",
    ]);

    assert.equal(bundle.attestation.type, "rsa-sha256");
    assert.equal(bundle.attestation.key_id, "ci-public");
    assert.equal(bundle.attestation.signed_at, "2026-05-23T00:00:00.000Z");
    assert.match(bundle.attestation.signature, /^[A-Za-z0-9+/=]+$/);

    const trusted = await runProcess([
      "bundle", "preflight",
      "--bundle", signedBundlePath,
      "--require-attestation", "true",
      "--verify-attestation-public-key", publicKeyPath,
      "--expect-attestation-key-id", "ci-public",
    ]);

    assert.equal(trusted.exitCode, 0, trusted.stderr);
    assert.equal(JSON.parse(trusted.stdout).ok, true);

    const imported = await runProcess([
      "bundle", "import",
      "--state-dir", importDir,
      "--bundle", signedBundlePath,
      "--require-attestation", "true",
      "--verify-attestation-public-key", publicKeyPath,
      "--expect-attestation-key-id", "ci-public",
    ]);

    assert.equal(imported.exitCode, 0, imported.stderr);
    assert.equal(JSON.parse(imported.stdout).ok, true);

    await rm(importDir, { recursive: true, force: true });

    const wrongKey = await runProcess(["bundle", "preflight", "--state-dir", importDir, "--bundle", signedBundlePath, "--verify-attestation-public-key", wrongPublicKeyPath]);
    const wrongKeyPayload = JSON.parse(wrongKey.stdout);

    assert.equal(wrongKey.exitCode, 1);
    assert.ok(wrongKeyPayload.errors.includes("bundle.attestation.signature verification failed"));
    await assertPathMissing(importDir);

    const wrongTypeKey = await runProcess(["bundle", "preflight", "--state-dir", importDir, "--bundle", signedBundlePath, "--verify-attestation-public-key", ecPublicKeyPath]);
    const wrongTypeKeyPayload = JSON.parse(wrongTypeKey.stdout);

    assert.equal(wrongTypeKey.exitCode, 1);
    assert.ok(wrongTypeKeyPayload.errors.includes("bundle.attestation.signature verification failed"));
    await assertPathMissing(importDir);

    const ecSigned = await runProcess([
      "bundle", "export",
      "--state-dir", sourceDir,
      "--claim", "claim_asymmetric_bundle",
      "--attest-private-key", ecPrivateKeyPath,
    ]);

    assert.equal(ecSigned.exitCode, 1);
    assert.match(ecSigned.stderr, /attestation private key must be RSA, got ec/);

    const tampered = JSON.parse(await readFile(signedBundlePath, "utf8"));
    tampered.records.evidence[0].summary = "tampered asymmetric evidence";
    await writeFile(tamperedBundlePath, `${JSON.stringify(tampered, null, 2)}\n`);

    const tamperedResult = await runProcess(["bundle", "import", "--state-dir", importDir, "--bundle", tamperedBundlePath, "--require-attestation", "true", "--verify-attestation-public-key", publicKeyPath]);
    const tamperedPayload = JSON.parse(tamperedResult.stdout);

    assert.equal(tamperedResult.exitCode, 1);
    assert.ok(tamperedPayload.errors.includes("bundle.attestation.signature verification failed"));
    await assertPathMissing(importDir);
  } finally {
    await rm(sourceDir, { recursive: true, force: true });
    await rm(cwd, { recursive: true, force: true });
  }
});

test("bundle key policy verifies trusted producers and public keys before import", async () => {
  const sourceDir = await tempState();
  const cwd = await tempState();
  const importDir = join(cwd, "policy-import-state");
  const privateKeyPath = join(cwd, "policy-private.pem");
  const publicKeyPath = join(cwd, "policy-public.pem");
  const wrongPublicKeyPath = join(cwd, "policy-wrong-public.pem");
  const policyPath = join(cwd, "jury-key-policy.json");
  const inlinePolicyPath = join(cwd, "inline-key-policy.json");
  const overlappingPolicyPath = join(cwd, "overlapping-key-policy.json");
  const wrongProducerPolicyPath = join(cwd, "wrong-producer-policy.json");
  const wrongKeyPolicyPath = join(cwd, "wrong-key-policy.json");
  const noMatchingKeyPolicyPath = join(cwd, "no-matching-key-policy.json");
  const expiredPolicyPath = join(cwd, "expired-key-policy.json");
  const futurePolicyPath = join(cwd, "future-key-policy.json");
  const revokedPolicyPath = join(cwd, "revoked-key-policy.json");
  const duplicateRevokedPolicyPath = join(cwd, "duplicate-revoked-key-policy.json");
  const tamperedSignedAtExpiredBundlePath = join(cwd, "tampered-signed-at-expired-review-bundle.json");
  const bundlePath = join(cwd, "policy-review-bundle.json");

  try {
    const pair = generateKeyPairSync("rsa", {
      modulusLength: 2048,
      privateKeyEncoding: { type: "pkcs8", format: "pem" },
      publicKeyEncoding: { type: "spki", format: "pem" },
    });
    const wrongPair = generateKeyPairSync("rsa", {
      modulusLength: 2048,
      privateKeyEncoding: { type: "pkcs8", format: "pem" },
      publicKeyEncoding: { type: "spki", format: "pem" },
    });
    await writeFile(privateKeyPath, pair.privateKey);
    await writeFile(publicKeyPath, pair.publicKey);
    await writeFile(wrongPublicKeyPath, wrongPair.publicKey);

    const policy = {
      schema_version: "jury.key_policy.v1",
      producers: [{
        name: "jury-ci",
        version: "9.9.9",
        source: "github.com/example/repo",
        revision_pattern: "^abc[0-9]+$",
        keys: [{
          key_id: "ci-policy",
          type: "rsa-sha256",
          public_key_path: "policy-public.pem",
          valid_from: "2026-05-22T00:00:00.000Z",
          valid_until: "2026-05-24T00:00:00.000Z",
        }],
      }],
    };
    await writeFile(policyPath, `${JSON.stringify(policy, null, 2)}\n`);
    await writeFile(inlinePolicyPath, `${JSON.stringify({
      ...policy,
      producers: [{
        ...policy.producers[0],
        keys: [{ ...policy.producers[0].keys[0], public_key_path: undefined, public_key: pair.publicKey }],
      }],
    }, null, 2)}\n`);
    await writeFile(overlappingPolicyPath, `${JSON.stringify({
      ...policy,
      producers: [
        {
          ...policy.producers[0],
          keys: [{ ...policy.producers[0].keys[0], public_key_path: "policy-wrong-public.pem" }],
        },
        policy.producers[0],
      ],
    }, null, 2)}\n`);
    await writeFile(wrongProducerPolicyPath, `${JSON.stringify({
      ...policy,
      producers: [{ ...policy.producers[0], source: "github.com/example/other" }],
    }, null, 2)}\n`);
    await writeFile(wrongKeyPolicyPath, `${JSON.stringify({
      ...policy,
      producers: [{
        ...policy.producers[0],
        keys: [{ ...policy.producers[0].keys[0], public_key_path: "policy-wrong-public.pem" }],
      }],
    }, null, 2)}\n`);
    await writeFile(noMatchingKeyPolicyPath, `${JSON.stringify({
      ...policy,
      producers: [{
        ...policy.producers[0],
        keys: [{ ...policy.producers[0].keys[0], key_id: "other-key" }],
      }],
    }, null, 2)}\n`);
    await writeFile(expiredPolicyPath, `${JSON.stringify({
      ...policy,
      producers: [{
        ...policy.producers[0],
        keys: [{ ...policy.producers[0].keys[0], valid_until: "2026-05-22T23:59:59.000Z" }],
      }],
    }, null, 2)}\n`);
    await writeFile(futurePolicyPath, `${JSON.stringify({
      ...policy,
      producers: [{
        ...policy.producers[0],
        keys: [{ ...policy.producers[0].keys[0], valid_from: "2026-05-24T00:00:00.000Z", valid_until: undefined }],
      }],
    }, null, 2)}\n`);
    await writeFile(revokedPolicyPath, `${JSON.stringify({
      ...policy,
      producers: [{
        ...policy.producers[0],
        keys: [{
          ...policy.producers[0].keys[0],
          revoked_at: "2026-05-23T00:30:00.000Z",
          revoked_reason: "compromised producer key",
        }],
      }],
    }, null, 2)}\n`);
    await writeFile(duplicateRevokedPolicyPath, `${JSON.stringify({
      ...policy,
      producers: [{
        ...policy.producers[0],
        keys: [
          {
            ...policy.producers[0].keys[0],
            revoked_at: "2026-05-23T00:30:00.000Z",
            revoked_reason: "compromised producer key",
          },
          policy.producers[0].keys[0],
        ],
      }],
    }, null, 2)}\n`);

    await runJson(["init", "--state-dir", sourceDir]);
    await runJson(["claim", "create", "--state-dir", sourceDir, "--id", "claim_policy_bundle", "--summary", "policy bundle is ready", "--scope", "jury"]);
    await runJson(["evidence", "add", "--state-dir", sourceDir, "--id", "ev_policy_tests", "--claim", "claim_policy_bundle", "--type", "command", "--command", "npm --prefix jury test", "--exit-code", "0"]);
    const bundle = await runJson([
      "bundle", "export",
      "--state-dir", sourceDir,
      "--claim", "claim_policy_bundle",
      "--out", bundlePath,
      "--producer-name", "jury-ci",
      "--producer-version", "9.9.9",
      "--source", "github.com/example/repo",
      "--revision", "abc123",
      "--attest-private-key", privateKeyPath,
      "--attestation-key-id", "ci-policy",
    ]);

    assert.equal(bundle.attestation.key_id, "ci-policy");

    const trusted = await runProcess(["bundle", "preflight", "--bundle", bundlePath, "--key-policy", policyPath]);
    const trustedPayload = JSON.parse(trusted.stdout);
    assert.equal(trusted.exitCode, 0, trusted.stderr);
    assert.equal(trustedPayload.ok, true);
    assert.deepEqual(trustedPayload.key_policy.matching_producers.map((producer) => producer.producer_index), [0]);
    assert.deepEqual(trustedPayload.key_policy.considered_keys.map((key) => key.status), ["verified"]);
    assert.equal(trustedPayload.key_policy.considered_keys[0].public_key_source, "policy-public.pem");

    const inlineTrusted = await runProcess(["bundle", "preflight", "--bundle", bundlePath, "--key-policy", inlinePolicyPath]);
    const inlineTrustedPayload = JSON.parse(inlineTrusted.stdout);
    assert.equal(inlineTrusted.exitCode, 0, inlineTrusted.stderr);
    assert.equal(inlineTrustedPayload.ok, true);
    assert.equal(inlineTrustedPayload.key_policy.considered_keys[0].public_key_source, "inline");

    const overlappingTrusted = await runProcess(["bundle", "preflight", "--bundle", bundlePath, "--key-policy", overlappingPolicyPath]);
    const overlappingTrustedPayload = JSON.parse(overlappingTrusted.stdout);
    assert.equal(overlappingTrusted.exitCode, 0, overlappingTrusted.stderr);
    assert.equal(overlappingTrustedPayload.ok, true);
    assert.deepEqual(overlappingTrustedPayload.key_policy.matching_producers.map((producer) => producer.producer_index), [0, 1]);
    assert.deepEqual(overlappingTrustedPayload.key_policy.considered_keys.map((key) => key.status), ["signature_mismatch", "verified"]);

    const imported = await runProcess(["bundle", "import", "--state-dir", importDir, "--bundle", bundlePath, "--key-policy", policyPath]);
    assert.equal(imported.exitCode, 0, imported.stderr);
    assert.equal(JSON.parse(imported.stdout).ok, true);

    await rm(importDir, { recursive: true, force: true });

    const wrongProducerPreflight = await runProcess(["bundle", "preflight", "--bundle", bundlePath, "--key-policy", wrongProducerPolicyPath]);
    const wrongProducerPreflightPayload = JSON.parse(wrongProducerPreflight.stdout);

    assert.equal(wrongProducerPreflight.exitCode, 1);
    assert.ok(wrongProducerPreflightPayload.errors.some((error) => error.includes("key policy has no trusted producer matching")));
    assert.deepEqual(wrongProducerPreflightPayload.key_policy.matching_producers, []);
    assert.deepEqual(wrongProducerPreflightPayload.key_policy.considered_keys, []);

    const wrongProducer = await runProcess(["bundle", "import", "--state-dir", importDir, "--bundle", bundlePath, "--key-policy", wrongProducerPolicyPath]);
    const wrongProducerPayload = JSON.parse(wrongProducer.stdout);

    assert.equal(wrongProducer.exitCode, 1);
    assert.ok(wrongProducerPayload.errors.some((error) => error.includes("key policy has no trusted producer matching")));
    assert.deepEqual(wrongProducerPayload.key_policy.matching_producers, []);
    assert.deepEqual(wrongProducerPayload.key_policy.considered_keys, []);
    await assertPathMissing(importDir);

    const wrongKeyPreflight = await runProcess(["bundle", "preflight", "--bundle", bundlePath, "--key-policy", wrongKeyPolicyPath]);
    const wrongKeyPreflightPayload = JSON.parse(wrongKeyPreflight.stdout);

    assert.equal(wrongKeyPreflight.exitCode, 1);
    assert.ok(wrongKeyPreflightPayload.errors.includes("bundle.attestation.signature verification failed"));
    assert.deepEqual(wrongKeyPreflightPayload.key_policy.considered_keys.map((key) => key.status), ["signature_mismatch"]);

    const wrongKey = await runProcess(["bundle", "import", "--state-dir", importDir, "--bundle", bundlePath, "--key-policy", wrongKeyPolicyPath]);
    const wrongKeyPayload = JSON.parse(wrongKey.stdout);

    assert.equal(wrongKey.exitCode, 1);
    assert.ok(wrongKeyPayload.errors.includes("bundle.attestation.signature verification failed"));
    assert.deepEqual(wrongKeyPayload.key_policy.considered_keys.map((key) => key.status), ["signature_mismatch"]);
    await assertPathMissing(importDir);

    const noMatchingKey = await runProcess(["bundle", "preflight", "--bundle", bundlePath, "--key-policy", noMatchingKeyPolicyPath]);
    const noMatchingKeyPayload = JSON.parse(noMatchingKey.stdout);

    assert.equal(noMatchingKey.exitCode, 1);
    assert.ok(noMatchingKeyPayload.errors.includes("key policy has no trusted rsa-sha256 key ci-policy"));
    assert.deepEqual(noMatchingKeyPayload.key_policy.considered_keys.map((key) => key.status), ["not_selected"]);

    const expired = await runProcess(["bundle", "preflight", "--bundle", bundlePath, "--key-policy", expiredPolicyPath]);
    const expiredPayload = JSON.parse(expired.stdout);

    assert.equal(expired.exitCode, 1);
    assert.ok(expiredPayload.errors.includes("key policy key ci-policy is not valid after 2026-05-22T23:59:59.000Z"));
    assert.deepEqual(expiredPayload.key_policy.considered_keys.map((key) => key.status), ["outside_validity"]);

    const tamperedSignedAt = JSON.parse(await readFile(bundlePath, "utf8"));
    tamperedSignedAt.attestation.signed_at = "2026-05-22T00:00:00.000Z";
    await writeFile(tamperedSignedAtExpiredBundlePath, `${JSON.stringify(tamperedSignedAt, null, 2)}\n`);

    const tamperedExpired = await runProcess(["bundle", "preflight", "--bundle", tamperedSignedAtExpiredBundlePath, "--key-policy", expiredPolicyPath]);
    const tamperedExpiredPayload = JSON.parse(tamperedExpired.stdout);

    assert.equal(tamperedExpired.exitCode, 1);
    assert.ok(tamperedExpiredPayload.errors.includes("key policy key ci-policy is not valid after 2026-05-22T23:59:59.000Z"));

    const expiredImport = await runProcess(["bundle", "import", "--state-dir", importDir, "--bundle", bundlePath, "--key-policy", expiredPolicyPath]);
    const expiredImportPayload = JSON.parse(expiredImport.stdout);

    assert.equal(expiredImport.exitCode, 1);
    assert.ok(expiredImportPayload.errors.includes("key policy key ci-policy is not valid after 2026-05-22T23:59:59.000Z"));
    assert.deepEqual(expiredImportPayload.key_policy.considered_keys.map((key) => key.status), ["outside_validity"]);
    await assertPathMissing(importDir);

    const future = await runProcess(["bundle", "preflight", "--bundle", bundlePath, "--key-policy", futurePolicyPath]);
    const futurePayload = JSON.parse(future.stdout);

    assert.equal(future.exitCode, 1);
    assert.ok(futurePayload.errors.includes("key policy key ci-policy is not valid before 2026-05-24T00:00:00.000Z"));

    const futureImport = await runProcess(["bundle", "import", "--state-dir", importDir, "--bundle", bundlePath, "--key-policy", futurePolicyPath]);
    const futureImportPayload = JSON.parse(futureImport.stdout);

    assert.equal(futureImport.exitCode, 1);
    assert.ok(futureImportPayload.errors.includes("key policy key ci-policy is not valid before 2026-05-24T00:00:00.000Z"));
    assert.deepEqual(futureImportPayload.key_policy.considered_keys.map((key) => key.status), ["outside_validity"]);
    await assertPathMissing(importDir);

    const revokedPreflight = await runProcess(["bundle", "preflight", "--bundle", bundlePath, "--key-policy", revokedPolicyPath]);
    const revokedPreflightPayload = JSON.parse(revokedPreflight.stdout);

    assert.equal(revokedPreflight.exitCode, 1);
    assert.ok(revokedPreflightPayload.errors.includes("key policy key ci-policy is revoked at 2026-05-23T00:30:00.000Z: compromised producer key"));
    assert.deepEqual(revokedPreflightPayload.key_policy.considered_keys.map((key) => key.status), ["revoked"]);

    const revoked = await runProcess(["bundle", "import", "--state-dir", importDir, "--bundle", bundlePath, "--key-policy", revokedPolicyPath]);
    const revokedPayload = JSON.parse(revoked.stdout);

    assert.equal(revoked.exitCode, 1);
    assert.ok(revokedPayload.errors.includes("key policy key ci-policy is revoked at 2026-05-23T00:30:00.000Z: compromised producer key"));
    assert.deepEqual(revokedPayload.key_policy.considered_keys.map((key) => key.status), ["revoked"]);
    await assertPathMissing(importDir);

    const duplicateRevoked = await runProcess(["bundle", "preflight", "--bundle", bundlePath, "--key-policy", duplicateRevokedPolicyPath]);
    const duplicateRevokedPayload = JSON.parse(duplicateRevoked.stdout);

    assert.equal(duplicateRevoked.exitCode, 1);
    assert.ok(duplicateRevokedPayload.errors.includes("key policy key ci-policy is revoked at 2026-05-23T00:30:00.000Z: compromised producer key"));
    assert.deepEqual(duplicateRevokedPayload.key_policy.considered_keys.map((key) => key.status), ["revoked", "blocked_by_revocation"]);
  } finally {
    await rm(sourceDir, { recursive: true, force: true });
    await rm(cwd, { recursive: true, force: true });
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
    const bundle = await runJson([
      "bundle", "export",
      "--state-dir", sourceDir,
      "--claim", "claim_bundle",
      "--out", bundlePath,
      "--producer-name", "jury-ci",
      "--producer-version", "9.9.9",
      "--source", "github.com/example/repo",
      "--revision", "abc123",
      "--workflow", "jury",
      "--run-id", "42",
    ]);

    assert.equal(verdict.decision, "accept");
    assert.equal(bundle.schema_version, "jury.review_bundle.v1");
    assert.deepEqual(bundle.producer, {
      name: "jury-ci",
      version: "9.9.9",
      command: "bundle export",
    });
    assert.deepEqual(bundle.provenance, {
      source: "github.com/example/repo",
      revision: "abc123",
      workflow: "jury",
      run_id: "42",
    });
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
    assert.deepEqual(imported.producer, bundle.producer);
    assert.deepEqual(imported.provenance, bundle.provenance);
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
  const keyPolicySchema = JSON.parse(await readFile(join(repoRoot, "jury/schemas/key-policy.schema.json"), "utf8"));
  const packageReleaseEvidenceSchema = JSON.parse(await readFile(join(repoRoot, "jury/schemas/package-release-evidence.schema.json"), "utf8"));
  const packageReleaseArchiveManifestSchema = JSON.parse(await readFile(join(repoRoot, "jury/schemas/package-release-archive-manifest.schema.json"), "utf8"));
  const packageReleaseRemediationAuditSchema = JSON.parse(await readFile(join(repoRoot, "jury/schemas/package-release-remediation-audit.schema.json"), "utf8"));
  const packageReleaseRemediationAuditHandoffSchema = JSON.parse(await readFile(join(repoRoot, "jury/schemas/package-release-remediation-audit-handoff.schema.json"), "utf8"));
  const packageReleaseReplaySummaryDiagnosticsSchema = JSON.parse(await readFile(join(repoRoot, "jury/schemas/package-release-replay-summary-diagnostics.schema.json"), "utf8"));
  const packageReleaseReplaySummaryDiagnosticsRetentionHandoffSchema = JSON.parse(await readFile(join(repoRoot, "jury/schemas/package-release-replay-summary-diagnostics-retention-handoff.schema.json"), "utf8"));
  const properties = schema.properties.records.properties;

  assert.ok(schema.required.includes("producer"));
  assert.ok(schema.required.includes("provenance"));
  assert.deepEqual(schema.properties.producer.required, ["name", "version", "command"]);
  assert.deepEqual(schema.properties.provenance.required, ["source", "revision", "workflow", "run_id"]);
  assert.deepEqual(schema.properties.attestation.required, ["type", "key_id", "signed_at", "signature"]);
  assert.deepEqual(schema.properties.attestation.properties.type.enum, ["hmac-sha256", "rsa-sha256"]);
  assert.equal(schema.properties.attestation.properties.signed_at.format, "date-time");
  assert.equal(schema.properties.attestation.allOf.length, 2);
  assert.equal(properties.claims.items.$ref, "claim.schema.json");
  assert.equal(properties.checks.items.$ref, "check.schema.json");
  assert.equal(properties.evidence.items.$ref, "evidence.schema.json");
  assert.equal(properties.objections.items.$ref, "objection.schema.json");
  assert.equal(properties.waivers.items.$ref, "waiver.schema.json");
  assert.equal(properties.verdicts.items.$ref, "verdict.schema.json");
  assert.equal(keyPolicySchema.properties.schema_version.const, "jury.key_policy.v1");
  assert.deepEqual(keyPolicySchema.required, ["schema_version", "producers"]);
  assert.equal(keyPolicySchema.properties.producers.items.properties.keys.items.properties.type.const, "rsa-sha256");
  assert.equal(keyPolicySchema.properties.producers.items.properties.keys.items.properties.valid_from.format, "date-time");
  assert.equal(keyPolicySchema.properties.producers.items.properties.keys.items.properties.valid_until.format, "date-time");
  assert.equal(keyPolicySchema.properties.producers.items.properties.keys.items.properties.revoked_at.format, "date-time");
  assert.deepEqual(keyPolicySchema.properties.producers.items.properties.keys.items.dependentRequired, { revoked_at: ["revoked_reason"] });
  assert.equal(keyPolicySchema.properties.producers.items.properties.keys.items.oneOf.length, 2);
  assert.equal(packageReleaseEvidenceSchema.properties.schema_version.const, "jury.package_release_evidence.v1");
  assert.deepEqual(packageReleaseEvidenceSchema.required, ["schema_version", "audit_type", "package", "failed", "retention"]);
  assert.deepEqual(packageReleaseEvidenceSchema.properties.audit_type.enum, ["failed-publication-rollback", "replacement-patch-supersedence"]);
  assert.deepEqual(packageReleaseEvidenceSchema.properties.failed.required, ["packageVersion", "tarballName", "dryRunRecord", "npmView"]);
  assert.deepEqual(packageReleaseEvidenceSchema.properties.retention.required, ["policy", "storage", "retainUntil", "artifacts", "provenance"]);
  assert.equal(packageReleaseEvidenceSchema.properties.retention.properties.policy.const, "jury.package_release_retention.v1");
  assert.equal(packageReleaseEvidenceSchema.properties.retention.properties.storage.const, "release record or incident archive");
  assert.equal(packageReleaseEvidenceSchema.properties.retention.properties.artifacts.minItems, 1);
  const retentionProvenance = packageReleaseEvidenceSchema.properties.retention.properties.provenance;
  assert.deepEqual(retentionProvenance.required, ["source", "workflow", "runId", "sourceRevision", "artifacts"]);
  assert.equal(retentionProvenance.properties.source.const, "github-actions");
  assert.equal(retentionProvenance.properties.workflow.const, "jury-npm-publish.yml");
  assert.deepEqual(retentionProvenance.properties.artifacts.items.required, ["name", "sourceJob", "retentionDays", "files"]);
  assert.deepEqual(retentionProvenance.properties.artifacts.items.properties.name.enum, [
    "jury-package-dry-run",
    "jury-package-release-evidence",
    "jury-package-release-replay-summary",
  ]);
  assert.equal(retentionProvenance.properties.artifacts.items.properties.retentionDays.const, 90);
  assert.deepEqual(packageReleaseEvidenceSchema.properties.deprecation.required, ["attempted", "allowed", "command", "result"]);
  assert.deepEqual(packageReleaseEvidenceSchema.properties.replacement.required, ["packageVersion", "npmView", "distTarball", "downstreamGate"]);
  assert.equal(packageReleaseEvidenceSchema.properties.checks.minItems, 1);
  assert.equal(packageReleaseEvidenceSchema.allOf.length, 2);
  assert.equal(packageReleaseArchiveManifestSchema.properties.schema_version.const, "jury.package_release_archive_manifest.v1");
  assert.deepEqual(packageReleaseArchiveManifestSchema.required, ["schema_version", "package", "failed", "replacement", "retention", "provenance", "archiveEvidence"]);
  assert.deepEqual(packageReleaseArchiveManifestSchema.properties.failed.required, ["packageVersion", "tarballName", "dryRunRecord", "npmView", "downstreamGate", "rollbackAudit", "deprecation"]);
  assert.equal(packageReleaseArchiveManifestSchema.properties.failed.properties.rollbackAudit.const, "rollback-audit.json");
  assert.deepEqual(packageReleaseArchiveManifestSchema.properties.failed.properties.deprecation.required, ["attempted", "allowed", "command", "result"]);
  assert.deepEqual(packageReleaseArchiveManifestSchema.properties.replacement.required, ["packageVersion", "npmView", "distTarball", "downstreamGate", "replacementAudit"]);
  assert.equal(packageReleaseArchiveManifestSchema.properties.replacement.properties.replacementAudit.const, "replacement-patch-audit.json");
  assert.deepEqual(packageReleaseArchiveManifestSchema.properties.retention.required, ["policy", "storage", "retainUntil", "artifacts"]);
  assert.equal(packageReleaseArchiveManifestSchema.properties.retention.properties.policy.const, "jury.package_release_retention.v1");
  assert.deepEqual(packageReleaseArchiveManifestSchema.properties.retention.properties.artifacts.allOf.map((rule) => rule.contains.const), [
    "jury-package-dry-run",
    "jury-package-release-evidence",
    "jury-package-release-replay-summary",
    "rollback-audit.json",
    "replacement-patch-audit.json",
    "archive-drift-remediation-audit.json",
    "archive-drift-remediation-audit-handoff.json",
    "jury-package-release-replay-summary-diagnostics.json",
    "jury-package-release-replay-summary-diagnostics-retention-handoff.json",
    "jury-package-release-replay-summary-expiry-handoff.json",
  ]);
  const archiveProvenance = packageReleaseArchiveManifestSchema.properties.provenance;
  assert.deepEqual(archiveProvenance.required, ["source", "workflow", "runId", "sourceRevision", "artifacts"]);
  assert.equal(archiveProvenance.properties.source.const, "github-actions");
  assert.equal(archiveProvenance.properties.workflow.const, "jury-npm-publish.yml");
  assert.deepEqual(archiveProvenance.properties.artifacts.allOf.map((rule) => rule.contains.properties.name.const), [
    "jury-package-dry-run",
    "jury-package-release-evidence",
    "jury-package-release-replay-summary",
  ]);
  assert.deepEqual(archiveProvenance.properties.artifacts.items.properties.name.enum, [
    "jury-package-dry-run",
    "jury-package-release-evidence",
    "jury-package-release-replay-summary",
  ]);
  assert.equal(archiveProvenance.properties.artifacts.items.properties.retentionDays.const, 90);
  assert.equal(packageReleaseArchiveManifestSchema.properties.archiveEvidence.minItems, 13);
  assert.deepEqual(packageReleaseArchiveManifestSchema.properties.archiveEvidence.allOf.map((rule) => rule.contains.properties.path.const), [
    "jury-pack-dry-run-record.json",
    "failed-npm-view.json",
    "downstream-failure-gate.json",
    "rollback-audit.json",
    "replacement-npm-view.json",
    "replacement-downstream-gate.json",
    "replacement-patch-audit.json",
    "archive-drift-remediation-audit.json",
    "archive-drift-remediation-audit-handoff.json",
    "jury-package-release-replay-summary.md",
    "jury-package-release-replay-summary-diagnostics.json",
    "jury-package-release-replay-summary-diagnostics-retention-handoff.json",
    "jury-package-release-replay-summary-expiry-handoff.json",
  ]);
  assert.equal(packageReleaseArchiveManifestSchema.properties.archiveEvidence.items.properties.sha256.pattern, "^sha256:[a-f0-9]{64}$");
  assert.equal(packageReleaseRemediationAuditSchema.properties.schema_version.const, "jury.package_release_remediation_audit.v1");
  assert.equal(packageReleaseRemediationAuditSchema.properties.audit_type.const, "retained-archive-drift-remediation");
  assert.deepEqual(packageReleaseRemediationAuditSchema.required, ["schema_version", "audit_type", "package", "failed", "replacement", "drift", "remediation", "verification", "approval", "record"]);
  assert.deepEqual(packageReleaseRemediationAuditSchema.properties.drift.required, ["detectedBy", "manifest", "evidence"]);
  assert.equal(packageReleaseRemediationAuditSchema.properties.drift.properties.detectedBy.const, "fixtures:package-release:drift");
  assert.equal(packageReleaseRemediationAuditSchema.properties.drift.properties.evidence.items.properties.archive.enum.length, 3);
  assert.equal(packageReleaseRemediationAuditSchema.properties.remediation.properties.policy.const, "restore-before-regenerate");
  assert.equal(packageReleaseRemediationAuditSchema.properties.remediation.properties.regeneratedManifest.const, "retained-package-release-evidence-manifest.json");
  assert.equal(packageReleaseRemediationAuditHandoffSchema.properties.schema_version.const, "jury.package_release_remediation_audit_handoff.v1");
  assert.deepEqual(packageReleaseRemediationAuditHandoffSchema.properties.driftEvidence.allOf.map((rule) => rule.contains.const), [
    "downstream-failure-gate.json",
    "replacement-downstream-gate.json",
  ]);
  assert.deepEqual(packageReleaseRemediationAuditHandoffSchema.properties.restoredEvidence.allOf.map((rule) => rule.contains.const), [
    "downstream-failure-gate.json",
    "replacement-downstream-gate.json",
  ]);
  assert.match(packageReleaseRemediationAuditHandoffSchema.properties.approvedAt.pattern, /\\d\{4\}/);
  assert.equal(packageReleaseReplaySummaryDiagnosticsSchema.properties.schema_version.const, "jury.package_release_replay_summary_diagnostics.v1");
  assert.deepEqual(packageReleaseReplaySummaryDiagnosticsSchema.required, ["schema_version", "sourceJob", "summaryArtifact", "summaryFile", "failedPackageVersion", "failedTarballName", "replacementPackageVersion", "failedArchiveEvidence", "replacementArchiveEvidence", "remediationApprovedBy", "checkedLines"]);
  assert.equal(packageReleaseReplaySummaryDiagnosticsSchema.properties.sourceJob.const, "package-release-evidence-replay");
  assert.equal(packageReleaseReplaySummaryDiagnosticsSchema.properties.summaryArtifact.const, "jury-package-release-replay-summary");
  assert.equal(packageReleaseReplaySummaryDiagnosticsSchema.properties.summaryFile.const, "jury-package-release-replay-summary.md");
  assert.equal(packageReleaseReplaySummaryDiagnosticsSchema.properties.checkedLines.minItems, 7);
  assert.equal(packageReleaseReplaySummaryDiagnosticsRetentionHandoffSchema.properties.schema_version.const, "jury.package_release_replay_summary_diagnostics_retention_handoff.v1");
  assert.deepEqual(packageReleaseReplaySummaryDiagnosticsRetentionHandoffSchema.required, ["schema_version", "reason", "sourceArtifact", "sourceJob", "retentionDays", "diagnosticsSchemaVersion", "retainedDiagnostics", "summaryFile", "retainedWith", "failedPackageVersion", "failedTarballName", "replacementPackageVersion", "runId", "sourceRevision", "reviewedBy"]);
  assert.equal(packageReleaseReplaySummaryDiagnosticsRetentionHandoffSchema.properties.sourceArtifact.const, "jury-package-release-replay-summary");
  assert.equal(packageReleaseReplaySummaryDiagnosticsRetentionHandoffSchema.properties.sourceJob.const, "package-release-evidence-replay");
  assert.equal(packageReleaseReplaySummaryDiagnosticsRetentionHandoffSchema.properties.retentionDays.const, 90);
  assert.equal(packageReleaseReplaySummaryDiagnosticsRetentionHandoffSchema.properties.diagnosticsSchemaVersion.const, "jury.package_release_replay_summary_diagnostics.v1");
  assert.equal(packageReleaseReplaySummaryDiagnosticsRetentionHandoffSchema.properties.retainedDiagnostics.const, "jury-package-release-replay-summary-diagnostics.json");
  assert.equal(packageReleaseReplaySummaryDiagnosticsRetentionHandoffSchema.properties.retainedWith.minItems, 3);
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
  assert.ok(migration.includes("CI adoption guide paths"));
  assert.ok(migration.includes("workflow variants"));
});

test("release checklist links the adoption path and valid artifacts", async () => {
  const checklistPath = join(repoRoot, "jury/RELEASE_CHECKLIST.md");
  const checklist = await readFile(checklistPath, "utf8");
  const readme = await readFile(join(repoRoot, "jury/README.md"), "utf8");
  const release = JSON.parse(await readFile(releasePath, "utf8"));
  const linkedTargets = [...checklist.matchAll(/\[[^\]]+\]\(([^)]+)\)/g)].map((match) => match[1]);

  for (const requiredLink of [
    "QUICKSTART.md",
    "CI_ADOPTION.md",
    "release.json",
    "PUBLISHING.md",
    "examples/ci/jury-package-manifest-check.yml",
    "examples/ci/jury-npm-publish.yml",
    "examples/ci/jury-review-gate.yml",
    "examples/ci/jury-signed-review-gate.yml",
    "examples/ci/jury-signed-artifact-handoff.yml",
    "examples/ci/jury-trusted-bundle-verify.yml",
    "examples/ci/jury-code-change-adoption.yml",
    "examples/ci/fixtures/quickstart",
    "examples/code-change-adoption/README.md",
    "examples/code-change-adoption/verdict.retry.json",
    "examples/code-change-adoption/gate.retry.json",
    "examples/code-change-adoption/review-bundle.retry.json",
    "examples/code-change-adoption/verdict.accept.json",
    "examples/code-change-adoption/gate.accept.json",
    "examples/code-change-adoption/review-bundle.accept.json",
    "MIGRATION.md",
    "TROUBLESHOOTING.md",
    "MAINTAINER_HANDOFF.md",
    "examples/ci/fixtures/quickstart/verdict.json",
    "examples/ci/fixtures/quickstart/review-bundle.json",
    "examples/ci/fixtures/quickstart/gate.json",
    "examples/ci/fixtures/key-policy",
    "examples/ci/fixtures/key-policy-rotation",
    "examples/ci/fixtures/key-policy/jury-key-policy.json",
    "examples/ci/fixtures/key-policy/jury-key-policy.untrusted-producer.json",
    "examples/ci/fixtures/key-policy/ci-public.pem",
    "examples/ci/fixtures/key-policy/review-bundle.signed.json",
    "examples/ci/fixtures/key-policy/README.md",
    "examples/ci/fixtures/key-policy-rotation/jury-key-policy.rotation.json",
    "examples/ci/fixtures/key-policy-rotation/jury-key-policy.revoked-old.json",
    "examples/ci/fixtures/key-policy-rotation/ci-old-public.pem",
    "examples/ci/fixtures/key-policy-rotation/ci-new-public.pem",
    "examples/ci/fixtures/key-policy-rotation/review-bundle.old.signed.json",
    "examples/ci/fixtures/key-policy-rotation/review-bundle.new.signed.json",
    "examples/ci/fixtures/key-policy-rotation/README.md",
    "examples/ci/fixtures/package-release",
    "examples/ci/fixtures/package-release/README.md",
    "examples/ci/fixtures/package-release/archive-drift-remediation-audit.json",
    "examples/ci/fixtures/package-release/archive-drift-remediation-audit-handoff.json",
    "examples/ci/fixtures/package-release/jury-pack-dry-run-record.json",
    "examples/ci/fixtures/package-release/failed-npm-view.json",
    "examples/ci/fixtures/package-release/downstream-failure-gate.json",
    "examples/ci/fixtures/package-release/rollback-audit.json",
    "examples/ci/fixtures/package-release/replacement-npm-view.json",
    "examples/ci/fixtures/package-release/replacement-downstream-gate.json",
    "examples/ci/fixtures/package-release/replacement-patch-audit.json",
    "examples/ci/fixtures/package-release/retained-package-release-evidence-manifest.json",
    "examples/ci/fixtures/package-release/jury-package-release-replay-summary-diagnostics.json",
    "examples/ci/fixtures/package-release/jury-package-release-replay-summary-diagnostics-retention-handoff.json",
    "examples/ci/fixtures/package-release/jury-package-release-replay-summary-expiry-handoff.json",
    "schemas/package-release-archive-manifest.schema.json",
    "schemas/package-release-evidence.schema.json",
    "schemas/package-release-remediation-audit.schema.json",
    "schemas/package-release-remediation-audit-handoff.schema.json",
    "schemas/package-release-replay-summary-diagnostics.schema.json",
    "schemas/package-release-replay-summary-diagnostics-retention-handoff.schema.json",
    "schemas/package-release-replay-summary-expiry-handoff.schema.json",
    "scripts/validate-package-release-fixtures.mjs",
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

  assert.ok(checklist.includes("ciAdoption"));
  assert.ok(checklist.includes("package publication"));
  assert.ok(checklist.includes("package:manifest:check"));
  assert.ok(checklist.includes("publication CI runs `package-release-fixtures`"));
  assert.ok(checklist.includes('npm --prefix "$JURY_PACKAGE_DIR" run fixtures:package-release:check'));
  assert.ok(checklist.includes("before `dry-run-publication`"));
  assert.ok(checklist.includes("`jury-package-release-evidence`"));
  assert.ok(checklist.includes("`rollback-audit.json`, `replacement-patch-audit.json`, and `archive-drift-remediation-audit.json`"));
  assert.ok(checklist.includes("`jury-package-release-archive-manifest`"));
  assert.ok(checklist.includes("`jury-package-release-replay-summary`"));
  assert.ok(checklist.includes("`jury-package-release-replay-summary.md`"));
  assert.ok(checklist.includes('JURY_PACKAGE_RELEASE_MANIFEST_PATH'));
  assert.ok(checklist.includes("Download `jury-package-release-archive-manifest`"));
  assert.ok(checklist.includes("replays `archive-drift-remediation-audit-handoff.json` against the retained manifest and remediation audit"));
  assert.ok(checklist.includes("failed package version, failed tarball name, replacement package version, failed archive evidence, replacement archive evidence, and remediation approver"));
  assert.ok(checklist.includes("--fixture-dir <downloaded-artifact-dir>"));
  assert.ok(checklist.includes("jury-pack-dry-run.json"));
  assert.ok(checklist.includes("jury-pack-dry-run-record.json"));
  assert.ok(checklist.includes("jury-package-dry-run"));
  assert.ok(checklist.includes("retention-days: 90"));
  assert.ok(checklist.includes("GITHUB_STEP_SUMMARY"));
  assert.ok(checklist.includes("jury-package-release-replay-summary-diagnostics.json"));
  assert.ok(checklist.includes("jury-package-release-replay-summary-diagnostics-retention-handoff.json"));
  assert.ok(checklist.includes("dry_run_reviewer"));
  assert.ok(checklist.includes("npm view @sanogueralorenzo/jury@<packageVersion> version dist.tarball --json"));
  assert.ok(checklist.includes("downstream verification fails after publication"));
  assert.ok(checklist.includes("ship a later patch version"));
  assert.ok(checklist.includes("replacement `packageVersion`"));
  assert.ok(checklist.includes("replacement `dist.tarball`"));
  assert.ok(checklist.includes("replacement downstream verification pass"));
  assert.ok(checklist.includes("failed-version deprecation result"));
  assert.ok(checklist.includes("Promote failed and replacement release evidence"));
  assert.ok(checklist.includes("Promote `jury-package-release-replay-summary.md`"));
  assert.ok(checklist.includes("Promote `jury-package-release-replay-summary-diagnostics.json`"));
  assert.ok(checklist.includes("Promote `jury-package-release-replay-summary-diagnostics-retention-handoff.json`"));
  assert.ok(checklist.includes("Promote `jury-package-release-replay-summary-expiry-handoff.json`"));
  assert.ok(checklist.includes("Promote `archive-drift-remediation-audit-handoff.json`"));
  assert.ok(checklist.includes("replays the generated diagnostics retention handoff"));
  assert.ok(checklist.includes("Record retained artifact provenance"));
  assert.ok(checklist.includes("If replay summary retention fails"));
  assert.ok(checklist.includes("If replay summary diagnostics fail"));
  assert.ok(checklist.includes("If replay summary diagnostics retention handoff fails"));
  assert.ok(checklist.includes("If replay summary diagnostics retention handoff CI replay enforcement fails"));
  assert.ok(checklist.includes("If the remediation audit handoff schema fails"));
  assert.ok(checklist.includes("drift evidence, restored evidence, verification commands, workflow run id, source revision, approver, and approval time"));
  assert.ok(checklist.includes("If remediation audit handoff CI workflow enforcement fails"));
  assert.ok(checklist.includes("replay `archive-drift-remediation-audit-handoff.json` locally against retained failed and replacement archive evidence"));
  assert.ok(checklist.includes("If the replay summary diagnostics retention handoff schema fails"));
  assert.ok(checklist.includes("saved summary file"));
  assert.ok(checklist.includes("diagnostics source artifact"));
  assert.ok(checklist.includes("diagnostics schema version"));
  assert.ok(checklist.includes("replay summary provenance"));
  assert.ok(checklist.includes("If the replay summary artifact expired before promotion"));
  assert.ok(checklist.includes("record a reviewed expiry handoff"));
  assert.ok(checklist.includes("If the replay summary expiry handoff schema fails"));
  assert.ok(checklist.includes("If replay summary expiry handoff CI workflow enforcement fails"));
  assert.ok(checklist.includes("replay `jury-package-release-replay-summary-expiry-handoff.json` locally"));
  assert.ok(checklist.includes("`schema_version`, `reason`, `expiredAfterDays`, reconstructed inputs"));
  assert.ok(checklist.includes("approving maintainer before closing the release archive"));
  assert.ok(checklist.includes("workflow run and source revision"));
  assert.ok(checklist.includes("retained-package-release-evidence-manifest.json"));
  assert.ok(checklist.includes("examples/ci/fixtures/package-release/retained-package-release-evidence-manifest.json"));
  assert.ok(checklist.includes("--manifest-out retained-package-release-evidence-manifest.json"));
  assert.ok(checklist.includes("--verify-manifest retained-package-release-evidence-manifest.json"));
  assert.ok(checklist.includes("npm --prefix jury run fixtures:package-release:drift"));
  assert.ok(checklist.includes("checked-in retained archive manifest has not drifted from failed or replacement archive evidence"));
  assert.ok(checklist.includes("If retained archive drift appears"));
  assert.ok(checklist.includes("archive-drift-remediation-audit.json"));
  assert.ok(checklist.includes("archive-drift-remediation-audit-handoff.json"));
  assert.ok(checklist.includes("failed-publication drift, replacement-patch drift"));
  assert.ok(checklist.includes("record the approving maintainer before replacing the archived copy"));
  assert.ok(checklist.includes("schemas/package-release-archive-manifest.schema.json"));
  assert.ok(checklist.includes("If retained package release manifest replay fails"));
  assert.ok(checklist.includes("manifest identity"));
  assert.ok(checklist.includes("required archive evidence"));
  assert.ok(checklist.includes("provenance artifacts"));
  assert.ok(checklist.includes("180 days after replacement downstream verification passes"));
  assert.ok(checklist.includes("package publication rollback evidence"));
  assert.ok(checklist.includes("fixtures:package-release:check"));
  assert.ok(checklist.includes("packageVersion"));
  assert.ok(checklist.includes("tarballName"));
  assert.ok(checklist.includes("reviewedBy"));
  assert.ok(checklist.includes("sanogueralorenzo-jury-0.1.0.tgz"));
  assert.ok(checklist.indexOf("jury-package-dry-run") < checklist.indexOf("secrets.NPM_TOKEN"));
  assert.ok(checklist.includes("stale or mismatched"));
  assert.ok(checklist.includes("secrets.NPM_TOKEN"));
  assert.ok(checklist.includes("@sanogueralorenzo/jury"));
  assert.ok(checklist.includes("NODE_AUTH_TOKEN"));
  assert.ok(checklist.includes("needs: package-manifest"));
  assert.ok(checklist.includes("permissions.id-token: write"));
  assert.ok(checklist.includes("npm publish --provenance --access public"));
  for (const workflow of release.ciAdoption.workflows) {
    assert.ok(linkedTargets.includes(workflow.path), `RELEASE_CHECKLIST.md should link ${workflow.path}`);
  }

  assert.ok(readme.includes("RELEASE_CHECKLIST.md"));
  assert.ok(readme.includes("PUBLISHING.md"));
  assert.ok(readme.includes("CI workflow variants"));

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
    "CI_ADOPTION.md",
    "examples/ci/jury-review-gate.yml",
    "examples/ci/jury-signed-review-gate.yml",
    "examples/ci/jury-signed-artifact-handoff.yml",
    "examples/ci/jury-trusted-bundle-verify.yml",
    "examples/ci/jury-code-change-adoption.yml",
    "examples/ci/jury-package-manifest-check.yml",
    "examples/ci/jury-npm-publish.yml",
    "examples/ci/fixtures/quickstart",
    "examples/code-change-adoption",
    "examples/ci/fixtures/key-policy",
    "examples/ci/fixtures/key-policy-rotation",
    "examples/ci/fixtures/package-release",
    "examples/ci/fixtures/package-release/retained-package-release-evidence-manifest.json",
    "examples/ci/fixtures/package-release/archive-drift-remediation-audit.json",
    "examples/ci/fixtures/package-release/archive-drift-remediation-audit-handoff.json",
    "examples/ci/fixtures/package-release/jury-package-release-replay-summary-diagnostics.json",
    "examples/ci/fixtures/package-release/jury-package-release-replay-summary-diagnostics-retention-handoff.json",
    "schemas/package-release-archive-manifest.schema.json",
    "schemas/package-release-evidence.schema.json",
    "schemas/package-release-remediation-audit.schema.json",
    "schemas/package-release-remediation-audit-handoff.schema.json",
    "schemas/package-release-replay-summary-diagnostics.schema.json",
    "schemas/package-release-replay-summary-diagnostics-retention-handoff.schema.json",
    "scripts/validate-package-release-fixtures.mjs",
    "MIGRATION.md",
    "RELEASE_CHECKLIST.md",
    "PUBLISHING.md",
    "release.json",
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
    "npm --prefix jury run package:manifest:check",
    "npm --prefix jury run fixtures:package-release:check",
    "npm --prefix jury run fixtures:package-release:drift",
  ]);

  for (const artifact of ["verdict.json", "gate.json", "review-bundle.json"]) {
    assert.ok(handoff.includes(artifact), `MAINTAINER_HANDOFF.md should mention ${artifact}`);
  }

  assert.match(handoff, /validates imported bundles before local state is created or mutated/);
  assert.match(handoff, /workflow chooser for unsigned, signed, artifact handoff, and reusable downstream CI paths/);
  assert.match(handoff, /before local state is created or mutated/);
  assert.match(handoff, /producer metadata, provenance, record, cross-reference, and trust policy errors/);
  assert.match(handoff, /expected producer name, producer version, source, and revision pattern/);
  assert.match(handoff, /bundle export --attest-key/);
  assert.match(handoff, /bundle export --attest-private-key/);
  assert.match(handoff, /bundle preflight --verify-attestation-key/);
  assert.match(handoff, /bundle preflight --verify-attestation-public-key/);
  assert.match(handoff, /bundle preflight --key-policy/);
  assert.match(handoff, /trusted producer metadata and RSA public keys/);
  assert.match(handoff, /untrusted-producer troubleshooting policy/);
  assert.match(handoff, /valid_from/);
  assert.match(handoff, /revoked_at/);
  assert.match(handoff, /CI migration overlap window/);
  assert.match(handoff, /revoked-old policy/);
  assert.match(handoff, /rejects stale old-key bundles after cutover/);
  assert.match(handoff, /failed publication rollback, replacement patch supersedence audits/);
  assert.match(handoff, /retained release archive manifest fixture/);
  assert.match(handoff, /matching producer entries/);
  assert.match(handoff, /signature-mismatch statuses/);
  assert.match(handoff, /signs a live bundle with an external CI private key secret/);
  assert.match(handoff, /downloads the signed producer artifact/);
  assert.match(handoff, /reusable workflow that publishes signed retry and accept code-change adoption bundles for downstream verification/);
  assert.match(handoff, /Code-Change Adoption CI Workflow/);
  assert.match(handoff, /uploads `verdict\.retry\.json`, `gate\.retry\.json`, `review-bundle\.retry\.json`, `review-bundle\.retry\.signed\.json`, `verdict\.accept\.json`, `gate\.accept\.json`, `review-bundle\.accept\.json`, `review-bundle\.accept\.signed\.json`/);
  assert.match(handoff, /bundle preflight --bundle review-bundle\.accept\.signed\.json --require-attestation true --verify-attestation-public-key/);
  assert.match(handoff, /\.jury-code-change-downstream/);
  assert.match(handoff, /machine-readable CI adoption guide path and workflow variant metadata/);
  assert.match(handoff, /package publication notes/);
  assert.match(handoff, /code-change adoption fixture/);
  assert.match(handoff, /portable `review-bundle\.retry\.json` carrying actionable scope-critic next actions/);
  assert.match(handoff, /portable `review-bundle\.accept\.json`/);
  assert.match(handoff, /dry-run release publication checklist guidance/);
  assert.match(handoff, /dry-run publication artifact handoff/);
  assert.match(handoff, /dry-run artifact retention expectations/);
  assert.match(handoff, /replay summary retention handoff/);
  assert.match(handoff, /replay summary diagnostics retention handoff/);
  assert.match(handoff, /package release evidence retention policy for failed and replacement release artifacts/);
  assert.match(handoff, /package release artifact provenance checks for retained failed and replacement evidence/);
  assert.match(handoff, /Retained package release evidence manifest export is available/);
  assert.match(handoff, /archive drift checking/);
  assert.match(handoff, /Manifest Replay Troubleshooting/);
  assert.match(handoff, /Retained package release evidence manifest replay troubleshooting now covers/);
  assert.match(handoff, /JSON schema contract for retained package release archive manifests/);
  assert.match(handoff, /jury\.package_release_archive_manifest\.v1/);
  assert.match(handoff, /schemas\/package-release-archive-manifest\.schema\.json/);
  assert.match(handoff, /--manifest-out retained-package-release-evidence-manifest\.json/);
  assert.match(handoff, /--verify-manifest retained-package-release-evidence-manifest\.json/);
  assert.match(handoff, /schema_version must equal jury\.package_release_archive_manifest\.v1/);
  assert.match(handoff, /does not match retained package release evidence/);
  assert.match(handoff, /retained file presence checks/);
  assert.match(handoff, /missing retained manifest diagnostics/);
  assert.match(handoff, /missing retained file diagnostics/);
  assert.match(handoff, /retentionDays: 90/);
  assert.match(handoff, /source revision/);
  assert.match(handoff, /90 days/);
  assert.match(handoff, /180 days after replacement downstream verification passes/);
  assert.match(handoff, /post-publication package metadata comparison guidance/);
  assert.match(handoff, /downstream verification rollback notes/);
  assert.match(handoff, /replacement patch supersedence evidence/);
  assert.match(handoff, /package release evidence fixture examples/);
  assert.match(handoff, /package release evidence schema validation/);
  assert.match(handoff, /JSON schema contract for package release evidence audit files/);
  assert.match(handoff, /dry-run publication summary output/);
  assert.match(handoff, /dry-run package summary reviewer audit notes/);
  assert.match(handoff, /stale dry-run artifact troubleshooting/);
  assert.match(handoff, /npm token and provenance release checklist guidance/);
  assert.match(handoff, /CI adoption metadata contract/);
  assert.match(handoff, /release metadata/);
  assert.match(handoff, /package tarball manifest checks/);
  assert.match(handoff, /package manifest troubleshooting/);
  assert.match(handoff, /reusable workflow step that runs the package manifest check before publication/);
  assert.match(handoff, /release workflow example where npm publication depends on the package manifest check, package release evidence fixture validation, a downloaded and replayed release evidence audit artifact/);
  assert.match(handoff, /downloaded and replayed retained archive manifest artifact/);
  assert.match(handoff, /Manifest CI Handoff/);
  assert.match(handoff, /jury-package-release-archive-manifest/);
  assert.match(handoff, /JURY_PACKAGE_RELEASE_MANIFEST_PATH/);
  assert.match(handoff, /before `dry-run-publication`/);
  assert.match(handoff, /Remediation Audit CI Handoff/);
  assert.match(handoff, /uploads .*archive-drift-remediation-audit\.json.* inside the `jury-package-release-evidence` artifact/);
  assert.match(handoff, /missing remediation audit records, failed-publication drift, replacement-patch drift, restored evidence, verification commands, and maintainer approval are checked before `dry-run-publication`/);
  assert.match(handoff, /Replay Artifact Summary/);
  assert.match(handoff, /Jury package release replay/);
  assert.match(handoff, /failed package version, failed tarball name, replacement package version, failed archive evidence, replacement archive evidence, and remediation approver before `dry-run-publication`/);
  assert.match(handoff, /saved as `jury-package-release-replay-summary\.md` and uploaded as the `jury-package-release-replay-summary` artifact with `retention-days: 90`/);
  assert.match(handoff, /Replay Summary CI Workflow Diagnostics/);
  assert.match(handoff, /jury\.package_release_replay_summary_diagnostics\.v1/);
  assert.match(handoff, /schemas\/package-release-replay-summary-diagnostics\.schema\.json/);
  assert.match(handoff, /jury-package-release-replay-summary-diagnostics\.json/);
  assert.match(handoff, /checked summary lines/);
  assert.match(handoff, /Replay Summary Diagnostics Retention Handoff/);
  assert.match(handoff, /jury\.package_release_replay_summary_diagnostics_retention_handoff\.v1/);
  assert.match(handoff, /schemas\/package-release-replay-summary-diagnostics-retention-handoff\.schema\.json/);
  assert.match(handoff, /jury-package-release-replay-summary-diagnostics-retention-handoff\.json/);
  assert.match(handoff, /diagnostics schema version/);
  assert.match(handoff, /Replay Summary Diagnostics Retention Handoff CI Replay Enforcement/);
  assert.match(handoff, /Replay Jury package release replay diagnostics retention handoff/);
  assert.match(handoff, /fails before `dry-run-publication`/);
  assert.match(handoff, /Replay Summary Diagnostics Retention Handoff CI Replay Enforcement Failure Troubleshooting/);
  assert.match(handoff, /workflow ordering checks/);
  assert.match(handoff, /Replay Summary Retention Handoff/);
  assert.match(handoff, /package-release-evidence-replay` source job/);
  assert.match(handoff, /Release Archive Fixture/);
  assert.match(handoff, /examples\/ci\/fixtures\/package-release\/retained-package-release-evidence-manifest\.json/);
  assert.match(handoff, /Keep it synchronized with `rollback-audit\.json`/);
  assert.match(handoff, /--verify-manifest examples\/ci\/fixtures\/package-release\/retained-package-release-evidence-manifest\.json/);
  assert.match(handoff, /Archive Drift Check/);
  assert.match(handoff, /fixtures:package-release:drift/);
  assert.match(handoff, /matches the failed publication archive evidence, replacement patch archive evidence, retention policy, artifact provenance, and archive evidence digests/);
  assert.match(handoff, /Archive Drift Remediation/);
  assert.match(handoff, /restore the changed failed or replacement archive evidence before regenerating/);
  assert.match(handoff, /record the approving maintainer in the release or incident record/);
  assert.match(handoff, /Remediation Audit Record/);
  assert.match(handoff, /archive-drift-remediation-audit\.json/);
  assert.match(handoff, /failed-publication drift, replacement-patch drift, restored evidence, verification commands, manifest regeneration, diff review, and maintainer approval/);
  assert.match(handoff, /Remediation Audit Handoff/);
  assert.match(handoff, /archive-drift-remediation-audit-handoff\.json/);
  assert.match(handoff, /jury\.package_release_remediation_audit_handoff\.v1/);
  assert.match(handoff, /schemas\/package-release-remediation-audit-handoff\.schema\.json/);
  assert.match(handoff, /package release evidence artifact upload guidance/);
  assert.match(handoff, /package release evidence artifact download and replay guidance/);
  assert.match(handoff, /archive drift remediation audit handoff schema failure troubleshooting/);
  assert.match(handoff, /archive drift remediation audit handoff CI workflow enforcement/);
  assert.match(handoff, /archive drift remediation audit handoff CI workflow enforcement failure troubleshooting/);
  assert.match(handoff, /Package release evidence replay troubleshooting now covers/);
  assert.match(handoff, /Remediation Audit Replay Troubleshooting/);
  assert.match(handoff, /executable examples for missing `approvedBy` and missing verification commands/);
  assert.match(handoff, /replay rejects the approval or command evidence required before replacing a retained manifest/);
  assert.match(handoff, /Remediation Audit Handoff Schema Failure Troubleshooting/);
  assert.match(handoff, /validator failures for `archive-drift-remediation-audit-handoff\.json`/);
  assert.match(handoff, /retained companion file checks/);
  assert.match(handoff, /drift evidence, restored evidence, verification commands, regenerated manifest, diff review, and maintainer approval checks/);
  assert.match(handoff, /Remediation Audit Handoff CI Workflow Enforcement/);
  assert.match(handoff, /Replay Jury package release remediation audit handoff/);
  assert.match(handoff, /before replay summary generation/);
  assert.match(handoff, /Remediation Audit Handoff CI Workflow Enforcement Failure Troubleshooting/);
  assert.match(handoff, /workflow ordering checks that prove replay runs after manifest replay/);
  assert.match(handoff, /Replay Artifact Summary Troubleshooting/);
  assert.match(handoff, /reconstruct the expected failed\/replacement archive summary from the retained evidence/);
  assert.match(handoff, /failed package identity, replacement package identity, retained archive evidence lists, or remediation approver/);
  assert.match(handoff, /Replay Summary CI Workflow Diagnostics Troubleshooting/);
  assert.match(handoff, /diagnostics JSON shape/);
  assert.match(handoff, /no longer proves the failed and replacement archive evidence behind the workflow summary/);
  assert.match(handoff, /Replay Summary Diagnostics Retention Handoff Troubleshooting/);
  assert.match(handoff, /diagnostics retention for failed and replacement release archives/);
  assert.match(handoff, /Replay Summary Diagnostics Retention Handoff Schema Failure Troubleshooting/);
  assert.match(handoff, /schema-critical field inspection/);
  assert.match(handoff, /workflow run id/);
  assert.match(handoff, /Replay Summary Retention Failure Troubleshooting/);
  assert.match(handoff, /missing `jury-package-release-replay-summary\.md`/);
  assert.match(handoff, /wrong `package-release-evidence-replay` source job/);
  assert.match(handoff, /Replay Summary Artifact Expiry Remediation Handoff/);
  assert.match(handoff, /jury\.package_release_replay_summary_expiry_handoff\.v1/);
  assert.match(handoff, /reviewing maintainer/);
  assert.match(handoff, /schemas\/package-release-replay-summary-expiry-handoff\.schema\.json/);
  assert.match(handoff, /jury-package-release-replay-summary-expiry-handoff\.json/);
  assert.match(handoff, /Replay Summary Expiry Handoff Schema Failure Troubleshooting/);
  assert.match(handoff, /schema-critical field inspection/);
  assert.match(handoff, /retained manifest relationship checks for failed and replacement package versions/);
  assert.match(handoff, /maintainer approval checks against `archive-drift-remediation-audit\.json`/);
  assert.match(handoff, /Replay Summary Expiry Handoff CI Workflow Enforcement/);
  assert.match(handoff, /Replay Jury package release replay summary expiry handoff/);
  assert.match(handoff, /retained evidence artifact provenance/);
  assert.match(handoff, /Replay Summary Expiry Handoff CI Workflow Enforcement Failure Troubleshooting/);
  assert.match(handoff, /workflow ordering checks that prove replay runs after diagnostics retention handoff replay/);
  assert.match(handoff, /JURY_PACKAGE_RELEASE_EVIDENCE_DIR/);
  assert.match(handoff, /replacement-patch-audit\.json\.checks is required/);
  assert.match(handoff, /package release evidence fixture validation/);
  assert.match(handoff, /package release fixture workflow gating/);
  assert.match(handoff, /release evidence replay failure troubleshooting for package rollback and replacement audits/);
  assert.match(handoff, /Goal Closure Evidence/);
  assert.match(handoff, /linked schemas, fixtures, CI workflow examples, troubleshooting commands, release checklist references, and validation commands above/);
  assert.match(handoff, /retained package release evidence manifest archive drift remediation audit record CI replay artifact summary retention failure CI artifact expiry remediation handoff schema failure CI workflow summary diagnostics retention handoff schema failure troubleshooting CI replay enforcement failure troubleshooting remediation audit handoff schema failure troubleshooting CI workflow enforcement failure troubleshooting for failed and replacement release archives/);
  assert.match(handoff, /Subagent Audit Evidence/);
  assert.match(handoff, /Curie \(`019e54fa-5822-71d2-8aa1-f849b85b4665`\) completed a read-only audit on 2026-05-23/);
  assert.match(handoff, /should require `jury-package-release-replay-summary-expiry-handoff\.json`/);
  assert.match(handoff, /requires the expiry handoff in both `retention\.artifacts` and `archiveEvidence`/);
  assert.match(handoff, /Next Hardening Step/);
  assert.match(handoff, /key-policy-backed downstream verifier fixture for signed code-change adoption bundles/);
  assert.match(handoff, /verify producer identity without wiring raw public-key flags/);
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

async function assertPathMissing(path) {
  try {
    await stat(path);
  } catch (error) {
    assert.equal(error.code, "ENOENT");
    return;
  }

  assert.fail(`${path} should not exist`);
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

function extractWorkflowUploadPaths(workflow) {
  const lines = workflow.split("\n");
  const paths = [];

  for (let index = 0; index < lines.length; index += 1) {
    const line = lines[index];
    const pathMatch = line.match(/^(\s*)path:\s*\|$/);
    if (!pathMatch) {
      continue;
    }

    const pathIndent = pathMatch[1].length;
    for (let pathLineIndex = index + 1; pathLineIndex < lines.length; pathLineIndex += 1) {
      const pathLine = lines[pathLineIndex];
      if (pathLine.trim() === "") {
        continue;
      }

      const currentIndent = pathLine.match(/^(\s*)/)?.[1].length ?? 0;
      if (currentIndent <= pathIndent) {
        break;
      }

      paths.push(pathLine.trim());
    }
  }

  return paths;
}

function extractWorkflowCallInputDefaults(workflow) {
  const lines = workflow.split("\n");
  const defaults = new Map();
  let currentInput = null;

  for (const line of lines) {
    const inputMatch = line.match(/^      ([a-z][a-z0-9-]*):$/);
    if (inputMatch) {
      currentInput = inputMatch[1];
      continue;
    }

    const defaultMatch = line.match(/^        default: (.+)$/);
    if (currentInput && defaultMatch) {
      defaults.set(currentInput, defaultMatch[1]);
    }
  }

  return defaults;
}

function packManifestFiles(paths) {
  return [...new Set(paths)].map((path) => ({ path }));
}

function shellQuote(value) {
  return `'${String(value).replaceAll("'", "'\\''")}'`;
}
