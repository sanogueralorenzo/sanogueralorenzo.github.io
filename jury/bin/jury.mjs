#!/usr/bin/env node

import { mkdir, readFile, writeFile, appendFile, rm, readdir } from "node:fs/promises";
import { readFileSync } from "node:fs";
import { spawn } from "node:child_process";
import { createHmac, createPrivateKey, createPublicKey, createSign, createVerify, timingSafeEqual } from "node:crypto";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const DEFAULT_STATE_DIR = ".jury";
const VERDICT_SCHEMA_VERSION = "jury.verdict.v1";
const REVIEW_BUNDLE_SCHEMA_VERSION = "jury.review_bundle.v1";
const KEY_POLICY_SCHEMA_VERSION = "jury.key_policy.v1";
const PRODUCER_NAME = "@sanogueralorenzo/jury";
const PRODUCER_VERSION = "0.1.0";
const VALID_DECISIONS = new Set(["accept", "reject", "retry", "human_decision"]);
const BLOCKING_SEVERITIES = new Set(["medium", "high", "critical"]);
const STATE_RECORD_TYPES = ["claims", "checks", "evidence", "objections", "waivers", "verdicts"];
const CLAIM_STATUSES = ["draft", "submitted", "screening", "in_review", "revision_required", "ready_for_judgment", "decided", "archived"];
const CHECK_STATUSES = ["pending", "passed", "failed", "waived", "not_applicable"];
const ALLOWED_CLAIM_TRANSITIONS = new Map([
  ["draft", ["submitted"]],
  ["submitted", ["screening"]],
  ["screening", ["in_review"]],
  ["in_review", ["revision_required", "ready_for_judgment"]],
  ["revision_required", ["in_review"]],
  ["ready_for_judgment", ["decided"]],
  ["decided", ["archived"]],
  ["archived", []],
]);
const SCHEMA_DIR = join(dirname(fileURLToPath(import.meta.url)), "..", "schemas");
const command = process.argv[2] ?? "help";
const subcommand = process.argv[3]?.startsWith("--") ? null : process.argv[3] ?? null;
const rawArgs = process.argv.slice(subcommand ? 4 : 3);
const args = parseArgs(rawArgs);
let collectValidationErrors = false;

main().catch((error) => fail(error.message));

async function main() {
  if (command === "help" || args.help) {
    printHelp();
    return;
  }

  if (command === "init") {
    await initState();
    return;
  }

  if (command === "claim" && subcommand === "create") {
    await createClaim();
    return;
  }

  if (command === "claim" && subcommand === "transition") {
    await transitionClaim();
    return;
  }

  if (command === "evidence" && subcommand === "add") {
    await addEvidence();
    return;
  }

  if (command === "check" && subcommand === "add") {
    await addReviewCheck();
    return;
  }

  if (command === "check" && subcommand === "update") {
    await updateReviewCheck();
    return;
  }

  if (command === "objection" && subcommand === "add") {
    await addObjection();
    return;
  }

  if (command === "objection" && subcommand === "resolve") {
    await resolveObjection();
    return;
  }

  if (command === "critic" && subcommand === "run") {
    await runCritic();
    return;
  }

  if (command === "waiver" && subcommand === "add") {
    await addWaiver();
    return;
  }

  if (command === "status") {
    await printStatus();
    return;
  }

  if (command === "judge") {
    await judgeClaim();
    return;
  }

  if (command === "gate") {
    await gateVerdict();
    return;
  }

  if (command === "bundle" && subcommand === "export") {
    await exportBundle();
    return;
  }

  if (command === "bundle" && subcommand === "preflight") {
    await preflightBundle();
    return;
  }

  if (command === "bundle" && subcommand === "import") {
    await importBundle();
    return;
  }

  if (command === "check") {
    await checkState();
    return;
  }

  if (command === "demo" && subcommand === "code-change") {
    await demoCodeChange();
    return;
  }

  fail(`unknown command: ${[command, subcommand].filter(Boolean).join(" ")}`);
}

function parseArgs(values) {
  const parsed = {};

  for (let index = 0; index < values.length; index += 1) {
    const value = values[index];

    if (!value.startsWith("--")) {
      fail(`unexpected positional argument: ${value}`);
    }

    const key = value.slice(2);

    if (["json", "help", "strict"].includes(key)) {
      parsed[key] = true;
      continue;
    }

    const next = values[index + 1];

    if (!next || next.startsWith("--")) {
      fail(`missing value for --${key}`);
    }

    parsed[key] = next;
    index += 1;
  }

  return parsed;
}

async function initState() {
  const dir = stateDir();
  await ensureState(dir);
  print({ ok: true, stateDir: dir, files: stateFiles(dir) });
}

async function createClaim() {
  const dir = stateDir();
  await ensureState(dir);
  const summary = requireArg("summary");
  const id = args.id ?? uniqueId("claim", summary, await readJsonl(fileFor(dir, "claims")));
  const claim = sortRecord({
    schema_version: "jury.claim.v1",
    id,
    version: 1,
    summary,
    claimant: args.claimant ?? "agent:local",
    scope: parseList(args.scope ?? ""),
    impact: args.impact ?? "medium",
    status: "submitted",
    created_at: now(),
    updated_at: now(),
  });

  validateClaim(claim);
  await appendJsonl(fileFor(dir, "claims"), claim);
  print(claim);
}

async function transitionClaim() {
  const dir = stateDir();
  await ensureState(dir);
  const claimId = requireArg("claim");
  const status = requireArg("status");
  const current = await requireClaim(dir, claimId);
  const allowed = ALLOWED_CLAIM_TRANSITIONS.get(current.status) ?? [];

  if (!allowed.includes(status)) {
    fail(`invalid claim transition: ${current.status} -> ${status}`);
  }

  const claim = sortRecord({
    ...current,
    version: current.version + 1,
    status,
    transition_reason: args.reason ?? null,
    updated_at: now(),
  });

  validateClaim(claim);
  await appendJsonl(fileFor(dir, "claims"), claim);
  print(claim);
}

async function addEvidence() {
  const dir = stateDir();
  await ensureState(dir);
  const claimId = requireArg("claim");
  await requireClaim(dir, claimId);
  const existing = await readJsonl(fileFor(dir, "evidence"));
  const type = args.type ?? (args.command ? "command" : "manual");
  let commandResult = {};

  if (args.run) {
    commandResult = await runShell(args.run);
  }

  const source = args.command ?? args.run ?? args.file ?? args.source ?? type;
  const evidence = sortRecord({
    schema_version: "jury.evidence.v1",
    id: args.id ?? uniqueId("ev", `${claimId}_${source}`, existing),
    claim_id: claimId,
    type,
    summary: args.summary ?? source,
    source,
    status: args.status ?? statusFromExitCode(args["exit-code"] ?? commandResult.exit_code),
    command: args.command ?? args.run,
    exit_code: numberOrNull(args["exit-code"] ?? commandResult.exit_code),
    stdout: commandResult.stdout,
    stderr: commandResult.stderr,
    collected_at: now(),
  });

  validateEvidence(evidence);
  await appendJsonl(fileFor(dir, "evidence"), evidence);
  print(evidence);
}

async function addReviewCheck() {
  const dir = stateDir();
  await ensureState(dir);
  const claimId = requireArg("claim");
  await requireClaim(dir, claimId);
  const type = requireArg("type");
  const existing = await readJsonl(fileFor(dir, "checks"));
  const check = sortRecord({
    schema_version: "jury.check.v1",
    id: args.id ?? uniqueId("check", `${claimId}_${type}_${args.summary ?? "required"}`, existing),
    claim_id: claimId,
    type,
    required: parseBoolean(args.required ?? "true", "check.required"),
    status: args.status ?? "pending",
    assigned_to: args["assigned-to"] ?? `${type}:local`,
    summary: args.summary ?? `${type} check`,
    evidence_ids: parseList(args.evidence ?? ""),
    resolution: null,
    created_at: now(),
    updated_at: now(),
  });

  validateCheck(check);
  await appendJsonl(fileFor(dir, "checks"), check);
  print(check);
}

async function updateReviewCheck() {
  const dir = stateDir();
  await ensureState(dir);
  const id = requireArg("id");
  const current = latestById(await readJsonl(fileFor(dir, "checks"))).get(id);

  if (!current) {
    fail(`unknown check: ${id}`);
  }

  const check = sortRecord({
    ...current,
    status: args.status ?? current.status,
    evidence_ids: args.evidence ? parseList(args.evidence) : current.evidence_ids,
    resolution: args.resolution ?? current.resolution,
    updated_at: now(),
  });

  validateCheck(check);
  await appendJsonl(fileFor(dir, "checks"), check);
  print(check);
}

