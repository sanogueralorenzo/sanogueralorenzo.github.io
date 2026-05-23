#!/usr/bin/env node

import { createHash, randomBytes } from "node:crypto";
import { spawn } from "node:child_process";
import { access, chmod, lstat, mkdir, readFile, readlink, readdir, realpath, rm, stat, symlink, writeFile } from "node:fs/promises";
import { constants as fsConstants } from "node:fs";
import { homedir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const TRACE_DIR = ".trace";
const CONFIG_VERSION = "trace.config.v1";
const MEMORY_VERSION = "trace.memory.v1";
const CHECKPOINT_REF = "refs/trace/checkpoints";
const HOOK_START = "# trace:start";
const HOOK_END = "# trace:end";
const AGENT_CONFIG_VERSION = "trace.agent.v1";
const SUPPORTED_AGENTS = new Set(["codex", "claude-code", "gemini", "generic"]);
const TRACE_EVENTS = ["prompt", "response", "tool", "decision", "validation", "risk", "note"];
const AGENT_CONTRACTS = {
  codex: {
    fixture: "codex-tool-call.json",
    event: "tool",
    messageIncludes: ["codex tool shell", "npm --prefix trace test"],
  },
  "claude-code": {
    fixture: "claude-code-user-prompt.json",
    event: "prompt",
    messageIncludes: ["Trace memory storage model"],
  },
  gemini: {
    fixture: "gemini-model-response.json",
    event: "response",
    messageIncludes: ["verified the Trace tests"],
  },
  generic: {
    fixture: "generic-validation.json",
    event: "validation",
    messageIncludes: ["npm --prefix trace test passed"],
  },
};
const MEMORY_SECTION_LIMIT = 5;
const MEMORY_ITEM_CHAR_LIMIT = 240;
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
    await initRepo();
    return;
  }

  if (command === "enable") {
    await enableRepo();
    return;
  }

  if (command === "disable") {
    await disableRepo();
    return;
  }

  if (command === "install") {
    await runInstallCommand(subcommand, rawArgs);
    return;
  }

  if (command === "status") {
    await printStatus();
    return;
  }

  if (command === "doctor") {
    await runDoctor();
    return;
  }

  if (command === "check") {
    await checkTrace();
    return;
  }

  if (command === "coverage") {
    await runCoverageReport(subcommand ?? args.range ?? defaultSummaryRange());
    return;
  }

  if (command === "ci") {
    await runCiCheck(subcommand ?? args.range ?? defaultSummaryRange());
    return;
  }

  if (command === "checkpoint") {
    await runCheckpointCommand(subcommand, rawArgs);
    return;
  }

  if (command === "redact") {
    await runRedactCommand(subcommand, rawArgs);
    return;
  }

  if (command === "capture") {
    await captureEvent();
    return;
  }

  if (command === "run") {
    await runTraceCommand(subcommand, rawArgs);
    return;
  }

  if (command === "session") {
    await runSessionCommand(subcommand, rawArgs);
    return;
  }

  if (command === "agent") {
    await runAgentCommand(subcommand, rawArgs);
    return;
  }

  if (command === "record") {
    await recordMemory();
    return;
  }

  if (command === "show") {
    await showMemory(subcommand ?? "HEAD");
    return;
  }

  if (command === "review") {
    await reviewMemories();
    return;
  }

  if (command === "log") {
    await logMemories();
    return;
  }

  if (command === "index") {
    await rebuildSearchIndex();
    return;
  }

  if (command === "search") {
    await searchMemories([subcommand, ...positionalValues(rawArgs)].filter(Boolean).join(" "));
    return;
  }

  if (command === "recall" || command === "context") {
    await recallMemories([subcommand, ...positionalValues(rawArgs)].filter(Boolean).join(" "));
    return;
  }

  if (command === "summary") {
    await summarizeRange(subcommand ?? args.range ?? defaultSummaryRange());
    return;
  }

  if (command === "branch-summary" || command === "branch") {
    await summarizeBranch(subcommand ?? args.branch ?? "HEAD");
    return;
  }

  if (command === "pr-body" || command === "pr") {
    await summarizeRange(subcommand ?? args.range ?? defaultSummaryRange(), { prBody: true });
    return;
  }

  if (command === "release-notes" || command === "release") {
    await summarizeRange(subcommand ?? args.range ?? defaultSummaryRange(), { releaseNotes: true });
    return;
  }

  if (command === "hook" && subcommand === "prepare-commit-msg") {
    await hookPrepareCommitMsg(rawArgs);
    return;
  }

  if (command === "hook" && subcommand === "pre-commit") {
    await hookPreCommit();
    return;
  }

  if (command === "hook" && subcommand === "post-commit") {
    await hookPostCommit();
    return;
  }

  if (command === "hook" && subcommand === "agent") {
    await hookAgent(rawArgs);
    return;
  }

  fail(`unknown command: ${[command, subcommand].filter(Boolean).join(" ")}`);
}

