#!/usr/bin/env node

import { spawn } from "node:child_process";
import { randomBytes } from "node:crypto";
import { constants as fsConstants } from "node:fs";
import { access, chmod, lstat, mkdir, readFile, readlink, readdir, realpath, rm, symlink, writeFile } from "node:fs/promises";
import { homedir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const TRACE_DIR = ".trace";
const CONFIG_VERSION = "trace.config.v1";
const MEMORY_VERSION = "trace.memory.v1";
const HOOK_START = "# trace:start";
const HOOK_END = "# trace:end";
const EVENTS = ["prompt", "response", "tool", "decision", "validation", "risk", "note"];

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

  if (command === "capture") {
    await captureEvent();
    return;
  }

  if (command === "hook" && subcommand === "agent") {
    await hookAgent(rawArgs);
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

  if (command === "run") {
    await runTraceCommand(subcommand, rawArgs);
    return;
  }

  if (command === "session") {
    await runSessionCommand(subcommand, rawArgs);
    return;
  }

  if (command === "record") {
    await recordMemory(subcommand);
    return;
  }

  if (command === "show") {
    await showMemory(subcommand ?? "HEAD");
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
    if (["json", "help", "dry-run", "install", "update", "uninstall", "status"].includes(key)) {
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
    raw_storage: "git-common-dir/trace/sessions",
    supported_agents: ["codex", "claude-code"],
  }, null, 2)}\n`);
  await writeFileIfMissing(join(traceRoot, "commits", ".gitkeep"), "");
  print({ ok: true, traceDir: TRACE_DIR });
}

async function enableRepo() {
  await initRepo();
  await installHook("pre-commit", traceHookCommand("pre-commit"));
  await installHook("post-commit", traceHookCommand("post-commit"));
  print({ ok: true, enabled: true });
}

async function disableRepo() {
  const hooksDir = await gitHooksDir();
  await removeManagedBlock(join(hooksDir, "pre-commit"));
  await removeManagedBlock(join(hooksDir, "post-commit"));
  print({ ok: true, enabled: false });
}

async function printStatus() {
  const root = await repoRoot();
  print({
    ok: true,
    schema_version: "trace.status.v1",
    repo: root,
    config: await exists(join(root, TRACE_DIR, "config.json")),
    hooks: await traceHookStatus(),
    currentSession: await readCurrentSession(root).catch(() => null),
    memories: (await listMemoryFiles(root)).length,
    rawStorage: join(await gitCommonDir(root), "trace", "sessions"),
  });
}

async function captureEvent() {
  const root = await repoRoot();
  const input = {
    sessionId: args.session,
    event: canonicalEvent(args.event ?? "note"),
    role: args.role ?? "agent",
    source: args.source ?? "manual",
    message: args.message ?? await readStdin(),
  };
  const event = args["dry-run"] ? await previewEvent(root, input) : await appendEvent(root, input);
  print({
    ok: true,
    schema_version: "trace.capture_result.v1",
    dryRun: Boolean(args["dry-run"]),
    session: event.session_id,
    event: event.event,
    source: event.source,
    preview: args["dry-run"] ? event : undefined,
  });
}

async function hookAgent(values) {
  const root = await repoRoot();
  const adapter = normalizeAdapter(args.adapter ?? args.agent ?? "codex");
  const explicitEvent = positionalValues(values)[0];
  const raw = await readStdin();
  const payloads = parsePayloads(raw);
  const events = [];

  for (const payload of payloads) {
    for (const event of normalizeAgentPayload(adapter, explicitEvent, payload, raw)) {
      events.push(args["dry-run"] ? await previewEvent(root, event) : await appendEvent(root, event));
    }
  }

  print({
    ok: true,
    schema_version: "trace.agent_capture.v1",
    dryRun: Boolean(args["dry-run"]),
    adapter,
    session: events[0]?.session_id ?? null,
    events: events.map((event) => ({
      session: event.session_id,
      event: event.event,
      role: event.role,
      source: event.source,
      message: event.message,
    })),
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
  const event = result.exitCode === 0 ? "validation" : "risk";
  const status = result.exitCode === 0 ? "passed" : `failed exit ${result.exitCode}`;
  await appendEvent(root, {
    sessionId: args.session,
    event,
    role: "tool",
    source: "trace-run",
    message: [`${event} ${status}: ${commandArgs.map(shellQuote).join(" ")}`, compactCommandOutput(result)].filter(Boolean).join("\n"),
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

async function runSessionCommand(action, values) {
  if (action === "start" || action === "new") {
    await startSession(values[0] ?? args.session);
    return;
  }
  if (action === "end" || action === "clear") {
    await endSession(values[0] ?? args.session);
    return;
  }
  if (action === "current") {
    const root = await repoRoot();
    print({ ok: true, current: await readCurrentSession(root).catch(() => null) });
    return;
  }
  if (action === "show") {
    await showSession(values[0] ?? args.session);
    return;
  }
  if (!action || action === "list") {
    await listSessions();
    return;
  }
  fail(`unknown session command: ${action}`);
}

async function startSession(requestedSessionId) {
  const root = await repoRoot();
  await ensureTrace(root);
  const sessionId = requestedSessionId ? validateSessionId(requestedSessionId) : newSessionId();
  const file = await sessionPath(root, sessionId);
  await mkdir(dirname(file), { recursive: true });
  await writeFile(file, "", { flag: "a" });
  await writeFile(await currentSessionPath(root), sessionId);
  print({ ok: true, session: sessionId, path: relativePath(root, file) });
}

async function endSession(expectedSessionId) {
  const root = await repoRoot();
  const current = await readCurrentSession(root).catch(() => null);
  if (!current) {
    print({ ok: true, ended: null, current: null });
    return;
  }
  if (expectedSessionId && expectedSessionId !== current) {
    fail(`current session is ${current}, not ${expectedSessionId}`);
  }
  await rm(await currentSessionPath(root), { force: true });
  print({ ok: true, ended: current, current: null });
}

async function listSessions() {
  const root = await repoRoot();
  const files = await listSessionFiles(root);
  const sessions = [];
  for (const file of files) {
    const events = await readJsonl(file);
    sessions.push({
      session: file.split("/").pop().replace(/\.jsonl$/, ""),
      path: relativePath(root, file),
      events: events.length,
      last_at: events.at(-1)?.created_at ?? null,
    });
  }
  print({ ok: true, current: await readCurrentSession(root).catch(() => null), sessions });
}

async function showSession(sessionId) {
  if (!sessionId) {
    fail("session id is required");
  }
  const root = await repoRoot();
  print({ ok: true, session: sessionId, events: await readSessionEvents(root, sessionId) });
}

async function recordMemory(commitish = null, options = {}) {
  const root = await repoRoot();
  await ensureTrace(root);
  const sha = await resolveCommit(commitish ?? args.commit ?? "HEAD");
  const sessionId = args.session ?? await readCurrentSession(root).catch(() => null);
  const memory = await buildMemory(root, sha, sessionId, {
    intent: args.intent,
    validation: args.validation,
  });
  const outputPath = memoryPathFor(root, sha);

  if (!args["dry-run"]) {
    await mkdir(dirname(outputPath), { recursive: true });
    await writeFile(outputPath, memory.markdown);
  }

  if (!options.quiet) {
    print({
      ok: true,
      schema_version: "trace.record_result.v1",
      dryRun: Boolean(args["dry-run"]),
      commit: sha,
      session: sessionId,
      memory: relativePath(root, outputPath),
      source: memory.source,
      preview: memory.preview,
      markdown: args["dry-run"] ? memory.markdown : undefined,
    });
  }
}

async function showMemory(commitish) {
  const root = await repoRoot();
  const sha = await resolveCommit(commitish);
  const file = memoryPathFor(root, sha);
  const content = await readFile(file, "utf8").catch(() => fail(`memory not found for ${sha}: ${relativePath(root, file)}`));
  const output = args.json ? `${JSON.stringify(memoryDetail(root, file, content), null, 2)}\n` : content;
  await writeOrPrint(output, {
    schema_version: "trace.show_output.v1",
    commit: sha,
    output: args.output,
  });
}

async function searchMemories(query) {
  const root = await repoRoot();
  const field = normalizeSearchField(args.field);
  const terms = queryTerms(query);
  const limit = parsePositiveInteger(args.limit ?? "20", "--limit");
  const matches = rankMemoryMatches(await memoryEntries(root), terms, field).slice(0, limit);
  const payload = {
    ok: true,
    schema_version: "trace.search_results.v1",
    query,
    field,
    matches: matches.length,
    results: matches,
  };
  const output = args.json ? `${JSON.stringify(payload, null, 2)}\n` : renderSearch(matches);
  await writeOrPrint(output, {
    schema_version: "trace.search_output.v1",
    query,
    field,
    matches: matches.length,
    output: args.output,
  });
}

async function recallMemories(query) {
  const root = await repoRoot();
  const field = normalizeSearchField(args.field);
  const files = splitList(args.files);
  const inferredFiles = query || files.length > 0 ? [] : await changedFilesForRecall(root);
  const recallFiles = files.length > 0 ? files : inferredFiles;
  const terms = queryTerms(query);
  const limit = parsePositiveInteger(args.limit ?? "5", "--limit");
  const matches = rankMemoryMatches(await memoryEntries(root), terms, field, recallFiles).slice(0, limit);
  const payload = {
    ok: true,
    schema_version: "trace.recall.v1",
    query,
    field,
    files: recallFiles,
    matches: matches.length,
    results: matches,
  };
  const output = args.json ? `${JSON.stringify(payload, null, 2)}\n` : renderRecall(payload);
  await writeOrPrint(output, {
    schema_version: "trace.recall_output.v1",
    query,
    field,
    matches: matches.length,
    output: args.output,
  });
}

async function hookPreCommit() {
  const root = await repoRoot();
  const unsafe = await stagedUnsafeTraceFiles(root);
  if (unsafe.length > 0) {
    process.stderr.write(`Trace blocks raw session data in the project tree:\n${unsafe.map((file) => `- ${file}`).join("\n")}\n`);
    process.exitCode = 1;
  }
}

async function hookPostCommit() {
  await recordMemory("HEAD", { quiet: true });
}

async function buildMemory(root, sha, sessionId, overrides = {}) {
  const subject = await git(["show", "-s", "--format=%s", sha], { cwd: root });
  const files = (await git(["diff-tree", "--root", "--no-commit-id", "--name-only", "-r", sha], { cwd: root })).split("\n").filter(Boolean);
  const events = sessionId ? await readSessionEvents(root, sessionId).catch(() => []) : [];
  const signals = memorySignals(events);
  const diffSummary = await commitDiffSummary(root, sha);
  const source = events.length > 0 ? "session" : "diff";
  const intent = overrides.intent || signals.intent || subject;
  const summary = signals.summary.length > 0 ? signals.summary : diffSummary;
  const validation = [...signals.validation, ...splitList(overrides.validation)];
  const risks = signals.risks;
  const handoff = handoffItems({
    decisions: signals.decisions,
    validation,
    risks,
    files,
    subject,
  });
  const preview = {
    intent: await redact(root, intent),
    summary: await redactList(root, summary),
    decisions: await redactList(root, signals.decisions),
    files,
    validation: await redactList(root, validation),
    risks: await redactList(root, risks),
    handoff: await redactList(root, handoff),
  };
  const lines = [
    "# Trace Memory",
    "",
    `Schema: \`${MEMORY_VERSION}\``,
    `Commit: \`${sha}\``,
    `Session: \`${sessionId ?? "none"}\``,
    `Created: \`${now()}\``,
    `Subject: ${await redact(root, subject)}`,
    "",
    "## Intent",
    "",
    await redact(root, intent || "Not recorded."),
    "",
    "## Summary",
    "",
    ...bulletLines(preview.summary, "No useful summary recorded."),
    "",
    "## Decisions",
    "",
    ...bulletLines(preview.decisions, "Not recorded."),
    "",
    "## Files",
    "",
    ...fileLines(files),
    "",
    "## Validation",
    "",
    ...bulletLines(preview.validation, "Not recorded."),
    "",
    "## Risks",
    "",
    ...bulletLines(preview.risks, "No known open risks recorded."),
    "",
    "## Handoff",
    "",
    ...bulletLines(preview.handoff, "Review this memory and the commit diff before changing related code."),
    "",
  ];
  return { source, preview, markdown: `${lines.join("\n").trimEnd()}\n` };
}