async function addObjection() {
  const dir = stateDir();
  await ensureState(dir);
  const claimId = requireArg("claim");
  await requireClaim(dir, claimId);
  const summary = requireArg("summary");
  const existing = await readJsonl(fileFor(dir, "objections"));
  const objection = sortRecord({
    schema_version: "jury.objection.v1",
    id: args.id ?? uniqueId("obj", `${claimId}_${summary}`, existing),
    claim_id: claimId,
    summary,
    raised_by: args["raised-by"] ?? "critic:local",
    severity: args.severity ?? "medium",
    status: "open",
    evidence_ids: parseList(args.evidence ?? ""),
    resolution: null,
    created_at: now(),
    updated_at: now(),
  });

  validateObjection(objection);
  await appendJsonl(fileFor(dir, "objections"), objection);
  print(objection);
}

async function runCritic() {
  const dir = stateDir();
  await ensureState(dir);
  const claimId = requireArg("claim");
  const role = requireArg("role");
  const review = await reviewForClaim(dir, claimId);
  const objections = criticObjections(review, role);

  for (const objection of objections) {
    validateObjection(objection);
    await appendJsonl(fileFor(dir, "objections"), objection);
  }

  print({ ok: true, role, claim_id: claimId, objections });
}

async function resolveObjection() {
  const dir = stateDir();
  await ensureState(dir);
  const id = requireArg("id");
  const objections = await readJsonl(fileFor(dir, "objections"));
  const current = latestById(objections).get(id);

  if (!current) {
    fail(`unknown objection: ${id}`);
  }

  const resolved = sortRecord({
    ...current,
    status: "resolved",
    resolution: requireArg("resolution"),
    updated_at: now(),
  });

  validateObjection(resolved);
  await appendJsonl(fileFor(dir, "objections"), resolved);
  print(resolved);
}

async function addWaiver() {
  const dir = stateDir();
  await ensureState(dir);
  const objectionId = requireArg("objection");
  const objections = latestById(await readJsonl(fileFor(dir, "objections")));
  const objection = objections.get(objectionId);

  if (!objection) {
    fail(`unknown objection: ${objectionId}`);
  }

  const existing = await readJsonl(fileFor(dir, "waivers"));
  const waiver = sortRecord({
    schema_version: "jury.waiver.v1",
    id: args.id ?? uniqueId("waiver", objectionId, existing),
    objection_id: objectionId,
    claim_id: objection.claim_id,
    approved_by: args["approved-by"] ?? "human:local",
    reason: requireArg("reason"),
    expires_at: args["expires-at"] ?? null,
    created_at: now(),
  });

  validateWaiver(waiver);
  await appendJsonl(fileFor(dir, "waivers"), waiver);
  print(waiver);
}

async function printStatus() {
  const dir = stateDir();
  await ensureState(dir);
  const claimId = requireArg("claim");
  const review = await reviewForClaim(dir, claimId);
  print(review);
}

async function judgeClaim() {
  const dir = stateDir();
  await ensureState(dir);
  const claimId = requireArg("claim");
  const review = await reviewForClaim(dir, claimId);
  const decision = decide(review, args["require-human-approval"] === "true");
  const verdicts = await readJsonl(fileFor(dir, "verdicts"));
  const verdict = sortRecord({
    schema_version: VERDICT_SCHEMA_VERSION,
    id: args.id ?? uniqueId("verdict", `${claimId}_${decision.decision}`, verdicts),
    claim_id: claimId,
    claim_version: review.claim.version,
    decision: decision.decision,
    reason: decision.reason,
    next_actions: decision.next_actions,
    evidence_ids: review.evidence.map((item) => item.id).sort(),
    objection_ids: review.objections.map((item) => item.id).sort(),
    waiver_ids: review.waivers.map((item) => item.id).sort(),
    check_ids: review.checks.map((item) => item.id).sort(),
    decided_by: args["decided-by"] ?? "judge:local",
    decided_at: now(),
  });

  validateVerdict(verdict);
  await appendJsonl(fileFor(dir, "verdicts"), verdict);

  if (args.out) {
    await writeFile(resolve(args.out), `${JSON.stringify(verdict, null, 2)}\n`);
  }

  print(verdict);
}

async function gateVerdict() {
  const path = resolve(requireArg("verdict"));
  const verdict = parseJson(await readFile(path, "utf8"), path);
  validateVerdict(verdict);
  const review = args.claim ? await reviewForClaim(stateDir(), args.claim) : null;
  const details = review ? gateDetails(review, verdict) : gateDetailsFromVerdict(verdict);
  const consistency = review ? gateConsistency(review, verdict) : [];

  if (consistency.length > 0) {
    print({ ok: false, decision: verdict.decision, reason: "Verdict does not match current claim state.", consistency_errors: consistency, ...details });
    process.exitCode = 1;
    return;
  }

  if (verdict.decision !== "accept") {
    print({ ok: false, decision: verdict.decision, reason: verdict.reason, ...details });
    process.exitCode = 1;
    return;
  }

  print({ ok: true, decision: verdict.decision, reason: verdict.reason, ...details });
}

async function exportBundle() {
  const dir = stateDir();
  await ensureState(dir);
  const claimId = requireArg("claim");
  const records = await recordsForClaim(dir, claimId);
  const bundle = sortRecord({
    schema_version: REVIEW_BUNDLE_SCHEMA_VERSION,
    exported_at: now(),
    claim_id: claimId,
    producer: bundleProducer(),
    provenance: bundleProvenance(),
    records,
  });
  const attestKey = args["attest-key"] ?? process.env.JURY_BUNDLE_ATTEST_KEY;
  const attestPrivateKey = args["attest-private-key"] ?? process.env.JURY_BUNDLE_ATTEST_PRIVATE_KEY;

  if (attestKey && attestPrivateKey) {
    fail("use either --attest-key or --attest-private-key, not both");
  }

  if (attestKey) {
    bundle.attestation = signBundle(bundle, attestKey, args["attestation-key-id"] ?? process.env.JURY_BUNDLE_ATTEST_KEY_ID ?? "local");
  } else if (attestPrivateKey) {
    bundle.attestation = signBundleWithPrivateKey(bundle, attestPrivateKey, args["attestation-key-id"] ?? process.env.JURY_BUNDLE_ATTEST_KEY_ID ?? "local");
  }

  validateReviewBundle(bundle);

  if (args.out) {
    await writeFile(resolve(args.out), `${JSON.stringify(bundle, null, 2)}\n`);
  }

  print(bundle);
}

async function importBundle() {
  const path = resolve(requireArg("bundle"));
  const bundle = parseJson(await readFile(path, "utf8"), path);
  const preflight = preflightReviewBundle(bundle);

  if (!preflight.ok) {
    print(preflight);
    process.exitCode = 1;
    return;
  }

  const dir = stateDir();
  await ensureState(dir);

  for (const name of STATE_RECORD_TYPES) {
    for (const record of bundle.records[name]) {
      validateRecord(name, record);
      await appendJsonl(fileFor(dir, name), record);
    }
  }

  let verdictOut = null;

  if (args["verdict-out"]) {
    const latestVerdict = latestVerdictFromBundle(bundle);

    if (!latestVerdict) {
      fail("bundle import --verdict-out requires at least one verdict record");
    }

    verdictOut = resolve(args["verdict-out"]);
    await writeFile(verdictOut, `${JSON.stringify(latestVerdict, null, 2)}\n`);
  }

  print({
    ok: true,
    claim_id: bundle.claim_id,
    producer: bundle.producer,
    provenance: bundle.provenance,
    imported: Object.fromEntries(STATE_RECORD_TYPES.map((name) => [name, bundle.records[name].length])),
    stateDir: dir,
    verdictOut,
  });
}

async function preflightBundle() {
  const path = resolve(requireArg("bundle"));
  const bundle = parseJson(await readFile(path, "utf8"), path);
  const preflight = preflightReviewBundle(bundle);

  print(preflight);

  if (!preflight.ok) {
    process.exitCode = 1;
  }
}

async function checkState() {
  const dir = stateDir();
  await ensureState(dir);
  const checks = [];

  for (const name of STATE_RECORD_TYPES) {
    try {
      const records = await withValidationErrors(() => readJsonl(fileFor(dir, name)));
      for (const record of records) {
        await withValidationErrors(() => validateRecord(name, record));
      }
      checks.push({ name, ok: true });
    } catch (error) {
      checks.push({ name, ok: false, message: error.message });
    }
  }

  checks.push(await checkSchemaFiles());
  checks.push(await checkStateConsistency(dir));

  const ok = checks.every((check) => check.ok);
  print({ ok, checks });

  if (!ok) {
    process.exitCode = 1;
  }
}

