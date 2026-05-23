#!/usr/bin/env node

import { mkdir, readFile, writeFile, appendFile, access } from "node:fs/promises";
import { dirname, join, resolve } from "node:path";

const DEFAULT_STATE_DIR = ".precedent";

const command = process.argv[2] ?? "help";
const args = parseArgs(process.argv.slice(3));

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

  await mkdir(stateDir, { recursive: true });
  await mkdir(join(stateDir, "traces"), { recursive: true });
  await ensureFile(join(stateDir, "precedents.jsonl"));
  await ensureFile(join(stateDir, "events.jsonl"));

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
  await initIfMissing(stateDir);

  const rawTrace = await readFile(resolve(tracePath), "utf8");
  const trace = parseJson(rawTrace, tracePath);
  const traceId = requireString(trace.id, "trace.id");
  const observedAt = new Date().toISOString();
  const event = {
    type: "trace_observed",
    observedAt,
    traceId,
    task: trace.task ?? null,
    outcome: trace.outcome ?? null,
    scope: trace.scope ?? null,
    failures: Array.isArray(trace.failures) ? trace.failures : [],
  };

  await appendJsonLine(join(stateDir, "events.jsonl"), event);
  await writeFile(join(stateDir, "traces", `${safeFileName(traceId)}.json`), JSON.stringify(trace, null, 2));

  let promoted = null;

  if (trace.precedent) {
    promoted = normalizePrecedent(trace.precedent, traceId);
    await appendJsonLine(join(stateDir, "precedents.jsonl"), promoted);
  }

  print({
    ok: true,
    observed: event,
    promoted,
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
    source_trace: precedent.source_trace ?? traceId,
    evidence: Array.isArray(precedent.evidence) ? precedent.evidence : [],
    injection: requireString(precedent.injection, "precedent.injection"),
    promotion: precedent.promotion ?? {},
  };
}

function rankPrecedents(precedents, context) {
  return precedents
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
  ].join(" ").toLowerCase();

  const needles = [
    precedent.scope,
    precedent.trigger,
    precedent.lesson,
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

  return score;
}

async function initIfMissing(stateDir) {
  try {
    await access(stateDir);
  } catch {
    await initState();
  }
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
  precedent report [--state-dir .precedent]

Commands:
  init      Create local Precedent state.
  observe   Ingest one agent trace and promote embedded precedent.
  inject    Return relevant precedent for the current task.
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