function memorySignals(events) {
  const signals = {
    intent: "",
    summary: [],
    decisions: [],
    validation: [],
    risks: [],
  };

  for (const event of events) {
    const message = normalizeText(event.message);
    if (!message) {
      continue;
    }
    if (!signals.intent && (event.event === "prompt" || event.role === "user")) {
      signals.intent = firstLine(message);
    }
    if (event.event === "response" || event.event === "tool" || event.event === "note") {
      signals.summary.push(firstLine(message));
    }
    if (event.event === "decision") {
      signals.decisions.push(message);
    }
    if (event.event === "validation") {
      signals.validation.push(message);
    }
    if (event.event === "risk") {
      signals.risks.push(message);
    }
    for (const item of labeledSignals(message)) {
      signals[item.key].push(item.value);
    }
  }

  return {
    intent: signals.intent,
    summary: compactItems(signals.summary),
    decisions: compactItems(signals.decisions),
    validation: compactItems(signals.validation),
    risks: compactItems(signals.risks),
  };
}

function labeledSignals(message) {
  const items = [];
  for (const rawLine of String(message ?? "").split(/\r?\n/)) {
    const line = rawLine.trim().replace(/^[-*]\s+/, "");
    const match = line.match(/^(decision|decisions|validation|validated|test|tests|risk|risks)\s*[:\-]\s*(.+)$/iu);
    if (!match) {
      continue;
    }
    const label = match[1].toLowerCase();
    const key = label.startsWith("decision")
      ? "decisions"
      : ["validation", "validated", "test", "tests"].includes(label)
        ? "validation"
        : "risks";
    items.push({ key, value: match[2].trim() });
  }
  return items;
}