function criticObjections(review, role) {
  if (role === "tests") {
    return testsCritic(review);
  }

  if (role === "security") {
    return securityCritic(review);
  }

  if (role === "scope") {
    return scopeCritic(review);
  }

  fail(`critic role must be one of tests, security, scope`);
}

function testsCritic(review) {
  const commandEvidence = review.evidence.filter((item) => item.type === "command");

  if (commandEvidence.length === 0) {
    return [criticObjection(review.claim.id, "tests", "missing_test_evidence", "No command evidence is attached to the claim.", "high", [])];
  }

  const failed = commandEvidence.filter((item) => item.status === "failed");

  if (failed.length > 0) {
    return [criticObjection(review.claim.id, "tests", "failed_test_evidence", "One or more validation commands failed.", "critical", failed.map((item) => item.id))];
  }

  return [];
}

function securityCritic(review) {
  const riskyPatterns = [
    [/rm\s+-rf\s+\/?(?:\s|$)/i, "destructive rm command"],
    [/delete_accounts|drop\s+table|truncate\s+table/i, "destructive data operation"],
    [/curl\b.*\|\s*(?:sh|bash)/i, "curl pipe shell execution"],
    [/\b(?:ghp|github_pat|sk)-[a-z0-9_:-]{10,}/i, "secret-like token"],
    [/\bsudo\b/i, "privileged command"],
  ];
  const hits = [];

  for (const item of review.evidence) {
    const text = [item.source, item.summary, item.command].filter(Boolean).join("\n");
    const match = riskyPatterns.find(([pattern]) => pattern.test(text));

    if (match) {
      hits.push({ evidence: item, reason: match[1] });
    }
  }

  if (hits.length === 0) {
    return [];
  }

  return [criticObjection(
    review.claim.id,
    "security",
    "risky_evidence",
    `Potentially unsafe evidence or command found: ${hits.map((hit) => hit.reason).sort().join(", ")}.`,
    hits.some((hit) => /secret|destructive/.test(hit.reason)) ? "critical" : "high",
    hits.map((hit) => hit.evidence.id),
  )];
}

function scopeCritic(review) {
  if (review.claim.scope.length === 0) {
    return [criticObjection(review.claim.id, "scope", "missing_scope", "The claim has no explicit scope.", "medium", [])];
  }

  const changedFiles = parseList(args["changed-files"] ?? "");

  if (changedFiles.length === 0) {
    return [];
  }

  const outOfScope = changedFiles.filter((file) => !review.claim.scope.some((scope) => file === scope || file.startsWith(`${scope.replace(/\/+$/, "")}/`)));

  if (outOfScope.length === 0) {
    return [];
  }

  return [criticObjection(review.claim.id, "scope", "out_of_scope_changes", `Changed files fall outside claim scope: ${outOfScope.join(", ")}.`, "high", [])];
}

function criticObjection(claimId, role, code, summary, severity, evidenceIds) {
  return sortRecord({
    schema_version: "jury.objection.v1",
    id: `obj_${claimId}_${role}_${code}`,
    claim_id: claimId,
    summary,
    raised_by: `critic:${role}`,
    severity,
    status: "open",
    evidence_ids: evidenceIds.sort(),
    resolution: null,
    created_at: now(),
    updated_at: now(),
  });
}

function gateDetails(review, verdict) {
  return {
    missing_fields: missingReviewFields(review),
    unresolved_objections: review.objections
      .filter((item) => item.status === "open" && BLOCKING_SEVERITIES.has(item.severity))
      .map((item) => ({ id: item.id, severity: item.severity, summary: item.summary })),
    next_actions: verdict.next_actions ?? [],
  };
}

function gateConsistency(review, verdict) {
  const errors = [];

  if (verdict.claim_id !== review.claim.id) {
    errors.push(`verdict.claim_id ${verdict.claim_id} does not match claim ${review.claim.id}`);
  }

  if (verdict.claim_version !== review.claim.version) {
    errors.push(`verdict.claim_version ${verdict.claim_version} does not match current claim version ${review.claim.version}`);
  }

  errors.push(...missingReferences("verdict.evidence_ids", verdict.evidence_ids, new Set(review.evidence.map((item) => item.id))));
  errors.push(...missingReferences("verdict.objection_ids", verdict.objection_ids, new Set(review.objections.map((item) => item.id))));
  errors.push(...missingReferences("verdict.waiver_ids", verdict.waiver_ids, new Set(review.waivers.map((item) => item.id))));
  errors.push(...missingReferences("verdict.check_ids", verdict.check_ids ?? [], new Set(review.checks.map((item) => item.id))));

  return errors;
}

function gateDetailsFromVerdict(verdict) {
  return {
    missing_fields: [],
    unresolved_objections: [],
    next_actions: verdict.next_actions ?? [],
  };
}

function missingReviewFields(review) {
  const missing = [];

  if (review.evidence.length === 0) {
    missing.push("evidence");
  }

  if (!review.claim.scope || review.claim.scope.length === 0) {
    missing.push("claim.scope");
  }

  return missing;
}

async function checkSchemaFiles() {
  try {
    const files = (await readdir(schemaDir())).filter((file) => file.endsWith(".schema.json")).sort();

    if (files.length === 0) {
      return { name: "schema_files", ok: false, message: "no schema files found" };
    }

    for (const file of files) {
      const schema = await withValidationErrors(async () => parseJson(await readFile(join(schemaDir(), file), "utf8"), file));
      await withValidationErrors(() => {
        requireString(schema.$schema, `${file}.$schema`);
        requireString(schema.title, `${file}.title`);
        requireEnum(schema.type, ["object"], `${file}.type`);
        requireArray(schema.required, `${file}.required`);
      });
    }

    return { name: "schema_files", ok: true, files };
  } catch (error) {
    return { name: "schema_files", ok: false, message: error.message };
  }
}

async function checkStateConsistency(dir) {
  try {
    const records = {};

    for (const name of STATE_RECORD_TYPES) {
      records[name] = await readJsonl(fileFor(dir, name));
    }

    const errors = consistencyErrorsForRecords(records);

    if (errors.length > 0) {
      return { name: "state_consistency", ok: false, message: errors.join("; ") };
    }

    return { name: "state_consistency", ok: true };
  } catch (error) {
    return { name: "state_consistency", ok: false, message: error.message };
  }
}

function consistencyErrorsForRecords(records) {
  const claims = latestById(records.claims);
  const checks = latestById(records.checks);
  const evidence = latestById(records.evidence);
  const objections = latestById(records.objections);
  const waivers = latestById(records.waivers);
  const verdicts = latestById(records.verdicts);
  const errors = [];

  for (const check of checks.values()) {
    assertKnownClaim(errors, "check", check.id, check.claim_id, claims);
    errors.push(...missingReferences(`check ${check.id} evidence_ids`, check.evidence_ids, evidence));
    errors.push(...crossClaimReferences(`check ${check.id} evidence_ids`, check.claim_id, check.evidence_ids, evidence));
  }

  for (const item of evidence.values()) {
    assertKnownClaim(errors, "evidence", item.id, item.claim_id, claims);
  }

  for (const objection of objections.values()) {
    assertKnownClaim(errors, "objection", objection.id, objection.claim_id, claims);
    errors.push(...missingReferences(`objection ${objection.id} evidence_ids`, objection.evidence_ids, evidence));
    errors.push(...crossClaimReferences(`objection ${objection.id} evidence_ids`, objection.claim_id, objection.evidence_ids, evidence));
  }

  for (const waiver of waivers.values()) {
    assertKnownClaim(errors, "waiver", waiver.id, waiver.claim_id, claims);

    const objection = objections.get(waiver.objection_id);

    if (!objection) {
      errors.push(`waiver ${waiver.id} references missing objection ${waiver.objection_id}`);
    } else if (objection.claim_id !== waiver.claim_id) {
      errors.push(`waiver ${waiver.id} references objection ${waiver.objection_id} from claim ${objection.claim_id}`);
    }
  }

  for (const verdict of verdicts.values()) {
    const claim = claims.get(verdict.claim_id);

    if (!claim) {
      errors.push(`verdict ${verdict.id} references missing claim ${verdict.claim_id}`);
      continue;
    }

    if (verdict.claim_version !== claim.version) {
      errors.push(`verdict ${verdict.id} claim_version ${verdict.claim_version} does not match current claim version ${claim.version}`);
    }

    errors.push(...missingReferences(`verdict ${verdict.id} evidence_ids`, verdict.evidence_ids, evidence));
    errors.push(...missingReferences(`verdict ${verdict.id} objection_ids`, verdict.objection_ids, objections));
    errors.push(...missingReferences(`verdict ${verdict.id} waiver_ids`, verdict.waiver_ids, waivers));
    errors.push(...missingReferences(`verdict ${verdict.id} check_ids`, verdict.check_ids ?? [], checks));
    errors.push(...crossClaimReferences(`verdict ${verdict.id} evidence_ids`, verdict.claim_id, verdict.evidence_ids, evidence));
    errors.push(...crossClaimReferences(`verdict ${verdict.id} objection_ids`, verdict.claim_id, verdict.objection_ids, objections));
    errors.push(...crossClaimReferences(`verdict ${verdict.id} waiver_ids`, verdict.claim_id, verdict.waiver_ids, waivers));
    errors.push(...crossClaimReferences(`verdict ${verdict.id} check_ids`, verdict.claim_id, verdict.check_ids ?? [], checks));
  }

  return errors;
}

