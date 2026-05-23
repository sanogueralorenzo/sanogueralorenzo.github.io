#!/usr/bin/env node

import { createHash, randomBytes } from "node:crypto";
import { spawn } from "node:child_process";
import { access, chmod, mkdir, readFile, readdir, rm, stat, writeFile } from "node:fs/promises";
import { constants as fsConstants } from "node:fs";
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

    if (!value.startsWith("--")) {
      continue;
    }

    const key = value.slice(2);
    if (["json", "help", "dry-run"].includes(key)) {
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
  await installHook("prepare-commit-msg", `trace hook prepare-commit-msg "$@"`);
  await installHook("post-commit", `trace hook post-commit "$@"`);
  print({ ok: true, enabled: true });
}

async function disableRepo() {
  const hooksDir = await gitHooksDir();
  await removeManagedBlock(join(hooksDir, "prepare-commit-msg"));
  await removeManagedBlock(join(hooksDir, "post-commit"));
  print({ ok: true, enabled: false });
}

async function printStatus() {
  const root = await repoRoot();
  const common = await gitCommonDir(root);
  const hooks = await traceHookStatus(root);
  const configExists = await exists(join(root, TRACE_DIR, "config.json"));
  const config = await loadTraceConfig(root);
  const agents = await listAgentConfigs(root);
  print({
    ok: true,
    repo: root,
    config: configExists,
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
  const dirtyTrace = await dirtyTraceFiles(root);
  const checkpoint = await checkpointAudit(root);
  const searchIndex = await searchIndexStatus(root);

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
      ok: hooks.prepareCommitMsg && hooks.postCommit,
      prepareCommitMsg: hooks.prepareCommitMsg,
      postCommit: hooks.postCommit,
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
  const ok = invalidMemories.length === 0 && dirtyTrace.length === 0;
  print({
    ok,
    memories: files.length,
    checkpointRef: checkpointRef || null,
    uncommitted: dirtyTrace,
    invalidMemories,
  });

  if (!ok) {
    process.exitCode = 1;
  }
}

async function runCiCheck(range) {
  const root = await repoRoot();
  const commits = (await git(["rev-list", "--reverse", range], { cwd: root })).split("\n").filter(Boolean);
  const missingMemories = [];

  for (const sha of commits) {
    if (await isTraceOnlyCommit(root, sha)) {
      continue;
    }

    const memoryPath = memoryPathFor(root, sha);
    if (!await exists(memoryPath)) {
      missingMemories.push({
        commit: sha,
        expected: relativePath(root, memoryPath),
      });
    }
  }

  const traceFiles = (await git(["ls-files", "-co", "--exclude-standard", "--", TRACE_DIR], { cwd: root })).split("\n").filter(Boolean);
  const unsafeFiles = traceFiles.filter(isUnsafeTracePath);
  const ok = missingMemories.length === 0 && unsafeFiles.length === 0;
  print({
    ok,
    range,
    checked: commits.length,
    missingMemories,
    unsafeFiles,
  });

  if (!ok) {
    process.exitCode = 1;
  }
}

async function runCheckpointCommand(action, values) {
  if (!action || action === "list") {
    await listCheckpoints();
    return;
  }

  if (action === "verify") {
    await verifyCheckpoints();
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

  if (action === "cleanup") {
    await cleanupCheckpoints();
    return;
  }

  fail(`unknown checkpoint command: ${action}`);
}

async function listCheckpoints() {
  const root = await repoRoot();
  const checkpoints = await readCheckpointPayloads(root);
  print({ ok: true, ref: CHECKPOINT_REF, checkpoints: checkpoints.map(({ payload }) => checkpointSummary(payload)) });
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

async function cleanupCheckpoints() {
  const root = await repoRoot();
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
        await rm(file);
        removed.push(relativePath(root, file));
      }
    }
  }

  const checkpoints = checkpointKeep == null
    ? { keep: null, retained: null, removed: [] }
    : await cleanupCheckpointRef(root, checkpointKeep);
  print({ ok: true, sessionsBeforeDays: days, removed, checkpoints });
}

async function readCheckpointPayloads(root) {
  const ref = await git(["rev-parse", "--verify", CHECKPOINT_REF], { cwd: root, allowFailure: true });
  if (!ref) {
    return [];
  }

  const paths = (await git(["ls-tree", "-r", "--name-only", CHECKPOINT_REF], { cwd: root })).split("\n").filter(Boolean);
  const checkpoints = [];
  for (const path of paths.filter((entry) => entry.startsWith("checkpoints/") && entry.endsWith(".json"))) {
    try {
      const raw = await git(["show", `${CHECKPOINT_REF}:${path}`], { cwd: root });
      checkpoints.push({ path, raw, payload: JSON.parse(raw) });
    } catch (error) {
      checkpoints.push({ path, payload: null, error: error.message });
    }
  }

  return checkpoints;
}

async function cleanupCheckpointRef(root, keep) {
  const checkpoints = await readCheckpointPayloads(root);
  if (checkpoints.length <= keep) {
    return { keep, retained: checkpoints.length, removed: [] };
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

  if (removed.length > 0) {
    await writeCheckpointTree(root, retained, `Trace checkpoint cleanup keep ${keep}`);
  }

  return { keep, retained: retained.length, removed };
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
  const event = await appendEvent(root, {
    sessionId: args.session,
    event: args.event ?? "note",
    role: args.role ?? "agent",
    message: args.message ?? await readStdin(),
    source: args.source ?? "manual",
  });
  print({ ok: true, session: event.session_id, event: event.event });
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

async function runAgentCommand(action, values) {
  if (action === "add" || action === "install") {
    await addAgent(values[0] ?? args.name);
    return;
  }

  if (action === "remove" || action === "rm") {
    await removeAgent(values[0] ?? args.name);
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
  const agentName = normalizeAgentName(name);
  const root = await repoRoot();
  await ensureTrace(root);
  const config = agentConfig(agentName);
  const file = agentConfigPath(root, agentName);
  await mkdir(dirname(file), { recursive: true });
  await writeFile(file, `${JSON.stringify(config, null, 2)}\n`);
  print({ ok: true, agent: agentName, config: relativePath(root, file), command: config.command });
}

async function removeAgent(name) {
  const agentName = normalizeAgentName(name);
  const root = await repoRoot();
  const file = agentConfigPath(root, agentName);
  await rm(file, { force: true });
  print({ ok: true, agent: agentName, removed: relativePath(root, file) });
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
  return {
    schema_version: AGENT_CONFIG_VERSION,
    agent: name,
    adapter: name,
    command: `trace hook agent --adapter ${name}`,
    events: TRACE_EVENTS,
    stdin: "json-or-text",
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
      agents.push({
        agent: config.agent ?? entry.name.replace(/\.json$/, ""),
        adapter: config.adapter ?? null,
        config: configPath,
        command: config.command ?? null,
        valid: config.schema_version === AGENT_CONFIG_VERSION,
      });
    } catch (error) {
      agents.push({
        agent: entry.name.replace(/\.json$/, ""),
        config: configPath,
        command: null,
        valid: false,
        error: error.message,
      });
    }
  }

  return agents.sort((left, right) => left.agent.localeCompare(right.agent));
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
  const checkpointId = args.checkpoint ?? randomHex(12);
  const sessionId = args.session ?? await readCurrentSession(root).catch(() => null);
  const memory = await buildMemory(root, sha, checkpointId, sessionId, {
    intent: args.intent,
    validation: args.validation,
    risk: args.risk,
  });
  const memoryPath = memoryPathFor(root, sha);
  await mkdir(dirname(memoryPath), { recursive: true });
  await writeFile(memoryPath, memory.markdown);
  await writeCheckpointRef(root, checkpointId, memory.rawCheckpoint);
  print({ ok: true, commit: sha, memory: relativePath(root, memoryPath), checkpoint: checkpointId });
}

async function showMemory(commitish) {
  const root = await repoRoot();
  const sha = await resolveCommit(commitish);
  const memoryPath = memoryPathFor(root, sha);
  if (!await exists(memoryPath)) {
    fail(`memory not found for commit ${sha}`);
  }
  process.stdout.write(await readFile(memoryPath, "utf8"));
}

async function logMemories() {
  const root = await repoRoot();
  const limit = Number.parseInt(args.limit ?? "20", 10);
  const files = await listMemoryFiles(root);
  const rows = [];

  for (const file of files) {
    const content = await readFile(file, "utf8");
    const sha = content.match(/^Commit: `([^`]+)`/m)?.[1] ?? file.split("/").pop()?.replace(/\.md$/, "") ?? "";
    const intent = content.match(/^## Intent\n\n([\s\S]*?)\n\n## /m)?.[1]?.trim() ?? "No intent recorded.";
    rows.push({ sha, intent: firstLine(intent), mtime: (await stat(file)).mtimeMs });
  }

  rows.sort((left, right) => right.mtime - left.mtime);
  for (const row of rows.slice(0, limit)) {
    process.stdout.write(`${row.sha.slice(0, 12)} ${row.intent}\n`);
  }
}

async function searchMemories(query) {
  if (!query.trim()) {
    fail("search query is required");
  }

  const root = await repoRoot();
  const terms = query.toLowerCase().split(/\s+/).filter(Boolean);
  const index = await loadSearchIndex(root);
  const field = normalizeSearchField(args.field);
  const matches = [];

  for (const entry of index.entries) {
    const searchable = searchFieldText(entry, field);
    const lower = searchable.toLowerCase();
    if (!terms.every((term) => lower.includes(term))) {
      continue;
    }
    matches.push({ sha: entry.sha, file: entry.file, snippet: snippet(searchable, terms[0]) });
  }

  for (const match of matches) {
    process.stdout.write(`${match.sha.slice(0, 12)} ${match.file}\n${match.snippet}\n`);
  }
}

async function recallMemories(query) {
  const root = await repoRoot();
  const explicitFiles = splitList(args.files ?? args.file);
  const changedFiles = query.trim() || explicitFiles.length > 0 ? [] : await changedFilesForRecall(root);
  const files = explicitFiles.length > 0 ? explicitFiles : changedFiles;
  const terms = query.toLowerCase().split(/\s+/).filter(Boolean);
  const limit = parsePositiveInteger(args.limit ?? "5", "--limit");

  if (terms.length === 0 && files.length === 0) {
    fail("recall query, --files, or local file changes are required");
  }

  const index = await loadSearchIndex(root);
  const matches = rankRecallEntries(index.entries, terms, files).slice(0, limit);
  const lines = ["# Trace Recall", ""];
  if (query.trim()) {
    lines.push(`Query: \`${query.trim()}\``);
  }
  if (files.length > 0) {
    lines.push(`Files: ${files.map((file) => `\`${file}\``).join(", ")}`);
  }
  lines.push(`Matches: ${matches.length}`, "");

  if (matches.length === 0) {
    lines.push("No Trace memories matched.", "");
  }

  for (const match of matches) {
    const entry = match.entry;
    lines.push(`## ${entry.sha.slice(0, 12)} ${recallTitle(entry)}`, "");
    lines.push(`Memory: \`${entry.file}\``);
    lines.push(`Score: ${match.score}`);
    appendRecallSection(lines, "Intent", entry.intent);
    appendRecallSection(lines, "Summary", entry.summary);
    appendRecallSection(lines, "Decisions", entry.decisions);
    appendRecallSection(lines, "Validation", entry.validation);
    appendRecallSection(lines, "Risks", entry.risks);
    lines.push("");
  }

  process.stdout.write(`${lines.join("\n").trimEnd()}\n`);
}