function parseArgs(values) {
  const parsed = {};

  for (let index = 0; index < values.length; index += 1) {
    const value = values[index];

    if (value === "--") {
      break;
    }

    if (!value.startsWith("--")) {
      continue;
    }

    const key = value.slice(2);
    if (["json", "help", "dry-run", "check-session", "strict", "strict-memory", "all", "agents", "checkpoints", "install", "update", "uninstall", "status"].includes(key)) {
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

async function initRepo() {
  const root = await repoRoot();
  const traceRoot = join(root, TRACE_DIR);
  await mkdir(join(traceRoot, "commits"), { recursive: true });
  await writeFileIfMissing(join(traceRoot, "config.json"), `${JSON.stringify({
    schema_version: CONFIG_VERSION,
    enabled: true,
    memory_dir: ".trace/commits",
    checkpoint_ref: CHECKPOINT_REF,
    raw_storage: "git-common-dir/trace/sessions",
    redaction: {
      custom_rules: [],
    },
  }, null, 2)}\n`);
  await writeFileIfMissing(join(traceRoot, "commits", ".gitkeep"), "");
  print({ ok: true, traceDir: TRACE_DIR });
}

async function enableRepo() {
  await initRepo();
  await installHook("pre-commit", traceHookCommand("pre-commit"));
  await installHook("prepare-commit-msg", traceHookCommand("prepare-commit-msg"));
  await installHook("post-commit", traceHookCommand("post-commit"));
  print({ ok: true, enabled: true });
}

async function disableRepo() {
  const hooksDir = await gitHooksDir();
  await removeManagedBlock(join(hooksDir, "pre-commit"));
  await removeManagedBlock(join(hooksDir, "prepare-commit-msg"));
  await removeManagedBlock(join(hooksDir, "post-commit"));
  print({ ok: true, enabled: false });
}

async function runInstallCommand(action, values) {
  const installAction = args.install ? "install"
    : args.update ? "update"
      : args.uninstall ? "uninstall"
        : args.status ? "status"
          : action ?? "install";

  if (installAction === "install" || installAction === "update") {
    await writeInstallLink(installAction, values);
    return;
  }

  if (installAction === "uninstall") {
    await removeInstallLink(values);
    return;
  }

  if (installAction === "status") {
    await printInstallStatus(values);
    return;
  }

  fail(`unknown install command: ${installAction}`);
}

async function printInstallStatus(values) {
  print(await installStatusPayload(values));
}

async function installStatusPayload(values = []) {
  const prefix = args.prefix ?? positionalValues(values)[0] ?? process.env.TRACE_INSTALL_DIR ?? join(homedir(), ".local", "bin");
  const installDir = resolve(process.cwd(), prefix);
  const target = join(installDir, "trace");
  const source = fileURLToPath(import.meta.url);
  const targetStatus = await traceInstallTargetStatus(target, source);
  return {
    ok: true,
    installDir,
    target,
    source,
    installed: targetStatus.installed,
    valid: targetStatus.valid,
    kind: targetStatus.kind,
    linkTarget: targetStatus.linkTarget,
    expectedLinkTarget: source,
    installCommand: `./trace/install.sh --prefix ${shellQuote(installDir)}`,
    updateCommand: `./trace/install.sh --update --prefix ${shellQuote(installDir)}`,
    uninstallCommand: `./trace/install.sh --uninstall --prefix ${shellQuote(installDir)}`,
  };
}

async function writeInstallLink(action, values) {
  const status = await installStatusPayload(values);
  const existing = await lstat(status.target).catch(() => null);
  if (existing?.isDirectory()) {
    fail(`install target is a directory: ${status.target}`);
  }

  await mkdir(status.installDir, { recursive: true });
  await rm(status.target, { force: true });
  await symlink(status.source, status.target);
  const next = await installStatusPayload(values);
  print({
    ok: next.valid,
    schema_version: "trace.install_result.v1",
    action,
    target: next.target,
    source: next.source,
    installed: next.installed,
    valid: next.valid,
    kind: next.kind,
  });
}

async function removeInstallLink(values) {
  const status = await installStatusPayload(values);
  await rm(status.target, { force: true });
  const next = await installStatusPayload(values);
  print({
    ok: true,
    schema_version: "trace.install_result.v1",
    action: "uninstall",
    target: next.target,
    source: next.source,
    installed: next.installed,
    valid: next.valid,
    kind: next.kind,
  });
}

async function traceInstallTargetStatus(target, source) {
  const info = await lstat(target).catch(() => null);
  if (!info) {
    return { installed: false, valid: false, kind: "missing", linkTarget: null };
  }

  if (!info.isSymbolicLink()) {
    const resolved = await realpath(target).catch(() => null);
    const expected = await realpath(source).catch(() => source);
    return {
      installed: true,
      valid: resolved === expected,
      kind: info.isFile() ? "file" : "other",
      linkTarget: resolved,
    };
  }

  const link = await readlink(target);
  const resolved = resolve(dirname(target), link);
  const expected = await realpath(source).catch(() => source);
  const actual = await realpath(target).catch(() => resolved);
  return {
    installed: true,
    valid: actual === expected,
    kind: "symlink",
    linkTarget: resolved,
  };
}

async function printStatus() {
  const root = await repoRoot();
  const common = await gitCommonDir(root);
  const hooks = await traceHookStatus(root);
  const configExists = await exists(join(root, TRACE_DIR, "config.json"));
  const config = await loadTraceConfig(root);
  const agents = await listAgentConfigs(root);
  const install = await installStatusPayload();
  print({
    ok: true,
    repo: root,
    config: configExists,
    install,
    hooks,
    agents,
    redactionRules: customRules(config).length,
    rawStorage: join(common, "trace", "sessions"),
    checkpointRef: CHECKPOINT_REF,
  });
}

async function runDoctor() {
  const root = await repoRoot();
  const config = await configStatus(root);
  const hooks = await traceHookStatus(root);
  const agents = await listAgentConfigs(root);
  const invalidAgents = agents.filter((agent) => !agent.valid);
  const memories = await auditMemoryFiles(root);
  const redaction = await redactionAudit(root);
  const dirtyTrace = await dirtyTraceFiles(root);
  const memoryTargets = await memoryTargetsForFiles(root, memories.files);
  const checkpoint = await checkpointIntegrityReport(root, memoryTargets);
  const memoryQuality = args["strict-memory"] ? await strictMemoryQualityReport(root, memoryTargets) : null;
  const searchIndex = await searchIndexStatus(root);
  const install = await installStatusPayload();

  const checks = [
    {
      name: "config",
      level: "error",
      ok: config.ok,
      path: `${TRACE_DIR}/config.json`,
      schema: config.schema,
      error: config.error ?? null,
    },
    {
      name: "hooks",
      level: "error",
      ok: hooks.details.preCommit.valid && hooks.details.prepareCommitMsg.valid && hooks.details.postCommit.valid,
      preCommit: hooks.preCommit,
      prepareCommitMsg: hooks.prepareCommitMsg,
      postCommit: hooks.postCommit,
      details: hooks.details,
    },
    {
      name: "agents",
      level: "error",
      ok: invalidAgents.length === 0,
      count: agents.length,
      agents,
      invalidAgents,
    },
    {
      name: "memories",
      level: "error",
      ok: memories.invalidMemories.length === 0,
      count: memories.files.length,
      invalidMemories: memories.invalidMemories,
    },
    ...(memoryQuality ? [{
      name: "memoryQuality",
      level: "error",
      ok: memoryQuality.ok,
      strict: memoryQuality.strict,
      checked: memoryQuality.checked,
      findings: memoryQuality.findings,
    }] : []),
    {
      name: "redaction",
      level: "error",
      ok: redaction.findings.length === 0,
      scanned: redaction.scanned,
      findings: redaction.findings,
    },
    {
      name: "dirtyTrace",
      level: "warning",
      ok: dirtyTrace.length === 0,
      uncommitted: dirtyTrace,
    },
    {
      name: "checkpointRef",
      level: checkpoint.errors.length > 0 ? "error" : "warning",
      ok: checkpoint.present && checkpoint.errors.length === 0,
      ref: checkpoint.ref,
      present: checkpoint.present,
      commit: checkpoint.commit,
      checked: checkpoint.checked,
      linkedMemories: checkpoint.linkedMemories,
      errors: checkpoint.errors,
    },
    {
      name: "searchIndex",
      level: "warning",
      ok: searchIndex.present && !searchIndex.stale && !searchIndex.error,
      path: searchIndex.path,
      present: searchIndex.present,
      entries: searchIndex.entries,
      files: searchIndex.files,
      stale: searchIndex.stale,
      error: searchIndex.error ?? null,
      rebuild: "trace index",
    },
    {
      name: "install",
      level: "warning",
      ok: install.valid,
      installed: install.installed,
      valid: install.valid,
      installDir: install.installDir,
      target: install.target,
      source: install.source,
      kind: install.kind,
      linkTarget: install.linkTarget,
      expectedLinkTarget: install.expectedLinkTarget,
      installCommand: install.installCommand,
      updateCommand: install.updateCommand,
      uninstallCommand: install.uninstallCommand,
    },
  ];
  const ok = checks.every((check) => check.ok || check.level === "warning");
  print({ ok, repo: root, checks });

  if (!ok) {
    process.exitCode = 1;
  }
}

async function checkTrace() {
  const root = await repoRoot();
  const { files, invalidMemories } = await auditMemoryFiles(root);
  const dirtyTrace = await dirtyTraceFiles(root);
  const checkpointRef = await git(["rev-parse", "--verify", CHECKPOINT_REF], { cwd: root, allowFailure: true });
  const checkpointIntegrity = args.checkpoints
    ? await checkpointIntegrityReport(root, await memoryTargetsForFiles(root, files))
    : null;
  const memoryQuality = args["strict-memory"] ? await strictMemoryQualityReport(root, await memoryTargetsForFiles(root, files)) : null;
  const ok = invalidMemories.length === 0
    && dirtyTrace.length === 0
    && (checkpointIntegrity?.ok ?? true)
    && (memoryQuality?.ok ?? true);
  print({
    ok,
    memories: files.length,
    checkpointRef: checkpointRef || null,
    uncommitted: dirtyTrace,
    invalidMemories,
    checkpointIntegrity,
    memoryQuality,
  });

  if (!ok) {
    process.exitCode = 1;
  }
}

async function memoryTargetsForFiles(root, files) {
  const memories = [];
  for (const file of files) {
    const content = await readFile(file, "utf8");
    const commit = content.match(/^Commit: `([^`]+)`/m)?.[1];
    if (commit) {
      memories.push({ commit, memory: relativePath(root, file) });
    }
  }
  return memories;
}

async function runCiCheck(range) {
  const root = await repoRoot();
  const report = await buildCoverageReport(root, range, { agents: args.agents, checkpoints: args.checkpoints, strictMemory: args["strict-memory"] });
  print(report);

  if (!report.ok) {
    process.exitCode = 1;
  }
}

async function runCoverageReport(range) {
  const root = await repoRoot();
  print(await buildCoverageReport(root, range, { agents: args.agents, checkpoints: args.checkpoints, strictMemory: args["strict-memory"] }));
}

async function buildCoverageReport(root, range, options = {}) {
  const commits = (await git(["rev-list", "--reverse", range], { cwd: root })).split("\n").filter(Boolean);
  const missingMemories = [];
  const coveredMemories = [];
  const skippedCommits = [];
  const entries = [];

  for (const sha of commits) {
    if (await isTraceOnlyCommit(root, sha)) {
      skippedCommits.push(sha);
      entries.push(await coverageEntry(root, sha, "skipped", null));
      continue;
    }

    const memoryPath = memoryPathFor(root, sha);
    if (!await exists(memoryPath)) {
      const missing = await coverageEntry(root, sha, "missing", relativePath(root, memoryPath));
      missingMemories.push({ commit: sha, expected: missing.memory });
      entries.push(missing);
    } else {
      const covered = await coverageEntry(root, sha, "covered", relativePath(root, memoryPath));
      coveredMemories.push({ commit: sha, memory: covered.memory });
      entries.push(covered);
    }
  }

  const traceFiles = (await git(["ls-files", "-co", "--exclude-standard", "--", TRACE_DIR], { cwd: root })).split("\n").filter(Boolean);
  const unsafeFiles = traceFiles.filter(isUnsafeTracePath);
  const memoryAudit = await auditMemoryFiles(root);
  const redaction = await redactionAudit(root);
  const agentContracts = options.agents ? await buildAgentCheckReport(root, "all") : null;
  const checkpointIntegrity = options.checkpoints ? await checkpointIntegrityReport(root, coveredMemories) : null;
  const memoryQuality = options.strictMemory ? await strictMemoryQualityReport(root, coveredMemories) : null;
  const ok = missingMemories.length === 0
    && unsafeFiles.length === 0
    && memoryAudit.invalidMemories.length === 0
    && redaction.findings.length === 0
    && (agentContracts?.ok ?? true)
    && (checkpointIntegrity?.ok ?? true)
    && (memoryQuality?.ok ?? true);
  const memoryTotal = coveredMemories.length + missingMemories.length;
  return {
    ok,
    range,
    checked: commits.length,
    covered: coveredMemories.length,
    missing: missingMemories.length,
    skipped: skippedCommits.length,
    coverage: memoryTotal === 0 ? 1 : coveredMemories.length / memoryTotal,
    commits: entries,
    coveredMemories,
    missingMemories,
    unsafeFiles,
    invalidMemories: memoryAudit.invalidMemories,
    redactionFindings: redaction.findings,
    agentContracts,
    checkpointIntegrity,
    memoryQuality,
  };
}

async function strictMemoryQualityReport(root, coveredMemories) {
  const findings = [];

  for (const memory of coveredMemories) {
    const file = join(root, memory.memory);
    const content = await readFile(file, "utf8");
    const record = memoryRecord(content);
    if (!record.intent) {
      findings.push({ file: memory.memory, commit: memory.commit, reason: "missing intent signal" });
    }
    if (record.decisions.length === 0) {
      findings.push({ file: memory.memory, commit: memory.commit, reason: "missing decision signal" });
    }
    if (record.validation.length === 0) {
      findings.push({ file: memory.memory, commit: memory.commit, reason: "missing validation signal" });
    }
  }

  return {
    ok: findings.length === 0,
    strict: true,
    checked: coveredMemories.length,
    findings,
  };
}

async function checkpointIntegrityReport(root, coveredMemories = []) {
  const audit = await checkpointAudit(root);
  const memoryLinks = audit.present ? await checkpointMemoryLinkErrors(root, coveredMemories) : { checked: 0, errors: [] };
  const errors = [...audit.errors, ...memoryLinks.errors];
  return {
    ok: audit.present && errors.length === 0,
    ref: audit.ref,
    present: audit.present,
    commit: audit.commit,
    checked: audit.checked,
    linkedMemories: memoryLinks.checked,
    errors,
  };
}

async function checkpointMemoryLinkErrors(root, coveredMemories) {
  const checkpointPayloads = await readCheckpointPayloads(root);
  const checkpointsById = new Map(
    checkpointPayloads
      .filter(({ payload, error }) => payload?.checkpoint_id && !error)
      .map(({ payload }) => [payload.checkpoint_id, payload]),
  );
  const errors = [];

  for (const memory of coveredMemories) {
    const file = join(root, memory.memory);
    const content = await readFile(file, "utf8");
    const checkpoint = content.match(/^Checkpoint: `([^`]+)`/m)?.[1];
    if (!checkpoint) {
      continue;
    }

    const payload = checkpointsById.get(checkpoint);
    if (!payload) {
      errors.push({ file: memory.memory, checkpoint, error: `missing checkpoint payload ${checkpoint}` });
      continue;
    }

    if (payload.commit && payload.commit !== memory.commit) {
      errors.push({ file: memory.memory, checkpoint, error: `checkpoint commit mismatch ${payload.commit}` });
    }
  }

  return { checked: coveredMemories.length, errors };
}

async function coverageEntry(root, sha, status, memory) {
  const subject = await git(["show", "-s", "--format=%s", sha], { cwd: root });
  return {
    commit: sha,
    subject,
    status,
    memory,
  };
}

async function runCheckpointCommand(action, values) {
  if (!action || action === "list") {
    await listCheckpoints();
    return;
  }

  if (action === "status") {
    await checkpointStatus(values[0] ?? args.remote ?? "origin");
    return;
  }

  if (action === "verify") {
    await verifyCheckpoints();
    return;
  }

  if (action === "show") {
    await showCheckpoint(values[0] ?? args.checkpoint);
    return;
  }

  if (action === "push") {
    await syncCheckpointRef("push", values[0] ?? args.remote ?? "origin");
    return;
  }

  if (action === "fetch") {
    await syncCheckpointRef("fetch", values[0] ?? args.remote ?? "origin");
    return;
  }

  if (action === "export") {
    await exportCheckpointBundle(values);
    return;
  }

  if (action === "import") {
    await importCheckpointBundle(values);
    return;
  }

  if (action === "cleanup") {
    await cleanupCheckpoints();
    return;
  }

  fail(`unknown checkpoint command: ${action}`);
}

async function listCheckpoints() {
  const root = await repoRoot();
  const limit = args.limit == null ? null : parsePositiveInteger(args.limit, "--limit");
  const checkpoints = await readCheckpointPayloads(root);
  const sorted = limit == null
    ? checkpoints
    : [...checkpoints].sort((left, right) => checkpointSortKey(right).localeCompare(checkpointSortKey(left)));
  const limited = limit == null ? sorted : sorted.slice(0, limit);
  print({
    ok: true,
    ref: CHECKPOINT_REF,
    total: checkpoints.length,
    limit,
    checkpoints: limited.map(({ payload }) => checkpointSummary(payload)),
  });
}

async function verifyCheckpoints() {
  const root = await repoRoot();
  const audit = await checkpointAudit(root);
  const ok = audit.errors.length === 0;
  print({
    ok,
    ref: audit.ref,
    present: audit.present,
    checked: audit.checked,
    errors: audit.errors,
  });
  if (!ok) {
    process.exitCode = 1;
  }
}

async function showCheckpoint(checkpointId) {
  if (!checkpointId) {
    fail("checkpoint id is required");
  }

  const root = await repoRoot();
  const checkpoints = await readCheckpointPayloads(root);
  const match = checkpoints.find(({ path, payload }) => (
    payload?.checkpoint_id === checkpointId || path === `checkpoints/${checkpointId}.json`
  ));
  if (!match) {
    fail(`checkpoint not found: ${checkpointId}`);
  }
  if (match.error || !match.payload) {
    fail(`checkpoint ${checkpointId} is unreadable: ${match.error ?? "missing payload"}`);
  }

  const integrityError = verifyCheckpointIntegrity(match.payload);
  if (args.json) {
    print({
      ok: true,
      schema_version: "trace.checkpoint_detail.v1",
      ref: CHECKPOINT_REF,
      path: match.path,
      integrity: {
        ok: integrityError == null,
        error: integrityError,
      },
      checkpoint: match.payload,
    });
    return;
  }

  const limit = parsePositiveInteger(args.limit ?? "20", "--limit");
  const events = Array.isArray(match.payload.events) ? match.payload.events : [];
  const lines = [
    "# Trace Checkpoint",
    "",
    `Checkpoint: \`${match.payload.checkpoint_id}\``,
    `Ref: \`${CHECKPOINT_REF}\``,
    `Path: \`${match.path}\``,
    `Commit: \`${match.payload.commit}\``,
    `Session: \`${match.payload.session_id ?? "none"}\``,
    `Created: \`${match.payload.created_at ?? ""}\``,
    `Integrity: \`${integrityError ?? "ok"}\``,
    `Events: ${events.length}`,
    "",
    "## Files",
    "",
    ...checkpointFileLines(match.payload.files),
    "",
    "## Events",
    "",
  ];

  for (const event of events.slice(0, limit)) {
    lines.push(`- ${checkpointEventLine(event)}`);
  }
  const omitted = events.length - Math.min(events.length, limit);
  if (omitted > 0) {
    lines.push(`- ${omitted} more event${omitted === 1 ? "" : "s"} omitted. Use \`--json\` for the full payload.`);
  }
  if (events.length === 0) {
    lines.push("- No events recorded.");
  }

  process.stdout.write(`${lines.join("\n").trimEnd()}\n`);
}

async function checkpointStatus(remote) {
  const root = await repoRoot();
  const localCommit = await git(["rev-parse", "--verify", CHECKPOINT_REF], { cwd: root, allowFailure: true });
  const remoteCommit = await remoteCheckpointCommit(root, remote);
  const distance = await checkpointDistance(root, localCommit, remoteCommit);
  print({
    ok: true,
    ref: CHECKPOINT_REF,
    remote,
    localPresent: Boolean(localCommit),
    localCommit: localCommit || null,
    remotePresent: Boolean(remoteCommit),
    remoteCommit: remoteCommit || null,
    inSync: Boolean(localCommit && remoteCommit && localCommit === remoteCommit),
    ahead: distance?.ahead ?? null,
    behind: distance?.behind ?? null,
    pushCommand: `git push ${remote} ${CHECKPOINT_REF}:${CHECKPOINT_REF}`,
    fetchCommand: `git fetch ${remote} ${CHECKPOINT_REF}:${CHECKPOINT_REF}`,
  });
}

async function remoteCheckpointCommit(root, remote) {
  const output = await git(["ls-remote", remote, CHECKPOINT_REF], { cwd: root, allowFailure: true });
  return output.split(/\s+/)[0] || "";
}

async function checkpointDistance(root, localCommit, remoteCommit) {
  if (!localCommit || !remoteCommit) {
    return null;
  }

  const remoteObject = await git(["rev-parse", "--verify", `${remoteCommit}^{commit}`], { cwd: root, allowFailure: true });
  if (!remoteObject && localCommit !== remoteCommit) {
    return null;
  }

  const ahead = localCommit === remoteCommit
    ? "0"
    : await git(["rev-list", "--count", `${remoteCommit}..${localCommit}`], { cwd: root, allowFailure: true });
  const behind = localCommit === remoteCommit
    ? "0"
    : await git(["rev-list", "--count", `${localCommit}..${remoteCommit}`], { cwd: root, allowFailure: true });
  return {
    ahead: ahead === "" ? null : Number.parseInt(ahead, 10),
    behind: behind === "" ? null : Number.parseInt(behind, 10),
  };
}

async function checkpointAudit(root) {
  const commit = await git(["rev-parse", "--verify", CHECKPOINT_REF], { cwd: root, allowFailure: true });
  if (!commit) {
    return { ref: CHECKPOINT_REF, present: false, commit: null, checked: 0, errors: [] };
  }

  const checkpoints = await readCheckpointPayloads(root);
  const errors = [];

  for (const { path, payload, error } of checkpoints) {
    if (error) {
      errors.push({ path, error });
      continue;
    }

    for (const field of ["schema_version", "checkpoint_id", "commit", "created_at", "integrity"]) {
      if (!payload[field]) {
        errors.push({ path, error: `missing ${field}` });
      }
    }

    if (payload.schema_version && payload.schema_version !== "trace.checkpoint.v1") {
      errors.push({ path, error: `unsupported schema ${payload.schema_version}` });
    }

    if (payload.commit) {
      const commit = await git(["rev-parse", "--verify", `${payload.commit}^{commit}`], { cwd: root, allowFailure: true });
      if (!commit) {
        errors.push({ path, error: `missing commit ${payload.commit}` });
      }
    }

    const integrityError = verifyCheckpointIntegrity(payload);
    if (integrityError) {
      errors.push({ path, error: integrityError });
    }
  }

  return { ref: CHECKPOINT_REF, present: true, commit, checked: checkpoints.length, errors };
}

async function syncCheckpointRef(action, remote) {
  const root = await repoRoot();
  const dryRun = Boolean(args["dry-run"]);
  const gitArgs = action === "push"
    ? ["push", remote, `${CHECKPOINT_REF}:${CHECKPOINT_REF}`]
    : ["fetch", remote, `${CHECKPOINT_REF}:${CHECKPOINT_REF}`];

  if (dryRun) {
    print({ ok: true, dryRun: true, command: `git ${gitArgs.join(" ")}` });
    return;
  }

  await git(gitArgs, { cwd: root });
  print({ ok: true, command: `git ${gitArgs.join(" ")}` });
}

async function exportCheckpointBundle(values) {
  const root = await repoRoot();
  const checkpoints = await readCheckpointPayloads(root);
  const errors = checkpoints.filter((checkpoint) => checkpoint.error).map(({ path, error }) => ({ path, error }));
  if (errors.length > 0) {
    print({ ok: false, ref: CHECKPOINT_REF, errors });
    process.exitCode = 1;
    return;
  }

  const bundle = {
    schema_version: "trace.checkpoint_bundle.v1",
    created_at: now(),
    ref: CHECKPOINT_REF,
    checkpoints: checkpoints.map(({ path, payload }) => ({ path, payload })),
  };
  const output = args.output ?? args.file ?? positionalValues(values)[0];
  const content = `${JSON.stringify(bundle, null, 2)}\n`;

  if (!output || output === "-") {
    process.stdout.write(content);
    return;
  }

  const outputPath = resolve(process.cwd(), output);
  await mkdir(dirname(outputPath), { recursive: true });
  await writeFile(outputPath, content);
  print({ ok: true, path: outputPath, ref: CHECKPOINT_REF, checkpoints: bundle.checkpoints.length });
}

async function importCheckpointBundle(values) {
  const input = args.input ?? args.file ?? positionalValues(values)[0];
  if (!input) {
    fail("checkpoint import requires a bundle file");
  }

  const root = await repoRoot();
  const dryRun = Boolean(args["dry-run"]);
  const inputPath = resolve(process.cwd(), input);
  const bundle = JSON.parse(await readFile(inputPath, "utf8"));
  const imported = checkpointBundleEntries(bundle);
  const existing = await readCheckpointPayloads(root);
  const merged = new Map();

  for (const checkpoint of existing) {
    if (checkpoint.path && (checkpoint.raw || checkpoint.payload)) {
      merged.set(checkpoint.path, checkpoint);
    }
  }
  for (const checkpoint of imported) {
    merged.set(checkpoint.path, checkpoint);
  }

  if (!dryRun) {
    await writeCheckpointTree(root, Array.from(merged.values()), `Trace checkpoint import ${imported.length}`);
  }
  print({ ok: true, dryRun, path: inputPath, ref: CHECKPOINT_REF, imported: imported.length, retained: merged.size });
}

function checkpointBundleEntries(bundle) {
  if (bundle?.schema_version !== "trace.checkpoint_bundle.v1") {
    fail(`unsupported checkpoint bundle schema ${bundle?.schema_version ?? "none"}`);
  }
  if (!Array.isArray(bundle.checkpoints)) {
    fail("checkpoint bundle checkpoints must be an array");
  }

  return bundle.checkpoints.map((entry, index) => {
    const payload = entry?.payload;
    if (!payload?.checkpoint_id) {
      fail(`checkpoint bundle entry ${index} is missing checkpoint_id`);
    }
    const integrityError = verifyCheckpointIntegrity(payload);
    if (integrityError) {
      fail(`checkpoint bundle entry ${payload.checkpoint_id}: ${integrityError}`);
    }
    return {
      path: entry.path ?? `checkpoints/${payload.checkpoint_id}.json`,
      payload,
    };
  });
}

async function cleanupCheckpoints() {
  const root = await repoRoot();
  const dryRun = Boolean(args["dry-run"]);
  const days = Number.parseInt(args["sessions-before-days"] ?? args.days ?? "14", 10);
  if (!Number.isInteger(days) || days < 0) {
    fail("--sessions-before-days must be a non-negative integer");
  }
  const checkpointKeep = args.keep == null ? null : Number.parseInt(args.keep, 10);
  if (checkpointKeep != null && (!Number.isInteger(checkpointKeep) || checkpointKeep < 0)) {
    fail("--keep must be a non-negative integer");
  }

  const sessionsDir = join(await gitCommonDir(root), "trace", "sessions");
  const removed = [];
  if (await exists(sessionsDir)) {
    const cutoff = Date.now() - days * 24 * 60 * 60 * 1000;
    for (const entry of await readdir(sessionsDir, { withFileTypes: true })) {
      if (!entry.isFile() || !entry.name.endsWith(".jsonl")) {
        continue;
      }
      const file = join(sessionsDir, entry.name);
      const fileStat = await stat(file);
      if (fileStat.mtimeMs <= cutoff) {
        if (!dryRun) {
          await rm(file);
        }
        removed.push(relativePath(root, file));
      }
    }
  }

  const checkpoints = checkpointKeep == null
    ? { keep: null, retained: null, removed: [], dryRun }
    : await cleanupCheckpointRef(root, checkpointKeep, { dryRun });
  print({ ok: true, dryRun, sessionsBeforeDays: days, removed, checkpoints });
}

async function readCheckpointPayloads(root) {
  const ref = await git(["rev-parse", "--verify", CHECKPOINT_REF], { cwd: root, allowFailure: true });
  if (!ref) {
    return [];
  }

  const paths = (await git(["ls-tree", "-r", "--name-only", CHECKPOINT_REF], { cwd: root })).split("\n").filter(Boolean);
  const checkpoints = [];
  for (const path of paths.filter((entry) => entry.startsWith("checkpoints/") && entry.endsWith(".json"))) {
    let raw = "";
    try {
      raw = await git(["show", `${CHECKPOINT_REF}:${path}`], { cwd: root });
      checkpoints.push({ path, raw, payload: JSON.parse(raw) });
    } catch (error) {
      checkpoints.push({ path, raw, payload: null, error: error.message });
    }
  }

  return checkpoints;
}

async function cleanupCheckpointRef(root, keep, options = {}) {
  const checkpoints = await readCheckpointPayloads(root);
  if (checkpoints.length <= keep) {
    return { keep, retained: checkpoints.length, removed: [], dryRun: Boolean(options.dryRun) };
  }

  const sorted = checkpoints
    .filter(({ payload }) => payload)
    .sort((left, right) => checkpointSortKey(right).localeCompare(checkpointSortKey(left)));
  const retainedPaths = new Set(sorted.slice(0, keep).map(({ path }) => path));
  const retained = checkpoints.filter(({ path, payload }) => !payload || retainedPaths.has(path));
  const removed = checkpoints
    .filter(({ path, payload }) => payload && !retainedPaths.has(path))
    .map(({ path }) => path)
    .sort();

  if (removed.length > 0 && !options.dryRun) {
    await writeCheckpointTree(root, retained, `Trace checkpoint cleanup keep ${keep}`);
  }

  return { keep, retained: retained.length, removed, dryRun: Boolean(options.dryRun) };
}

async function writeCheckpointTree(root, checkpoints, message) {
  const common = await gitCommonDir(root);
  const scratch = join(common, "trace", "tmp", `tree-${process.pid}-${randomHex(8)}`);
  const indexPath = join(scratch, "index");
  await mkdir(scratch, { recursive: true });

  const env = { ...process.env, GIT_INDEX_FILE: indexPath };
  await git(["read-tree", "--empty"], { cwd: root, env });

  for (const checkpoint of checkpoints) {
    if (!checkpoint.raw && !checkpoint.payload) {
      continue;
    }
    const file = join(scratch, checkpoint.path.replaceAll("/", "-"));
    const raw = checkpoint.raw ?? `${JSON.stringify(checkpoint.payload, null, 2)}\n`;
    await writeFile(file, raw.endsWith("\n") ? raw : `${raw}\n`);
    const blob = await git(["hash-object", "-w", file], { cwd: root, env });
    await git(["update-index", "--add", "--cacheinfo", `100644,${blob},${checkpoint.path}`], { cwd: root, env });
  }

  const newTree = await git(["write-tree"], { cwd: root, env });
  const parent = await git(["rev-parse", "--verify", CHECKPOINT_REF], { cwd: root, allowFailure: true });
  const commitArgs = ["commit-tree", newTree, "-m", message];
  if (parent) {
    commitArgs.splice(2, 0, "-p", parent);
  }
  const commit = await git(commitArgs, { cwd: root, env });
  await git(["update-ref", CHECKPOINT_REF, commit], { cwd: root });
  await rm(scratch, { recursive: true, force: true });
}

function checkpointSortKey(checkpoint) {
  return `${checkpoint.payload?.created_at ?? ""}\n${checkpoint.path}`;
}

function checkpointSummary(payload) {
  return {
    checkpoint_id: payload.checkpoint_id,
    session_id: payload.session_id ?? null,
    commit: payload.commit,
    created_at: payload.created_at,
    files: Array.isArray(payload.files) ? payload.files.length : 0,
    events: Array.isArray(payload.events) ? payload.events.length : 0,
    integrity: verifyCheckpointIntegrity(payload) == null,
  };
}

function checkpointFileLines(files) {
  if (!Array.isArray(files) || files.length === 0) {
    return ["- No files recorded."];
  }

  return files.map((file) => `- \`${file}\``);
}

function checkpointEventLine(event) {
  const eventName = event.event ?? "event";
  const role = event.role ? ` ${event.role}` : "";
  const source = event.adapter ?? event.source ?? "trace";
  const message = truncateMemoryText(normalizeMemoryText(event.message ?? ""));
  return `[${eventName}${role}] ${source}: ${message || "No message recorded."}`;
}

function withCheckpointIntegrity(payload) {
  return {
    ...withoutCheckpointIntegrity(payload),
    integrity: {
      algorithm: "sha256",
      payload_sha256: checkpointPayloadHash(payload),
    },
  };
}

function verifyCheckpointIntegrity(payload) {
  if (!payload?.integrity) {
    return "missing integrity";
  }

  if (payload.integrity.algorithm !== "sha256") {
    return `unsupported integrity algorithm ${payload.integrity.algorithm ?? "none"}`;
  }

  const expected = checkpointPayloadHash(payload);
  if (payload.integrity.payload_sha256 !== expected) {
    return "checkpoint integrity mismatch";
  }

  return null;
}

function checkpointPayloadHash(payload) {
  return createHash("sha256").update(stableJson(withoutCheckpointIntegrity(payload))).digest("hex");
}

function withoutCheckpointIntegrity(payload) {
  const { integrity, ...rest } = payload ?? {};
  return rest;
}

async function captureEvent() {
  const root = await repoRoot();
  const dryRun = Boolean(args["dry-run"]);
  const eventName = args.event ?? "note";
  if (!TRACE_EVENTS.includes(eventName)) {
    fail(`unsupported capture event ${eventName}: expected ${TRACE_EVENTS.join(", ")}`);
  }

  const eventInput = {
    sessionId: args.session,
    event: eventName,
    role: args.role ?? "agent",
    message: args.message ?? await readStdin(),
    source: args.source ?? "manual",
  };
  const event = dryRun ? await previewEvent(root, eventInput) : await appendEvent(root, eventInput);
  print({
    ok: true,
    schema_version: "trace.capture_result.v1",
    dryRun,
    session: event.session_id,
    event: event.event,
    source: event.source,
    preview: dryRun ? event : undefined,
  });
}

async function runTraceCommand(subcommandValue, values) {
  const commandArgs = traceRunArgs(subcommandValue, values);
  if (commandArgs.length === 0) {
    fail("trace run requires a command after --");
  }

  const root = await repoRoot();
  await ensureTrace(root);
  const result = await runStreaming(commandArgs[0], commandArgs.slice(1), { cwd: root });
  const eventName = args.event ?? (result.exitCode === 0 ? "validation" : "risk");
  if (!TRACE_EVENTS.includes(eventName)) {
    fail(`unsupported run event ${eventName}: expected ${TRACE_EVENTS.join(", ")}`);
  }

  const commandLine = commandArgs.map(shellQuote).join(" ");
  const status = result.exitCode === 0 ? "passed" : `failed exit ${result.exitCode}`;
  const output = compactCommandOutput(result);
  await appendEvent(root, {
    sessionId: args.session,
    event: eventName,
    role: "tool",
    source: args.source ?? "trace-run",
    message: [`${eventName} ${status}: ${commandLine}`, output].filter(Boolean).join("\n"),
  });
  process.exitCode = result.exitCode;
}

function traceRunArgs(subcommandValue, values) {
  const separator = values.indexOf("--");
  if (separator >= 0) {
    return values.slice(separator + 1);
  }
  return [subcommandValue, ...positionalValues(values)].filter(Boolean);
}

function compactCommandOutput(result) {
  const sections = [];
  const stdout = compactOutputText(result.stdout);
  const stderr = compactOutputText(result.stderr);
  if (stdout) {
    sections.push(`stdout: ${stdout}`);
  }
  if (stderr) {
    sections.push(`stderr: ${stderr}`);
  }
  return sections.join("\n");
}

function compactOutputText(value) {
  const normalized = String(value ?? "").replace(/\s+/g, " ").trim();
  if (!normalized) {
    return "";
  }
  const limit = 500;
  if (normalized.length <= limit) {
    return normalized;
  }
  return `...${normalized.slice(-limit)}`;
}

async function runSessionCommand(action, values) {
  if (action === "start" || action === "new") {
    await startSession(values[0] ?? args.session);
    return;
  }

  if (action === "end" || action === "clear") {
    await endSession(values[0] ?? args.session);
    return;
  }

  if (!action || action === "list") {
    await listSessions();
    return;
  }

  if (action === "current") {
    await showCurrentSession();
    return;
  }

  if (action === "recap" || action === "summary") {
    await recapSession(values[0] ?? args.session);
    return;
  }

  if (action === "check") {
    await checkSession(values[0] ?? args.session);
    return;
  }

  if (action === "show") {
    await showSession(values[0] ?? args.session);
    return;
  }

  fail(`unknown session command: ${action}`);
}

async function startSession(requestedSessionId) {
  const root = await repoRoot();
  await ensureTrace(root);
  const sessionId = requestedSessionId ? validateSessionId(requestedSessionId) : newSessionId();
  const file = await sessionPath(root, sessionId);
  const event = await appendEvent(root, {
    sessionId,
    event: "note",
    role: "system",
    source: "trace-session",
    message: "session started",
  });
  print({ ok: true, session: sessionId, path: relativePath(root, file), event: event.event });
}

async function endSession(expectedSessionId) {
  const root = await repoRoot();
  const current = await readCurrentSession(root).catch(() => null);
  if (!current) {
    print({ ok: true, ended: null, current: null });
    return;
  }

  if (expectedSessionId && current !== expectedSessionId) {
    fail(`current session is ${current}, not ${expectedSessionId}`);
  }

  const event = await appendEvent(root, {
    sessionId: current,
    event: "note",
    role: "system",
    source: "trace-session",
    message: "session ended",
  });
  await rm(await currentSessionPath(root), { force: true });
  print({ ok: true, ended: current, current: null, event: event.event });
}

async function listSessions() {
  const root = await repoRoot();
  print({ ok: true, current: await readCurrentSession(root).catch(() => null), sessions: await sessionSummaries(root) });
}

async function showCurrentSession() {
  const root = await repoRoot();
  print({ ok: true, current: await readCurrentSession(root).catch(() => null) });
}

async function showSession(sessionId) {
  if (!sessionId) {
    fail("session id is required");
  }

  const root = await repoRoot();
  const events = await readSessionEvents(root, sessionId).catch((error) => fail(`session ${sessionId} not found or unreadable: ${error.message}`));
  const limit = args.limit == null ? events.length : parsePositiveInteger(args.limit, "--limit");
  print({
    ok: true,
    session: sessionId,
    path: relativePath(root, await sessionPath(root, sessionId)),
    events: events.slice(Math.max(0, events.length - limit)),
  });
}

async function recapSession(sessionId) {
  const root = await repoRoot();
  const resolvedSession = sessionId ?? await readCurrentSession(root).catch(() => null);
  if (!resolvedSession) {
    fail("session id is required");
  }

  const events = await readSessionEvents(root, resolvedSession).catch((error) => fail(`session ${resolvedSession} not found or unreadable: ${error.message}`));
  const limit = parsePositiveInteger(args.limit ?? "5", "--limit");
  const field = normalizeRecapField(args.field);
  const recap = await sessionRecap(root, resolvedSession, events, limit);
  const output = {
    ...recap,
    field,
    sections: recapSectionsForField(recap.sections, field),
  };
  const document = args.json ? `${JSON.stringify(output, null, 2)}\n` : renderSessionRecapMarkdown(output, field);
  if (args.output) {
    const outputPath = resolve(args.output);
    await mkdir(dirname(outputPath), { recursive: true });
    await writeFile(outputPath, document);
    print({
      ok: true,
      schema_version: "trace.session_recap_output.v1",
      session: output.session,
      field,
      output: args.output,
      bytes: Buffer.byteLength(document),
    });
    return;
  }

  if (args.json) {
    process.stdout.write(document);
    return;
  }

  process.stdout.write(document);
}

function renderSessionRecapMarkdown(output, field) {
  const lines = [
    "# Trace Session Recap",
    "",
    `Session: \`${output.session}\``,
    `Path: \`${output.path}\``,
    `Events: ${output.events}`,
    `Commit Memory Events: ${output.commitMemoryEvents}`,
  ];
  if (field !== "all") {
    lines.push(`Field: \`${field}\``);
  }
  for (const [key, label] of recapSectionEntries(field)) {
    appendRecapSection(lines, label, output.sections[key]);
  }
  return `${lines.join("\n").trimEnd()}\n`;
}

async function checkSession(sessionId) {
  const root = await repoRoot();
  const resolvedSession = sessionId ?? await readCurrentSession(root).catch(() => null);
  if (!resolvedSession) {
    fail("session id is required");
  }

  const events = await readSessionEvents(root, resolvedSession).catch((error) => fail(`session ${resolvedSession} not found or unreadable: ${error.message}`));
  const report = await sessionCheck(root, resolvedSession, events, { strict: args.strict });

  if (args.json) {
    print(report);
  } else {
    const lines = [
      "# Trace Session Check",
      "",
      `Session: \`${report.session}\``,
      `Events: ${report.events}`,
      `Commit Memory Events: ${report.commitMemoryEvents}`,
      `Status: ${report.ok ? "ok" : "needs capture"}`,
      "",
      "## Checks",
      "",
    ];
    for (const check of report.checks) {
      lines.push(`- ${check.ok ? "ok" : check.level}: ${check.message}`);
    }
    process.stdout.write(`${lines.join("\n").trimEnd()}\n`);
  }

  if (!report.ok) {
    process.exitCode = 1;
  }
}

async function sessionSummaries(root) {
  const files = await listSessionFiles(root);
  const sessions = [];
  for (const file of files) {
    sessions.push(await sessionSummary(root, file));
  }

  return sessions.sort((left, right) => String(right.last_at ?? "").localeCompare(String(left.last_at ?? "")));
}

async function listSessionFiles(root) {
  const dir = join(await gitCommonDir(root), "trace", "sessions");
  if (!await exists(dir)) {
    return [];
  }

  const files = [];
  for (const entry of await readdir(dir, { withFileTypes: true })) {
    if (!entry.isFile() || !entry.name.endsWith(".jsonl")) {
      continue;
    }
    files.push(join(dir, entry.name));
  }

  return files.sort();
}

async function sessionSummary(root, file) {
  const events = (await readFile(file, "utf8")).split("\n").filter(Boolean).map((line) => JSON.parse(line));
  const counts = {};
  const sources = new Set();
  const adapters = new Set();

  for (const event of events) {
    counts[event.event] = (counts[event.event] ?? 0) + 1;
    if (event.source) {
      sources.add(event.source);
    }
    if (event.adapter) {
      adapters.add(event.adapter);
    }
  }

  return {
    session: file.split("/").pop().replace(/\.jsonl$/, ""),
    path: relativePath(root, file),
    events: events.length,
    first_at: events[0]?.created_at ?? null,
    last_at: events.at(-1)?.created_at ?? null,
    counts,
    sources: Array.from(sources).sort(),
    adapters: Array.from(adapters).sort(),
  };
}

async function sessionRecap(root, sessionId, events, limit) {
  const commitMemoryEvents = events.filter(includeInCommitMemory);
  const extracted = extractedMemorySignals(commitMemoryEvents);
  const prompts = [
    ...commitMemoryEvents.filter((event) => event.role === "user" || event.event === "prompt").map(eventMessage),
    ...extracted.prompts,
  ];
  const responses = commitMemoryEvents.filter((event) => event.event === "response" || event.role === "assistant").map(eventMessage);
  const tools = commitMemoryEvents.filter((event) => event.event === "tool").map(eventMessage);
  const decisions = [
    ...commitMemoryEvents.filter((event) => event.event === "decision").map(eventMessage),
    ...extracted.decisions,
  ];
  const validation = [
    ...commitMemoryEvents.filter((event) => event.event === "validation").map(eventMessage),
    ...extracted.validation,
  ];
  const risks = [
    ...commitMemoryEvents.filter((event) => event.event === "risk").map(eventMessage),
    ...extracted.risks,
  ];
  const notes = commitMemoryEvents.filter((event) => !["prompt", "response", "tool", "decision", "validation", "risk"].includes(event.event)).map(eventMessage);

  return {
    ok: true,
    schema_version: "trace.session_recap.v1",
    session: sessionId,
    path: relativePath(root, await sessionPath(root, sessionId)),
    events: events.length,
    commitMemoryEvents: commitMemoryEvents.length,
    omittedLifecycleEvents: events.length - commitMemoryEvents.length,
    counts: eventCounts(events),
    sections: {
      prompts: await recapItems(root, prompts, limit),
      responses: await recapItems(root, responses, limit),
      tools: await recapItems(root, tools, limit),
      decisions: await recapItems(root, decisions, limit),
      validation: await recapItems(root, validation, limit),
      risks: await recapItems(root, risks, limit),
      handoff: await recapItems(root, handoffItems({
        decisions,
        validations: validation,
        risks,
        files: [],
        subject: `session ${sessionId}`,
      }), limit),
      notes: await recapItems(root, notes, limit),
    },
  };
}

async function sessionCheck(root, sessionId, events, options = {}) {
  const recap = await sessionRecap(root, sessionId, events, 1);
  const strict = Boolean(options.strict);
  const checks = [
    {
      name: "commitMemoryEvents",
      level: "error",
      ok: recap.commitMemoryEvents > 0,
      message: recap.commitMemoryEvents > 0
        ? "session has events that can be turned into commit memory"
        : "session only has local lifecycle notes; capture prompt, response, tool, decision, validation, risk, or note events before recording",
    },
    {
      name: "intent",
      level: "warning",
      ok: recap.sections.prompts.length > 0,
      message: recap.sections.prompts.length > 0
        ? "session has an intent signal"
        : "session has no prompt or user-role event",
    },
    {
      name: "decisions",
      level: "warning",
      ok: recap.sections.decisions.length > 0,
      message: recap.sections.decisions.length > 0
        ? "session has decision context"
        : "session has no decision signal",
    },
    {
      name: "validation",
      level: "warning",
      ok: recap.sections.validation.length > 0,
      message: recap.sections.validation.length > 0
        ? "session has validation context"
        : "session has no validation signal",
    },
  ];

  return {
    ok: checks.every((check) => check.ok || (!strict && check.level === "warning")),
    schema_version: "trace.session_check.v1",
    strict,
    session: sessionId,
    path: recap.path,
    events: recap.events,
    commitMemoryEvents: recap.commitMemoryEvents,
    counts: recap.counts,
    checks,
  };
}

function eventMessage(event) {
  return event.message ?? "";
}

function extractedMemorySignals(events) {
  const signals = {
    prompts: [],
    decisions: [],
    validation: [],
    risks: [],
  };

  for (const event of events) {
    if (["decision", "validation", "risk"].includes(event.event)) {
      continue;
    }
    for (const item of extractMemorySignalItems(eventMessage(event))) {
      signals[item.key].push(item.value);
    }
  }

  return signals;
}

function extractMemorySignalItems(message) {
  const items = [];
  let active = null;

  for (const rawLine of String(message ?? "").split(/\r?\n/)) {
    const line = rawLine.trim();
    if (!line) {
      active = null;
      continue;
    }

    const bullet = line.replace(/^[-*]\s+/, "").trim();
    const labeled = bullet.match(/^(intent|goal|task|decision|decisions|validation|validations|validated|test|tests|risk|risks)\s*[:\-]\s*(.*)$/iu);
    if (labeled) {
      active = signalKeyForLabel(labeled[1]);
      const value = labeled[2].trim();
      if (value) {
        items.push({ key: active, value });
      }
      continue;
    }

    if (active && /^[-*]\s+/.test(line)) {
      items.push({ key: active, value: bullet });
    }
  }

  return items.filter((item) => item.value);
}

function signalKeyForLabel(label) {
  const normalized = label.toLowerCase();
  if (["intent", "goal", "task"].includes(normalized)) {
    return "prompts";
  }
  if (normalized.startsWith("decision")) {
    return "decisions";
  }
  if (["validation", "validations", "validated", "test", "tests"].includes(normalized)) {
    return "validation";
  }
  return "risks";
}

function eventCounts(events) {
  const counts = {};
  for (const event of events) {
    counts[event.event] = (counts[event.event] ?? 0) + 1;
  }
  return counts;
}

async function recapItems(root, values, limit) {
  const items = compactMemoryItems(values).slice(0, limit);
  const redacted = [];
  for (const item of items) {
    redacted.push(await conciseMemoryText(root, item));
  }
  return redacted;
}

function appendRecapSection(lines, name, values) {
  lines.push("", `## ${name}`, "");
  if (values.length === 0) {
    lines.push("- Not recorded.");
    return;
  }

  for (const value of values) {
    lines.push(`- ${value}`);
  }
}

function normalizeRecapField(value) {
  const field = String(value ?? "all").toLowerCase();
  const aliases = {
    all: "all",
    intent: "prompts",
    intents: "prompts",
    prompt: "prompts",
    prompts: "prompts",
    response: "responses",
    responses: "responses",
    tool: "tools",
    tools: "tools",
    activity: "tools",
    decision: "decisions",
    decisions: "decisions",
    validation: "validation",
    risk: "risks",
    risks: "risks",
    handoff: "handoff",
    handoffs: "handoff",
    note: "notes",
    notes: "notes",
  };

  if (!aliases[field]) {
    fail(`unknown session recap field: ${value}`);
  }

  return aliases[field];
}

function recapSectionEntries(field = "all") {
  const entries = [
    ["prompts", "Intent Signals"],
    ["responses", "Responses"],
    ["tools", "Tool Activity"],
    ["decisions", "Decisions"],
    ["validation", "Validation"],
    ["risks", "Risks"],
    ["handoff", "Handoff"],
    ["notes", "Notes"],
  ];
  return field === "all" ? entries : entries.filter(([key]) => key === field);
}

function recapSectionsForField(sections, field = "all") {
  const selected = {};
  for (const [key] of recapSectionEntries(field)) {
    selected[key] = sections[key] ?? [];
  }
  return selected;
}

async function runRedactCommand(action, values) {
  if (action === "add") {
    await addRedactionRule(values[0] ?? args.label, values[1] ?? args.pattern);
    return;
  }

  if (action === "remove" || action === "rm") {
    await removeRedactionRule(values[0] ?? args.label);
    return;
  }

  if (action === "audit") {
    await auditRedactionCommand();
    return;
  }

  if (action === "preview") {
    await previewRedaction(values);
    return;
  }

  if (!action || action === "list") {
    const root = await repoRoot();
    print({ ok: true, rules: customRules(await loadTraceConfig(root)) });
    return;
  }

  fail(`unknown redact command: ${action}`);
}

async function addRedactionRule(label, pattern) {
  if (!label) {
    fail("redaction label is required");
  }
  if (!pattern) {
    fail("redaction pattern is required");
  }

  validateRegex(pattern);
  const root = await repoRoot();
  await ensureTrace(root);
  const config = await loadTraceConfig(root);
  const rules = customRules(config).filter((rule) => rule.label !== label);
  rules.push({ label, pattern });
  await writeTraceConfig(root, withCustomRules(config, rules));
  print({ ok: true, label, pattern });
}

async function removeRedactionRule(label) {
  if (!label) {
    fail("redaction label is required");
  }

  const root = await repoRoot();
  await ensureTrace(root);
  const config = await loadTraceConfig(root);
  const rules = customRules(config).filter((rule) => rule.label !== label);
  await writeTraceConfig(root, withCustomRules(config, rules));
  print({ ok: true, label, rules: rules.length });
}

async function auditRedactionCommand() {
  const root = await repoRoot();
  const audit = await redactionAudit(root);
  print(audit);
  if (!audit.ok) {
    process.exitCode = 1;
  }
}

async function previewRedaction(values) {
  const root = await repoRoot();
  let input = args.text ?? positionalValues(values).join(" ");
  if (!input) {
    input = await readStdin();
  }
  if (!input) {
    fail("redact preview requires text argument, --text, or stdin");
  }

  const redacted = await redact(root, input);
  if (args.json) {
    print({ ok: true, schema_version: "trace.redaction_preview.v1", redacted });
    return;
  }

  process.stdout.write(`${redacted}\n`);
}

async function redactionAudit(root) {
  const files = [
    ...await listMemoryFiles(root),
    ...await listSessionFiles(root),
  ];
  const findings = [];
  const config = await loadTraceConfig(root);
  const customAuditRules = customRules(config).map((rule) => {
    validateRegex(rule.pattern);
    return {
      label: rule.label,
      pattern: new RegExp(rule.pattern, "gu"),
    };
  });

  for (const file of files) {
    auditRedactionContent(findings, customAuditRules, relativePath(root, file), await readFile(file, "utf8"));
  }

  const checkpoints = await readCheckpointPayloads(root);
  for (const checkpoint of checkpoints) {
    if (checkpoint.raw) {
      auditRedactionContent(findings, customAuditRules, `${CHECKPOINT_REF}:${checkpoint.path}`, checkpoint.raw);
    }
  }

  return {
    ok: findings.length === 0,
    scanned: [
      ...files.map((file) => relativePath(root, file)),
      ...checkpoints.filter((checkpoint) => checkpoint.raw).map((checkpoint) => `${CHECKPOINT_REF}:${checkpoint.path}`),
    ],
    findings,
  };
}

function auditRedactionContent(findings, customAuditRules, file, content) {
  const builtin = countUnredactedAssignments(content);
  if (builtin > 0) {
    findings.push({ file, rule: "secret-assignment", count: builtin });
  }

  for (const rule of customAuditRules) {
    const count = countMatches(content, rule.pattern);
    if (count > 0) {
      findings.push({ file, rule: rule.label, count });
    }
  }
}

async function runAgentCommand(action, values) {
  if (action === "add" || action === "install") {
    await addAgent(values[0] ?? args.name);
    return;
  }

  if (action === "remove" || action === "rm") {
    await removeAgent(values[0] ?? args.name);
    return;
  }

  if (action === "check" || action === "verify") {
    await checkAgents(values[0] ?? args.name);
    return;
  }

  if (!action || action === "list" || action === "status") {
    const root = await repoRoot();
    print({ ok: true, agents: await listAgentConfigs(root) });
    return;
  }

  fail(`unknown agent command: ${action}`);
}

async function addAgent(name) {
  if (name === "all") {
    await addAllAgents();
    return;
  }

  const agentName = normalizeAgentName(name);
  const root = await repoRoot();
  await ensureTrace(root);
  const config = agentConfig(agentName);
  const file = agentConfigPath(root, agentName);
  await mkdir(dirname(file), { recursive: true });
  await writeFile(file, `${JSON.stringify(config, null, 2)}\n`);
  print({ ok: true, agent: agentName, config: relativePath(root, file), command: config.command });
}

async function addAllAgents() {
  const root = await repoRoot();
  await ensureTrace(root);
  const agents = [];
  for (const agentName of SUPPORTED_AGENTS) {
    const config = agentConfig(agentName);
    const file = agentConfigPath(root, agentName);
    await mkdir(dirname(file), { recursive: true });
    await writeFile(file, `${JSON.stringify(config, null, 2)}\n`);
    agents.push({ agent: agentName, config: relativePath(root, file), command: config.command });
  }
  print({ ok: true, agents });
}

async function removeAgent(name) {
  if (name === "all") {
    await removeAllAgents();
    return;
  }

  const agentName = normalizeAgentName(name);
  const root = await repoRoot();
  const file = agentConfigPath(root, agentName);
  await rm(file, { force: true });
  print({ ok: true, agent: agentName, removed: relativePath(root, file) });
}

async function removeAllAgents() {
  const root = await repoRoot();
  const removed = [];
  for (const agentName of SUPPORTED_AGENTS) {
    const file = agentConfigPath(root, agentName);
    await rm(file, { force: true });
    removed.push({ agent: agentName, removed: relativePath(root, file) });
  }
  print({ ok: true, removed });
}

async function checkAgents(target) {
  const root = await repoRoot();
  const report = await buildAgentCheckReport(root, target);
  print(report);
  if (!report.ok) {
    process.exitCode = 1;
  }
}

async function buildAgentCheckReport(root, target) {
  const installed = await listAgentConfigs(root);
  const installedByName = new Map(installed.map((agent) => [agent.agent, agent]));
  const names = agentCheckNames(target, installed);
  const contracts = [];

  for (const name of names) {
    const installedAgent = installedByName.get(name);
    const configErrors = installedAgent ? installedAgent.errors : [`missing adapter config: run trace agent add ${name}`];
    const contract = await checkAgentContract(name);
    contracts.push({
      agent: name,
      config: installedAgent?.config ?? null,
      command: installedAgent?.command ?? null,
      fixture: contract.fixture,
      event: contract.event,
      valid: configErrors.length === 0 && contract.errors.length === 0,
      errors: [...configErrors, ...contract.errors],
    });
  }

  const ok = contracts.length > 0 && contracts.every((contract) => contract.valid);
  return { ok, agents: contracts };
}

function agentCheckNames(target, installed) {
  if (target === "all") {
    return Array.from(SUPPORTED_AGENTS);
  }

  if (target) {
    return [normalizeAgentName(target)];
  }

  return installed.map((agent) => agent.agent).sort((left, right) => left.localeCompare(right));
}

async function checkAgentContract(name) {
  if (!SUPPORTED_AGENTS.has(name)) {
    return {
      fixture: null,
      event: null,
      errors: [`unsupported agent ${name}: no contract fixture`],
    };
  }

  const contract = AGENT_CONTRACTS[name];
  const fixturePath = join(tracePackageRoot(), "examples", contract.fixture);
  const fixture = relativePath(tracePackageRoot(), fixturePath);
  const errors = [];
  let raw = "";
  let payload = null;

  try {
    raw = await readFile(fixturePath, "utf8");
    payload = parseOptionalJson(raw);
  } catch (error) {
    errors.push(`fixture ${fixture} could not be read: ${error.message}`);
  }

  if (!payload || Array.isArray(payload)) {
    errors.push(`fixture ${fixture} must be one JSON object`);
  }

  const event = payload && !Array.isArray(payload) ? normalizeAgentPayload(name, null, payload, raw) : null;
  if (event && event.event !== contract.event) {
    errors.push(`fixture ${fixture} expected ${contract.event} event but got ${event.event}`);
  }
  if (event && event.adapter !== name) {
    errors.push(`fixture ${fixture} expected ${name} adapter but got ${event.adapter}`);
  }
  for (const expectedText of contract.messageIncludes) {
    if (event && !event.message.includes(expectedText)) {
      errors.push(`fixture ${fixture} message missing ${expectedText}`);
    }
  }

  return {
    fixture,
    event: event?.event ?? null,
    errors,
  };
}

function normalizeAgentName(name) {
  if (!name) {
    fail(`agent name is required: ${Array.from(SUPPORTED_AGENTS).join(", ")}`);
  }

  if (!SUPPORTED_AGENTS.has(name)) {
    fail(`unsupported agent ${name}: expected ${Array.from(SUPPORTED_AGENTS).join(", ")}`);
  }

  return name;
}

function agentConfig(name) {
  const contract = AGENT_CONTRACTS[name];
  return {
    schema_version: AGENT_CONFIG_VERSION,
    agent: name,
    adapter: name,
    command: `trace hook agent --adapter ${name}`,
    events: TRACE_EVENTS,
    stdin: "json-or-text",
    contract: {
      fixture: `examples/${contract.fixture}`,
      event: contract.event,
      message_includes: contract.messageIncludes,
    },
    output: "trace.event.v1 JSONL in git common dir",
  };
}

function agentConfigPath(root, name) {
  return join(root, TRACE_DIR, "agents", `${name}.json`);
}

async function listAgentConfigs(root) {
  const dir = join(root, TRACE_DIR, "agents");
  if (!await exists(dir)) {
    return [];
  }

  const agents = [];
  for (const entry of await readdir(dir, { withFileTypes: true })) {
    if (!entry.isFile() || !entry.name.endsWith(".json")) {
      continue;
    }

    const file = join(dir, entry.name);
    const configPath = relativePath(root, file);
    try {
      const config = JSON.parse(await readFile(file, "utf8"));
      const errors = validateAgentConfig(config);
      agents.push({
        agent: config.agent ?? entry.name.replace(/\.json$/, ""),
        adapter: config.adapter ?? null,
        config: configPath,
        command: config.command ?? null,
        events: Array.isArray(config.events) ? config.events : [],
        contract: config.contract ?? null,
        valid: errors.length === 0,
        errors,
      });
    } catch (error) {
      agents.push({
        agent: entry.name.replace(/\.json$/, ""),
        config: configPath,
        command: null,
        valid: false,
        errors: [error.message],
      });
    }
  }

  return agents.sort((left, right) => left.agent.localeCompare(right.agent));
}

function validateAgentConfig(config) {
  const errors = [];
  if (config.schema_version !== AGENT_CONFIG_VERSION) {
    errors.push(`unsupported schema ${config.schema_version ?? "none"}`);
  }
  if (!SUPPORTED_AGENTS.has(config.agent)) {
    errors.push(`unsupported agent ${config.agent ?? "none"}`);
  }
  if (config.adapter !== config.agent) {
    errors.push(`adapter must match agent ${config.agent ?? "none"}`);
  }
  if (config.command !== `trace hook agent --adapter ${config.agent}`) {
    errors.push("command must call trace hook agent with the adapter");
  }
  if (!Array.isArray(config.events) || config.events.some((event) => !TRACE_EVENTS.includes(event))) {
    errors.push(`events must be supported Trace lifecycle events: ${TRACE_EVENTS.join(", ")}`);
  } else {
    const missing = TRACE_EVENTS.filter((event) => !config.events.includes(event));
    if (missing.length > 0) {
      errors.push(`events missing ${missing.join(", ")}`);
    }
  }
  if (config.stdin !== "json-or-text") {
    errors.push("stdin must be json-or-text");
  }
  const expectedContract = expectedAgentContract(config.agent);
  if (!config.contract || typeof config.contract !== "object") {
    errors.push("contract must describe the adapter fixture");
  } else if (expectedContract) {
    if (config.contract.fixture !== expectedContract.fixture) {
      errors.push(`contract fixture must be ${expectedContract.fixture}`);
    }
    if (config.contract.event !== expectedContract.event) {
      errors.push(`contract event must be ${expectedContract.event}`);
    }
    if (!Array.isArray(config.contract.message_includes)
      || config.contract.message_includes.some((item) => typeof item !== "string")
      || !sameStringList(config.contract.message_includes, expectedContract.message_includes)) {
      errors.push("contract message_includes must match the adapter contract");
    }
  }
  return errors;
}

function expectedAgentContract(name) {
  const contract = AGENT_CONTRACTS[name];
  if (!contract) {
    return null;
  }
  return {
    fixture: `examples/${contract.fixture}`,
    event: contract.event,
    message_includes: contract.messageIncludes,
  };
}

function sameStringList(left, right) {
  return left.length === right.length && left.every((item, index) => item === right[index]);
}

async function appendEvent(root, input) {
  const sessionId = input.sessionId ?? await currentOrNewSession(root);
  const event = {
    schema_version: "trace.event.v1",
    session_id: sessionId,
    event: input.event,
    role: input.role,
    source: input.source ?? "manual",
    adapter: input.adapter ?? null,
    message: await redact(root, input.message),
    created_at: now(),
  };
  const sessionFile = await sessionPath(root, sessionId);
  await mkdir(dirname(sessionFile), { recursive: true });
  await writeFile(sessionFile, `${JSON.stringify(event)}\n`, { flag: "a" });
  await writeFile(await currentSessionPath(root), sessionId);
  return event;
}

async function recordMemory() {
  const root = await repoRoot();
  await ensureTrace(root);
  const sha = await resolveCommit(args.commit ?? "HEAD");
  const trailers = await traceCommitTrailers(root, sha);
  const checkpointId = args.checkpoint ?? trailers.checkpoint ?? randomHex(12);
  const sessionId = args.session ?? trailers.session ?? await readCurrentSession(root).catch(() => null);
  const sessionReport = args["check-session"] ? await recordSessionCheck(root, sessionId) : null;
  if (sessionReport === false) {
    return;
  }
  const memory = await buildMemory(root, sha, checkpointId, sessionId, {
    intent: args.intent,
    validation: args.validation,
    risk: args.risk,
  });
  const memoryPath = memoryPathFor(root, sha);
  if (args["dry-run"]) {
    const output = {
      ok: true,
      schema_version: "trace.record_result.v1",
      dryRun: true,
      commit: sha,
      memory: relativePath(root, memoryPath),
      checkpoint: checkpointId,
      session: sessionId,
      markdown: memory.markdown,
      memoryPreview: recordMemoryPreview(memory.markdown),
      checkpointPreview: recordCheckpointPreview(memory.rawCheckpoint),
    };
    if (sessionReport) {
      output.sessionCheck = sessionReport;
    }
    print(output);
    return;
  }

  await mkdir(dirname(memoryPath), { recursive: true });
  await writeFile(memoryPath, memory.markdown);
  await writeCheckpointRef(root, checkpointId, memory.rawCheckpoint);
  const output = {
    ok: true,
    schema_version: "trace.record_result.v1",
    commit: sha,
    memory: relativePath(root, memoryPath),
    checkpoint: checkpointId,
    session: sessionId,
    memoryPreview: recordMemoryPreview(memory.markdown),
    checkpointPreview: recordCheckpointPreview(memory.rawCheckpoint),
  };
  if (sessionReport) {
    output.sessionCheck = sessionReport;
  }
  print(output);
}

async function recordSessionCheck(root, sessionId) {
  if (!sessionId) {
    fail("record --check-session requires a session id or current session");
  }

  const events = await readSessionEvents(root, sessionId).catch((error) => fail(`session ${sessionId} not found or unreadable: ${error.message}`));
  const report = await sessionCheck(root, sessionId, events, { strict: args.strict });
  if (!report.ok) {
    print(report);
    process.exitCode = 1;
    return false;
  }

  return report;
}

async function showMemory(commitish) {
  const root = await repoRoot();
  const sha = await resolveCommit(commitish);
  const memoryPath = memoryPathFor(root, sha);
  if (!await exists(memoryPath)) {
    fail(`memory not found for commit ${sha}`);
  }
  const content = await readFile(memoryPath, "utf8");
  if (args.json) {
    const { mtimeMs: _mtimeMs, ...memory } = memoryLogRecord(root, memoryPath, content, (await stat(memoryPath)).mtimeMs);
    print({ ok: true, schema_version: "trace.memory_detail.v1", memory });
    return;
  }

  process.stdout.write(content);
}

async function reviewMemories() {
  const root = await repoRoot();
  const memoryStatuses = args.all
    ? (await listMemoryFiles(root)).map((file) => ({ path: relativePath(root, file), status: "tracked" }))
    : await pendingMemoryStatuses(root);
  const memories = [];

  for (const entry of memoryStatuses) {
    const file = join(root, entry.path);
    if (!await exists(file)) {
      continue;
    }
    memories.push(await memoryReviewEntry(root, file, entry.status));
  }

  memories.sort((left, right) => right.created.localeCompare(left.created) || left.path.localeCompare(right.path));

  if (args.json) {
    print({ ok: true, mode: args.all ? "all" : "pending", memories });
    return;
  }

  const lines = ["# Trace Memory Review", "", `Mode: ${args.all ? "all memories" : "pending memories"}`, `Memories: ${memories.length}`, ""];
  if (memories.length === 0) {
    lines.push(args.all ? "No Trace memories found." : "No pending Trace memories found.", "");
  }

  for (const memory of memories) {
    lines.push(`## ${memory.commit.slice(0, 12)} ${memory.title}`, "");
    lines.push(`Memory: \`${memory.path}\``);
    lines.push(`Status: ${memory.status}`);
    lines.push(`Checkpoint: \`${memory.checkpoint}\``);
    lines.push(`Session: \`${memory.session}\``);
    appendReviewSection(lines, "Intent", memory.intent);
    appendReviewSection(lines, "Agents", memory.agents);
    appendReviewSection(lines, "Lifecycle", memory.lifecycle);
    appendReviewSection(lines, "Summary", memory.summary);
    appendReviewSection(lines, "Decisions", memory.decisions);
    appendReviewSection(lines, "Files", memory.files);
    appendReviewSection(lines, "Validation", memory.validation);
    appendReviewSection(lines, "Risks", memory.risks);
    appendReviewSection(lines, "Handoff", memory.handoff);
    lines.push("");
  }

  process.stdout.write(`${lines.join("\n").trimEnd()}\n`);
}

async function pendingMemoryStatuses(root) {
  const output = await git(["status", "--porcelain", "-uall", "--", `${TRACE_DIR}/commits`], { cwd: root });
  return output.split("\n")
    .filter(Boolean)
    .map((line) => ({
      status: normalizePorcelainStatus(line.slice(0, 2)),
      path: line.slice(3).replace(/^"|"$/g, ""),
    }))
    .filter((entry) => entry.path.endsWith(".md"));
}

async function memoryReviewEntry(root, file, status) {
  const content = await readFile(file, "utf8");
  const commit = content.match(/^Commit: `([^`]+)`/m)?.[1] ?? file.split("/").pop()?.replace(/\.md$/, "") ?? "";
  const title = firstLine(content).replace(/^#\s*/, "").replace(new RegExp(`^${escapeRegExp(commit.slice(0, 12))}\\s+`), "");
  return {
    path: relativePath(root, file),
    status,
    commit,
    title,
    created: content.match(/^Created: `([^`]+)`/m)?.[1] ?? "",
    checkpoint: content.match(/^Checkpoint: `([^`]+)`/m)?.[1] ?? "none",
    session: content.match(/^Session: `([^`]+)`/m)?.[1] ?? "none",
    agents: section(content, "Agents") ?? "No agent adapters recorded.",
    lifecycle: section(content, "Lifecycle") ?? "No lifecycle events recorded.",
    intent: section(content, "Intent") ?? "Not recorded.",
    summary: section(content, "Summary") ?? "Not recorded.",
    decisions: section(content, "Decisions") ?? "Not recorded.",
    files: section(content, "Files") ?? "Not recorded.",
    validation: section(content, "Validation") ?? "Not recorded.",
    risks: section(content, "Risks") ?? "No known open risks recorded.",
    handoff: section(content, "Handoff") ?? "Not recorded.",
  };
}

function normalizePorcelainStatus(status) {
  const value = status.trim();
  if (value === "??") {
    return "untracked";
  }
  if (value === "A") {
    return "added";
  }
  if (value === "M") {
    return "modified";
  }
  return value || "changed";
}

function appendReviewSection(lines, name, value) {
  const content = String(value ?? "").trim();
  if (!content) {
    return;
  }
  lines.push("", `### ${name}`, "", content);
}

async function logMemories() {
  const root = await repoRoot();
  const limit = parsePositiveInteger(args.limit ?? "20", "--limit");
  const files = await listMemoryFiles(root);
  const rows = [];

  for (const file of files) {
    const content = await readFile(file, "utf8");
    rows.push(memoryLogRecord(root, file, content, (await stat(file)).mtimeMs));
  }

  rows.sort((left, right) => String(right.created).localeCompare(String(left.created)) || right.mtimeMs - left.mtimeMs);
  const memories = rows.slice(0, limit).map(({ mtimeMs, ...row }) => row);

  if (args.json) {
    print({ ok: true, schema_version: "trace.memory_log.v1", limit, memories });
    return;
  }

  for (const row of memories) {
    process.stdout.write(`${row.commit.slice(0, 12)} ${row.intent || "No intent recorded."}\n`);
  }
}

function memoryLogRecord(root, file, content, mtimeMs) {
  return {
    ...memoryRecord(content),
    memory: relativePath(root, file),
    created: content.match(/^Created: `([^`]+)`/m)?.[1] ?? "",
    checkpoint: content.match(/^Checkpoint: `([^`]+)`/m)?.[1] ?? "none",
    session: content.match(/^Session: `([^`]+)`/m)?.[1] ?? "none",
    mtimeMs,
  };
}

function recordMemoryPreview(markdown) {
  return {
    schema_version: "trace.record_memory_preview.v1",
    ...memoryRecord(markdown),
  };
}

function recordCheckpointPreview(payload) {
  const checkpoint = withCheckpointIntegrity(payload);
  return {
    schema_version: "trace.record_checkpoint_preview.v1",
    ref: CHECKPOINT_REF,
    path: `checkpoints/${checkpoint.checkpoint_id}.json`,
    ...checkpointSummary(checkpoint),
    payload_sha256: checkpoint.integrity.payload_sha256,
  };
}

async function searchMemories(query) {
  if (!query.trim()) {
    fail("search query is required");
  }

  const root = await repoRoot();
  const terms = query.toLowerCase().split(/\s+/).filter(Boolean);
  const limit = parsePositiveInteger(args.limit ?? "20", "--limit");
  const index = await loadSearchIndex(root);
  const field = normalizeSearchField(args.field);
  const matches = [];

  for (const entry of index.entries) {
    const searchable = searchFieldText(entry, field);
    const lower = searchable.toLowerCase();
    if (!terms.every((term) => lower.includes(term))) {
      continue;
    }
    const score = searchScore(lower, terms);
    matches.push({
      score,
      sha: entry.sha,
      file: entry.file,
      checkpoint: entry.checkpoint,
      session: entry.session,
      created: entry.created,
      snippet: snippet(searchable, terms[0]),
    });
  }

  const limited = matches
    .sort((left, right) => right.score - left.score || left.file.localeCompare(right.file))
    .slice(0, limit);
  const payload = searchPayload(query, field, terms, limited);
  const document = args.json ? `${JSON.stringify(payload, null, 2)}\n` : renderSearchResults(limited);
  if (args.output) {
    const outputPath = resolve(args.output);
    await mkdir(dirname(outputPath), { recursive: true });
    await writeFile(outputPath, document);
    print({
      ok: true,
      schema_version: "trace.search_output.v1",
      output: args.output,
      matches: limited.length,
      bytes: Buffer.byteLength(document),
    });
    return;
  }

  if (args.json) {
    process.stdout.write(document);
    return;
  }

  process.stdout.write(document);
}

function searchPayload(query, field, terms, results) {
  return {
    ok: true,
    schema_version: "trace.search_results.v1",
    query,
    field,
    terms,
    matches: results.length,
    results,
  };
}

function renderSearchResults(matches) {
  const lines = [];
  for (const match of matches) {
    lines.push(`${match.sha.slice(0, 12)} ${match.file} score=${match.score}`, match.snippet);
  }
  return lines.length > 0 ? `${lines.join("\n")}\n` : "";
}

function searchScore(searchable, terms) {
  return terms.reduce((score, term) => score + countTermOccurrences(searchable, term), 0);
}

function countTermOccurrences(value, term) {
  let count = 0;
  let index = value.indexOf(term);
  while (index !== -1) {
    count += 1;
    index = value.indexOf(term, index + term.length);
  }
  return count;
}

async function recallMemories(query) {
  const root = await repoRoot();
  const explicitFiles = splitList(args.files ?? args.file);
  const checkpoint = String(args.checkpoint ?? "").trim();
  const session = String(args.session ?? "").trim();
  const hasIdentityFilter = checkpoint || session;
  const changedFiles = query.trim() || explicitFiles.length > 0 || hasIdentityFilter ? [] : await changedFilesForRecall(root);
  const files = explicitFiles.length > 0 ? explicitFiles : changedFiles;
  const terms = query.toLowerCase().split(/\s+/).filter(Boolean);
  const limit = parsePositiveInteger(args.limit ?? "5", "--limit");
  const field = normalizeSearchField(args.field);

  if (terms.length === 0 && files.length === 0 && !hasIdentityFilter) {
    fail("recall query, --files, --checkpoint, --session, or local file changes are required");
  }

  const index = await loadSearchIndex(root);
  const matches = rankRecallEntries(index.entries, terms, files, { checkpoint, session, field }).slice(0, limit);
  const payload = recallPayload(query, field, files, checkpoint, session, matches);
  const document = args.json ? `${JSON.stringify(payload, null, 2)}\n` : renderRecallMarkdown(query, field, files, checkpoint, session, matches);
  if (args.output) {
    const outputPath = resolve(args.output);
    await mkdir(dirname(outputPath), { recursive: true });
    await writeFile(outputPath, document);
    print({
      ok: true,
      schema_version: "trace.recall_output.v1",
      output: args.output,
      matches: matches.length,
      bytes: Buffer.byteLength(document),
    });
    return;
  }

  if (args.json) {
    process.stdout.write(document);
    return;
  }

  process.stdout.write(document);
}

function recallPayload(query, field, files, checkpoint, session, matches) {
  return {
    ok: true,
    schema_version: "trace.recall.v1",
    query: query.trim(),
    field,
    files,
    checkpoint: checkpoint || null,
    session: session || null,
    matches: matches.length,
    results: matches.map(({ score, entry }) => ({
      score,
      sha: entry.sha,
      file: entry.file,
      checkpoint: entry.checkpoint,
      session: entry.session,
      created: entry.created,
      title: recallTitle(entry),
      agents: entry.agents,
      lifecycle: entry.lifecycle,
      intent: entry.intent,
      summary: entry.summary,
      decisions: entry.decisions,
      responses: entry.responses,
      tools: entry.tools,
      files: entry.files,
      validation: entry.validation,
      risks: entry.risks,
      handoff: entry.handoff,
    })),
  };
}

function renderRecallMarkdown(query, field, files, checkpoint, session, matches) {
  const lines = ["# Trace Recall", ""];
  if (query.trim()) {
    lines.push(`Query: \`${query.trim()}\``);
  }
  if (field !== "text") {
    lines.push(`Field: \`${field}\``);
  }
  if (files.length > 0) {
    lines.push(`Files: ${files.map((file) => `\`${file}\``).join(", ")}`);
  }
  if (checkpoint) {
    lines.push(`Checkpoint Filter: \`${checkpoint}\``);
  }
  if (session) {
    lines.push(`Session Filter: \`${session}\``);
  }
  lines.push(`Matches: ${matches.length}`, "");

  if (matches.length === 0) {
    lines.push("No Trace memories matched.", "");
  }

  for (const match of matches) {
    const entry = match.entry;
    lines.push(`## ${entry.sha.slice(0, 12)} ${recallTitle(entry)}`, "");
    lines.push(`Memory: \`${entry.file}\``);
    lines.push(`Checkpoint: \`${entry.checkpoint}\``);
    lines.push(`Session: \`${entry.session}\``);
    lines.push(`Score: ${match.score}`);
    appendRecallSection(lines, "Agents", entry.agents);
    appendRecallSection(lines, "Lifecycle", entry.lifecycle);
    appendRecallSection(lines, "Intent", entry.intent);
    appendRecallSection(lines, "Summary", entry.summary);
    appendRecallSection(lines, "Decisions", entry.decisions);
    appendRecallSection(lines, "Responses", entry.responses);
    appendRecallSection(lines, "Tool Activity", entry.tools);
    appendRecallSection(lines, "Files", entry.files);
    appendRecallSection(lines, "Validation", entry.validation);
    appendRecallSection(lines, "Risks", entry.risks);
    appendRecallSection(lines, "Handoff", entry.handoff);
    lines.push("");
  }

  return `${lines.join("\n").trimEnd()}\n`;
}

