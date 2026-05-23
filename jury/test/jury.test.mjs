import test from "node:test";
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { generateKeyPairSync } from "node:crypto";
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
  const dryRunCommands = extractWorkflowRunBlock(workflow, "Create Jury package dry-run record");
  const verifyCommands = extractWorkflowRunBlock(workflow, "Verify Jury package dry-run record");
  const publishCommands = extractWorkflowRunBlock(workflow, "Publish Jury package");

  assert.ok(workflow.includes("workflow_dispatch"));
  assert.ok(workflow.includes("permissions:"));
  assert.ok(workflow.includes("id-token: write"));
  assert.ok(workflow.includes("package-manifest:"));
  assert.ok(workflow.includes("uses: ./.github/workflows/jury-package-manifest-check.yml"));
  assert.ok(workflow.includes("dry-run-publication:"));
  assert.ok(workflow.includes("needs: package-manifest"));
  assert.ok(workflow.includes("actions/upload-artifact@v4"));
  assert.ok(workflow.includes("actions/download-artifact@v4"));
  assert.ok(workflow.includes("jury-package-dry-run"));
  assert.ok(workflow.includes("jury-pack-dry-run.json"));
  assert.ok(workflow.includes("jury-pack-dry-run-record.json"));
  assert.ok(workflow.includes("needs: package-manifest"));
  assert.ok(workflow.includes("NODE_AUTH_TOKEN: ${{ secrets.NPM_TOKEN }}"));
  assert.ok(workflow.indexOf("dry-run-publication:") < workflow.indexOf("publish:"));
  assert.ok(workflow.indexOf("Download Jury package dry-run record") < workflow.indexOf("Verify Jury package dry-run record"));
  assert.ok(workflow.indexOf("Verify Jury package dry-run record") < workflow.indexOf("NODE_AUTH_TOKEN"));
  assert.ok(workflow.indexOf("needs: package-manifest") < workflow.indexOf("npm publish --provenance --access public"));
  assert.deepEqual(dryRunCommands, [
    '(cd "$JURY_PACKAGE_DIR" && npm pack --dry-run --json) > jury-pack-dry-run.json',
    'node -e \'const fs=require("node:fs"); const [pack]=JSON.parse(fs.readFileSync("jury-pack-dry-run.json","utf8")); fs.writeFileSync("jury-pack-dry-run-record.json", JSON.stringify({ packageVersion: pack.version, tarballName: pack.filename }, null, 2) + "\\n");\'',
  ]);
  assert.deepEqual(verifyCommands, [
    'node -e \'const fs=require("node:fs"); const pkg=JSON.parse(fs.readFileSync("jury/package.json","utf8")); const record=JSON.parse(fs.readFileSync("jury-pack-dry-run-record.json","utf8")); const expectedTarball=`sanogueralorenzo-jury-${pkg.version}.tgz`; if (record.packageVersion !== pkg.version) throw new Error(`packageVersion ${record.packageVersion} did not match ${pkg.version}`); if (record.tarballName !== expectedTarball) throw new Error(`tarballName ${record.tarballName} did not match ${expectedTarball}`);\'',
  ]);
  assert.deepEqual(publishCommands, [
    'test -n "$NODE_AUTH_TOKEN"',
    'cd "$JURY_PACKAGE_DIR"',
    "npm publish --provenance --access public",
  ]);

  const checkout = await copyJuryCheckout();
  try {
    const dryRun = await runShell(dryRunCommands.join("\n"), checkout, { ...fixedEnv, JURY_PACKAGE_DIR: "jury" });
    assert.equal(dryRun.exitCode, 0, `${dryRunCommands.join("\n")}\nstdout:\n${dryRun.stdout}\nstderr:\n${dryRun.stderr}`);

    const record = JSON.parse(await readFile(join(checkout, "jury-pack-dry-run-record.json"), "utf8"));
    assert.deepEqual(record, {
      packageVersion: "0.1.0",
      tarballName: "sanogueralorenzo-jury-0.1.0.tgz",
    });

    const verify = await runShell(verifyCommands.join("\n"), checkout);
    assert.equal(verify.exitCode, 0, `${verifyCommands.join("\n")}\nstdout:\n${verify.stdout}\nstderr:\n${verify.stderr}`);
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
  assert.ok(readme.includes("needs: package-manifest"));
  assert.ok(readme.includes("dry-run-publication"));
  assert.ok(readme.includes("jury-package-dry-run"));
  assert.ok(readme.includes("NODE_AUTH_TOKEN"));
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
  assert.ok(guide.includes("Package Manifest Failure"));
  assert.ok(guide.includes("npm --prefix jury run package:manifest:check"));
  assert.ok(guide.includes("--pack-manifest npm-pack.json"));
  assert.ok(guide.includes("checked_paths"));
  assert.ok(guide.includes("missing"));
  assert.ok(guide.includes("examples/ci/jury-trusted-bundle-verify.yml"));
  assert.ok(guide.includes("examples/ci/fixtures/key-policy"));

  const manifestCommands = extractShellBlock(guide, "Package Manifest Failure");
  assert.deepEqual(manifestCommands, ["npm --prefix jury run package:manifest:check"]);
  const manifestCheck = await runShell(manifestCommands[0]);
  assert.equal(manifestCheck.exitCode, 0, manifestCheck.stderr);
  assert.equal(JSON.parse(manifestCheck.stdout.slice(manifestCheck.stdout.indexOf("{"))).ok, true);

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
  assert.ok(publicationNotes.includes("Dry-Run Publication Record"));
  assert.ok(publicationNotes.includes("jury-pack-dry-run.json"));
  assert.ok(publicationNotes.includes("jury-pack-dry-run-record.json"));
  assert.ok(publicationNotes.includes("jury-package-dry-run"));
  assert.ok(publicationNotes.includes("dry-run-publication"));
  assert.ok(publicationNotes.includes("packageVersion"));
  assert.ok(publicationNotes.includes("tarballName"));
  assert.ok(publicationNotes.includes("sanogueralorenzo-jury-0.1.0.tgz"));
  assert.ok(publicationNotes.includes("If the version or tarball name does not match"));
  assert.ok(publicationNotes.includes("TROUBLESHOOTING.md"));
  assert.ok(publicationNotes.includes("secrets.NPM_TOKEN"));
  assert.ok(publicationNotes.includes("NODE_AUTH_TOKEN"));
  assert.ok(publicationNotes.includes("permissions.id-token: write"));
  assert.ok(publicationNotes.includes("npm publish --provenance --access public"));
  assert.ok(publicationNotes.includes("needs: package-manifest"));
  assert.ok(publicationNotes.includes("downloaded dry-run record has verified"));
  assert.ok(publicationNotes.includes("package-manifest and dry-run-publication jobs token-free"));
  assert.ok(publicationNotes.includes("--pack-manifest <npm-pack-json>"));
  assert.ok(publicationNotes.includes('"missing": ["CI_ADOPTION.md"]'));
  assert.ok(publicationNotes.includes('"missing": ["examples/ci/jury-trusted-bundle-verify.yml"]'));

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
    "examples/ci/fixtures/quickstart",
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
  assert.ok(checklist.includes("jury-pack-dry-run.json"));
  assert.ok(checklist.includes("jury-pack-dry-run-record.json"));
  assert.ok(checklist.includes("jury-package-dry-run"));
  assert.ok(checklist.includes("packageVersion"));
  assert.ok(checklist.includes("tarballName"));
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
    "examples/ci/jury-package-manifest-check.yml",
    "examples/ci/jury-npm-publish.yml",
    "examples/ci/fixtures/quickstart",
    "examples/ci/fixtures/key-policy",
    "examples/ci/fixtures/key-policy-rotation",
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
  assert.match(handoff, /matching producer entries/);
  assert.match(handoff, /signature-mismatch statuses/);
  assert.match(handoff, /signs a live bundle with an external CI private key secret/);
  assert.match(handoff, /downloads the signed producer artifact/);
  assert.match(handoff, /machine-readable CI adoption guide path and workflow variant metadata/);
  assert.match(handoff, /package publication notes/);
  assert.match(handoff, /dry-run release publication checklist guidance/);
  assert.match(handoff, /dry-run publication artifact handoff/);
  assert.match(handoff, /stale dry-run artifact troubleshooting/);
  assert.match(handoff, /npm token and provenance release checklist guidance/);
  assert.match(handoff, /CI adoption metadata contract/);
  assert.match(handoff, /release metadata/);
  assert.match(handoff, /package tarball manifest checks/);
  assert.match(handoff, /package manifest troubleshooting/);
  assert.match(handoff, /reusable workflow step that runs the package manifest check before publication/);
  assert.match(handoff, /release workflow example where npm publication depends on the package manifest check and a downloaded dry-run publication record/);
  assert.match(handoff, /CI summary output for the verified dry-run publication record/);
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