async function changedFilesForRecall(root) {
  const output = await git(["diff", "--name-only", "HEAD"], { cwd: root, allowFailure: true });
  return output.split("\n").map((file) => file.trim()).filter(Boolean);
}

function rankRecallEntries(entries, terms, files) {
  const normalizedFiles = files.map((file) => file.toLowerCase());
  const matches = [];

  for (const entry of entries) {
    const searchable = `${entry.text}\n${entry.files}\n${entry.file}`.toLowerCase();
    let score = 0;

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
      title: firstLine(content.replace(/^#\s*/, "")),
      intent: section(content, "Intent") ?? "",
      summary: section(content, "Summary") ?? "",
      decisions: section(content, "Decisions") ?? "",
      responses: section(content, "Responses") ?? "",
      tools: section(content, "Tool Activity") ?? "",
      files: section(content, "Files") ?? "",
      validation: section(content, "Validation") ?? "",
      risks: section(content, "Risks") ?? "",
    };
    entries.push({
      ...entry,
      text: [
        entry.title,
        entry.intent,
        entry.summary,
        entry.decisions,
        entry.responses,
        entry.tools,
        entry.files,
        entry.validation,
        entry.risks,
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
  writeSummaryDocument(range, memories, options);
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
  writeSummaryDocument(range, memories, {
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

function writeSummaryDocument(range, memories, options = {}) {
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

    lines.push("", "## Decisions", "");
    appendMergedSection(lines, memories, "Decisions");

    lines.push("", "## Changed Files", "");
    appendMergedSection(lines, memories, "Files");

    lines.push("", "## Validation", "");
    appendMergedSection(lines, memories, "Validation");

    lines.push("", "## Risks", "");
    appendMergedSection(lines, memories, "Risks");

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

    if (options.branchSummary) {
      lines.push("", "## Changed Files", "");
      appendMergedSection(lines, memories, "Files");
    }

    lines.push("", "## Validation", "");
    appendMergedSection(lines, memories, "Validation");

    lines.push("", "## Risks", "");
    appendMergedSection(lines, memories, "Risks");

    lines.push("", "## Commits", "");
    appendCommitList(lines, memories);
    lines.push("", "## Review Notes", "", "Use `trace show <commit>` for the full memory attached to each commit.");
  }

  process.stdout.write(`${lines.join("\n")}\n`);
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

async function hookPostCommit() {
  const root = await repoRoot();
  const pending = await readPendingCommit(root).catch(() => null);
  const sha = await resolveCommit("HEAD");
  const sessionId = pending?.sessionId ?? await readCurrentSession(root).catch(() => null);
  const checkpointId = pending?.checkpointId ?? randomHex(12);
  const memory = await buildMemory(root, sha, checkpointId, sessionId, {});
  const memoryPath = memoryPathFor(root, sha);
  await mkdir(dirname(memoryPath), { recursive: true });
  await writeFile(memoryPath, memory.markdown);
  await writeCheckpointRef(root, checkpointId, memory.rawCheckpoint);
  await rm(await pendingCommitPath(root), { force: true });
}

async function hookAgent(values) {
  const root = await repoRoot();
  await ensureTrace(root);
  const raw = await readStdin();
  const payload = parseOptionalJson(raw);
  const adapter = normalizeAdapterName(args.adapter ?? args.source ?? payload?.adapter ?? payload?.agent ?? payload?.source);
  const eventName = normalizeAgentEvent(adapter, args.event ?? firstPositional(values), payload);
  const message = args.message ?? agentPayloadMessage(adapter, eventName, payload) ?? raw;
  const role = args.role ?? payload?.role ?? inferRole(eventName);
  const source = args.source ?? payload?.agent ?? payload?.source ?? adapter;
  const sessionId = args.session ?? payload?.session_id ?? payload?.sessionId;
  const event = await appendEvent(root, {
    sessionId,
    event: eventName,
    role,
    source,
    adapter,
    message,
  });
  print({ ok: true, session: event.session_id, event: event.event, source: event.source, adapter: event.adapter });
}

async function buildMemory(root, sha, checkpointId, sessionId, overrides) {
  const [subject, author, createdAt] = (await git(["show", "-s", "--format=%s%n%an <%ae>%n%cI", sha], { cwd: root })).split("\n");
  const files = (await git(["show", "--name-only", "--format=", sha], { cwd: root })).split("\n").filter(Boolean);
  const events = sessionId ? await readSessionEvents(root, sessionId).catch(() => []) : [];
  const prompts = events.filter((event) => event.role === "user" || event.event === "prompt").map((event) => event.message).filter(Boolean);
  const decisions = events.filter((event) => event.event === "decision").map((event) => event.message).filter(Boolean);
  const responses = events.filter((event) => event.event === "response" || event.role === "assistant").map((event) => event.message).filter(Boolean);
  const tools = events.filter((event) => event.event === "tool").map((event) => event.message).filter(Boolean);
  const validations = events.filter((event) => event.event === "validation").map((event) => event.message).filter(Boolean);
  const risks = events.filter((event) => event.event === "risk").map((event) => event.message).filter(Boolean);
  const notes = events.filter((event) => !["prompt", "response", "tool", "decision", "validation", "risk"].includes(event.event)).map((event) => event.message).filter(Boolean);
  const summaryEvents = [...responses, ...tools, ...notes].slice(-3);
  const intent = await conciseMemoryText(root, overrides.intent ?? prompts.at(-1) ?? subject);
  const summary = await formatMemoryList(root, summaryEvents.length > 0 ? summaryEvents : [subject]);
  const decisionLines = await formatMemoryList(root, decisions, "Not recorded.");
  const responseLines = await formatMemoryList(root, responses, "Not recorded.");
  const toolLines = await formatMemoryList(root, tools, "Not recorded.");
  const validation = await formatMemoryList(root, [overrides.validation, ...validations].filter(Boolean), "Not recorded.");
  const risk = await formatMemoryList(root, [overrides.risk, ...risks].filter(Boolean), "No known open risks recorded.");
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
`;

  return { markdown, rawCheckpoint };
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
  const cliPath = fileURLToPath(import.meta.url);
  const managed = [
    HOOK_START,
    `node ${shellQuote(cliPath)} ${traceCommand.replace(/^trace /, "")}`,
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
    const sha = content.match(/^Commit: `([^`]+)`/m)?.[1];
    if (!sha) {
      invalidMemories.push({ file: relativePath(root, file), reason: "missing Commit field" });
      continue;
    }

    const expected = memoryPathFor(root, sha);
    if (file !== expected) {
      invalidMemories.push({
        file: relativePath(root, file),
        reason: `expected ${relativePath(root, expected)}`,
      });
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
  const sessionId = `${new Date().toISOString().slice(0, 10)}-${randomHex(16)}`;
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
  const hooksDir = await gitHooksDir();
  return {
    prepareCommitMsg: await fileIncludes(join(hooksDir, "prepare-commit-msg"), HOOK_START),
    postCommit: await fileIncludes(join(hooksDir, "post-commit"), HOOK_START),
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

async function readStdin() {
  const chunks = [];
  for await (const chunk of process.stdin) {
    chunks.push(chunk);
  }
  return Buffer.concat(chunks).toString("utf8").trim();
}

async function redact(root, value) {
  let redacted = String(value)
    .replace(/\b(api[_-]?key|token|secret|password)=("[^"]*"|'[^']*'|[^\s]+)/gi, "$1=REDACTED")
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
  trace init
  trace enable
  trace capture --event prompt --role user --message "why this change exists"
  trace agent add <codex|claude-code|gemini|generic>
  trace agent list
  trace agent remove <codex|claude-code|gemini|generic>
  trace checkpoint list
  trace checkpoint verify
  trace checkpoint push [remote] [--dry-run]
  trace checkpoint fetch [remote] [--dry-run]
  trace checkpoint cleanup [--sessions-before-days 14] [--keep 100]
  trace redact add <label> <regex>
  trace redact list
  trace redact remove <label>
  trace ci [range]
  trace record [--commit HEAD] [--intent "..."] [--validation "..."] [--risk "..."]
  trace show [commit]
  trace log [--limit 20]
  trace index
  trace search [--field decisions|files|validation|risks] <query>
  trace recall [query] [--files path[,path]] [--limit 5]
  trace summary [range]
  trace branch-summary [branch] [--base main]
  trace pr-body [range]
  trace release-notes [range]
  trace hook agent [event] [--adapter codex|claude-code|gemini|generic]
  trace doctor
  trace check
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
  const pattern = new RegExp(`^## ${escapeRegExp(name)}\\n\\n([\\s\\S]*?)(?=\\n\\n## |\\n*$)`, "m");
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
    file: "files",
    files: "files",
    validation: "validation",
    risk: "risks",
    risks: "risks",
  };

  if (!aliases[field]) {
    fail(`unknown search field: ${value}`);
  }

  return aliases[field];
}

function searchFieldText(entry, field) {
  return String(entry[field] ?? "");
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
      if (!["--json", "--help", "--dry-run"].includes(value)) {
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
  if (!trimmed.startsWith("{")) {
    return null;
  }

  try {
    return JSON.parse(trimmed);
  } catch {
    return null;
  }
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

  for (const key of ["message", "prompt", "text", "summary", "response", "content", "output", "completion"]) {
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