async function changedFilesForRecall(root) {
  const output = await git(["diff", "--name-only", "HEAD"], { cwd: root, allowFailure: true });
  return output.split("\n").map((file) => file.trim()).filter(Boolean);
}

function rankRecallEntries(entries, terms, files, filters = {}) {
  const normalizedFiles = files.map((file) => file.toLowerCase());
  const checkpoint = String(filters.checkpoint ?? "").toLowerCase();
  const session = String(filters.session ?? "").toLowerCase();
  const field = filters.field ?? "text";
  const matches = [];

  for (const entry of entries) {
    if (checkpoint && String(entry.checkpoint ?? "").toLowerCase() !== checkpoint) {
      continue;
    }
    if (session && String(entry.session ?? "").toLowerCase() !== session) {
      continue;
    }

    const searchable = field === "text"
      ? `${entry.text}\n${entry.files}\n${entry.file}`.toLowerCase()
      : searchFieldText(entry, field).toLowerCase();
    let score = 0;
    if (checkpoint) {
      score += 10;
    }
    if (session) {
      score += 10;
    }

    for (const term of terms) {
      if (searchable.includes(term)) {
        score += 3;
      }
    }

    for (const file of normalizedFiles) {
      const basename = file.split("/").pop();
      if (searchable.includes(file)) {
        score += 8;
      } else if (basename && searchable.includes(basename)) {
        score += 4;
      }
    }

    if (score > 0) {
      matches.push({ score, entry });
    }
  }

  return matches.sort((left, right) => right.score - left.score || left.entry.file.localeCompare(right.entry.file));
}