async function recordsForClaim(dir, claimId) {
  const claims = (await readJsonl(fileFor(dir, "claims"))).filter((item) => item.id === claimId).sort(byVersionThenUpdatedAt);

  if (claims.length === 0) {
    fail(`unknown claim: ${claimId}`);
  }

  const byClaim = {};

  for (const name of ["checks", "evidence", "objections", "waivers", "verdicts"]) {
    byClaim[name] = (await readJsonl(fileFor(dir, name))).filter((item) => item.claim_id === claimId).sort(byId);
  }

  return {
    claims,
    checks: byClaim.checks,
    evidence: byClaim.evidence,
    objections: byClaim.objections,
    waivers: byClaim.waivers,
    verdicts: byClaim.verdicts,
  };
}

function validateReviewBundle(bundle) {
  requireEnum(bundle.schema_version, [REVIEW_BUNDLE_SCHEMA_VERSION], "bundle.schema_version");
  requireString(bundle.exported_at, "bundle.exported_at");
  requireString(bundle.claim_id, "bundle.claim_id");
  validateBundleProducer(bundle.producer);
  validateBundleProvenance(bundle.provenance);
  if (bundle.attestation !== undefined) {
    validateBundleAttestation(bundle.attestation);
  }

  if (!bundle.records || typeof bundle.records !== "object" || Array.isArray(bundle.records)) {
    fail("bundle.records must be an object");
  }

  for (const name of STATE_RECORD_TYPES) {
    requireArray(bundle.records[name], `bundle.records.${name}`);

    for (const record of bundle.records[name]) {
      validateRecord(name, record);

      if (name === "claims") {
        if (record.id !== bundle.claim_id) {
          fail(`bundle.records.claims contains claim ${record.id}, expected ${bundle.claim_id}`);
        }
      } else if (record.claim_id !== bundle.claim_id) {
        fail(`bundle.records.${name} contains ${record.id} from claim ${record.claim_id}, expected ${bundle.claim_id}`);
      }
    }
  }

  if (bundle.records.claims.length === 0) {
    fail("bundle.records.claims must include at least one claim record");
  }
}

function preflightReviewBundle(bundle) {
  const errors = [];

  if (!bundle || typeof bundle !== "object" || Array.isArray(bundle)) {
    return { ok: false, errors: ["bundle must be an object"] };
  }

  collectValidationError(errors, () => requireEnum(bundle.schema_version, [REVIEW_BUNDLE_SCHEMA_VERSION], "bundle.schema_version"));
  collectValidationError(errors, () => requireString(bundle.exported_at, "bundle.exported_at"));
  collectValidationError(errors, () => requireString(bundle.claim_id, "bundle.claim_id"));
  collectValidationError(errors, () => validateBundleProducer(bundle.producer));
  collectValidationError(errors, () => validateBundleProvenance(bundle.provenance));
  if (bundle.attestation !== undefined) {
    collectValidationError(errors, () => validateBundleAttestation(bundle.attestation));
  }

  const keyPolicy = keyPolicyCheck(bundle);

  if (!bundle.records || typeof bundle.records !== "object" || Array.isArray(bundle.records)) {
    errors.push("bundle.records must be an object");
    errors.push(...keyPolicy.errors);
    return sortRecord({ ok: false, errors, key_policy: keyPolicy.diagnostics });
  }

  for (const name of STATE_RECORD_TYPES) {
    collectValidationError(errors, () => requireArray(bundle.records[name], `bundle.records.${name}`));

    if (!Array.isArray(bundle.records[name])) {
      continue;
    }

    for (const record of bundle.records[name]) {
      collectValidationError(errors, () => validateRecord(name, record));

      if (!record || typeof record !== "object" || Array.isArray(record)) {
        continue;
      }

      if (name === "claims") {
        if (record.id !== bundle.claim_id) {
          errors.push(`bundle.records.claims contains claim ${record.id}, expected ${bundle.claim_id}`);
        }
      } else if (record.claim_id !== bundle.claim_id) {
        errors.push(`bundle.records.${name} contains ${record.id} from claim ${record.claim_id}, expected ${bundle.claim_id}`);
      }
    }
  }

  if (Array.isArray(bundle.records.claims) && bundle.records.claims.length === 0) {
    errors.push("bundle.records.claims must include at least one claim record");
  }

  if (STATE_RECORD_TYPES.every((name) => Array.isArray(bundle.records[name]))) {
    errors.push(...consistencyErrorsForRecords(bundle.records));
  }

  errors.push(...trustPolicyErrors(bundle));
  errors.push(...keyPolicy.errors);
  errors.push(...attestationPolicyErrors(bundle));

  if (errors.length > 0) {
    return sortRecord({ ok: false, errors, key_policy: keyPolicy.diagnostics });
  }

  return sortRecord({
    ok: true,
    claim_id: bundle.claim_id,
    producer: bundle.producer,
    provenance: bundle.provenance,
    records: Object.fromEntries(STATE_RECORD_TYPES.map((name) => [name, bundle.records[name].length])),
    latest_verdict_id: latestVerdictFromBundle(bundle)?.id ?? null,
    key_policy: keyPolicy.diagnostics,
  });
}

function trustPolicyErrors(bundle) {
  const errors = [];

  if (args["expect-producer-name"] && bundle.producer?.name !== args["expect-producer-name"]) {
    errors.push(`bundle.producer.name expected ${args["expect-producer-name"]}, got ${bundle.producer?.name ?? "missing"}`);
  }

  if (args["expect-producer-version"] && bundle.producer?.version !== args["expect-producer-version"]) {
    errors.push(`bundle.producer.version expected ${args["expect-producer-version"]}, got ${bundle.producer?.version ?? "missing"}`);
  }

  if (args["expect-source"] && bundle.provenance?.source !== args["expect-source"]) {
    errors.push(`bundle.provenance.source expected ${args["expect-source"]}, got ${bundle.provenance?.source ?? "missing"}`);
  }

  if (args["expect-revision-pattern"]) {
    let pattern;

    try {
      pattern = new RegExp(args["expect-revision-pattern"]);
    } catch (error) {
      errors.push(`bundle.provenance.revision pattern is invalid: ${error.message}`);
      return errors;
    }

    const revision = bundle.provenance?.revision;
    if (typeof revision !== "string" || !pattern.test(revision)) {
      errors.push(`bundle.provenance.revision must match ${args["expect-revision-pattern"]}, got ${revision ?? "missing"}`);
    }
  }

  return errors;
}

function keyPolicyCheck(bundle) {
  const policySource = args["key-policy"] ?? process.env.JURY_BUNDLE_KEY_POLICY;

  if (!policySource) {
    return { errors: [], diagnostics: undefined };
  }

  const loaded = loadKeyPolicy(policySource);
  const diagnostics = {
    policy: resolve(policySource),
    matching_producers: [],
    considered_keys: [],
  };

  if (loaded.errors.length > 0) {
    return { errors: loaded.errors, diagnostics };
  }

  const errors = [];
  diagnostics.policy = loaded.path;
  const producers = matchingKeyPolicyProducers(loaded.policy, bundle, diagnostics);

  if (producers.length === 0) {
    errors.push(`key policy has no trusted producer matching ${bundlePolicyDescription(bundle)}`);
    return { errors, diagnostics };
  }

  if (!bundle.attestation) {
    errors.push("bundle.attestation is required by key policy");
    return { errors, diagnostics };
  }

  const keys = matchingKeyPolicyKeys(producers, bundle, diagnostics);

  if (keys.length === 0) {
    errors.push(`key policy has no trusted ${bundle.attestation.type} key ${bundle.attestation.key_id}`);
    return { errors, diagnostics };
  }

  const revokedKeyErrors = keys.flatMap(({ key, diagnostic }) => keyPolicyRevocationErrors(key, diagnostic));

  if (revokedKeyErrors.length > 0) {
    for (const { diagnostic } of keys) {
      if (diagnostic.status === "matched") {
        diagnostic.status = "blocked_by_revocation";
      }
    }
    errors.push(...revokedKeyErrors);
    return { errors, diagnostics };
  }

  const usableKeys = [];
  const keyUseErrors = [];

  for (const keyMatch of keys) {
    const errorsForKey = keyPolicyKeyUseErrors(keyMatch.key, bundle, keyMatch.diagnostic);

    if (errorsForKey.length === 0) {
      keyMatch.diagnostic.status = "usable";
      usableKeys.push(keyMatch);
    } else {
      keyUseErrors.push(...errorsForKey);
    }
  }

  if (usableKeys.length === 0) {
    errors.push(...keyUseErrors);
    return { errors, diagnostics };
  }

  let verified = false;

  for (const { key, diagnostic } of usableKeys) {
    let verifiedBundleWithKey = false;

    try {
      verifiedBundleWithKey = verifyBundleWithPublicKey(bundle, keyPolicyPublicKeyMaterial(key, loaded.dir));
    } catch (error) {
      diagnostic.status = "read_error";
      diagnostic.errors.push(error.message);
      errors.push(`key policy public key ${key.key_id} could not be read: ${error.message}`);
      continue;
    }

    if (verifiedBundleWithKey) {
      diagnostic.status = "verified";
      verified = true;
      continue;
    }

    diagnostic.status = "signature_mismatch";
  }

  if (!verified) {
    errors.push("bundle.attestation.signature verification failed");
  }

  return { errors, diagnostics };
}