async function commitDiffSummary(root, sha) {
  const stat = await git(["show", "--stat", "--oneline", "--format=", sha], { cwd: root });
  const lines = stat.split("\n").map((line) => line.trim()).filter(Boolean);
  return compactItems(lines.length > 0 ? lines : [`Commit ${sha.slice(0, 12)} changed repository files.`]);
}

function handoffItems({ decisions, validation, risks, files, subject }) {
  const items = [];
  if (decisions.length > 0) {
    items.push(`Preserve the decision: ${firstLine(decisions[0])}`);
  }
  if (validation.length > 0) {
    items.push(`Last known validation: ${firstLine(validation[0])}`);
  }
  if (risks.length > 0) {
    items.push(`Recheck risk: ${firstLine(risks[0])}`);
  }
  if (decisions.length === 0 && validation.length === 0 && risks.length === 0) {
    items.push(`Review the diff for "${subject}" before changing related code.`);
  }
  if (files.length > 0) {
    items.push(`Relevant files: ${files.slice(0, 5).join(", ")}`);
  }
  if (items.length === 0) {
    items.push(`Review the diff for "${subject}" before changing related code.`);
  }
  return items;
}

async function writeOrPrint(content, payload) {
  if (!payload.output) {
    process.stdout.write(content);
    return;
  }
  const outputPath = resolve(payload.output);
  await mkdir(dirname(outputPath), { recursive: true });
  await writeFile(outputPath, content);
  print({
    ok: true,
    ...payload,
    output: outputPath,
    bytes: Buffer.byteLength(content),
  });
}

