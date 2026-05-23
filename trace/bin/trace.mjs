#!/usr/bin/env node

import { randomBytes } from "node:crypto";
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

  if (command === "check") {
    await checkTrace();
    return;
  }

  if (command === "capture") {
    await captureEvent();
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

  if (command === "search") {
    await searchMemories([subcommand, ...rawArgs].filter(Boolean).join(" "));
    return;
  }

  if (command === "summary") {
    await summarizeRange(subcommand ?? args.range ?? defaultSummaryRange());
    return;
  }

  if (command === "pr-body" || command === "pr") {
    await summarizeRange(subcommand ?? args.range ?? defaultSummaryRange(), { prBody: true });
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
    if (["json", "help"].includes(key)) {
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
  const prepareHook = await fileIncludes(join(await gitHooksDir(), "prepare-commit-msg"), HOOK_START);
  const postHook = await fileIncludes(join(await gitHooksDir(), "post-commit"), HOOK_START);
  const configExists = await exists(join(root, TRACE_DIR, "config.json"));
  print({
    ok: true,
    repo: root,
    config: configExists,
    hooks: {
      prepareCommitMsg: prepareHook,
      postCommit: postHook,
    },
    rawStorage: join(common, "trace", "sessions"),
    checkpointRef: CHECKPOINT_REF,
  });
}

async function checkTrace() {
  const root = await repoRoot();
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

  const dirtyTrace = (await git(["status", "--porcelain", "-uall", "--", TRACE_DIR], { cwd: root })).split("\n").filter(Boolean);
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

async function appendEvent(root, input) {
  const sessionId = input.sessionId ?? await currentOrNewSession(root);
  const event = {
    schema_version: "trace.event.v1",
    session_id: sessionId,
    event: input.event,
    role: input.role,
    source: input.source ?? "manual",
    message: redact(input.message),
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
  const files = await listMemoryFiles(root);
  const matches = [];

  for (const file of files) {
    const content = await readFile(file, "utf8");
    const lower = content.toLowerCase();
    if (!terms.every((term) => lower.includes(term))) {
      continue;
    }
    const sha = content.match(/^Commit: `([^`]+)`/m)?.[1] ?? "";
    matches.push({ sha, file: relativePath(root, file), snippet: snippet(content, terms[0]) });
  }

  for (const match of matches) {
    process.stdout.write(`${match.sha.slice(0, 12)} ${match.file}\n${match.snippet}\n`);
  }
}

async function summarizeRange(range, options = {}) {
  const root = await repoRoot();
  const commits = (await git(["rev-list", "--reverse", range], { cwd: root })).split("\n").filter(Boolean);
  const memories = [];

  for (const sha of commits) {
    const memoryPath = memoryPathFor(root, sha);
    if (await exists(memoryPath)) {
      memories.push(await readFile(memoryPath, "utf8"));
    }
  }

  const title = options.prBody ? "Trace PR Summary" : "Trace Summary";
  const lines = [`# ${title}`, "", `Range: \`${range}\``];
  if (memories.length === 0) {
    lines.push("", "No Trace memories found for this range.", "");
  } else {
    lines.push("", "## Intent", "");
    for (const memory of memories) {
      const intent = section(memory, "Intent") ?? "No intent recorded.";
      lines.push(`- ${firstLine(intent)}`);
    }

    lines.push("", "## Decisions", "");
    appendMergedSection(lines, memories, "Decisions");

    lines.push("", "## Validation", "");
    appendMergedSection(lines, memories, "Validation");

    lines.push("", "## Risks", "");
    appendMergedSection(lines, memories, "Risks");

    lines.push("", "## Commits", "");
    for (const memory of memories) {
      const sha = memory.match(/^Commit: `([^`]+)`/m)?.[1] ?? "unknown";
      const intent = memory.match(/^## Intent\n\n([\s\S]*?)\n\n## /m)?.[1]?.trim() ?? "No intent recorded.";
      lines.push(`- \`${sha.slice(0, 12)}\` ${firstLine(intent)}`);
    }
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
  const eventName = args.event ?? firstPositional(values) ?? payload?.event ?? payload?.hook ?? "agent";
  const message = args.message ?? payloadMessage(payload) ?? raw;
  const role = args.role ?? payload?.role ?? inferRole(eventName);
  const source = args.source ?? payload?.agent ?? payload?.source ?? "agent-hook";
  const sessionId = args.session ?? payload?.session_id ?? payload?.sessionId;
  const event = await appendEvent(root, {
    sessionId,
    event: eventName,
    role,
    source,
    message,
  });
  print({ ok: true, session: event.session_id, event: event.event, source: event.source });
}

async function buildMemory(root, sha, checkpointId, sessionId, overrides) {
  const [subject, author, createdAt] = (await git(["show", "-s", "--format=%s%n%an <%ae>%n%cI", sha], { cwd: root })).split("\n");
  const files = (await git(["show", "--name-only", "--format=", sha], { cwd: root })).split("\n").filter(Boolean);
  const events = sessionId ? await readSessionEvents(root, sessionId).catch(() => []) : [];
  const prompts = events.filter((event) => event.role === "user" || event.event === "prompt").map((event) => event.message).filter(Boolean);
  const decisions = events.filter((event) => event.event === "decision").map((event) => event.message).filter(Boolean);
  const validations = events.filter((event) => event.event === "validation").map((event) => event.message).filter(Boolean);
  const risks = events.filter((event) => event.event === "risk").map((event) => event.message).filter(Boolean);
  const notes = events.filter((event) => !["prompt", "decision", "validation", "risk"].includes(event.event)).map((event) => event.message).filter(Boolean);
  const intent = redact(overrides.intent ?? prompts.at(-1) ?? subject);
  const validation = redact(overrides.validation ?? validations.at(-1) ?? "Not recorded.");
  const risk = redact(overrides.risk ?? risks.at(-1) ?? "No known open risks recorded.");
  const summary = notes.length > 0 ? notes.slice(-3).map((note) => `- ${redact(note)}`).join("\n") : `- ${redact(subject)}`;
  const decisionLines = decisions.length > 0 ? decisions.map((decision) => `- ${redact(decision)}`).join("\n") : "- Not recorded.";
  const fileLines = files.length > 0 ? files.map((file) => `- \`${file}\``).join("\n") : "- No files reported by git.";
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
  await writeFile(payloadPath, `${JSON.stringify(payload, null, 2)}\n`);

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

async function listMemoryFiles(root) {
  const dir = join(root, TRACE_DIR, "commits");
  if (!await exists(dir)) {
    return [];
  }

  const files = [];
  await walk(dir, files);
  return files.filter((file) => file.endsWith(".md"));
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

async function gitHooksDir() {
  const root = await repoRoot();
  const hooks = await git(["rev-parse", "--git-path", "hooks"], { cwd: root });
  return resolve(root, hooks);
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

function redact(value) {
  return String(value)
    .replace(/\b(api[_-]?key|token|secret|password)=("[^"]*"|'[^']*'|[^\s]+)/gi, "$1=REDACTED")
    .replace(/\b[A-Za-z0-9_=-]{24,}\b/g, (match) => match.includes("REDACTED") ? match : "REDACTED");
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
  trace record [--commit HEAD] [--intent "..."] [--validation "..."] [--risk "..."]
  trace show [commit]
  trace log [--limit 20]
  trace search <query>
  trace summary [range]
  trace pr-body [range]
  trace hook agent <event>
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

function snippet(content, term) {
  const index = content.toLowerCase().indexOf(term.toLowerCase());
  if (index < 0) {
    return firstLine(content);
  }
  return content.slice(Math.max(0, index - 60), Math.min(content.length, index + 140)).replace(/\s+/g, " ").trim();
}

function shellQuote(value) {
  return `'${String(value).replaceAll("'", "'\\''")}'`;
}

function escapeRegExp(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
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

function payloadMessage(payload) {
  if (!payload) {
    return null;
  }

  for (const key of ["message", "prompt", "text", "summary", "response"]) {
    if (typeof payload[key] === "string" && payload[key].trim()) {
      return payload[key];
    }
  }

  return JSON.stringify(payload);
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
  return values.find((value) => !value.startsWith("--")) ?? null;
}
