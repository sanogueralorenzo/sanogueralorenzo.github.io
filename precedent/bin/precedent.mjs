#!/usr/bin/env node

import { mkdir, readFile, writeFile, appendFile, access, readdir } from "node:fs/promises";
import { spawn } from "node:child_process";
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

  if (command === "compile") {
    await compilePrecedents();
    return;
  }

  if (command === "replay") {
    await replayCase();
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
      join(stateDir, "candidates.jsonl"),
      join(stateDir, "events.jsonl"),
      join(stateDir, "replays"),
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
    const candidate = normalizePrecedent(precedentFromTrace(trace), traceId);
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

async function compilePrecedents() {
  const stateDir = statePath();
  await ensureState(stateDir);

  const traces = await readStoredTraces(join(stateDir, "traces"));
  const candidates = traces
    .flatMap((trace) => compileTraceCandidates(trace))
    .sort((left, right) => left.id.localeCompare(right.id));

  await writeJsonLines(join(stateDir, "candidates.jsonl"), candidates);
  await appendJsonLine(join(stateDir, "events.jsonl"), {
    type: "compile_completed",
    observedAt: new Date().toISOString(),
    traces: traces.length,
    candidates: candidates.length,
    candidateIds: candidates.map((candidate) => candidate.id),
  });

  print({
    ok: true,
    traces: traces.length,
    candidates,
  });
}

async function replayCase() {
  const casePath = args.case;

  if (!casePath) {
    fail("replay requires --case <path>");
  }

  const stateDir = statePath();
  await ensureState(stateDir);

  const resolvedCasePath = resolve(casePath);
  const replayCase = parseJson(await readFile(resolvedCasePath, "utf8"), casePath);
  const replayId = requireString(replayCase.id, "case.id");
  const replayDir = join(stateDir, "replays", safeFileName(replayId));
  const startedAt = new Date().toISOString();
  const cwd = replayCase.cwd ? resolve(dirname(resolvedCasePath), replayCase.cwd) : process.cwd();

  await mkdir(replayDir, { recursive: true });

  const baseline = await runReplayCommand({
    label: "baseline",
    command: requireString(replayCase.baseline?.command, "case.baseline.command"),
    cwd,
    outputDir: replayDir,
  });
  const rerun = await runReplayCommand({
    label: "rerun",
    command: requireString(replayCase.rerun?.command, "case.rerun.command"),
    cwd,
    outputDir: replayDir,
  });
  const promotion = {
    baseline_failures: baseline.exitCode === 0 ? 0 : 1,
    rerun_failures: rerun.exitCode === 0 ? 0 : 1,
    baseline_exit_code: baseline.exitCode,
    rerun_exit_code: rerun.exitCode,
  };
  const improved = promotion.baseline_failures > promotion.rerun_failures;
  const replay = {
    id: replayId,
    casePath: resolvedCasePath,
    cwd,
    startedAt,
    completedAt: new Date().toISOString(),
    task: replayCase.task ?? null,
    scope: replayCase.scope ?? null,
    changedFiles: Array.isArray(replayCase.changedFiles) ? replayCase.changedFiles : [],
    baseline,
    rerun,
    promotion,
    improved,
  };
  const replayPath = join(replayDir, "replay.json");
  const trace = buildReplayTrace(replayCase, replay, replayPath);

  await writeFile(replayPath, JSON.stringify(replay, null, 2));

  let tracePath = null;
  if (args["trace-out"]) {
    tracePath = resolve(args["trace-out"]);
    await mkdir(dirname(tracePath), { recursive: true });
    await writeFile(tracePath, JSON.stringify(trace, null, 2));
  }

  await appendJsonLine(join(stateDir, "events.jsonl"), {
    type: "replay_completed",
    observedAt: replay.completedAt,
    replayId,
    improved,
    baselineExitCode: baseline.exitCode,
    rerunExitCode: rerun.exitCode,
    replayPath,
    tracePath,
  });

  print({
    ok: true,
    replay,
    replayPath,
    tracePath,
    trace,
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
  const candidates = await readJsonLines(join(stateDir, "candidates.jsonl"));
  const events = await readJsonLines(join(stateDir, "events.jsonl"));
  const replays = await readReplayCount(join(stateDir, "replays"));

  const artifactCounts = {};
  for (const precedent of precedents) {
    const artifact = precedent.artifact ?? "unknown";
    artifactCounts[artifact] = (artifactCounts[artifact] ?? 0) + 1;
  }

  print({
    stateDir,
    precedents: precedents.length,
    candidates: candidates.length,
    replays,
    events: events.length,
    artifactCounts,
  });
}

function compileTraceCandidates(trace) {
  if (trace.precedent) {
    return [];
  }

  const traceId = requireString(trace.id, "trace.id");
  const failures = Array.isArray(trace.failures) ? trace.failures : [];
  const failureTypes = classifyFailures(failures);

  if (failureTypes.length === 0) {
    return [];
  }

  const scope = typeof trace.scope === "string" && trace.scope.trim().length > 0 ? trace.scope : "repo";
  const evidence = collectTraceEvidence(trace);
  const id = `cand_${safeFileName(scope)}_${failureTypes.join("_")}`;

  return [{
    id,
    status: "candidate",
    scope,
    trigger: triggerForTrace(trace),
    lesson: lessonForFailureTypes(failureTypes, scope),
    artifact: "skill",
    paths: pathsForScope(scope),
    source_traces: [traceId],
    failure_types: failureTypes,
    evidence,
    injection: injectionForFailureTypes(failureTypes, scope),
    promotion_required: "Replay the task with this candidate injected, then promote only with concrete evidence and baseline_failures > rerun_failures.",
  }];
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

function precedentFromTrace(trace) {
  if (!trace.replay?.verified || !trace.replay.promotion) {
    return trace.precedent;
  }

  const evidence = Array.isArray(trace.precedent.evidence) ? trace.precedent.evidence : [];
  const replayEvidence = Array.isArray(trace.replay.evidence) ? trace.replay.evidence : [];

  return {
    ...trace.precedent,
    evidence: [...evidence, ...replayEvidence],
    promotion: trace.replay.promotion,
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

async function runReplayCommand({ label, command, cwd, outputDir }) {
  const startedAt = Date.now();
  const result = await spawnShell(command, cwd);
  const durationMs = Date.now() - startedAt;
  const stdoutPath = join(outputDir, `${label}.stdout.txt`);
  const stderrPath = join(outputDir, `${label}.stderr.txt`);

  await writeFile(stdoutPath, result.stdout);
  await writeFile(stderrPath, result.stderr);

  return {
    command,
    cwd,
    exitCode: result.exitCode,
    durationMs,
    stdoutPath,
    stderrPath,
  };
}

function spawnShell(command, cwd) {
  return new Promise((resolvePromise, reject) => {
    const child = spawn(command, {
      cwd,
      shell: true,
      stdio: ["ignore", "pipe", "pipe"],
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
      resolvePromise({
        exitCode,
        stdout,
        stderr,
      });
    });
  });
}

function buildReplayTrace(replayCase, replay, replayPath) {
  if (!replayCase.precedent) {
    fail("case.precedent is required to emit a promotion-ready trace");
  }

  const traceId = `${replay.id}-replay`;
  const replayEvidence = [
    `replay: baseline exited ${replay.baseline.exitCode}`,
    `replay: rerun exited ${replay.rerun.exitCode}`,
    `replay: ${replayPath}`,
  ];

  return {
    id: traceId,
    task: replay.task,
    scope: replay.scope,
    outcome: replay.improved ? "replay_improved" : "replay_not_improved",
    changedFiles: replay.changedFiles,
    failures: Array.isArray(replayCase.failures) ? replayCase.failures : [],
    replay: {
      verified: true,
      id: replay.id,
      path: replayPath,
      evidence: replayEvidence,
      promotion: replay.promotion,
    },
    precedent: {
      ...replayCase.precedent,
      source_trace: traceId,
      evidence: Array.isArray(replayCase.precedent.evidence) ? replayCase.precedent.evidence : [],
      promotion: replay.promotion,
    },
  };
}

function classifyFailures(failures) {
  const joined = failures.join(" ").toLowerCase();
  const types = [];

  if (joined.includes("wrong test") || joined.includes("setup") || joined.includes("command")) {
    types.push("wrong_test_command");
  }

  if (joined.includes("outside") || joined.includes("boundary") || joined.includes("broad") || joined.includes("wrong repo slice")) {
    types.push("wrong_repo_slice");
  }

  if (joined.includes("nullable") || joined.includes("contract") || joined.includes("schema") || joined.includes("payload")) {
    types.push("missed_contract");
  }

  return types;
}

function collectTraceEvidence(trace) {
  const evidence = [];

  for (const failure of Array.isArray(trace.failures) ? trace.failures : []) {
    if (typeof failure === "string" && failure.trim().length > 0) {
      evidence.push(`failure: ${failure}`);
    }
  }

  const validation = trace.hooks?.["validation.after_run"];
  if (validation?.command || validation?.result || validation?.evidence) {
    evidence.push(`validation: ${[validation.command, validation.result, validation.evidence].filter(Boolean).join(" - ")}`);
  }

  const review = trace.hooks?.["review.after_feedback"];
  for (const comment of Array.isArray(review?.comments) ? review.comments : []) {
    if (typeof comment === "string" && comment.trim().length > 0) {
      evidence.push(`review-comment: ${comment}`);
    }
  }

  return evidence;
}

function triggerForTrace(trace) {
  if (typeof trace.task === "string" && trace.task.trim().length > 0) {
    return `task resembles: ${trace.task}`;
  }

  return "task matches the same repo scope and failure pattern";
}

function lessonForFailureTypes(failureTypes, scope) {
  const lessons = [];

  if (failureTypes.includes("wrong_test_command")) {
    lessons.push("use the narrow validation command captured by this feature slice");
  }

  if (failureTypes.includes("wrong_repo_slice")) {
    lessons.push(`keep edits inside ${scope} boundaries`);
  }

  if (failureTypes.includes("missed_contract")) {
    lessons.push("inspect existing tests, types, and fixtures for implicit payload contracts before editing");
  }

  return capitalizeSentence(lessons.join("; "));
}

function injectionForFailureTypes(failureTypes, scope) {
  const instructions = [];

  if (failureTypes.includes("wrong_test_command")) {
    instructions.push("identify and run the narrow feature test command before broad validation");
  }

  if (failureTypes.includes("wrong_repo_slice")) {
    instructions.push(`keep changes inside ${scope} boundaries unless evidence requires otherwise`);
  }

  if (failureTypes.includes("missed_contract")) {
    instructions.push("check existing tests, types, and fixtures for nullable or optional payload fields");
  }

  return `For ${scope} changes: ${instructions.join("; ")}.`;
}

function pathsForScope(scope) {
  if (!scope.includes(":")) {
    return [];
  }

  const [kind, name] = scope.split(":", 2);
  if (kind !== "feature" || !name) {
    return [];
  }

  return [`features/${name}`];
}

function capitalizeSentence(value) {
  if (value.length === 0) {
    return value;
  }

  return `${value[0].toUpperCase()}${value.slice(1)}.`;
}

async function ensureState(stateDir) {
  await mkdir(stateDir, { recursive: true });
  await mkdir(join(stateDir, "traces"), { recursive: true });
  await mkdir(join(stateDir, "replays"), { recursive: true });
  await ensureFile(join(stateDir, "precedents.jsonl"));
  await ensureFile(join(stateDir, "candidates.jsonl"));
  await ensureFile(join(stateDir, "events.jsonl"));
}

async function readStoredTraces(tracesDir) {
  const entries = await readdir(tracesDir, { withFileTypes: true });
  const traceFiles = entries
    .filter((entry) => entry.isFile() && entry.name.endsWith(".json"))
    .map((entry) => join(tracesDir, entry.name))
    .sort();
  const traces = [];

  for (const traceFile of traceFiles) {
    traces.push(parseJson(await readFile(traceFile, "utf8"), traceFile));
  }

  return traces;
}

async function readReplayCount(replaysDir) {
  try {
    const entries = await readdir(replaysDir, { withFileTypes: true });
    return entries.filter((entry) => entry.isDirectory()).length;
  } catch (error) {
    if (error.code === "ENOENT") {
      return 0;
    }

    throw error;
  }
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

async function writeJsonLines(path, values) {
  await ensureFile(path);
  await writeFile(path, values.map((value) => JSON.stringify(value)).join("\n") + (values.length > 0 ? "\n" : ""));
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
  precedent compile [--state-dir .precedent]
  precedent replay --case replay-case.json [--trace-out trace.json] [--state-dir .precedent]
  precedent inject --task "add webhook handler" [--scope feature:webhooks] [--limit 2]
  precedent hook [--event-file hook.json] [--state-dir .precedent] [--limit 2]
  precedent hook before-turn --task "add webhook handler" [--scope feature:webhooks] [--changed-files paths]
  precedent report [--state-dir .precedent]

Commands:
  init      Create local Precedent state.
  observe   Ingest one agent trace and promote embedded precedent.
  compile   Mine observed raw traces into candidate precedent artifacts.
  replay    Run baseline/rerun commands and emit verified promotion evidence.
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