async function memoryEntries(root) {
  const entries = [];
  for (const file of await listMemoryFiles(root)) {
    const content = await readFile(file, "utf8");
    const detail = memoryDetail(root, file, content).memory;
    entries.push({
      ...detail,
      text: content,
      file: relativePath(root, file),
      snippet: "",
      score: 0,
    });
  }
  return entries;
}

function memoryDetail(root, file, content) {
  const commit = content.match(/^Commit: `([^`]+)`/m)?.[1] ?? "";
  return {
    ok: true,
    schema_version: "trace.memory_detail.v1",
    memory: {
      commit,
      memory: relativePath(root, file),
      session: content.match(/^Session: `([^`]+)`/m)?.[1] ?? "none",
      subject: content.match(/^Subject: (.+)$/m)?.[1] ?? "",
      intent: section(content, "Intent").trim(),
      summary: sectionItems(content, "Summary"),
      decisions: sectionItems(content, "Decisions"),
      files: sectionItems(content, "Files").map((fileItem) => fileItem.replace(/^`|`$/g, "")),
      validation: sectionItems(content, "Validation"),
      risks: sectionItems(content, "Risks"),
      handoff: sectionItems(content, "Handoff"),
    },
  };
}

function rankMemoryMatches(entries, terms, field, files = []) {
  return entries
    .map((entry) => {
      const fieldText = searchFieldText(entry, field);
      const fileScore = files.length === 0 ? 0 : files.filter((file) => entry.files.some((memoryFile) => memoryFile.includes(file))).length * 5;
      const textScore = terms.length === 0 ? 0 : terms.reduce((score, term) => score + countTermOccurrences(fieldText, term), 0);
      const score = fileScore + textScore;
      return { ...entry, score, snippet: snippet(fieldText, terms[0] ?? files[0] ?? "") };
    })
    .filter((entry) => terms.length === 0 && files.length === 0 ? true : entry.score > 0)
    .sort((left, right) => right.score - left.score || right.commit.localeCompare(left.commit));
}

function renderSearch(matches) {
  return matches.map((match) => `${match.commit.slice(0, 12)} ${match.file} score=${match.score} ${match.snippet}`).join("\n") + (matches.length ? "\n" : "");
}

