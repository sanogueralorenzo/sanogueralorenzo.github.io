#!/usr/bin/env node

import { mkdir, readFile, writeFile, appendFile, rm } from "node:fs/promises";
import { spawn } from "node:child_process";
import { join, resolve } from "node:path";

const DEFAULT_STATE_DIR = ".jury";
const VERDICT_SCHEMA_VERSION = "jury.verdict.v1";
const VALID_DECISIONS = new Set(["accept", "reject", "retry", "human_decision"]);
const BLOCKING_SEVERITIES = new Set(["medium", "high", "critical"]);
const command = process.argv[2] ?? "help";
const subcommand = process.argv[3]?.startsWith("--") ? null : process.argv[3] ?? null;
const rawArgs = process.argv.slice(subcommand ? 4 : 3);
const args = parseArgs(rawArgs);

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

  if (command === "evidence" && subcommand === "add") {
    await addEvidence();
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

  if (verdict.decision !== "accept") {
    print({ ok: false, decision: verdict.decision, reason: verdict.reason });
    process.exitCode = 1;
    return;
  }

  print({ ok: true, decision: verdict.decision, reason: verdict.reason });
}

async function checkState() {
  const dir = stateDir();
  await ensureState(dir);
  const checks = [];

  for (const name of ["claims", "evidence", "objections", "waivers", "verdicts"]) {
    try {
      const records = await readJsonl(fileFor(dir, name));
      for (const record of records) {
        validateRecord(name, record);
      }
      checks.push({ name, ok: true });
    } catch (error) {
      checks.push({ name, ok: false, message: error.message });
    }
  }

  const ok = checks.every((check) => check.ok);
  print({ ok, checks });

  if (!ok) {
    process.exitCode = 1;
  }
}

async function demoCodeChange() {
  const dir = stateDir();
  await rm(dir, { force: true, recursive: true });
  await ensureState(dir);
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
  await createRecord(fileFor(dir, "objections"), {
    ...objection,
    status: "resolved",
    resolution: "added regression test",
    updated_at: now(),
  }, validateObjection);
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
    decided_by: "judge:demo",
    decided_at: now(),
  }, validateVerdict);
  await writeFile("verdict.json", `${JSON.stringify(verdict, null, 2)}\n`);
  print({ ok: true, claim, verdict, stateDir: dir, verdictFile: "verdict.json" });
}

async function reviewForClaim(dir, claimId) {
  const claim = await requireClaim(dir, claimId);
  const evidence = latestById(await readJsonl(fileFor(dir, "evidence")));
  const objections = latestById(await readJsonl(fileFor(dir, "objections")));
  const waivers = latestById(await readJsonl(fileFor(dir, "waivers")));

  return {
    claim,
    evidence: Array.from(evidence.values()).filter((item) => item.claim_id === claimId).sort(byId),
    objections: Array.from(objections.values()).filter((item) => item.claim_id === claimId).sort(byId),
    waivers: Array.from(waivers.values()).filter((item) => item.claim_id === claimId).sort(byId),
  };
}

function decide(review, requireHumanApproval) {
  const openBlocking = review.objections.filter((item) => item.status === "open" && BLOCKING_SEVERITIES.has(item.severity));
  const failedEvidence = review.evidence.filter((item) => item.status === "failed");

  if (requireHumanApproval) {
    return {
      decision: "human_decision",
      reason: "Human approval is required before this claim can be accepted.",
      next_actions: ["Record an explicit approval or waiver."],
    };
  }

  if (failedEvidence.length > 0 || openBlocking.some((item) => item.severity === "critical")) {
    return {
      decision: "reject",
      reason: failedEvidence.length > 0
        ? "Required evidence failed."
        : "A critical objection is still open.",
      next_actions: [],
    };
  }

  if (review.evidence.length === 0 || openBlocking.length > 0) {
    return {
      decision: "retry",
      reason: review.evidence.length === 0
        ? "The claim has no evidence yet."
        : "Blocking objections must be resolved before acceptance.",
      next_actions: openBlocking.map((item) => `Resolve ${item.id}: ${item.summary}`),
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
  requireEnum(record.status, ["draft", "submitted", "screening", "in_review", "revision_required", "ready_for_judgment", "decided", "archived"], "claim.status");
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
  return ["claims", "evidence", "objections", "waivers", "verdicts"].map((name) => fileFor(dir, name));
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
  jury evidence add --claim <id> --type command --command "npm test" --exit-code 0
  jury objection add --claim <id> --summary <text> [--severity high]
  jury objection resolve --id <id> --resolution <text>
  jury waiver add --objection <id> --reason <text>
  jury status --claim <id>
  jury judge --claim <id> [--out verdict.json] [--require-human-approval true]
  jury gate --verdict verdict.json
  jury check --strict
  jury demo code-change`);
}

function fail(message) {
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