function appendRecallSection(lines, name, value) {
  const content = String(value ?? "").trim();
  if (!content || content === "- Not recorded.") {
    return;
  }
  lines.push("", `### ${name}`, "", content);
}

function recallTitle(entry) {
  return entry.title.replace(new RegExp(`^${escapeRegExp(entry.sha.slice(0, 12))}\\s+`), "");
}

async function rebuildSearchIndex() {
  const root = await repoRoot();
  const index = await buildSearchIndex(root);
  const path = await searchIndexPath(root);
  await mkdir(dirname(path), { recursive: true });
  await writeFile(path, `${JSON.stringify(index, null, 2)}\n`);
  print({ ok: true, path: relativePath(root, path), entries: index.entries.length });
}

async function loadSearchIndex(root) {
  const path = await searchIndexPath(root);
  const currentFiles = await memoryFingerprints(root);
  const existing = await readFile(path, "utf8").then((content) => JSON.parse(content)).catch(() => null);

  if (existing?.schema_version === "trace.search_index.v1" && sameFingerprints(existing.files, currentFiles)) {
    return existing;
  }

  const rebuilt = await buildSearchIndex(root, currentFiles);
  await mkdir(dirname(path), { recursive: true });
  await writeFile(path, `${JSON.stringify(rebuilt, null, 2)}\n`);
  return rebuilt;
}

