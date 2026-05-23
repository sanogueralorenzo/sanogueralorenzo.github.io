#!/usr/bin/env node

import { mkdir, readFile, writeFile, appendFile, access, readdir } from "node:fs/promises";
import { spawn } from "node:child_process";
import { dirname, join, resolve } from "node:path";

const DEFAULT_STATE_DIR = ".precedent";
const SCHEMA_VERSION = "precedent.v1";
const SUPPORTED_EVENT_HOOKS = new Set([
  "context.before_turn",
  "validation.after_run",
  "diff.after_edit",
  "outcome.after_task",
]);

const command = process.argv[2] ?? "help";
const hookName = command === "hook" && process.argv[3] && !process.argv[3].startsWith("--") ? process.argv[3] : null;
const runSeparatorIndex = command === "run" ? process.argv.indexOf("--", 3) : -1;
const runCommandArgs = command === "run" && runSeparatorIndex >= 0 ? process.argv.slice(runSeparatorIndex + 1) : [];
const rawArgs = command === "run" && runSeparatorIndex >= 0
  ? process.argv.slice(3, runSeparatorIndex)
  : process.argv.slice(command === "hook" && hookName ? 4 : 3);
const args = parseArgs(rawArgs);

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

  if (command === "explain") {
    await explainPrecedent();
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

  if (command === "run") {
    await runValidationCommand();
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
      join(stateDir, "sessions"),
      join(stateDir, "traces"),
    ],
  });
}