function loadKeyPolicy(source) {
  const path = resolve(source);
  let content;
  let policy;

  try {
    content = readFileSync(path, "utf8");
  } catch (error) {
    return { errors: [`key policy ${path} could not be read: ${error.message}`] };
  }

  try {
    policy = JSON.parse(content);
  } catch (error) {
    return { errors: [`key policy ${path} contains invalid JSON: ${error.message}`] };
  }

  const errors = [];
  collectValidationError(errors, () => validateKeyPolicy(policy));

  return {
    dir: dirname(path),
    errors: errors.map((error) => `key policy ${error}`),
    path,
    policy,
  };
}

function validateKeyPolicy(policy) {
  requireObject(policy, "key_policy");
  requireEnum(policy.schema_version, [KEY_POLICY_SCHEMA_VERSION], "key_policy.schema_version");
  requireArray(policy.producers, "key_policy.producers");

  if (policy.producers.length === 0) {
    fail("key_policy.producers must include at least one producer");
  }

  for (const [producerIndex, producer] of policy.producers.entries()) {
    validateKeyPolicyProducer(producer, producerIndex);
  }
}

function validateKeyPolicyProducer(producer, producerIndex) {
  const field = `key_policy.producers[${producerIndex}]`;
  requireObject(producer, field);
  requireString(producer.name, `${field}.name`);
  requireOptionalString(producer.version, `${field}.version`);
  requireOptionalString(producer.source, `${field}.source`);
  requireOptionalString(producer.revision_pattern, `${field}.revision_pattern`);
  requireArray(producer.keys, `${field}.keys`);

  if (producer.keys.length === 0) {
    fail(`${field}.keys must include at least one key`);
  }

  if (producer.revision_pattern) {
    try {
      new RegExp(producer.revision_pattern);
    } catch (error) {
      fail(`${field}.revision_pattern is invalid: ${error.message}`);
    }
  }

  for (const [keyIndex, key] of producer.keys.entries()) {
    validateKeyPolicyKey(key, `${field}.keys[${keyIndex}]`);
  }
}

function validateKeyPolicyKey(key, field) {
  requireObject(key, field);
  requireString(key.key_id, `${field}.key_id`);
  requireEnum(key.type, ["rsa-sha256"], `${field}.type`);
  requireOptionalString(key.public_key, `${field}.public_key`);
  requireOptionalString(key.public_key_path, `${field}.public_key_path`);
  requireOptionalDateTime(key.valid_from, `${field}.valid_from`);
  requireOptionalDateTime(key.valid_until, `${field}.valid_until`);
  requireOptionalDateTime(key.revoked_at, `${field}.revoked_at`);
  requireOptionalString(key.revoked_reason, `${field}.revoked_reason`);

  if (Boolean(key.public_key) === Boolean(key.public_key_path)) {
    fail(`${field} must set exactly one of public_key or public_key_path`);
  }

  if (key.valid_from && key.valid_until && parseDateTime(key.valid_from) > parseDateTime(key.valid_until)) {
    fail(`${field}.valid_from must be before valid_until`);
  }

  if (key.revoked_at && !key.revoked_reason) {
    fail(`${field}.revoked_reason is required when revoked_at is set`);
  }
}

function matchingKeyPolicyProducers(policy, bundle, diagnostics) {
  const matches = [];

  for (const [producerIndex, producer] of policy.producers.entries()) {
    if (!keyPolicyProducerMatchesBundle(producer, bundle)) {
      continue;
    }

    matches.push({ producer, producerIndex });
    diagnostics.matching_producers.push({
      producer_index: producerIndex,
      name: producer.name,
      version: producer.version ?? null,
      source: producer.source ?? null,
      revision_pattern: producer.revision_pattern ?? null,
      keys: producer.keys.length,
    });
  }

  return matches;
}

function matchingKeyPolicyKeys(producers, bundle, diagnostics) {
  const matches = [];

  for (const { producer, producerIndex } of producers) {
    for (const [keyIndex, key] of producer.keys.entries()) {
      const diagnostic = keyPolicyKeyDiagnostic(key, producerIndex, keyIndex);
      diagnostics.considered_keys.push(diagnostic);

      if (key.key_id !== bundle.attestation.key_id || key.type !== bundle.attestation.type) {
        diagnostic.status = "not_selected";
        diagnostic.errors.push(`key ${key.key_id} ${key.type} does not match bundle attestation ${bundle.attestation.key_id} ${bundle.attestation.type}`);
        continue;
      }

      matches.push({ key, diagnostic });
    }
  }

  return matches;
}

function keyPolicyProducerMatchesBundle(producer, bundle) {
  if (producer.name !== bundle.producer?.name) {
    return false;
  }

  if (producer.version && producer.version !== bundle.producer?.version) {
    return false;
  }

  if (producer.source && producer.source !== bundle.provenance?.source) {
    return false;
  }

  if (producer.revision_pattern) {
    const revision = bundle.provenance?.revision;
    if (typeof revision !== "string" || !new RegExp(producer.revision_pattern).test(revision)) {
      return false;
    }
  }

  return true;
}

function keyPolicyPublicKeyMaterial(key, policyDir) {
  if (key.public_key) {
    return key.public_key;
  }

  return readFileSync(resolve(policyDir, key.public_key_path), "utf8");
}

function keyPolicyKeyDiagnostic(key, producerIndex, keyIndex) {
  return {
    producer_index: producerIndex,
    key_index: keyIndex,
    key_id: key.key_id,
    type: key.type,
    public_key_source: key.public_key ? "inline" : key.public_key_path,
    valid_from: key.valid_from ?? null,
    valid_until: key.valid_until ?? null,
    revoked_at: key.revoked_at ?? null,
    status: "matched",
    errors: [],
  };
}

function keyPolicyRevocationErrors(key, diagnostic) {
  const errors = [];

  if (key.revoked_at) {
    const error = `key policy key ${key.key_id} is revoked at ${key.revoked_at}: ${key.revoked_reason}`;
    diagnostic.status = "revoked";
    diagnostic.errors.push(error);
    errors.push(error);
  }

  return errors;
}

function keyPolicyKeyUseErrors(key, bundle, diagnostic) {
  const errors = [];
  const exportedAt = parseDateTime(bundle.exported_at);

  if (!Number.isFinite(exportedAt)) {
    diagnostic.status = "outside_validity";
    diagnostic.errors.push("bundle.exported_at must be a valid date-time for key policy");
    return diagnostic.errors;
  }

  if (key.valid_from && exportedAt < parseDateTime(key.valid_from)) {
    errors.push(`key policy key ${key.key_id} is not valid before ${key.valid_from}`);
  }

  if (key.valid_until && exportedAt > parseDateTime(key.valid_until)) {
    errors.push(`key policy key ${key.key_id} is not valid after ${key.valid_until}`);
  }

  if (errors.length > 0) {
    diagnostic.status = "outside_validity";
    diagnostic.errors.push(...errors);
  }

  return errors;
}

function bundlePolicyDescription(bundle) {
  return [
    `producer=${bundle.producer?.name ?? "missing"}`,
    `version=${bundle.producer?.version ?? "missing"}`,
    `source=${bundle.provenance?.source ?? "missing"}`,
    `revision=${bundle.provenance?.revision ?? "missing"}`,
  ].join(" ");
}

