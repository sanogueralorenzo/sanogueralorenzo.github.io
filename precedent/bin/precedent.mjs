#!/usr/bin/env node

import { mkdir, readFile, writeFile, appendFile, access } from "node:fs/promises";
import { dirname, join, resolve } from "node:path";

const DEFAULT_STATE_DIR = ".precedent";
const SUPPORTED_EVENT_HOOKS = new Set(["context.before_turn"]);

const command = process.argv[2] ?? "help";
const hookName = command === "hook" && process.argv[3] && !process.argv[3].startsWith("--") ? process.argv[3] : null;
const args = parseArgs(process.argv.slice(command === "hook" && hookName ? 4 : 3));

async function main() {
  if (command === "help" || args.help) {
    printHelp();
    return;
  }

  if (command === "init") {
    await initState();
    return;
  }

  if (command === "observe") {
    await observeTrace();
    return;
  }

  if (command === "inject") {
    await injectPrecedent();
    return;
  }

  if (command === "hook") {
    await runHook();
    return;
  }

  if (command === "report") {
    await reportState();
    return;
  }

  fail(`unknown command: ${command}`);
}

function parseArgs(rawArgs) {
  const parsed = {};

  for (let index = 0; index < rawArgs.length; index += 1) {
    const arg = rawArgs[index];

    if (!arg.startsWith("--")) {
      fail(`unexpected positional argument: ${arg}`);
    }

    const key = arg.slice(2);

    if (key.length === 0) {
      fail("empty flag is not valid");
    }

    if (key === "json" || key === "help") {
      parsed[key] = true;
      continue;
    }

    const value = rawArgs[index + 1];

    if (!value || value.startsWith("--")) {
      fail(`missing value for --${key}`);
    }

    parsed[key] = value;
    index += 1;
  }

  return parsed;
}

async function initState() {
  const stateDir = statePath();

  await ensureState(stateDir);

  print({
    ok: true,
    stateDir,
    files: [
      join(stateDir, "precedents.jsonl"),
      join(stateDir, "events.jsonl"),
      join(stateDir, "traces"),
    ],
  });
}

async function observeTrace() {
  const tracePath = args.trace;

  if (!tracePath) {
    fail("observe requires --trace <path>");
  }

  const stateDir = statePath();
  await ensureState(stateDir);

  const rawTrace = await readFile(resolve(tracePath), "utf8");
  const trace = parseJson(rawTrace, tracePath);
  const traceId = requireString(trace.id, "trace.id");
  const observedAt = new Date().toISOString();
  let promoted = null;
  let rejected = null;

  if (trace.precedent) {
    const candidate = normalizePrecedent(trace.precedent, traceId);
    const assessment = assessPromotionCandidate(candidate);

    if (assessment.ok) {
      promoted = {
        ...candidate,
        promotion_status: "promoted",
        promoted_at: observedAt,
      };
    } else {
      rejected = {
        id: candidate.id,
        reasons: assessment.reasons,
      };
    }
  }

  const event = {
    type: "trace_observed",
    observedAt,
    traceId,
    task: trace.task ?? null,
    outcome: trace.outcome ?? null,
    scope: trace.scope ?? null,
    failures: Array.isArray(trace.failures) ? trace.failures : [],
    promotionStatus: promoted ? "promoted" : trace.precedent ? "rejected" : "none",
    promotionReasons: rejected?.reasons ?? [],
  };

  await writeFile(join(stateDir, "traces", `${safeFileName(traceId)}.json`), JSON.stringify(trace, null, 2));
  await appendJsonLine(join(stateDir, "events.jsonl"), event);
  if (promoted) {
    await appendJsonLine(join(stateDir, "precedents.jsonl"), promoted);
  }

  print({
    ok: true,
    observed: event,
    promoted,
    rejected,
  });
}

async function injectPrecedent() {
  const task = args.task;

  if (!task) {
    fail("inject requires --task <text>");
  }

  const precedents = await readJsonLines(join(statePath(), "precedents.jsonl"));
  const matches = rankPrecedents(precedents, {
    task,
    scope: args.scope ?? "",
    changedFiles: parseListArg(args["changed-files"]),
  }).slice(0, Number(args.limit ?? 2));

  print({
    task,
    scope: args.scope ?? null,
    injections: matches.map((match) => ({
      id: match.id,
      score: match.score,
      injection: match.injection,
      sourceTrace: match.source_trace,
    })),
  });
}

async function runHook() {
  if (hookName === null) {
    await eventHook();
    return;
  }

  if (hookName === "before-turn") {
    await beforeTurnHook();
    return;
  }

  fail(`unknown hook: ${hookName ?? "(missing)"}`);
}

async function eventHook() {
  const event = await readHookEvent();
  const hook = requireString(event.hook, "event.hook");

  if (!SUPPORTED_EVENT_HOOKS.has(hook)) {
    fail(`unsupported hook: ${hook}; supported hooks: ${Array.from(SUPPORTED_EVENT_HOOKS).join(", ")}`);
  }

  if (hook === "context.before_turn") {
    await contextBeforeTurnEventHook(event);
    return;
  }

  fail(`unsupported hook: ${hook}`);
}