async function buildSearchIndex(root, files = null) {
  const memoryFiles = files ?? await memoryFingerprints(root);
  const entries = [];

  for (const file of memoryFiles) {
    const content = await readFile(join(root, file.path), "utf8");
    const sha = content.match(/^Commit: `([^`]+)`/m)?.[1] ?? "";
    const entry = {
      sha,
      file: file.path,
      checkpoint: content.match(/^Checkpoint: `([^`]+)`/m)?.[1] ?? "none",
      session: content.match(/^Session: `([^`]+)`/m)?.[1] ?? "none",
      created: content.match(/^Created: `([^`]+)`/m)?.[1] ?? "",
      title: firstLine(content.replace(/^#\s*/, "")),
      agents: section(content, "Agents") ?? "",
      lifecycle: section(content, "Lifecycle") ?? "",
      intent: section(content, "Intent") ?? "",
      summary: section(content, "Summary") ?? "",
      decisions: section(content, "Decisions") ?? "",
      responses: section(content, "Responses") ?? "",
      tools: section(content, "Tool Activity") ?? "",
      files: section(content, "Files") ?? "",
      validation: section(content, "Validation") ?? "",
      risks: section(content, "Risks") ?? "",
      handoff: section(content, "Handoff") ?? "",
    };
    entries.push({
      ...entry,
      text: [
        entry.title,
        entry.agents,
        entry.lifecycle,
        entry.intent,
        entry.summary,
        entry.decisions,
        entry.responses,
        entry.tools,
        entry.files,
        entry.validation,
        entry.risks,
        entry.handoff,
      ].filter(Boolean).join("\n"),
    });
  }

  return {
    schema_version: "trace.search_index.v1",
    created_at: now(),
    files: memoryFiles,
    entries,
  };
}

async function summarizeRange(range, options = {}) {
  const root = await repoRoot();
  const memories = await memoriesForRange(root, range);
  await writeSummaryDocument(range, memories, options);
}

async function summarizeBranch(branch) {
  const root = await repoRoot();
  const base = args.base ?? await defaultBranchBase(root, branch);
  const mergeBase = await git(["merge-base", base, branch], { cwd: root, allowFailure: true });
  if (!mergeBase) {
    fail(`could not find merge-base for ${base} and ${branch}`);
  }

  const resolvedBranch = await git(["rev-parse", "--abbrev-ref", branch], { cwd: root, allowFailure: true }) || branch;
  const range = `${mergeBase}..${branch}`;
  const memories = await memoriesForRange(root, range);
  await writeSummaryDocument(range, memories, {
    branchSummary: true,
    branch: resolvedBranch,
    base,
  });
}

async function defaultBranchBase(root, branch) {
  const upstream = await git(["rev-parse", "--abbrev-ref", `${branch}@{upstream}`], { cwd: root, allowFailure: true });
  if (upstream) {
    return upstream;
  }

  for (const candidate of ["origin/main", "origin/master", "main", "master"]) {
    if (candidate === branch) {
      continue;
    }
    const exists = await git(["rev-parse", "--verify", `${candidate}^{commit}`], { cwd: root, allowFailure: true });
    if (exists) {
      return candidate;
    }
  }

  fail("branch summary needs --base when no upstream, main, or master base exists");
}

async function memoriesForRange(root, range) {
  const commits = (await git(["rev-list", "--reverse", range], { cwd: root })).split("\n").filter(Boolean);
  const memories = [];

  for (const sha of commits) {
    const memoryPath = memoryPathFor(root, sha);
    if (await exists(memoryPath)) {
      memories.push(await readFile(memoryPath, "utf8"));
    }
  }

  return memories;
}

async function writeSummaryDocument(range, memories, options = {}) {
  const payload = summaryPayload(range, memories, options);
  const document = args.json ? `${JSON.stringify(payload, null, 2)}\n` : renderSummaryMarkdown(range, memories, options);
  if (args.output) {
    const outputPath = resolve(args.output);
    await mkdir(dirname(outputPath), { recursive: true });
    await writeFile(outputPath, document);
    print({
      ok: true,
      schema_version: "trace.summary_output.v1",
      kind: payload.kind,
      range,
      output: args.output,
      bytes: Buffer.byteLength(document),
    });
    return;
  }

  if (args.json) {
    process.stdout.write(document);
    return;
  }

  process.stdout.write(document);
}

function renderSummaryMarkdown(range, memories, options = {}) {
  const title = options.releaseNotes ? "Trace Release Notes" : options.prBody ? "Trace PR Summary" : "Trace Summary";
  const summaryTitle = options.branchSummary ? "Trace Branch Summary" : title;
  const lines = [`# ${summaryTitle}`, ""];
  if (options.branchSummary) {
    lines.push(`Branch: \`${options.branch}\``, `Base: \`${options.base}\``);
  }
  lines.push(`Range: \`${range}\``);
  if (memories.length === 0) {
    lines.push("", "No Trace memories found for this range.", "");
  } else if (options.releaseNotes) {
    lines.push("", "## Highlights", "");
    appendReleaseHighlights(lines, memories);

    lines.push("", "## Agents", "");
    appendMergedSection(lines, memories, "Agents");

    lines.push("", "## Lifecycle", "");
    appendMergedSection(lines, memories, "Lifecycle");

    lines.push("", "## Decisions", "");
    appendMergedSection(lines, memories, "Decisions");

    lines.push("", "## Changed Files", "");
    appendMergedSection(lines, memories, "Files");

    lines.push("", "## Validation", "");
    appendMergedSection(lines, memories, "Validation");

    lines.push("", "## Risks", "");
    appendMergedSection(lines, memories, "Risks");

    lines.push("", "## Handoff", "");
    appendMergedSection(lines, memories, "Handoff");

    lines.push("", "## Commits", "");
    appendCommitList(lines, memories);
  } else {
    lines.push("", "## Intent", "");
    for (const memory of memories) {
      const intent = section(memory, "Intent") ?? "No intent recorded.";
      lines.push(`- ${firstLine(intent)}`);
    }

    lines.push("", "## Decisions", "");
    appendMergedSection(lines, memories, "Decisions");

    lines.push("", "## Agents", "");
    appendMergedSection(lines, memories, "Agents");

    lines.push("", "## Lifecycle", "");
    appendMergedSection(lines, memories, "Lifecycle");

    if (options.branchSummary) {
      lines.push("", "## Changed Files", "");
      appendMergedSection(lines, memories, "Files");
    }

    lines.push("", "## Validation", "");
    appendMergedSection(lines, memories, "Validation");

    lines.push("", "## Risks", "");
    appendMergedSection(lines, memories, "Risks");

    lines.push("", "## Handoff", "");
    appendMergedSection(lines, memories, "Handoff");

    lines.push("", "## Commits", "");
    appendCommitList(lines, memories);
    lines.push("", "## Review Notes", "", "Use `trace show <commit>` for the full memory attached to each commit.");
  }

  return `${lines.join("\n")}\n`;
}

function summaryPayload(range, memories, options = {}) {
  const records = memories.map(memoryRecord);
  return {
    ok: true,
    schema_version: "trace.summary.v1",
    kind: options.releaseNotes ? "release" : options.prBody ? "pr" : options.branchSummary ? "branch" : "range",
    range,
    branch: options.branch ?? null,
    base: options.base ?? null,
    memories: records.length,
    intent: records.map((record) => record.intent).filter(Boolean),
    highlights: records.flatMap((record) => record.summary.length > 0 ? record.summary : [record.intent].filter(Boolean)),
    agents: uniqueValues(records.flatMap((record) => record.agents)),
    lifecycle: uniqueValues(records.flatMap((record) => record.lifecycle)),
    decisions: records.flatMap((record) => record.decisions),
    files: uniqueValues(records.flatMap((record) => record.files)),
    validation: records.flatMap((record) => record.validation),
    risks: records.flatMap((record) => record.risks),
    handoff: records.flatMap((record) => record.handoff),
    commits: records.map((record) => ({
      commit: record.commit,
      memory: record.memory,
      checkpoint: record.checkpoint,
      session: record.session,
      created: record.created,
      agents: record.agents,
      lifecycle: record.lifecycle,
      intent: record.intent,
      summary: record.summary,
      decisions: record.decisions,
      files: record.files,
      validation: record.validation,
      risks: record.risks,
      handoff: record.handoff,
    })),
  };
}

function memoryRecord(memory) {
  const commit = memory.match(/^Commit: `([^`]+)`/m)?.[1] ?? "unknown";
  return {
    commit,
    memory: `${TRACE_DIR}/commits/${commit.slice(0, 2)}/${commit}.md`,
    checkpoint: memory.match(/^Checkpoint: `([^`]+)`/m)?.[1] ?? "none",
    session: memory.match(/^Session: `([^`]+)`/m)?.[1] ?? "none",
    created: memory.match(/^Created: `([^`]+)`/m)?.[1] ?? "",
    agents: sectionItems(memory, "Agents", ["No agent adapters recorded."]),
    lifecycle: sectionItems(memory, "Lifecycle", ["No lifecycle events recorded."]),
    intent: firstLine(section(memory, "Intent") ?? ""),
    summary: sectionItems(memory, "Summary", ["Not recorded."]),
    decisions: sectionItems(memory, "Decisions", ["Not recorded."]),
    responses: sectionItems(memory, "Responses", ["Not recorded."]),
    tools: sectionItems(memory, "Tool Activity", ["Not recorded."]),
    files: sectionItems(memory, "Files", ["No files reported by git."]).map((file) => file.replace(/^`|`$/g, "")),
    validation: sectionItems(memory, "Validation", ["Not recorded."]),
    risks: sectionItems(memory, "Risks", ["No known open risks recorded."]),
    handoff: sectionItems(memory, "Handoff", ["Not recorded."]),
  };
}