function attestationPolicyErrors(bundle) {
  const errors = [];
  const verifyKey = args["verify-attestation-key"] ?? process.env.JURY_BUNDLE_VERIFY_KEY;
  const verifyPublicKey = args["verify-attestation-public-key"] ?? process.env.JURY_BUNDLE_VERIFY_PUBLIC_KEY;

  if (verifyKey && verifyPublicKey) {
    errors.push("use either --verify-attestation-key or --verify-attestation-public-key, not both");
  }

  if ((args["require-attestation"] === "true" || verifyKey || verifyPublicKey) && !bundle.attestation) {
    errors.push("bundle.attestation is required");
    return errors;
  }

  if (!bundle.attestation) {
    return errors;
  }

  if (args["expect-attestation-key-id"] && bundle.attestation.key_id !== args["expect-attestation-key-id"]) {
    errors.push(`bundle.attestation.key_id expected ${args["expect-attestation-key-id"]}, got ${bundle.attestation.key_id ?? "missing"}`);
  }

  if (!verifyKey) {
    if (!verifyPublicKey) {
      return errors;
    }
  } else if (bundle.attestation.type !== "hmac-sha256") {
    errors.push(`bundle.attestation.type expected hmac-sha256 for HMAC verification, got ${bundle.attestation.type ?? "missing"}`);
  } else {
    const expected = bundleSignature(bundle, verifyKey);
    if (!constantTimeEqual(bundle.attestation.signature, expected)) {
      errors.push("bundle.attestation.signature verification failed");
    }
  }

  if (verifyPublicKey) {
    if (bundle.attestation.type !== "rsa-sha256") {
      errors.push(`bundle.attestation.type expected rsa-sha256 for public key verification, got ${bundle.attestation.type ?? "missing"}`);
    } else if (!verifyBundleWithPublicKey(bundle, verifyPublicKey)) {
      errors.push("bundle.attestation.signature verification failed");
    }
  }

  return errors;
}

function signBundle(bundle, key, keyId) {
  return {
    type: "hmac-sha256",
    key_id: keyId,
    signed_at: now(),
    signature: bundleSignature(bundle, key),
  };
}

function signBundleWithPrivateKey(bundle, keySource, keyId) {
  const privateKey = loadRsaPrivateKey(keySource);
  const signer = createSign("sha256");
  signer.update(canonicalJson(unsignedBundle(bundle)));
  signer.end();
  return {
    type: "rsa-sha256",
    key_id: keyId,
    signed_at: now(),
    signature: signer.sign(privateKey, "base64"),
  };
}

function bundleSignature(bundle, key) {
  return createHmac("sha256", key).update(canonicalJson(unsignedBundle(bundle))).digest("hex");
}

function verifyBundleWithPublicKey(bundle, keySource) {
  try {
    const publicKey = loadRsaPublicKey(keySource);
    const verifier = createVerify("sha256");
    verifier.update(canonicalJson(unsignedBundle(bundle)));
    verifier.end();
    return verifier.verify(publicKey, bundle.attestation.signature, "base64");
  } catch {
    return false;
  }
}

function loadRsaPrivateKey(source) {
  const privateKey = createPrivateKey(loadKeyMaterial(source));

  if (privateKey.asymmetricKeyType !== "rsa") {
    fail(`attestation private key must be RSA, got ${privateKey.asymmetricKeyType ?? "unknown"}`);
  }

  return privateKey;
}

function loadRsaPublicKey(source) {
  const publicKey = createPublicKey(loadKeyMaterial(source));

  if (publicKey.asymmetricKeyType !== "rsa") {
    throw new Error(`attestation public key must be RSA, got ${publicKey.asymmetricKeyType ?? "unknown"}`);
  }

  return publicKey;
}

function loadKeyMaterial(source) {
  if (source.includes("-----BEGIN ")) {
    return source;
  }

  return readFileSync(resolve(source), "utf8");
}

function unsignedBundle(bundle) {
  const { attestation, ...unsigned } = bundle;
  return unsigned;
}

function canonicalJson(value) {
  return JSON.stringify(canonicalValue(value));
}

function canonicalValue(value) {
  if (Array.isArray(value)) {
    return value.map(canonicalValue);
  }

  if (value && typeof value === "object") {
    return Object.fromEntries(Object.keys(value).sort().map((key) => [key, canonicalValue(value[key])]));
  }

  return value;
}

function constantTimeEqual(left, right) {
  if (typeof left !== "string" || typeof right !== "string") {
    return false;
  }

  const leftBuffer = Buffer.from(left);
  const rightBuffer = Buffer.from(right);

  if (leftBuffer.length !== rightBuffer.length) {
    return false;
  }

  return timingSafeEqual(leftBuffer, rightBuffer);
}

function bundleProducer() {
  return {
    name: args["producer-name"] ?? PRODUCER_NAME,
    version: args["producer-version"] ?? PRODUCER_VERSION,
    command: "bundle export",
  };
}

function bundleProvenance() {
  return {
    source: args.source ?? process.env.GITHUB_REPOSITORY ?? "local",
    revision: args.revision ?? process.env.GITHUB_SHA ?? "unknown",
    workflow: args.workflow ?? process.env.GITHUB_WORKFLOW ?? null,
    run_id: args["run-id"] ?? process.env.GITHUB_RUN_ID ?? null,
  };
}

function validateBundleProducer(producer) {
  requireObject(producer, "bundle.producer");
  requireString(producer.name, "bundle.producer.name");
  requireString(producer.version, "bundle.producer.version");
  requireString(producer.command, "bundle.producer.command");
}

function validateBundleProvenance(provenance) {
  requireObject(provenance, "bundle.provenance");
  requireString(provenance.source, "bundle.provenance.source");
  requireString(provenance.revision, "bundle.provenance.revision");
  requireNullableString(provenance.workflow, "bundle.provenance.workflow");
  requireNullableString(provenance.run_id, "bundle.provenance.run_id");
}

function validateBundleAttestation(attestation) {
  requireObject(attestation, "bundle.attestation");
  requireEnum(attestation.type, ["hmac-sha256", "rsa-sha256"], "bundle.attestation.type");
  requireString(attestation.key_id, "bundle.attestation.key_id");
  requireString(attestation.signed_at, "bundle.attestation.signed_at");
  requireString(attestation.signature, "bundle.attestation.signature");
}

function collectValidationError(errors, action) {
  const previous = collectValidationErrors;
  collectValidationErrors = true;

  try {
    action();
  } catch (error) {
    errors.push(error.message);
  } finally {
    collectValidationErrors = previous;
  }
}

function assertKnownClaim(errors, recordType, recordId, claimId, claims) {
  if (!claims.has(claimId)) {
    errors.push(`${recordType} ${recordId} references missing claim ${claimId}`);
  }
}

function missingReferences(field, ids, records) {
  return ids
    .filter((id) => !records.has(id))
    .map((id) => `${field} references missing record ${id}`);
}

function crossClaimReferences(field, claimId, ids, records) {
  return ids
    .map((id) => records.get(id))
    .filter((record) => record && record.claim_id !== claimId)
    .map((record) => `${field} references ${record.id} from claim ${record.claim_id}`);
}

function latestVerdictFromBundle(bundle) {
  return [...bundle.records.verdicts].sort((left, right) => (
    String(left.decided_at).localeCompare(String(right.decided_at)) || left.id.localeCompare(right.id)
  )).at(-1) ?? null;
}

async function withValidationErrors(action) {
  const previous = collectValidationErrors;
  collectValidationErrors = true;

  try {
    return await action();
  } finally {
    collectValidationErrors = previous;
  }
}