async function beforeTurnHook() {
  const task = args.task;

  if (!task) {
    fail("hook before-turn requires --task <text>");
  }

  const stateDir = statePath();
  await ensureState(stateDir);

  const context = {
    task,
    scope: args.scope ?? "",
    changedFiles: parseListArg(args["changed-files"]),
  };
  const limit = Number(args.limit ?? 2);
  const threshold = Number(args.threshold ?? 4);
  const precedents = await readJsonLines(join(stateDir, "precedents.jsonl"));
  const matches = rankPrecedents(precedents, context)
    .filter((precedent) => precedent.score >= threshold)
    .slice(0, limit);
  const block = formatInjectionBlock(matches);
  const event = {
    type: "context_before_turn",
    observedAt: new Date().toISOString(),
    task,
    scope: context.scope || null,
    changedFiles: context.changedFiles,
    threshold,
    injectedIds: matches.map((match) => match.id),
  };

  await appendJsonLine(join(stateDir, "events.jsonl"), event);

  print({
    hook: "context.before_turn",
    task,
    scope: context.scope || null,
    changedFiles: context.changedFiles,
    threshold,
    injected: matches.length > 0,
    block,
    injections: matches.map((match) => ({
      id: match.id,
      score: match.score,
      scope: match.scope,
      artifact: match.artifact,
      injection: match.injection,
      sourceTrace: match.source_trace,
    })),
  });
}

async function contextBeforeTurnEventHook(event) {
  const task = requireString(event.task, "event.task");
  const stateDir = statePath();
  await ensureState(stateDir);

  const context = {
    task,
    scope: typeof event.scope === "string" ? event.scope : "",
    changedFiles: Array.isArray(event.changedFiles) ? event.changedFiles : parseListArg(event.changedFiles),
  };
  const limit = Number(args.limit ?? event.limit ?? 2);
  const threshold = Number(args.threshold ?? event.threshold ?? 4);
  const precedents = await readJsonLines(join(stateDir, "precedents.jsonl"));
  const matches = rankPrecedents(precedents, context)
    .filter((precedent) => precedent.score >= threshold)
    .slice(0, limit);
  const contextBlock = formatInjectionBlock(matches);

  await appendJsonLine(join(stateDir, "events.jsonl"), {
    type: "hook_event",
    receivedAt: new Date().toISOString(),
    hook: event.hook,
    task,
    scope: context.scope || null,
    changedFiles: context.changedFiles,
    threshold,
    injections: matches.map((match) => match.id),
  });

  print({
    ok: true,
    hook: event.hook,
    injections: matches.map(formatInjection),
    contextBlock,
  });
}

async function reportState() {
  const stateDir = statePath();
  const precedents = await readJsonLines(join(stateDir, "precedents.jsonl"));
  const events = await readJsonLines(join(stateDir, "events.jsonl"));

  const artifactCounts = {};
  for (const precedent of precedents) {
    const artifact = precedent.artifact ?? "unknown";
    artifactCounts[artifact] = (artifactCounts[artifact] ?? 0) + 1;
  }

  print({
    stateDir,
    precedents: precedents.length,
    events: events.length,
    artifactCounts,
  });
}

function normalizePrecedent(precedent, traceId) {
  return {
    id: requireString(precedent.id, "precedent.id"),
    scope: requireString(precedent.scope, "precedent.scope"),
    trigger: requireString(precedent.trigger, "precedent.trigger"),
    lesson: requireString(precedent.lesson, "precedent.lesson"),
    artifact: requireString(precedent.artifact, "precedent.artifact"),
    paths: Array.isArray(precedent.paths) ? precedent.paths : [],
    source_trace: precedent.source_trace ?? traceId,
    evidence: Array.isArray(precedent.evidence) ? precedent.evidence : [],
    injection: requireString(precedent.injection, "precedent.injection"),
    promotion: precedent.promotion ?? {},
  };
}

function rankPrecedents(precedents, context) {
  return precedents
    .filter((precedent) => precedent.promotion_status === "promoted")
    .map((precedent) => ({
      ...precedent,
      score: scorePrecedent(precedent, context),
    }))
    .filter((precedent) => precedent.score > 0)
    .sort((left, right) => right.score - left.score || left.id.localeCompare(right.id));
}

function scorePrecedent(precedent, context) {
  const haystack = [
    context.task,
    context.scope,
    ...(context.changedFiles ?? []),
  ].join(" ").toLowerCase();

  const needles = [
    precedent.scope,
    precedent.trigger,
    precedent.lesson,
    precedent.injection,
    ...(Array.isArray(precedent.paths) ? precedent.paths : []),
  ]
    .join(" ")
    .toLowerCase()
    .split(/[^a-z0-9_:-]+/u)
    .filter((word) => word.length >= 4);

  const uniqueNeedles = new Set(needles);
  let score = 0;

  for (const needle of uniqueNeedles) {
    if (haystack.includes(needle)) {
      score += 1;
    }
  }

  if (context.scope && precedent.scope === context.scope) {
    score += 5;
  }

  if (Array.isArray(precedent.paths) && precedent.paths.length > 0) {
    for (const file of context.changedFiles ?? []) {
      if (precedent.paths.some((path) => file.includes(path) || path.includes(file))) {
        score += 4;
      }
    }
  }

  return score;
}

