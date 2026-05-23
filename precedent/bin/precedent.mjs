#!/usr/bin/env node

import { createHash } from "node:crypto";
import { mkdir, readFile, writeFile, appendFile, access, readdir, rm, stat, rename } from "node:fs/promises";
import { spawn } from "node:child_process";
import { dirname, join, resolve } from "node:path";

const DEFAULT_STATE_DIR = ".precedent";
const SCHEMA_VERSION = "precedent.v1";
const CONFIG_SCHEMA_VERSION = "precedent.config.v1";
const ADAPTER_SCHEMA_VERSION = "precedent.adapter.v1";
const SUPPORTED_GUARD_TYPES = new Set([
  "changed_files_within_paths",
  "required_validation_command",
]);
const SUPPORTED_EVENT_HOOKS = new Set([
  "conversation.observe",
  "context.before_turn",
  "context.after_inject",
  "validation.after_run",
  "diff.after_edit",
  "review.after_feedback",
  "finalize.before_response",
  "outcome.after_task",
  "orchestration.after_idle",
  "repair.before_retry",
  "repair.after_retry",
]);
const STALE_SIGNAL_THRESHOLD = 2;
const RETIRE_SIGNAL_THRESHOLD = 4;
const REPAIR_EFFICACY_SUPPRESSION_THRESHOLD = 2;
const PROMOTION_TRIAL_LEASE_MS = 5 * 60 * 1000;
const PROMOTION_TRIAL_MAX_ATTEMPTS = 2;
const FINALIZATION_TRIGGER_HOOKS = new Set([
  "context.before_turn",
  "warrant.issue",
  "validation.after_run",
  "diff.after_edit",
  "review.after_feedback",
]);
const DEFAULT_CONFIG = {
  schema_version: CONFIG_SCHEMA_VERSION,
  stateDir: DEFAULT_STATE_DIR,
  maxInjections: 2,
  hookTimeoutMs: 1500,
  failurePolicy: "fail_open",
  retentionDays: 30,
  redaction: {
    enabled: true,
  },
  enabledHooks: Array.from(SUPPORTED_EVENT_HOOKS),
};
let runtimeConfig = DEFAULT_CONFIG;
let runtimeConfigPath = null;
let runtimeConfigHash = stableHash(DEFAULT_CONFIG);
let activeLockDir = null;
let atomicWriteCounter = 0;
let failThrows = false;
const printCaptureStack = [];

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

  await loadRuntimeConfig();

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

  if (command === "context") {
    await exportContext();
    return;
  }

  if (command === "warrant") {
    await issueWarrant();
    return;
  }

  if (command === "artifact") {
    await materializeArtifact();
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

  if (command === "promotion-trial") {
    await runPromotionTrial();
    return;
  }

  if (command === "promote-pending") {
    await promotePendingTrials();
    return;
  }

  if (command === "hook") {
    await runHook();
    return;
  }

  if (command === "loop") {
    await runLoop();
    return;
  }

  if (command === "run") {
    await runValidationCommand();
    return;
  }

  if (command === "manifest") {
    await printManifest();
    return;
  }

  if (command === "attach") {
    await attachRuntime();
    return;
  }

  if (command === "attach-run") {
    await attachRunSession();
    return;
  }

  if (command === "check") {
    await checkState();
    return;
  }

  if (command === "prune") {
    await pruneState();
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

    if (key === "json" || key === "help" || key === "dry-run" || key === "strict" || key === "promote-session-pairs" || key === "include-stale" || key === "auto-promote") {
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

  await withStateLock(stateDir, async () => {
    await ensureState(stateDir);
    await writeDefaultConfig(stateDir);
  });

  print({
    ok: true,
    stateDir,
    files: [
      join(stateDir, "config.json"),
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

  if (!args.trace && !args.session) {
    fail("observe requires --trace <path> or --session <id>");
  }

  const rawTrace = args.session
    ? await traceFromSession(stateDir, args.session)
    : parseJson(await readFile(resolve(args.trace), "utf8"), args.trace);
  const observed = await observeTraceRecord({ stateDir, rawTrace });

  print({
    ok: true,
    ...observed,
  });
}

async function observeTraceRecord({ stateDir, rawTrace }) {
  const redaction = redactSecretsDeep(rawTrace);
  const trace = redaction.value;
  assertSchemaVersion(trace, "trace");
  const traceId = requireString(trace.id, "trace.id");
  const observedAt = new Date().toISOString();
  let promoted = null;
  let rejected = null;
  let promotionAction = "none";
  let event = null;

  await withStateLock(stateDir, async () => {
    await ensureState(stateDir);
    if (trace.precedent) {
      const candidate = normalizePrecedent(precedentFromTrace(trace), traceId);
      const assessment = assessPromotionCandidate(candidate);
      const replayAudit = assessment.ok ? await replayAuditEntry(candidate, stateDir) : null;

      if (assessment.ok && replayAudit.status === "verified") {
        const promotion = await upsertPromotedPrecedent(stateDir, candidate, observedAt);

        promoted = promotion.precedent;
        promotionAction = promotion.action;
      } else {
        rejected = {
          id: candidate.id,
          reasons: [
            ...assessment.reasons,
            ...(replayAudit && replayAudit.status !== "verified"
              ? [`replay audit ${replayAudit.status}: ${replayAudit.messages.join("; ")}`]
              : []),
          ],
        };
        promotionAction = "rejected";
      }
    }

    event = {
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
      redactions: redaction.counts,
    };

    await writeFileAtomic(join(stateDir, "traces", `${safeFileName(traceId)}.json`), `${JSON.stringify(trace, null, 2)}\n`);
    await appendJsonLine(join(stateDir, "events.jsonl"), event);
  });

  return {
    observed: event,
    promoted,
    rejected,
  };
}

async function injectPrecedent() {
  const task = args.task;

  if (!task) {
    fail("inject requires --task <text>");
  }

  const stateDir = statePath();
  const precedents = await readJsonLines(join(stateDir, "precedents.jsonl"));
  const selected = await suppressReplayAuditInjections({
    stateDir,
    matches: rankPrecedents(precedents, {
      task,
      scope: args.scope ?? "",
      changedFiles: parseListArg(args["changed-files"]),
    }),
  });
  const applicabilitySelected = suppressApplicabilityInjections(selected.matches);
  const matches = applicabilitySelected.matches.slice(0, Number(args.limit ?? runtimeConfig.maxInjections));

  print({
    task,
    scope: args.scope ?? null,
    injections: matches.map((match) => ({
      id: match.id,
      score: match.score,
      matchReasons: match.matchReasons ?? [],
      injection: match.injection,
      sourceTrace: match.source_trace,
      applicabilityReceipt: match.applicabilityReceipt,
    })),
    suppressedInjections: [
      ...selected.suppressed.map(formatSuppressedInjection),
      ...applicabilitySelected.suppressed.map(formatSuppressedInjection),
    ],
  });
}

async function exportContext() {
  const stateDir = statePath();
  await ensureState(stateDir);

  const task = args.task ?? (args["task-file"] ? await readFile(resolve(args["task-file"]), "utf8") : null);
  if (!task) {
    fail("context requires --task <text> or --task-file <path>");
  }

  const context = {
    task,
    scope: args.scope ?? "",
    changedFiles: parseListArg(args["changed-files"]),
  };
  const limit = Number(args.limit ?? runtimeConfig.maxInjections);
  const threshold = Number(args.threshold ?? 4);
  const eventId = typeof args["event-id"] === "string" && args["event-id"].trim().length > 0
    ? args["event-id"].trim()
    : null;
  let payload = null;
  const locked = await withStateLock(stateDir, async () => {
    await ensureState(stateDir);
    if (args.session && eventId) {
      const existing = await findSessionEventByEventId(stateDir, args.session, eventId);

      if (existing?.event?.contextPayload) {
        payload = {
          ...existing.event.contextPayload,
          recorded: false,
          deduped: true,
          sessionEventPath: existing.path,
        };
        return;
      }
    }

    const precedents = await readJsonLines(join(stateDir, "precedents.jsonl"));
    const candidates = await readJsonLines(join(stateDir, "candidates.jsonl"));
    const events = await readJsonLines(join(stateDir, "events.jsonl"));
    const replayAuditSelected = await suppressReplayAuditInjections({
      stateDir,
      matches: rankPrecedents(precedents, context)
        .filter((precedent) => precedent.score >= threshold),
    });
    const lifecycleSelected = suppressLifecycleInjections({
      events,
      matches: replayAuditSelected.matches.slice(0, limit),
      includeStale: args["include-stale"] === "true" || args["include-stale"] === true,
    });
    const applicabilitySelected = suppressApplicabilityInjections(lifecycleSelected.matches);
    const selected = await suppressRepeatedSessionInjections({
      stateDir,
      sessionId: args.session ?? null,
      matches: applicabilitySelected.matches,
      allowRepeat: args["allow-repeat"] === "true" || args["allow-repeat"] === true,
    });
    const turnDirectives = await activeTurnDirectivesForSession(stateDir, args.session ?? null);
    const contextBlock = formatRuntimeContextBlock(selected.matches, turnDirectives);
    const observedAt = new Date().toISOString();
    const deliveryReceipt = deliveryReceiptFor({
      sessionId: args.session ?? null,
      eventId,
      injections: selected.matches,
      contextBlock,
      issuedAt: observedAt,
    });
    const suppressedInjections = [
      ...replayAuditSelected.suppressed.map(formatSuppressedInjection),
      ...lifecycleSelected.suppressed.map((match) => formatSuppressedInjection(match, events)),
      ...applicabilitySelected.suppressed.map(formatSuppressedInjection),
      ...selected.suppressed.map(formatSuppressedInjection),
    ];
    const revisionBriefs = revisionBriefsForSuppressed(events, lifecycleSelected.suppressed);
    const promotionTrials = promotionTrialsForContext({
      candidates,
      context,
      suppressed: lifecycleSelected.suppressed,
      sessionId: args.session ?? null,
    });
    const candidateHints = candidateHintsForContext({
      candidates,
      precedents,
      context,
      stateDir,
      sessionId: args.session ?? null,
    });
    const exportEvent = {
      type: "context_export",
      observedAt,
      sessionId: args.session ?? null,
      ...eventIdField(eventId),
      task,
      scope: context.scope || null,
      changedFiles: context.changedFiles,
      threshold,
      injections: selected.matches.map((match) => match.id),
      injectionMatches: selected.matches.map((match) => ({
        id: match.id,
        score: match.score,
        reasons: match.matchReasons ?? [],
      })),
      suppressedInjections,
      revisionBriefs,
      promotionTrials,
      candidateHints,
      deliveryReceipt,
      turnDirectives,
      contextBlockHash: contextBlockHash(contextBlock),
    };
    payload = {
      schema_version: "precedent.context.v1",
      contextBlock,
      contextBlockHash: exportEvent.contextBlockHash,
      injections: selected.matches.map(formatInjection),
      suppressedInjections,
      revisionBriefs,
      promotionTrials,
      candidateHints,
      deliveryReceipt,
      turnDirectives,
      source: {
        command: "context",
        task,
        taskFile: args["task-file"] ?? null,
        scope: context.scope || null,
        changedFiles: context.changedFiles,
        sessionId: args.session ?? null,
        limit,
        threshold,
      },
      recorded: true,
      deduped: false,
      sessionEventPath: args.session ? join(stateDir, "sessions", `${safeFileName(args.session)}.jsonl`) : null,
    };

    await appendJsonLine(join(stateDir, "events.jsonl"), exportEvent);
    if (args.session) {
      const stored = await appendSessionEvent(stateDir, {
        type: "context_export",
        receivedAt: exportEvent.observedAt,
        hook: "context.export",
        sessionId: args.session,
        ...eventIdField(eventId),
        task,
        scope: context.scope || null,
        changedFiles: context.changedFiles,
        contextBlock,
        contextBlockHash: exportEvent.contextBlockHash,
        injections: exportEvent.injections,
        injectionMatches: exportEvent.injectionMatches,
        suppressedInjections: exportEvent.suppressedInjections,
        revisionBriefs: exportEvent.revisionBriefs,
        promotionTrials: exportEvent.promotionTrials,
        candidateHints: exportEvent.candidateHints,
        deliveryReceipt: exportEvent.deliveryReceipt,
        turnDirectives: exportEvent.turnDirectives,
        contextPayload: payload,
      });
      payload.sessionEventPath = stored.path;
    }
  }, { failOpen: true });

  if (locked?.lockTimeout) {
    payload = {
      schema_version: "precedent.context.v1",
      contextBlock: "",
      contextBlockHash: contextBlockHash(""),
      injections: [],
      suppressedInjections: [{ reason: "lock_timeout" }],
      revisionBriefs: [],
      promotionTrials: [],
      candidateHints: [],
      deliveryReceipt: null,
      turnDirectives: emptyTurnDirectives(),
      recorded: false,
      deduped: false,
      sessionEventPath: null,
      source: {
        command: "context",
        task,
        taskFile: args["task-file"] ?? null,
        scope: context.scope || null,
        changedFiles: context.changedFiles,
        sessionId: args.session ?? null,
        limit,
        threshold,
      },
    };
  }

  if (args.format === "markdown") {
    process.stdout.write(payload.contextBlock ? `${payload.contextBlock}\n` : "");
    return;
  }

  if (args.format && args.format !== "json") {
    fail(`unsupported context format: ${args.format}`);
  }

  print(payload);
}

async function issueWarrant() {
  const stateDir = statePath();
  const sessionId = requireString(args.session, "warrant --session");
  const eventId = requireString(args["event-id"], "warrant --event-id");
  const task = args.task ?? (args["task-file"] ? await readFile(resolve(args["task-file"]), "utf8") : null);
  if (!task) {
    fail("warrant requires --task <text> or --task-file <path>");
  }

  const context = {
    task,
    scope: args.scope ?? "",
    changedFiles: parseListArg(args["changed-files"]),
  };
  const limit = Number(args.limit ?? runtimeConfig.maxInjections);
  const threshold = Number(args.threshold ?? 4);
  const explicitDeliveryId = stringOrNull(args["delivery-id"]);
  let payload = null;

  await withStateLock(stateDir, async () => {
    await ensureState(stateDir);
    const existing = await findSessionEventByEventId(stateDir, sessionId, eventId);
    if (existing?.event?.warrant) {
      payload = {
        ...existing.event.warrant,
        recorded: false,
        deduped: true,
        sessionEventPath: existing.path,
      };
      return;
    }

    const precedents = await readJsonLines(join(stateDir, "precedents.jsonl"));
    const candidates = await readJsonLines(join(stateDir, "candidates.jsonl"));
    const events = await readJsonLines(join(stateDir, "events.jsonl"));
    const turnDirectives = await activeTurnDirectivesForSession(stateDir, sessionId);
    const issuedAt = new Date().toISOString();
    let matches = [];
    let candidateHints = [];
    let deliveryReceipt = null;

    if (explicitDeliveryId) {
      deliveryReceipt = await findDeliveryReceipt(stateDir, explicitDeliveryId);
      if (!deliveryReceipt) {
        fail(`warrant --delivery-id references unknown delivery: ${explicitDeliveryId}`);
      }
      if (deliveryReceipt.sessionId !== sessionId) {
        fail(`warrant --delivery-id session mismatch: ${deliveryReceipt.sessionId} !== ${sessionId}`);
      }
      matches = precedentsForDeliveryReceipt(precedents, deliveryReceipt);
    } else {
      const replayAuditSelected = await suppressReplayAuditInjections({
        stateDir,
        matches: rankPrecedents(precedents, context)
          .filter((precedent) => precedent.score >= threshold),
      });
      const lifecycleSelected = suppressLifecycleInjections({
        events,
        matches: replayAuditSelected.matches.slice(0, limit),
        includeStale: args["include-stale"] === "true" || args["include-stale"] === true,
      });
      const applicabilitySelected = suppressApplicabilityInjections(lifecycleSelected.matches);
      const selected = await suppressRepeatedSessionInjections({
        stateDir,
        sessionId,
        matches: applicabilitySelected.matches,
        allowRepeat: args["allow-repeat"] === "true" || args["allow-repeat"] === true,
      });
      matches = selected.matches;
      candidateHints = candidateHintsForContext({
        candidates,
        precedents,
        context,
        stateDir,
        sessionId,
      });
      deliveryReceipt = deliveryReceiptFor({
        sessionId,
        eventId,
        injections: matches,
        issuedAt,
      });
    }
    const warrant = warrantForContext({
      sessionId,
      eventId,
      issuedAt,
      task,
      context,
      matches,
      candidateHints,
      deliveryReceipt,
      turnDirectives,
    });
    const sessionEvent = await appendSessionEvent(stateDir, {
      type: "warrant_issued",
      receivedAt: issuedAt,
      hook: "warrant.issue",
      sessionId,
      eventId,
      task,
      scope: context.scope || null,
      changedFiles: context.changedFiles,
      warrantId: warrant.warrantId,
      warrant,
      deliveryReceipt,
      turnDirectives,
    });

    if (!sessionEvent.deduped) {
      await appendJsonLine(join(stateDir, "events.jsonl"), {
        type: "warrant_issued",
        observedAt: sessionEvent.receivedAt,
        sessionId,
        eventId,
        warrantId: warrant.warrantId,
        status: warrant.status,
        sourcePrecedents: warrant.sources.precedentIds,
        sourceCandidates: warrant.sources.candidateIds,
      });
    }

    payload = {
      ...sessionEvent.event.warrant,
      recorded: !sessionEvent.deduped,
      deduped: sessionEvent.deduped,
      sessionEventPath: sessionEvent.path,
    };
  });

  print(payload);
}

async function materializeArtifact() {
  const stateDir = statePath();
  const candidateId = requireString(args.candidate, "artifact --candidate");
  let payload = null;

  await withStateLock(stateDir, async () => {
    await ensureState(stateDir);
    const candidates = await readJsonLines(join(stateDir, "candidates.jsonl"));
    const candidate = candidates.find((item) => item.id === candidateId);
    if (!candidate) {
      fail(`unknown candidate id: ${candidateId}`);
    }

    const artifact = artifactDescriptor(candidate, stateDir);
    const content = renderCandidateSkill(candidate, artifact);
    await writeFileAtomic(artifact.path, content);
    const artifactSha256 = sha256Text(content);

    await appendJsonLine(join(stateDir, "events.jsonl"), {
      type: "candidate_artifact_materialized",
      observedAt: new Date().toISOString(),
      candidateId,
      artifactPath: artifact.path,
      artifactSha256,
      injectable: false,
      promotionStatus: candidate.status ?? "candidate",
    });

    payload = {
      schema_version: "precedent.artifact.v1",
      ok: true,
      candidateId,
      artifactPath: artifact.path,
      artifactSha256,
      promotionStatus: candidate.status ?? "candidate",
      injectable: false,
      promotable: false,
      regenerateCommand: artifact.command,
    };
  });

  print(payload);
}

async function compilePrecedents() {
  const stateDir = statePath();
  let traces = [];
  let candidates = [];
  let promoted = [];

  await withStateLock(stateDir, async () => {
    await ensureState(stateDir);

    traces = await readStoredTraces(join(stateDir, "traces"));
    candidates = traces
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

    if (args["promote-session-pairs"]) {
      promoted = await promoteSessionPairs(stateDir);
    }
  });

  print({
    ok: true,
    traces: traces.length,
    candidates,
    promoted,
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
      outcomes: outcomeSummaryForPrecedent(events, id),
      counterexamples: counterexamplesForPrecedent(events, id),
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
  const stateDir = statePath();
  const replayResult = await executeReplayCase({
    stateDir,
    traceOut: args["trace-out"] ? resolve(args["trace-out"]) : null,
  });

  print({
    ok: true,
    ...replayResult,
  });
}

async function runPromotionTrial() {
  const stateDir = statePath();

  if (args.case) {
    fail("promotion-trial accepts --candidate <id>, not --case");
  }

  if (!args.candidate) {
    fail("promotion-trial requires --candidate <id>");
  }

  const traceOut = args["trace-out"]
    ? resolve(args["trace-out"])
    : join(stateDir, "traces", `promotion-trial-${safeFileName(args.candidate)}-${Date.now()}.json`);
  const replayResult = await executeReplayCase({ stateDir, traceOut });
  const observed = await observeTraceRecord({ stateDir, rawTrace: replayResult.trace });
  const replayAudit = observed.promoted ? await replayAuditEntry(observed.promoted, stateDir) : null;

  print({
    ok: true,
    candidateId: args.candidate,
    ...replayResult,
    ...observed,
    replayAudit,
  });
}

async function promotePendingTrials() {
  const stateDir = statePath();
  print(await runPendingPromotionTrials({
    stateDir,
    dryRun: args["dry-run"] === true,
    limit: Number(args.limit ?? 3),
    leaseMs: Number(args["lease-ms"] ?? PROMOTION_TRIAL_LEASE_MS),
    maxAttempts: Number(args["max-attempts"] ?? PROMOTION_TRIAL_MAX_ATTEMPTS),
  }));
}

async function runPendingPromotionTrials({
  stateDir,
  dryRun = false,
  limit = 3,
  leaseMs = PROMOTION_TRIAL_LEASE_MS,
  maxAttempts = PROMOTION_TRIAL_MAX_ATTEMPTS,
}) {
  await ensureState(stateDir);
  const now = new Date();
  const claims = await claimPendingPromotionTrials({
    stateDir,
    dryRun,
    limit,
    leaseMs,
    maxAttempts,
    now,
  });
  const results = [];

  for (const item of claims.items) {
    const safety = replayTrialExecutionSafety(item);
    if (!safety.safe) {
      results.push({
        trialId: item.trialId,
        candidateId: item.candidateId,
        status: "blocked",
        reason: safety.reason,
        blockers: safety.blockers,
      });
      continue;
    }

    if (dryRun) {
      results.push({
        trialId: item.trialId,
        candidateId: item.candidateId,
        status: "dry_run",
        command: item.command,
        attempt: item.attempt,
      });
      continue;
    }

    try {
      const observed = await runPrecedentChildJson(item.command.slice(2));
      await appendJsonLine(join(stateDir, "events.jsonl"), {
        type: "promotion_trial_completed",
        observedAt: new Date().toISOString(),
        runId: item.runId,
        attempt: item.attempt,
        trialId: item.trialId,
        candidateId: item.candidateId,
        sourceEventId: item.sourceEventId,
        sourceSessionId: item.sourceSessionId,
        promotedId: observed.promoted?.id ?? null,
        rejectedId: observed.rejected?.id ?? null,
        replayAuditStatus: observed.replayAudit?.status ?? null,
        replayPath: observed.replayPath ?? null,
        tracePath: observed.tracePath ?? null,
      });
      results.push({
        trialId: item.trialId,
        candidateId: item.candidateId,
        status: observed.promoted ? "promoted" : "completed",
        runId: item.runId,
        attempt: item.attempt,
        promotedId: observed.promoted?.id ?? null,
        rejectedId: observed.rejected?.id ?? null,
        replayAuditStatus: observed.replayAudit?.status ?? null,
      });
    } catch (error) {
      await appendJsonLine(join(stateDir, "events.jsonl"), {
        type: "promotion_trial_failed",
        observedAt: new Date().toISOString(),
        runId: item.runId,
        attempt: item.attempt,
        trialId: item.trialId,
        candidateId: item.candidateId,
        sourceEventId: item.sourceEventId,
        sourceSessionId: item.sourceSessionId,
        error: error.message,
      });
      results.push({
        trialId: item.trialId,
        candidateId: item.candidateId,
        status: "failed",
        runId: item.runId,
        attempt: item.attempt,
        error: error.message,
      });
    }
  }

  const afterEvents = dryRun ? claims.events : await readJsonLines(join(stateDir, "events.jsonl"));
  return {
    ok: results.every((result) => result.status !== "failed"),
    schema_version: "precedent.promote_pending.v1",
    dryRun,
    stateDir,
    leaseMs,
    maxAttempts,
    processed: results.length,
    results,
    queue: promotionTrialQueue(afterEvents, { now: new Date(), maxAttempts }),
  };
}

async function claimPendingPromotionTrials({ stateDir, dryRun, limit, leaseMs, maxAttempts, now }) {
  let events = [];
  let items = [];

  await withStateLock(stateDir, async () => {
    await ensureState(stateDir);
    events = await readJsonLines(join(stateDir, "events.jsonl"));
    const queue = promotionTrialQueue(events, { now, maxAttempts });
    items = queue.items
      .filter((item) => item.status === "ready" || item.status === "blocked")
      .slice(0, limit)
      .map((item) => ({
        ...item,
        runId: `run_${stableHash({ trialId: item.trialId, attempt: item.attempt, now: now.toISOString() }).slice(0, 16)}`,
        leaseExpiresAt: new Date(now.getTime() + leaseMs).toISOString(),
      }));

    if (dryRun) {
      return;
    }

    for (const item of items.filter((entry) => replayTrialExecutionSafety(entry).safe)) {
      await appendJsonLine(join(stateDir, "events.jsonl"), {
        type: "promotion_trial_started",
        observedAt: now.toISOString(),
        runId: item.runId,
        attempt: item.attempt,
        leaseExpiresAt: item.leaseExpiresAt,
        trialId: item.trialId,
        candidateId: item.candidateId,
        sourceEventId: item.sourceEventId,
        sourceSessionId: item.sourceSessionId,
        command: item.command,
      });
    }
  });

  return { events, items };
}

function replayTrialExecutionSafety(item) {
  const blockers = [];
  if (item.autoExecute !== true) {
    blockers.push("auto_execute_not_enabled");
  }
  const baseline = replayCommandSafety(item.baselineCommand);
  if (!baseline.safe) {
    blockers.push(`baseline_${baseline.reason}`);
  }
  const rerun = replayCommandSafety(item.rerunCommand);
  if (!rerun.safe) {
    blockers.push(`rerun_${rerun.reason}`);
  }

  return {
    safe: blockers.length === 0,
    reason: blockers[0] ?? null,
    blockers,
  };
}

async function executeReplayCase({ stateDir, traceOut = null }) {
  const {
    rawReplayCase,
    replayCase,
    resolvedCasePath,
    cwd,
  } = await loadReplayCaseInput(stateDir);
  const replayId = requireString(replayCase.id, "case.id");
  const replayDir = join(stateDir, "replays", safeFileName(replayId));
  const startedAt = new Date().toISOString();
  let baseline = null;
  let rerun = null;
  let replay = null;
  let trace = null;
  let tracePath = null;
  const replayPath = join(replayDir, "replay.json");

  await withStateLock(stateDir, async () => {
    await ensureState(stateDir);
    await mkdir(replayDir, { recursive: true });

    baseline = await runReplayCommand({
      label: "baseline",
      command: requireString(rawReplayCase.baseline?.command, "case.baseline.command"),
      storedCommand: requireString(replayCase.baseline?.command, "case.baseline.command"),
      cwd,
      outputDir: replayDir,
    });
    rerun = await runReplayCommand({
      label: "rerun",
      command: requireString(rawReplayCase.rerun?.command, "case.rerun.command"),
      storedCommand: requireString(replayCase.rerun?.command, "case.rerun.command"),
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
    replay = {
      id: replayId,
      casePath: resolvedCasePath,
      candidateId: replayCase.candidateId ?? null,
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
    const replayContent = `${JSON.stringify(replay, null, 2)}\n`;
    const artifactSha256 = sha256Text(replayContent);
    trace = buildReplayTrace(replayCase, replay, replayPath, artifactSha256);

    await writeFileAtomic(replayPath, replayContent);

    if (traceOut) {
      tracePath = resolve(traceOut);
      await mkdir(dirname(tracePath), { recursive: true });
      await writeFileAtomic(tracePath, `${JSON.stringify(trace, null, 2)}\n`);
    }

    await appendJsonLine(join(stateDir, "events.jsonl"), {
      type: "replay_completed",
      observedAt: replay.completedAt,
      replayId,
      improved,
      baselineExitCode: baseline.exitCode,
      rerunExitCode: rerun.exitCode,
      candidateId: replay.candidateId,
      replayPath,
      tracePath,
    });
  });

  return {
    replay,
    replayPath,
    tracePath,
    trace,
  };
}

async function loadReplayCaseInput(stateDir) {
  if (args.case && args.candidate) {
    fail("replay accepts either --case or --candidate, not both");
  }

  if (args.candidate) {
    await ensureState(stateDir);
    const candidates = await readJsonLines(join(stateDir, "candidates.jsonl"));
    const candidate = candidates.find((item) => item.id === args.candidate);
    if (!candidate) {
      fail(`unknown candidate id: ${args.candidate}`);
    }

    const baselineCommand = requireString(args["baseline-command"] ?? args.baseline, "replay --baseline-command");
    const rerunCommand = args["rerun-command"] ?? args.rerun ?? validationCommandFromEvidence(candidate.evidence);
    if (!rerunCommand) {
      fail("replay --candidate requires --rerun-command or successful validation evidence");
    }

    const rawReplayCase = replayCaseFromCandidate({
      candidate,
      baselineCommand,
      rerunCommand,
    });
    const replayCase = redactSecretsDeep(rawReplayCase).value;
    assertSchemaVersion(replayCase, "case");

    return {
      rawReplayCase,
      replayCase,
      resolvedCasePath: null,
      cwd: args.cwd ? resolve(args.cwd) : process.cwd(),
    };
  }

  const casePath = args.case;
  if (!casePath) {
    fail("replay requires --case <path> or --candidate <id>");
  }

  const resolvedCasePath = resolve(casePath);
  const rawReplayCase = parseJson(await readFile(resolvedCasePath, "utf8"), casePath);
  const replayCase = redactSecretsDeep(rawReplayCase).value;
  assertSchemaVersion(replayCase, "case");

  return {
    rawReplayCase,
    replayCase,
    resolvedCasePath,
    cwd: replayCase.cwd ? resolve(dirname(resolvedCasePath), replayCase.cwd) : process.cwd(),
  };
}

function replayCaseFromCandidate({ candidate, baselineCommand, rerunCommand }) {
  return {
    schema_version: SCHEMA_VERSION,
    id: `candidate-${safeFileName(requireString(candidate.id, "candidate.id"))}`,
    candidateId: candidate.id,
    task: candidate.trigger ?? candidate.lesson ?? candidate.id,
    scope: candidate.scope ?? "repo",
    changedFiles: Array.isArray(candidate.paths) ? candidate.paths : [],
    failures: Array.isArray(candidate.failure_types) ? candidate.failure_types : [],
    baseline: {
      command: baselineCommand,
    },
    rerun: {
      command: rerunCommand,
    },
    precedent: {
      id: requireString(candidate.id, "candidate.id"),
      scope: requireString(candidate.scope, "candidate.scope"),
      trigger: requireString(candidate.trigger, "candidate.trigger"),
      lesson: requireString(candidate.lesson, "candidate.lesson"),
      artifact: requireString(candidate.artifact, "candidate.artifact"),
      paths: Array.isArray(candidate.paths) ? candidate.paths : [],
      evidence: [
        ...(Array.isArray(candidate.evidence) ? candidate.evidence : []),
        `candidate replay: ${candidate.id}`,
      ],
      injection: requireString(candidate.injection, "candidate.injection"),
      guards: Array.isArray(candidate.guards) ? candidate.guards : [],
    },
  };
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
  const payload = await dispatchHookEvent(await readHookEvent());
  print(payload);
}

async function dispatchHookEvent(rawEvent) {
  const event = redactSecretsDeep(rawEvent).value;
  assertSchemaVersion(event, "event");
  const hook = requireString(event.hook, "event.hook");

  if (!SUPPORTED_EVENT_HOOKS.has(hook)) {
    fail(`unsupported hook: ${hook}; supported hooks: ${Array.from(SUPPORTED_EVENT_HOOKS).join(", ")}`);
  }

  if (!runtimeConfig.enabledHooks.includes(hook)) {
    fail(`disabled hook: ${hook}`);
  }

  if (hook === "context.before_turn") {
    return capturePrintedPayload(() => contextBeforeTurnEventHook(event));
  }

  if (hook === "context.after_inject") {
    return capturePrintedPayload(() => contextAfterInjectEventHook(event));
  }

  if (hook === "conversation.observe") {
    return capturePrintedPayload(() => conversationObserveEventHook(event));
  }

  if (hook === "validation.after_run") {
    return capturePrintedPayload(() => validationAfterRunEventHook(event));
  }

  if (hook === "diff.after_edit") {
    return capturePrintedPayload(() => diffAfterEditEventHook(event));
  }

  if (hook === "review.after_feedback") {
    return capturePrintedPayload(() => reviewAfterFeedbackEventHook(event));
  }

  if (hook === "finalize.before_response") {
    return capturePrintedPayload(() => finalizeBeforeResponseEventHook(event));
  }

  if (hook === "outcome.after_task") {
    return capturePrintedPayload(() => outcomeAfterTaskEventHook(event));
  }

  if (hook === "orchestration.after_idle") {
    return capturePrintedPayload(() => orchestrationAfterIdleEventHook(event));
  }

  if (hook === "repair.before_retry") {
    return capturePrintedPayload(() => repairBeforeRetryEventHook(event));
  }

  if (hook === "repair.after_retry") {
    return capturePrintedPayload(() => repairAfterRetryEventHook(event));
  }

  fail(`unsupported hook: ${hook}`);
}

async function runLoop() {
  const input = await readStdin();
  const lines = input.split(/\r?\n/u);

  for (let index = 0; index < lines.length; index += 1) {
    const line = lines[index].trim();

    if (line.length === 0) {
      continue;
    }

    const payload = await loopLinePayload(line, index + 1);
    process.stdout.write(`${JSON.stringify(payload)}\n`);
  }
}

async function loopLinePayload(line, lineNumber) {
  let event = null;

  try {
    event = JSON.parse(line);
  } catch (error) {
    return {
      ok: false,
      line: lineNumber,
      error: `invalid JSON: ${error.message}`,
    };
  }

  try {
    return await withFailThrows(() => dispatchHookEvent(event));
  } catch (error) {
    return {
      ok: false,
      line: lineNumber,
      hook: typeof event?.hook === "string" ? event.hook : null,
      error: error.message,
    };
  }
}

async function beforeTurnHook() {
  const task = args.task;

  if (!task) {
    fail("hook before-turn requires --task <text>");
  }

  const stateDir = statePath();
  const context = {
    task,
    scope: args.scope ?? "",
    changedFiles: parseListArg(args["changed-files"]),
  };
  const limit = Number(args.limit ?? runtimeConfig.maxInjections);
  const threshold = Number(args.threshold ?? 4);
  let matches = [];
  let suppressed = [];
  let block = "";

  await withStateLock(stateDir, async () => {
    await ensureState(stateDir);
    const precedents = await readJsonLines(join(stateDir, "precedents.jsonl"));
    const selected = await suppressReplayAuditInjections({
      stateDir,
      matches: rankPrecedents(precedents, context)
        .filter((precedent) => precedent.score >= threshold),
    });
    const applicabilitySelected = suppressApplicabilityInjections(selected.matches);
    matches = applicabilitySelected.matches.slice(0, limit);
    suppressed = [
      ...selected.suppressed.map(formatSuppressedInjection),
      ...applicabilitySelected.suppressed.map(formatSuppressedInjection),
    ];
    block = formatInjectionBlock(matches);
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
      suppressedInjections: suppressed,
    };

    await appendJsonLine(join(stateDir, "events.jsonl"), event);
  });

  print({
    hook: "context.before_turn",
    task,
    scope: context.scope || null,
    changedFiles: context.changedFiles,
    threshold,
    injected: matches.length > 0,
    block,
    injections: matches.map(formatInjection),
    suppressedInjections: suppressed,
  });
}

async function contextBeforeTurnEventHook(event) {
  const task = requireString(event.task, "event.task");
  const stateDir = statePath();
  const sessionId = typeof event.sessionId === "string" ? event.sessionId : null;
  const eventId = hookEventId(event);
  const context = {
    task,
    scope: typeof event.scope === "string" ? event.scope : "",
    changedFiles: Array.isArray(event.changedFiles) ? event.changedFiles : parseListArg(event.changedFiles),
  };
  const limit = Number(args.limit ?? event.limit ?? runtimeConfig.maxInjections);
  const threshold = Number(args.threshold ?? event.threshold ?? 4);
  let matches = [];
  let suppressed = [];
  let revisionBriefs = [];
  let promotionTrials = [];
  let candidateHints = [];
  let turnDirectives = emptyTurnDirectives();
  let deliveryReceipt = null;
  let contextBlock = "";
  let injections = [];
  let sessionEvent = null;
  const locked = await withStateLock(stateDir, async () => {
    await ensureState(stateDir);
    if (sessionId && eventId) {
      const existing = await findSessionEventByEventId(stateDir, sessionId, eventId);

      if (existing?.event?.contextPayload) {
        const payload = existing.event.contextPayload;
        suppressed = payload.suppressedInjections ?? [];
        revisionBriefs = payload.revisionBriefs ?? [];
        promotionTrials = payload.promotionTrials ?? [];
        candidateHints = payload.candidateHints ?? [];
        turnDirectives = payload.turnDirectives ?? emptyTurnDirectives();
        deliveryReceipt = payload.deliveryReceipt ?? null;
        contextBlock = payload.contextBlock ?? "";
        injections = payload.injections ?? [];
        sessionEvent = {
          sessionId,
          path: existing.path,
          event: existing.event,
          receivedAt: existing.event.receivedAt,
          deduped: true,
        };
        return;
      }
    }

    const precedents = await readJsonLines(join(stateDir, "precedents.jsonl"));
    const candidates = await readJsonLines(join(stateDir, "candidates.jsonl"));
    const events = await readJsonLines(join(stateDir, "events.jsonl"));
    const rankedMatches = rankPrecedents(precedents, context)
      .filter((precedent) => precedent.score >= threshold);
    const replayAuditSelected = await suppressReplayAuditInjections({
      stateDir,
      matches: rankedMatches,
    });
    const lifecycleSelected = suppressLifecycleInjections({
      events,
      matches: replayAuditSelected.matches.slice(0, limit),
      includeStale: event.includeStale === true,
    });
    const applicabilitySelected = suppressApplicabilityInjections(lifecycleSelected.matches);
    const selected = await suppressRepeatedSessionInjections({
      stateDir,
      sessionId: typeof event.sessionId === "string" ? event.sessionId : null,
      matches: applicabilitySelected.matches,
      allowRepeat: event.allowRepeat === true,
    });
    matches = selected.matches;
    suppressed = [
      ...replayAuditSelected.suppressed.map(formatSuppressedInjection),
      ...lifecycleSelected.suppressed.map((match) => formatSuppressedInjection(match, events)),
      ...applicabilitySelected.suppressed.map(formatSuppressedInjection),
      ...selected.suppressed.map(formatSuppressedInjection),
    ];
    revisionBriefs = revisionBriefsForSuppressed(events, lifecycleSelected.suppressed);
    promotionTrials = promotionTrialsForContext({
      candidates,
      context,
      suppressed: lifecycleSelected.suppressed,
      sessionId: typeof event.sessionId === "string" ? event.sessionId : null,
    });
    candidateHints = candidateHintsForContext({
      candidates,
      precedents,
      context,
      stateDir,
      sessionId: typeof event.sessionId === "string" ? event.sessionId : null,
    });
    turnDirectives = await activeTurnDirectivesForSession(stateDir, sessionId);
    contextBlock = formatRuntimeContextBlock(matches, turnDirectives);
    deliveryReceipt = deliveryReceiptFor({
      sessionId,
      eventId,
      injections: matches,
      contextBlock,
      issuedAt: new Date().toISOString(),
    });

    const hookEvent = {
      type: "hook_event",
      receivedAt: new Date().toISOString(),
      hook: event.hook,
      sessionId,
      ...eventIdField(eventId),
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
      suppressedInjections: suppressed,
      revisionBriefs,
      promotionTrials,
      candidateHints,
      turnDirectives,
      deliveryReceipt,
      contextBlockHash: contextBlockHash(contextBlock),
    };
    injections = matches.map(formatInjection);
    const contextPayload = {
      ok: true,
      hook: event.hook,
      sessionId,
      injections,
      suppressedInjections: suppressed,
      revisionBriefs,
      promotionTrials,
      candidateHints,
      turnDirectives,
      deliveryReceipt,
      contextBlock,
      contextBlockHash: hookEvent.contextBlockHash,
    };

    await appendJsonLine(join(stateDir, "events.jsonl"), hookEvent);
    sessionEvent = sessionId
      ? await appendSessionEvent(stateDir, {
        ...hookEvent,
        task,
        contextBlock,
        contextBlockHash: hookEvent.contextBlockHash,
        contextPayload,
      })
      : null;
    if (sessionEvent?.deduped) {
      suppressed = sessionEvent.event.contextPayload?.suppressedInjections ?? suppressed;
      revisionBriefs = sessionEvent.event.contextPayload?.revisionBriefs ?? revisionBriefs;
      promotionTrials = sessionEvent.event.contextPayload?.promotionTrials ?? promotionTrials;
      candidateHints = sessionEvent.event.contextPayload?.candidateHints ?? candidateHints;
      turnDirectives = sessionEvent.event.contextPayload?.turnDirectives ?? turnDirectives;
      deliveryReceipt = sessionEvent.event.contextPayload?.deliveryReceipt ?? deliveryReceipt;
      contextBlock = sessionEvent.event.contextPayload?.contextBlock ?? contextBlock;
      injections = sessionEvent.event.contextPayload?.injections ?? injections;
    }
  }, { failOpen: true });

  if (locked?.lockTimeout) {
    suppressed = [{ reason: "lock_timeout" }];
    revisionBriefs = [];
    promotionTrials = [];
    candidateHints = [];
    turnDirectives = emptyTurnDirectives();
    deliveryReceipt = null;
    injections = [];
  }

  print({
    ok: true,
    hook: event.hook,
    sessionId: sessionEvent?.sessionId ?? null,
    recorded: !sessionEvent?.deduped,
    deduped: Boolean(sessionEvent?.deduped),
    sessionEventPath: sessionEvent?.path ?? null,
    injections,
    suppressedInjections: suppressed,
    revisionBriefs,
    promotionTrials,
    candidateHints,
    turnDirectives,
    deliveryReceipt,
    contextBlock,
    contextBlockHash: contextBlockHash(contextBlock),
  });
}

async function contextAfterInjectEventHook(event) {
  const stateDir = statePath();
  const sessionId = requireString(event.sessionId, "event.sessionId");
  const eventId = hookEventId(event);
  const deliveryId = requireString(event.deliveryId, "event.deliveryId");
  const inserted = hookBoolean(event.inserted, "event.inserted", true);
  const receivedHash = stringOrNull(event.contextBlockHash);
  let injectionAck = null;
  let sessionEvent = null;

  await withStateLock(stateDir, async () => {
    await ensureState(stateDir);
    const receipt = await findDeliveryReceipt(stateDir, deliveryId);
    injectionAck = contextInjectionAckFor({
      deliveryId,
      receipt,
      inserted,
      contextBlockHash: receivedHash,
      reason: stringOrNull(event.reason),
    });
    sessionEvent = await appendSessionEvent(stateDir, {
      type: "hook_event",
      receivedAt: new Date().toISOString(),
      hook: event.hook,
      sessionId,
      ...eventIdField(eventId),
      deliveryId,
      inserted,
      contextBlockHash: receivedHash,
      reason: stringOrNull(event.reason),
      contextInjectionAck: injectionAck,
    });

    if (!sessionEvent.deduped) {
      await appendJsonLine(join(stateDir, "events.jsonl"), {
        type: "hook_event",
        receivedAt: sessionEvent.receivedAt,
        hook: event.hook,
        sessionId,
        ...eventIdField(eventId),
        deliveryId,
        contextInjectionAck: injectionAck,
      });
    } else {
      injectionAck = sessionEvent.event.contextInjectionAck ?? injectionAck;
    }
  });

  print({
    ok: true,
    hook: event.hook,
    sessionId,
    recorded: !sessionEvent.deduped,
    deduped: sessionEvent.deduped,
    sessionEventPath: sessionEvent.path,
    deliveryId,
    contextInjectionAck: injectionAck,
  });
}

async function validationAfterRunEventHook(event) {
  const stateDir = statePath();
  const sessionId = requireString(event.sessionId, "event.sessionId");
  const commandText = requireString(event.command, "event.command");
  const exitCode = requireNumber(event.exitCode, "event.exitCode");
  const eventId = hookEventId(event);
  const failureSignals = validationFailureSignals(event, exitCode);
  let guardResult = emptyGuardResult();
  let warrantResult = null;
  let contextBlock = "";
  let promotionTrials = [];
  let sessionEvent = null;

  await withStateLock(stateDir, async () => {
    await ensureState(stateDir);
    const activePrecedents = await activePrecedentsForSessionOrAttribution(stateDir, sessionId, event.attributedPrecedents, event.deliveryId);
    const priorSessionEvents = await readSessionEvents(stateDir, sessionId);
    const candidates = await readJsonLines(join(stateDir, "candidates.jsonl"));
    const precedents = await readJsonLines(join(stateDir, "precedents.jsonl"));
    promotionTrials = promotionTrialsForValidation({
      candidates,
      precedents,
      context: contextFromSessionEvents(priorSessionEvents, event),
      sessionId,
      commandText,
      exitCode,
      stateDir,
    });
    guardResult = evaluatePrecedentGuards(activePrecedents, "validation.after_run", {
      command: commandText,
      exitCode,
      failureSignals,
    });
    warrantResult = evaluateWarrantValidation(await findWarrant(stateDir, event.warrantId), {
      command: commandText,
      exitCode,
    });
    contextBlock = formatGuardContextBlock(guardResult.failed);
    sessionEvent = await appendSessionEvent(stateDir, {
      type: "hook_event",
      receivedAt: new Date().toISOString(),
      hook: event.hook,
      sessionId,
      ...eventIdField(eventId),
      command: commandText,
      exitCode,
      durationMs: numberOrNull(event.durationMs),
      failureSignals,
      deliveryId: stringOrNull(event.deliveryId),
      warrantId: stringOrNull(event.warrantId),
      warrantResult,
      stdout: typeof event.stdout === "string" ? event.stdout : "",
      stderr: typeof event.stderr === "string" ? event.stderr : "",
      guardResult,
      promotionTrials,
      contextBlock,
    });
    if (sessionEvent.deduped) {
      promotionTrials = Array.isArray(sessionEvent.event.promotionTrials) ? sessionEvent.event.promotionTrials : promotionTrials;
    }

    if (!sessionEvent.deduped) {
      await appendJsonLine(join(stateDir, "events.jsonl"), {
        type: "hook_event",
        receivedAt: sessionEvent.receivedAt,
        hook: event.hook,
        sessionId,
        ...eventIdField(eventId),
        command: commandText,
        exitCode,
        failureSignals,
        guardResult,
        promotionTrials,
        deliveryId: stringOrNull(event.deliveryId),
        warrantId: stringOrNull(event.warrantId),
        warrantResult,
      });
    }
  });

  print({
    ok: true,
    hook: event.hook,
    sessionId,
    recorded: !sessionEvent.deduped,
    deduped: sessionEvent.deduped,
    sessionEventPath: sessionEvent.path,
    validation: {
      command: commandText,
      exitCode,
      failureSignals,
      stdoutPath: sessionEvent.event.stdoutPath ?? null,
      stderrPath: sessionEvent.event.stderrPath ?? null,
    },
    guardResult,
    warrantResult,
    promotionTrials,
    contextBlock,
  });
}

async function conversationObserveEventHook(event) {
  const stateDir = statePath();
  const sessionId = requireString(event.sessionId, "event.sessionId");
  const eventId = hookEventId(event);
  const messages = conversationMessages(event);
  const correctionSignals = conversationCorrectionSignals(messages);
  const turnDirectiveSignals = conversationTurnDirectiveSignals(messages);
  const changedFiles = Array.isArray(event.changedFiles) ? event.changedFiles : parseListArg(event.changedFiles);
  const correctionSafetyReceipt = correctionSafetyReceiptFor({
    event,
    messages,
    correctionSignals,
    changedFiles,
  });
  const turnDirectiveReceipt = turnDirectiveReceiptFor({ messages, turnDirectiveSignals });
  const acceptedCorrectionSignals = correctionSafetyReceipt.status === "accepted" ? correctionSignals : [];
  const acceptedTurnDirectives = turnDirectiveReceipt.status === "accepted" ? turnDirectiveSignals : [];
  const contextBlock = [
    formatCorrectionContextBlock(acceptedCorrectionSignals),
    formatTurnDirectiveContextBlock(directiveSummary(acceptedTurnDirectives)),
  ].filter(Boolean).join("\n");
  let sessionEvent = null;

  await withStateLock(stateDir, async () => {
    await ensureState(stateDir);
    sessionEvent = await appendSessionEvent(stateDir, {
      type: "hook_event",
      receivedAt: new Date().toISOString(),
      hook: event.hook,
      sessionId,
      ...eventIdField(eventId),
      task: typeof event.task === "string" ? event.task : null,
      scope: typeof event.scope === "string" ? event.scope : null,
      changedFiles,
      messages,
      correctionSignals,
      acceptedCorrectionSignals,
      correctionSafetyReceipt,
      turnDirectiveSignals,
      acceptedTurnDirectives,
      turnDirectiveReceipt,
      contextBlock,
    });

    if (!sessionEvent.deduped) {
      await appendJsonLine(join(stateDir, "events.jsonl"), {
        type: "hook_event",
        receivedAt: sessionEvent.receivedAt,
        hook: event.hook,
        sessionId,
        ...eventIdField(eventId),
        task: sessionEvent.event.task,
        scope: sessionEvent.event.scope,
        changedFiles: sessionEvent.event.changedFiles,
        correctionSignals: sessionEvent.event.correctionSignals,
        acceptedCorrectionSignals: sessionEvent.event.acceptedCorrectionSignals,
        correctionSafetyReceipt: sessionEvent.event.correctionSafetyReceipt,
        turnDirectiveSignals: sessionEvent.event.turnDirectiveSignals,
        acceptedTurnDirectives: sessionEvent.event.acceptedTurnDirectives,
        turnDirectiveReceipt: sessionEvent.event.turnDirectiveReceipt,
        contextBlock: sessionEvent.event.contextBlock,
      });
    }
  });

  print({
    ok: true,
    hook: event.hook,
    sessionId,
    recorded: !sessionEvent.deduped,
    deduped: sessionEvent.deduped,
    sessionEventPath: sessionEvent.path,
    observation: {
      messages: sessionEvent.event.messages,
      correctionSignals: sessionEvent.event.correctionSignals,
      acceptedCorrectionSignals: sessionEvent.event.acceptedCorrectionSignals,
      correctionSafetyReceipt: sessionEvent.event.correctionSafetyReceipt,
      turnDirectiveSignals: sessionEvent.event.turnDirectiveSignals,
      acceptedTurnDirectives: sessionEvent.event.acceptedTurnDirectives,
      turnDirectiveReceipt: sessionEvent.event.turnDirectiveReceipt,
    },
    correctionSafetyReceipt: sessionEvent.event.correctionSafetyReceipt,
    turnDirectiveReceipt: sessionEvent.event.turnDirectiveReceipt,
    turnDirectives: directiveSummary(sessionEvent.event.acceptedTurnDirectives),
    contextBlock: sessionEvent.event.contextBlock,
  });
}

async function diffAfterEditEventHook(event) {
  const stateDir = statePath();
  const sessionId = requireString(event.sessionId, "event.sessionId");
  const eventId = hookEventId(event);
  const changedFiles = diffChangedFiles(event);
  const breadthSignals = diffBreadthSignals(event, changedFiles);
  let guardResult = emptyGuardResult();
  let warrantResult = null;
  let contextBlock = "";
  let repairPrompt = null;
  let sessionEvent = null;

  await withStateLock(stateDir, async () => {
    await ensureState(stateDir);
    const activePrecedents = await activePrecedentsForSessionOrAttribution(stateDir, sessionId, event.attributedPrecedents, event.deliveryId);
    const turnDirectives = await activeTurnDirectivesForSession(stateDir, sessionId);
    guardResult = evaluatePrecedentGuards(activePrecedents, "diff.after_edit", {
      changedFiles,
      breadthSignals,
    });
    const diffEvidence = {
      changedFiles,
      linesAdded: numberOrNull(event.linesAdded),
      linesDeleted: numberOrNull(event.linesDeleted),
    };
    warrantResult = mergeWarrantResults(
      evaluateWarrantDiff(await findWarrant(stateDir, event.warrantId), diffEvidence),
      evaluateTurnDirectiveDiff(turnDirectives, diffEvidence),
    );
    repairPrompt = repairPromptForDiffGuard({
      guardResult,
      activePrecedents,
      changedFiles,
      diffSummary: event.diffSummary,
      unifiedDiff: event.unifiedDiff ?? event.diff,
    });
    contextBlock = formatRepairContextBlock(repairPrompt)
      || formatWarrantContextBlock(warrantResult)
      || formatGuardContextBlock(guardResult.failed);
    sessionEvent = await appendSessionEvent(stateDir, {
      type: "hook_event",
      receivedAt: new Date().toISOString(),
      hook: event.hook,
      sessionId,
      ...eventIdField(eventId),
      changedFiles,
      linesAdded: numberOrNull(event.linesAdded),
      linesDeleted: numberOrNull(event.linesDeleted),
      breadthSignals,
      deliveryId: stringOrNull(event.deliveryId),
      warrantId: stringOrNull(event.warrantId),
      warrantResult,
      guardResult,
      repairPrompt,
      contextBlock,
    });

    if (!sessionEvent.deduped) {
      await appendJsonLine(join(stateDir, "events.jsonl"), {
        type: "hook_event",
        receivedAt: sessionEvent.receivedAt,
        hook: event.hook,
        sessionId,
        ...eventIdField(eventId),
        changedFiles,
        breadthSignals,
        guardResult,
        repairPrompt,
        deliveryId: stringOrNull(event.deliveryId),
        warrantId: stringOrNull(event.warrantId),
        warrantResult,
      });
    }
  });

  print({
    ok: true,
    hook: event.hook,
    sessionId,
    recorded: !sessionEvent.deduped,
    deduped: sessionEvent.deduped,
    sessionEventPath: sessionEvent.path,
    diff: {
      changedFiles,
      breadthSignals,
    },
    guardResult,
    warrantResult,
    repairPrompt,
    contextBlock,
  });
}

async function finalizeBeforeResponseEventHook(event) {
  const stateDir = statePath();
  const sessionId = requireString(event.sessionId, "event.sessionId");
  const eventId = hookEventId(event);
  let finalization = null;
  let contextBlock = "";
  let sessionEvent = null;

  await withStateLock(stateDir, async () => {
    await ensureState(stateDir);
    const existing = eventId ? await findSessionEventByEventId(stateDir, sessionId, eventId) : null;

    if (existing?.event?.finalization) {
      finalization = existing.event.finalization;
      contextBlock = existing.event.contextBlock ?? "";
      sessionEvent = {
        sessionId,
        path: existing.path,
        event: existing.event,
        receivedAt: existing.event.receivedAt,
        deduped: true,
      };
      return;
    }

    const sessionEvents = await readSessionEvents(stateDir, sessionId);
    const warrant = await finalizationWarrant(stateDir, sessionEvents, event.warrantId);
    finalization = finalizeSessionDecision({
      sessionEvents,
      warrant,
    });
    contextBlock = formatFinalizeContextBlock(finalization);
    sessionEvent = await appendSessionEvent(stateDir, {
      type: "hook_event",
      receivedAt: new Date().toISOString(),
      hook: event.hook,
      sessionId,
      ...eventIdField(eventId),
      deliveryId: stringOrNull(event.deliveryId),
      warrantId: warrant?.warrantId ?? stringOrNull(event.warrantId),
      finalization,
      contextBlock,
    });

    if (!sessionEvent.deduped) {
      await appendJsonLine(join(stateDir, "events.jsonl"), {
        type: "hook_event",
        receivedAt: sessionEvent.receivedAt,
        hook: event.hook,
        sessionId,
        ...eventIdField(eventId),
        deliveryId: stringOrNull(event.deliveryId),
        warrantId: warrant?.warrantId ?? stringOrNull(event.warrantId),
        finalization,
        contextBlock,
      });
    }
  });

  print({
    schema_version: "precedent.finalize.v1",
    ok: true,
    hook: event.hook,
    sessionId,
    recorded: !sessionEvent.deduped,
    deduped: sessionEvent.deduped,
    sessionEventPath: sessionEvent.path,
    decision: finalization.decision,
    nextAction: finalization.nextAction,
    finalization,
    contextBlock,
  });
}

async function reviewAfterFeedbackEventHook(event) {
  const stateDir = statePath();
  const sessionId = requireString(event.sessionId, "event.sessionId");
  const eventId = hookEventId(event);
  const comments = reviewComments(event);
  const changedFiles = Array.isArray(event.changedFiles) ? event.changedFiles : parseListArg(event.changedFiles);
  let sessionEvent = null;

  if (comments.length === 0) {
    fail("event.comments must include at least one review comment");
  }

  await withStateLock(stateDir, async () => {
    await ensureState(stateDir);
    sessionEvent = await appendSessionEvent(stateDir, {
      type: "hook_event",
      receivedAt: new Date().toISOString(),
      hook: event.hook,
      sessionId,
      ...eventIdField(eventId),
      reviewer: typeof event.reviewer === "string" ? event.reviewer : null,
      comments,
      changedFiles,
    });

    if (!sessionEvent.deduped) {
      await appendJsonLine(join(stateDir, "events.jsonl"), {
        type: "hook_event",
        receivedAt: sessionEvent.receivedAt,
        hook: event.hook,
        sessionId,
        ...eventIdField(eventId),
        reviewer: sessionEvent.event.reviewer,
        comments,
        changedFiles,
      });
    }
  });

  print({
    ok: true,
    hook: event.hook,
    sessionId,
    recorded: !sessionEvent.deduped,
    deduped: sessionEvent.deduped,
    sessionEventPath: sessionEvent.path,
    review: {
      comments,
      changedFiles,
    },
  });
}

async function outcomeAfterTaskEventHook(event) {
  const stateDir = statePath();
  const sessionId = requireString(event.sessionId, "event.sessionId");
  const eventId = hookEventId(event);
  const success = hookBoolean(event.success, "event.success", false);
  const status = typeof event.status === "string" ? event.status : (success ? "success" : "failure");
  let activePrecedentIds = [];
  let sessionEvent = null;
  let learning = null;
  let warrantStatus = null;

  await withStateLock(stateDir, async () => {
    await ensureState(stateDir);
    activePrecedentIds = await attributedPrecedentIdsForSession(stateDir, sessionId, event.attributedPrecedents, event.deliveryId);
    warrantStatus = await warrantStatusForOutcome(stateDir, event.warrantId);
    sessionEvent = await appendSessionEvent(stateDir, {
      type: "hook_event",
      receivedAt: new Date().toISOString(),
      hook: event.hook,
      sessionId,
      ...eventIdField(eventId),
      success,
      status,
      task: typeof event.task === "string" ? event.task : null,
      scope: typeof event.scope === "string" ? event.scope : null,
      changedFiles: Array.isArray(event.changedFiles) ? event.changedFiles : parseListArg(event.changedFiles),
      retries: numberOrNull(event.retries),
      tokenEstimate: numberOrNull(event.tokenEstimate),
      notes: typeof event.notes === "string" ? event.notes : "",
      attributedPrecedents: activePrecedentIds,
      deliveryId: stringOrNull(event.deliveryId),
      warrantId: stringOrNull(event.warrantId),
      warrantStatus,
      precedent: event.precedent ?? null,
      replay: event.replay ?? null,
    });

    if (!sessionEvent.deduped) {
      await appendJsonLine(join(stateDir, "events.jsonl"), {
        type: "hook_event",
        receivedAt: sessionEvent.receivedAt,
        hook: event.hook,
        sessionId,
        ...eventIdField(eventId),
        success: sessionEvent.event.success,
        status: sessionEvent.event.status,
        task: sessionEvent.event.task,
        scope: sessionEvent.event.scope,
        changedFiles: sessionEvent.event.changedFiles,
        retries: sessionEvent.event.retries,
        tokenEstimate: sessionEvent.event.tokenEstimate,
        attributedPrecedents: activePrecedentIds,
        deliveryId: stringOrNull(event.deliveryId),
        warrantId: stringOrNull(event.warrantId),
        warrantStatus,
      });
    }

    learning = sessionEvent.deduped ? null : await createSessionLearningSnapshot(stateDir, sessionId);
    if (!sessionEvent.deduped && sessionEvent.event.success === true) {
      const promoted = await promoteSessionPairs(stateDir, {
        successSessionId: sessionId,
        requireFailureBeforeSuccess: true,
      });
      learning = {
        ...learning,
        promotionStatus: promoted.length > 0 ? "promoted" : "not_promoted",
        promoted,
        promotedIds: promoted.map((item) => item.id),
      };
    }
  });

  print({
    ok: true,
    hook: event.hook,
    sessionId,
    recorded: !sessionEvent.deduped,
    deduped: sessionEvent.deduped,
    sessionEventPath: sessionEvent.path,
    outcome: {
      success: sessionEvent.event.success,
      status: sessionEvent.event.status,
      task: sessionEvent.event.task,
      scope: sessionEvent.event.scope,
      changedFiles: sessionEvent.event.changedFiles,
      retries: sessionEvent.event.retries,
      tokenEstimate: sessionEvent.event.tokenEstimate,
      attributedPrecedents: activePrecedentIds,
      warrantStatus,
    },
    learning,
  });
}

async function orchestrationAfterIdleEventHook(event) {
  const stateDir = statePath();
  const sessionId = requireString(event.sessionId, "event.sessionId");
  const eventId = hookEventId(event);
  let sessionEvent = null;
  let idle = null;

  try {
    const locked = await withStateLock(stateDir, async () => {
      await ensureState(stateDir);
      if (eventId) {
        const existing = await findSessionEventByEventId(stateDir, sessionId, eventId);
        if (existing?.event?.hook === event.hook) {
          idle = existing.event.idle ?? null;
          sessionEvent = {
            sessionId,
            path: existing.path,
            event: existing.event,
            receivedAt: existing.event.receivedAt,
            deduped: true,
          };
        }
      }
    }, { failOpen: true });

    if (locked?.lockTimeout) {
      idle = {
        status: "unavailable",
        reason: "lock_timeout",
        promotion: null,
      };
    }

    if (!sessionEvent && idle?.status !== "unavailable") {
      const promotion = await runPendingPromotionTrials({
        stateDir,
        dryRun: hookBoolean(event.dryRun, "event.dryRun", false),
        limit: Number(event.limit ?? 3),
        leaseMs: Number(event.leaseMs ?? PROMOTION_TRIAL_LEASE_MS),
        maxAttempts: Number(event.maxAttempts ?? PROMOTION_TRIAL_MAX_ATTEMPTS),
      });
      idle = {
        status: promotion.ok ? "drained" : "failed",
        reason: promotion.ok ? null : "promotion_failed",
        promotion,
        finalization: await runIdleFinalization({
          stateDir,
          sessionId,
          eventId: eventId ? `${eventId}:finalize.before_response` : null,
          warrantId: event.warrantId,
        }),
      };

      await withStateLock(stateDir, async () => {
        await ensureState(stateDir);
        sessionEvent = await appendSessionEvent(stateDir, {
          type: "hook_event",
          receivedAt: new Date().toISOString(),
          hook: event.hook,
          sessionId,
          ...eventIdField(eventId),
          idle,
        });

        if (!sessionEvent.deduped) {
          await appendJsonLine(join(stateDir, "events.jsonl"), {
            type: "hook_event",
            receivedAt: sessionEvent.receivedAt,
            hook: event.hook,
            sessionId,
            ...eventIdField(eventId),
            idle: idleSummary(idle),
          });
        }
      }, { failOpen: true });
    }
  } catch (error) {
    idle = {
      status: "unavailable",
      reason: "idle_orchestration_unavailable",
      message: error.message,
      promotion: null,
    };
  }

  print({
    schema_version: "precedent.orchestration.v1",
    ok: true,
    hook: event.hook,
    sessionId,
    recorded: Boolean(sessionEvent) && !sessionEvent.deduped,
    deduped: Boolean(sessionEvent?.deduped),
    sessionEventPath: sessionEvent?.path ?? null,
    idle,
  });
}

async function repairBeforeRetryEventHook(event) {
  const stateDir = statePath();
  const sessionId = requireString(event.sessionId, "event.sessionId");
  const eventId = hookEventId(event);
  let repairBlock = "";
  let repairSource = null;
  let suppressedRepairs = [];
  let sessionEvent = null;

  try {
    const locked = await withStateLock(stateDir, async () => {
      await ensureState(stateDir);
      if (eventId) {
        const existing = await findSessionEventByEventId(stateDir, sessionId, eventId);
        if (existing?.event?.hook === event.hook) {
          repairBlock = existing.event.repairBlock ?? "";
          repairSource = existing.event.repairSource ?? null;
          suppressedRepairs = existing.event.suppressedRepairs ?? [];
          sessionEvent = {
            sessionId,
            path: existing.path,
            event: existing.event,
            receivedAt: existing.event.receivedAt,
            deduped: true,
          };
          return;
        }
      }

      const events = await readSessionEvents(stateDir, sessionId);
      const allEvents = await readJsonLines(join(stateDir, "events.jsonl"));
      const candidate = latestRepairCandidate(events);
      if (!candidate) {
        suppressedRepairs = [{ reason: events.length === 0 ? "empty_session" : "no_repair_candidate" }];
        return;
      }

      suppressedRepairs = repairSuppressionReasonsForCandidate(allEvents, candidate);
      if (suppressedRepairs.length > 0) {
        await appendJsonLine(join(stateDir, "events.jsonl"), {
          type: "hook_event",
          receivedAt: new Date().toISOString(),
          hook: event.hook,
          sessionId,
          suppressedRepairs,
          attributedPrecedents: candidate.attributedPrecedents,
        });
        return;
      }

      repairBlock = candidate.repairBlock;
      repairSource = candidate.repairSource;
      const repairId = repairIdForCandidate(sessionId, candidate);
      sessionEvent = await appendSessionEvent(stateDir, {
        type: "hook_event",
        receivedAt: new Date().toISOString(),
        hook: event.hook,
        sessionId,
        ...eventIdField(eventId),
        nextSessionId: typeof event.nextSessionId === "string" ? event.nextSessionId : null,
        repairId,
        repairBlock,
        repairSource,
        suppressedRepairs,
        attributedPrecedents: candidate.attributedPrecedents,
      });

      if (!sessionEvent.deduped) {
        await appendJsonLine(join(stateDir, "events.jsonl"), {
          type: "hook_event",
          receivedAt: sessionEvent.receivedAt,
          hook: event.hook,
          sessionId,
          ...eventIdField(eventId),
          nextSessionId: sessionEvent.event.nextSessionId,
          repairId: sessionEvent.event.repairId,
          repairSource,
          attributedPrecedents: candidate.attributedPrecedents,
        });
      }
    }, { failOpen: true });

    if (locked?.lockTimeout) {
      repairBlock = "";
      repairSource = null;
      suppressedRepairs = [{ reason: "lock_timeout" }];
    }
  } catch (error) {
    repairBlock = "";
    repairSource = null;
    suppressedRepairs = [{ reason: "repair_unavailable", message: error.message }];
  }

  print({
    schema_version: "precedent.repair.v1",
    ok: true,
    hook: event.hook,
    sessionId,
    recorded: Boolean(sessionEvent) && !sessionEvent.deduped,
    deduped: Boolean(sessionEvent?.deduped),
    sessionEventPath: sessionEvent?.path ?? null,
    repairId: sessionEvent?.event?.repairId ?? null,
    repairBlock: sessionEvent?.event?.repairBlock ?? repairBlock,
    repairSource,
    suppressedRepairs,
  });
}

async function repairAfterRetryEventHook(event) {
  const stateDir = statePath();
  const sessionId = requireString(event.sessionId, "event.sessionId");
  const eventId = hookEventId(event);
  const repairId = typeof event.repairId === "string" ? event.repairId.trim() : "";
  const retryStartedAt = nonEmptyString(event.retryStartedAt) ? event.retryStartedAt.trim() : null;
  const retryStartedAtMs = Date.parse(retryStartedAt ?? "");
  let repairReceipt = null;
  let suppressedRepairs = [];
  let sessionEvent = null;

  try {
    const locked = await withStateLock(stateDir, async () => {
      await ensureState(stateDir);
      if (!repairId) {
        suppressedRepairs = [{ reason: "missing_repair_id" }];
        repairReceipt = {
          id: null,
          repairSessionId: typeof event.repairSessionId === "string" ? event.repairSessionId : null,
          retrySessionId: sessionId,
          status: "unresolved",
          cleared: false,
          repairResolved: false,
          failureSource: null,
        };
      } else {
        const repairSessionId = typeof event.repairSessionId === "string" ? event.repairSessionId : null;
        const repairEvent = await findRepairBeforeRetryEvent(stateDir, repairId, repairSessionId);
        if (!repairEvent) {
          suppressedRepairs = [{ reason: "unknown_repair_id" }];
          repairReceipt = {
            id: repairId,
            repairSessionId,
            retrySessionId: sessionId,
            status: "unresolved",
            cleared: false,
            repairResolved: false,
            failureSource: null,
          };
        } else {
          const retryEvents = (await readSessionEvents(stateDir, sessionId))
            .filter((item) => !Number.isFinite(retryStartedAtMs) || eventTime(item) >= retryStartedAtMs);
          if (!hasRepairRetryEvidence(retryEvents)) {
            suppressedRepairs = [{ reason: "missing_retry_evidence" }];
            repairReceipt = {
              id: repairId,
              repairSessionId: repairEvent.sessionId ?? repairSessionId,
              retrySessionId: sessionId,
              status: "unresolved",
              cleared: false,
              repairResolved: false,
              failureSource: null,
            };
          } else {
            const retryCandidate = latestRepairCandidate(retryEvents);
            const cleared = retryCandidate === null;
            repairReceipt = {
              id: repairId,
              repairSessionId: repairEvent.sessionId ?? repairSessionId,
              retrySessionId: sessionId,
              status: cleared ? "cleared" : "still_failing",
              cleared,
              repairResolved: true,
              failureSource: retryCandidate?.repairSource ?? null,
            };
          }
        }
      }

      const repairEvent = repairReceipt.repairResolved
        ? await findRepairBeforeRetryEvent(stateDir, repairId, repairReceipt.repairSessionId)
        : null;
      const attributedPrecedents = uniqueStrings([
        ...parseListArg(event.attributedPrecedents),
        ...(Array.isArray(repairEvent?.attributedPrecedents) ? repairEvent.attributedPrecedents : []),
      ]);
      sessionEvent = await appendSessionEvent(stateDir, {
        type: "hook_event",
        receivedAt: new Date().toISOString(),
        hook: event.hook,
        sessionId,
        ...eventIdField(eventId),
        repairId: repairReceipt.id,
        repairSessionId: repairReceipt.repairSessionId,
        retryStartedAt,
        repairReceipt,
        suppressedRepairs,
        attributedPrecedents,
      });

      if (!sessionEvent.deduped) {
        await appendJsonLine(join(stateDir, "events.jsonl"), {
          type: "hook_event",
          receivedAt: sessionEvent.receivedAt,
          hook: event.hook,
          sessionId,
          ...eventIdField(eventId),
          repairId: repairReceipt.id,
          repairSessionId: repairReceipt.repairSessionId,
          retryStartedAt,
          repairReceipt,
          suppressedRepairs,
          attributedPrecedents,
        });
      }
    }, { failOpen: true });

    if (locked?.lockTimeout) {
      suppressedRepairs = [{ reason: "lock_timeout" }];
    }
  } catch (error) {
    repairReceipt = null;
    suppressedRepairs = [{ reason: "repair_receipt_unavailable", message: error.message }];
  }

  print({
    schema_version: "precedent.repair_receipt.v1",
    ok: true,
    hook: event.hook,
    sessionId,
    recorded: Boolean(sessionEvent) && !sessionEvent.deduped,
    deduped: Boolean(sessionEvent?.deduped),
    sessionEventPath: sessionEvent?.path ?? null,
    repairReceipt,
    suppressedRepairs,
  });
}

async function runValidationCommand() {
  const sessionId = requireString(args.session, "run.session");

  if (runSeparatorIndex < 0 || runCommandArgs.length === 0) {
    fail("run requires --session <id> -- <command>");
  }

  const stateDir = statePath();
  const startedAt = Date.now();
  const result = await spawnPassthrough(runCommandArgs);
  const durationMs = Date.now() - startedAt;
  const commandText = redactSecrets(shellQuoteCommand(runCommandArgs)).value;
  const failureSignals = validationFailureSignals({
    stderr: result.stderr,
  }, result.exitCode);
  await withStateLock(stateDir, async () => {
    await ensureState(stateDir);
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
  });

  process.exit(result.exitCode);
}

async function printManifest() {
  const runtime = args.runtime ?? "generic";

  if (!["generic", "codex"].includes(runtime)) {
    fail(`unsupported runtime: ${runtime}`);
  }

  print(buildManifest(runtime, args["state-dir"] ?? runtimeConfig.stateDir));
}

function buildManifest(runtime, stateDir) {
  const hookCommand = ["node", "precedent/bin/precedent.mjs", "hook", "--state-dir", stateDir, "--json"];
  const promotionTrialCommand = [
    "node",
    "precedent/bin/precedent.mjs",
    "promotion-trial",
    "--state-dir",
    stateDir,
    "--candidate",
    "$CANDIDATE_ID",
    "--baseline-command",
    "$BASELINE_COMMAND",
    "--trace-out",
    "$TRACE_OUT",
    "--json",
  ];
  const promotionPendingCommand = [
    "node",
    "precedent/bin/precedent.mjs",
    "promote-pending",
    "--state-dir",
    stateDir,
    "--json",
  ];
  const warrantCommand = [
    "node",
    "precedent/bin/precedent.mjs",
    "warrant",
    "--state-dir",
    stateDir,
    "--session",
    "$SESSION_ID",
    "--event-id",
    "$EVENT_ID",
    "--delivery-id",
    "$DELIVERY_ID",
    "--task-file",
    "$TASK_FILE",
    "--scope",
    "$SCOPE",
    "--changed-files",
    "$CHANGED_FILES",
    "--json",
  ];
  const timeoutMs = runtimeConfig.hookTimeoutMs;
  const failurePolicy = runtimeConfig.failurePolicy;

  return {
    schema_version: "precedent.manifest.v1",
    runtime,
    stateDir,
    configPath: runtimeConfigPath,
    configHash: runtimeConfigHash,
    defaults: {
      maxInjections: runtimeConfig.maxInjections,
      hookTimeoutMs: runtimeConfig.hookTimeoutMs,
      failurePolicy: runtimeConfig.failurePolicy,
      retentionDays: runtimeConfig.retentionDays,
      redaction: runtimeConfig.redaction,
      enabledHooks: runtimeConfig.enabledHooks,
    },
    requiredEnv: [],
    identity: runtimeIdentityContract(),
    transports: {
      loop: {
        command: [
          "node",
          "precedent/bin/precedent.mjs",
          "loop",
          "--state-dir",
          stateDir,
          "--json",
        ],
        stdin: "jsonl",
        stdout: "jsonl",
        eventSchema: SCHEMA_VERSION,
        failurePolicy,
      },
    },
    hooks: {
      "context.before_turn": {
        command: [
          "node",
          "precedent/bin/precedent.mjs",
          "context",
          "--state-dir",
          stateDir,
          "--task-file",
          "$TASK_FILE",
          "--scope",
          "$SCOPE",
          "--changed-files",
          "$CHANGED_FILES",
          "--session",
          "$SESSION_ID",
          "--event-id",
          "$EVENT_ID",
          "--format",
          "json",
        ],
        output: ["schema_version", "contextBlock", "contextBlockHash", "injections", "suppressedInjections", "revisionBriefs", "promotionTrials", "candidateHints", "turnDirectives", "deliveryReceipt", "source", "recorded", "deduped", "sessionEventPath"],
        injectFrom: "contextBlock",
        timeoutMs,
        failurePolicy,
      },
      "context.after_inject": {
        command: hookCommand,
        stdin: ["schema_version", "hook", "sessionId", "eventId", "deliveryId", "contextBlockHash", "inserted", "reason"],
        output: ["ok", "hook", "sessionId", "recorded", "deduped", "sessionEventPath", "deliveryId", "contextInjectionAck"],
        timeoutMs,
        failurePolicy,
      },
      "conversation.observe": {
        command: hookCommand,
        stdin: ["schema_version", "hook", "sessionId", "eventId", "task", "scope", "changedFiles", "messages", "message"],
        output: ["ok", "hook", "sessionId", "recorded", "deduped", "sessionEventPath", "observation", "correctionSafetyReceipt", "turnDirectiveReceipt", "turnDirectives", "contextBlock"],
        injectFrom: "contextBlock",
        timeoutMs,
        failurePolicy,
      },
      "validation.after_run": {
        command: hookCommand,
        stdin: ["schema_version", "hook", "sessionId", "eventId", "deliveryId", "warrantId", "command", "exitCode", "durationMs", "stdout", "stderr", "failureSignals", "attributedPrecedents"],
        output: ["ok", "hook", "sessionId", "recorded", "deduped", "sessionEventPath", "validation", "guardResult", "warrantResult", "promotionTrials", "contextBlock"],
        timeoutMs,
        failurePolicy,
      },
      "diff.after_edit": {
        command: hookCommand,
        stdin: ["schema_version", "hook", "sessionId", "eventId", "deliveryId", "warrantId", "changedFiles", "linesAdded", "linesDeleted", "breadthSignals", "diffSummary", "unifiedDiff", "attributedPrecedents"],
        output: ["ok", "hook", "sessionId", "recorded", "deduped", "sessionEventPath", "diff", "guardResult", "warrantResult", "repairPrompt", "contextBlock"],
        timeoutMs,
        failurePolicy,
      },
      "review.after_feedback": {
        command: hookCommand,
        stdin: ["schema_version", "hook", "sessionId", "eventId", "comments", "changedFiles", "reviewer"],
        output: ["ok", "hook", "sessionId", "recorded", "deduped", "sessionEventPath", "review"],
        timeoutMs,
        failurePolicy,
      },
      "finalize.before_response": {
        command: hookCommand,
        stdin: ["schema_version", "hook", "sessionId", "eventId", "deliveryId", "warrantId", "attributedPrecedents"],
        output: ["schema_version", "ok", "hook", "sessionId", "recorded", "deduped", "sessionEventPath", "decision", "nextAction", "finalization", "contextBlock"],
        injectFrom: "contextBlock",
        timeoutMs,
        failurePolicy,
      },
      "outcome.after_task": {
        command: hookCommand,
        stdin: ["schema_version", "hook", "sessionId", "eventId", "deliveryId", "warrantId", "success", "status", "task", "scope", "changedFiles", "retries", "tokenEstimate", "notes", "attributedPrecedents", "precedent", "replay"],
        output: ["ok", "hook", "sessionId", "recorded", "deduped", "sessionEventPath", "outcome"],
        timeoutMs,
        failurePolicy,
      },
      "orchestration.after_idle": {
        command: hookCommand,
        stdin: ["schema_version", "hook", "sessionId", "eventId", "limit", "dryRun"],
        output: ["schema_version", "ok", "hook", "sessionId", "recorded", "deduped", "sessionEventPath", "idle"],
        timeoutMs,
        failurePolicy,
      },
      "repair.before_retry": {
        command: hookCommand,
        stdin: ["schema_version", "hook", "sessionId", "eventId", "nextSessionId", "task", "finalMessage", "scope", "changedFiles", "retry", "attributedPrecedents"],
        output: ["schema_version", "ok", "hook", "sessionId", "recorded", "deduped", "sessionEventPath", "repairId", "repairBlock", "repairSource", "suppressedRepairs"],
        injectFrom: "repairBlock",
        timeoutMs,
        failurePolicy,
      },
      "repair.after_retry": {
        command: hookCommand,
        stdin: ["schema_version", "hook", "sessionId", "eventId", "repairId", "repairSessionId", "retryStartedAt", "attributedPrecedents"],
        output: ["schema_version", "ok", "hook", "sessionId", "recorded", "deduped", "sessionEventPath", "repairReceipt", "suppressedRepairs"],
        timeoutMs,
        failurePolicy,
      },
    },
    actions: {
      "warrant.issue": {
        command: warrantCommand,
        stdin: [],
        output: ["schema_version", "ok", "warrantId", "sessionId", "eventId", "allowed", "requiredEvidence", "forbidden", "sources", "status", "recorded", "deduped", "sessionEventPath"],
        timeoutMs,
        failurePolicy,
      },
      "promotion.trial": {
        command: promotionTrialCommand,
        stdin: [],
        output: ["ok", "candidateId", "replay", "replayPath", "tracePath", "observed", "promoted", "rejected", "replayAudit"],
        timeoutMs,
        failurePolicy,
      },
      "promotion.pending": {
        command: promotionPendingCommand,
        stdin: [],
        output: ["ok", "schema_version", "dryRun", "processed", "results", "queue"],
        timeoutMs,
        failurePolicy,
      },
    },
  };
}

async function attachRuntime() {
  const runtime = args.runtime ?? "generic";

  if (!["generic", "codex"].includes(runtime)) {
    fail(`unsupported runtime: ${runtime}`);
  }

  const stateDir = statePath();
  const stateDirArg = args["state-dir"] ?? runtimeConfig.stateDir;
  const taskSource = await readAttachTaskSource();
  const scope = args.scope ?? "";
  const changedFiles = parseListArg(args["changed-files"]);
  const sessionIdentity = runtimeSessionIdentity({
    runtime,
    taskSource,
    scope,
    changedFiles,
  });
  const sessionId = sessionIdentity.sessionId;
  const beforeTurnCommand = [
    "node",
    "precedent/bin/precedent.mjs",
    "context",
    "--state-dir",
    stateDirArg,
    ...(taskSource.taskFile ? ["--task-file", taskSource.taskFile] : ["--task", taskSource.task]),
    ...(scope ? ["--scope", scope] : []),
    ...(changedFiles.length > 0 ? ["--changed-files", changedFiles.join(",")] : []),
    "--session",
    sessionId,
    "--event-id",
    "$EVENT_ID",
    "--format",
    "json",
    "--json",
  ];
  const hookCommand = [
    "node",
    "precedent/bin/precedent.mjs",
    "hook",
    "--state-dir",
    stateDirArg,
    "--json",
  ];
  const warrantCommand = [
    "node",
    "precedent/bin/precedent.mjs",
    "warrant",
    "--state-dir",
    stateDirArg,
    "--session",
    sessionId,
    "--event-id",
    "$EVENT_ID",
    "--delivery-id",
    "$DELIVERY_ID",
    ...(taskSource.taskFile ? ["--task-file", taskSource.taskFile] : ["--task", taskSource.task]),
    ...(scope ? ["--scope", scope] : []),
    ...(changedFiles.length > 0 ? ["--changed-files", changedFiles.join(",")] : []),
    "--json",
  ];
  const promotionTrialCommand = [
    "node",
    "precedent/bin/precedent.mjs",
    "promotion-trial",
    "--state-dir",
    stateDirArg,
    "--candidate",
    "$CANDIDATE_ID",
    "--baseline-command",
    "$BASELINE_COMMAND",
    "--trace-out",
    "$TRACE_OUT",
    "--json",
  ];
  const promotionPendingCommand = [
    "node",
    "precedent/bin/precedent.mjs",
    "promote-pending",
    "--state-dir",
    stateDirArg,
    "--json",
  ];

  await withStateLock(stateDir, async () => {
    await ensureState(stateDir);
    await appendJsonLine(join(stateDir, "events.jsonl"), {
      type: "runtime_attach",
      observedAt: new Date().toISOString(),
      runtime,
      sessionId,
      identity: sessionIdentity,
      task: taskSource.task,
      taskFile: taskSource.taskFile,
      scope: scope || null,
      changedFiles,
    });
  });

  print({
    schema_version: ADAPTER_SCHEMA_VERSION,
    runtime,
    stateDir: stateDirArg,
    sessionId,
    identity: sessionIdentity,
    task: taskSource.task,
    taskFile: taskSource.taskFile,
    scope: scope || null,
    changedFiles,
    hookTimeoutMs: runtimeConfig.hookTimeoutMs,
    failurePolicy: runtimeConfig.failurePolicy,
    adapter: {
      lifecycle: [
        {
          phase: "conversationObserve",
          hook: "conversation.observe",
          required: false,
          injectFrom: "contextBlock",
          eventId: "$EVENT_ID",
        },
        {
          phase: "beforeTurn",
          hook: "context.before_turn",
          required: true,
          injectFrom: "contextBlock",
          eventId: "$EVENT_ID",
        },
        {
          phase: "afterInject",
          hook: "context.after_inject",
          required: false,
          eventId: "$EVENT_ID",
        },
        {
          phase: "beforeEdit",
          action: "warrant.issue",
          required: false,
          eventId: "$EVENT_ID",
        },
        {
          phase: "afterValidation",
          hook: "validation.after_run",
          required: false,
          eventId: "$EVENT_ID",
        },
        {
          phase: "afterDiff",
          hook: "diff.after_edit",
          required: false,
          eventId: "$EVENT_ID",
        },
        {
          phase: "afterReview",
          hook: "review.after_feedback",
          required: false,
          eventId: "$EVENT_ID",
        },
        {
          phase: "beforeRetry",
          hook: "repair.before_retry",
          required: false,
          injectFrom: "repairBlock",
          eventId: "$EVENT_ID",
        },
        {
          phase: "afterRetry",
          hook: "repair.after_retry",
          required: false,
          eventId: "$EVENT_ID",
        },
        {
          phase: "beforeResponse",
          hook: "finalize.before_response",
          required: true,
          injectFrom: "contextBlock",
          eventId: "$EVENT_ID",
        },
        {
          phase: "afterOutcome",
          hook: "outcome.after_task",
          required: true,
          eventId: "$EVENT_ID",
        },
        {
          phase: "afterIdle",
          hook: "orchestration.after_idle",
          required: false,
          eventId: "$EVENT_ID",
        },
      ],
      beforeTurn: {
        command: beforeTurnCommand,
        eventId: "$EVENT_ID",
        output: ["schema_version", "contextBlock", "contextBlockHash", "injections", "suppressedInjections", "revisionBriefs", "promotionTrials", "candidateHints", "turnDirectives", "deliveryReceipt", "source", "recorded", "deduped", "sessionEventPath"],
        injectFrom: "contextBlock",
        timeoutMs: runtimeConfig.hookTimeoutMs,
        failurePolicy: runtimeConfig.failurePolicy,
      },
      afterInject: {
        command: hookCommand,
        output: ["ok", "hook", "sessionId", "recorded", "deduped", "sessionEventPath", "deliveryId", "contextInjectionAck"],
        stdin: {
          schema_version: SCHEMA_VERSION,
          hook: "context.after_inject",
          sessionId,
          eventId: "$EVENT_ID",
          deliveryId: "$DELIVERY_ID",
          contextBlockHash: "$CONTEXT_BLOCK_HASH",
          inserted: "$INSERTED",
          reason: "$REASON",
        },
        timeoutMs: runtimeConfig.hookTimeoutMs,
        failurePolicy: runtimeConfig.failurePolicy,
      },
      conversationObserve: {
        command: hookCommand,
        output: ["ok", "hook", "sessionId", "recorded", "deduped", "sessionEventPath", "observation", "correctionSafetyReceipt", "turnDirectiveReceipt", "turnDirectives", "contextBlock"],
        injectFrom: "contextBlock",
        stdin: {
          schema_version: SCHEMA_VERSION,
          hook: "conversation.observe",
          sessionId,
          eventId: "$EVENT_ID",
          task: taskSource.task,
          scope: scope || null,
          changedFiles,
          messages: "$MESSAGES",
          message: "$MESSAGE",
        },
        timeoutMs: runtimeConfig.hookTimeoutMs,
        failurePolicy: runtimeConfig.failurePolicy,
      },
      warrant: {
        command: warrantCommand,
        eventId: "$EVENT_ID",
        output: ["schema_version", "ok", "warrantId", "allowed", "requiredEvidence", "forbidden", "sources", "status", "recorded", "deduped", "sessionEventPath"],
        timeoutMs: runtimeConfig.hookTimeoutMs,
        failurePolicy: runtimeConfig.failurePolicy,
      },
      afterValidation: {
        command: hookCommand,
        output: ["ok", "hook", "sessionId", "recorded", "deduped", "sessionEventPath", "validation", "guardResult", "warrantResult", "promotionTrials", "contextBlock"],
        stdin: {
          schema_version: SCHEMA_VERSION,
          hook: "validation.after_run",
          sessionId,
          eventId: "$EVENT_ID",
          deliveryId: "$DELIVERY_ID",
          warrantId: "$WARRANT_ID",
          command: "$COMMAND",
          exitCode: "$EXIT_CODE",
          durationMs: "$DURATION_MS",
          stdout: "$STDOUT",
          stderr: "$STDERR",
          attributedPrecedents: "$ATTRIBUTED_PRECEDENTS",
        },
        timeoutMs: runtimeConfig.hookTimeoutMs,
        failurePolicy: runtimeConfig.failurePolicy,
      },
      afterDiff: {
        command: hookCommand,
        stdin: {
          schema_version: SCHEMA_VERSION,
          hook: "diff.after_edit",
          sessionId,
          eventId: "$EVENT_ID",
          deliveryId: "$DELIVERY_ID",
          warrantId: "$WARRANT_ID",
          changedFiles: "$CHANGED_FILES",
          linesAdded: "$LINES_ADDED",
          linesDeleted: "$LINES_DELETED",
          diffSummary: "$DIFF_SUMMARY",
          unifiedDiff: "$UNIFIED_DIFF",
          attributedPrecedents: "$ATTRIBUTED_PRECEDENTS",
        },
        timeoutMs: runtimeConfig.hookTimeoutMs,
        failurePolicy: runtimeConfig.failurePolicy,
      },
      afterReview: {
        command: hookCommand,
        stdin: {
          schema_version: SCHEMA_VERSION,
          hook: "review.after_feedback",
          sessionId,
          eventId: "$EVENT_ID",
          comments: "$COMMENTS",
          changedFiles: "$CHANGED_FILES",
          reviewer: "$REVIEWER",
        },
        timeoutMs: runtimeConfig.hookTimeoutMs,
        failurePolicy: runtimeConfig.failurePolicy,
      },
      beforeResponse: {
        command: hookCommand,
        stdin: {
          schema_version: SCHEMA_VERSION,
          hook: "finalize.before_response",
          sessionId,
          eventId: "$EVENT_ID",
          deliveryId: "$DELIVERY_ID",
          warrantId: "$WARRANT_ID",
          attributedPrecedents: "$ATTRIBUTED_PRECEDENTS",
        },
        output: ["schema_version", "ok", "hook", "sessionId", "recorded", "deduped", "sessionEventPath", "decision", "nextAction", "finalization", "contextBlock"],
        injectFrom: "contextBlock",
        timeoutMs: runtimeConfig.hookTimeoutMs,
        failurePolicy: runtimeConfig.failurePolicy,
      },
      afterOutcome: {
        command: hookCommand,
        stdin: {
          schema_version: SCHEMA_VERSION,
          hook: "outcome.after_task",
          sessionId,
          eventId: "$EVENT_ID",
          deliveryId: "$DELIVERY_ID",
          warrantId: "$WARRANT_ID",
          success: "$SUCCESS",
          status: "$STATUS",
          task: taskSource.task,
          scope: scope || null,
          changedFiles,
          retries: "$RETRIES",
          tokenEstimate: "$TOKEN_ESTIMATE",
          notes: "$NOTES",
          attributedPrecedents: "$ATTRIBUTED_PRECEDENTS",
        },
        timeoutMs: runtimeConfig.hookTimeoutMs,
        failurePolicy: runtimeConfig.failurePolicy,
      },
      afterIdle: {
        command: hookCommand,
        stdin: {
          schema_version: SCHEMA_VERSION,
          hook: "orchestration.after_idle",
          sessionId,
          eventId: "$EVENT_ID",
          limit: "$LIMIT",
          dryRun: "$DRY_RUN",
        },
        output: ["schema_version", "ok", "hook", "sessionId", "recorded", "deduped", "sessionEventPath", "idle"],
        timeoutMs: runtimeConfig.hookTimeoutMs,
        failurePolicy: runtimeConfig.failurePolicy,
      },
      beforeRetry: {
        command: hookCommand,
        stdin: {
          schema_version: SCHEMA_VERSION,
          hook: "repair.before_retry",
          sessionId,
          eventId: "$EVENT_ID",
          nextSessionId: "$NEXT_SESSION_ID",
          task: taskSource.task,
          finalMessage: "$FINAL_MESSAGE",
          scope: scope || null,
          changedFiles,
          retry: "$RETRY",
          attributedPrecedents: "$ATTRIBUTED_PRECEDENTS",
        },
        output: ["schema_version", "ok", "hook", "sessionId", "recorded", "deduped", "sessionEventPath", "repairId", "repairBlock", "repairSource", "suppressedRepairs"],
        injectFrom: "repairBlock",
        timeoutMs: runtimeConfig.hookTimeoutMs,
        failurePolicy: runtimeConfig.failurePolicy,
      },
      afterRetry: {
        command: hookCommand,
        stdin: {
          schema_version: SCHEMA_VERSION,
          hook: "repair.after_retry",
          sessionId,
          eventId: "$EVENT_ID",
          repairId: "$REPAIR_ID",
          repairSessionId: "$REPAIR_SESSION_ID",
          retryStartedAt: "$RETRY_STARTED_AT",
          attributedPrecedents: "$ATTRIBUTED_PRECEDENTS",
        },
        output: ["schema_version", "ok", "hook", "sessionId", "recorded", "deduped", "sessionEventPath", "repairReceipt", "suppressedRepairs"],
        timeoutMs: runtimeConfig.hookTimeoutMs,
        failurePolicy: runtimeConfig.failurePolicy,
      },
      promotionTrial: {
        command: promotionTrialCommand,
        output: ["ok", "candidateId", "replay", "replayPath", "tracePath", "observed", "promoted", "rejected", "replayAudit"],
        timeoutMs: runtimeConfig.hookTimeoutMs,
        failurePolicy: runtimeConfig.failurePolicy,
      },
      promotionPending: {
        command: promotionPendingCommand,
        output: ["ok", "schema_version", "dryRun", "processed", "results", "queue"],
        timeoutMs: runtimeConfig.hookTimeoutMs,
        failurePolicy: runtimeConfig.failurePolicy,
      },
    },
  });
}

async function attachRunSession() {
  const stateDirArg = args["state-dir"] ?? runtimeConfig.stateDir;
  const runtime = args.runtime ?? "generic";
  const taskSource = await readAttachTaskSource();
  const scope = args.scope ?? "";
  const changedFiles = parseListArg(args["changed-files"]);
  const sessionIdentity = runtimeSessionIdentity({
    runtime,
    taskSource,
    scope,
    changedFiles,
  });
  const sessionId = sessionIdentity.sessionId;
  const validationCommand = requireString(args["validation-command"], "attach-run --validation-command");
  const eventPrefix = typeof args["event-prefix"] === "string" && args["event-prefix"].trim().length > 0
    ? args["event-prefix"].trim()
    : null;
  const retryRepairId = typeof args["repair-id"] === "string" && args["repair-id"].trim().length > 0
    ? args["repair-id"].trim()
    : null;
  const retryRepairSessionId = repairSessionArg();
  if (retryRepairId && !retryRepairSessionId) {
    fail("attach-run --repair-id requires --repair-session-id");
  }
  if (!retryRepairId && retryRepairSessionId) {
    fail("attach-run --repair-session-id requires --repair-id");
  }
  const retryRepairTarget = retryRepairId
    ? {
      source: "explicit",
      repairId: retryRepairId,
      repairSessionId: retryRepairSessionId,
    }
    : await attachPendingRepairTarget({
      stateDirArg,
      sessionId,
      eventId: eventPrefix ? `${eventPrefix}:repair.after_retry` : null,
    });
  const retryStartedAt = new Date().toISOString();

  const beforeTurn = await runPrecedentChildJson([
    "context",
    "--state-dir",
    stateDirArg,
    ...(taskSource.taskFile ? ["--task-file", taskSource.taskFile] : ["--task", taskSource.task]),
    ...(scope ? ["--scope", scope] : []),
    ...(changedFiles.length > 0 ? ["--changed-files", changedFiles.join(",")] : []),
    "--session",
    sessionId,
    ...(eventPrefix ? ["--event-id", `${eventPrefix}:context.before_turn`] : []),
    "--format",
    "json",
    "--json",
  ]);
  const injectionAck = await runAttachInjectionAck({
    stateDirArg,
    sessionId,
    eventId: eventPrefix ? `${eventPrefix}:context.after_inject` : null,
    deliveryReceipt: beforeTurn.deliveryReceipt,
    contextBlockHash: beforeTurn.contextBlockHash,
    inserted: beforeTurn.contextBlock ? true : false,
  });
  const attributedPrecedents = beforeTurn.injections.map((injection) => injection.id);
  const warrant = await runPrecedentChildJson([
    "warrant",
    "--state-dir",
    stateDirArg,
    "--session",
    sessionId,
    "--event-id",
    eventPrefix ? `${eventPrefix}:warrant.issue` : `warrant-${Date.now()}-${stableHash({ sessionId, task: taskSource.task, scope, changedFiles }).slice(0, 12)}`,
    ...(beforeTurn.deliveryReceipt?.deliveryId ? ["--delivery-id", beforeTurn.deliveryReceipt.deliveryId] : []),
    ...(taskSource.taskFile ? ["--task-file", taskSource.taskFile] : ["--task", taskSource.task]),
    ...(scope ? ["--scope", scope] : []),
    ...(changedFiles.length > 0 ? ["--changed-files", changedFiles.join(",")] : []),
    "--json",
  ]);
  const warrantId = warrant.warrantId ?? null;
  const deliveryId = warrant.deliveryReceipt?.deliveryId ?? beforeTurn.deliveryReceipt?.deliveryId ?? null;
  const validation = await runAttachValidation({
    stateDirArg,
    sessionId,
    eventId: eventPrefix ? `${eventPrefix}:validation.after_run` : null,
    deliveryId,
    warrantId,
    command: redactSecrets(validationCommand).value,
    attributedPrecedents,
  });
  const diff = await runAttachDiff({
    stateDirArg,
    sessionId,
    eventId: eventPrefix ? `${eventPrefix}:diff.after_edit` : null,
    deliveryId,
    warrantId,
    changedFiles: parseListArg(args["diff-changed-files"]),
    diffSummary: args["diff-summary"],
    unifiedDiff: args["unified-diff"],
    attributedPrecedents,
  });
  const initialFinalization = await runAttachFinalization({
    stateDirArg,
    sessionId,
    eventId: eventPrefix ? `${eventPrefix}:finalize.before_response` : null,
    deliveryId,
    warrantId,
    attributedPrecedents,
  });
  const selfHealing = await runAttachSelfHealing({
    stateDirArg,
    sessionId,
    eventPrefix,
    deliveryId,
    warrantId,
    attributedPrecedents,
    finalization: initialFinalization,
  });
  const finalization = selfHealing.finalization ?? initialFinalization;
  const selfRepair = await runAttachRepairHandoff({
    stateDirArg,
    sessionId,
    eventId: eventPrefix ? `${eventPrefix}:repair.before_retry` : null,
    task: taskSource.task,
    scope,
    changedFiles,
    attributedPrecedents,
    finalization,
  });
  const validationResults = [
    validation.validation,
    ...selfHealing.validations.map((item) => item.validation),
  ];
  const success = args.success === undefined
    ? validationResults.every((item) => item.exitCode === 0) && finalization.decision === "ready"
    : hookBoolean(args.success, "attach-run.success", false);
  const outcome = await runPrecedentChildJson([
    "hook",
    "--state-dir",
    stateDirArg,
    "--json",
  ], {
    schema_version: SCHEMA_VERSION,
    hook: "outcome.after_task",
    sessionId,
    ...eventIdField(eventPrefix ? `${eventPrefix}:outcome.after_task` : null),
    deliveryId,
    warrantId,
    success,
    status: args.status ?? (success ? "success" : "failure"),
    task: taskSource.task,
    scope: scope || null,
    changedFiles,
    notes: args.notes ?? `attach-run validation exited ${validation.validation.exitCode}`,
    attributedPrecedents,
  });
  const repairReceipt = await runAttachRepairReceipt({
    stateDirArg,
    sessionId,
    eventId: eventPrefix ? `${eventPrefix}:repair.after_retry` : null,
    repairTarget: retryRepairTarget,
    retryStartedAt,
    attributedPrecedents,
  });
  const autoPromotion = args["auto-promote"] === true
    ? await runPrecedentChildJson([
      "promote-pending",
      "--state-dir",
      stateDirArg,
      "--json",
    ])
    : null;
  const idle = await runAttachIdle({
    stateDirArg,
    sessionId,
    eventId: eventPrefix ? `${eventPrefix}:orchestration.after_idle` : null,
  });

  print({
    ok: true,
    schema_version: "precedent.attach_run.v1",
    runtime,
    stateDir: stateDirArg,
    sessionId,
    eventPrefix,
    identity: sessionIdentity,
    task: taskSource.task,
    taskFile: taskSource.taskFile,
    scope: scope || null,
    changedFiles,
    attributedPrecedents,
    beforeTurn,
    injectionAck,
    warrant,
    diff,
    validation,
    selfHealing,
    selfRepair,
    finalization,
    outcome,
    repairReceipt,
    autoPromotion,
    idle,
    learning: outcome.learning ?? null,
  });
}

async function runAttachDiff({
  stateDirArg,
  sessionId,
  eventId,
  deliveryId,
  warrantId,
  changedFiles,
  diffSummary,
  unifiedDiff,
  attributedPrecedents,
}) {
  if (changedFiles.length === 0 && !diffSummary && !unifiedDiff) {
    return null;
  }

  return runPrecedentChildJson([
    "hook",
    "--state-dir",
    stateDirArg,
    "--json",
  ], {
    schema_version: SCHEMA_VERSION,
    hook: "diff.after_edit",
    sessionId,
    ...eventIdField(eventId),
    deliveryId,
    warrantId,
    changedFiles,
    diffSummary: diffSummary ?? null,
    unifiedDiff: unifiedDiff ?? null,
    attributedPrecedents,
  });
}

async function runAttachInjectionAck({
  stateDirArg,
  sessionId,
  eventId,
  deliveryReceipt,
  contextBlockHash,
  inserted,
}) {
  if (!deliveryReceipt?.deliveryId) {
    return {
      status: "not_needed",
      ack: null,
    };
  }

  const ack = await runPrecedentChildJson([
    "hook",
    "--state-dir",
    stateDirArg,
    "--json",
  ], {
    schema_version: SCHEMA_VERSION,
    hook: "context.after_inject",
    sessionId,
    ...eventIdField(eventId),
    deliveryId: deliveryReceipt.deliveryId,
    contextBlockHash,
    inserted,
  });

  return {
    status: ack.contextInjectionAck?.status ?? "unknown",
    ack,
  };
}

async function runAttachValidation({
  stateDirArg,
  sessionId,
  eventId,
  deliveryId,
  warrantId,
  command,
  attributedPrecedents,
}) {
  const startedAt = Date.now();
  const validationResult = await spawnShell(command, process.cwd());
  const durationMs = Date.now() - startedAt;

  return runPrecedentChildJson([
    "hook",
    "--state-dir",
    stateDirArg,
    "--json",
  ], {
    schema_version: SCHEMA_VERSION,
    hook: "validation.after_run",
    sessionId,
    ...eventIdField(eventId),
    deliveryId,
    warrantId,
    command: redactSecrets(command).value,
    exitCode: validationResult.exitCode,
    durationMs,
    stdout: validationResult.stdout,
    stderr: validationResult.stderr,
    attributedPrecedents,
  });
}

function runAttachFinalization({ stateDirArg, sessionId, eventId, deliveryId, warrantId, attributedPrecedents }) {
  return runPrecedentChildJson([
    "hook",
    "--state-dir",
    stateDirArg,
    "--json",
  ], {
    schema_version: SCHEMA_VERSION,
    hook: "finalize.before_response",
    sessionId,
    ...eventIdField(eventId),
    deliveryId,
    warrantId,
    attributedPrecedents,
  });
}

function runAttachRepairHandoff({
  stateDirArg,
  sessionId,
  eventId,
  task,
  scope,
  changedFiles,
  attributedPrecedents,
  finalization,
}) {
  const nextAction = finalization.nextAction ?? {};
  if (nextAction.type !== "repair_retry") {
    return {
      status: "not_needed",
      repair: null,
    };
  }

  return runPrecedentChildJson([
    "hook",
    "--state-dir",
    stateDirArg,
    "--json",
  ], {
    schema_version: SCHEMA_VERSION,
    hook: "repair.before_retry",
    sessionId,
    ...eventIdField(eventId),
    task,
    scope: scope || null,
    changedFiles,
    attributedPrecedents,
  }).then((repair) => ({
    status: repair.repairBlock ? "handoff_ready" : "suppressed",
    repair,
    repairId: repair.repairId,
    suppressedRepairs: repair.suppressedRepairs ?? [],
  }));
}

function runAttachRepairReceipt({
  stateDirArg,
  sessionId,
  eventId,
  repairTarget,
  retryStartedAt,
  attributedPrecedents,
}) {
  const repairId = repairTarget?.repairId ?? null;
  const repairSessionId = repairTarget?.repairSessionId ?? null;

  if (!repairId) {
    return {
      status: "not_requested",
      receipt: null,
      repairSource: "none",
    };
  }

  return runPrecedentChildJson([
    "hook",
    "--state-dir",
    stateDirArg,
    "--json",
  ], {
    schema_version: SCHEMA_VERSION,
    hook: "repair.after_retry",
    sessionId,
    ...eventIdField(eventId),
    repairId,
    repairSessionId,
    retryStartedAt,
    attributedPrecedents,
  }).then((receipt) => ({
    status: receipt.repairReceipt?.status ?? "unresolved",
    receipt,
    repairId,
    repairSessionId,
    repairSource: repairTarget.source,
    suppressedRepairs: receipt.suppressedRepairs ?? [],
  }));
}

async function attachPendingRepairTarget({ stateDirArg, sessionId, eventId }) {
  try {
    await ensureState(stateDirArg);

    if (eventId) {
      const existing = await findSessionEventByEventId(stateDirArg, sessionId, eventId);
      if (existing?.event?.hook === "repair.after_retry" && existing.event.repairId) {
        return {
          source: "deduped_receipt",
          repairId: existing.event.repairId,
          repairSessionId: existing.event.repairSessionId ?? sessionId,
        };
      }
    }

    const sessionEvents = await readSessionEvents(stateDirArg, sessionId);
    const globalEvents = await readJsonLines(join(stateDirArg, "events.jsonl"));
    const receiptKeys = new Set(globalEvents
      .filter((event) => event.hook === "repair.after_retry" && event.repairReceipt)
      .map((event) => repairReceiptKey({
        repairId: event.repairReceipt.id ?? event.repairId,
        repairSessionId: event.repairReceipt.repairSessionId ?? event.repairSessionId ?? sessionId,
      })));
    const repair = sessionEvents
      .filter((event) => event.hook === "repair.before_retry" && event.repairId)
      .filter((event) => !receiptKeys.has(repairReceiptKey({
        repairId: event.repairId,
        repairSessionId: event.sessionId ?? sessionId,
      })))
      .sort((left, right) => eventTime(left) - eventTime(right))
      .at(-1);

    if (!repair) {
      return null;
    }

    return {
      source: "pending_repair",
      repairId: repair.repairId,
      repairSessionId: repair.sessionId ?? sessionId,
    };
  } catch (error) {
    return null;
  }
}

function runAttachIdle({ stateDirArg, sessionId, eventId }) {
  return runPrecedentChildJson([
    "hook",
    "--state-dir",
    stateDirArg,
    "--json",
  ], {
    schema_version: SCHEMA_VERSION,
    hook: "orchestration.after_idle",
    sessionId,
    ...eventIdField(eventId),
  });
}

async function runAttachSelfHealing({
  stateDirArg,
  sessionId,
  eventPrefix,
  deliveryId,
  warrantId,
  attributedPrecedents,
  finalization,
}) {
  const nextAction = finalization.nextAction ?? {};
  if (nextAction.type !== "run_validation") {
    return {
      status: "not_needed",
      validations: [],
      finalization: null,
    };
  }

  const commands = uniqueStrings(Array.isArray(nextAction.commands) ? nextAction.commands : []);
  const unsafe = commands
    .map((commandText) => ({ command: commandText, safety: replayCommandSafety(commandText) }))
    .filter((item) => !item.safety.safe);
  if (unsafe.length > 0) {
    return {
      status: "blocked_unsafe_command",
      reason: unsafe[0].safety.reason,
      commands,
      blockedCommands: unsafe.map((item) => ({
        command: item.command,
        reason: item.safety.reason,
      })),
      validations: [],
      finalization: null,
    };
  }

  const validations = [];
  for (const commandText of commands) {
    validations.push(await runAttachValidation({
      stateDirArg,
      sessionId,
      eventId: eventPrefix ? `${eventPrefix}:validation.after_run:self_heal:${stableHash(commandText).slice(0, 12)}` : null,
      deliveryId,
      warrantId,
      command: commandText,
      attributedPrecedents,
    }));
  }

  const recovered = await runAttachFinalization({
    stateDirArg,
    sessionId,
    eventId: eventPrefix ? `${eventPrefix}:finalize.before_response:self_heal` : null,
    deliveryId,
    warrantId,
    attributedPrecedents,
  });

  return {
    status: recovered.decision === "ready" ? "recovered" : "still_blocked",
    commands,
    validations,
    finalization: recovered,
  };
}

function runPrecedentChildJson(childArgs, stdinJson = null) {
  return new Promise((resolvePromise, reject) => {
    const child = spawn(process.execPath, [process.argv[1], ...childArgs], {
      cwd: process.cwd(),
      stdio: ["pipe", "pipe", "pipe"],
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
      if (exitCode !== 0) {
        reject(new Error(`precedent ${childArgs.join(" ")} failed\n${stderr}`));
        return;
      }

      try {
        resolvePromise(parseJson(stdout, `precedent ${childArgs.join(" ")}`));
      } catch (error) {
        reject(error);
      }
    });

    if (stdinJson) {
      child.stdin.end(`${JSON.stringify(stdinJson)}\n`);
    } else {
      child.stdin.end();
    }
  });
}

async function readAttachTaskSource() {
  if (args["task-file"]) {
    const taskFile = resolve(args["task-file"]);
    return {
      task: await readFile(taskFile, "utf8"),
      taskFile,
    };
  }

  if (args.task) {
    return {
      task: args.task,
      taskFile: null,
    };
  }

  fail("attach requires --task <text> or --task-file <path>");
}

function runtimeSessionIdentity({ runtime, taskSource, scope, changedFiles }) {
  if (args.session) {
    return {
      sessionId: safeFileName(args.session),
      source: "explicit_session",
      threadId: args["thread-id"] ?? null,
      fallback: false,
    };
  }

  if (args["thread-id"]) {
    return {
      sessionId: safeFileName(stableSessionId({
        runtime,
        cwd: process.cwd(),
        threadId: args["thread-id"],
      })),
      source: "thread_id",
      threadId: args["thread-id"],
      fallback: false,
    };
  }

  return {
    sessionId: safeFileName(stableSessionId({
      runtime,
      task: taskSource.task,
      taskFile: taskSource.taskFile,
      scope,
      changedFiles,
    })),
    source: "task_hash_fallback",
    threadId: null,
    fallback: true,
  };
}

function runtimeIdentityContract() {
  return {
    inputs: {
      session: "$SESSION_ID",
      threadId: "$THREAD_ID",
    },
    precedence: ["session", "threadId", "task_hash_fallback"],
    recommendation: "Pass a stable runtime conversation id as --thread-id; task-hash fallback is only for demos.",
  };
}

function stableSessionId(input) {
  return `session_${stableHash(input).slice(0, 16)}`;
}

async function reportState() {
  const stateDir = statePath();
  const precedents = await readJsonLines(join(stateDir, "precedents.jsonl"));
  const candidates = await readJsonLines(join(stateDir, "candidates.jsonl"));
  const events = await readJsonLines(join(stateDir, "events.jsonl"));
  const replays = await readReplayCount(join(stateDir, "replays"));
  const replayAudit = await replayAuditEntries(precedents, stateDir);
  const runtimeWiringHealth = await runtimeWiringHealthSummary(stateDir, events);
  const warrantHealth = await warrantHealthSummary(stateDir);
  const artifactHealth = await candidateArtifactHealth(stateDir, candidates);

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
    auditHealth: replayAuditHealth(replayAudit),
    replayAudit,
    candidateHintQueue: candidateHintQueue(candidates, precedents, stateDir),
    promotionTrialQueue: promotionTrialQueue(events),
    repairHealth: repairHealthSummary(events, precedents),
    runtimeWiringHealth,
    warrantHealth,
    artifactHealth,
    precedentHealth: precedents.map((precedent) => ({
      id: precedent.id,
      ...outcomeSummaryForPrecedent(events, precedent.id),
    })),
  });
}

function promotionTrialQueue(events, options = {}) {
  const nowMs = options.now instanceof Date ? options.now.getTime() : Date.now();
  const maxAttempts = Number(options.maxAttempts ?? PROMOTION_TRIAL_MAX_ATTEMPTS);
  const eventsByTrial = new Map();
  const byId = new Map();

  for (const event of events) {
    if (event.trialId) {
      const list = eventsByTrial.get(event.trialId) ?? [];
      list.push(event);
      eventsByTrial.set(event.trialId, list);
    }
    if (!Array.isArray(event.promotionTrials)) {
      continue;
    }
    for (const trial of event.promotionTrials) {
      if (!trial?.id || !Array.isArray(trial.command) || trial.command.length < 3) {
        continue;
      }

      byId.set(trial.id, {
        trialId: trial.id,
        candidateId: trial.candidateId ?? null,
        sourceEventId: event.eventId ?? null,
        sourceSessionId: event.sessionId ?? null,
        reason: trial.reason ?? null,
        baselineCommand: trial.baselineCommand ?? null,
        rerunCommand: trial.rerunCommand ?? null,
        autoExecute: trial.autoExecute === true,
        autoExecuteBlockers: Array.isArray(trial.autoExecuteBlockers) ? trial.autoExecuteBlockers : [],
        traceOut: trial.traceOut ?? null,
        command: trial.command,
      });
    }
  }

  const items = [...byId.values()]
    .sort((left, right) => left.trialId.localeCompare(right.trialId))
    .map((item) => {
      const trialEvents = eventsByTrial.get(item.trialId) ?? [];
      const safety = replayTrialExecutionSafety(item);
      const state = promotionTrialExecutionState(trialEvents, safety, nowMs, maxAttempts);

      return {
        ...item,
        status: state.status,
        attempt: state.attempt,
        runId: state.runId,
        leaseExpiresAt: state.leaseExpiresAt,
        blockers: state.status === "blocked" ? safety.blockers : [],
        promotedId: state.terminal?.promotedId ?? null,
        rejectedId: state.terminal?.rejectedId ?? null,
        replayAuditStatus: state.terminal?.replayAuditStatus ?? null,
        error: state.error,
      };
    });

  return {
    total: items.length,
    ready: items.filter((item) => item.status === "ready").length,
    blocked: items.filter((item) => item.status === "blocked").length,
    running: items.filter((item) => item.status === "running").length,
    completed: items.filter((item) => item.status === "completed").length,
    failed: items.filter((item) => item.status === "failed").length,
    items,
  };
}

function promotionTrialExecutionState(trialEvents, safety, nowMs, maxAttempts) {
  const starts = trialEvents.filter((event) => event.type === "promotion_trial_started");
  const terminals = trialEvents.filter((event) => event.type === "promotion_trial_completed" || event.type === "promotion_trial_failed");
  const latestStart = starts.at(-1) ?? null;
  const latestTerminal = terminals.at(-1) ?? null;
  const attempt = starts.length + 1;

  if (latestTerminal && (!latestStart || eventTime(latestTerminal) >= eventTime(latestStart))) {
    if (latestTerminal.type === "promotion_trial_completed") {
      return {
        status: "completed",
        attempt: starts.length,
        runId: latestTerminal.runId ?? null,
        leaseExpiresAt: null,
        terminal: latestTerminal,
        error: null,
      };
    }

    if (starts.length >= maxAttempts) {
      return {
        status: "failed",
        attempt: starts.length,
        runId: latestTerminal.runId ?? null,
        leaseExpiresAt: null,
        terminal: latestTerminal,
        error: latestTerminal.error ?? "promotion trial failed",
      };
    }
  }

  if (!safety.safe) {
    return {
      status: "blocked",
      attempt,
      runId: null,
      leaseExpiresAt: null,
      terminal: latestTerminal,
      error: safety.reason,
    };
  }

  if (latestStart && (!latestTerminal || eventTime(latestTerminal) < eventTime(latestStart))) {
    const leaseExpiresAt = Date.parse(latestStart.leaseExpiresAt ?? "");
    const leaseExpired = Number.isFinite(leaseExpiresAt) && leaseExpiresAt <= nowMs;
    if (!leaseExpired) {
      return {
        status: "running",
        attempt: starts.length,
        runId: latestStart.runId ?? null,
        leaseExpiresAt: latestStart.leaseExpiresAt ?? null,
        terminal: null,
        error: null,
      };
    }

    if (starts.length >= maxAttempts) {
      return {
        status: "failed",
        attempt: starts.length,
        runId: latestStart.runId ?? null,
        leaseExpiresAt: latestStart.leaseExpiresAt ?? null,
        terminal: null,
        error: "promotion trial lease expired after max attempts",
      };
    }
  }

  return {
    status: "ready",
    attempt,
    runId: null,
    leaseExpiresAt: null,
    terminal: latestTerminal,
    error: null,
  };
}

async function replayAuditEntries(precedents, stateDir) {
  return Promise.all(precedents.map((precedent) => replayAuditEntry(precedent, stateDir)));
}

async function replayAuditEntry(precedent, stateDir) {
  const replay = precedent.replay ?? {};
  const base = {
    precedentId: precedent.id ?? null,
    replayId: replay.id ?? null,
    replayPath: replay.path ?? null,
    expectedSha256: replay.artifact_sha256 ?? null,
    actualSha256: null,
    baselineFailures: replay.baseline_failures ?? null,
    rerunFailures: replay.rerun_failures ?? null,
    baselineExitCode: replay.baseline_exit_code ?? null,
    rerunExitCode: replay.rerun_exit_code ?? null,
    failureDelta: Number.isFinite(replay.baseline_failures) && Number.isFinite(replay.rerun_failures)
      ? replay.baseline_failures - replay.rerun_failures
      : null,
  };

  if (!nonEmptyString(replay.id) || !nonEmptyString(replay.path) || !/^[a-f0-9]{64}$/u.test(replay.artifact_sha256 ?? "")) {
    return {
      ...base,
      status: "missing_receipt",
      messages: ["typed replay receipt is incomplete"],
      nextAction: "rerun candidate replay and observe the generated trace",
    };
  }

  const replayPath = resolve(replay.path);
  if (!pathWithin(resolve(stateDir), replayPath)) {
    return {
      ...base,
      status: "outside_state",
      messages: ["replay.path points outside the Precedent state directory"],
      nextAction: "discard the precedent or replay it into the current state directory",
    };
  }

  let rawArtifact = null;
  try {
    rawArtifact = await readFile(replayPath, "utf8");
  } catch (error) {
    return {
      ...base,
      status: error.code === "ENOENT" ? "missing_artifact" : "unreadable_artifact",
      messages: [`replay artifact is not readable: ${error.message}`],
      nextAction: "restore the replay artifact or replay the candidate again",
    };
  }

  const actualSha256 = sha256Text(rawArtifact);
  if (actualSha256 !== replay.artifact_sha256) {
    return {
      ...base,
      actualSha256,
      status: "hash_mismatch",
      messages: ["replay artifact hash does not match the typed receipt"],
      nextAction: "rerun replay and observe a fresh trace before trusting this precedent",
    };
  }

  let artifact = null;
  try {
    artifact = JSON.parse(rawArtifact);
  } catch (error) {
    return {
      ...base,
      actualSha256,
      status: "metadata_mismatch",
      messages: [`replay artifact JSON is invalid: ${error.message}`],
      nextAction: "rerun replay and observe a fresh trace before promotion",
    };
  }
  const messages = [];
  if (artifact.id !== replay.id) {
    messages.push("replay artifact id does not match receipt");
  }
  if (artifact.promotion?.baseline_failures !== precedent.promotion?.baseline_failures) {
    messages.push("baseline failure count does not match promotion");
  }
  if (artifact.promotion?.rerun_failures !== precedent.promotion?.rerun_failures) {
    messages.push("rerun failure count does not match promotion");
  }
  if (artifact.baseline?.exitCode !== replay.baseline_exit_code) {
    messages.push("baseline exit code does not match replay artifact");
  }
  if (artifact.rerun?.exitCode !== replay.rerun_exit_code) {
    messages.push("rerun exit code does not match replay artifact");
  }

  if (messages.length > 0) {
    return {
      ...base,
      actualSha256,
      status: "metadata_mismatch",
      messages,
      nextAction: "rerun replay and observe a fresh trace before promotion",
    };
  }

  return {
    ...base,
    actualSha256,
    status: "verified",
    messages: [],
    nextAction: "none",
  };
}

function replayAuditHealth(entries) {
  const counts = {
    total: entries.length,
    verified: 0,
    missingReceipt: 0,
    missingArtifact: 0,
    unreadableArtifact: 0,
    outsideState: 0,
    hashMismatch: 0,
    metadataMismatch: 0,
    needsAttention: 0,
  };

  for (const entry of entries) {
    if (entry.status === "verified") {
      counts.verified += 1;
      continue;
    }

    counts.needsAttention += 1;
    if (entry.status === "missing_receipt") {
      counts.missingReceipt += 1;
    } else if (entry.status === "missing_artifact") {
      counts.missingArtifact += 1;
    } else if (entry.status === "unreadable_artifact") {
      counts.unreadableArtifact += 1;
    } else if (entry.status === "outside_state") {
      counts.outsideState += 1;
    } else if (entry.status === "hash_mismatch") {
      counts.hashMismatch += 1;
    } else if (entry.status === "metadata_mismatch") {
      counts.metadataMismatch += 1;
    }
  }

  return counts;
}

async function checkState() {
  const stateDir = statePath();
  const checks = [];

  await checkConfig(checks);
  await checkJsonLinesFile(checks, join(stateDir, "precedents.jsonl"), "precedents");
  await checkJsonLinesFile(checks, join(stateDir, "events.jsonl"), "events");
  await checkJsonLinesFile(checks, join(stateDir, "candidates.jsonl"), "candidates");
  await checkJsonFilesInDir(checks, join(stateDir, "traces"), "trace", (value, file) => {
    assertCheck(value?.schema_version === SCHEMA_VERSION, checks, "trace_schema", file, "trace.schema_version is invalid");
  });
  await checkCandidateLedger(checks, stateDir);
  await checkJsonLinesInDir(checks, join(stateDir, "sessions"), "session");
  await checkReplayArtifacts(checks, join(stateDir, "replays"));
  await checkPromotedPrecedents(checks, stateDir);
  await checkRepairReceipts(checks, stateDir);
  await checkCorrectionSafety(checks, stateDir, args.strict === true);
  await checkRuntimeWiring(checks, stateDir, args.strict === true);
  await checkWarrants(checks, stateDir, args.strict === true);
  await checkNoRawSecrets(checks, stateDir);
  await checkManifestBuilds(checks);
  if (args.strict) {
    await checkStrictStateArtifacts(checks, stateDir);
  }

  const ok = checks.every((check) => check.ok);
  const payload = {
    ok,
    stateDir,
    checks,
  };

  print(payload);
  if (!ok) {
    process.exit(1);
  }
}

async function pruneState() {
  const stateDir = statePath();
  const dryRun = args["dry-run"] === true;
  const cutoff = args.before
    ? new Date(args.before)
    : new Date(Date.now() - runtimeConfig.retentionDays * 24 * 60 * 60 * 1000);

  if (Number.isNaN(cutoff.getTime())) {
    fail("prune.before must be a valid ISO date");
  }

  const plan = {
    ok: true,
    dryRun,
    stateDir,
    cutoff: cutoff.toISOString(),
    retentionDays: runtimeConfig.retentionDays,
    removedEvents: 0,
    keptEvents: 0,
    removedSessionEvents: 0,
    keptSessionEvents: 0,
    removedFiles: [],
  };

  await withStateLock(stateDir, async () => {
    await ensureState(stateDir);
    await pruneJsonLinesByTime(join(stateDir, "events.jsonl"), cutoff, dryRun, plan, "removedEvents", "keptEvents");

    for (const sessionFile of await jsonFiles(join(stateDir, "sessions"), ".jsonl")) {
      await pruneJsonLinesByTime(sessionFile, cutoff, dryRun, plan, "removedSessionEvents", "keptSessionEvents");
    }

    for (const replayDir of await childDirs(join(stateDir, "replays"))) {
      const replayPath = join(replayDir, "replay.json");
      const replayTime = await fileTime(replayPath);

      if (replayTime && replayTime < cutoff) {
        plan.removedFiles.push(replayDir);
        if (!dryRun) {
          await rm(replayDir, { recursive: true, force: true });
        }
      }
    }
  });

  print(plan);
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
    paths: pathsForCandidateTrace(trace, scope, failureTypes),
    source_traces: [traceId],
    failure_types: failureTypes,
    evidence,
    injection: injectionForFailureTypes(failureTypes, scope),
    replayPlan: replayPlanFromTrace(trace),
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
    replay: precedent.replay ?? null,
    guards: Array.isArray(precedent.guards) ? precedent.guards : [],
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
    replay: replayReceiptFromTrace(trace),
  };
}

function replayReceiptFromTrace(trace) {
  const promotion = trace.replay?.promotion ?? {};

  return {
    id: requireString(trace.replay?.id, "trace.replay.id"),
    path: requireString(trace.replay?.path, "trace.replay.path"),
    artifact_sha256: requireString(trace.replay?.artifact_sha256, "trace.replay.artifact_sha256"),
    baseline_failures: promotion.baseline_failures,
    rerun_failures: promotion.rerun_failures,
    baseline_exit_code: promotion.baseline_exit_code ?? trace.replay?.baseline?.exitCode ?? null,
    rerun_exit_code: promotion.rerun_exit_code ?? trace.replay?.rerun?.exitCode ?? null,
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
        applicabilityReceipt: applicabilityReceiptForMatch(match.reasons),
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

function applicabilityReceiptForMatch(reasons) {
  const anchors = reasons
    .filter((reason) => reason.type === "scope_match" || reason.type === "path_match")
    .map((reason) => reason.type);

  return {
    status: anchors.length > 0 ? "anchored" : "unanchored",
    anchors: uniqueStrings(anchors),
    required: ["scope_match", "path_match"],
  };
}

function suppressApplicabilityInjections(matches) {
  const selected = [];
  const suppressed = [];

  for (const match of matches) {
    const receipt = match.applicabilityReceipt ?? applicabilityReceiptForMatch(match.matchReasons ?? []);
    if (receipt.status === "anchored") {
      selected.push({ ...match, applicabilityReceipt: receipt });
      continue;
    }

    suppressed.push({
      ...match,
      applicabilityReceipt: receipt,
      suppressionReason: "applicability_unanchored",
    });
  }

  return { matches: selected, suppressed };
}

function formatInjectionBlock(matches) {
  if (matches.length === 0) {
    return "";
  }

  const lines = ["Precedent:"];

  for (const match of matches) {
    lines.push(`- ${redactSecrets(match.injection).value}`);
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
    injection: redactSecrets(match.injection).value,
    sourceTrace: match.source_trace,
    applicabilityReceipt: match.applicabilityReceipt ?? null,
  };
}

function formatSuppressedInjection(match, events = null) {
  const formatted = {
    id: match.id,
    score: match.score,
    reason: match.suppressionReason ?? "already_injected_in_session",
  };
  if (match.applicabilityReceipt) {
    formatted.applicabilityReceipt = match.applicabilityReceipt;
  }
  if (match.suppressionReason === "replay_audit_failed") {
    formatted.replayAuditStatus = match.replayAuditStatus ?? null;
    formatted.replayAuditMessages = Array.isArray(match.replayAuditMessages) ? match.replayAuditMessages : [];
  }
  if (events && ["stale_repair_efficacy", "retired_repair_efficacy"].includes(formatted.reason)) {
    formatted.counterexampleCount = counterexamplesForPrecedent(events, match.id).length;
  }
  return formatted;
}

async function suppressReplayAuditInjections({ stateDir, matches }) {
  const selected = [];
  const suppressed = [];

  for (const match of matches) {
    const audit = await replayAuditEntry(match, stateDir);
    if (audit.status === "verified") {
      selected.push(match);
      continue;
    }

    suppressed.push({
      ...match,
      suppressionReason: "replay_audit_failed",
      replayAuditStatus: audit.status,
      replayAuditMessages: audit.messages,
    });
  }

  return { matches: selected, suppressed };
}

function revisionBriefsForSuppressed(events, suppressed) {
  return suppressed
    .filter((match) => ["stale_repair_efficacy", "retired_repair_efficacy"].includes(match.suppressionReason))
    .map((match) => revisionBriefForPrecedent(events, match));
}

function revisionBriefForPrecedent(events, match) {
  const counterexamples = counterexamplesForPrecedent(events, match.id);
  return {
    id: match.id,
    status: match.suppressionReason === "retired_repair_efficacy" ? "retired" : "stale",
    failureSummary: counterexampleSummary(counterexamples),
    recentCounterexamples: counterexamples.slice(-3),
    revisionCriteria: [
      "Identify the assumption in the old precedent that the counterexamples invalidate.",
      "Capture a clean session with matching scope or path overlap and passing validation.",
      "Promote a replacement only after replay evidence shows fewer failures.",
    ],
  };
}

function counterexampleSummary(counterexamples) {
  const counts = {};
  for (const counterexample of counterexamples) {
    counts[counterexample.type] = (counts[counterexample.type] ?? 0) + 1;
  }

  return Object.entries(counts)
    .map(([type, count]) => `${count} ${type.replaceAll("_", " ")}`)
    .join(", ") || "no counterexamples";
}

function promotionTrialsForContext({ candidates, context, suppressed, sessionId }) {
  const suppressedRepairIds = new Set(
    suppressed
      .filter((match) => ["stale_repair_efficacy", "retired_repair_efficacy"].includes(match.suppressionReason))
      .map((match) => match.id),
  );
  if (suppressedRepairIds.size === 0) {
    return [];
  }

  return candidates
    .filter((candidate) =>
      candidate.reason === "repair_efficacy_replacement"
      && candidate.status === "candidate"
      && Array.isArray(candidate.replaces)
      && candidate.replaces.some((id) => suppressedRepairIds.has(id))
      && candidateOverlapsContext(candidate, context))
    .slice(0, 3)
    .map((candidate) => ({
      id: `trial_${safeFileName(candidate.id)}_${safeFileName(sessionId ?? stableHash(context).slice(0, 8))}`,
      candidateId: candidate.id,
      replaces: candidate.replaces,
      reason: "verify_repair_efficacy_replacement",
      validationCommand: validationCommandFromEvidence(candidate.evidence),
      evidence: Array.isArray(candidate.evidence) ? candidate.evidence.slice(0, 5) : [],
      acceptance: "Replay with candidate injected; promote only if rerun failures are lower than baseline failures.",
    }));
}

function promotionTrialsForValidation({ candidates, precedents, context, sessionId, commandText, exitCode, stateDir }) {
  if (exitCode !== 0) {
    return [];
  }

  const promotedIds = new Set(precedents.map((precedent) => precedent.id));
  return candidates
    .filter((candidate) =>
      candidate.status === "candidate"
      && !promotedIds.has(candidate.id)
      && candidateReplayBaseline(candidate)
      && candidateOverlapsContext(candidate, context))
    .sort((left, right) => left.id.localeCompare(right.id))
    .slice(0, 3)
    .map((candidate) => validationPromotionTrialForCandidate({
      candidate,
      context,
      sessionId,
      commandText,
      stateDir,
    }));
}

function validationPromotionTrialForCandidate({ candidate, context, sessionId, commandText, stateDir }) {
  const baseline = candidateReplayBaseline(candidate);
  const executionSafety = replayCommandPairSafety(baseline.command, commandText);
  const traceOut = join(
    stateDir,
    "traces",
    `promotion-trial-${safeFileName(candidate.id)}-${safeFileName(sessionId ?? "validation")}.json`,
  );
  const command = [
    "node",
    "precedent/bin/precedent.mjs",
    "promotion-trial",
    "--state-dir",
    stateDir,
    "--candidate",
    candidate.id,
    "--baseline-command",
    baseline.command,
    "--rerun-command",
    commandText,
    "--trace-out",
    traceOut,
    "--json",
  ];

  return redactSecretsDeep({
    id: `trial_${safeFileName(candidate.id)}_${stableHash({
      sessionId,
      commandText,
      scope: context.scope,
      changedFiles: context.changedFiles,
    }).slice(0, 12)}`,
    candidateId: candidate.id,
    reason: "successful_validation_matches_candidate",
    replayRequired: true,
    injectable: false,
    autoExecute: executionSafety.safe,
    autoExecuteBlockers: executionSafety.blockers,
    baselineCommand: baseline.command,
    baselineExitCode: baseline.exitCode,
    baselineSourceTrace: baseline.sourceTrace ?? null,
    baselineSourceSession: baseline.sourceSession ?? null,
    rerunCommand: commandText,
    validationCommand: commandText,
    traceOut,
    command,
    acceptance: "Run the promotion trial and inject only if replay promotion produces a verified precedent.",
  }).value;
}

function replayCommandPairSafety(baselineCommand, rerunCommand) {
  const blockers = [];
  const baseline = replayCommandSafety(baselineCommand);
  if (!baseline.safe) {
    blockers.push(`baseline_${baseline.reason}`);
  }
  const rerun = replayCommandSafety(rerunCommand);
  if (!rerun.safe) {
    blockers.push(`rerun_${rerun.reason}`);
  }

  return {
    safe: blockers.length === 0,
    blockers,
  };
}

function replayCommandSafety(command) {
  if (typeof command !== "string" || command.trim().length === 0) {
    return { safe: false, reason: "missing_command" };
  }

  const trimmed = command.trim();
  if (/[;&|<>`$\\\n\r"'()]/u.test(trimmed)) {
    return { safe: false, reason: "unsafe_shell_syntax" };
  }

  if (/^node\s+--check\s+[A-Za-z0-9_./-]+(?:\s+[A-Za-z0-9_./:=@-]+)*$/u.test(trimmed)) {
    return { safe: true, reason: null };
  }

  if (/^(?:pnpm|npm|yarn)\s+(?:test(?::[A-Za-z0-9_.-]+)?|run\s+test(?::[A-Za-z0-9_.-]+)?)(?:\s+--\s*[A-Za-z0-9_./:=@-]+)*$/u.test(trimmed)) {
    return { safe: true, reason: null };
  }

  return { safe: false, reason: "not_allowlisted" };
}

function candidateReplayBaseline(candidate) {
  const baseline = candidate.replayPlan?.baseline;
  if (!baseline || typeof baseline.command !== "string" || baseline.command.trim().length === 0) {
    return null;
  }

  return {
    command: baseline.command.trim(),
    exitCode: Number.isFinite(baseline.exitCode) ? baseline.exitCode : null,
    sourceTrace: typeof baseline.sourceTrace === "string" ? baseline.sourceTrace : null,
    sourceSession: typeof baseline.sourceSession === "string" ? baseline.sourceSession : null,
  };
}

function candidateHintsForContext({ candidates, precedents, context, stateDir, sessionId, limit = 3 }) {
  const promotedIds = new Set(precedents.map((precedent) => precedent.id));

  return candidates
    .filter((candidate) =>
      candidate.status === "candidate"
      && !promotedIds.has(candidate.id))
    .map((candidate) => {
      const match = scorePrecedent(candidate, context);

      return {
        ...candidate,
        score: match.score,
        matchReasons: match.reasons,
        applicabilityReceipt: applicabilityReceiptForMatch(match.reasons),
      };
    })
    .filter((candidate) => candidate.score > 0 && candidate.applicabilityReceipt.status === "anchored")
    .sort((left, right) => right.score - left.score || left.id.localeCompare(right.id))
    .slice(0, limit)
    .map((candidate) => formatCandidateHint(candidate, stateDir, sessionId));
}

function formatCandidateHint(candidate, stateDir, sessionId) {
  const baseline = candidateReplayBaseline(candidate);
  const rerunCommand = validationCommandFromEvidence(candidate.evidence);
  const artifact = artifactDescriptor(candidate, stateDir);
  const traceOut = join(
    stateDir,
    "traces",
    `promotion-trial-${safeFileName(candidate.id)}-${safeFileName(sessionId ?? "manual")}.json`,
  );
  const command = [
    "node",
    "precedent/bin/precedent.mjs",
    "promotion-trial",
    "--state-dir",
    stateDir,
    "--candidate",
    candidate.id,
    "--baseline-command",
    baseline?.command ?? "$BASELINE_COMMAND",
    ...(rerunCommand ? ["--rerun-command", rerunCommand] : []),
    "--trace-out",
    traceOut,
    "--json",
  ];

  return redactSecretsDeep({
    candidateId: candidate.id,
    status: candidate.status ?? "candidate",
    reason: candidate.reason ?? null,
    scope: candidate.scope ?? null,
    paths: Array.isArray(candidate.paths) ? candidate.paths : [],
    failureTypes: Array.isArray(candidate.failure_types) ? candidate.failure_types : [],
    sourceTraces: Array.isArray(candidate.source_traces) ? candidate.source_traces : [],
    evidence: Array.isArray(candidate.evidence) ? candidate.evidence.slice(0, 5) : [],
    replayRequired: true,
    promotionRequired: candidate.promotion_required ?? "Replay before promotion.",
    matchReasons: candidate.matchReasons ?? [],
    applicabilityReceipt: candidate.applicabilityReceipt ?? null,
    suggestedAction: "Run a promotion trial with a failing baseline command before trusting this candidate.",
    artifact: {
      path: artifact.path,
      command: artifact.command,
      injectable: false,
      status: "preview",
    },
    replayPlan: candidate.replayPlan ?? null,
    promotionTrial: {
      readiness: baseline?.command && rerunCommand ? "ready" : baseline?.command ? "needs_rerun_command" : "needs_baseline_command",
      blockers: [
        ...(baseline?.command ? [] : ["missing failed baseline validation evidence or --baseline-command"]),
        ...(rerunCommand ? [] : ["missing successful validation evidence or --rerun-command"]),
      ],
      baselineCommand: baseline?.command ?? "$BASELINE_COMMAND",
      baselineExitCode: baseline?.exitCode ?? null,
      rerunCommand,
      traceOut,
      command,
      acceptance: {
        requiresReplay: true,
        promoteWhen: "baseline_failures > rerun_failures",
      },
    },
  }).value;
}

function artifactDescriptor(candidate, stateDir) {
  const artifactPath = join(stateDir, "artifacts", safeFileName(requireString(candidate.id, "candidate.id")), "SKILL.md");
  return {
    path: artifactPath,
    command: [
      "node",
      "precedent/bin/precedent.mjs",
      "artifact",
      "--state-dir",
      stateDir,
      "--candidate",
      candidate.id,
      "--json",
    ],
  };
}

function renderCandidateSkill(candidate, artifact) {
  const redacted = redactSecretsDeep(candidate).value;
  const requiredValidation = validationCommandFromEvidence(redacted.evidence);
  const evidence = markdownList(redacted.evidence);
  const paths = markdownList(redacted.paths);
  const sourceTraces = markdownList(redacted.source_traces);
  const failureTypes = markdownList(redacted.failure_types);
  const acceptanceChecks = markdownList([
    "Replay the candidate before promotion.",
    "Promote only when baseline_failures > rerun_failures.",
    ...(requiredValidation ? [`Run ${requiredValidation} and record a passing validation result.`] : []),
    "Keep this artifact non-injectable until replay promotion succeeds.",
  ]);

  return [
    `# Candidate Skill: ${redacted.id}`,
    "",
    "Status: preview only. Not injectable until replay promotion succeeds.",
    "",
    "## Scope",
    redacted.scope ?? "repo",
    "",
    "## Trigger",
    redacted.trigger ?? "Unknown trigger.",
    "",
    "## Lesson",
    redacted.lesson ?? "No lesson recorded.",
    "",
    "## Proposed Injection",
    redacted.injection ?? "No injection recorded.",
    "",
    "## Failure Types",
    failureTypes,
    "",
    "## Evidence",
    evidence,
    "",
    "## Source Traces",
    sourceTraces,
    "",
    "## Paths",
    paths,
    "",
    "## Replay Requirement",
    redacted.promotion_required ?? "Replay before promotion.",
    "",
    "## Acceptance Checks",
    acceptanceChecks,
    "",
    "## Regeneration",
    `Command: ${artifact.command.join(" ")}`,
    "",
  ].join("\n");
}

function markdownList(values) {
  const items = Array.isArray(values) ? values.filter((value) => typeof value === "string" && value.trim().length > 0) : [];
  if (items.length === 0) {
    return "- None recorded.";
  }

  return items.map((item) => `- ${item}`).join("\n");
}

function deliveryReceiptFor({ sessionId, eventId, injections, contextBlock = "", issuedAt }) {
  const injectedPrecedentIds = uniqueStrings((injections ?? []).map((injection) => injection.id).filter(Boolean));
  const blockHash = contextBlockHash(contextBlock);
  if (!sessionId || !eventId || (injectedPrecedentIds.length === 0 && contextBlock.trim().length === 0)) {
    return null;
  }

  return {
    deliveryId: `del_${stableHash({ sessionId, eventId, injectedPrecedentIds, contextBlockHash: blockHash }).slice(0, 20)}`,
    sessionId,
    eventId,
    injectedPrecedentIds,
    contextBlockHash: blockHash,
    issuedAt,
    expiresAt: new Date(Date.parse(issuedAt) + runtimeConfig.retentionDays * 24 * 60 * 60 * 1000).toISOString(),
  };
}

function contextBlockHash(contextBlock) {
  return sha256Text(typeof contextBlock === "string" ? contextBlock : "");
}

function warrantForContext({ sessionId, eventId, issuedAt, task, context, matches, candidateHints, deliveryReceipt, turnDirectives }) {
  const directives = turnDirectives ?? emptyTurnDirectives();
  const allowed = {
    paths: warrantAllowedPaths(matches, context, directives),
    maxFiles: directives.noEdit ? 0 : Number(args["max-files"] ?? 6),
    maxLinesChanged: Number(args["max-lines-changed"] ?? 400),
  };
  const requiredEvidence = warrantRequiredEvidence(matches);
  const sources = {
    precedentIds: matches.map((match) => match.id),
    candidateIds: candidateHints.map((hint) => hint.candidateId),
    deliveryId: deliveryReceipt?.deliveryId ?? null,
  };
  const warrantId = `wrn_${stableHash({
    sessionId,
    eventId,
    task,
    scope: context.scope || null,
    changedFiles: context.changedFiles,
    allowed,
    requiredEvidence,
    sources,
  }).slice(0, 20)}`;

  return redactSecretsDeep({
    schema_version: "precedent.warrant.v1",
    ok: true,
    warrantId,
    sessionId,
    eventId,
    issuedAt,
    expiresAfterHook: "outcome.after_task",
    task,
    scope: context.scope || null,
    changedFiles: context.changedFiles,
    contextBlock: formatInjectionBlock(matches),
    allowed,
    requiredEvidence,
    turnDirectives: directives,
    forbidden: [
      ...(directives.noEdit ? [{
        type: "no_edit",
        message: "Do not edit files in this turn.",
      }] : []),
      {
        type: "path_escape",
        message: allowed.paths.length > 0
          ? `Do not modify paths outside ${allowed.paths.join(", ")}.`
          : "Do not expand beyond the task scope without explicit evidence.",
      },
      ...(requiredEvidence.length > 0 ? [{
        type: "missing_validation",
        message: `Do not close the task without ${requiredEvidence.map((item) => item.command).join(", ")} evidence.`,
      }] : []),
    ],
    sources,
    deliveryReceipt,
    status: "issued",
  }).value;
}

function warrantAllowedPaths(matches, context, directives = emptyTurnDirectives()) {
  if (Array.isArray(directives.allowedPaths) && directives.allowedPaths.length > 0) {
    return uniqueStrings(directives.allowedPaths).slice(0, 12);
  }

  const guardPaths = matches.flatMap((match) => (Array.isArray(match.guards) ? match.guards : [])
    .filter((guard) => guard.type === "changed_files_within_paths")
    .flatMap((guard) => Array.isArray(guard.paths) ? guard.paths : []));
  const precedentPaths = matches.flatMap((match) => Array.isArray(match.paths) ? match.paths : []);
  const contextPaths = commonPathPrefixes(context.changedFiles ?? []);
  const scopePaths = context.scope ? pathsForScope(context.scope) : [];

  return uniqueStrings([
    ...guardPaths,
    ...precedentPaths,
    ...contextPaths,
    ...scopePaths,
  ]).slice(0, 12);
}

function warrantRequiredEvidence(matches) {
  const commands = uniqueStrings(matches.flatMap((match) => (Array.isArray(match.guards) ? match.guards : [])
    .filter((guard) => guard.type === "required_validation_command" && nonEmptyString(guard.command))
    .map((guard) => guard.command.trim())));

  return commands.map((command) => ({
    type: "validation_command",
    command,
    satisfiedBy: "validation.after_run",
  }));
}

function candidateHintQueue(candidates, precedents, stateDir) {
  const promotedIds = new Set(precedents.map((precedent) => precedent.id));
  const items = candidates
    .filter((candidate) => candidate.status === "candidate" && !promotedIds.has(candidate.id))
    .sort((left, right) => left.id.localeCompare(right.id))
    .map((candidate) => {
      const hint = formatCandidateHint(candidate, stateDir, "report");

      return {
        candidateId: hint.candidateId,
        status: hint.status,
        reason: hint.reason,
        scope: hint.scope,
        failureTypes: hint.failureTypes,
        sourceTraces: hint.sourceTraces,
        replayRequired: hint.replayRequired,
        readiness: hint.promotionTrial.readiness,
        blockers: hint.promotionTrial.blockers,
        command: hint.promotionTrial.command,
        artifact: hint.artifact,
      };
    });

  return {
    total: items.length,
    readyForReplay: items.filter((item) => item.readiness === "ready").length,
    readyForBaseline: items.filter((item) => item.readiness !== "needs_baseline_command").length,
    blocked: items.filter((item) => item.readiness !== "ready").length,
    artifactPreviews: items.filter((item) => item.artifact?.path).length,
    items,
  };
}

function candidateOverlapsContext(candidate, context) {
  if (candidate.scope && context.scope && candidate.scope === context.scope) {
    return true;
  }

  const candidatePrefixes = new Set([
    ...commonPathPrefixes(candidate.paths ?? []),
    ...(Array.isArray(candidate.paths) ? candidate.paths : []),
  ]);
  return commonPathPrefixes(context.changedFiles ?? [])
    .some((prefix) => candidatePrefixes.has(prefix));
}

function validationCommandFromEvidence(evidence) {
  const validationEvidence = Array.isArray(evidence)
    ? evidence.find((item) => /^successful validation: .+ exited 0$/u.test(item))
    : null;
  return validationEvidence?.replace(/^successful validation: /u, "").replace(/ exited 0$/u, "") ?? null;
}

function suppressLifecycleInjections({ events, matches, includeStale }) {
  const selected = [];
  const suppressed = [];

  for (const match of matches) {
    const lifecycle = lifecycleForPrecedent(events, match.id);
    if (lifecycle.status === "retired") {
      suppressed.push({
        ...match,
        suppressionReason: lifecycle.retireReasons.some((reason) => reason.includes("repair failure"))
          ? "retired_repair_efficacy"
          : "retired",
      });
      continue;
    }
    if (lifecycle.status === "stale" && !includeStale) {
      suppressed.push({
        ...match,
        suppressionReason: lifecycle.retireReasons.some((reason) => reason.includes("repair failure"))
          ? "stale_repair_efficacy"
          : "stale",
      });
      continue;
    }

    selected.push(match);
  }

  return { matches: selected, suppressed };
}

async function suppressRepeatedSessionInjections({ stateDir, sessionId, matches, allowRepeat }) {
  if (!sessionId || allowRepeat || matches.length === 0) {
    return { matches, suppressed: [] };
  }

  const priorEvents = await readSessionEvents(stateDir, sessionId);
  const priorInjectedIds = new Set(
    priorEvents
      .filter((event) => event.hook === "context.before_turn" || event.hook === "context.export")
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

  const source = sourceForTrace(trace);
  return {
    ...source,
    replayId: source.replayId ?? precedent.replay?.id ?? null,
    replayPath: source.replayPath ?? precedent.replay?.path ?? null,
  };
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
  const receipt = precedent.replay ?? null;

  return {
    baselineFailures: Number.isFinite(baselineFailures) ? baselineFailures : null,
    rerunFailures: Number.isFinite(rerunFailures) ? rerunFailures : null,
    failureDelta: Number.isFinite(baselineFailures) && Number.isFinite(rerunFailures)
      ? baselineFailures - rerunFailures
      : null,
    baselineExitCode,
    rerunExitCode,
    receipt,
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

function outcomeSummaryForPrecedent(events, id) {
  const injections = injectionEventsForPrecedent(events, id);
  const suppressions = events.filter((event) =>
    Array.isArray(event.suppressedInjections)
    && event.suppressedInjections.some((item) => item.id === id),
  );
  const revisionBriefCount = events.filter((event) =>
    Array.isArray(event.revisionBriefs)
    && event.revisionBriefs.some((item) => item.id === id),
  ).length;
  const promotionTrialCount = events.filter((event) =>
    Array.isArray(event.promotionTrials)
    && event.promotionTrials.some((item) => Array.isArray(item.replaces) && item.replaces.includes(id)),
  ).length;
  const guardChecks = guardChecksForPrecedent(events, id);
  const guardPasses = guardChecks.filter((check) => check.status === "pass");
  const guardWarnings = guardChecks.filter((check) => check.status === "warn");
  const lastGuard = guardChecks.at(-1);
  const outcomes = events.filter((event) =>
    event.hook === "outcome.after_task"
    && Array.isArray(event.attributedPrecedents)
    && event.attributedPrecedents.includes(id),
  );
  const successes = outcomes.filter((event) => event.success === true);
  const failures = outcomes.filter((event) => event.success === false);
  const lastOutcome = outcomes.at(-1);
  const repairReceipts = repairReceiptEventsForPrecedent(events, id);
  const repairCleared = repairReceipts.filter((event) => event.repairReceipt.cleared === true);
  const repairStillFailing = repairReceipts.filter((event) => event.repairReceipt.cleared === false);
  const recentRepairFailures = recentRepairFailuresForPrecedent(events, id);
  const lastRepairCleared = repairCleared.at(-1);
  const lastRepairFailed = repairStillFailing.at(-1);
  const lastRepair = repairReceipts.at(-1);
  const lifecycle = lifecycleForPrecedent(events, id);
  const counterexamples = counterexamplesForPrecedent(events, id);
  const lastSuccess = successes.at(-1);
  const lastFailure = failures.at(-1);
  const lastCounterexample = counterexamples.at(-1);

  return {
    status: lifecycle.status,
    injectionCount: injections.length,
    successCount: successes.length,
    failureCount: failures.length,
    suppressionCount: suppressions.length,
    revisionBriefCount,
    promotionTrialCount,
    guardPassCount: guardPasses.length,
    guardWarningCount: guardWarnings.length,
    repairAttemptCount: repairReceipts.length,
    repairClearedCount: repairCleared.length,
    repairFailedCount: repairStillFailing.length,
    repairStillFailingCount: repairStillFailing.length,
    repairStillFailingSinceLastClearOrSuccessCount: recentRepairFailures.length,
    counterexampleCount: counterexamples.length,
    failureRate: rate(failures.length, outcomes.length),
    guardWarningRate: rate(guardWarnings.length, guardChecks.length),
    repairSuccessRate: rate(repairCleared.length, repairReceipts.length),
    lastSuccessAt: lastSuccess?.receivedAt ?? lastSuccess?.observedAt ?? null,
    lastFailureAt: lastFailure?.receivedAt ?? lastFailure?.observedAt ?? null,
    lastGuardAt: lastGuard?.observedAt ?? null,
    lastOutcomeAt: lastOutcome?.receivedAt ?? lastOutcome?.observedAt ?? null,
    lastRepairAt: lastRepair?.receivedAt ?? lastRepair?.observedAt ?? null,
    lastRepairClearedAt: lastRepairCleared?.receivedAt ?? lastRepairCleared?.observedAt ?? null,
    lastRepairFailedAt: lastRepairFailed?.receivedAt ?? lastRepairFailed?.observedAt ?? null,
    lastCounterexampleAt: lastCounterexample?.timestamp ?? null,
    retireReasons: lifecycle.retireReasons,
  };
}

function counterexamplesForPrecedent(events, id) {
  const repairRelatedSessionIds = new Set(
    events
      .filter((event) =>
        event.hook === "repair.after_retry"
        && Array.isArray(event.attributedPrecedents)
        && event.attributedPrecedents.includes(id)
        && event.repairReceipt)
      .flatMap((event) => [event.repairReceipt.repairSessionId, event.repairReceipt.retrySessionId])
      .filter(Boolean),
  );
  const outcomeCounterexamples = events
    .filter((event) =>
      event.hook === "outcome.after_task"
      && event.success === false
      && Array.isArray(event.attributedPrecedents)
      && event.attributedPrecedents.includes(id))
    .map((event) => ({
      type: "attributed_failure",
      sessionId: event.sessionId ?? null,
      timestamp: event.receivedAt ?? event.observedAt ?? null,
      reason: event.status ?? "failed_outcome",
      changedFiles: Array.isArray(event.changedFiles) ? event.changedFiles : [],
      command: null,
      repairId: null,
    }));
  const guardCounterexamples = guardChecksForPrecedent(events, id)
    .filter((check) => check.status === "warn" && !repairRelatedSessionIds.has(check.sessionId))
    .map((check) => ({
      type: "guard_warning",
      sessionId: check.sessionId ?? null,
      timestamp: check.observedAt ?? null,
      reason: check.guardId ?? "guard_warning",
      changedFiles: guardEvidenceFiles(check.evidence),
      command: check.evidence?.command ?? null,
      repairId: null,
    }));
  const repairCounterexamples = events
    .filter((event) =>
      event.hook === "repair.after_retry"
      && Array.isArray(event.attributedPrecedents)
      && event.attributedPrecedents.includes(id)
      && event.repairReceipt
      && (event.repairReceipt.repairResolved !== true || event.repairReceipt.cleared === false))
    .map((event) => ({
      type: event.repairReceipt.repairResolved === true ? "repair_still_failing" : "repair_unresolved",
      sessionId: event.sessionId ?? event.repairReceipt.retrySessionId ?? null,
      timestamp: event.receivedAt ?? event.observedAt ?? null,
      reason: event.repairReceipt.repairResolved === true
        ? "still_failing"
        : event.suppressedRepairs?.[0]?.reason ?? "unresolved",
      changedFiles: [],
      command: null,
      repairId: event.repairReceipt.id ?? null,
    }));

  return [
    ...outcomeCounterexamples,
    ...guardCounterexamples,
    ...repairCounterexamples,
  ]
    .filter((item) => item.timestamp)
    .sort((left, right) => eventTime({ observedAt: left.timestamp }) - eventTime({ observedAt: right.timestamp }))
    .slice(-10);
}

function guardEvidenceFiles(evidence) {
  if (!Array.isArray(evidence)) {
    return [];
  }
  return evidence.filter((item) => typeof item === "string" && item.includes("/"));
}

function lifecycleForPrecedent(events, id) {
  const outcomes = events.filter((event) =>
    event.hook === "outcome.after_task"
    && Array.isArray(event.attributedPrecedents)
    && event.attributedPrecedents.includes(id),
  );
  const successes = outcomes.filter((event) => event.success === true);
  const failures = outcomes.filter((event) => event.success === false);
  const repairRetrySessionIds = new Set(
    repairReceiptEventsForPrecedent(events, id)
      .map((event) => event.repairReceipt.retrySessionId)
      .filter(Boolean),
  );
  const guardWarnings = guardChecksForPrecedent(events, id)
    .filter((check) => check.status === "warn" && !repairRetrySessionIds.has(check.sessionId));
  const resetAt = repairResetTimeForPrecedent(events, id);
  const recentFailures = failures.filter((event) => eventTime(event) > resetAt).length;
  const recentGuardWarnings = guardWarnings.filter((check) => eventTime(check) > resetAt).length;
  const recentRepairFailures = recentRepairFailuresForPrecedent(events, id).length;
  const signalCount = Math.max(recentFailures + recentGuardWarnings, recentRepairFailures);
  const retireReasons = [];

  if (recentFailures > 0) {
    retireReasons.push(`${recentFailures} attributed failure(s) since last success`);
  }
  if (recentGuardWarnings > 0) {
    retireReasons.push(`${recentGuardWarnings} guard warning(s) since last success`);
  }
  if (recentRepairFailures > 0) {
    retireReasons.push(`${recentRepairFailures} repair failure(s) since last success`);
  }

  if (signalCount >= RETIRE_SIGNAL_THRESHOLD) {
    return { status: "retired", retireReasons };
  }
  if (signalCount >= STALE_SIGNAL_THRESHOLD) {
    return { status: "stale", retireReasons };
  }

  return { status: "active", retireReasons: [] };
}

function repairReceiptEventsForPrecedent(events, id) {
  return events.filter((event) =>
    event.hook === "repair.after_retry"
    && Array.isArray(event.attributedPrecedents)
    && event.attributedPrecedents.includes(id)
    && event.repairReceipt
    && event.repairReceipt.repairResolved === true,
  );
}

function repairSuppressionReasonsForCandidate(events, candidate) {
  return candidate.attributedPrecedents.flatMap((id) => {
    const recentFailures = recentRepairFailuresForPrecedent(events, id);
    if (recentFailures.length < REPAIR_EFFICACY_SUPPRESSION_THRESHOLD) {
      return [];
    }

    return [{
      reason: "repair_efficacy_suppressed",
      id,
      repairStillFailingSinceLastClearOrSuccessCount: recentFailures.length,
      threshold: REPAIR_EFFICACY_SUPPRESSION_THRESHOLD,
    }];
  });
}

function recentRepairFailuresForPrecedent(events, id) {
  const receipts = repairReceiptEventsForPrecedent(events, id);
  const resetAt = repairResetTimeForPrecedent(events, id);
  return receipts.filter((event) => event.repairReceipt.cleared === false && eventTime(event) > resetAt);
}

function repairResetTimeForPrecedent(events, id) {
  return Math.max(
    eventTime(repairReceiptEventsForPrecedent(events, id)
      .filter((event) => event.repairReceipt.cleared === true)
      .at(-1)),
    eventTime(events
      .filter((event) => event.hook === "outcome.after_task"
        && event.success === true
        && Array.isArray(event.attributedPrecedents)
        && event.attributedPrecedents.includes(id))
      .at(-1)),
  );
}

function repairHealthSummary(events, precedents) {
  const receipts = events.filter((event) => event.hook === "repair.after_retry" && event.repairReceipt);
  const suppressedRepairEvents = events.filter((event) =>
    event.hook === "repair.before_retry"
    && Array.isArray(event.suppressedRepairs)
    && event.suppressedRepairs.some((item) => item.reason === "repair_efficacy_suppressed")
  );
  const lifecycles = precedents.map((precedent) => lifecycleForPrecedent(events, precedent.id));
  const isRepairLifecycle = (lifecycle, status) =>
    lifecycle.status === status && lifecycle.retireReasons.some((reason) => reason.includes("repair failure"));

  return {
    attempts: receipts.length,
    cleared: receipts.filter((event) => event.repairReceipt.repairResolved === true && event.repairReceipt.cleared === true).length,
    stillFailing: receipts.filter((event) => event.repairReceipt.repairResolved === true && event.repairReceipt.cleared === false).length,
    unresolved: receipts.filter((event) => event.repairReceipt.repairResolved !== true).length,
    efficacySuppressed: suppressedRepairEvents.length,
    staleByRepair: lifecycles.filter((lifecycle) => isRepairLifecycle(lifecycle, "stale")).length,
    retiredByRepair: lifecycles.filter((lifecycle) => isRepairLifecycle(lifecycle, "retired")).length,
  };
}

async function warrantHealthSummary(stateDir) {
  const sessionEvents = (await runtimeSessionEntries(stateDir)).flatMap((entry) => entry.events);
  const warrantEvents = sessionEvents.filter((event) => event.warrant);
  const outcomeStatuses = sessionEvents
    .filter((event) => event.hook === "outcome.after_task" && event.warrantStatus)
    .map((event) => ({
      sessionId: event.sessionId,
      eventId: event.eventId ?? null,
      warrantId: event.warrantStatus.warrantId,
      status: event.warrantStatus.status,
      violations: event.warrantStatus.violations ?? [],
      missingEvidence: event.warrantStatus.missingEvidence ?? [],
    }));
  const needsAttention = outcomeStatuses.filter((item) => item.status === "violated" || item.status === "unresolved");

  return {
    issued: warrantEvents.length,
    closed: outcomeStatuses.length,
    satisfied: outcomeStatuses.filter((item) => item.status === "satisfied").length,
    violated: outcomeStatuses.filter((item) => item.status === "violated").length,
    unresolved: outcomeStatuses.filter((item) => item.status === "unresolved").length,
    needsAttention: needsAttention.length,
    recent: needsAttention.slice(-20),
  };
}

async function candidateArtifactHealth(stateDir, candidates) {
  const candidateIds = new Set(candidates.map((candidate) => candidate.id));
  const rendered = [];
  let stale = 0;

  for (const candidate of candidates) {
    const descriptor = artifactDescriptor(candidate, stateDir);
    try {
      const content = await readFile(descriptor.path, "utf8");
      const expected = renderCandidateSkill(candidate, descriptor);
      rendered.push({
        candidateId: candidate.id,
        path: descriptor.path,
        sha256: sha256Text(content),
        stale: content !== expected,
      });
      if (content !== expected) {
        stale += 1;
      }
    } catch (error) {
      if (error.code !== "ENOENT") {
        throw error;
      }
    }
  }

  const artifactDirs = await childDirs(join(stateDir, "artifacts"));
  const missingCandidate = artifactDirs
    .map((dir) => dir.split("/").at(-1))
    .filter((id) => id && !candidateIds.has(id));

  return {
    rendered: rendered.length,
    stale,
    missingCandidate: missingCandidate.length,
    items: rendered.slice(0, 20),
    missingCandidateIds: missingCandidate.slice(0, 20),
  };
}

async function runtimeWiringHealthSummary(stateDir, events) {
  const sessionEntries = await runtimeSessionEntries(stateDir);
  const knownDeliveryIds = new Set(sessionEntries
    .flatMap((entry) => entry.events)
    .map((event) => event.deliveryReceipt ?? event.contextPayload?.deliveryReceipt ?? null)
    .map((receipt) => receipt?.deliveryId)
    .filter(Boolean));
  const fallbackAttachments = events
    .filter((event) => event.type === "runtime_attach" && event.identity?.fallback === true)
    .map((event) => event.sessionId)
    .filter(Boolean);
  const missingEventIds = [];
  const unclosedInjectedSessions = [];
  const unattributedOutcomesAfterInjections = [];
  const unknownDeliveryIds = [];
  const unackedDeliveries = [];
  const mismatchedInjectionAcks = [];
  const rejectedInjectionAcks = [];

  for (const entry of sessionEntries) {
    const hookEvents = entry.events.filter((event) => typeof event.hook === "string");
    const injectedEvents = hookEvents.filter((event) => Array.isArray(event.injections) && event.injections.length > 0);
    const outcomeEvents = hookEvents.filter((event) => event.hook === "outcome.after_task");
    const contextDeliveries = hookEvents
      .filter((event) => event.hook === "context.before_turn" || event.hook === "context.export")
      .map((event) => event.deliveryReceipt ?? event.contextPayload?.deliveryReceipt ?? null)
      .filter((receipt) => receipt?.deliveryId && receipt.contextBlockHash);
    const ackEvents = hookEvents.filter((event) => event.hook === "context.after_inject" && event.contextInjectionAck);

    for (const event of hookEvents) {
      if (!event.eventId) {
        missingEventIds.push({
          sessionId: entry.sessionId,
          hook: event.hook,
        });
      }

      if (event.deliveryId && !knownDeliveryIds.has(event.deliveryId)) {
        unknownDeliveryIds.push({
          sessionId: entry.sessionId,
          hook: event.hook,
          deliveryId: event.deliveryId,
        });
      }
    }

    for (const receipt of contextDeliveries) {
      const acks = ackEvents.filter((event) => event.contextInjectionAck.deliveryId === receipt.deliveryId);
      if (acks.length === 0) {
        unackedDeliveries.push({
          sessionId: entry.sessionId,
          deliveryId: receipt.deliveryId,
          eventId: receipt.eventId ?? null,
        });
        continue;
      }

      for (const ackEvent of acks) {
        const ack = ackEvent.contextInjectionAck;
        if (ack.status === "mismatch") {
          mismatchedInjectionAcks.push({
            sessionId: entry.sessionId,
            deliveryId: ack.deliveryId,
            expectedContextBlockHash: ack.expectedContextBlockHash,
            contextBlockHash: ack.contextBlockHash,
          });
        } else if (ack.status === "rejected") {
          rejectedInjectionAcks.push({
            sessionId: entry.sessionId,
            deliveryId: ack.deliveryId,
            reason: ack.reason ?? null,
          });
        }
      }
    }

    if (injectedEvents.length > 0 && outcomeEvents.length === 0) {
      unclosedInjectedSessions.push(entry.sessionId);
    }

    if (injectedEvents.length > 0 && outcomeEvents.some((event) =>
      !Array.isArray(event.attributedPrecedents) || event.attributedPrecedents.length === 0
    )) {
      unattributedOutcomesAfterInjections.push(entry.sessionId);
    }
  }

  return {
    sessions: sessionEntries.length,
    fallbackAttachments: uniqueStrings(fallbackAttachments).length,
    missingEventIds: missingEventIds.length,
    unclosedInjectedSessions: uniqueStrings(unclosedInjectedSessions).length,
    unattributedOutcomesAfterInjections: uniqueStrings(unattributedOutcomesAfterInjections).length,
    unknownDeliveryIds: unknownDeliveryIds.length,
    unackedDeliveries: unackedDeliveries.length,
    mismatchedInjectionAcks: mismatchedInjectionAcks.length,
    rejectedInjectionAcks: rejectedInjectionAcks.length,
    needsAttention: uniqueStrings(fallbackAttachments).length
      + missingEventIds.length
      + uniqueStrings(unclosedInjectedSessions).length
      + uniqueStrings(unattributedOutcomesAfterInjections).length
      + unknownDeliveryIds.length
      + unackedDeliveries.length
      + mismatchedInjectionAcks.length
      + rejectedInjectionAcks.length,
    details: {
      fallbackAttachments: uniqueStrings(fallbackAttachments),
      missingEventIds: missingEventIds.slice(0, 20),
      unclosedInjectedSessions: uniqueStrings(unclosedInjectedSessions).slice(0, 20),
      unattributedOutcomesAfterInjections: uniqueStrings(unattributedOutcomesAfterInjections).slice(0, 20),
      unknownDeliveryIds: unknownDeliveryIds.slice(0, 20),
      unackedDeliveries: unackedDeliveries.slice(0, 20),
      mismatchedInjectionAcks: mismatchedInjectionAcks.slice(0, 20),
      rejectedInjectionAcks: rejectedInjectionAcks.slice(0, 20),
    },
  };
}

async function runtimeSessionEntries(stateDir) {
  const entries = [];

  for (const sessionFile of await jsonFiles(join(stateDir, "sessions"), ".jsonl")) {
    const sessionId = sessionFile
      .slice(join(stateDir, "sessions").length + 1)
      .replace(/\.jsonl$/u, "");
    entries.push({
      sessionId,
      file: sessionFile,
      events: await readJsonLines(sessionFile),
    });
  }

  return entries;
}

function eventTime(event) {
  const timestamp = Date.parse(event?.receivedAt ?? event?.observedAt ?? "");
  return Number.isFinite(timestamp) ? timestamp : 0;
}

function rate(numerator, denominator) {
  return denominator > 0 ? numerator / denominator : 0;
}

function guardChecksForPrecedent(events, id) {
  return events
    .flatMap((event) => {
      const observedAt = event.receivedAt ?? event.observedAt ?? null;
      const hook = event.hook ?? null;
      const sessionId = event.sessionId ?? null;
      const guardResult = event.guardResult ?? {};

      return [
        ...guardChecksWithStatus(guardResult.passed, "pass", observedAt, hook, sessionId),
        ...guardChecksWithStatus(guardResult.failed, "warn", observedAt, hook, sessionId),
        ...guardChecksWithStatus(guardResult.pending, "unknown", observedAt, hook, sessionId),
        ...guardChecksWithStatus(guardResult.skipped, "unknown", observedAt, hook, sessionId),
      ];
    })
    .filter((check) => check.precedentId === id);
}

function guardChecksWithStatus(checks, status, observedAt, hook, sessionId) {
  if (!Array.isArray(checks)) {
    return [];
  }

  return checks.map((check) => ({
    ...check,
    status: check.status ?? status,
    observedAt,
    hook,
    sessionId,
  }));
}

async function activeInjectionIdsForSession(stateDir, sessionId) {
  const events = await readSessionEvents(stateDir, sessionId);
  const ids = [];

  for (const event of events) {
    if (event.hook === "outcome.after_task") {
      ids.length = 0;
      continue;
    }

    if (event.hook === "context.before_turn" || event.hook === "context.export") {
      ids.push(...(Array.isArray(event.injections) ? event.injections : []));
    }
  }

  return uniqueStrings(ids);
}

async function attributedPrecedentIdsForSession(stateDir, sessionId, explicitIds, deliveryId = null) {
  const knownIds = new Set((await readJsonLines(join(stateDir, "precedents.jsonl"))).map((precedent) => precedent.id));
  return uniqueStrings([
    ...(await activeInjectionIdsForSession(stateDir, sessionId)),
    ...(await precedentIdsForDelivery(stateDir, deliveryId)),
    ...parseListArg(explicitIds),
  ]).filter((id) => knownIds.has(id));
}

async function activePrecedentsForSessionOrAttribution(stateDir, sessionId, explicitIds, deliveryId = null) {
  const activeIds = new Set(await attributedPrecedentIdsForSession(stateDir, sessionId, explicitIds, deliveryId));
  if (activeIds.size === 0) {
    return [];
  }

  const precedents = await readJsonLines(join(stateDir, "precedents.jsonl"));
  return precedents.filter((precedent) => activeIds.has(precedent.id));
}

async function activePrecedentsForSession(stateDir, sessionId) {
  return activePrecedentsForSessionOrAttribution(stateDir, sessionId, []);
}

async function precedentIdsForDelivery(stateDir, deliveryId) {
  if (typeof deliveryId !== "string" || deliveryId.trim().length === 0) {
    return [];
  }

  const receipt = await findDeliveryReceipt(stateDir, deliveryId.trim());
  return Array.isArray(receipt?.injectedPrecedentIds) ? receipt.injectedPrecedentIds : [];
}

async function findDeliveryReceipt(stateDir, deliveryId) {
  for (const entry of await runtimeSessionEntries(stateDir)) {
    for (const event of entry.events) {
      const receipt = event.deliveryReceipt ?? event.contextPayload?.deliveryReceipt ?? null;
      if (receipt?.deliveryId === deliveryId) {
        return receipt;
      }
    }
  }

  return null;
}

function precedentsForDeliveryReceipt(precedents, receipt) {
  const byId = new Map(precedents.map((precedent) => [precedent.id, precedent]));
  const missing = [];
  const matches = [];

  for (const id of receipt.injectedPrecedentIds ?? []) {
    const precedent = byId.get(id);
    if (!precedent) {
      missing.push(id);
      continue;
    }

    matches.push({
      ...precedent,
      score: 0,
      matchReasons: [{
        type: "delivery_receipt",
        deliveryId: receipt.deliveryId,
      }],
      applicabilityReceipt: {
        status: "anchored",
        anchors: ["delivery_receipt"],
        required: ["delivery_receipt"],
      },
    });
  }

  if (missing.length > 0) {
    fail(`warrant --delivery-id references unknown precedent ids: ${missing.join(", ")}`);
  }

  return matches;
}

function contextInjectionAckFor({ deliveryId, receipt, inserted, contextBlockHash: receivedHash, reason }) {
  const expectedHash = receipt?.contextBlockHash ?? null;
  const status = !receipt
    ? "missing_delivery"
    : inserted !== true
      ? "rejected"
      : receivedHash !== expectedHash
        ? "mismatch"
        : "accepted";

  return {
    deliveryId,
    status,
    ok: status === "accepted",
    inserted,
    expectedContextBlockHash: expectedHash,
    contextBlockHash: receivedHash,
    reason: reason ?? (status === "accepted" ? null : status),
  };
}

async function findWarrant(stateDir, warrantId) {
  if (typeof warrantId !== "string" || warrantId.trim().length === 0) {
    return null;
  }

  for (const entry of await runtimeSessionEntries(stateDir)) {
    for (const event of entry.events) {
      if (event.warrant?.warrantId === warrantId) {
        return event.warrant;
      }
    }
  }

  return null;
}

function evaluateWarrantDiff(warrant, event) {
  if (!warrant) {
    return null;
  }

  const changedFiles = Array.isArray(event.changedFiles) ? event.changedFiles : [];
  const allowedPaths = Array.isArray(warrant.allowed?.paths) ? warrant.allowed.paths : [];
  const turnDirectives = warrant.turnDirectives ?? emptyTurnDirectives();
  const outsidePaths = allowedPaths.length > 0
    ? changedFiles.filter((file) => !allowedPaths.some((path) => pathMatchesGuardPath(file, path)))
    : [];
  const maxFiles = Number(warrant.allowed?.maxFiles);
  const maxLinesChanged = Number(warrant.allowed?.maxLinesChanged);
  const linesChanged = (Number.isFinite(event.linesAdded) ? event.linesAdded : 0)
    + (Number.isFinite(event.linesDeleted) ? event.linesDeleted : 0);
  const violations = [
    ...(turnDirectives.noEdit && changedFiles.length > 0 ? [{
      type: "no_edit",
      message: `Turn directive forbids file edits; changed files: ${changedFiles.join(", ")}`,
      evidence: changedFiles,
    }] : []),
    ...(outsidePaths.length > 0 ? [{
      type: "path_escape",
      message: `Changed files outside warrant paths: ${outsidePaths.join(", ")}`,
      evidence: outsidePaths,
    }] : []),
    ...(Number.isFinite(maxFiles) && changedFiles.length > maxFiles ? [{
      type: "max_files",
      message: `Changed ${changedFiles.length} files; warrant allows ${maxFiles}.`,
      evidence: changedFiles,
    }] : []),
    ...(Number.isFinite(maxLinesChanged) && linesChanged > maxLinesChanged ? [{
      type: "max_lines_changed",
      message: `Changed ${linesChanged} lines; warrant allows ${maxLinesChanged}.`,
      evidence: [`${linesChanged} lines changed`],
    }] : []),
  ];

  return {
    warrantId: warrant.warrantId,
    hook: "diff.after_edit",
    ok: violations.length === 0,
    status: violations.length > 0 ? "violated" : "passed",
    checked: true,
    violations,
    passed: violations.length === 0 ? [{
      type: "edit_boundary",
      message: "Diff stayed within warrant limits.",
      evidence: changedFiles,
    }] : [],
  };
}

function evaluateTurnDirectiveDiff(turnDirectives, event) {
  const directives = turnDirectives ?? emptyTurnDirectives();
  if (!directives.noEdit && directives.allowedPaths.length === 0) {
    return null;
  }

  const warrant = {
    warrantId: null,
    allowed: {
      paths: directives.allowedPaths,
      maxFiles: directives.noEdit ? 0 : Number.POSITIVE_INFINITY,
      maxLinesChanged: Number.POSITIVE_INFINITY,
    },
    turnDirectives: directives,
  };

  return evaluateWarrantDiff(warrant, event);
}

function mergeWarrantResults(primary, fallback) {
  if (!primary) {
    return fallback;
  }
  if (!fallback) {
    return primary;
  }

  const violations = uniqueBy([
    ...(Array.isArray(primary.violations) ? primary.violations : []),
    ...(Array.isArray(fallback.violations) ? fallback.violations : []),
  ], (item) => `${item.type}:${item.message}`);
  const passed = uniqueBy([
    ...(Array.isArray(primary.passed) ? primary.passed : []),
    ...(Array.isArray(fallback.passed) ? fallback.passed : []),
  ], (item) => `${item.type}:${item.message}`);

  return {
    ...primary,
    ok: violations.length === 0,
    status: violations.length > 0 ? "violated" : primary.status,
    violations,
    passed,
  };
}

function evaluateWarrantValidation(warrant, event) {
  if (!warrant) {
    return null;
  }

  const required = (Array.isArray(warrant.requiredEvidence) ? warrant.requiredEvidence : [])
    .filter((item) => item.type === "validation_command" && nonEmptyString(item.command));
  const satisfied = required.filter((item) =>
    String(event.command ?? "").includes(item.command) && event.exitCode === 0);

  return {
    warrantId: warrant.warrantId,
    hook: "validation.after_run",
    ok: satisfied.length === required.length,
    status: required.length === 0
      ? "not_required"
      : satisfied.length > 0
        ? "satisfied"
        : "pending",
    requiredEvidence: required,
    satisfiedEvidence: satisfied.map((item) => ({
      ...item,
      evidence: `${event.command} exited ${event.exitCode}`,
    })),
  };
}

async function warrantStatusForOutcome(stateDir, warrantId) {
  const warrant = await findWarrant(stateDir, warrantId);
  if (!warrant) {
    return null;
  }

  const relatedEvents = (await runtimeSessionEntries(stateDir))
    .flatMap((entry) => entry.events)
    .filter((event) => event.warrantId === warrant.warrantId);
  const violations = relatedEvents
    .filter((event) => event.warrantResult?.status === "violated")
    .flatMap((event) => event.warrantResult.violations ?? []);
  const satisfiedCommands = new Set(relatedEvents
    .flatMap((event) => event.warrantResult?.satisfiedEvidence ?? [])
    .map((item) => item.command)
    .filter(Boolean));
  const required = (Array.isArray(warrant.requiredEvidence) ? warrant.requiredEvidence : [])
    .filter((item) => item.type === "validation_command" && nonEmptyString(item.command));
  const missingEvidence = required.filter((item) => !satisfiedCommands.has(item.command));
  const status = violations.length > 0
    ? "violated"
    : missingEvidence.length === 0
      ? "satisfied"
      : "unresolved";

  return {
    warrantId: warrant.warrantId,
    status,
    ok: status === "satisfied",
    violations,
    missingEvidence,
    satisfiedEvidence: [...satisfiedCommands].map((command) => ({ type: "validation_command", command })),
  };
}

async function finalizationWarrant(stateDir, sessionEvents, explicitWarrantId) {
  if (nonEmptyString(explicitWarrantId)) {
    return findWarrant(stateDir, explicitWarrantId);
  }

  const latestIssued = sessionEvents
    .filter((event) => event.warrant?.warrantId)
    .at(-1);

  if (latestIssued?.warrant) {
    return latestIssued.warrant;
  }

  const latestReferencedId = sessionEvents
    .map((event) => event.warrantId)
    .filter(nonEmptyString)
    .at(-1);

  return latestReferencedId ? findWarrant(stateDir, latestReferencedId) : null;
}

function finalizeSessionDecision({ sessionEvents, warrant }) {
  const turnEvents = eventsSinceLastOutcome(sessionEvents);
  const warrantId = warrant?.warrantId ?? null;
  const relatedEvents = warrantId
    ? turnEvents.filter((event) => event.warrantId === warrantId || event.warrant?.warrantId === warrantId)
    : turnEvents;
  const warrantViolations = relatedEvents
    .filter((event) => event.warrantResult?.status === "violated")
    .flatMap((event) => event.warrantResult.violations ?? []);
  const guardFailures = relatedEvents.flatMap((event) => event.guardResult?.failed ?? []);
  const validationGuardFailures = guardFailures.filter((item) => item.type === "required_validation_command");
  const repairGuardFailures = guardFailures.filter((item) => item.type !== "required_validation_command");

  if (warrantViolations.length > 0 || repairGuardFailures.length > 0) {
    return {
      decision: "repair",
      status: "blocked",
      reason: "repair_required_before_response",
      nextAction: {
        type: "repair_retry",
        followUpHook: "repair.before_retry",
        refinalize: true,
      },
      warrantId,
      missingEvidence: [],
      violations: warrantViolations,
      guardFailures: repairGuardFailures,
    };
  }

  const requiredEvidence = (Array.isArray(warrant?.requiredEvidence) ? warrant.requiredEvidence : [])
    .filter((item) => item.type === "validation_command" && nonEmptyString(item.command));
  const satisfiedCommands = new Set(relatedEvents
    .flatMap((event) => event.warrantResult?.satisfiedEvidence ?? [])
    .map((item) => item.command)
    .filter(Boolean));
  for (const item of requiredEvidence) {
    if (relatedEvents.some((event) =>
      event.hook === "validation.after_run"
      && String(event.command ?? "").includes(item.command)
      && event.exitCode === 0)) {
      satisfiedCommands.add(item.command);
    }
  }
  const missingEvidence = requiredEvidence.filter((item) => !satisfiedCommands.has(item.command));
  const missingGuardEvidence = validationGuardFailures
    .map((item) => guardValidationEvidence(item))
    .filter(Boolean)
    .filter((item) => !satisfiedCommands.has(item.command));
  const allMissingEvidence = uniqueBy(
    [...missingEvidence, ...missingGuardEvidence],
    (item) => `${item.type}:${item.command}`,
  );
  const latestValidation = relatedEvents
    .filter((event) => event.hook === "validation.after_run")
    .at(-1);

  if (allMissingEvidence.length > 0 || (latestValidation && latestValidation.exitCode !== 0)) {
    return {
      decision: "validate",
      status: "blocked",
      reason: allMissingEvidence.length > 0 ? "missing_required_validation" : "latest_validation_failed",
      nextAction: {
        type: "run_validation",
        commands: allMissingEvidence.map((item) => item.command).filter(Boolean),
        followUpHook: "validation.after_run",
        refinalize: true,
      },
      warrantId,
      missingEvidence: allMissingEvidence,
      violations: [],
      guardFailures: validationGuardFailures,
      latestValidation: latestValidation
        ? {
          command: latestValidation.command,
          exitCode: latestValidation.exitCode,
        }
        : null,
    };
  }

  return {
    decision: "ready",
    status: "ready",
    reason: "final_response_ready",
    nextAction: {
      type: "respond",
    },
    warrantId,
    missingEvidence: [],
    violations: [],
    guardFailures: [],
  };
}

function guardValidationEvidence(item) {
  const expected = (Array.isArray(item.evidence) ? item.evidence : [])
    .find((entry) => typeof entry === "string" && entry.startsWith("expected "));
  const command = expected?.slice("expected ".length).trim();
  return command ? { type: "validation_command", command } : null;
}

function eventsSinceLastOutcome(events) {
  const lastOutcomeIndex = events.findLastIndex((event) => event.hook === "outcome.after_task");
  return lastOutcomeIndex >= 0 ? events.slice(lastOutcomeIndex + 1) : events;
}

function evaluatePrecedentGuards(precedents, hook, event) {
  const result = emptyGuardResult();

  for (const precedent of precedents) {
    for (const guard of Array.isArray(precedent.guards) ? precedent.guards : []) {
      if (!SUPPORTED_GUARD_TYPES.has(guard.type)) {
        result.skipped.push(formatGuardCheck({
          precedent,
          guard,
          status: "unknown",
          message: guard.message ?? `Unsupported guard type: ${guard.type}`,
          evidence: [],
        }));
        continue;
      }

      if (guard.type === "changed_files_within_paths" && hook === "diff.after_edit") {
        const allowedPaths = Array.isArray(guard.paths) ? guard.paths : [];
        const changedFiles = Array.isArray(event.changedFiles) ? event.changedFiles : [];
        const outsidePaths = changedFiles.filter((file) => !allowedPaths.some((path) => pathMatchesGuardPath(file, path)));

        if (outsidePaths.length > 0) {
          result.failed.push(formatGuardCheck({
            precedent,
            guard,
            status: "warn",
            message: guard.message ?? `Keep edits inside ${allowedPaths.join(", ")}.`,
            evidence: outsidePaths,
          }));
        } else {
          result.passed.push(formatGuardCheck({
            precedent,
            guard,
            status: "pass",
            message: guard.message ?? `Changed files are inside ${allowedPaths.join(", ")}.`,
            evidence: changedFiles,
          }));
        }
        continue;
      }

      if (guard.type === "required_validation_command" && hook === "validation.after_run") {
        const command = typeof guard.command === "string" ? guard.command : "";
        const allowedExitCodes = Array.isArray(guard.allowedExitCodes) ? guard.allowedExitCodes : [0];

        if (command && String(event.command ?? "").includes(command) && allowedExitCodes.includes(event.exitCode)) {
          result.passed.push(formatGuardCheck({
            precedent,
            guard,
            status: "pass",
            message: guard.message ?? `Validation command passed: ${command}.`,
            evidence: [`${event.command} exited ${event.exitCode}`],
          }));
        } else {
          result.failed.push(formatGuardCheck({
            precedent,
            guard,
            status: "warn",
            message: guard.message ?? `Run ${command}.`,
            evidence: [`expected ${command}`, `actual ${event.command ?? "(missing)"} exited ${event.exitCode}`],
          }));
        }
        continue;
      }

      result.pending.push(formatGuardCheck({
        precedent,
        guard,
        status: "unknown",
        message: guard.message ?? `Guard ${guard.id ?? guard.type} waits for ${guardHookForType(guard.type)}.`,
        evidence: [],
      }));
    }
  }

  result.checked = result.passed.length + result.failed.length + result.pending.length + result.skipped.length;
  result.ok = result.failed.length === 0;
  result.decision = result.failed.length > 0 ? "feedback" : "none";
  return result;
}

function emptyGuardResult() {
  return {
    ok: true,
    decision: "none",
    checked: 0,
    passed: [],
    failed: [],
    pending: [],
    skipped: [],
  };
}

function pathMatchesGuardPath(file, guardPath) {
  return file === guardPath || file.startsWith(`${guardPath}/`);
}

function formatGuardCheck({ precedent, guard, status, message, evidence }) {
  return {
    id: guard.id ?? null,
    precedentId: precedent.id,
    guardId: guard.id ?? null,
    type: guard.type,
    status,
    severity: guard.severity ?? "warning",
    message,
    evidence,
  };
}

function guardHookForType(type) {
  if (type === "changed_files_within_paths") {
    return "diff.after_edit";
  }

  if (type === "required_validation_command") {
    return "validation.after_run";
  }

  return "a supported hook";
}

function formatGuardContextBlock(failedChecks) {
  if (failedChecks.length === 0) {
    return "";
  }

  return [
    "Precedent guard:",
    ...failedChecks.map((check) => `- ${check.message}`),
  ].join("\n");
}

function formatWarrantContextBlock(warrantResult) {
  const violations = Array.isArray(warrantResult?.violations) ? warrantResult.violations : [];
  if (violations.length === 0) {
    return "";
  }

  return [
    "Precedent directive repair:",
    ...violations.map((violation) => `- ${violation.message}`),
  ].join("\n");
}

function formatFinalizeContextBlock(finalization) {
  if (finalization.decision === "ready") {
    return "";
  }

  if (finalization.decision === "validate") {
    const commands = finalization.missingEvidence
      .map((item) => item.command)
      .filter(Boolean);
    const latest = finalization.latestValidation?.command
      ? [`Latest validation failed: ${finalization.latestValidation.command} exited ${finalization.latestValidation.exitCode}.`]
      : [];
    return [
      "Precedent finalize:",
      "- Run required validation before the final response.",
      ...commands.map((command) => `- Required command: ${command}`),
      ...latest.map((line) => `- ${line}`),
    ].join("\n");
  }

  return [
    "Precedent finalize:",
    "- Repair the turn before the final response.",
    ...finalization.violations.map((item) => `- Warrant violation: ${item.message}`),
    ...finalization.guardFailures.map((item) => `- Guard warning: ${item.message}`),
  ].join("\n");
}

function diffChangedFiles(event) {
  return uniqueStrings([
    ...(Array.isArray(event.changedFiles) ? event.changedFiles : parseListArg(event.changedFiles)),
    ...changedFilesFromDiffSummary(event.diffSummary),
    ...changedFilesFromUnifiedDiff(event.unifiedDiff ?? event.diff),
  ]);
}

function changedFilesFromDiffSummary(value) {
  if (!value) {
    return [];
  }

  if (Array.isArray(value)) {
    return value.flatMap((item) => changedFilesFromDiffSummary(item));
  }

  if (typeof value === "object") {
    return uniqueStrings([
      ...parseListArg(value.changedFiles),
      ...parseListArg(value.files),
      ...(typeof value.path === "string" ? [value.path] : []),
      ...(typeof value.file === "string" ? [value.file] : []),
    ]);
  }

  if (typeof value !== "string") {
    return [];
  }

  return value
    .split(/\r?\n/u)
    .map((line) => line.split("|", 1)[0].trim())
    .filter((path) => path.length > 0 && !path.startsWith(" "))
    .filter((path) => !/^\d+\s+files?\s+changed/u.test(path));
}

function changedFilesFromUnifiedDiff(value) {
  if (typeof value !== "string" || value.trim().length === 0) {
    return [];
  }

  const files = [];
  for (const line of value.split(/\r?\n/u)) {
    const match = line.match(/^diff --git a\/(.+?) b\/(.+)$/u);
    if (match) {
      files.push(match[2]);
      continue;
    }

    const newFile = line.match(/^\+\+\+ b\/(.+)$/u);
    if (newFile && newFile[1] !== "/dev/null") {
      files.push(newFile[1]);
    }
  }
  return uniqueStrings(files);
}

function repairPromptForDiffGuard({ guardResult, activePrecedents, changedFiles, diffSummary, unifiedDiff }) {
  const failed = Array.isArray(guardResult.failed) ? guardResult.failed[0] : null;
  if (!failed) {
    return null;
  }

  const precedent = activePrecedents.find((item) => item.id === failed.precedentId);
  if (!precedent) {
    return null;
  }

  const suggestedValidation = suggestedValidationForPrecedent(precedent);
  const affectedPaths = uniqueStrings(Array.isArray(failed.evidence) && failed.evidence.length > 0 ? failed.evidence : changedFiles);
  return {
    precedentId: precedent.id,
    guardId: failed.guardId ?? null,
    matchReasons: uniqueStrings([
      failed.message,
      ...(Array.isArray(precedent.paths) ? precedent.paths.map((path) => `allowed path: ${path}`) : []),
      ...(diffSummary ? ["diff summary supplied"] : []),
      ...(unifiedDiff ? ["unified diff supplied"] : []),
    ]),
    affectedPaths,
    suggestedValidation,
    action: repairActionForGuard(failed, precedent, affectedPaths, suggestedValidation),
  };
}

function suggestedValidationForPrecedent(precedent) {
  const guard = (Array.isArray(precedent.guards) ? precedent.guards : [])
    .find((item) => item.type === "required_validation_command" && typeof item.command === "string" && item.command.trim().length > 0);
  return guard?.command ?? null;
}

function repairActionForGuard(failed, precedent, affectedPaths, suggestedValidation) {
  const allowedPaths = Array.isArray(precedent.paths) ? precedent.paths.join(", ") : "";
  const paths = affectedPaths.length > 0 ? affectedPaths.join(", ") : "the current edit";
  const validation = suggestedValidation ? ` Then run ${suggestedValidation}.` : "";
  const base = failed.message ?? precedent.injection ?? "Repair the edit to satisfy the active precedent.";
  return `${base} Rework ${paths}${allowedPaths ? ` so it stays within ${allowedPaths}` : ""}.${validation}`;
}

function formatRepairContextBlock(repairPrompt) {
  if (!repairPrompt) {
    return "";
  }

  const lines = [
    "Precedent repair:",
    `- ${repairPrompt.action}`,
    `- Precedent: ${repairPrompt.precedentId}`,
  ];
  if (repairPrompt.affectedPaths.length > 0) {
    lines.push(`- Affected paths: ${repairPrompt.affectedPaths.join(", ")}`);
  }
  if (repairPrompt.suggestedValidation) {
    lines.push(`- Suggested validation: ${repairPrompt.suggestedValidation}`);
  }
  return lines.join("\n");
}

function latestRepairCandidate(events) {
  const lastRepairAt = Math.max(
    0,
    ...events
      .filter((event) => event.hook === "repair.before_retry")
      .map(eventTime),
  );
  const candidates = events
    .filter((event) => lastRepairAt === 0 || eventTime(event) > lastRepairAt)
    .filter((event) => event.hook !== "repair.before_retry")
    .map(repairCandidateForEvent)
    .filter(Boolean)
    .sort((left, right) => eventTime(left.event) - eventTime(right.event));

  return candidates.at(-1) ?? null;
}

function repairIdForCandidate(sessionId, candidate) {
  return `repair_${stableHash({
    sessionId,
    source: candidate.repairSource,
    block: candidate.repairBlock,
  }).slice(0, 16)}`;
}

async function findRepairBeforeRetryEvent(stateDir, repairId, repairSessionId) {
  if (repairSessionId) {
    return (await readSessionEvents(stateDir, repairSessionId))
      .find((event) => event.hook === "repair.before_retry" && event.repairId === repairId) ?? null;
  }

  const event = (await readJsonLines(join(stateDir, "events.jsonl")))
    .find((item) => item.hook === "repair.before_retry" && item.repairId === repairId);
  if (!event?.sessionId) {
    return event ?? null;
  }

  return (await readSessionEvents(stateDir, event.sessionId))
    .find((item) => item.hook === "repair.before_retry" && item.repairId === repairId) ?? event;
}

function repairReceiptKey({ repairId, repairSessionId }) {
  return `${repairId ?? ""}:${repairSessionId ?? ""}`;
}

function hasRepairRetryEvidence(events) {
  return events.some((event) => (
    event.hook === "validation.after_run"
    || event.hook === "diff.after_edit"
    || event.hook === "outcome.after_task"
  ));
}

function repairCandidateForEvent(event) {
  if (event.hook === "diff.after_edit" && event.repairPrompt) {
    return {
      event,
      repairBlock: event.contextBlock || formatRepairContextBlock(event.repairPrompt),
      repairSource: {
        hook: event.hook,
        receivedAt: event.receivedAt ?? null,
        kind: "diff_repair",
        guardId: event.repairPrompt.guardId ?? null,
      },
      attributedPrecedents: repairAttributedPrecedents(event),
    };
  }

  if (event.hook === "validation.after_run" && (event.exitCode !== 0 || hasFailedGuards(event))) {
    return {
      event,
      repairBlock: repairBlockForFailedValidation(event),
      repairSource: {
        hook: event.hook,
        receivedAt: event.receivedAt ?? null,
        kind: "failed_validation",
        command: event.command ?? null,
        exitCode: Number.isFinite(event.exitCode) ? event.exitCode : null,
      },
      attributedPrecedents: repairAttributedPrecedents(event),
    };
  }

  if (event.hook === "outcome.after_task" && event.success === false) {
    return {
      event,
      repairBlock: repairBlockForFailedOutcome(event),
      repairSource: {
        hook: event.hook,
        receivedAt: event.receivedAt ?? null,
        kind: "failed_outcome",
        status: event.status ?? null,
      },
      attributedPrecedents: repairAttributedPrecedents(event),
    };
  }

  return null;
}

function repairBlockForFailedValidation(event) {
  const lines = [
    "Precedent repair:",
    `- Validation failed: ${event.command ?? "validation command"}${Number.isFinite(event.exitCode) ? ` exited ${event.exitCode}` : ""}.`,
  ];
  const signals = Array.isArray(event.failureSignals) ? event.failureSignals : [];
  if (signals.length > 0) {
    lines.push(`- Failure signals: ${signals.slice(0, 3).join(", ")}`);
  }
  const summary = event.stderrSummary || event.stdoutSummary;
  if (typeof summary === "string" && summary.trim().length > 0) {
    lines.push(`- Evidence: ${summary.trim()}`);
  }
  lines.push("- Repair: Fix the validation failure, then rerun the same validation.");
  return lines.join("\n");
}

function repairBlockForFailedOutcome(event) {
  const lines = [
    "Precedent repair:",
    `- Outcome failed: ${event.status ?? "failure"}.`,
  ];
  if (typeof event.notes === "string" && event.notes.trim().length > 0) {
    lines.push(`- Evidence: ${summarizeText(event.notes)}`);
  }
  if (Array.isArray(event.changedFiles) && event.changedFiles.length > 0) {
    lines.push(`- Changed files: ${event.changedFiles.slice(0, 5).join(", ")}`);
  }
  if (Number.isFinite(event.retries)) {
    lines.push(`- Retry: ${event.retries}`);
  }
  lines.push("- Repair: Address the failed outcome before continuing.");
  return lines.join("\n");
}

function idleSummary(idle) {
  const promotion = idle?.promotion ?? null;
  const finalization = idle?.finalization ?? null;
  return {
    status: idle?.status ?? "unknown",
    reason: idle?.reason ?? null,
    promotionProcessed: Number.isFinite(promotion?.processed) ? promotion.processed : 0,
    promotionQueue: promotion?.queue
      ? {
        total: promotion.queue.total,
        ready: promotion.queue.ready,
        blocked: promotion.queue.blocked,
        running: promotion.queue.running,
        completed: promotion.queue.completed,
        failed: promotion.queue.failed,
      }
      : null,
    finalization: finalization
      ? {
        status: finalization.status,
        reason: finalization.reason ?? null,
        decision: finalization.decision ?? null,
        recorded: finalization.recorded ?? false,
        deduped: finalization.deduped ?? false,
      }
      : null,
  };
}

async function runIdleFinalization({ stateDir, sessionId, eventId, warrantId }) {
  let result = null;

  await withStateLock(stateDir, async () => {
    await ensureState(stateDir);
    const sessionEvents = await readSessionEvents(stateDir, sessionId);
    const plan = await idleFinalizationPlan({
      stateDir,
      sessionEvents,
      explicitWarrantId: warrantId,
    });

    if (!plan.needed) {
      result = {
        status: "not_needed",
        reason: plan.reason,
        decision: null,
        nextAction: null,
        finalization: null,
        contextBlock: "",
        recorded: false,
        deduped: false,
        sessionEventPath: null,
      };
      return;
    }

    const sessionEvent = await appendSessionEvent(stateDir, {
      type: "hook_event",
      receivedAt: new Date().toISOString(),
      hook: "finalize.before_response",
      sessionId,
      ...eventIdField(eventId),
      warrantId: plan.warrant?.warrantId ?? null,
      finalization: plan.finalization,
      contextBlock: plan.contextBlock,
      source: {
        hook: "orchestration.after_idle",
        reason: "missing_finalization",
      },
    });

    if (!sessionEvent.deduped) {
      await appendJsonLine(join(stateDir, "events.jsonl"), {
        type: "hook_event",
        receivedAt: sessionEvent.receivedAt,
        hook: "finalize.before_response",
        sessionId,
        ...eventIdField(eventId),
        warrantId: plan.warrant?.warrantId ?? null,
        finalization: plan.finalization,
        contextBlock: plan.contextBlock,
        source: {
          hook: "orchestration.after_idle",
          reason: "missing_finalization",
        },
      });
    }

    result = {
      status: plan.finalization.decision === "ready" ? "ready" : "blocked",
      reason: "missing_finalization",
      decision: plan.finalization.decision,
      nextAction: plan.finalization.nextAction,
      finalization: plan.finalization,
      contextBlock: plan.contextBlock,
      recorded: !sessionEvent.deduped,
      deduped: sessionEvent.deduped,
      sessionEventPath: sessionEvent.path,
    };
  }, { failOpen: true });

  return result ?? {
    status: "unavailable",
    reason: "lock_timeout",
    decision: null,
    nextAction: null,
    finalization: null,
    contextBlock: "",
    recorded: false,
    deduped: false,
    sessionEventPath: null,
  };
}

async function idleFinalizationPlan({ stateDir, sessionEvents, explicitWarrantId }) {
  const turnEvents = eventsSinceLastOutcome(sessionEvents);
  const latestTriggerIndex = turnEvents.findLastIndex((event) => FINALIZATION_TRIGGER_HOOKS.has(event.hook));
  if (latestTriggerIndex < 0) {
    return {
      needed: false,
      reason: "no_unfinished_turn",
    };
  }

  const latestFinalizationIndex = turnEvents.findLastIndex((event) => event.hook === "finalize.before_response");
  if (latestFinalizationIndex > latestTriggerIndex) {
    return {
      needed: false,
      reason: "already_finalized",
    };
  }

  const warrant = await finalizationWarrant(stateDir, sessionEvents, explicitWarrantId);
  const finalization = finalizeSessionDecision({
    sessionEvents,
    warrant,
  });

  return {
    needed: true,
    reason: "missing_finalization",
    warrant,
    finalization,
    contextBlock: formatFinalizeContextBlock(finalization),
  };
}

function hasFailedGuards(event) {
  return Array.isArray(event.guardResult?.failed) && event.guardResult.failed.length > 0;
}

function repairAttributedPrecedents(event) {
  return uniqueStrings([
    ...(Array.isArray(event.attributedPrecedents) ? event.attributedPrecedents : []),
    ...(event.repairPrompt?.precedentId ? [event.repairPrompt.precedentId] : []),
    ...guardPrecedentIds(event.guardResult),
  ]);
}

function guardPrecedentIds(guardResult) {
  if (!guardResult || typeof guardResult !== "object") {
    return [];
  }

  return uniqueStrings([
    ...guardPrecedentIdsFromChecks(guardResult.failed),
    ...guardPrecedentIdsFromChecks(guardResult.passed),
    ...guardPrecedentIdsFromChecks(guardResult.pending),
    ...guardPrecedentIdsFromChecks(guardResult.skipped),
  ]);
}

function guardPrecedentIdsFromChecks(checks) {
  return Array.isArray(checks) ? checks.map((check) => check.precedentId).filter(Boolean) : [];
}

function hookEventId(event) {
  return typeof event.eventId === "string" && event.eventId.trim().length > 0
    ? event.eventId.trim()
    : null;
}

function eventIdField(eventId) {
  return eventId ? { eventId } : {};
}

function repairSessionArg() {
  const value = args["repair-session-id"] ?? args["repair-session"];
  return typeof value === "string" && value.trim().length > 0
    ? value.trim()
    : null;
}

async function findSessionEventByEventId(stateDir, sessionId, eventId) {
  if (!sessionId || !eventId) {
    return null;
  }

  const path = join(stateDir, "sessions", `${safeFileName(sessionId)}.jsonl`);
  const event = (await readJsonLines(path)).find((item) => item.eventId === eventId);

  return event ? { path, event } : null;
}

async function appendSessionEvent(stateDir, rawEvent) {
  const sessionId = requireString(rawEvent.sessionId, "event.sessionId");
  const sessionFile = join(stateDir, "sessions", `${safeFileName(sessionId)}.jsonl`);
  const artifactDir = join(stateDir, "sessions", `${safeFileName(sessionId)}-artifacts`);
  const event = redactSecretsDeep(rawEvent).value;
  const eventId = hookEventId(event);

  if (eventId) {
    const existing = (await readJsonLines(sessionFile)).find((item) => item.eventId === eventId);

    if (existing) {
      return {
        sessionId,
        path: sessionFile,
        event: existing,
        receivedAt: existing.receivedAt,
        deduped: true,
      };
    }
  }

  if (typeof event.stdout === "string" && event.stdout.length > 0) {
    await mkdir(artifactDir, { recursive: true });
    const stdoutPath = join(artifactDir, `${Date.now()}-${event.hook.replaceAll(".", "_")}.stdout.txt`);
    await writeFileAtomic(stdoutPath, event.stdout);
    event.stdoutPath = stdoutPath;
    event.stdoutSummary = summarizeText(event.stdout);
    delete event.stdout;
  }

  if (typeof event.stderr === "string" && event.stderr.length > 0) {
    await mkdir(artifactDir, { recursive: true });
    const stderrPath = join(artifactDir, `${Date.now()}-${event.hook.replaceAll(".", "_")}.stderr.txt`);
    await writeFileAtomic(stderrPath, event.stderr);
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
    deduped: false,
  };
}

async function readSessionEvents(stateDir, sessionId) {
  if (!sessionId) {
    return [];
  }

  return readJsonLines(join(stateDir, "sessions", `${safeFileName(sessionId)}.jsonl`));
}

function contextFromSessionEvents(events, fallbackEvent = {}) {
  const contextTurns = events.filter((event) => event.hook === "context.before_turn" || event.hook === "context.export");
  const observations = events.filter((event) => event.hook === "conversation.observe");
  const diffs = events.filter((event) => event.hook === "diff.after_edit");
  const reviews = events.filter((event) => event.hook === "review.after_feedback");
  const outcomes = events.filter((event) => event.hook === "outcome.after_task");
  const lastContextTurn = contextTurns.at(-1) ?? {};
  const lastOutcome = outcomes.at(-1) ?? {};

  return {
    task: nonEmptyString(lastOutcome.task)
      ? lastOutcome.task
      : (lastContextTurn.task ?? fallbackEvent.task ?? ""),
    scope: nonEmptyString(lastOutcome.scope)
      ? lastOutcome.scope
      : (lastContextTurn.scope ?? fallbackEvent.scope ?? ""),
    changedFiles: uniqueStrings([
      ...contextTurns.flatMap((event) => Array.isArray(event.changedFiles) ? event.changedFiles : []),
      ...observations.flatMap((event) => Array.isArray(event.changedFiles) ? event.changedFiles : []),
      ...diffs.flatMap((event) => Array.isArray(event.changedFiles) ? event.changedFiles : []),
      ...reviews.flatMap((event) => Array.isArray(event.changedFiles) ? event.changedFiles : []),
      ...outcomes.flatMap((event) => Array.isArray(event.changedFiles) ? event.changedFiles : []),
      ...(Array.isArray(fallbackEvent.changedFiles) ? fallbackEvent.changedFiles : parseListArg(fallbackEvent.changedFiles)),
    ]),
  };
}

async function traceFromSession(stateDir, sessionId) {
  const sessionFile = join(stateDir, "sessions", `${safeFileName(sessionId)}.jsonl`);
  const events = await readJsonLines(sessionFile);

  if (events.length === 0) {
    fail(`session has no recorded hook events: ${sessionId}`);
  }

  const contextTurns = events.filter((event) => event.hook === "context.before_turn" || event.hook === "context.export");
  const observations = events.filter((event) => event.hook === "conversation.observe");
  const validations = events.filter((event) => event.hook === "validation.after_run");
  const diffs = events.filter((event) => event.hook === "diff.after_edit");
  const reviews = events.filter((event) => event.hook === "review.after_feedback");
  const outcomes = events.filter((event) => event.hook === "outcome.after_task");
  const receivedTimes = events
    .map((event) => Date.parse(event.receivedAt ?? ""))
    .filter((timestamp) => Number.isFinite(timestamp));
  const lastContextTurn = contextTurns.at(-1) ?? {};
  const lastOutcome = outcomes.at(-1) ?? {};
  const changedFiles = uniqueStrings([
    ...contextTurns.flatMap((event) => Array.isArray(event.changedFiles) ? event.changedFiles : []),
    ...observations.flatMap((event) => Array.isArray(event.changedFiles) ? event.changedFiles : []),
    ...diffs.flatMap((event) => Array.isArray(event.changedFiles) ? event.changedFiles : []),
    ...reviews.flatMap((event) => Array.isArray(event.changedFiles) ? event.changedFiles : []),
    ...outcomes.flatMap((event) => Array.isArray(event.changedFiles) ? event.changedFiles : []),
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
  const reviewFailures = reviews
    .flatMap((event) => Array.isArray(event.comments) ? event.comments : [])
    .map((comment) => `review: ${comment}`);
  const observationFailures = observations
    .flatMap((event) => Array.isArray(event.acceptedCorrectionSignals) ? event.acceptedCorrectionSignals : [])
    .map(formatCorrectionFailureForTrace);
  const guardFailures = events
    .flatMap((event) => Array.isArray(event.guardResult?.failed) ? event.guardResult.failed : [])
    .map(formatGuardFailureForTrace);
  const failures = [...validationFailures, ...diffFailures, ...reviewFailures, ...observationFailures, ...guardFailures, ...outcomeFailures];
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
  const reviewEvidence = reviews.length > 0
    ? {
      comments: reviews.flatMap((event) => Array.isArray(event.comments) ? event.comments : []),
      changedFiles: uniqueStrings(reviews.flatMap((event) => Array.isArray(event.changedFiles) ? event.changedFiles : [])),
    }
    : null;
  const observationEvidence = observations.length > 0
    ? {
      correctionSignals: observations.flatMap((event) => Array.isArray(event.correctionSignals) ? event.correctionSignals : []),
      acceptedCorrectionSignals: observations.flatMap((event) => Array.isArray(event.acceptedCorrectionSignals) ? event.acceptedCorrectionSignals : []),
      turnDirectiveSignals: observations.flatMap((event) => Array.isArray(event.turnDirectiveSignals) ? event.turnDirectiveSignals : []),
      acceptedTurnDirectives: observations.flatMap((event) => Array.isArray(event.acceptedTurnDirectives) ? event.acceptedTurnDirectives : []),
      safetyReceipts: observations.map((event) => event.correctionSafetyReceipt).filter(Boolean),
      turnDirectiveReceipts: observations.map((event) => event.turnDirectiveReceipt).filter(Boolean),
      changedFiles: uniqueStrings(observations.flatMap((event) => Array.isArray(event.changedFiles) ? event.changedFiles : [])),
    }
    : null;

  return {
    schema_version: SCHEMA_VERSION,
    id: `session-${safeFileName(sessionId)}`,
    sessionId,
    task: nonEmptyString(lastOutcome.task) ? lastOutcome.task : (lastContextTurn.task ?? null),
    scope: nonEmptyString(lastOutcome.scope) ? lastOutcome.scope : (lastContextTurn.scope ?? null),
    outcome: lastOutcome.status ?? (lastOutcome.success === true ? "success" : "unknown"),
    changedFiles,
    failures,
    hooks: {
      ...(observationEvidence ? { "conversation.observe": observationEvidence } : {}),
      ...(validationEvidence ? { "validation.after_run": validationEvidence } : {}),
      ...(reviewEvidence ? { "review.after_feedback": reviewEvidence } : {}),
    },
    session: {
      path: sessionFile,
      eventCount: events.length,
      hooks: uniqueStrings(events.map((event) => event.hook).filter(Boolean)),
      startedAt: receivedTimes.length > 0 ? new Date(Math.min(...receivedTimes)).toISOString() : null,
      completedAt: receivedTimes.length > 0 ? new Date(Math.max(...receivedTimes)).toISOString() : null,
      events: events.map(sessionTraceEvent),
    },
    ...(lastOutcome.precedent ? { precedent: lastOutcome.precedent } : {}),
    ...(lastOutcome.replay ? { replay: lastOutcome.replay } : {}),
  };
}

function sessionTraceEvent(event) {
  return {
    hook: event.hook ?? null,
    receivedAt: event.receivedAt ?? null,
    task: event.task ?? null,
    scope: event.scope ?? null,
    changedFiles: Array.isArray(event.changedFiles) ? event.changedFiles : [],
    comments: Array.isArray(event.comments) ? event.comments : [],
    messages: Array.isArray(event.messages) ? event.messages : [],
    correctionSignals: Array.isArray(event.correctionSignals) ? event.correctionSignals : [],
    acceptedCorrectionSignals: Array.isArray(event.acceptedCorrectionSignals) ? event.acceptedCorrectionSignals : [],
    correctionSafetyReceipt: event.correctionSafetyReceipt ?? null,
    turnDirectiveSignals: Array.isArray(event.turnDirectiveSignals) ? event.turnDirectiveSignals : [],
    acceptedTurnDirectives: Array.isArray(event.acceptedTurnDirectives) ? event.acceptedTurnDirectives : [],
    turnDirectiveReceipt: event.turnDirectiveReceipt ?? null,
    command: event.command ?? null,
    exitCode: Number.isFinite(event.exitCode) ? event.exitCode : null,
    success: typeof event.success === "boolean" ? event.success : null,
    status: event.status ?? null,
    failureSignals: Array.isArray(event.failureSignals) ? event.failureSignals : [],
    guardResult: event.guardResult ?? null,
    suppressedInjections: Array.isArray(event.suppressedInjections) ? event.suppressedInjections : [],
    promotionTrials: Array.isArray(event.promotionTrials) ? event.promotionTrials : [],
    contextBlock: event.contextBlock ?? "",
    stdoutSummary: event.stdoutSummary ?? null,
    stderrSummary: event.stderrSummary ?? null,
  };
}

async function createSessionLearningSnapshot(stateDir, sessionId) {
  const trace = await traceFromSession(stateDir, sessionId);
  const events = await readJsonLines(join(stateDir, "events.jsonl"));
  const precedents = await readJsonLines(join(stateDir, "precedents.jsonl"));
  const candidates = [
    ...compileTraceCandidates(trace),
    ...compileReplacementCandidates({ trace, events, precedents }),
  ];
  const tracePath = trace.failures.length > 0 || candidates.length > 0
    ? join(stateDir, "traces", `${safeFileName(trace.id)}.json`)
    : null;

  if (tracePath) {
    await writeFileAtomic(tracePath, `${JSON.stringify(trace, null, 2)}\n`);
  }

  if (candidates.length > 0) {
    await upsertCandidateRecords(stateDir, candidates);
  }

  const snapshot = {
    type: "learning_snapshot_created",
    observedAt: new Date().toISOString(),
    sessionId,
    traceId: trace.id,
    tracePath,
    status: candidates.length > 0 ? "candidate" : "no_signal",
    failures: trace.failures.length,
    candidateIds: candidates.map((candidate) => candidate.id),
    replacementCandidateIds: candidates.filter((candidate) => candidate.reason === "repair_efficacy_replacement").map((candidate) => candidate.id),
    promotionStatus: "not_promoted",
    replayRequired: candidates.length > 0,
  };
  await appendJsonLine(join(stateDir, "events.jsonl"), snapshot);

  return {
    status: snapshot.status,
    traceId: trace.id,
    tracePath,
    failures: trace.failures.length,
    candidateIds: snapshot.candidateIds,
    replacementCandidateIds: snapshot.replacementCandidateIds,
    promotionStatus: snapshot.promotionStatus,
    replayRequired: snapshot.replayRequired,
  };
}

function compileReplacementCandidates({ trace, events, precedents }) {
  if (!traceEligibleAsSuccessfulPair(trace)) {
    return [];
  }

  return suppressedRepairEfficacyIdsForTrace(trace)
    .map((id) => replacementCandidateForPrecedent({ trace, events, precedents, id }))
    .filter(Boolean);
}

function suppressedRepairEfficacyIdsForTrace(trace) {
  return uniqueStrings((trace.session?.events ?? [])
    .flatMap((event) => Array.isArray(event.suppressedInjections) ? event.suppressedInjections : [])
    .filter((item) => ["stale_repair_efficacy", "retired_repair_efficacy"].includes(item.reason))
    .map((item) => item.id));
}

function replacementCandidateForPrecedent({ trace, events, precedents, id }) {
  const precedent = precedents.find((item) => item.id === id);
  if (!precedent) {
    return null;
  }
  if (!replacementCandidateOverlaps(trace, precedent)) {
    return null;
  }

  const counterexamples = counterexamplesForPrecedent(events, id);
  if (counterexamples.length === 0) {
    return null;
  }

  const successfulValidation = successfulValidationForTrace(trace);
  const scope = trace.scope ?? precedent.scope ?? "repo";
  const candidateId = `cand_replace_${safeFileName(id)}_${safeFileName(trace.sessionId)}`;
  const successfulPaths = commonPathPrefixes(trace.changedFiles ?? []);
  const paths = uniqueStrings([
    ...(Array.isArray(precedent.paths) ? precedent.paths : []),
    ...successfulPaths,
  ]);

  return {
    id: candidateId,
    status: "candidate",
    reason: "repair_efficacy_replacement",
    replaces: [id],
    scope,
    trigger: precedent.trigger ?? triggerForTrace(trace),
    lesson: `Precedent ${id} has counterexamples; replace it with the successful pattern from ${trace.id}.`,
    artifact: precedent.artifact ?? "skill",
    paths,
    source_traces: [trace.id],
    failure_types: ["repair_efficacy_replacement"],
    counterexample_ids: counterexamples.map((item) => item.repairId ?? `${item.type}:${item.sessionId ?? "unknown"}`),
    evidence: replacementEvidence({ precedent, trace, counterexamples, successfulValidation }),
    injection: replacementInjection({ precedent, trace, successfulValidation }),
    promotion_required: "Replay the stale precedent scenario with this replacement injected, then promote only with concrete improvement.",
  };
}

function replacementCandidateOverlaps(trace, precedent) {
  if (trace.scope && precedent.scope && trace.scope === precedent.scope) {
    return true;
  }

  const precedentPrefixes = new Set([
    ...commonPathPrefixes(precedent.paths ?? []),
    ...(Array.isArray(precedent.paths) ? precedent.paths : []),
  ]);
  if (precedentPrefixes.size === 0) {
    return false;
  }

  return commonPathPrefixes(trace.changedFiles ?? [])
    .some((prefix) => precedentPrefixes.has(prefix));
}

function replacementEvidence({ precedent, trace, counterexamples, successfulValidation }) {
  return uniqueStrings([
    `suppressed stale repair efficacy: ${precedent.id}`,
    `repair counterexamples: ${counterexamples.length}`,
    ...(successfulValidation ? [`successful validation: ${successfulValidation.command} exited ${successfulValidation.exitCode}`] : []),
    `successful session: ${trace.id}`,
    `successful changed files: ${(trace.changedFiles ?? []).join(", ")}`,
  ]);
}

function replacementInjection({ precedent, trace, successfulValidation }) {
  const base = `Precedent ${precedent.id} has recent counterexamples; prefer the validated pattern from ${trace.id}.`;
  if (successfulValidation?.command) {
    return `${base} Run ${successfulValidation.command} before treating the replacement as safe.`;
  }

  return base;
}

async function promoteSessionPairs(stateDir, { successSessionId = null, requireFailureBeforeSuccess = false } = {}) {
  const traces = await sessionTraces(stateDir);
  const failed = traces.filter((trace) => traceOutcomeFailed(trace) && trace.failures.length > 0);
  const succeeded = traces
    .filter((trace) => traceEligibleAsSuccessfulPair(trace))
    .filter((trace) => !successSessionId || trace.sessionId === successSessionId);
  const promoted = [];

  for (const successTrace of succeeded) {
    const failedTrace = failed.find((trace) =>
      trace.sessionId !== successTrace.sessionId
      &&
      tracesAreAnalogous(trace, successTrace)
      && (!requireFailureBeforeSuccess || traceCompletedBefore(trace, successTrace)),
    );

    if (!failedTrace) {
      continue;
    }
    if (!failedValidationEvidence(failedTrace)) {
      continue;
    }

    const replayId = `session-pair-${safeFileName(failedTrace.id)}-${safeFileName(successTrace.id)}`;
    const replayDir = join(stateDir, "replays", replayId);
    const replayPath = join(replayDir, "replay.json");
    const promotion = sessionPairPromotion(failedTrace, successTrace);
    const replayArtifact = sessionPairReplay({
      id: replayId,
      replayPath,
      failedTrace,
      successTrace,
      promotion,
    });
    const replayContent = `${JSON.stringify(replayArtifact, null, 2)}\n`;
    const artifactSha256 = sha256Text(replayContent);
    const precedent = precedentFromSessionPair(failedTrace, successTrace, replayPath, replayId, artifactSha256);
    const assessment = assessPromotionCandidate(precedent);
    if (!assessment.ok) {
      continue;
    }

    await mkdir(replayDir, { recursive: true });
    await writeFileAtomic(replayPath, replayContent);
    const promotedPrecedent = await upsertPromotedPrecedent(stateDir, precedent, new Date().toISOString());
    promoted.push({
      id: promotedPrecedent.precedent.id,
      action: promotedPrecedent.action,
      failedTrace: failedTrace.id,
      successTrace: successTrace.id,
      replayId,
      replayPath,
    });
  }

  if (promoted.length > 0) {
    await appendJsonLine(join(stateDir, "events.jsonl"), {
      type: "session_pair_promotion_completed",
      observedAt: new Date().toISOString(),
      promoted,
    });
  }

  return promoted;
}

async function sessionTraces(stateDir) {
  const traces = [];

  for (const sessionFile of await jsonFiles(join(stateDir, "sessions"), ".jsonl")) {
    const sessionId = sessionFile
      .slice(join(stateDir, "sessions").length + 1)
      .replace(/\.jsonl$/u, "");
    const trace = await traceFromSession(stateDir, sessionId);
    traces.push(trace);
    if (trace.failures.length > 0) {
      await writeFileAtomic(join(stateDir, "traces", `${safeFileName(trace.id)}.json`), `${JSON.stringify(trace, null, 2)}\n`);
    }
  }

  return traces;
}

function traceOutcomeFailed(trace) {
  return trace.outcome === "failure" || trace.outcome === "failed" || trace.outcome === "error" || trace.failures.length > 0;
}

function traceOutcomeSucceeded(trace) {
  return trace.outcome === "success" || trace.outcome === "passed" || trace.outcome === "done";
}

function traceEligibleAsSuccessfulPair(trace) {
  return traceOutcomeSucceeded(trace)
    && trace.failures.length === 0
    && successfulValidationForTrace(trace) !== null;
}

function traceCompletedBefore(left, right) {
  const leftTime = Date.parse(left.session?.completedAt ?? "");
  const rightTime = Date.parse(right.session?.completedAt ?? "");

  if (!Number.isFinite(leftTime) || !Number.isFinite(rightTime)) {
    return false;
  }

  return leftTime <= rightTime;
}

function tracesAreAnalogous(failedTrace, successTrace) {
  if (failedTrace.scope && successTrace.scope && failedTrace.scope !== successTrace.scope) {
    return false;
  }

  const scopesMatch = Boolean(failedTrace.scope) && failedTrace.scope === successTrace.scope;
  const pathsOverlap = tracesHavePathOverlap(failedTrace, successTrace);
  if (!scopesMatch && !pathsOverlap) {
    return false;
  }

  const failedTask = String(failedTrace.task ?? "").toLowerCase();
  const successTask = String(successTrace.task ?? "").toLowerCase();
  const failedWords = new Set(failedTask.split(/[^a-z0-9_:-]+/u).filter((word) => word.length >= 4));
  const overlap = successTask
    .split(/[^a-z0-9_:-]+/u)
    .filter((word) => failedWords.has(word)).length;

  return overlap > 0 || scopesMatch;
}

function tracesHavePathOverlap(failedTrace, successTrace) {
  const failedPrefixes = new Set(commonPathPrefixes(failedTrace.changedFiles ?? []));
  if (failedPrefixes.size === 0) {
    return false;
  }

  return commonPathPrefixes(successTrace.changedFiles ?? [])
    .some((prefix) => failedPrefixes.has(prefix));
}

function precedentFromSessionPair(failedTrace, successTrace, replayPath, replayId, artifactSha256) {
  const failureTypes = classifyFailures(failedTrace.failures);
  const scope = failedTrace.scope || successTrace.scope || "repo";
  const id = `prec_${safeFileName(scope)}_${failureTypes.join("_") || "session_pair"}`;
  const paths = uniqueStrings([
    ...pathsForScope(scope),
    ...commonPathPrefixes(successTrace.changedFiles),
  ]);
  const successfulValidation = successfulValidationForTrace(successTrace);
  const injection = sessionPairInjection(failureTypes, scope, successfulValidation?.command);
  const promotion = sessionPairPromotion(failedTrace, successTrace);

  return {
    id,
    scope,
    trigger: triggerForTrace(failedTrace),
    lesson: lessonForFailureTypes(failureTypes, scope),
    artifact: "skill",
    paths,
    source_trace: failedTrace.id,
    source_traces: [failedTrace.id, successTrace.id],
    evidence: sessionPairEvidence(failedTrace, successTrace, replayPath),
    injection,
    guards: guardsForSessionPair(failureTypes, paths, successfulValidation?.command),
    replay: {
      id: replayId,
      path: replayPath,
      baseline_failures: 1,
      rerun_failures: 0,
      baseline_exit_code: failedValidationExitCode(failedTrace),
      rerun_exit_code: successfulValidation?.exitCode ?? 0,
      artifact_sha256: artifactSha256,
    },
    promotion,
  };
}

function sessionPairPromotion(failedTrace, successTrace) {
  const successfulValidation = successfulValidationForTrace(successTrace);

  return {
    baseline_failures: 1,
    rerun_failures: 0,
    baseline_exit_code: failedValidationExitCode(failedTrace),
    rerun_exit_code: successfulValidation?.exitCode ?? 0,
  };
}

function sessionPairReplay({ id, replayPath, failedTrace, successTrace, promotion }) {
  const failedValidation = failedValidationEvidence(failedTrace);
  const successValidation = successfulValidationForTrace(successTrace);

  return {
    id,
    replayPath,
    startedAt: failedTrace.session?.completedAt ?? null,
    completedAt: successTrace.session?.completedAt ?? null,
    task: failedTrace.task ?? successTrace.task ?? null,
    scope: failedTrace.scope ?? successTrace.scope ?? null,
    changedFiles: uniqueStrings([
      ...(Array.isArray(failedTrace.changedFiles) ? failedTrace.changedFiles : []),
      ...(Array.isArray(successTrace.changedFiles) ? successTrace.changedFiles : []),
    ]),
    baseline: {
      sessionId: failedTrace.sessionId,
      traceId: failedTrace.id,
      command: failedValidation?.command ?? null,
      exitCode: failedValidation?.exitCode ?? 1,
      failures: failedTrace.failures,
    },
    rerun: {
      sessionId: successTrace.sessionId,
      traceId: successTrace.id,
      command: successValidation?.command ?? null,
      exitCode: successValidation?.exitCode ?? 0,
      failures: successTrace.failures,
    },
    promotion,
    improved: promotion.baseline_failures > promotion.rerun_failures,
  };
}

function successfulValidationForTrace(trace) {
  const validations = Array.isArray(trace.session?.events)
    ? trace.session.events.filter((event) => event.hook === "validation.after_run")
    : [];

  return validations.find((event) => event.exitCode === 0) ?? null;
}

function failedValidationExitCode(trace) {
  const validations = Array.isArray(trace.session?.events)
    ? trace.session.events.filter((event) => event.hook === "validation.after_run")
    : [];
  const failed = validations.find((event) => event.exitCode !== 0);

  return failed?.exitCode ?? null;
}

function sessionPairEvidence(failedTrace, successTrace, replayPath) {
  const failedValidation = failedValidationEvidence(failedTrace);
  const successValidation = successfulValidationForTrace(successTrace);

  return uniqueStrings([
    ...(failedValidation ? [`failed validation: ${failedValidation.command} exited ${failedValidation.exitCode}`] : []),
    ...(successValidation ? [`successful validation: ${successValidation.command} exited ${successValidation.exitCode}`] : []),
    `session-pair replay: ${replayPath}`,
    `failed changed files: ${(failedTrace.changedFiles ?? []).join(", ")}`,
    `successful changed files: ${(successTrace.changedFiles ?? []).join(", ")}`,
    `outcome delta: ${failedTrace.outcome} to ${successTrace.outcome}`,
    ...collectTraceEvidence(failedTrace),
    ...failedTrace.failures.map((failure) => `failure: ${failure}`),
  ]);
}

function failedValidationEvidence(trace) {
  const validations = Array.isArray(trace.session?.events)
    ? trace.session.events.filter((event) => event.hook === "validation.after_run")
    : [];

  return validations.find((event) => event.exitCode !== 0) ?? null;
}

function sessionPairInjection(failureTypes, scope, successfulCommand) {
  const base = injectionForFailureTypes(failureTypes, scope);

  if (successfulCommand && !base.includes(successfulCommand)) {
    return `${base} Use the validation command that passed in the paired session: ${successfulCommand}.`;
  }

  return base;
}

function guardsForSessionPair(failureTypes, paths, successfulCommand) {
  const guards = [];

  if (failureTypes.includes("wrong_repo_slice") && paths.length > 0) {
    guards.push({
      id: "guard_session_pair_paths",
      type: "changed_files_within_paths",
      paths,
      message: `Keep edits inside ${paths.join(", ")}.`,
    });
  }

  if (failureTypes.includes("wrong_test_command") && successfulCommand) {
    guards.push({
      id: "guard_session_pair_validation",
      type: "required_validation_command",
      command: successfulCommand,
      message: `Run ${successfulCommand}.`,
    });
  }

  return guards;
}

function commonPathPrefixes(files) {
  return uniqueStrings((files ?? [])
    .map((file) => file.split("/").slice(0, 2).join("/"))
    .filter((path) => path.includes("/")));
}

function formatGuardFailureForTrace(guard) {
  if (guard.type === "required_validation_command") {
    return `wrong test command: ${guard.message}`;
  }

  if (guard.type === "changed_files_within_paths") {
    return `outside boundary: ${guard.message}`;
  }

  return `guard warning: ${guard.message}`;
}

function formatCorrectionFailureForTrace(signal) {
  if (signal.type === "command_correction") {
    return `wrong test command: user corrected ${signal.actual} to ${signal.expected}`;
  }

  if (signal.type === "boundary_correction") {
    return `wrong repo slice: user corrected edits from ${signal.actual} to ${signal.expected}`;
  }

  return `conversation correction: ${signal.message ?? signal.type ?? "unknown"}`;
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

function uniqueBy(values, keyFn) {
  const seen = new Set();
  const result = [];
  for (const value of values) {
    const key = keyFn(value);
    if (seen.has(key)) {
      continue;
    }
    seen.add(key);
    result.push(value);
  }
  return result;
}

function nonEmptyString(value) {
  return typeof value === "string" && value.trim().length > 0;
}

function stringOrNull(value) {
  return nonEmptyString(value) ? value.trim() : null;
}

function numberOrNull(value) {
  if (value === null || value === undefined || value === "") {
    return null;
  }

  const number = Number(value);
  return Number.isFinite(number) ? number : null;
}

function hookBoolean(value, name, defaultValue) {
  if (value === undefined || value === null || value === "") {
    return defaultValue;
  }

  if (typeof value === "boolean") {
    return value;
  }

  if (value === "true") {
    return true;
  }

  if (value === "false") {
    return false;
  }

  fail(`${name} must be a boolean or "true"/"false"`);
}

function reviewComments(event) {
  if (Array.isArray(event.comments)) {
    return event.comments
      .map((comment) => String(comment).trim())
      .filter((comment) => comment.length > 0);
  }

  if (typeof event.comment === "string" && event.comment.trim().length > 0) {
    return [event.comment.trim()];
  }

  if (typeof event.comments === "string" && event.comments.trim().length > 0) {
    return [event.comments.trim()];
  }

  return [];
}

function conversationMessages(event) {
  const rawMessages = Array.isArray(event.messages)
    ? event.messages
    : [event.message ?? event.content].filter((value) => value !== undefined && value !== null);
  const messages = rawMessages
    .map((message) => {
      if (typeof message === "string") {
        return {
          role: "user",
          trusted: true,
          content: message.trim(),
        };
      }

      return {
        role: typeof message?.role === "string" && message.role.trim().length > 0 ? message.role.trim() : "unknown",
        trusted: typeof message?.trusted === "boolean" ? message.trusted : message?.role === "user",
        content: typeof message?.content === "string" ? message.content.trim() : "",
      };
    })
    .filter((message) => message.content.length > 0);

  if (messages.length === 0) {
    fail("conversation.observe requires messages, message, or content");
  }

  return messages;
}

function conversationCorrectionSignals(messages) {
  const signals = [];

  for (const message of messages) {
    const content = message.content.replace(/\s+/gu, " ").trim();
    for (const match of content.matchAll(/\buse\s+([^.;\n]+?)\s*,?\s+not\s+([^.;\n]+)/giu)) {
      signals.push(commandCorrectionSignal(match[1], match[2], message.role));
    }
    for (const match of content.matchAll(/\buse\s+([^.;\n]+?)\s+instead\s+of\s+([^.;\n]+)/giu)) {
      signals.push(commandCorrectionSignal(match[1], match[2], message.role));
    }
    for (const match of content.matchAll(/\b(?:do not|don't)\s+use\s+([^.;\n]+?)[,;]\s*use\s+([^.;\n]+)/giu)) {
      signals.push(commandCorrectionSignal(match[2], match[1], message.role));
    }
    for (const match of content.matchAll(/\b(?:keep|stay)\s+(?:(?:edits|changes|work)\s+)?(?:inside|in|within)\s+([^.;\n]+?)\s*,?\s+not\s+([^.;\n]+)/giu)) {
      signals.push(boundaryCorrectionSignal(match[1], match[2], message.role));
    }
    for (const match of content.matchAll(/\b(?:edit|change|touch)\s+([^.;\n]+?)\s*,?\s+not\s+([^.;\n]+)/giu)) {
      signals.push(boundaryCorrectionSignal(match[1], match[2], message.role));
    }
  }

  return uniqueBy(signals.filter((signal) => signal.expected && signal.actual), (signal) => `${signal.type}:${signal.expected}:${signal.actual}`);
}

function conversationTurnDirectiveSignals(messages) {
  const signals = [];

  for (const message of messages) {
    const content = message.content.replace(/\s+/gu, " ").trim();
    if (/\b(?:do not|don't|must not|should not)\s+(?:edit|change|touch|modify)\s+(?:files|code|anything)?\b/iu.test(content)
      || /\b(?:answer only|read[- ]only|no edits?|no changes?)\b/iu.test(content)) {
      signals.push({
        type: "no_edit",
        source: message.role,
      });
    }

    for (const match of content.matchAll(/\b(?:scope|limit)\s+(?:(?:all|any)\s+)?(?:recommendations|work|changes|edits|files)?\s*(?:to|under|inside|within)\s+([^.;\n]+?)(?=$|[.;\n])/giu)) {
      signals.push(pathScopeDirectiveSignal(match[1], message.role));
    }
    for (const match of content.matchAll(/\b(?:changes|edits|work)\s+(?:must|should|need to|needs to)\s+stay\s+(?:under|inside|within|in)\s+([^.;\n]+?)(?=$|[.;\n])/giu)) {
      signals.push(pathScopeDirectiveSignal(match[1], message.role));
    }
    for (const match of content.matchAll(/\b(?:keep|stay)\s+(?:(?:edits|changes|work)\s+)?(?:inside|in|within|under)\s+([^.;\n]+?)(?=$|[.;\n])/giu)) {
      signals.push(pathScopeDirectiveSignal(match[1], message.role));
    }
  }

  return uniqueBy(
    signals.filter((signal) => signal.type === "no_edit" || nonEmptyString(signal.path)),
    (signal) => `${signal.type}:${signal.path ?? ""}:${signal.source ?? ""}`,
  );
}

function pathScopeDirectiveSignal(path, role) {
  return {
    type: "path_scope",
    path: cleanDirectivePath(path),
    source: role,
  };
}

function turnDirectiveReceiptFor({ messages, turnDirectiveSignals }) {
  if (turnDirectiveSignals.length === 0) {
    return {
      status: "no_directive",
      accepted: false,
      reasons: [],
      trustedSources: [],
      pathSafety: [],
    };
  }

  const trustedSources = uniqueStrings(messages
    .filter((message) => message.role === "user" && message.trusted !== false)
    .map((message) => message.role));
  const pathSafety = turnDirectiveSignals
    .filter((signal) => signal.type === "path_scope")
    .map((signal) => ({
      path: signal.path,
      safe: directivePathSafe(signal.path),
      reason: directivePathSafe(signal.path) ? "safe_repo_path" : "unsafe_path",
    }));
  const reasons = [
    ...(trustedSources.length === 0 ? ["untrusted_source"] : []),
    ...pathSafety.filter((item) => !item.safe).map((item) => `path_${item.reason}`),
  ];

  return {
    status: reasons.length === 0 ? "accepted" : "quarantined",
    accepted: reasons.length === 0,
    reasons,
    trustedSources,
    pathSafety,
  };
}

function correctionSafetyReceiptFor({ event, messages, correctionSignals, changedFiles }) {
  if (correctionSignals.length === 0) {
    return {
      status: "no_correction",
      accepted: false,
      reasons: [],
      anchors: [],
      commandSafety: [],
      trustedSources: [],
    };
  }

  const trustedSources = uniqueStrings(messages
    .filter((message) => message.role === "user" && message.trusted !== false)
    .map((message) => message.role));
  const anchors = uniqueStrings([
    ...(nonEmptyString(event.scope) ? ["scope"] : []),
    ...(changedFiles.length > 0 ? ["path"] : []),
  ]);
  const commandSafety = correctionSignals.flatMap((signal) => {
    if (signal.type !== "command_correction") {
      return [];
    }

    return [
      {
        field: "expected",
        command: signal.expected,
        ...replayCommandSafety(signal.expected),
      },
      {
        field: "actual",
        command: signal.actual,
        ...replayCommandSafety(signal.actual),
      },
    ];
  });
  const boundarySafety = correctionSignals.flatMap((signal) => {
    if (signal.type !== "boundary_correction") {
      return [];
    }

    return [
      {
        field: "expected",
        path: signal.expected,
        ...boundaryPathSafety(signal.expected, event.scope, changedFiles, true),
      },
      {
        field: "actual",
        path: signal.actual,
        ...boundaryPathSafety(signal.actual, event.scope, changedFiles, false),
      },
    ];
  });
  const unsafeCommands = commandSafety.filter((item) => !item.safe);
  const unsafeBoundaryPaths = boundarySafety.filter((item) => !item.safe);
  const reasons = [
    ...(trustedSources.length === 0 ? ["untrusted_source"] : []),
    ...(anchors.length === 0 ? ["unanchored_context"] : []),
    ...unsafeCommands.map((item) => `${item.field}_${item.reason}`),
    ...unsafeBoundaryPaths.map((item) => `${item.field}_${item.reason}`),
  ];

  return {
    status: reasons.length === 0 ? "accepted" : "quarantined",
    accepted: reasons.length === 0,
    reasons,
    anchors,
    commandSafety,
    boundarySafety,
    trustedSources,
  };
}

function commandCorrectionSignal(expected, actual, role) {
  if (looksLikeRepoPath(expected) && looksLikeRepoPath(actual)) {
    return boundaryCorrectionSignal(expected, actual, role);
  }

  return {
    type: "command_correction",
    expected: cleanCorrectionCommand(expected),
    actual: cleanCorrectionCommand(actual),
    source: role,
  };
}

function boundaryCorrectionSignal(expected, actual, role) {
  return {
    type: "boundary_correction",
    expected: cleanCorrectionPath(expected),
    actual: cleanCorrectionPath(actual),
    source: role,
  };
}

function cleanCorrectionCommand(value) {
  return String(value)
    .replace(/^["'`]+|["'`]+$/gu, "")
    .replace(/\s+/gu, " ")
    .trim();
}

function cleanCorrectionPath(value) {
  return String(value)
    .replace(/^["'`]+|["'`]+$/gu, "")
    .replace(/\s+/gu, " ")
    .replace(/\s+(?:directory|folder|module|path)$/iu, "")
    .replace(/[),]+$/gu, "")
    .trim();
}

function cleanDirectivePath(value) {
  return cleanCorrectionPath(value)
    .replace(/^the\s+/iu, "")
    .replace(/\s+(?:folder|directory|module|path)$/iu, "")
    .replace(/\/+$/u, "")
    .trim();
}

function looksLikeRepoPath(value) {
  return repoPathSafe(cleanCorrectionPath(value));
}

function boundaryPathSafety(path, scope, changedFiles, requireAnchor) {
  if (!repoPathSafe(path)) {
    return {
      safe: false,
      reason: "unsafe_path",
      pathAnchors: [],
    };
  }

  const pathAnchors = correctionPathAnchors(path, scope, changedFiles);
  if (requireAnchor && pathAnchors.length === 0) {
    return {
      safe: false,
      reason: "unanchored_path",
      pathAnchors,
    };
  }

  return {
    safe: true,
    reason: null,
    pathAnchors,
  };
}

function correctionPathAnchors(path, scope, changedFiles) {
  return uniqueStrings([
    ...(pathsForScope(typeof scope === "string" ? scope : "").some((scopePath) => repoPathsOverlap(path, scopePath)) ? ["scope"] : []),
    ...(changedFiles.some((changedFile) => repoPathsOverlap(path, changedFile)) ? ["path"] : []),
  ]);
}

function repoPathSafe(path) {
  if (!nonEmptyString(path)) {
    return false;
  }
  if (path.startsWith("/") || path.startsWith("~") || /^[a-z][a-z0-9+.-]*:/iu.test(path)) {
    return false;
  }
  if (path.split("/").includes("..")) {
    return false;
  }

  return /^[A-Za-z0-9._@/-]+$/u.test(path) && path.includes("/");
}

function directivePathSafe(path) {
  if (!nonEmptyString(path)) {
    return false;
  }
  if (path.startsWith("/") || path.startsWith("~") || /^[a-z][a-z0-9+.-]*:/iu.test(path)) {
    return false;
  }
  if (path.split("/").includes("..")) {
    return false;
  }

  return /^[A-Za-z0-9._@/-]+$/u.test(path);
}

function repoPathsOverlap(left, right) {
  if (!repoPathSafe(left) || !repoPathSafe(right)) {
    return false;
  }

  return left === right || left.startsWith(`${right}/`) || right.startsWith(`${left}/`);
}

function formatCorrectionContextBlock(signals) {
  const commandCorrections = signals.filter((signal) => signal.type === "command_correction");
  const boundaryCorrections = signals.filter((signal) => signal.type === "boundary_correction");
  if (commandCorrections.length === 0 && boundaryCorrections.length === 0) {
    return "";
  }

  return [
    "Precedent correction:",
    ...commandCorrections.slice(0, 3).map((signal) => `- Use ${signal.expected} instead of ${signal.actual}.`),
    ...boundaryCorrections.slice(0, 3).map((signal) => `- Keep edits inside ${signal.expected} instead of ${signal.actual}.`),
  ].join("\n");
}

function emptyTurnDirectives() {
  return {
    noEdit: false,
    allowedPaths: [],
    sources: [],
  };
}

function directiveSummary(signals) {
  const accepted = Array.isArray(signals) ? signals : [];
  return {
    noEdit: accepted.some((signal) => signal.type === "no_edit"),
    allowedPaths: uniqueStrings(accepted
      .filter((signal) => signal.type === "path_scope" && directivePathSafe(signal.path))
      .map((signal) => signal.path)),
    sources: uniqueStrings(accepted.map((signal) => signal.source).filter(Boolean)),
  };
}

async function activeTurnDirectivesForSession(stateDir, sessionId) {
  if (!nonEmptyString(sessionId)) {
    return emptyTurnDirectives();
  }

  const events = await readSessionEvents(stateDir, sessionId);
  return directiveSummary(eventsSinceLastOutcome(events)
    .filter((event) => event.hook === "conversation.observe" && event.turnDirectiveReceipt?.status === "accepted")
    .flatMap((event) => Array.isArray(event.acceptedTurnDirectives) ? event.acceptedTurnDirectives : []));
}

function formatTurnDirectiveContextBlock(directives) {
  const summary = directives ?? emptyTurnDirectives();
  const lines = [];
  if (summary.noEdit) {
    lines.push("- Do not edit files in this turn.");
  }
  for (const path of summary.allowedPaths.slice(0, 5)) {
    lines.push(`- Keep this turn inside ${path}.`);
  }

  return lines.length > 0 ? ["Precedent directive:", ...lines].join("\n") : "";
}

function formatRuntimeContextBlock(matches, directives) {
  return [
    formatInjectionBlock(matches),
    formatTurnDirectiveContextBlock(directives),
  ].filter(Boolean).join("\n");
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

  const replay = precedent.replay ?? {};
  if (!nonEmptyString(replay.id)) {
    reasons.push("precedent.replay.id is required for promotion");
  }
  if (!nonEmptyString(replay.path)) {
    reasons.push("precedent.replay.path is required for promotion");
  }
  if (replay.baseline_failures !== baselineFailures) {
    reasons.push("precedent.replay.baseline_failures must match promotion baseline_failures");
  }
  if (replay.rerun_failures !== rerunFailures) {
    reasons.push("precedent.replay.rerun_failures must match promotion rerun_failures");
  }
  if (!Number.isFinite(replay.baseline_exit_code)) {
    reasons.push("precedent.replay.baseline_exit_code must be a number");
  }
  if (!Number.isFinite(replay.rerun_exit_code)) {
    reasons.push("precedent.replay.rerun_exit_code must be a number");
  }
  if (!/^[a-f0-9]{64}$/u.test(replay.artifact_sha256 ?? "")) {
    reasons.push("precedent.replay.artifact_sha256 must be a sha256 hex digest");
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
      ...(Array.isArray(candidate.source_traces) ? candidate.source_traces : []),
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

async function upsertCandidateRecords(stateDir, candidates) {
  const ledgerPath = join(stateDir, "candidates.jsonl");
  const existingCandidates = await readJsonLines(ledgerPath);
  const byId = new Map(existingCandidates.map((candidate) => [candidate.id, candidate]));

  for (const candidate of candidates) {
    const existing = byId.get(candidate.id);
    byId.set(candidate.id, mergeCandidateRecord(existing, candidate));
  }

  await writeJsonLines(ledgerPath, [...byId.values()].sort((left, right) => left.id.localeCompare(right.id)));
}

function mergeCandidateRecord(existing, candidate) {
  if (!existing) {
    return candidate;
  }

  return {
    ...existing,
    ...candidate,
    source_traces: uniqueStrings([
      ...(Array.isArray(existing.source_traces) ? existing.source_traces : []),
      ...(Array.isArray(candidate.source_traces) ? candidate.source_traces : []),
    ]),
    failure_types: uniqueStrings([
      ...(Array.isArray(existing.failure_types) ? existing.failure_types : []),
      ...(Array.isArray(candidate.failure_types) ? candidate.failure_types : []),
    ]),
    evidence: uniqueStrings([
      ...(Array.isArray(existing.evidence) ? existing.evidence : []),
      ...(Array.isArray(candidate.evidence) ? candidate.evidence : []),
    ]),
    replayPlan: mergeReplayPlan(existing.replayPlan, candidate.replayPlan),
  };
}

function mergeReplayPlan(existing, next) {
  if (!existing) {
    return next;
  }
  if (!next) {
    return existing;
  }

  return {
    ...existing,
    ...next,
    baseline: {
      ...(existing.baseline ?? {}),
      ...(next.baseline ?? {}),
    },
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

async function runReplayCommand({ label, command, storedCommand, cwd, outputDir }) {
  const startedAt = Date.now();
  const result = await spawnShell(command, cwd);
  const durationMs = Date.now() - startedAt;
  const stdoutPath = join(outputDir, `${label}.stdout.txt`);
  const stderrPath = join(outputDir, `${label}.stderr.txt`);
  const stdout = redactSecrets(result.stdout).value;
  const stderr = redactSecrets(result.stderr).value;

  await writeFileAtomic(stdoutPath, stdout);
  await writeFileAtomic(stderrPath, stderr);

  return {
    command: storedCommand,
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

function buildReplayTrace(replayCase, replay, replayPath, artifactSha256) {
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
      artifact_sha256: artifactSha256,
      baseline: {
        command: replay.baseline.command,
        exitCode: replay.baseline.exitCode,
      },
      rerun: {
        command: replay.rerun.command,
        exitCode: replay.rerun.exitCode,
      },
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

  const observation = trace.hooks?.["conversation.observe"];
  for (const signal of Array.isArray(observation?.acceptedCorrectionSignals) ? observation.acceptedCorrectionSignals : []) {
    if (signal.type === "command_correction") {
      evidence.push(`conversation-correction: use ${signal.expected} instead of ${signal.actual}`);
    } else if (signal.type === "boundary_correction") {
      evidence.push(`conversation-correction: keep edits inside ${signal.expected} instead of ${signal.actual}`);
    }
  }

  const review = trace.hooks?.["review.after_feedback"];
  for (const comment of Array.isArray(review?.comments) ? review.comments : []) {
    if (typeof comment === "string" && comment.trim().length > 0) {
      evidence.push(`review-comment: ${comment}`);
    }
  }

  return evidence;
}

function replayPlanFromTrace(trace) {
  const validation = trace.hooks?.["validation.after_run"];
  if (!validation?.command) {
    return null;
  }

  const exitCode = exitCodeFromValidationResult(validation.result);
  if (!Number.isFinite(exitCode) || exitCode === 0) {
    return null;
  }

  return redactSecretsDeep({
    baseline: {
      command: validation.command,
      exitCode,
      sourceTrace: trace.id ?? null,
      sourceSession: trace.sessionId ?? null,
      evidence: validation.evidence ?? null,
    },
    rerun: null,
    promotion: {
      required: true,
      acceptance: "Promote only after replay proves baseline_failures > rerun_failures.",
    },
  }).value;
}

function exitCodeFromValidationResult(result) {
  if (typeof result !== "string") {
    return null;
  }

  const match = result.match(/\bexit\s+(-?\d+)\b/u);
  return match ? Number(match[1]) : null;
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

function pathsForCandidateTrace(trace, scope, failureTypes) {
  return uniqueStrings([
    ...pathsForScope(scope),
    ...correctedBoundaryPaths(trace),
    ...(failureTypes.includes("wrong_repo_slice") ? commonPathPrefixes(trace.changedFiles ?? []) : []),
  ]);
}

function correctedBoundaryPaths(trace) {
  return uniqueStrings((trace.hooks?.["conversation.observe"]?.acceptedCorrectionSignals ?? [])
    .filter((signal) => signal.type === "boundary_correction")
    .map((signal) => signal.expected)
    .filter(repoPathSafe));
}

function capitalizeSentence(value) {
  if (value.length === 0) {
    return value;
  }

  return `${value[0].toUpperCase()}${value.slice(1)}.`;
}

async function loadRuntimeConfig() {
  runtimeConfigPath = configPath();

  let loadedConfig = DEFAULT_CONFIG;
  try {
    loadedConfig = parseJson(await readFile(runtimeConfigPath, "utf8"), runtimeConfigPath);
    validateConfig(loadedConfig, "config");
  } catch (error) {
    if (error.code !== "ENOENT") {
      throw error;
    }
  }

  runtimeConfig = normalizeConfig(loadedConfig);

  if (args["state-dir"]) {
    runtimeConfig = {
      ...runtimeConfig,
      stateDir: args["state-dir"],
    };
  }

  if (args.limit) {
    runtimeConfig = {
      ...runtimeConfig,
      maxInjections: positiveInteger(args.limit, "config.maxInjections"),
    };
  }

  runtimeConfigHash = stableHash(runtimeConfig);
}

function configPath() {
  if (process.env.PRECEDENT_CONFIG) {
    return resolve(process.env.PRECEDENT_CONFIG);
  }

  return join(resolve(args["state-dir"] ?? DEFAULT_STATE_DIR), "config.json");
}

function normalizeConfig(config) {
  return {
    schema_version: CONFIG_SCHEMA_VERSION,
    stateDir: config.stateDir ?? DEFAULT_CONFIG.stateDir,
    maxInjections: config.maxInjections ?? DEFAULT_CONFIG.maxInjections,
    hookTimeoutMs: config.hookTimeoutMs ?? DEFAULT_CONFIG.hookTimeoutMs,
    failurePolicy: config.failurePolicy ?? DEFAULT_CONFIG.failurePolicy,
    retentionDays: config.retentionDays ?? DEFAULT_CONFIG.retentionDays,
    redaction: {
      enabled: config.redaction?.enabled ?? DEFAULT_CONFIG.redaction.enabled,
    },
    enabledHooks: Array.isArray(config.enabledHooks) ? config.enabledHooks : DEFAULT_CONFIG.enabledHooks,
  };
}

function validateConfig(config, name) {
  if (config?.schema_version !== CONFIG_SCHEMA_VERSION) {
    fail(`${name}.schema_version must be "${CONFIG_SCHEMA_VERSION}"`);
  }

  if (config.stateDir !== undefined && typeof config.stateDir !== "string") {
    fail(`${name}.stateDir must be a string`);
  }

  if (config.maxInjections !== undefined) {
    positiveInteger(config.maxInjections, `${name}.maxInjections`);
  }

  if (config.hookTimeoutMs !== undefined) {
    positiveInteger(config.hookTimeoutMs, `${name}.hookTimeoutMs`);
  }

  if (config.failurePolicy !== undefined && config.failurePolicy !== "fail_open") {
    fail(`${name}.failurePolicy must be "fail_open"`);
  }

  if (config.retentionDays !== undefined) {
    positiveInteger(config.retentionDays, `${name}.retentionDays`);
  }

  if (config.redaction !== undefined && typeof config.redaction !== "object") {
    fail(`${name}.redaction must be an object`);
  }

  if (config.redaction?.enabled !== undefined && typeof config.redaction.enabled !== "boolean") {
    fail(`${name}.redaction.enabled must be a boolean`);
  }

  if (config.enabledHooks !== undefined) {
    if (!Array.isArray(config.enabledHooks)) {
      fail(`${name}.enabledHooks must be an array`);
    }

    for (const hook of config.enabledHooks) {
      if (!SUPPORTED_EVENT_HOOKS.has(hook)) {
        fail(`${name}.enabledHooks contains unsupported hook: ${hook}`);
      }
    }
  }
}

async function writeDefaultConfig(stateDir) {
  const configuredStateDir = args["state-dir"] ?? runtimeConfig.stateDir ?? DEFAULT_STATE_DIR;
  const config = normalizeConfig({
    ...runtimeConfig,
    stateDir: configuredStateDir,
  });

  await writeFileAtomic(join(stateDir, "config.json"), `${JSON.stringify(sortObject(config), null, 2)}\n`);
  runtimeConfig = config;
  runtimeConfigPath = join(stateDir, "config.json");
  runtimeConfigHash = stableHash(runtimeConfig);
}

function positiveInteger(value, name) {
  const number = Number(value);

  if (!Number.isInteger(number) || number <= 0) {
    fail(`${name} must be a positive integer`);
  }

  return number;
}

function stableHash(value) {
  return createHash("sha256").update(JSON.stringify(sortObject(value))).digest("hex");
}

function sha256Text(value) {
  return createHash("sha256").update(value).digest("hex");
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
    let count = 0;

    for (const entry of entries) {
      if (!entry.isDirectory()) {
        continue;
      }

      try {
        await access(join(replaysDir, entry.name, "replay.json"));
        count += 1;
      } catch (error) {
        if (error.code !== "ENOENT") {
          throw error;
        }
      }
    }

    return count;
  } catch (error) {
    if (error.code === "ENOENT") {
      return 0;
    }

    throw error;
  }
}

async function checkConfig(checks) {
  try {
    const config = parseJson(await readFile(runtimeConfigPath, "utf8"), runtimeConfigPath);
    validateConfigForCheck(config, "config", runtimeConfigPath, checks);
    checks.push({ ok: true, name: "config", file: runtimeConfigPath });
  } catch (error) {
    checks.push({ ok: false, name: "config", file: runtimeConfigPath, message: error.message });
  }
}

async function pruneJsonLinesByTime(path, cutoff, dryRun, plan, removedKey, keptKey) {
  let entries = [];

  try {
    const content = await readFile(path, "utf8");
    entries = content
      .split("\n")
      .filter((line) => line.trim().length > 0)
      .map((line) => JSON.parse(line));
  } catch (error) {
    if (error.code === "ENOENT") {
      return;
    }

    throw error;
  }

  const kept = [];
  for (const entry of entries) {
    const timestamp = timestampForEntry(entry);
    if (timestamp && timestamp < cutoff) {
      plan[removedKey] += 1;
    } else {
      plan[keptKey] += 1;
      kept.push(entry);
    }
  }

  if (!dryRun) {
    await writeJsonLines(path, kept);
  }
}

function timestampForEntry(entry) {
  const value = entry.observedAt ?? entry.receivedAt ?? entry.startedAt ?? entry.completedAt ?? entry.created_at ?? entry.updated_at;
  if (!value) {
    return null;
  }

  const timestamp = new Date(value);
  return Number.isNaN(timestamp.getTime()) ? null : timestamp;
}

async function fileTime(path) {
  try {
    const content = parseJson(await readFile(path, "utf8"), path);
    return timestampForEntry(content) ?? (await stat(path)).mtime;
  } catch (error) {
    if (error.code === "ENOENT") {
      return null;
    }

    throw error;
  }
}

async function childDirs(dir) {
  try {
    const entries = await readdir(dir, { withFileTypes: true });
    return entries
      .filter((entry) => entry.isDirectory())
      .map((entry) => join(dir, entry.name))
      .sort();
  } catch (error) {
    if (error.code === "ENOENT") {
      return [];
    }

    throw error;
  }
}

async function checkJsonLinesFile(checks, path, name) {
  try {
    const content = await readFile(path, "utf8");
    const lines = content.split("\n");

    lines.forEach((line, index) => {
      if (line.trim().length === 0) {
        return;
      }

      try {
        JSON.parse(line);
      } catch (error) {
        checks.push({ ok: false, name, file: path, line: index + 1, message: `invalid JSONL: ${error.message}` });
      }
    });

    if (!checks.some((check) => check.name === name && check.file === path && !check.ok)) {
      checks.push({ ok: true, name, file: path });
    }
  } catch (error) {
    if (error.code === "ENOENT") {
      checks.push({ ok: true, name, file: path, skipped: true });
      return;
    }

    checks.push({ ok: false, name, file: path, message: error.message });
  }
}

async function checkJsonFilesInDir(checks, dir, name, validate) {
  for (const file of await jsonFiles(dir)) {
    try {
      validate(parseJson(await readFile(file, "utf8"), file), file);
      checks.push({ ok: true, name, file });
    } catch (error) {
      checks.push({ ok: false, name, file, message: error.message });
    }
  }
}

async function checkJsonLinesInDir(checks, dir, name) {
  for (const file of await jsonFiles(dir, ".jsonl")) {
    await checkJsonLinesFile(checks, file, name);
  }
}

async function checkReplayArtifacts(checks, replaysDir) {
  for (const file of await replayJsonFiles(replaysDir)) {
    try {
      const replay = parseJson(await readFile(file, "utf8"), file);
      validateReplayArtifact(replay, checks, file);
    } catch (error) {
      checks.push({ ok: false, name: "replay", file, message: error.message });
    }
  }
}

function validateReplayArtifact(replay, checks, file) {
  const before = checks.length;
  assertCheck(typeof replay.id === "string", checks, "replay", file, "replay.id is required");
  assertCheck(typeof replay.baseline?.exitCode === "number", checks, "replay", file, "replay.baseline.exitCode is required");
  assertCheck(typeof replay.rerun?.exitCode === "number", checks, "replay", file, "replay.rerun.exitCode is required");
  assertCheck(Number.isFinite(replay.promotion?.baseline_failures), checks, "replay", file, "replay.promotion.baseline_failures is required");
  assertCheck(Number.isFinite(replay.promotion?.rerun_failures), checks, "replay", file, "replay.promotion.rerun_failures is required");

  if (Number.isFinite(replay.promotion?.baseline_failures) && Number.isFinite(replay.promotion?.rerun_failures)) {
    assertCheck(
      replay.improved === (replay.promotion.baseline_failures > replay.promotion.rerun_failures),
      checks,
      "replay",
      file,
      "replay.improved must match promotion failure delta",
    );
  }

  if (checks.length === before) {
    checks.push({ ok: true, name: "replay", file });
  }
}

async function checkPromotedPrecedents(checks, stateDir) {
  let precedents = [];
  try {
    precedents = await readJsonLinesForCheck(join(stateDir, "precedents.jsonl"));
  } catch (error) {
    checks.push({ ok: false, name: "promoted_precedent", file: join(stateDir, "precedents.jsonl"), message: error.message });
    return;
  }

  for (const precedent of precedents) {
    const name = "promoted_precedent";
    const file = join(stateDir, "precedents.jsonl");
    assertCheck(precedent.promotion_status === "promoted", checks, name, file, `precedent ${precedent.id} is not promoted`);
    assertCheck(Array.isArray(precedent.evidence) && precedent.evidence.length > 0, checks, name, file, `precedent ${precedent.id} has no evidence`);
    assertCheck(Number.isFinite(precedent.promotion?.baseline_failures), checks, name, file, `precedent ${precedent.id} missing baseline_failures`);
    assertCheck(Number.isFinite(precedent.promotion?.rerun_failures), checks, name, file, `precedent ${precedent.id} missing rerun_failures`);
    if (Number.isFinite(precedent.promotion?.baseline_failures) && Number.isFinite(precedent.promotion?.rerun_failures)) {
      assertCheck(
        precedent.promotion.baseline_failures > precedent.promotion.rerun_failures,
        checks,
        name,
        file,
        `precedent ${precedent.id} promotion must show baseline_failures greater than rerun_failures`,
      );
    }
    await checkPrecedentReplayReceipt(precedent, checks, stateDir, file);
    checkPrecedentGuards(precedent, checks, file);
  }

  if (!checks.some((check) => check.name === "promoted_precedent" && !check.ok)) {
    checks.push({ ok: true, name: "promoted_precedent", file: join(stateDir, "precedents.jsonl") });
  }
}

async function checkCandidateLedger(checks, stateDir) {
  const file = join(stateDir, "candidates.jsonl");
  let candidates = [];
  let precedents = [];
  let traces = [];
  try {
    candidates = await readJsonLinesForCheck(file);
    precedents = await readJsonLinesForCheck(join(stateDir, "precedents.jsonl"));
    traces = await readStoredTraces(join(stateDir, "traces"));
  } catch (error) {
    checks.push({ ok: false, name: "candidate_ledger", file, message: error.message });
    return;
  }

  const before = checks.length;
  const promotedIds = new Set(precedents.filter((precedent) => precedent.promotion_status === "promoted").map((precedent) => precedent.id));
  const traceIds = new Set(traces.map((trace) => trace.id));

  for (const candidate of candidates) {
    assertCheck(typeof candidate.id === "string" && candidate.id.length > 0, checks, "candidate_ledger", file, "candidate.id is required");
    assertCheck(candidate.status === "candidate", checks, "candidate_ledger", file, `candidate ${candidate.id ?? "(missing)"} status must be candidate`);
    assertCheck(candidate.promotion_status !== "promoted", checks, "candidate_ledger", file, `candidate ${candidate.id ?? "(missing)"} must not be promoted without replay`);
    assertCheck(candidate.promotion === undefined, checks, "candidate_ledger", file, `candidate ${candidate.id ?? "(missing)"} must not include promotion metrics before replay`);
    assertCheck(Array.isArray(candidate.source_traces) && candidate.source_traces.length > 0, checks, "candidate_ledger", file, `candidate ${candidate.id ?? "(missing)"} source_traces are required`);
    assertCheck(Array.isArray(candidate.evidence) && candidate.evidence.length > 0, checks, "candidate_ledger", file, `candidate ${candidate.id ?? "(missing)"} evidence is required`);
    checkCandidateReplayPlan(candidate, checks, file);

    if (Array.isArray(candidate.source_traces)) {
      for (const traceId of candidate.source_traces) {
        assertCheck(traceIds.has(traceId), checks, "candidate_ledger", file, `candidate ${candidate.id ?? "(missing)"} source trace ${traceId} is missing`);
      }
    }

    if (candidate.reason === "repair_efficacy_replacement") {
      assertCheck(Array.isArray(candidate.replaces) && candidate.replaces.length === 1, checks, "candidate_ledger", file, `replacement candidate ${candidate.id ?? "(missing)"} must replace exactly one precedent`);
      const replacedId = Array.isArray(candidate.replaces) ? candidate.replaces[0] : null;
      assertCheck(promotedIds.has(replacedId), checks, "candidate_ledger", file, `replacement candidate ${candidate.id ?? "(missing)"} replaces unknown promoted precedent ${replacedId ?? "(missing)"}`);
      const evidence = Array.isArray(candidate.evidence) ? candidate.evidence : [];
      assertCheck(evidence.some((item) => /^repair counterexamples: [1-9]/u.test(item)), checks, "candidate_ledger", file, `replacement candidate ${candidate.id ?? "(missing)"} needs counterexample evidence`);
      assertCheck(evidence.some((item) => /^successful validation: .+ exited 0$/u.test(item)), checks, "candidate_ledger", file, `replacement candidate ${candidate.id ?? "(missing)"} needs successful validation evidence`);
    }
  }

  if (!checks.some((check) => check.name === "candidate_ledger" && !check.ok)) {
    checks.push({ ok: true, name: "candidate_ledger", file, checked: candidates.length });
  } else if (checks.length === before) {
    checks.push({ ok: true, name: "candidate_ledger", file, checked: candidates.length });
  }
}

function checkCandidateReplayPlan(candidate, checks, file) {
  if (candidate.replayPlan === undefined || candidate.replayPlan === null) {
    return;
  }

  const replayPlan = candidate.replayPlan;
  assertCheck(typeof replayPlan === "object" && !Array.isArray(replayPlan), checks, "candidate_ledger", file, `candidate ${candidate.id ?? "(missing)"} replayPlan must be an object`);
  const baseline = replayPlan?.baseline;
  assertCheck(typeof baseline === "object" && baseline !== null && !Array.isArray(baseline), checks, "candidate_ledger", file, `candidate ${candidate.id ?? "(missing)"} replayPlan.baseline is required`);
  assertCheck(typeof baseline?.command === "string" && baseline.command.trim().length > 0, checks, "candidate_ledger", file, `candidate ${candidate.id ?? "(missing)"} replayPlan.baseline.command is required`);
  assertCheck(Number.isFinite(baseline?.exitCode), checks, "candidate_ledger", file, `candidate ${candidate.id ?? "(missing)"} replayPlan.baseline.exitCode is required`);
  if (Number.isFinite(baseline?.exitCode)) {
    assertCheck(baseline.exitCode !== 0, checks, "candidate_ledger", file, `candidate ${candidate.id ?? "(missing)"} replayPlan baseline must be a failing command`);
  }
  if (baseline?.sourceTrace !== undefined && baseline.sourceTrace !== null) {
    assertCheck(typeof baseline.sourceTrace === "string" && baseline.sourceTrace.length > 0, checks, "candidate_ledger", file, `candidate ${candidate.id ?? "(missing)"} replayPlan.baseline.sourceTrace must be a string`);
  }
  if (baseline?.sourceSession !== undefined && baseline.sourceSession !== null) {
    assertCheck(typeof baseline.sourceSession === "string" && baseline.sourceSession.length > 0, checks, "candidate_ledger", file, `candidate ${candidate.id ?? "(missing)"} replayPlan.baseline.sourceSession must be a string`);
  }
}

async function checkRepairReceipts(checks, stateDir) {
  const file = join(stateDir, "events.jsonl");
  let events = [];
  try {
    events = await readJsonLinesForCheck(file);
  } catch (error) {
    checks.push({ ok: false, name: "repair_receipt", file, message: error.message });
    return;
  }

  const repairEvents = events.filter((event) => event.hook === "repair.before_retry" && event.repairId);
  const receipts = events.filter((event) => event.hook === "repair.after_retry" && event.repairReceipt);
  const missingRepairIds = [];
  const missingRetryEvidence = [];
  const unresolved = [];

  for (const event of receipts) {
    const receipt = event.repairReceipt;
    const repairEvent = repairEvents.find((item) =>
      item.repairId === receipt.id
      && (!receipt.repairSessionId || item.sessionId === receipt.repairSessionId)
    );

    if (receipt.repairResolved === true && !repairEvent) {
      missingRepairIds.push(receipt.id ?? "(missing)");
    }

    if (receipt.repairResolved === true && !events.some((item) =>
      item.sessionId === receipt.retrySessionId
      && (item.hook === "validation.after_run" || item.hook === "diff.after_edit" || item.hook === "outcome.after_task")
    )) {
      missingRetryEvidence.push(receipt.id ?? "(missing)");
    }

    if (receipt.repairResolved !== true) {
      unresolved.push(receipt.id ?? "(missing)");
    }
  }

  checks.push({
    ok: missingRepairIds.length === 0 && missingRetryEvidence.length === 0 && unresolved.length === 0,
    name: "repair_receipt",
    file,
    missingRepairIds,
    missingRetryEvidence,
    unresolved,
    message: unresolved.length > 0
      ? "unresolved repair receipt(s) found"
      : missingRepairIds.length > 0
        ? "resolved repair receipt references unknown repair id"
        : missingRetryEvidence.length > 0
          ? "resolved repair receipt lacks retry evidence"
          : undefined,
  });
}

async function checkCorrectionSafety(checks, stateDir, strict) {
  const file = join(stateDir, "sessions");
  const violations = [];

  for (const sessionFile of await jsonFiles(file, ".jsonl")) {
    let events = [];
    try {
      events = await readJsonLinesForCheck(sessionFile);
    } catch (error) {
      checks.push({ ok: false, name: "correction_safety", file: sessionFile, message: error.message });
      continue;
    }

    for (const event of events.filter((item) => item.hook === "conversation.observe")) {
      const signals = Array.isArray(event.correctionSignals) ? event.correctionSignals : [];
      if (signals.length === 0) {
        continue;
      }

      const receipt = event.correctionSafetyReceipt;
      if (!receipt || !["accepted", "quarantined", "no_correction"].includes(receipt.status)) {
        violations.push({ sessionId: event.sessionId, eventId: event.eventId ?? null, reason: "missing_correction_safety_receipt" });
      }
      for (const signal of signals) {
        if (!nonEmptyString(signal.source)) {
          violations.push({ sessionId: event.sessionId, eventId: event.eventId ?? null, reason: "missing_correction_source" });
        }
      }
      if (receipt?.status === "accepted" && (!Array.isArray(receipt.anchors) || receipt.anchors.length === 0)) {
        violations.push({ sessionId: event.sessionId, eventId: event.eventId ?? null, reason: "accepted_correction_without_anchor" });
      }
    }
  }

  checks.push({
    ok: !strict || violations.length === 0,
    name: "correction_safety",
    file,
    strict,
    violations,
    message: strict && violations.length > 0
      ? "conversation correction signals require safety receipts, trust source, and anchors"
      : undefined,
  });
}

async function checkRuntimeWiring(checks, stateDir, strict) {
  const events = await readJsonLines(join(stateDir, "events.jsonl"));
  const health = await runtimeWiringHealthSummary(stateDir, events);
  const fallbackSessions = health.details.fallbackAttachments;
  const strictFailures = fallbackSessions.length
    + health.unackedDeliveries
    + health.mismatchedInjectionAcks
    + health.rejectedInjectionAcks;

  checks.push({
    ok: !strict || strictFailures === 0,
    name: "runtime_wiring",
    file: join(stateDir, "events.jsonl"),
    strict,
    ...health,
    message: strict && fallbackSessions.length > 0
      ? "runtime attach used task_hash_fallback identity; pass --session or --thread-id"
      : strict && strictFailures > 0
        ? "runtime wiring has injection acknowledgement issues"
      : undefined,
  });
}

async function checkWarrants(checks, stateDir, strict) {
  const health = await warrantHealthSummary(stateDir);

  checks.push({
    ok: !strict || health.needsAttention === 0,
    name: "warrant",
    file: join(stateDir, "sessions"),
    strict,
    ...health,
    message: strict && health.needsAttention > 0
      ? "warrant outcome has unresolved or violated contract"
      : undefined,
  });
}

async function checkPrecedentReplayReceipt(precedent, checks, stateDir, file) {
  const replay = precedent.replay ?? {};
  assertCheck(nonEmptyString(replay.id), checks, "promoted_precedent_replay", file, `precedent ${precedent.id} replay.id is required`);
  assertCheck(nonEmptyString(replay.path), checks, "promoted_precedent_replay", file, `precedent ${precedent.id} replay.path is required`);
  assertCheck(replay.baseline_failures === precedent.promotion?.baseline_failures, checks, "promoted_precedent_replay", file, `precedent ${precedent.id} replay baseline failure count does not match promotion`);
  assertCheck(replay.rerun_failures === precedent.promotion?.rerun_failures, checks, "promoted_precedent_replay", file, `precedent ${precedent.id} replay rerun failure count does not match promotion`);
  assertCheck(Number.isFinite(replay.baseline_exit_code), checks, "promoted_precedent_replay", file, `precedent ${precedent.id} replay baseline exit code is required`);
  assertCheck(Number.isFinite(replay.rerun_exit_code), checks, "promoted_precedent_replay", file, `precedent ${precedent.id} replay rerun exit code is required`);
  assertCheck(/^[a-f0-9]{64}$/u.test(replay.artifact_sha256 ?? ""), checks, "promoted_precedent_replay", file, `precedent ${precedent.id} replay artifact_sha256 is required`);

  if (!nonEmptyString(replay.path)) {
    return;
  }

  const replayPath = resolve(replay.path);
  if (!pathWithin(resolve(stateDir), replayPath)) {
    checks.push({
      ok: false,
      name: "promoted_precedent_replay",
      file,
      message: `precedent ${precedent.id} replay.path must stay inside state dir`,
    });
    return;
  }

  try {
    const rawArtifact = await readFile(replayPath, "utf8");
    const artifact = parseJson(rawArtifact, replayPath);
    assertCheck(artifact.id === replay.id, checks, "promoted_precedent_replay", file, `precedent ${precedent.id} replay id does not match receipt`);
    assertCheck(sha256Text(rawArtifact) === replay.artifact_sha256, checks, "promoted_precedent_replay", file, `precedent ${precedent.id} replay artifact hash does not match receipt`);
    assertCheck(artifact.promotion?.baseline_failures === precedent.promotion?.baseline_failures, checks, "promoted_precedent_replay", file, `precedent ${precedent.id} baseline failure count does not match replay`);
    assertCheck(artifact.promotion?.rerun_failures === precedent.promotion?.rerun_failures, checks, "promoted_precedent_replay", file, `precedent ${precedent.id} rerun failure count does not match replay`);
    assertCheck(artifact.baseline?.exitCode === replay.baseline_exit_code, checks, "promoted_precedent_replay", file, `precedent ${precedent.id} baseline exit code does not match replay`);
    assertCheck(artifact.rerun?.exitCode === replay.rerun_exit_code, checks, "promoted_precedent_replay", file, `precedent ${precedent.id} rerun exit code does not match replay`);
  } catch (error) {
    checks.push({
      ok: false,
      name: "promoted_precedent_replay",
      file,
      message: `precedent ${precedent.id} replay receipt is invalid: ${error.message}`,
    });
  }
}

function pathWithin(parent, child) {
  return child === parent || child.startsWith(`${parent}/`);
}

function checkPrecedentGuards(precedent, checks, file) {
  if (precedent.guards === undefined) {
    return;
  }

  assertCheck(Array.isArray(precedent.guards), checks, "precedent_guard", file, `precedent ${precedent.id} guards must be an array`);
  if (!Array.isArray(precedent.guards)) {
    return;
  }

  for (const guard of precedent.guards) {
    assertCheck(typeof guard.id === "string" && guard.id.length > 0, checks, "precedent_guard", file, `precedent ${precedent.id} guard.id is required`);
    assertCheck(SUPPORTED_GUARD_TYPES.has(guard.type), checks, "precedent_guard", file, `precedent ${precedent.id} guard ${guard.id ?? "(missing)"} type is unsupported`);

    if (guard.type === "changed_files_within_paths") {
      assertCheck(Array.isArray(guard.paths) && guard.paths.length > 0, checks, "precedent_guard", file, `precedent ${precedent.id} guard ${guard.id} paths are required`);
    }

    if (guard.type === "required_validation_command") {
      assertCheck(typeof guard.command === "string" && guard.command.length > 0, checks, "precedent_guard", file, `precedent ${precedent.id} guard ${guard.id} command is required`);
    }
  }
}

async function readJsonLinesForCheck(path) {
  const content = await readFile(path, "utf8");

  return content
    .split("\n")
    .filter((line) => line.trim().length > 0)
    .map((line) => JSON.parse(line));
}

async function checkNoRawSecrets(checks, stateDir) {
  const files = await allFiles(stateDir);
  const findings = [];

  for (const file of files) {
    const content = await readFile(file, "utf8");
    if (Object.keys(redactSecrets(content).counts).length > 0) {
      findings.push(file);
    }
  }

  checks.push({
    ok: findings.length === 0,
    name: "raw_secret_scan",
    files: findings,
    message: findings.length > 0 ? "raw secret-like values found in state" : undefined,
  });
}

async function checkManifestBuilds(checks) {
  const manifest = buildManifest(args.runtime ?? "generic", runtimeConfig.stateDir);
  checks.push({
    ok: manifest.schema_version === "precedent.manifest.v1" && manifest.hooks["context.before_turn"].injectFrom === "contextBlock",
    name: "manifest",
  });
}

async function checkStrictStateArtifacts(checks, stateDir) {
  const lockDir = join(stateDir, "state.lock");

  try {
    await stat(lockDir);
    checks.push({
      ok: false,
      name: "state_lock",
      file: lockDir,
      message: "state lock exists",
    });
  } catch (error) {
    if (error.code === "ENOENT") {
      checks.push({ ok: true, name: "state_lock", file: lockDir });
    } else {
      checks.push({ ok: false, name: "state_lock", file: lockDir, message: error.message });
    }
  }

  const tempFiles = (await allFiles(stateDir)).filter((file) => file.endsWith(".tmp"));
  checks.push({
    ok: tempFiles.length === 0,
    name: "atomic_temp_files",
    files: tempFiles,
    message: tempFiles.length > 0 ? "temporary atomic-write files remain" : undefined,
  });
}

function validateConfigForCheck(config, name, file, checks) {
  const before = checks.length;
  try {
    validateConfig(config, name);
  } catch (error) {
    checks.push({ ok: false, name, file, message: error.message });
  }

  return checks.length === before;
}

function assertCheck(condition, checks, name, file, message) {
  if (!condition) {
    checks.push({ ok: false, name, file, message });
  }
}

async function jsonFiles(dir, suffix = ".json") {
  try {
    const entries = await readdir(dir, { withFileTypes: true });
    return entries
      .filter((entry) => entry.isFile() && entry.name.endsWith(suffix))
      .map((entry) => join(dir, entry.name))
      .sort();
  } catch (error) {
    if (error.code === "ENOENT") {
      return [];
    }

    throw error;
  }
}

async function replayJsonFiles(replaysDir) {
  return (await childDirs(replaysDir))
    .map((dir) => join(dir, "replay.json"))
    .sort();
}

async function allFiles(dir) {
  try {
    const entries = await readdir(dir, { withFileTypes: true });
    const files = [];

    for (const entry of entries) {
      const path = join(dir, entry.name);
      if (entry.isDirectory()) {
        files.push(...await allFiles(path));
      } else if (entry.isFile()) {
        files.push(path);
      }
    }

    return files;
  } catch (error) {
    if (error.code === "ENOENT") {
      return [];
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
    await writeFileAtomic(path, "");
  }
}

async function appendJsonLine(path, value) {
  await ensureFile(path);
  await appendFile(path, `${JSON.stringify(redactSecretsDeep(value).value)}\n`);
}

async function writeJsonLines(path, values) {
  await ensureFile(path);
  await writeFileAtomic(path, values.map((value) => JSON.stringify(redactSecretsDeep(value).value)).join("\n") + (values.length > 0 ? "\n" : ""));
}

async function writeFileAtomic(path, content) {
  await mkdir(dirname(path), { recursive: true });
  const tempPath = `${path}.${process.pid}.${Date.now()}.${atomicWriteCounter++}.tmp`;
  await writeFile(tempPath, content);
  await rename(tempPath, path);
}

async function withStateLock(stateDir, fn, { failOpen = false } = {}) {
  const resolvedStateDir = resolve(stateDir);
  if (activeLockDir === resolvedStateDir) {
    return fn();
  }

  await mkdir(resolvedStateDir, { recursive: true });
  const lockDir = join(resolvedStateDir, "state.lock");
  const timeoutMs = failOpen ? Math.min(runtimeConfig.hookTimeoutMs, 1500) : 5000;
  const startedAt = Date.now();

  while (true) {
    try {
      await mkdir(lockDir);
      await writeFile(join(lockDir, "owner.json"), JSON.stringify({
        pid: process.pid,
        createdAt: new Date().toISOString(),
      }));
      break;
    } catch (error) {
      if (error.code !== "EEXIST") {
        throw error;
      }

      if (await removeStaleLock(lockDir)) {
        continue;
      }

      if (Date.now() - startedAt > timeoutMs) {
        if (failOpen) {
          return { lockTimeout: true };
        }

        fail(`state lock timeout: ${lockDir}`);
      }

      await sleep(25);
    }
  }

  activeLockDir = resolvedStateDir;
  try {
    return await fn();
  } finally {
    activeLockDir = null;
    await rm(lockDir, { recursive: true, force: true });
  }
}

async function removeStaleLock(lockDir) {
  try {
    const info = await stat(lockDir);
    if (Date.now() - info.mtimeMs > 30000) {
      await rm(lockDir, { recursive: true, force: true });
      return true;
    }
  } catch (error) {
    if (error.code === "ENOENT") {
      return true;
    }

    throw error;
  }

  return false;
}

function sleep(ms) {
  return new Promise((resolvePromise) => setTimeout(resolvePromise, ms));
}

const SECRET_PATTERNS = [
  {
    type: "bearer_token",
    pattern: /\bBearer\s+([A-Za-z0-9._~+/-]{10,}=*)/gu,
    replace: () => "Bearer [REDACTED:bearer_token]",
  },
  {
    type: "openai_key",
    pattern: /\bsk-(?:live|test|proj)?-?[A-Za-z0-9_-]{10,}\b/gu,
    replace: () => "[REDACTED:openai_key]",
  },
  {
    type: "github_token",
    pattern: /\b(?:ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9_]{20,}\b/gu,
    replace: () => "[REDACTED:github_token]",
  },
  {
    type: "slack_token",
    pattern: /\bxox[baprs]-[A-Za-z0-9-]{10,}\b/gu,
    replace: () => "[REDACTED:slack_token]",
  },
  {
    type: "connection_string_password",
    pattern: /\b((?:postgres|postgresql|mysql|redis):\/\/[^:\s/]+:)([^@\s]+)(@)/giu,
    replace: (_match, prefix, _password, suffix) => `${prefix}[REDACTED:connection_string_password]${suffix}`,
  },
  {
    type: "credential",
    pattern: /\b(api[_-]?key|access[_-]?token|refresh[_-]?token|auth[_-]?token|password|passwd|secret)\b(\s*[:=]\s*)(["']?)([^\s"',}&]{8,})(["']?)/giu,
    replace: (_match, name, separator, openQuote, _secret, closeQuote) => `${name}${separator}${openQuote}[REDACTED:credential]${closeQuote}`,
  },
];

function redactSecretsDeep(value, counts = {}) {
  if (typeof value === "string") {
    return redactSecrets(value, counts);
  }

  if (Array.isArray(value)) {
    return {
      value: value.map((item) => redactSecretsDeep(item, counts).value),
      counts,
    };
  }

  if (value && typeof value === "object") {
    const redacted = {};

    for (const [key, item] of Object.entries(value)) {
      redacted[key] = redactSecretsDeep(item, counts).value;
    }

    return {
      value: redacted,
      counts,
    };
  }

  return { value, counts };
}

function redactSecrets(value, counts = {}) {
  let redacted = value;

  for (const secretPattern of SECRET_PATTERNS) {
    redacted = redacted.replace(secretPattern.pattern, (...match) => {
      counts[secretPattern.type] = (counts[secretPattern.type] ?? 0) + 1;
      return secretPattern.replace(...match);
    });
  }

  return {
    value: redacted,
    counts,
  };
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
  return resolve(args["state-dir"] ?? runtimeConfig.stateDir ?? DEFAULT_STATE_DIR);
}

function safeFileName(value) {
  return value.replace(/[^a-zA-Z0-9_.-]/gu, "_");
}

function print(value) {
  if (printCaptureStack.length > 0) {
    printCaptureStack[printCaptureStack.length - 1] = value;
    return;
  }

  if (args.json) {
    process.stdout.write(`${JSON.stringify(value)}\n`);
    return;
  }

  process.stdout.write(`${JSON.stringify(value, null, 2)}\n`);
}

async function capturePrintedPayload(fn) {
  printCaptureStack.push(undefined);

  try {
    await fn();
    const payload = printCaptureStack[printCaptureStack.length - 1];

    if (payload === undefined) {
      fail("hook produced no response");
    }

    return payload;
  } finally {
    printCaptureStack.pop();
  }
}

async function withFailThrows(fn) {
  const previous = failThrows;
  failThrows = true;

  try {
    return await fn();
  } finally {
    failThrows = previous;
  }
}

function printHelp() {
  process.stdout.write(`precedent: passive hook memory for agent-readiness

Usage:
  precedent init [--state-dir .precedent]
  precedent observe --trace trace.json [--state-dir .precedent]
  precedent observe --session session-id [--state-dir .precedent]
  precedent context --task "add webhook handler" [--scope feature:webhooks] [--include-stale] [--format json|markdown]
  precedent warrant --session session-id --event-id event-id --task "add webhook handler" [--scope feature:webhooks]
  precedent artifact --candidate candidate-id [--state-dir .precedent]
  precedent compile [--state-dir .precedent] [--promote-session-pairs]
  precedent replay --case replay-case.json [--trace-out trace.json] [--state-dir .precedent]
  precedent replay --candidate candidate-id --baseline-command "cmd" [--rerun-command "cmd"] [--trace-out trace.json]
  precedent promotion-trial --candidate candidate-id --baseline-command "cmd" [--rerun-command "cmd"] [--trace-out trace.json]
  precedent promote-pending [--state-dir .precedent] [--dry-run]
  precedent inject --task "add webhook handler" [--scope feature:webhooks] [--limit 2]
  precedent explain --id precedent-id [--state-dir .precedent]
  precedent hook [--event-file hook.json] [--state-dir .precedent] [--limit 2]
  precedent hook < hook-event.json
  precedent loop [--state-dir .precedent]
  precedent hook before-turn --task "add webhook handler" [--scope feature:webhooks] [--changed-files paths]
  precedent run --session session-id [--state-dir .precedent] -- command [args...]
  precedent manifest [--runtime generic|codex] [--state-dir .precedent]
  precedent attach [--runtime generic|codex] [--session session-id|--thread-id thread-id] --task "text"
  precedent attach-run --task "text" --validation-command "cmd" [--diff-changed-files paths] [--session session-id|--thread-id thread-id] [--event-prefix id] [--repair-id id --repair-session-id session-id] [--auto-promote]
  precedent check [--state-dir .precedent] [--strict]
  precedent prune [--state-dir .precedent] [--dry-run] [--before ISO-date]
  precedent report [--state-dir .precedent]

Commands:
  init      Create local Precedent state.
  observe   Ingest one agent trace or recorded hook session.
  context   Export stable agent-ready precedent context.
  warrant   Issue a machine-readable edit and evidence contract for one turn.
  artifact  Render a non-injectable SKILL.md preview for a candidate.
  compile   Mine observed raw traces into candidates, optionally promoting analogous session pairs.
  replay    Run baseline/rerun commands and emit verified promotion evidence.
  promotion-trial Run a candidate replay and immediately observe the promotion decision.
  promote-pending Run queued promotion trial work orders emitted by validation hooks.
  inject    Return relevant precedent for the current task.
  explain   Explain promotion evidence, matching inputs, and injection history.
  hook      Run a passive hook from JSON, including the before-response finalization gate.
  loop      Run a JSONL hook loop over stdin and emit one JSON response per line.
  run       Run a validation command and capture it as a session hook event.
  manifest  Emit the machine-readable runtime hook contract.
  attach    Emit a zero-touch runtime adapter contract for one session.
  attach-run Run before-turn, warrant, validation, optional diff, self-healing finalization, repair handoff/receipt, outcome, and optional queued promotion hooks.
  check     Validate local Precedent state for CI.
  prune     Remove old non-promoted state using retention config.
  report    Summarize local precedent state.

Config:
  Defaults load from .precedent/config.json or PRECEDENT_CONFIG.
  CLI flags such as --state-dir and --limit override config values.
`);
}

function fail(message) {
  if (failThrows) {
    throw new Error(message);
  }

  process.stderr.write(`precedent: ${message}\n`);
  process.exit(1);
}

main().catch((error) => {
  fail(error.stack ?? error.message);
});