async function demoCodeChange() {
  const dir = stateDir();
  await rm(dir, { force: true, recursive: true });
  await ensureState(dir);
  const transcript = [];
  const claim = await createRecord(fileFor(dir, "claims"), {
    schema_version: "jury.claim.v1",
    id: "claim_checkout_ready",
    version: 1,
    summary: "checkout fix is ready",
    claimant: "agent:demo",
    scope: ["src/checkout"],
    impact: "high",
    status: "submitted",
    created_at: now(),
    updated_at: now(),
  }, validateClaim);
  transcript.push({ step: "claim_created", claim_id: claim.id, status: claim.status });

  const pendingCheck = await createRecord(fileFor(dir, "checks"), {
    schema_version: "jury.check.v1",
    id: "check_tests_required",
    claim_id: claim.id,
    type: "verifier",
    required: true,
    status: "pending",
    assigned_to: "verifier:demo",
    summary: "test command must pass",
    evidence_ids: [],
    resolution: null,
    created_at: now(),
    updated_at: now(),
  }, validateCheck);
  transcript.push({ step: "check_created", check_id: pendingCheck.id, status: pendingCheck.status });

  await createRecord(fileFor(dir, "evidence"), {
    schema_version: "jury.evidence.v1",
    id: "ev_npm_test",
    claim_id: claim.id,
    type: "command",
    summary: "npm test passed",
    source: "npm test",
    status: "passed",
    command: "npm test",
    exit_code: 0,
    stdout: "",
    stderr: "",
    collected_at: now(),
  }, validateEvidence);
  transcript.push({ step: "evidence_collected", evidence_id: "ev_npm_test", status: "passed" });

  const objection = await createRecord(fileFor(dir, "objections"), {
    schema_version: "jury.objection.v1",
    id: "obj_missing_regression_test",
    claim_id: claim.id,
    summary: "missing regression test",
    raised_by: "critic:tests",
    severity: "high",
    status: "open",
    evidence_ids: ["ev_npm_test"],
    resolution: null,
    created_at: now(),
    updated_at: now(),
  }, validateObjection);
  transcript.push({ step: "objection_opened", objection_id: objection.id, severity: objection.severity });

  const retryReview = await reviewForClaim(dir, claim.id);
  const retryDecision = decide(retryReview, false);
  const retryVerdict = await createRecord(fileFor(dir, "verdicts"), {
    schema_version: VERDICT_SCHEMA_VERSION,
    id: "verdict_checkout_ready_retry",
    claim_id: claim.id,
    claim_version: claim.version,
    decision: retryDecision.decision,
    reason: retryDecision.reason,
    next_actions: retryDecision.next_actions,
    evidence_ids: retryReview.evidence.map((item) => item.id).sort(),
    objection_ids: retryReview.objections.map((item) => item.id).sort(),
    waiver_ids: [],
    check_ids: retryReview.checks.map((item) => item.id).sort(),
    decided_by: "judge:demo",
    decided_at: now(),
  }, validateVerdict);
  transcript.push({ step: "first_verdict", verdict_id: retryVerdict.id, decision: retryVerdict.decision, next_actions: retryVerdict.next_actions });

  await createRecord(fileFor(dir, "objections"), {
    ...objection,
    status: "resolved",
    resolution: "added regression test",
    updated_at: now(),
  }, validateObjection);
  transcript.push({ step: "objection_resolved", objection_id: objection.id });

  await createRecord(fileFor(dir, "checks"), {
    ...pendingCheck,
    status: "passed",
    evidence_ids: ["ev_npm_test"],
    resolution: "npm test passed",
    updated_at: now(),
  }, validateCheck);
  transcript.push({ step: "check_passed", check_id: pendingCheck.id });

  const review = await reviewForClaim(dir, claim.id);
  const decision = decide(review, false);
  const verdict = await createRecord(fileFor(dir, "verdicts"), {
    schema_version: VERDICT_SCHEMA_VERSION,
    id: "verdict_checkout_ready_accept",
    claim_id: claim.id,
    claim_version: claim.version,
    decision: decision.decision,
    reason: decision.reason,
    next_actions: decision.next_actions,
    evidence_ids: review.evidence.map((item) => item.id).sort(),
    objection_ids: review.objections.map((item) => item.id).sort(),
    waiver_ids: [],
    check_ids: review.checks.map((item) => item.id).sort(),
    decided_by: "judge:demo",
    decided_at: now(),
  }, validateVerdict);
  transcript.push({ step: "final_verdict", verdict_id: verdict.id, decision: verdict.decision });

  await writeFile("verdict.json", `${JSON.stringify(verdict, null, 2)}\n`);
  await writeFile("jury-demo-transcript.json", `${JSON.stringify(transcript, null, 2)}\n`);
  print({ ok: true, claim, retryVerdict, verdict, transcript, stateDir: dir, verdictFile: "verdict.json", transcriptFile: "jury-demo-transcript.json" });
}

async function reviewForClaim(dir, claimId) {
  const claim = await requireClaim(dir, claimId);
  const evidence = latestById(await readJsonl(fileFor(dir, "evidence")));
  const checks = latestById(await readJsonl(fileFor(dir, "checks")));
  const objections = latestById(await readJsonl(fileFor(dir, "objections")));
  const waivers = latestById(await readJsonl(fileFor(dir, "waivers")));

  return {
    claim,
    checks: Array.from(checks.values()).filter((item) => item.claim_id === claimId).sort(byId),
    evidence: Array.from(evidence.values()).filter((item) => item.claim_id === claimId).sort(byId),
    objections: Array.from(objections.values()).filter((item) => item.claim_id === claimId).sort(byId),
    waivers: Array.from(waivers.values()).filter((item) => item.claim_id === claimId).sort(byId),
  };
}

function decide(review, requireHumanApproval) {
  const openBlocking = review.objections.filter((item) => item.status === "open" && BLOCKING_SEVERITIES.has(item.severity));
  const failedEvidence = review.evidence.filter((item) => item.status === "failed");
  const requiredChecks = review.checks.filter((item) => item.required);
  const failedChecks = requiredChecks.filter((item) => item.status === "failed");
  const pendingChecks = requiredChecks.filter((item) => item.status === "pending");
  const humanChecks = pendingChecks.filter((item) => item.type === "human_approval");

  if (requireHumanApproval || humanChecks.length > 0) {
    return {
      decision: "human_decision",
      reason: "Human approval is required before this claim can be accepted.",
      next_actions: humanChecks.length > 0
        ? humanChecks.map((item) => `Complete ${item.id}: ${item.summary}`)
        : ["Record an explicit approval or waiver."],
    };
  }

  if (failedEvidence.length > 0 || failedChecks.length > 0 || openBlocking.some((item) => item.severity === "critical")) {
    return {
      decision: "reject",
      reason: failedEvidence.length > 0
        ? "Required evidence failed."
        : failedChecks.length > 0
          ? "A required check failed."
        : "A critical objection is still open.",
      next_actions: [],
    };
  }

  if (review.evidence.length === 0 || pendingChecks.length > 0 || openBlocking.length > 0) {
    return {
      decision: "retry",
      reason: review.evidence.length === 0
        ? "The claim has no evidence yet."
        : pendingChecks.length > 0
          ? "Required checks must complete before acceptance."
        : "Blocking objections must be resolved before acceptance.",
      next_actions: [
        ...pendingChecks.map((item) => `Complete ${item.id}: ${item.summary}`),
        ...openBlocking.map((item) => `Resolve ${item.id}: ${item.summary}`),
      ],
    };
  }

  return {
    decision: "accept",
    reason: "Required evidence passed and no blocking objections remain open.",
    next_actions: [],
  };
}

function validateRecord(name, record) {
  if (name === "claims") validateClaim(record);
  if (name === "checks") validateCheck(record);
  if (name === "evidence") validateEvidence(record);
  if (name === "objections") validateObjection(record);
  if (name === "waivers") validateWaiver(record);
  if (name === "verdicts") validateVerdict(record);
}

function validateClaim(record) {
  requireString(record.schema_version, "claim.schema_version");
  requireString(record.id, "claim.id");
  requireNumber(record.version, "claim.version");
  requireString(record.summary, "claim.summary");
  requireString(record.claimant, "claim.claimant");
  requireArray(record.scope, "claim.scope");
  requireEnum(record.impact, ["low", "medium", "high", "critical"], "claim.impact");
  requireEnum(record.status, CLAIM_STATUSES, "claim.status");
}

function validateCheck(record) {
  requireString(record.schema_version, "check.schema_version");
  requireString(record.id, "check.id");
  requireString(record.claim_id, "check.claim_id");
  requireEnum(record.type, ["critic", "verifier", "policy", "human_approval"], "check.type");

  if (typeof record.required !== "boolean") {
    fail("check.required must be a boolean");
  }

  requireEnum(record.status, CHECK_STATUSES, "check.status");
  requireString(record.assigned_to, "check.assigned_to");
  requireString(record.summary, "check.summary");
  requireArray(record.evidence_ids, "check.evidence_ids");

  if (["passed", "failed", "waived", "not_applicable"].includes(record.status) && !record.resolution) {
    fail("check.resolution is required when check is no longer pending");
  }
}

function validateEvidence(record) {
  requireString(record.schema_version, "evidence.schema_version");
  requireString(record.id, "evidence.id");
  requireString(record.claim_id, "evidence.claim_id");
  requireEnum(record.type, ["command", "diff", "artifact", "citation", "screenshot", "log", "review", "manual", "approval", "tool_call_preview", "policy_check"], "evidence.type");
  requireString(record.summary, "evidence.summary");
  requireString(record.source, "evidence.source");
  requireEnum(record.status, ["pending", "passed", "failed", "inconclusive"], "evidence.status");

  if (record.type === "command") {
    requireString(record.command, "evidence.command");
    requireNumber(record.exit_code, "evidence.exit_code");
  }
}