function formatInjectionBlock(matches) {
  if (matches.length === 0) {
    return "";
  }

  const lines = ["Precedent:"];

  for (const match of matches) {
    lines.push(`- ${match.injection}`);
  }

  return lines.join("\n");
}

function formatInjection(match) {
  return {
    id: match.id,
    score: match.score,
    scope: match.scope,
    artifact: match.artifact,
    injection: match.injection,
    sourceTrace: match.source_trace,
  };
}

function parseListArg(value) {
  if (!value) {
    return [];
  }

  return value
    .split(",")
    .map((item) => item.trim())
    .filter((item) => item.length > 0);
}

function assessPromotionCandidate(precedent) {
  const reasons = [];

  if (!precedent.evidence.some((item) => typeof item === "string" && item.trim().length > 0)) {
    reasons.push("precedent.evidence must include at least one concrete evidence item");
  }

  const baselineFailures = precedent.promotion.baseline_failures;
  const rerunFailures = precedent.promotion.rerun_failures;

  if (!Number.isFinite(baselineFailures)) {
    reasons.push("precedent.promotion.baseline_failures must be a number");
  }

  if (!Number.isFinite(rerunFailures)) {
    reasons.push("precedent.promotion.rerun_failures must be a number");
  }

  if (Number.isFinite(baselineFailures) && Number.isFinite(rerunFailures) && baselineFailures <= rerunFailures) {
    reasons.push("precedent.promotion must show baseline_failures greater than rerun_failures");
  }

  return {
    ok: reasons.length === 0,
    reasons,
  };
}

async function ensureState(stateDir) {
  await mkdir(stateDir, { recursive: true });
  await mkdir(join(stateDir, "traces"), { recursive: true });
  await ensureFile(join(stateDir, "precedents.jsonl"));
  await ensureFile(join(stateDir, "events.jsonl"));
}

async function readHookEvent() {
  let rawEvent = "";
  let source = "stdin";

  if (args["event-file"]) {
    source = args["event-file"];
    rawEvent = await readFile(resolve(args["event-file"]), "utf8");
  } else {
    rawEvent = await readStdin();
  }

  if (rawEvent.trim().length === 0) {
    fail("hook requires JSON from stdin or --event-file <path>");
  }

  return parseJson(rawEvent, source);
}

async function readStdin() {
  const chunks = [];

  for await (const chunk of process.stdin) {
    chunks.push(Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk));
  }

  return Buffer.concat(chunks).toString("utf8");
}

async function ensureFile(path) {
  try {
    await access(path);
  } catch {
    await mkdir(dirname(path), { recursive: true });
    await writeFile(path, "");
  }
}

async function appendJsonLine(path, value) {
  await ensureFile(path);
  await appendFile(path, `${JSON.stringify(value)}\n`);
}

async function readJsonLines(path) {
  try {
    const content = await readFile(path, "utf8");
    return content
      .split("\n")
      .filter((line) => line.trim().length > 0)
      .map((line) => parseJson(line, path));
  } catch (error) {
    if (error.code === "ENOENT") {
      return [];
    }

    throw error;
  }
}

function parseJson(content, path) {
  try {
    return JSON.parse(content);
  } catch (error) {
    fail(`invalid JSON in ${path}: ${error.message}`);
  }
}

function requireString(value, name) {
  if (typeof value !== "string" || value.trim().length === 0) {
    fail(`${name} must be a non-empty string`);
  }

  return value;
}

function statePath() {
  return resolve(args["state-dir"] ?? DEFAULT_STATE_DIR);
}

function safeFileName(value) {
  return value.replace(/[^a-zA-Z0-9_.-]/gu, "_");
}

function print(value) {
  if (args.json) {
    process.stdout.write(`${JSON.stringify(value)}\n`);
    return;
  }

  process.stdout.write(`${JSON.stringify(value, null, 2)}\n`);
}

function printHelp() {
  process.stdout.write(`precedent: passive hook memory for agent-readiness

Usage:
  precedent init [--state-dir .precedent]
  precedent observe --trace trace.json [--state-dir .precedent]
  precedent inject --task "add webhook handler" [--scope feature:webhooks] [--limit 2]
  precedent hook [--event-file hook.json] [--state-dir .precedent] [--limit 2]
  precedent hook before-turn --task "add webhook handler" [--scope feature:webhooks] [--changed-files paths]
  precedent report [--state-dir .precedent]

Commands:
  init      Create local Precedent state.
  observe   Ingest one agent trace and promote embedded precedent.
  inject    Return relevant precedent for the current task.
  hook      Run a passive hook from JSON, or the legacy before-turn flags shape.
  report    Summarize local precedent state.
`);
}

function fail(message) {
  process.stderr.write(`precedent: ${message}\n`);
  process.exit(1);
}

main().catch((error) => {
  fail(error.stack ?? error.message);
});