function sectionItems(memory, name, ignored = []) {
  const value = section(memory, name);
  if (!value) {
    return [];
  }
  return value.split("\n")
    .map((line) => line.trim().replace(/^- /, "").trim())
    .filter(Boolean)
    .filter((line) => !ignored.includes(line));
}

function uniqueValues(values) {
  return Array.from(new Set(values.filter(Boolean))).sort();
}

async function hookPrepareCommitMsg(values) {
  const root = await repoRoot();
  await ensureTrace(root);
  const commitMsgFile = values[0];
  if (!commitMsgFile) {
    fail("commit message file is required");
  }

  const current = await readFile(commitMsgFile, "utf8");
  if (/^Trace-Checkpoint:/m.test(current)) {
    return;
  }

  const sessionId = await currentOrNewSession(root);
  const checkpointId = randomHex(12);
  await writePendingCommit(root, { sessionId, checkpointId, createdAt: now() });
  const needsNewline = current.endsWith("\n") ? "" : "\n";
  await writeFile(commitMsgFile, `${current}${needsNewline}\nTrace-Checkpoint: ${checkpointId}\nTrace-Session: ${sessionId}\n`);
}

async function hookPreCommit() {
  const root = await repoRoot();
  const unsafeFiles = await stagedUnsafeTraceFiles(root);
  if (unsafeFiles.length === 0) {
    return;
  }

  process.stderr.write([
    "Trace blocked unsafe raw memory files from being committed.",
    "Raw transcripts and checkpoint payloads must stay outside the project tree.",
    ...unsafeFiles.map((file) => `- ${file}`),
    "Move these files out of .trace/ or remove them from the index, then retry.",
    "",
  ].join("\n"));
  process.exitCode = 1;
}

async function traceCommitTrailers(root, sha) {
  const body = await git(["show", "-s", "--format=%B", sha], { cwd: root });
  return {
    checkpoint: body.match(/^Trace-Checkpoint:\s*(\S+)/m)?.[1] ?? null,
    session: body.match(/^Trace-Session:\s*(\S+)/m)?.[1] ?? null,
  };
}

async function hookPostCommit() {
  const root = await repoRoot();
  const pending = await readPendingCommit(root).catch(() => null);
  const sha = await resolveCommit("HEAD");
  const trailers = await traceCommitTrailers(root, sha);
  const sessionId = pending?.sessionId ?? trailers.session ?? await readCurrentSession(root).catch(() => null);
  const checkpointId = pending?.checkpointId ?? trailers.checkpoint ?? randomHex(12);
  const memory = await buildMemory(root, sha, checkpointId, sessionId, {});
  const memoryPath = memoryPathFor(root, sha);
  await mkdir(dirname(memoryPath), { recursive: true });
  await writeFile(memoryPath, memory.markdown);
  await writeCheckpointRef(root, checkpointId, memory.rawCheckpoint);
  await rm(await pendingCommitPath(root), { force: true });
}

async function hookAgent(values) {
  const root = await repoRoot();
  const dryRun = Boolean(args["dry-run"]);
  if (!dryRun) {
    await ensureTrace(root);
  }
  const raw = await readStdin();
  const payload = parseOptionalJson(raw);
  const jsonLines = payload == null ? parseOptionalJsonLines(raw) : null;
  const payloads = jsonLines ?? (Array.isArray(payload) ? payload : [payload]);
  const events = [];

  for (const item of payloads) {
    const sessionId = args.session ?? item?.session_id ?? item?.sessionId;
    const normalizedEvents = normalizeAgentPayloadEvents(args.adapter ?? args.source, args.event ?? firstPositional(values), item, raw);
    for (const normalized of normalizedEvents) {
      const event = {
        sessionId,
        event: normalized.event,
        role: args.role ?? normalized.role,
        source: args.source ?? normalized.source,
        adapter: normalized.adapter,
        message: args.message ?? normalized.message,
      };
      events.push(dryRun ? await previewEvent(root, event) : await appendEvent(root, event));
    }
  }

  if (dryRun) {
    print({ ok: true, schema_version: "trace.agent_hook_result.v1", dryRun: true, events });
    return;
  }

  if (events.length === 1) {
    const event = events[0];
    print({
      ok: true,
      schema_version: "trace.agent_hook_result.v1",
      dryRun: false,
      session: event.session_id,
      event: event.event,
      source: event.source,
      adapter: event.adapter,
    });
    return;
  }

  print({
    ok: true,
    schema_version: "trace.agent_hook_result.v1",
    dryRun: false,
    events: events.map((event) => ({ session: event.session_id, event: event.event, source: event.source, adapter: event.adapter })),
  });
}

async function previewEvent(root, input) {
  return {
    schema_version: "trace.event.v1",
    session_id: input.sessionId ?? null,
    event: input.event,
    role: input.role,
    source: input.source ?? "manual",
    adapter: input.adapter ?? null,
    message: await redact(root, input.message),
    created_at: now(),
  };
}

async function buildMemory(root, sha, checkpointId, sessionId, overrides) {
  const [subject, author, createdAt] = (await git(["show", "-s", "--format=%s%n%an <%ae>%n%cI", sha], { cwd: root })).split("\n");
  const files = (await git(["show", "--name-only", "--format=", sha], { cwd: root })).split("\n").filter(Boolean);
  const events = sessionId ? await readSessionEvents(root, sessionId).catch(() => []) : [];
  const memoryEvents = events.filter(includeInCommitMemory);
  const extracted = extractedMemorySignals(memoryEvents);
  const prompts = [
    ...memoryEvents.filter((event) => event.role === "user" || event.event === "prompt").map((event) => event.message).filter(Boolean),
    ...extracted.prompts,
  ];
  const decisions = [
    ...memoryEvents.filter((event) => event.event === "decision").map((event) => event.message).filter(Boolean),
    ...extracted.decisions,
  ];
  const responses = memoryEvents.filter((event) => event.event === "response" || event.role === "assistant").map((event) => event.message).filter(Boolean);
  const tools = memoryEvents.filter((event) => event.event === "tool").map((event) => event.message).filter(Boolean);
  const validations = [
    ...memoryEvents.filter((event) => event.event === "validation").map((event) => event.message).filter(Boolean),
    ...extracted.validation,
  ];
  const risks = [
    ...memoryEvents.filter((event) => event.event === "risk").map((event) => event.message).filter(Boolean),
    ...extracted.risks,
  ];
  const notes = memoryEvents.filter((event) => !["prompt", "response", "tool", "decision", "validation", "risk"].includes(event.event)).map((event) => event.message).filter(Boolean);
  const agents = memoryAgentItems(memoryEvents);
  const lifecycle = memoryLifecycleItems(memoryEvents);
  const summaryEvents = [...responses, ...tools, ...notes].slice(-3);
  const intent = await conciseMemoryText(root, overrides.intent ?? prompts.at(-1) ?? subject);
  const agentLines = await formatMemoryList(root, agents, "No agent adapters recorded.");
  const lifecycleLines = await formatMemoryList(root, lifecycle, "No lifecycle events recorded.");
  const summary = await formatMemoryList(root, summaryEvents.length > 0 ? summaryEvents : [subject]);
  const decisionLines = await formatMemoryList(root, decisions, "Not recorded.");
  const responseLines = await formatMemoryList(root, responses, "Not recorded.");
  const toolLines = await formatMemoryList(root, tools, "Not recorded.");
  const validation = await formatMemoryList(root, [overrides.validation, ...validations].filter(Boolean), "Not recorded.");
  const risk = await formatMemoryList(root, [overrides.risk, ...risks].filter(Boolean), "No known open risks recorded.");
  const handoff = await formatMemoryList(root, handoffItems({
    decisions,
    validations: [overrides.validation, ...validations].filter(Boolean),
    risks: [overrides.risk, ...risks].filter(Boolean),
    files,
    subject,
  }), "Review this memory and the commit diff before changing related code.");
  const fileLines = formatFileList(files);
  const rawCheckpoint = {
    schema_version: "trace.checkpoint.v1",
    checkpoint_id: checkpointId,
    session_id: sessionId,
    commit: sha,
    subject,
    author,
    created_at: createdAt,
    files,
    events,
  };
  const markdown = `# ${sha.slice(0, 12)} ${subject}

Schema: \`${MEMORY_VERSION}\`
Commit: \`${sha}\`
Checkpoint: \`${checkpointId}\`
Session: \`${sessionId ?? "none"}\`
Created: \`${createdAt}\`

## Agents

${agentLines}

## Lifecycle

${lifecycleLines}

## Intent

${intent}

## Summary

${summary}

## Decisions

${decisionLines}

## Responses

${responseLines}

## Tool Activity

${toolLines}

## Files

${fileLines}

## Validation

${validation}

## Risks

${risk}

## Handoff

${handoff}
`;

  return { markdown, rawCheckpoint };
}

function includeInCommitMemory(event) {
  return event.source !== "trace-session";
}

function memoryAgentItems(events) {
  const adapters = compactMemoryItems(events.map((event) => event.adapter).filter(Boolean));
  const adapterSet = new Set(adapters.map((adapter) => adapter.toLowerCase()));
  const sources = compactMemoryItems(events
    .map((event) => event.source)
    .filter((source) => source && source !== "manual" && !adapterSet.has(String(source).toLowerCase())));
  return [
    ...adapters.map((adapter) => `adapter: ${adapter}`),
    ...sources.map((source) => `source: ${source}`),
  ];
}

function memoryLifecycleItems(events) {
  if (events.length === 0) {
    return [];
  }

  const counts = new Map(TRACE_EVENTS.map((event) => [event, 0]));
  for (const event of events) {
    const eventName = TRACE_EVENTS.includes(event.event) ? event.event : "note";
    counts.set(eventName, (counts.get(eventName) ?? 0) + 1);
  }

  return [
    `total: ${events.length}`,
    ...Array.from(counts.entries())
      .filter(([, count]) => count > 0)
      .map(([event, count]) => `${event}: ${count}`),
  ];
}