function validateObjection(record) {
  requireString(record.schema_version, "objection.schema_version");
  requireString(record.id, "objection.id");
  requireString(record.claim_id, "objection.claim_id");
  requireString(record.summary, "objection.summary");
  requireString(record.raised_by, "objection.raised_by");
  requireEnum(record.severity, ["low", "medium", "high", "critical"], "objection.severity");
  requireEnum(record.status, ["open", "resolved", "waived", "rejected"], "objection.status");
  requireArray(record.evidence_ids, "objection.evidence_ids");

  if (record.status !== "open" && !record.resolution) {
    fail("objection.resolution is required unless status is open");
  }
}

function validateWaiver(record) {
  requireString(record.schema_version, "waiver.schema_version");
  requireString(record.id, "waiver.id");
  requireString(record.objection_id, "waiver.objection_id");
  requireString(record.claim_id, "waiver.claim_id");
  requireString(record.approved_by, "waiver.approved_by");
  requireString(record.reason, "waiver.reason");
}

function validateVerdict(record) {
  requireEnum(record.schema_version, [VERDICT_SCHEMA_VERSION], "verdict.schema_version");
  requireString(record.id, "verdict.id");
  requireString(record.claim_id, "verdict.claim_id");
  requireNumber(record.claim_version, "verdict.claim_version");
  requireEnum(record.decision, Array.from(VALID_DECISIONS), "verdict.decision");
  requireString(record.reason, "verdict.reason");
  requireArray(record.evidence_ids, "verdict.evidence_ids");
  requireArray(record.objection_ids, "verdict.objection_ids");
  requireArray(record.waiver_ids, "verdict.waiver_ids");
  if (record.check_ids !== undefined) {
    requireArray(record.check_ids, "verdict.check_ids");
  }
  requireString(record.decided_by, "verdict.decided_by");
  requireString(record.decided_at, "verdict.decided_at");
}

async function requireClaim(dir, claimId) {
  const claims = latestById(await readJsonl(fileFor(dir, "claims")));
  const claim = claims.get(claimId);

  if (!claim) {
    fail(`unknown claim: ${claimId}`);
  }

  return claim;
}

async function createRecord(path, record, validate) {
  const sorted = sortRecord(record);
  validate(sorted);
  await appendJsonl(path, sorted);
  return sorted;
}

async function ensureState(dir) {
  await mkdir(dir, { recursive: true });

  for (const path of stateFiles(dir)) {
    await ensureFile(path);
  }
}

async function ensureFile(path) {
  try {
    await readFile(path, "utf8");
  } catch (error) {
    if (error.code !== "ENOENT") throw error;
    await writeFile(path, "");
  }
}

async function readJsonl(path) {
  await ensureFile(path);
  const content = await readFile(path, "utf8");
  return content
    .split("\n")
    .filter((line) => line.trim().length > 0)
    .map((line, index) => parseJson(line, `${path}:${index + 1}`));
}

async function appendJsonl(path, record) {
  await appendFile(path, `${JSON.stringify(record)}\n`);
}

function latestById(records) {
  const map = new Map();

  for (const record of records) {
    map.set(record.id, record);
  }

  return map;
}

function fileFor(dir, name) {
  return join(dir, `${name}.jsonl`);
}

function stateDir() {
  return args["state-dir"] ?? DEFAULT_STATE_DIR;
}

function stateFiles(dir) {
  return STATE_RECORD_TYPES.map((name) => fileFor(dir, name));
}

function schemaDir() {
  return args["schema-dir"] ?? SCHEMA_DIR;
}

function uniqueId(prefix, value, existing) {
  const base = slug(value);
  let candidate = `${prefix}_${base}`;
  const ids = new Set(existing.map((record) => record.id));
  let count = 2;

  while (ids.has(candidate)) {
    candidate = `${prefix}_${base}_${count}`;
    count += 1;
  }

  return candidate;
}

function slug(value) {
  const normalized = String(value)
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "_")
    .replace(/^_+|_+$/g, "")
    .slice(0, 48);

  return normalized || "record";
}

function parseList(value) {
  if (!value) return [];
  return value.split(",").map((item) => item.trim()).filter(Boolean).sort();
}

function parseBoolean(value, field) {
  if (value === "true") return true;
  if (value === "false") return false;
  fail(`${field} must be true or false`);
}

function statusFromExitCode(value) {
  if (value === undefined || value === null) return args.status ?? "passed";
  return Number(value) === 0 ? "passed" : "failed";
}

function numberOrNull(value) {
  if (value === undefined || value === null || value === "") return null;
  const parsed = Number(value);
  if (!Number.isFinite(parsed)) fail(`expected number, got ${value}`);
  return parsed;
}

function now() {
  return process.env.JURY_NOW ?? new Date().toISOString();
}

function parseJson(content, label) {
  try {
    return JSON.parse(content);
  } catch (error) {
    fail(`${label} contains invalid JSON: ${error.message}`);
  }
}

function sortRecord(record) {
  return Object.fromEntries(Object.entries(record).filter(([, value]) => value !== undefined));
}

function byId(left, right) {
  return left.id.localeCompare(right.id);
}

function byVersionThenUpdatedAt(left, right) {
  return left.version - right.version || String(left.updated_at).localeCompare(String(right.updated_at));
}

function requireArg(name) {
  const value = args[name];
  if (!value) fail(`missing required --${name}`);
  return value;
}

function requireString(value, field) {
  if (typeof value !== "string" || value.length === 0) {
    fail(`${field} must be a non-empty string`);
  }
}

function requireObject(value, field) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    fail(`${field} must be an object`);
  }
}

function requireNullableString(value, field) {
  if (value !== null && typeof value !== "string") {
    fail(`${field} must be a string or null`);
  }
}

function requireOptionalString(value, field) {
  if (value !== undefined && (typeof value !== "string" || value.length === 0)) {
    fail(`${field} must be a non-empty string when set`);
  }
}

function requireOptionalDateTime(value, field) {
  requireOptionalString(value, field);

  if (value !== undefined && !Number.isFinite(parseDateTime(value))) {
    fail(`${field} must be a valid date-time`);
  }
}

function parseDateTime(value) {
  const rfc3339DateTime = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$/;

  if (typeof value !== "string" || !rfc3339DateTime.test(value)) {
    return Number.NaN;
  }

  return Date.parse(value);
}

function requireNumber(value, field) {
  if (typeof value !== "number" || !Number.isFinite(value)) {
    fail(`${field} must be a number`);
  }
}

function requireArray(value, field) {
  if (!Array.isArray(value)) {
    fail(`${field} must be an array`);
  }
}

function requireEnum(value, allowed, field) {
  if (!allowed.includes(value)) {
    fail(`${field} must be one of ${allowed.join(", ")}`);
  }
}

function print(value) {
  if (args.json || typeof value !== "string") {
    process.stdout.write(`${JSON.stringify(value, null, 2)}\n`);
  } else {
    process.stdout.write(`${value}\n`);
  }
}

function printHelp() {
  print(`Jury CLI

Commands:
  jury init
  jury claim create --summary <text> [--impact high] [--scope path,path]
  jury claim transition --claim <id> --status screening
  jury check add --claim <id> --type verifier --summary <text>
  jury check update --id <id> --status passed --resolution <text>
  jury evidence add --claim <id> --type command --command "npm test" --exit-code 0
  jury critic run --claim <id> --role tests
  jury objection add --claim <id> --summary <text> [--severity high]
  jury objection resolve --id <id> --resolution <text>
  jury waiver add --objection <id> --reason <text>
  jury status --claim <id>
  jury judge --claim <id> [--out verdict.json] [--require-human-approval true]
  jury gate --verdict verdict.json [--claim <id>]
  jury bundle export --claim <id> --out review-bundle.json [--attest-key secret] [--attest-private-key private.pem]
  jury bundle preflight --bundle review-bundle.json [--key-policy jury-key-policy.json] [--require-attestation true] [--verify-attestation-key secret] [--verify-attestation-public-key public.pem] [--expect-producer-name name]
  jury bundle import --bundle review-bundle.json [--verdict-out verdict.json] [--key-policy jury-key-policy.json] [--require-attestation true] [--verify-attestation-key secret] [--verify-attestation-public-key public.pem]
  jury check --strict
  jury demo code-change`);
}

function fail(message) {
  if (collectValidationErrors) {
    throw new Error(message);
  }

  process.stderr.write(`${message}\n`);
  process.exit(1);
}

function runShell(commandLine) {
  return new Promise((resolveRun) => {
    const child = spawn(commandLine, { shell: true, stdio: ["ignore", "pipe", "pipe"] });
    let stdout = "";
    let stderr = "";

    child.stdout.on("data", (chunk) => {
      stdout += chunk.toString();
    });
    child.stderr.on("data", (chunk) => {
      stderr += chunk.toString();
    });
    child.on("close", (exitCode) => {
      resolveRun({ exit_code: exitCode ?? 1, stdout, stderr });
    });
  });
}