function renderRecall(payload) {
  const lines = [
    "# Trace Recall",
    "",
    `Query: \`${payload.query || "changed files"}\``,
    `Field: \`${payload.field}\``,
  ];
  if (payload.files.length > 0) {
    lines.push(`Files: ${payload.files.map((file) => `\`${file}\``).join(", ")}`);
  }
  lines.push(`Matches: ${payload.matches}`, "");

  if (payload.results.length === 0) {
    lines.push("No matching Trace memories found.");
    return `${lines.join("\n").trimEnd()}\n`;
  }

  for (const result of payload.results) {
    lines.push(`## ${result.commit.slice(0, 12)}`, "", `Memory: \`${result.file}\``, `Score: ${result.score}`, "", "### Intent", "", result.intent || "Not recorded.");
    appendRecallSection(lines, "Summary", result.summary);
    appendRecallSection(lines, "Decisions", result.decisions);
    appendRecallSection(lines, "Files", result.files.map((file) => `\`${file}\``));
    appendRecallSection(lines, "Validation", result.validation);
    appendRecallSection(lines, "Risks", result.risks);
    appendRecallSection(lines, "Handoff", result.handoff);
  }
  return `${lines.join("\n").trimEnd()}\n`;
}

function appendRecallSection(lines, name, values) {
  lines.push("", `### ${name}`, "");
  lines.push(...bulletLines(values, name === "Risks" ? "No known open risks recorded." : "Not recorded."));
}

async function appendEvent(root, input) {
  await ensureTrace(root);
  const event = await previewEvent(root, input);
  const file = await sessionPath(root, event.session_id);
  await mkdir(dirname(file), { recursive: true });
  await writeFile(file, `${JSON.stringify(event)}\n`, { flag: "a" });
  await writeFile(await currentSessionPath(root), event.session_id);
  return event;
}

async function previewEvent(root, input) {
  return {
    schema_version: "trace.event.v1",
    session_id: input.sessionId ? validateSessionId(input.sessionId) : await readCurrentSession(root).catch(() => newSessionId()),
    created_at: now(),
    event: canonicalEvent(input.event),
    role: input.role ?? inferRole(input.event),
    source: input.source ?? "manual",
    adapter: input.adapter,
    message: await redact(root, normalizeText(input.message)),
  };
}

function normalizeAgentPayload(adapter, explicitEvent, payload, raw) {
  const events = [];
  const sessionId = payload?.session_id ?? payload?.sessionId ?? payload?.conversation_id ?? payload?.cwd_session;
  const push = (event, message, role = inferRole(event)) => {
    if (message) {
      events.push({ sessionId, event, role, source: adapter, adapter, message });
    }
  };
  const event = canonicalEvent(explicitEvent ?? agentEventHint(adapter, payload));

  if (payload && typeof payload === "object" && !Array.isArray(payload)) {
    for (const [key, eventName] of Object.entries({
      prompts: "prompt",
      responses: "response",
      tools: "tool",
      decisions: "decision",
      validations: "validation",
      risks: "risk",
      notes: "note",
    })) {
      for (const value of splitStructuredValues(payload[key])) {
        push(eventName, value);
      }
    }
    if (events.length > 0) {
      return events;
    }
  }

  push(event, agentMessage(adapter, event, payload, raw));
  return events;
}

function agentEventHint(adapter, payload) {
  const hook = String(payload?.hook_event_name ?? payload?.event ?? payload?.type ?? payload?.kind ?? "").toLowerCase();
  if (payload?.prompt) {
    return "prompt";
  }
  if (hook.includes("userprompt") || hook.includes("prompt")) {
    return "prompt";
  }
  if (hook.includes("tool")) {
    return "tool";
  }
  if (hook.includes("stop") || hook.includes("response") || hook.includes("assistant")) {
    return "response";
  }
  return adapter === "claude-code" ? "note" : "response";
}

function agentMessage(adapter, event, payload, raw) {
  if (!payload || typeof payload !== "object" || Array.isArray(payload)) {
    return String(raw ?? payload ?? "");
  }
  if (event === "tool") {
    const tool = payload.tool_name ?? payload.tool ?? payload.name ?? payload.command ?? "tool";
    const result = payload.result ?? payload.output ?? payload.command_output ?? payload.response;
    return [tool, result].filter(Boolean).map(stringifyCompact).join(": ");
  }
  return payload.prompt
    ?? payload.message
    ?? payload.content
    ?? payload.response
    ?? payload.text
    ?? payload.summary
    ?? stringifyCompact(payload);
}

function parsePayloads(raw) {
  const trimmed = raw.trim();
  if (!trimmed) {
    return [""];
  }
  try {
    const parsed = JSON.parse(trimmed);
    return Array.isArray(parsed) ? parsed : [parsed];
  } catch {
    const lines = trimmed.split(/\r?\n/).filter(Boolean);
    if (lines.length > 1) {
      const parsed = [];
      for (const line of lines) {
        try {
          parsed.push(JSON.parse(line));
        } catch {
          return [raw];
        }
      }
      return parsed;
    }
    return [raw];
  }
}