async function writeCheckpointRef(root, checkpointId, payload) {
  const common = await gitCommonDir(root);
  const scratch = join(common, "trace", "tmp");
  await mkdir(scratch, { recursive: true });
  const payloadPath = join(scratch, `${checkpointId}.json`);
  const indexPath = join(scratch, `index-${process.pid}-${checkpointId}`);
  await writeFile(payloadPath, `${JSON.stringify(withCheckpointIntegrity(payload), null, 2)}\n`);

  const env = { ...process.env, GIT_INDEX_FILE: indexPath };
  const parent = await git(["rev-parse", "--verify", CHECKPOINT_REF], { cwd: root, allowFailure: true });
  const tree = await git(["rev-parse", "--verify", `${CHECKPOINT_REF}^{tree}`], { cwd: root, env, allowFailure: true });

  if (tree) {
    await git(["read-tree", tree], { cwd: root, env });
  } else {
    await git(["read-tree", "--empty"], { cwd: root, env });
  }

  const blob = await git(["hash-object", "-w", payloadPath], { cwd: root, env });
  await git(["update-index", "--add", "--cacheinfo", `100644,${blob},checkpoints/${checkpointId}.json`], { cwd: root, env });
  const newTree = await git(["write-tree"], { cwd: root, env });
  const commitArgs = ["commit-tree", newTree, "-m", `Trace checkpoint ${checkpointId}`];
  if (parent) {
    commitArgs.splice(2, 0, "-p", parent);
  }
  const commit = await git(commitArgs, { cwd: root, env });
  await git(["update-ref", CHECKPOINT_REF, commit], { cwd: root });
  await rm(indexPath, { force: true });
  await rm(payloadPath, { force: true });
}

async function installHook(name, traceCommand) {
  const hooksDir = await gitHooksDir();
  const hookPath = join(hooksDir, name);
  const managed = [
    HOOK_START,
    expectedHookLine(traceCommand),
    HOOK_END,
    "",
  ].join("\n");
  const existing = await readFile(hookPath, "utf8").catch(() => "#!/bin/sh\n");
  const withoutManaged = stripManagedBlock(existing);
  const next = withoutManaged.endsWith("\n") ? `${withoutManaged}\n${managed}` : `${withoutManaged}\n\n${managed}`;
  await writeFile(hookPath, next);
  await chmod(hookPath, 0o755);
}

async function removeManagedBlock(file) {
  const existing = await readFile(file, "utf8").catch(() => null);
  if (existing == null) {
    return;
  }
  await writeFile(file, stripManagedBlock(existing));
}

function stripManagedBlock(content) {
  const pattern = new RegExp(`\\n?${escapeRegExp(HOOK_START)}[\\s\\S]*?${escapeRegExp(HOOK_END)}\\n?`, "g");
  return content.replace(pattern, "\n").replace(/\n{3,}/g, "\n\n").trimEnd() + "\n";
}

function traceHookCommand(name) {
  if (name === "pre-commit") {
    return `trace hook pre-commit "$@"`;
  }
  if (name === "prepare-commit-msg") {
    return `trace hook prepare-commit-msg "$@"`;
  }
  if (name === "post-commit") {
    return `trace hook post-commit "$@"`;
  }
  fail(`unknown managed hook ${name}`);
}

function expectedHookLine(traceCommand) {
  const cliPath = fileURLToPath(import.meta.url);
  return `node ${shellQuote(cliPath)} ${traceCommand.replace(/^trace /, "")}`;
}

function tracePackageRoot() {
  return resolve(dirname(fileURLToPath(import.meta.url)), "..");
}

async function ensureTrace(root) {
  if (!await exists(join(root, TRACE_DIR, "config.json"))) {
    await initRepo();
  }
}

async function configStatus(root) {
  const path = join(root, TRACE_DIR, "config.json");
  if (!await exists(path)) {
    return { ok: false, schema: null, error: "missing config" };
  }

  try {
    const config = JSON.parse(await readFile(path, "utf8"));
    return {
      ok: config.schema_version === CONFIG_VERSION,
      schema: config.schema_version ?? null,
      error: config.schema_version === CONFIG_VERSION ? null : `unsupported schema ${config.schema_version ?? "none"}`,
    };
  } catch (error) {
    return { ok: false, schema: null, error: error.message };
  }
}

async function loadTraceConfig(root) {
  const path = join(root, TRACE_DIR, "config.json");
  if (!await exists(path)) {
    return {
      schema_version: CONFIG_VERSION,
      redaction: { custom_rules: [] },
    };
  }
  return JSON.parse(await readFile(path, "utf8"));
}

async function writeTraceConfig(root, config) {
  await writeFile(join(root, TRACE_DIR, "config.json"), `${JSON.stringify(config, null, 2)}\n`);
}

function customRules(config) {
  const rules = config?.redaction?.custom_rules;
  return Array.isArray(rules) ? rules : [];
}

function withCustomRules(config, rules) {
  return {
    ...config,
    redaction: {
      ...(config.redaction ?? {}),
      custom_rules: rules,
    },
  };
}

async function listMemoryFiles(root) {
  const dir = join(root, TRACE_DIR, "commits");
  if (!await exists(dir)) {
    return [];
  }

  const files = [];
  await walk(dir, files);
  return files.filter((file) => file.endsWith(".md"));
}

async function auditMemoryFiles(root) {
  const files = await listMemoryFiles(root);
  const invalidMemories = [];

  for (const file of files) {
    const content = await readFile(file, "utf8");
    const relative = relativePath(root, file);
    const schema = content.match(/^Schema: `([^`]+)`/m)?.[1];
    const sha = content.match(/^Commit: `([^`]+)`/m)?.[1];
    const checkpoint = content.match(/^Checkpoint: `([^`]+)`/m)?.[1];
    const session = content.match(/^Session: `([^`]+)`/m)?.[1];
    const created = content.match(/^Created: `([^`]+)`/m)?.[1];
    if (schema !== MEMORY_VERSION) {
      invalidMemories.push({ file: relative, reason: `unsupported schema ${schema ?? "none"}` });
    }
    if (!sha) {
      invalidMemories.push({ file: relative, reason: "missing Commit field" });
      continue;
    }

    const commit = await git(["rev-parse", "--verify", `${sha}^{commit}`], { cwd: root, allowFailure: true });
    if (!commit) {
      invalidMemories.push({ file: relative, reason: `missing commit ${sha}` });
    }

    if (!checkpoint) {
      invalidMemories.push({ file: relative, reason: "missing Checkpoint field" });
    }
    if (!session) {
      invalidMemories.push({ file: relative, reason: "missing Session field" });
    }
    if (!created) {
      invalidMemories.push({ file: relative, reason: "missing Created field" });
    }

    const expected = memoryPathFor(root, sha);
    if (file !== expected) {
      invalidMemories.push({
        file: relative,
        reason: `expected ${relativePath(root, expected)}`,
      });
    }
    for (const sectionName of ["Intent", "Summary", "Decisions", "Files", "Validation", "Risks", "Handoff"]) {
      if (section(content, sectionName) == null) {
        invalidMemories.push({ file: relative, reason: `missing ${sectionName} section` });
      }
    }
  }

  return { files, invalidMemories };
}

async function dirtyTraceFiles(root) {
  return (await git(["status", "--porcelain", "-uall", "--", TRACE_DIR], { cwd: root })).split("\n").filter(Boolean);
}

async function memoryFingerprints(root) {
  const files = await listMemoryFiles(root);
  const fingerprints = [];

  for (const file of files) {
    const fileStat = await stat(file);
    fingerprints.push({
      path: relativePath(root, file),
      size: fileStat.size,
      mtimeMs: Math.round(fileStat.mtimeMs),
    });
  }

  return fingerprints.sort((left, right) => left.path.localeCompare(right.path));
}

async function isTraceOnlyCommit(root, sha) {
  const files = (await git(["show", "--name-only", "--format=", sha], { cwd: root })).split("\n").filter(Boolean);
  return files.length > 0 && files.every((file) => file === TRACE_DIR || file.startsWith(`${TRACE_DIR}/`));
}

function isUnsafeTracePath(path) {
  const normalized = path.replaceAll("\\", "/");
  if (!normalized.startsWith(`${TRACE_DIR}/`)) {
    return false;
  }

  if (normalized.startsWith(`${TRACE_DIR}/commits/`) && normalized.endsWith(".md")) {
    return false;
  }

  if (normalized === `${TRACE_DIR}/commits/.gitkeep`) {
    return false;
  }

  if (normalized === `${TRACE_DIR}/config.json`) {
    return false;
  }

  if (normalized.startsWith(`${TRACE_DIR}/agents/`) && normalized.endsWith(".json")) {
    return false;
  }

  return [
    `${TRACE_DIR}/sessions/`,
    `${TRACE_DIR}/raw/`,
    `${TRACE_DIR}/checkpoints/`,
    `${TRACE_DIR}/transcripts/`,
  ].some((prefix) => normalized.startsWith(prefix))
    || normalized.endsWith(".jsonl")
    || normalized.includes("/raw_")
    || normalized.includes("/transcript")
    || normalized.endsWith("/current_session")
    || normalized.endsWith("/pending_commit.json");
}

async function stagedUnsafeTraceFiles(root) {
  const files = (await git(["diff", "--cached", "--name-only", "--diff-filter=ACMR", "--", TRACE_DIR], { cwd: root }))
    .split("\n")
    .filter(Boolean);
  return files.filter(isUnsafeTracePath);
}

async function walk(dir, files) {
  for (const entry of await readdir(dir, { withFileTypes: true })) {
    const path = join(dir, entry.name);
    if (entry.isDirectory()) {
      await walk(path, files);
    } else {
      files.push(path);
    }
  }
}

async function readSessionEvents(root, sessionId) {
  const content = await readFile(await sessionPath(root, sessionId), "utf8");
  return content.split("\n").filter(Boolean).map((line) => JSON.parse(line));
}

async function currentOrNewSession(root) {
  const current = await readCurrentSession(root).catch(() => null);
  if (current) {
    return current;
  }
  const sessionId = newSessionId();
  await mkdir(dirname(await currentSessionPath(root)), { recursive: true });
  await writeFile(await currentSessionPath(root), sessionId);
  return sessionId;
}

async function readCurrentSession(root) {
  return (await readFile(await currentSessionPath(root), "utf8")).trim();
}

async function currentSessionPath(root) {
  return join(await gitCommonDir(root), "trace", "current_session");
}

async function pendingCommitPath(root) {
  return join(await gitCommonDir(root), "trace", "pending_commit.json");
}

async function writePendingCommit(root, payload) {
  const file = await pendingCommitPath(root);
  await mkdir(dirname(file), { recursive: true });
  await writeFile(file, `${JSON.stringify(payload, null, 2)}\n`);
}

async function readPendingCommit(root) {
  return JSON.parse(await readFile(await pendingCommitPath(root), "utf8"));
}

async function sessionPath(root, sessionId) {
  return join(await gitCommonDir(root), "trace", "sessions", `${sessionId}.jsonl`);
}

async function searchIndexPath(root) {
  return join(await gitCommonDir(root), "trace", "index.json");
}

async function searchIndexStatus(root) {
  const path = await searchIndexPath(root);
  const currentFiles = await memoryFingerprints(root);
  const content = await readFile(path, "utf8").catch(() => null);
  if (content == null) {
    return {
      path: relativePath(root, path),
      present: false,
      entries: 0,
      files: currentFiles.length,
      stale: currentFiles.length > 0,
    };
  }

  try {
    const existing = JSON.parse(content);
    const stale = existing.schema_version !== "trace.search_index.v1" || !sameFingerprints(existing.files, currentFiles);
    return {
      path: relativePath(root, path),
      present: true,
      entries: Array.isArray(existing.entries) ? existing.entries.length : 0,
      files: currentFiles.length,
      stale,
    };
  } catch (error) {
    return {
      path: relativePath(root, path),
      present: true,
      entries: 0,
      files: currentFiles.length,
      stale: true,
      error: error.message,
    };
  }
}

async function gitHooksDir() {
  const root = await repoRoot();
  const hooks = await git(["rev-parse", "--git-path", "hooks"], { cwd: root });
  return resolve(root, hooks);
}

async function traceHookStatus() {
  const preCommit = await managedHookStatus("pre-commit");
  const prepareCommitMsg = await managedHookStatus("prepare-commit-msg");
  const postCommit = await managedHookStatus("post-commit");
  return {
    preCommit: preCommit.installed,
    prepareCommitMsg: prepareCommitMsg.installed,
    postCommit: postCommit.installed,
    details: {
      preCommit,
      prepareCommitMsg,
      postCommit,
    },
  };
}

async function managedHookStatus(name) {
  const root = await repoRoot();
  const hooksDir = await gitHooksDir();
  const hookPath = join(hooksDir, name);
  const content = await readFile(hookPath, "utf8").catch(() => "");
  const block = content.match(new RegExp(`${escapeRegExp(HOOK_START)}\\n([\\s\\S]*?)\\n${escapeRegExp(HOOK_END)}`))?.[1] ?? "";
  const commands = block.split("\n").map((line) => line.trim()).filter(Boolean);
  const expectedCommand = expectedHookLine(traceHookCommand(name));
  return {
    hook: name,
    path: relativePath(root, hookPath),
    installed: block.length > 0,
    valid: commands.includes(expectedCommand),
    command: commands[0] ?? null,
    expectedCommand,
  };
}

async function gitCommonDir(root) {
  const common = await git(["rev-parse", "--git-common-dir"], { cwd: root });
  return resolve(root, common);
}

async function repoRoot() {
  return git(["rev-parse", "--show-toplevel"], { cwd: process.cwd() });
}

async function resolveCommit(commitish) {
  return git(["rev-parse", "--verify", `${commitish}^{commit}`], { cwd: process.cwd() });
}

async function git(gitArgs, options = {}) {
  const result = await run("git", gitArgs, options);
  if (result.exitCode !== 0) {
    if (options.allowFailure) {
      return "";
    }
    fail(`git ${gitArgs.join(" ")} failed: ${result.stderr.trim() || result.stdout.trim()}`);
  }
  return result.stdout.trim();
}

async function run(commandName, commandArgs, options = {}) {
  return new Promise((resolveRun) => {
    const child = spawn(commandName, commandArgs, {
      cwd: options.cwd ?? process.cwd(),
      env: options.env ?? process.env,
      stdio: ["ignore", "pipe", "pipe"],
    });
    let stdout = "";
    let stderr = "";
    child.stdout.on("data", (chunk) => { stdout += chunk; });
    child.stderr.on("data", (chunk) => { stderr += chunk; });
    child.on("close", (exitCode) => resolveRun({ exitCode, stdout, stderr }));
  });
}

async function runStreaming(commandName, commandArgs, options = {}) {
  return new Promise((resolveRun) => {
    const child = spawn(commandName, commandArgs, {
      cwd: options.cwd ?? process.cwd(),
      env: options.env ?? process.env,
      stdio: ["ignore", "pipe", "pipe"],
    });
    let stdout = "";
    let stderr = "";
    child.stdout.on("data", (chunk) => {
      stdout += chunk;
      process.stdout.write(chunk);
    });
    child.stderr.on("data", (chunk) => {
      stderr += chunk;
      process.stderr.write(chunk);
    });
    child.on("error", (error) => fail(`failed to run ${commandName}: ${error.message}`));
    child.on("close", (exitCode) => resolveRun({ exitCode: exitCode ?? 1, stdout, stderr }));
  });
}

async function readStdin() {
  const chunks = [];
  for await (const chunk of process.stdin) {
    chunks.push(chunk);
  }
  return Buffer.concat(chunks).toString("utf8").trim();
}

async function redact(root, value) {
  let redacted = String(value)
    .replace(secretAssignmentPattern(), (_match, key, separator) => `${key}${separator}REDACTED`)
    .replace(authHeaderPattern(), (_match, key, scheme) => `${key}: ${scheme} REDACTED`)
    .replace(/\b[A-Za-z0-9_=-]{24,}\b/g, (match) => match.includes("REDACTED") ? match : "REDACTED");

  const config = await loadTraceConfig(root);
  for (const rule of customRules(config)) {
    validateRegex(rule.pattern);
    redacted = redacted.replace(new RegExp(rule.pattern, "gu"), `[REDACTED_${String(rule.label).toUpperCase()}]`);
  }

  return redacted;
}

function memoryPathFor(root, sha) {
  return join(root, TRACE_DIR, "commits", sha.slice(0, 2), `${sha}.md`);
}

function defaultSummaryRange() {
  return "HEAD";
}

function print(payload) {
  if (args.json || typeof payload !== "object") {
    process.stdout.write(`${typeof payload === "string" ? payload : JSON.stringify(payload, null, 2)}\n`);
    return;
  }
  process.stdout.write(`${JSON.stringify(payload)}\n`);
}

function printHelp() {
  process.stdout.write(`Trace records compact commit memory for agentic coding.

Usage:
  trace install [install|update|uninstall|status] [--prefix DIR]
  trace init
  trace enable
  trace capture --event prompt --role user --message "why this change exists" [--dry-run]
  trace run [--event validation|tool|risk] [--session id] -- <command> [args...]
  trace session start [session-id]
  trace session end [session-id]
  trace session list
  trace session current
  trace session show <session> [--limit 20]
  trace session recap [session] [--field intent|responses|tools|decisions|validation|risks|handoff|notes] [--limit 5] [--json] [--output FILE]
  trace session check [session] [--strict] [--json]
  trace agent add <codex|claude-code|gemini|generic|all>
  trace agent list
  trace agent check [codex|claude-code|gemini|generic|all]
  trace agent remove <codex|claude-code|gemini|generic|all>
  trace checkpoint list [--limit N]
  trace checkpoint show <checkpoint> [--limit 20] [--json]
  trace checkpoint status [remote]
  trace checkpoint verify
  trace checkpoint push [remote] [--dry-run]
  trace checkpoint fetch [remote] [--dry-run]
  trace checkpoint export [--output trace-checkpoints.json]
  trace checkpoint import <trace-checkpoints.json> [--dry-run]
  trace checkpoint cleanup [--sessions-before-days 14] [--keep 100] [--dry-run]
  trace redact add <label> <regex>
  trace redact list
  trace redact audit
  trace redact preview [--text "..."] [--json]
  trace redact remove <label>
  trace coverage [range] [--agents] [--checkpoints] [--strict-memory]
  trace ci [range] [--agents] [--checkpoints] [--strict-memory]
  trace record [--commit HEAD] [--intent "..."] [--validation "..."] [--risk "..."] [--check-session] [--strict] [--dry-run]
  trace show [commit] [--json]
  trace review [--all] [--json]
  trace log [--limit 20] [--json]
  trace index
  trace search [--field agents|lifecycle|intent|summary|decisions|responses|tools|files|checkpoint|session|validation|risks|handoff] [--limit 20] [--json] [--output FILE] <query>
  trace recall [query] [--field agents|lifecycle|intent|summary|decisions|responses|tools|files|validation|risks|handoff] [--files path[,path]] [--checkpoint id] [--session id] [--limit 5] [--json] [--output FILE]
  trace summary [range] [--json] [--output FILE]
  trace branch-summary [branch] [--base main] [--json] [--output FILE]
  trace pr-body [range] [--json] [--output FILE]
  trace release-notes [range] [--json] [--output FILE]
  trace hook pre-commit
  trace hook agent [event] [--adapter codex|claude-code|gemini|generic] [--dry-run]
  trace doctor [--strict-memory]
  trace check [--checkpoints] [--strict-memory]
  trace status
  trace disable
`);
}

function fail(message) {
  process.stderr.write(`${message}\n`);
  process.exit(1);
}

async function writeFileIfMissing(path, content) {
  if (await exists(path)) {
    return;
  }
  await mkdir(dirname(path), { recursive: true });
  await writeFile(path, content);
}

async function exists(path) {
  try {
    await access(path, fsConstants.F_OK);
    return true;
  } catch {
    return false;
  }
}

async function fileIncludes(path, needle) {
  return (await readFile(path, "utf8").catch(() => "")).includes(needle);
}

function now() {
  return process.env.TRACE_NOW ?? new Date().toISOString();
}

function randomHex(length) {
  return randomBytes(Math.ceil(length / 2)).toString("hex").slice(0, length);
}

function newSessionId() {
  return `${now().slice(0, 10)}-${randomHex(16)}`;
}

function validateSessionId(sessionId) {
  const value = String(sessionId);
  if (!/^[A-Za-z0-9._-]+$/.test(value)) {
    fail("session id may only contain letters, numbers, dots, underscores, and dashes");
  }
  return value;
}

function relativePath(root, path) {
  return path.startsWith(`${root}/`) ? path.slice(root.length + 1) : path;
}

function firstLine(value) {
  return value.split("\n").find(Boolean) ?? "";
}

function splitList(value) {
  return String(value ?? "").split(",").map((entry) => entry.trim()).filter(Boolean);
}

function parsePositiveInteger(value, label) {
  const parsed = Number.parseInt(value, 10);
  if (!Number.isInteger(parsed) || parsed < 1) {
    fail(`${label} must be a positive integer`);
  }
  return parsed;
}

function section(markdown, name) {
  const pattern = new RegExp(`(?:^|\\n)## ${escapeRegExp(name)}\\n\\n([\\s\\S]*?)(?=\\n\\n## |\\s*$)`);
  return markdown.match(pattern)?.[1]?.trim() ?? null;
}