async function observeTrace() {
  const stateDir = statePath();
  await ensureState(stateDir);

  if (!args.trace && !args.session) {
    fail("observe requires --trace <path> or --session <id>");
  }

  const trace = args.session
    ? await traceFromSession(stateDir, args.session)
    : parseJson(await readFile(resolve(args.trace), "utf8"), args.trace);
  assertSchemaVersion(trace, "trace");
  const traceId = requireString(trace.id, "trace.id");
  const observedAt = new Date().toISOString();
  let promoted = null;
  let rejected = null;
  let promotionAction = "none";

  if (trace.precedent) {
    const candidate = normalizePrecedent(precedentFromTrace(trace), traceId);
    const assessment = assessPromotionCandidate(candidate);

    if (assessment.ok) {
      const promotion = await upsertPromotedPrecedent(stateDir, candidate, observedAt);

      promoted = promotion.precedent;
      promotionAction = promotion.action;
    } else {
      rejected = {
        id: candidate.id,
        reasons: assessment.reasons,
      };
      promotionAction = "rejected";
    }
  }

  const event = {
    type: "trace_observed",
    observedAt,
    traceId,
    precedentId: promoted?.id ?? rejected?.id ?? null,
    task: trace.task ?? null,
    outcome: trace.outcome ?? null,
    scope: trace.scope ?? null,
    failures: Array.isArray(trace.failures) ? trace.failures : [],
    promotionStatus: promoted ? "promoted" : trace.precedent ? "rejected" : "none",
    promotionAction,
    promotionReasons: rejected?.reasons ?? [],
  };

  await writeFile(join(stateDir, "traces", `${safeFileName(traceId)}.json`), JSON.stringify(trace, null, 2));
  await appendJsonLine(join(stateDir, "events.jsonl"), event);

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
      matchReasons: match.matchReasons ?? [],
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

async function explainPrecedent() {
  const id = args.id;

  if (!id) {
    fail("explain requires --id <precedent_id>");
  }

  const stateDir = statePath();
  await ensureState(stateDir);

  const precedents = await readJsonLines(join(stateDir, "precedents.jsonl"));
  const events = await readJsonLines(join(stateDir, "events.jsonl"));
  const traces = await readStoredTraces(join(stateDir, "traces"));
  const promoted = precedents.find((precedent) => precedent.id === id);

  if (promoted) {
    print({
      ok: true,
      id,
      promotionStatus: "promoted",
      promotionReason: promotionReason(promoted),
      source: sourceForPrecedent(promoted, traces),
      replay: replayExplanation(promoted),
      evidence: Array.isArray(promoted.evidence) ? promoted.evidence : [],
      matching: matchingExplanation(promoted),
      injections: injectionEventsForPrecedent(events, id),
      record: promoted,
    });
    return;
  }

  const rejectedTrace = traces.find((trace) => trace.precedent?.id === id);
  if (rejectedTrace) {
    const candidate = normalizePrecedent(precedentFromTrace(rejectedTrace), rejectedTrace.id);
    const assessment = assessPromotionCandidate(candidate);
    const rejectionEvents = events.filter((event) => event.precedentId === id && event.promotionStatus === "rejected");

    print({
      ok: true,
      id,
      promotionStatus: "rejected",
      promotionReason: assessment.reasons.join("; "),
      source: sourceForTrace(rejectedTrace),
      replay: replayExplanation(candidate),
      evidence: Array.isArray(candidate.evidence) ? candidate.evidence : [],
      matching: matchingExplanation(candidate),
      injections: [],
      rejectionEvents: rejectionEvents.slice(-5),
    });
    return;
  }

  fail(`unknown precedent id: ${id}`);
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
  assertSchemaVersion(replayCase, "case");
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
  assertSchemaVersion(event, "event");
  const hook = requireString(event.hook, "event.hook");

  if (!SUPPORTED_EVENT_HOOKS.has(hook)) {
    fail(`unsupported hook: ${hook}; supported hooks: ${Array.from(SUPPORTED_EVENT_HOOKS).join(", ")}`);
  }

  if (hook === "context.before_turn") {
    await contextBeforeTurnEventHook(event);
    return;
  }

  if (hook === "validation.after_run") {
    await validationAfterRunEventHook(event);
    return;
  }

  if (hook === "diff.after_edit") {
    await diffAfterEditEventHook(event);
    return;
  }

  if (hook === "outcome.after_task") {
    await outcomeAfterTaskEventHook(event);
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
    injectionMatches: matches.map((match) => ({
      id: match.id,
      score: match.score,
      reasons: match.matchReasons ?? [],
    })),
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
    injections: matches.map(formatInjection),
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
  const rankedMatches = rankPrecedents(precedents, context)
    .filter((precedent) => precedent.score >= threshold)
    .slice(0, limit);
  const selected = await suppressRepeatedSessionInjections({
    stateDir,
    sessionId: typeof event.sessionId === "string" ? event.sessionId : null,
    matches: rankedMatches,
    allowRepeat: event.allowRepeat === true,
  });
  const matches = selected.matches;
  const contextBlock = formatInjectionBlock(matches);

  const hookEvent = {
    type: "hook_event",
    receivedAt: new Date().toISOString(),
    hook: event.hook,
    sessionId: typeof event.sessionId === "string" ? event.sessionId : null,
    task,
    scope: context.scope || null,
    changedFiles: context.changedFiles,
    threshold,
    allowRepeat: event.allowRepeat === true,
    injections: matches.map((match) => match.id),
    injectionMatches: matches.map((match) => ({
      id: match.id,
      score: match.score,
      reasons: match.matchReasons ?? [],
    })),
    suppressedInjections: selected.suppressed.map(formatSuppressedInjection),
  };

  await appendJsonLine(join(stateDir, "events.jsonl"), hookEvent);
  const sessionEvent = event.sessionId
    ? await appendSessionEvent(stateDir, {
      ...hookEvent,
      task,
      contextBlock,
    })
    : null;

  print({
    ok: true,
    hook: event.hook,
    sessionId: sessionEvent?.sessionId ?? null,
    injections: matches.map(formatInjection),
    suppressedInjections: selected.suppressed.map(formatSuppressedInjection),
    contextBlock,
  });
}

async function validationAfterRunEventHook(event) {
  const stateDir = statePath();
  await ensureState(stateDir);

  const sessionId = requireString(event.sessionId, "event.sessionId");
  const commandText = requireString(event.command, "event.command");
  const exitCode = requireNumber(event.exitCode, "event.exitCode");
  const failureSignals = validationFailureSignals(event, exitCode);
  const sessionEvent = await appendSessionEvent(stateDir, {
    type: "hook_event",
    receivedAt: new Date().toISOString(),
    hook: event.hook,
    sessionId,
    command: commandText,
    exitCode,
    durationMs: numberOrNull(event.durationMs),
    failureSignals,
    stdout: typeof event.stdout === "string" ? event.stdout : "",
    stderr: typeof event.stderr === "string" ? event.stderr : "",
  });

  await appendJsonLine(join(stateDir, "events.jsonl"), {
    type: "hook_event",
    receivedAt: sessionEvent.receivedAt,
    hook: event.hook,
    sessionId,
    command: commandText,
    exitCode,
    failureSignals,
  });

  print({
    ok: true,
    hook: event.hook,
    sessionId,
    recorded: true,
    sessionEventPath: sessionEvent.path,
    validation: {
      command: commandText,
      exitCode,
      failureSignals,
      stdoutPath: sessionEvent.event.stdoutPath ?? null,
      stderrPath: sessionEvent.event.stderrPath ?? null,
    },
  });
}

async function diffAfterEditEventHook(event) {
  const stateDir = statePath();
  await ensureState(stateDir);

  const sessionId = requireString(event.sessionId, "event.sessionId");
  const changedFiles = Array.isArray(event.changedFiles) ? event.changedFiles : parseListArg(event.changedFiles);
  const breadthSignals = diffBreadthSignals(event, changedFiles);
  const sessionEvent = await appendSessionEvent(stateDir, {
    type: "hook_event",
    receivedAt: new Date().toISOString(),
    hook: event.hook,
    sessionId,
    changedFiles,
    linesAdded: numberOrNull(event.linesAdded),
    linesDeleted: numberOrNull(event.linesDeleted),
    breadthSignals,
  });

  await appendJsonLine(join(stateDir, "events.jsonl"), {
    type: "hook_event",
    receivedAt: sessionEvent.receivedAt,
    hook: event.hook,
    sessionId,
    changedFiles,
    breadthSignals,
  });

  print({
    ok: true,
    hook: event.hook,
    sessionId,
    recorded: true,
    sessionEventPath: sessionEvent.path,
    diff: {
      changedFiles,
      breadthSignals,
    },
  });
}

async function outcomeAfterTaskEventHook(event) {
  const stateDir = statePath();
  await ensureState(stateDir);

  const sessionId = requireString(event.sessionId, "event.sessionId");
  const sessionEvent = await appendSessionEvent(stateDir, {
    type: "hook_event",
    receivedAt: new Date().toISOString(),
    hook: event.hook,
    sessionId,
    success: Boolean(event.success),
    status: typeof event.status === "string" ? event.status : (event.success ? "success" : "failure"),
    retries: numberOrNull(event.retries),
    tokenEstimate: numberOrNull(event.tokenEstimate),
    notes: typeof event.notes === "string" ? event.notes : "",
    precedent: event.precedent ?? null,
    replay: event.replay ?? null,
  });

  await appendJsonLine(join(stateDir, "events.jsonl"), {
    type: "hook_event",
    receivedAt: sessionEvent.receivedAt,
    hook: event.hook,
    sessionId,
    success: sessionEvent.event.success,
    status: sessionEvent.event.status,
    retries: sessionEvent.event.retries,
    tokenEstimate: sessionEvent.event.tokenEstimate,
  });

  print({
    ok: true,
    hook: event.hook,
    sessionId,
    recorded: true,
    sessionEventPath: sessionEvent.path,
    outcome: {
      success: sessionEvent.event.success,
      status: sessionEvent.event.status,
      retries: sessionEvent.event.retries,
      tokenEstimate: sessionEvent.event.tokenEstimate,
    },
  });
}

async function runValidationCommand() {
  const sessionId = requireString(args.session, "run.session");

  if (runSeparatorIndex < 0 || runCommandArgs.length === 0) {
    fail("run requires --session <id> -- <command>");
  }

  const stateDir = statePath();
  await ensureState(stateDir);

  const startedAt = Date.now();
  const result = await spawnPassthrough(runCommandArgs);
  const durationMs = Date.now() - startedAt;
  const commandText = shellQuoteCommand(runCommandArgs);
  const failureSignals = validationFailureSignals({
    stderr: result.stderr,
  }, result.exitCode);
  const sessionEvent = await appendSessionEvent(stateDir, {
    type: "hook_event",
    receivedAt: new Date().toISOString(),
    hook: "validation.after_run",
    sessionId,
    command: commandText,
    exitCode: result.exitCode,
    durationMs,
    failureSignals,
    stdout: result.stdout,
    stderr: result.stderr,
  });

  await appendJsonLine(join(stateDir, "events.jsonl"), {
    type: "hook_event",
    receivedAt: sessionEvent.receivedAt,
    hook: "validation.after_run",
    sessionId,
    command: commandText,
    exitCode: result.exitCode,
    durationMs,
    failureSignals,
  });

  process.exit(result.exitCode);
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

function assertSchemaVersion(value, name) {
  if (value?.schema_version !== SCHEMA_VERSION) {
    fail(`${name}.schema_version must be "${SCHEMA_VERSION}"`);
  }
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
    .map((precedent) => {
      const match = scorePrecedent(precedent, context);

      return {
        ...precedent,
        score: match.score,
        matchReasons: match.reasons,
      };
    })
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
  const matchedTerms = [];

  for (const needle of uniqueNeedles) {
    if (haystack.includes(needle)) {
      score += 1;
      matchedTerms.push(needle);
    }
  }

  const reasons = [];

  if (matchedTerms.length > 0) {
    reasons.push({
      type: "text_overlap",
      score: matchedTerms.length,
      terms: matchedTerms.slice(0, 8),
    });
  }

  if (context.scope && precedent.scope === context.scope) {
    score += 5;
    reasons.push({
      type: "scope_match",
      score: 5,
      scope: precedent.scope,
    });
  }

  if (Array.isArray(precedent.paths) && precedent.paths.length > 0) {
    for (const file of context.changedFiles ?? []) {
      const matchedPath = precedent.paths.find((path) => file.includes(path) || path.includes(file));

      if (matchedPath) {
        score += 4;
        reasons.push({
          type: "path_match",
          score: 4,
          file,
          path: matchedPath,
        });
      }
    }
  }

  return { score, reasons };
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
    matchReasons: match.matchReasons ?? [],
    scope: match.scope,
    artifact: match.artifact,
    injection: match.injection,
    sourceTrace: match.source_trace,
  };
}

function formatSuppressedInjection(match) {
  return {
    id: match.id,
    score: match.score,
    reason: "already_injected_in_session",
  };
}

async function suppressRepeatedSessionInjections({ stateDir, sessionId, matches, allowRepeat }) {
  if (!sessionId || allowRepeat || matches.length === 0) {
    return { matches, suppressed: [] };
  }

  const priorEvents = await readSessionEvents(stateDir, sessionId);
  const priorInjectedIds = new Set(
    priorEvents
      .filter((event) => event.hook === "context.before_turn")
      .flatMap((event) => Array.isArray(event.injections) ? event.injections : []),
  );
  const selected = [];
  const suppressed = [];

  for (const match of matches) {
    if (priorInjectedIds.has(match.id)) {
      suppressed.push(match);
      continue;
    }

    selected.push(match);
  }

  return {
    matches: selected,
    suppressed,
  };
}

function promotionReason(precedent) {
  const baselineFailures = precedent.promotion?.baseline_failures;
  const rerunFailures = precedent.promotion?.rerun_failures;

  if (Number.isFinite(baselineFailures) && Number.isFinite(rerunFailures)) {
    return `verified replay improved from ${baselineFailures} baseline failure(s) to ${rerunFailures} rerun failure(s)`;
  }

  return "promoted with concrete evidence";
}

function sourceForPrecedent(precedent, traces) {
  const trace = traces.find((item) => item.id === precedent.source_trace)
    ?? traces.find((item) => item.precedent?.id === precedent.id)
    ?? null;

  if (!trace) {
    return {
      traceId: precedent.source_trace ?? null,
      sessionId: null,
      replayId: null,
      replayPath: null,
    };
  }

  return sourceForTrace(trace);
}

function sourceForTrace(trace) {
  return {
    traceId: trace.id ?? null,
    sessionId: trace.sessionId ?? null,
    sessionPath: trace.session?.path ?? null,
    replayId: trace.replay?.id ?? null,
    replayPath: trace.replay?.path ?? null,
  };
}

function replayExplanation(precedent) {
  const promotion = precedent.promotion ?? {};
  const baselineFailures = promotion.baseline_failures;
  const rerunFailures = promotion.rerun_failures;
  const baselineExitCode = promotion.baseline_exit_code ?? null;
  const rerunExitCode = promotion.rerun_exit_code ?? null;

  return {
    baselineFailures: Number.isFinite(baselineFailures) ? baselineFailures : null,
    rerunFailures: Number.isFinite(rerunFailures) ? rerunFailures : null,
    failureDelta: Number.isFinite(baselineFailures) && Number.isFinite(rerunFailures)
      ? baselineFailures - rerunFailures
      : null,
    baselineExitCode,
    rerunExitCode,
  };
}

function matchingExplanation(precedent) {
  return {
    scope: precedent.scope ?? null,
    trigger: precedent.trigger ?? null,
    artifact: precedent.artifact ?? null,
    paths: Array.isArray(precedent.paths) ? precedent.paths : [],
  };
}

function injectionEventsForPrecedent(events, id) {
  return events
    .filter((event) => {
      if (Array.isArray(event.injectedIds) && event.injectedIds.includes(id)) {
        return true;
      }

      return Array.isArray(event.injections) && event.injections.includes(id);
    })
    .slice(-5)
    .map((event) => ({
      type: event.type ?? null,
      hook: event.hook ?? "context.before_turn",
      observedAt: event.observedAt ?? event.receivedAt ?? null,
      sessionId: event.sessionId ?? null,
      task: event.task ?? null,
      scope: event.scope ?? null,
      changedFiles: Array.isArray(event.changedFiles) ? event.changedFiles : [],
    }));
}

async function appendSessionEvent(stateDir, rawEvent) {
  const sessionId = requireString(rawEvent.sessionId, "event.sessionId");
  const sessionFile = join(stateDir, "sessions", `${safeFileName(sessionId)}.jsonl`);
  const artifactDir = join(stateDir, "sessions", `${safeFileName(sessionId)}-artifacts`);
  const event = { ...rawEvent };

  if (typeof event.stdout === "string" && event.stdout.length > 0) {
    await mkdir(artifactDir, { recursive: true });
    const stdoutPath = join(artifactDir, `${Date.now()}-${event.hook.replaceAll(".", "_")}.stdout.txt`);
    await writeFile(stdoutPath, event.stdout);
    event.stdoutPath = stdoutPath;
    event.stdoutSummary = summarizeText(event.stdout);
    delete event.stdout;
  }

  if (typeof event.stderr === "string" && event.stderr.length > 0) {
    await mkdir(artifactDir, { recursive: true });
    const stderrPath = join(artifactDir, `${Date.now()}-${event.hook.replaceAll(".", "_")}.stderr.txt`);
    await writeFile(stderrPath, event.stderr);
    event.stderrPath = stderrPath;
    event.stderrSummary = summarizeText(event.stderr);
    delete event.stderr;
  }

  await appendJsonLine(sessionFile, event);

  return {
    sessionId,
    path: sessionFile,
    event,
    receivedAt: event.receivedAt,
  };
}

async function readSessionEvents(stateDir, sessionId) {
  if (!sessionId) {
    return [];
  }

  return readJsonLines(join(stateDir, "sessions", `${safeFileName(sessionId)}.jsonl`));
}

async function traceFromSession(stateDir, sessionId) {
  const sessionFile = join(stateDir, "sessions", `${safeFileName(sessionId)}.jsonl`);
  const events = await readJsonLines(sessionFile);

  if (events.length === 0) {
    fail(`session has no recorded hook events: ${sessionId}`);
  }

  const beforeTurns = events.filter((event) => event.hook === "context.before_turn");
  const validations = events.filter((event) => event.hook === "validation.after_run");
  const diffs = events.filter((event) => event.hook === "diff.after_edit");
  const outcomes = events.filter((event) => event.hook === "outcome.after_task");
  const lastBeforeTurn = beforeTurns.at(-1) ?? {};
  const lastOutcome = outcomes.at(-1) ?? {};
  const changedFiles = uniqueStrings([
    ...beforeTurns.flatMap((event) => Array.isArray(event.changedFiles) ? event.changedFiles : []),
    ...diffs.flatMap((event) => Array.isArray(event.changedFiles) ? event.changedFiles : []),
  ]);
  const validationFailures = validations
    .filter((event) => event.exitCode !== 0)
    .map((event) => {
      const signals = Array.isArray(event.failureSignals) ? event.failureSignals.join(", ") : "non_zero_exit";
      return `command failed: ${event.command} (${signals})`;
    });
  const diffFailures = diffs
    .filter((event) => Array.isArray(event.breadthSignals) && event.breadthSignals.length > 0)
    .map((event) => `broad edit: ${event.breadthSignals.join(", ")}`);
  const outcomeFailures = outcomes
    .filter((event) => event.success === false && typeof event.notes === "string" && event.notes.trim().length > 0)
    .map((event) => `outcome: ${event.notes}`);
  const failures = [...validationFailures, ...diffFailures, ...outcomeFailures];
  const failedValidation = validations.find((event) => event.exitCode !== 0);
  const validationEvidence = failedValidation
    ? {
      command: failedValidation.command,
      result: `exit ${failedValidation.exitCode}`,
      evidence: [
        ...(Array.isArray(failedValidation.failureSignals) ? failedValidation.failureSignals : []),
        failedValidation.stderrSummary,
        failedValidation.stdoutSummary,
      ].filter(Boolean).join(" - "),
    }
    : null;

  return {
    schema_version: SCHEMA_VERSION,
    id: `session-${safeFileName(sessionId)}`,
    sessionId,
    task: lastBeforeTurn.task ?? lastOutcome.task ?? null,
    scope: lastBeforeTurn.scope ?? lastOutcome.scope ?? null,
    outcome: lastOutcome.status ?? (lastOutcome.success === true ? "success" : "unknown"),
    changedFiles,
    failures,
    hooks: {
      ...(validationEvidence ? { "validation.after_run": validationEvidence } : {}),
    },
    session: {
      path: sessionFile,
      eventCount: events.length,
      hooks: uniqueStrings(events.map((event) => event.hook).filter(Boolean)),
    },
    ...(lastOutcome.precedent ? { precedent: lastOutcome.precedent } : {}),
    ...(lastOutcome.replay ? { replay: lastOutcome.replay } : {}),
  };
}

function validationFailureSignals(event, exitCode) {
  return uniqueStrings([
    ...(Array.isArray(event.failureSignals) ? event.failureSignals : parseListArg(event.failureSignals)),
    ...(exitCode === 0 ? [] : ["non_zero_exit"]),
    ...(typeof event.stderr === "string" && event.stderr.trim().length > 0 ? ["stderr_output"] : []),
  ]);
}

function diffBreadthSignals(event, changedFiles) {
  const topLevelDirs = uniqueStrings(changedFiles.map((file) => file.split("/", 1)[0]).filter(Boolean));

  return uniqueStrings([
    ...(Array.isArray(event.breadthSignals) ? event.breadthSignals : parseListArg(event.breadthSignals)),
    ...(changedFiles.length > 5 ? ["many_files_touched"] : []),
    ...(topLevelDirs.length > 2 ? ["multiple_top_level_scopes"] : []),
  ]);
}

function summarizeText(value) {
  const normalized = value.replace(/\s+/gu, " ").trim();
  return normalized.length <= 500 ? normalized : `${normalized.slice(0, 497)}...`;
}

function uniqueStrings(values) {
  return [...new Set(values.filter((value) => typeof value === "string" && value.trim().length > 0))];
}

function numberOrNull(value) {
  if (value === null || value === undefined || value === "") {
    return null;
  }

  const number = Number(value);
  return Number.isFinite(number) ? number : null;
}

function parseListArg(value) {
  if (!value) {
    return [];
  }

  if (Array.isArray(value)) {
    return value
      .map((item) => String(item).trim())
      .filter((item) => item.length > 0);
  }

  if (typeof value !== "string") {
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

async function upsertPromotedPrecedent(stateDir, candidate, observedAt) {
  const ledgerPath = join(stateDir, "precedents.jsonl");
  const existingPrecedents = await readJsonLines(ledgerPath);
  const existing = existingPrecedents.find((precedent) => precedent.id === candidate.id);
  const createdAt = existing?.created_at ?? existing?.promoted_at ?? observedAt;
  const next = {
    ...existing,
    ...candidate,
    evidence: uniqueStrings([
      ...(Array.isArray(existing?.evidence) ? existing.evidence : []),
      ...(Array.isArray(candidate.evidence) ? candidate.evidence : []),
    ]),
    source_trace: candidate.source_trace ?? existing?.source_trace,
    source_traces: uniqueStrings([
      ...(Array.isArray(existing?.source_traces) ? existing.source_traces : []),
      existing?.source_trace,
      candidate.source_trace,
    ]),
    promotion: candidate.promotion,
    promotion_status: "promoted",
    promoted_at: existing?.promoted_at ?? observedAt,
    created_at: createdAt,
    updated_at: observedAt,
  };

  const action = existing ? promotionRecordChanged(existing, next) ? "updated" : "unchanged" : "created";
  const finalRecord = action === "unchanged" ? existing : next;
  const records = existingPrecedents
    .filter((precedent) => precedent.id !== candidate.id)
    .concat(finalRecord)
    .sort((left, right) => left.id.localeCompare(right.id));

  await writeJsonLines(ledgerPath, records);

  return {
    action,
    precedent: finalRecord,
  };
}

function promotionRecordChanged(existing, next) {
  return stableComparablePrecedent(existing) !== stableComparablePrecedent(next);
}

function stableComparablePrecedent(precedent) {
  const {
    updated_at: _updatedAt,
    ...stableFields
  } = precedent;

  return JSON.stringify(sortObject(stableFields));
}

function sortObject(value) {
  if (Array.isArray(value)) {
    return value.map(sortObject);
  }

  if (value && typeof value === "object") {
    return Object.fromEntries(
      Object.entries(value)
        .sort(([left], [right]) => left.localeCompare(right))
        .map(([key, item]) => [key, sortObject(item)]),
    );
  }

  return value;
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

function spawnPassthrough(commandArgs) {
  return new Promise((resolvePromise, reject) => {
    const child = spawn(commandArgs[0], commandArgs.slice(1), {
      cwd: process.cwd(),
      stdio: ["ignore", "pipe", "pipe"],
    });
    let stdout = "";
    let stderr = "";

    child.stdout.on("data", (chunk) => {
      stdout += chunk.toString("utf8");
      process.stdout.write(chunk);
    });
    child.stderr.on("data", (chunk) => {
      stderr += chunk.toString("utf8");
      process.stderr.write(chunk);
    });
    child.on("error", reject);
    child.on("close", (exitCode) => {
      resolvePromise({
        exitCode: exitCode ?? 1,
        stdout,
        stderr,
      });
    });
  });
}

function shellQuoteCommand(commandArgs) {
  return commandArgs
    .map((arg) => /^[a-zA-Z0-9_./:=@+-]+$/u.test(arg) ? arg : JSON.stringify(arg))
    .join(" ");
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
    schema_version: SCHEMA_VERSION,
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
  await mkdir(join(stateDir, "sessions"), { recursive: true });
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
    const trace = parseJson(await readFile(traceFile, "utf8"), traceFile);
    assertSchemaVersion(trace, "trace");
    traces.push(trace);
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

function requireNumber(value, name) {
  const number = Number(value);

  if (!Number.isFinite(number)) {
    fail(`${name} must be a number`);
  }

  return number;
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
  precedent observe --session session-id [--state-dir .precedent]
  precedent compile [--state-dir .precedent]
  precedent replay --case replay-case.json [--trace-out trace.json] [--state-dir .precedent]
  precedent inject --task "add webhook handler" [--scope feature:webhooks] [--limit 2]
  precedent explain --id precedent-id [--state-dir .precedent]
  precedent hook [--event-file hook.json] [--state-dir .precedent] [--limit 2]
  precedent hook before-turn --task "add webhook handler" [--scope feature:webhooks] [--changed-files paths]
  precedent run --session session-id [--state-dir .precedent] -- command [args...]
  precedent report [--state-dir .precedent]

Commands:
  init      Create local Precedent state.
  observe   Ingest one agent trace or recorded hook session.
  compile   Mine observed raw traces into candidate precedent artifacts.
  replay    Run baseline/rerun commands and emit verified promotion evidence.
  inject    Return relevant precedent for the current task.
  explain   Explain promotion evidence, matching inputs, and injection history.
  hook      Run a passive hook from JSON, or the legacy before-turn flags shape.
  run       Run a validation command and capture it as a session hook event.
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