async function runInstallCommand(action, values) {
  const installAction = args.install ? "install"
    : args.update ? "update"
      : args.uninstall ? "uninstall"
        : args.status ? "status"
          : action ?? "install";

  if (installAction === "status") {
    print(await installStatusPayload(values));
    return;
  }
  if (installAction === "install" || installAction === "update") {
    await writeInstallLink(installAction, values);
    return;
  }
  if (installAction === "uninstall") {
    await removeInstallLink(values);
    return;
  }
  fail(`unknown install command: ${installAction}`);
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

async function installHook(name, traceCommand) {
  const hooksDir = await gitHooksDir();
  await mkdir(hooksDir, { recursive: true });
  const file = join(hooksDir, name);
  const existing = await readFile(file, "utf8").catch(() => "#!/usr/bin/env sh\n");
  const content = `${stripManagedBlock(existing).trimEnd()}\n${HOOK_START}\n${traceCommand}\n${HOOK_END}\n`;
  await writeFile(file, content);
  await chmod(file, 0o755);
}

async function removeManagedBlock(file) {
  const content = await readFile(file, "utf8").catch(() => "");
  if (!content) {
    return;
  }
  await writeFile(file, stripManagedBlock(content));
}

function stripManagedBlock(content) {
  return content.replace(new RegExp(`\\n?${escapeRegExp(HOOK_START)}[\\s\\S]*?${escapeRegExp(HOOK_END)}\\n?`, "g"), "\n");
}

function traceHookCommand(name) {
  return `node ${shellQuote(fileURLToPath(import.meta.url))} hook ${name}${name === "post-commit" ? " >/dev/null 2>&1 || true" : ""}`;
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
  return (await readdir(dir, { withFileTypes: true }))
    .filter((entry) => entry.isFile() && entry.name.endsWith(".md"))
    .map((entry) => join(dir, entry.name))
    .sort();
}

async function listSessionFiles(root) {
  const dir = join(await gitCommonDir(root), "trace", "sessions");
  if (!await exists(dir)) {
    return [];
  }
  return (await readdir(dir, { withFileTypes: true }))
    .filter((entry) => entry.isFile() && entry.name.endsWith(".jsonl"))
    .map((entry) => join(dir, entry.name))
    .sort();
}

async function readSessionEvents(root, sessionId) {
  return readJsonl(await sessionPath(root, validateSessionId(sessionId)));
}

async function readJsonl(file) {
  const content = await readFile(file, "utf8");
  return content.split("\n").filter(Boolean).map((line) => JSON.parse(line));
}

async function currentSessionPath(root) {
  return join(await gitCommonDir(root), "trace", "current_session");
}

async function readCurrentSession(root) {
  return (await readFile(await currentSessionPath(root), "utf8")).trim();
}

async function sessionPath(root, sessionId) {
  return join(await gitCommonDir(root), "trace", "sessions", `${validateSessionId(sessionId)}.jsonl`);
}

async function stagedUnsafeTraceFiles(root) {
  const staged = (await git(["diff", "--cached", "--name-only", "--", TRACE_DIR], { cwd: root, allowFailure: true })).split("\n").filter(Boolean);
  return staged.filter(isUnsafeTracePath);
}

function isUnsafeTracePath(path) {
  return path.startsWith(".trace/sessions/")
    || path.startsWith(".trace/raw/")
    || path.startsWith(".trace/checkpoints/")
    || path.endsWith(".jsonl");
}

async function changedFilesForRecall(root) {
  return (await git(["diff", "--name-only", "HEAD"], { cwd: root, allowFailure: true })).split("\n").filter(Boolean);
}

async function traceHookStatus() {
  return {
    preCommit: await managedHookStatus("pre-commit"),
    postCommit: await managedHookStatus("post-commit"),
  };
}

async function managedHookStatus(name) {
  const file = join(await gitHooksDir(), name);
  const content = await readFile(file, "utf8").catch(() => "");
  return content.includes(HOOK_START) && content.includes(`hook ${name}`);
}

async function gitHooksDir() {
  const root = await repoRoot();
  const hooksPath = await git(["config", "--get", "core.hooksPath"], { cwd: root, allowFailure: true });
  return hooksPath ? resolve(root, hooksPath) : join(await gitCommonDir(root), "hooks");
}

async function gitCommonDir(root) {
  const path = await git(["rev-parse", "--git-common-dir"], { cwd: root });
  return resolve(root, path);
}

async function repoRoot() {
  return git(["rev-parse", "--show-toplevel"]);
}

async function resolveCommit(commitish) {
  return git(["rev-parse", `${commitish}^{commit}`]);
}

async function git(gitArgs, options = {}) {
  const result = await run("git", gitArgs, options);
  if (result.exitCode !== 0) {
    if (options.allowFailure) {
      return "";
    }
    fail(result.stderr.trim() || `git ${gitArgs.join(" ")} failed`);
  }
  return result.stdout.trim();
}

async function run(commandName, commandArgs, options = {}) {
  return new Promise((resolveRun) => {
    const child = spawn(commandName, commandArgs, {
      cwd: options.cwd,
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
      cwd: options.cwd,
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
    child.on("close", (exitCode) => resolveRun({ exitCode, stdout, stderr }));
  });
}

async function readStdin() {
  const chunks = [];
  for await (const chunk of process.stdin) {
    chunks.push(chunk);
  }
  return Buffer.concat(chunks).toString("utf8");
}

async function redact(root, value) {
  let output = String(value ?? "");
  output = output.replace(/(authorization:\s*bearer\s+)[^\s]+/giu, "$1REDACTED");
  output = output.replace(/\b([A-Z][A-Z0-9_]*(?:TOKEN|SECRET|PASSWORD|API_KEY)|token|secret|password|api[_-]?key)\s*=\s*([^\s'"`]+)/giu, "$1=REDACTED");
  output = output.replace(/\b(?:sk|ghp|github_pat|xox[baprs])_[A-Za-z0-9_=-]{12,}/g, "REDACTED");
  output = output.replace(/\b[A-Za-z0-9+/=_-]{40,}\b/g, "REDACTED");
  return output;
}

async function redactList(root, values) {
  const redacted = [];
  for (const value of values) {
    redacted.push(await redact(root, value));
  }
  return redacted;
}

function memoryPathFor(root, sha) {
  return join(root, TRACE_DIR, "commits", `${sha}.md`);
}

function section(markdown, name) {
  const match = markdown.match(new RegExp(`^## ${escapeRegExp(name)}\\n\\n([\\s\\S]*?)(?=\\n## |\\n?$)`, "m"));
  return match?.[1]?.trim() ?? "";
}

function sectionItems(markdown, name) {
  return section(markdown, name).split("\n")
    .map((line) => line.trim().replace(/^-\s+/, ""))
    .filter(Boolean)
    .filter((line) => !["Not recorded.", "No useful summary recorded.", "No known open risks recorded."].includes(line));
}

function searchFieldText(entry, field) {
  if (field === "text") {
    return entry.text;
  }
  const value = entry[field];
  return Array.isArray(value) ? value.join("\n") : String(value ?? "");
}

function normalizeSearchField(value) {
  const field = String(value ?? "text").toLowerCase();
  const aliases = {
    text: "text",
    all: "text",
    intent: "intent",
    summary: "summary",
    decision: "decisions",
    decisions: "decisions",
    file: "files",
    files: "files",
    validation: "validation",
    risk: "risks",
    risks: "risks",
    handoff: "handoff",
    session: "session",
  };
  if (!aliases[field]) {
    fail(`unknown search field: ${value}`);
  }
  return aliases[field];
}

function queryTerms(query) {
  return String(query ?? "").toLowerCase().split(/\s+/).filter(Boolean);
}

function countTermOccurrences(value, term) {
  if (!term) {
    return 0;
  }
  return (String(value ?? "").toLowerCase().match(new RegExp(escapeRegExp(term), "g")) ?? []).length;
}

function snippet(content, term) {
  const text = normalizeText(content);
  if (!term) {
    return firstLine(text).slice(0, 160);
  }
  const index = text.toLowerCase().indexOf(term.toLowerCase());
  if (index < 0) {
    return firstLine(text).slice(0, 160);
  }
  return text.slice(Math.max(0, index - 60), index + 120).trim();
}

function bulletLines(values, fallback) {
  if (!values || values.length === 0) {
    return [`- ${fallback}`];
  }
  return values.map((value) => `- ${truncate(value)}`);
}

function fileLines(files) {
  if (files.length === 0) {
    return ["- No files recorded."];
  }
  return files.map((file) => `- \`${file}\``);
}

function compactItems(values) {
  const seen = new Set();
  const items = [];
  for (const value of values.map(normalizeText).filter(Boolean)) {
    const key = value.toLowerCase();
    if (seen.has(key)) {
      continue;
    }
    seen.add(key);
    items.push(value);
  }
  return items.slice(0, 5);
}

function compactCommandOutput(result) {
  const parts = [];
  const stdout = normalizeText(result.stdout);
  const stderr = normalizeText(result.stderr);
  if (stdout) {
    parts.push(`stdout: ${stdout.slice(-500)}`);
  }
  if (stderr) {
    parts.push(`stderr: ${stderr.slice(-500)}`);
  }
  return parts.join("\n");
}

function normalizeText(value) {
  return String(value ?? "").replace(/\s+/g, " ").trim();
}

function truncate(value) {
  const text = normalizeText(value);
  return text.length > 240 ? `${text.slice(0, 237)}...` : text;
}

function splitStructuredValues(value) {
  if (value == null) {
    return [];
  }
  if (Array.isArray(value)) {
    return value.map(stringifyCompact);
  }
  return [stringifyCompact(value)];
}

function stringifyCompact(value) {
  return typeof value === "string" ? value : JSON.stringify(value);
}

function splitList(value) {
  if (!value) {
    return [];
  }
  return String(value).split(",").map((item) => item.trim()).filter(Boolean);
}

function positionalValues(values) {
  const positional = [];
  for (let index = 0; index < values.length; index += 1) {
    const value = values[index];
    if (value === "--") {
      positional.push(...values.slice(index + 1));
      break;
    }
    if (value.startsWith("--")) {
      if (!["--json", "--help", "--dry-run"].includes(value)) {
        index += 1;
      }
      continue;
    }
    positional.push(value);
  }
  return positional;
}

function parsePositiveInteger(value, label) {
  const parsed = Number.parseInt(value, 10);
  if (!Number.isInteger(parsed) || parsed < 1) {
    fail(`${label} must be a positive integer`);
  }
  return parsed;
}

function canonicalEvent(value) {
  const event = String(value ?? "note").toLowerCase().replaceAll("_", "-");
  const aliases = {
    user: "prompt",
    assistant: "response",
    model: "response",
    command: "tool",
    test: "validation",
    validated: "validation",
  };
  const canonical = aliases[event] ?? event;
  if (!EVENTS.includes(canonical)) {
    fail(`unsupported event ${value}: expected ${EVENTS.join(", ")}`);
  }
  return canonical;
}

function normalizeAdapter(value) {
  const adapter = String(value ?? "codex").toLowerCase();
  if (!["codex", "claude-code"].includes(adapter)) {
    fail(`unsupported adapter ${adapter}: expected codex or claude-code`);
  }
  return adapter;
}

function inferRole(event) {
  const canonical = canonicalEvent(event);
  if (canonical === "prompt") {
    return "user";
  }
  if (canonical === "tool" || canonical === "validation" || canonical === "risk") {
    return "tool";
  }
  return "agent";
}

function validateSessionId(sessionId) {
  if (!/^[A-Za-z0-9._-]+$/.test(String(sessionId ?? ""))) {
    fail("session id may only contain letters, numbers, dot, underscore, and dash");
  }
  return String(sessionId);
}

function newSessionId() {
  return `session-${randomBytes(6).toString("hex")}`;
}

function firstLine(value) {
  return String(value ?? "").split(/\r?\n/).find((line) => line.trim())?.trim() ?? "";
}

function relativePath(root, path) {
  return path.startsWith(root) ? path.slice(root.length + 1) : path;
}

function now() {
  return process.env.TRACE_NOW ?? new Date().toISOString();
}

function print(payload) {
  process.stdout.write(`${JSON.stringify(payload, null, 2)}\n`);
}

function printHelp() {
  process.stdout.write(`Trace records compact commit memory for future agents.

Usage:
  trace init
  trace enable
  trace capture --event prompt --message "why this change exists"
  trace hook agent --adapter codex
  trace hook agent --adapter claude-code
  trace record [commit]
  trace show [commit]
  trace search "query"
  trace recall "query"

Core loop:
  conversation + diff -> .trace/commits/<sha>.md -> show/search/recall
`);
}

function fail(message) {
  process.stderr.write(`trace: ${message}\n`);
  process.exit(1);
}

async function writeFileIfMissing(path, content) {
  try {
    await access(path, fsConstants.F_OK);
  } catch {
    await mkdir(dirname(path), { recursive: true });
    await writeFile(path, content);
  }
}

async function exists(path) {
  try {
    await access(path, fsConstants.F_OK);
    return true;
  } catch {
    return false;
  }
}

function shellQuote(value) {
  return `'${String(value).replaceAll("'", "'\\''")}'`;
}

function escapeRegExp(value) {
  return String(value).replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}