function appendMergedSection(lines, memories, name) {
  const values = memories
    .map((memory) => section(memory, name))
    .filter(Boolean)
    .filter((value) => value !== "Not recorded." && value !== "No known open risks recorded.");

  if (values.length === 0) {
    lines.push("- Not recorded.");
    return;
  }

  for (const value of values) {
    for (const line of value.split("\n").map((entry) => entry.trim()).filter(Boolean)) {
      lines.push(line.startsWith("- ") ? line : `- ${line}`);
    }
  }
}

function appendReleaseHighlights(lines, memories) {
  for (const memory of memories) {
    const summary = section(memory, "Summary");
    const intent = section(memory, "Intent") ?? "No intent recorded.";
    const value = summary && summary !== "- Not recorded." ? summary : intent;
    for (const line of value.split("\n").map((entry) => entry.trim()).filter(Boolean).slice(0, 3)) {
      lines.push(line.startsWith("- ") ? line : `- ${line}`);
    }
  }
}

function appendCommitList(lines, memories) {
  for (const memory of memories) {
    const sha = memory.match(/^Commit: `([^`]+)`/m)?.[1] ?? "unknown";
    const intent = section(memory, "Intent") ?? "No intent recorded.";
    lines.push(`- \`${sha.slice(0, 12)}\` ${firstLine(intent)}`);
  }
}

async function formatMemoryList(root, values, fallback = "Not recorded.") {
  const items = compactMemoryItems(values);
  if (items.length === 0) {
    return `- ${fallback}`;
  }

  const visible = items.slice(0, MEMORY_SECTION_LIMIT);
  const lines = [];
  for (const item of visible) {
    lines.push(`- ${await conciseMemoryText(root, item)}`);
  }

  const omitted = items.length - visible.length;
  if (omitted > 0) {
    lines.push(`- ${omitted} more event${omitted === 1 ? "" : "s"} omitted from this compact memory.`);
  }

  return lines.join("\n");
}

function handoffItems({ decisions, validations, risks, files, subject }) {
  const items = [];
  const latestDecision = compactMemoryItems(decisions).slice(0, MEMORY_SECTION_LIMIT).at(-1);
  const latestValidation = compactMemoryItems(validations).slice(0, MEMORY_SECTION_LIMIT).at(-1);
  const latestRisk = compactMemoryItems(risks).slice(0, MEMORY_SECTION_LIMIT).at(-1);

  if (latestDecision) {
    items.push(`Preserve the decision: ${latestDecision}`);
  }
  if (latestValidation) {
    items.push(`Last known validation: ${latestValidation}`);
  }
  if (latestRisk) {
    items.push(`Watch the open risk: ${latestRisk}`);
  }
  if (files.length > 0) {
    items.push(`Relevant files: ${files.join(", ")}`);
  }
  if (items.length === 0) {
    items.push(`Start from commit intent: ${subject}`);
  }

  return items;
}

async function conciseMemoryText(root, value) {
  return truncateMemoryText(await redact(root, normalizeMemoryText(value)));
}

function compactMemoryItems(values) {
  const seen = new Set();
  const items = [];

  for (const value of values) {
    const text = normalizeMemoryText(value);
    const key = text.toLowerCase();
    if (!text || seen.has(key)) {
      continue;
    }
    seen.add(key);
    items.push(text);
  }

  return items;
}

function normalizeMemoryText(value) {
  return String(value ?? "").replace(/\s+/g, " ").trim();
}

function truncateMemoryText(value) {
  if (value.length <= MEMORY_ITEM_CHAR_LIMIT) {
    return value;
  }

  return `${value.slice(0, MEMORY_ITEM_CHAR_LIMIT - 1).trimEnd()}...`;
}

function formatFileList(files) {
  if (files.length === 0) {
    return "- No files reported by git.";
  }

  const visible = files.slice(0, 20).map((file) => `- \`${file}\``);
  const omitted = files.length - visible.length;
  if (omitted > 0) {
    visible.push(`- ${omitted} more file${omitted === 1 ? "" : "s"} omitted from this compact memory.`);
  }
  return visible.join("\n");
}

function normalizeSearchField(value) {
  const field = String(value ?? "all").toLowerCase();
  const aliases = {
    all: "text",
    memory: "text",
    text: "text",
    intent: "intent",
    summary: "summary",
    decision: "decisions",
    decisions: "decisions",
    response: "responses",
    responses: "responses",
    tool: "tools",
    tools: "tools",
    activity: "tools",
    agent: "agents",
    agents: "agents",
    adapter: "agents",
    adapters: "agents",
    source: "agents",
    sources: "agents",
    lifecycle: "lifecycle",
    lifecycles: "lifecycle",
    event: "lifecycle",
    events: "lifecycle",
    file: "files",
    files: "files",
    checkpoint: "checkpoint",
    checkpoints: "checkpoint",
    session: "session",
    sessions: "session",
    validation: "validation",
    risk: "risks",
    risks: "risks",
    handoff: "handoff",
    handoffs: "handoff",
  };

  if (!aliases[field]) {
    fail(`unknown search field: ${value}`);
  }

  return aliases[field];
}

function searchFieldText(entry, field) {
  return String(entry[field] ?? "");
}

function countUnredactedAssignments(content) {
  const matches = [
    ...content.matchAll(secretAssignmentPattern()),
    ...content.matchAll(authHeaderPattern()),
  ];
  let count = 0;
  for (const match of matches) {
    if (!match[0].includes("REDACTED")) {
      count += 1;
    }
  }
  return count;
}

function secretAssignmentPattern() {
  return /\b([A-Z0-9_-]*(?:api[_-]?key|token|secret|password|access[_-]?token|refresh[_-]?token|private[_-]?key)[A-Z0-9_-]*)\b(\s*[:=]\s*)("[^"]*"|'[^']*'|[^\s]+)/gi;
}

function authHeaderPattern() {
  return /\b(authorization)\s*:\s*(bearer|basic)\s+[^\s]+/gi;
}

function countMatches(content, pattern) {
  const matches = content.match(pattern);
  return matches ? matches.length : 0;
}

function stableJson(value) {
  if (Array.isArray(value)) {
    return `[${value.map((entry) => stableJson(entry)).join(",")}]`;
  }

  if (value && typeof value === "object") {
    return `{${Object.keys(value).sort().map((key) => `${JSON.stringify(key)}:${stableJson(value[key])}`).join(",")}}`;
  }

  return JSON.stringify(value);
}

function sameFingerprints(left, right) {
  if (!Array.isArray(left) || !Array.isArray(right) || left.length !== right.length) {
    return false;
  }

  return left.every((file, index) => {
    const other = right[index];
    return file.path === other.path && file.size === other.size && file.mtimeMs === other.mtimeMs;
  });
}

function snippet(content, term) {
  const index = content.toLowerCase().indexOf(term.toLowerCase());
  if (index < 0) {
    return firstLine(content);
  }
  return content.slice(Math.max(0, index - 60), Math.min(content.length, index + 140)).replace(/\s+/g, " ").trim();
}

function positionalValues(values) {
  const positionals = [];
  for (let index = 0; index < values.length; index += 1) {
    const value = values[index];
    if (value.startsWith("--")) {
      if (!["--json", "--help", "--dry-run", "--install", "--update", "--uninstall", "--status"].includes(value)) {
        index += 1;
      }
      continue;
    }
    positionals.push(value);
  }
  return positionals;
}

function shellQuote(value) {
  return `'${String(value).replaceAll("'", "'\\''")}'`;
}

function escapeRegExp(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

function validateRegex(pattern) {
  try {
    new RegExp(pattern, "u");
  } catch (error) {
    fail(`invalid redaction pattern: ${error.message}`);
  }
}

function normalizeAdapterName(value) {
  const adapter = String(value ?? "generic").toLowerCase();
  return SUPPORTED_AGENTS.has(adapter) ? adapter : "generic";
}

function normalizeAgentEvent(adapter, explicitEvent, payload) {
  const candidate = explicitEvent
    ?? payload?.event
    ?? payload?.hook
    ?? payload?.type
    ?? payload?.kind
    ?? payload?.hook_event_name
    ?? payload?.hookEventName
    ?? "note";
  const normalized = String(candidate).toLowerCase().replaceAll("_", "-");

  if (adapter === "claude-code") {
    if (normalized === "userpromptsubmit" || normalized.includes("prompt")) {
      return "prompt";
    }
    if (normalized === "pretooluse" || normalized === "posttooluse" || normalized.includes("tool")) {
      return "tool";
    }
    if (normalized === "stop" || normalized === "subagentstop" || normalized.includes("assistant")) {
      return "response";
    }
  }

  if (adapter === "codex") {
    if (normalized.includes("user") || normalized.includes("prompt") || normalized.includes("input")) {
      return "prompt";
    }
    if (normalized.includes("assistant") || normalized.includes("response") || normalized.includes("output") || normalized.includes("completion")) {
      return "response";
    }
    if (normalized.includes("tool") || normalized.includes("function")) {
      return "tool";
    }
  }

  if (adapter === "gemini") {
    if (normalized.includes("user") || normalized.includes("prompt")) {
      return "prompt";
    }
    if (normalized.includes("model") || normalized.includes("assistant") || normalized.includes("response") || normalized.includes("output")) {
      return "response";
    }
    if (normalized.includes("tool") || normalized.includes("function")) {
      return "tool";
    }
  }

  return canonicalEventName(normalized);
}

function canonicalEventName(value) {
  if (value.includes("prompt") || value.includes("user")) {
    return "prompt";
  }
  if (value.includes("response") || value.includes("assistant") || value.includes("completion")) {
    return "response";
  }
  if (value.includes("tool") || value.includes("function")) {
    return "tool";
  }
  if (value.includes("decision")) {
    return "decision";
  }
  if (value.includes("validation") || value.includes("test") || value.includes("check")) {
    return "validation";
  }
  if (value.includes("risk") || value.includes("warning") || value.includes("error")) {
    return "risk";
  }
  return TRACE_EVENTS.includes(value) ? value : "note";
}

function parseOptionalJson(raw) {
  const trimmed = raw.trim();
  if (!trimmed.startsWith("{") && !trimmed.startsWith("[")) {
    return null;
  }

  try {
    return JSON.parse(trimmed);
  } catch {
    return null;
  }
}

function parseOptionalJsonLines(raw) {
  const lines = raw.split(/\r?\n/).map((line) => line.trim()).filter(Boolean);
  if (lines.length < 2) {
    return null;
  }

  const payloads = [];
  for (const line of lines) {
    if (!line.startsWith("{")) {
      return null;
    }

    try {
      payloads.push(JSON.parse(line));
    } catch {
      return null;
    }
  }
  return payloads;
}

function normalizeAgentPayload(adapterInput, explicitEvent, payload, raw) {
  const adapter = normalizeAdapterName(adapterInput ?? payload?.adapter ?? payload?.agent ?? payload?.source);
  const eventName = normalizeAgentEvent(adapter, explicitEvent, payload);
  return {
    event: eventName,
    role: payload?.role ?? inferRole(eventName),
    source: payload?.agent ?? payload?.source ?? adapter,
    adapter,
    message: agentPayloadMessage(adapter, eventName, payload) ?? payloadFallbackMessage(payload, raw),
  };
}

function normalizeAgentPayloadEvents(adapterInput, explicitEvent, payload, raw) {
  const primary = normalizeAgentPayload(adapterInput, explicitEvent, payload, raw);
  const events = [primary];

  if (!payload || typeof payload !== "object" || Array.isArray(payload)) {
    return events;
  }

  for (const eventName of TRACE_EVENTS) {
    for (const message of lifecycleFieldMessages(primary.adapter, eventName, payload)) {
      if (eventName === primary.event && message === primary.message) {
        continue;
      }
      events.push({
        event: eventName,
        role: inferRole(eventName),
        source: primary.source,
        adapter: primary.adapter,
        message,
      });
    }
  }

  return events;
}

function lifecycleFieldMessages(adapter, eventName, payload) {
  const keys = {
    prompt: ["prompts"],
    response: ["responses"],
    tool: ["tools", "tool_activity", "toolActivity"],
    decision: ["decision", "decisions"],
    validation: ["validation", "validations"],
    risk: ["risk", "risks"],
    note: ["note", "notes"],
  }[eventName] ?? [];
  return keys.flatMap((key) => Object.hasOwn(payload, key) ? lifecycleValueMessages(adapter, eventName, payload[key]) : []);
}

function lifecycleValueMessages(adapter, eventName, value) {
  if (value == null) {
    return [];
  }

  if (Array.isArray(value)) {
    return value.flatMap((item) => lifecycleValueMessages(adapter, eventName, item));
  }

  if (typeof value === "string") {
    const message = value.trim();
    return message ? [message] : [];
  }

  if (typeof value === "object") {
    return [agentPayloadMessage(adapter, eventName, value) ?? stringifyCompact(value)];
  }

  return [String(value)];
}

function agentPayloadMessage(adapter, eventName, payload) {
  if (!payload) {
    return null;
  }

  if (eventName === "tool") {
    return toolPayloadMessage(adapter, payload);
  }

  return payloadMessage(payload);
}

function payloadFallbackMessage(payload, raw) {
  if (payload == null) {
    return raw;
  }
  return stringifyCompact(payload);
}

function toolPayloadMessage(adapter, payload) {
  const toolName = payload.tool_name ?? payload.toolName ?? payload.name ?? payload.function_name ?? payload.functionName ?? "tool";
  const input = payload.tool_input ?? payload.toolInput ?? payload.input ?? payload.arguments ?? payload.args ?? null;
  const output = payload.tool_response ?? payload.toolResponse ?? payload.result ?? payload.output ?? payload.response ?? null;
  const parts = [`${adapter} tool ${toolName}`];

  if (input != null) {
    parts.push(`input=${stringifyCompact(input)}`);
  }

  if (output != null) {
    parts.push(`output=${stringifyCompact(output)}`);
  }

  return parts.join(" ");
}

function payloadMessage(payload) {
  if (!payload) {
    return null;
  }

  for (const key of ["message", "prompt", "text", "summary", "response", "content", "output", "completion", "decision", "validation", "risk", "note"]) {
    if (typeof payload[key] === "string" && payload[key].trim()) {
      return payload[key];
    }
  }

  return JSON.stringify(payload);
}

function stringifyCompact(value) {
  if (typeof value === "string") {
    return value.replace(/\s+/g, " ").trim();
  }
  return JSON.stringify(value);
}

function inferRole(eventName) {
  const normalized = eventName.toLowerCase();
  if (normalized.includes("prompt") || normalized.includes("user")) {
    return "user";
  }
  if (normalized.includes("stop") || normalized.includes("assistant") || normalized.includes("response")) {
    return "assistant";
  }
  return "agent";
}

function firstPositional(values) {
  for (let index = 0; index < values.length; index += 1) {
    const value = values[index];
    if (value.startsWith("--")) {
      index += 1;
      continue;
    }
    return value;
  }
  return null;
}
