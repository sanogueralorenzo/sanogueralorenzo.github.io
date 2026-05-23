import test from "node:test";
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";

const repoRoot = resolve(import.meta.dirname, "../..");
const cliPath = join(repoRoot, "trace/bin/trace.mjs");
const fixedEnv = { ...process.env, TRACE_NOW: "2026-05-23T00:00:00.000Z" };

test("record writes commit-scoped memory and supports show/search/summary", async () => {
  const repo = await tempRepo();

  try {
    await git(repo, ["config", "user.name", "Trace Test"]);
    await git(repo, ["config", "user.email", "trace@example.com"]);
    await writeFile(join(repo, "app.txt"), "hello\n");
    await git(repo, ["add", "app.txt"]);
    await git(repo, ["commit", "-m", "Add app text"]);

    await runTrace(repo, ["init"]);
    const capture = JSON.parse((await runTrace(repo, ["capture", "--event", "prompt", "--role", "user", "--message", "remember why app text exists"])).stdout);
    assert.equal(capture.schema_version, "trace.capture_result.v1");
    assert.match(capture.session, /^[A-Za-z0-9-]+$/);
    assert.equal(capture.event, "prompt");
    assert.equal(capture.source, "manual");
    await runTrace(repo, ["capture", "--event", "response", "--role", "assistant", "--message", "created a minimal text fixture"]);
    await runTrace(repo, ["capture", "--event", "tool", "--message", "git commit wrote app.txt"]);
    await runTrace(repo, ["capture", "--event", "decision", "--message", "Use committed Markdown for reviewable memory"]);

    const strictDryRun = await runTraceAllowFailure(repo, ["record", "--dry-run", "--check-session", "--strict", "--validation", "node --test"]);
    assert.equal(strictDryRun.exitCode, 1);
    const strictDryRunPayload = JSON.parse(strictDryRun.stdout);
    assert.equal(strictDryRunPayload.schema_version, "trace.session_check.v1");
    assert.equal(strictDryRunPayload.strict, true);
    assert.equal(strictDryRunPayload.ok, false);
    assert.equal(strictDryRunPayload.checks.find((check) => check.name === "validation").ok, false);

    const dryRun = JSON.parse((await runTrace(repo, ["record", "--dry-run", "--check-session", "--validation", "node --test"])).stdout);
    assert.equal(dryRun.ok, true);
    assert.equal(dryRun.schema_version, "trace.record_result.v1");
    assert.equal(dryRun.dryRun, true);
    assert.match(dryRun.memory, /^\.trace\/commits\/[0-9a-f]{2}\//);
    assert.equal(dryRun.sessionCheck.ok, true);
    assert.match(dryRun.markdown, /## Handoff\n\n- Preserve the decision: Use committed Markdown for reviewable memory/);
    assert.equal(dryRun.memoryPreview.schema_version, "trace.record_memory_preview.v1");
    assert.equal(dryRun.memoryPreview.intent, "remember why app text exists");
    assert.deepEqual(dryRun.memoryPreview.decisions, ["Use committed Markdown for reviewable memory"]);
    assert.deepEqual(dryRun.memoryPreview.validation, ["node --test"]);
    assert.match(dryRun.memoryPreview.handoff[0], /Preserve the decision/);
    assert.equal(dryRun.checkpointPreview.schema_version, "trace.record_checkpoint_preview.v1");
    assert.equal(dryRun.checkpointPreview.ref, "refs/trace/checkpoints");
    assert.match(dryRun.checkpointPreview.path, /^checkpoints\/[0-9a-f]+\.json$/);
    assert.equal(dryRun.checkpointPreview.events, 4);
    assert.equal(dryRun.checkpointPreview.integrity, true);
    assert.match(dryRun.checkpointPreview.payload_sha256, /^[0-9a-f]{64}$/);
    const missingDryRunMemory = await runTraceAllowFailure(repo, ["show", "HEAD"]);
    assert.equal(missingDryRunMemory.exitCode, 1);
    const missingDryRunCheckpoint = await run(repo, ["git", "rev-parse", "--verify", "refs/trace/checkpoints"], fixedEnv);
    assert.notEqual(missingDryRunCheckpoint.exitCode, 0);

    const record = await runTrace(repo, ["record", "--check-session", "--validation", "node --test"]);
    const payload = JSON.parse(record.stdout);

    assert.equal(payload.ok, true);
    assert.equal(payload.schema_version, "trace.record_result.v1");
    assert.match(payload.memory, /^\.trace\/commits\/[0-9a-f]{2}\//);
    assert.equal(payload.sessionCheck.ok, true);
    assert.equal(payload.memoryPreview.schema_version, "trace.record_memory_preview.v1");
    assert.equal(payload.memoryPreview.intent, "remember why app text exists");
    assert.deepEqual(payload.memoryPreview.validation, ["node --test"]);
    assert.equal(payload.checkpointPreview.schema_version, "trace.record_checkpoint_preview.v1");
    assert.equal(payload.checkpointPreview.integrity, true);
    assert.equal(payload.checkpointPreview.checkpoint_id, payload.checkpoint);

    const strictMemoryCi = JSON.parse((await runTrace(repo, ["ci", "HEAD", "--strict-memory"])).stdout);
    assert.equal(strictMemoryCi.ok, true);
    assert.equal(strictMemoryCi.memoryQuality.ok, true);
    assert.equal(strictMemoryCi.memoryQuality.checked, 1);
    assert.deepEqual(strictMemoryCi.memoryQuality.findings, []);

    const show = await runTrace(repo, ["show", "HEAD"]);
    assert.match(show.stdout, /remember why app text exists/);
    assert.match(show.stdout, /Use committed Markdown/);
    assert.match(show.stdout, /## Responses\n\n- created a minimal text fixture/);
    assert.match(show.stdout, /## Tool Activity\n\n- git commit wrote app.txt/);
    assert.match(show.stdout, /node --test/);
    assert.match(show.stdout, /## Handoff\n\n- Preserve the decision: Use committed Markdown for reviewable memory/);
    assert.match(show.stdout, /- Last known validation: node --test/);
    assert.match(show.stdout, /- Relevant files: app.txt/);

    const showJson = JSON.parse((await runTrace(repo, ["show", "HEAD", "--json"])).stdout);
    assert.equal(showJson.schema_version, "trace.memory_detail.v1");
    assert.equal(showJson.memory.commit, payload.commit);
    assert.equal(showJson.memory.memory, payload.memory);
    assert.equal(showJson.memory.intent, "remember why app text exists");
    assert.deepEqual(showJson.memory.lifecycle, ["total: 4", "prompt: 1", "response: 1", "tool: 1", "decision: 1"]);
    assert.deepEqual(showJson.memory.summary, ["created a minimal text fixture", "git commit wrote app.txt"]);
    assert.deepEqual(showJson.memory.decisions, ["Use committed Markdown for reviewable memory"]);
    assert.deepEqual(showJson.memory.responses, ["created a minimal text fixture"]);
    assert.deepEqual(showJson.memory.tools, ["git commit wrote app.txt"]);
    assert.deepEqual(showJson.memory.files, ["app.txt"]);
    assert.deepEqual(showJson.memory.validation, ["node --test"]);
    assert.match(showJson.memory.handoff[0], /Preserve the decision/);
    assert.match(showJson.memory.checkpoint, /^[0-9a-f]+$/);
    assert.match(showJson.memory.session, /^[A-Za-z0-9-]+$/);

    const showPath = join(repo, "trace-show.md");
    const showWrite = JSON.parse((await runTrace(repo, ["show", "HEAD", "--output", showPath])).stdout);
    assert.equal(showWrite.schema_version, "trace.show_output.v1");
    assert.equal(showWrite.commit, payload.commit);
    assert.equal(showWrite.output, showPath);
    assert.equal(showWrite.bytes, (await readFile(showPath, "utf8")).length);
    assert.match(await readFile(showPath, "utf8"), /Use committed Markdown for reviewable memory/);

    const showJsonPath = join(repo, "trace-show.json");
    const showJsonWrite = JSON.parse((await runTrace(repo, ["show", "HEAD", "--json", "--output", showJsonPath])).stdout);
    assert.equal(showJsonWrite.schema_version, "trace.show_output.v1");
    const showJsonFile = JSON.parse(await readFile(showJsonPath, "utf8"));
    assert.equal(showJsonFile.schema_version, "trace.memory_detail.v1");
    assert.equal(showJsonFile.memory.commit, payload.commit);

    const search = await runTrace(repo, ["search", "reviewable"]);
    assert.match(search.stdout, /\.trace\/commits\//);

    const searchJson = JSON.parse((await runTrace(repo, ["search", "--field", "decisions", "--limit", "1", "--json", "reviewable"])).stdout);
    assert.equal(searchJson.schema_version, "trace.search_results.v1");
    assert.equal(searchJson.query, "reviewable");
    assert.equal(searchJson.field, "decisions");
    assert.equal(searchJson.matches, 1);
    assert.equal(searchJson.results[0].sha.length, 40);
    assert.match(searchJson.results[0].checkpoint, /^[0-9a-f]+$/);
    assert.match(searchJson.results[0].session, /^[A-Za-z0-9-]+$/);
    assert.equal(searchJson.results[0].file, payload.memory);
    assert.match(searchJson.results[0].snippet, /reviewable/);

    const searchPath = join(repo, "trace-search.txt");
    const searchWrite = JSON.parse((await runTrace(repo, ["search", "--field", "decisions", "--limit", "1", "--output", searchPath, "reviewable"])).stdout);
    assert.equal(searchWrite.schema_version, "trace.search_output.v1");
    assert.equal(searchWrite.output, searchPath);
    assert.equal(searchWrite.matches, 1);
    assert.equal(searchWrite.bytes, (await readFile(searchPath, "utf8")).length);
    assert.match(await readFile(searchPath, "utf8"), /reviewable/);

    const searchJsonPath = join(repo, "trace-search.json");
    const searchJsonWrite = JSON.parse((await runTrace(repo, ["search", "--field", "decisions", "--limit", "1", "--json", "--output", searchJsonPath, "reviewable"])).stdout);
    assert.equal(searchJsonWrite.schema_version, "trace.search_output.v1");
    const searchJsonFile = JSON.parse(await readFile(searchJsonPath, "utf8"));
    assert.equal(searchJsonFile.schema_version, "trace.search_results.v1");
    assert.equal(searchJsonFile.matches, 1);

    const commonDir = (await git(repo, ["rev-parse", "--git-common-dir"])).stdout.trim();
    const indexed = JSON.parse((await runTrace(repo, ["index"])).stdout);
    assert.equal(indexed.ok, true);
    assert.equal(indexed.entries, 1);
    assert.equal(indexed.path, `${commonDir}/trace/index.json`);
    const index = JSON.parse(await readFile(join(repo, commonDir, "trace/index.json"), "utf8"));
    assert.equal(index.schema_version, "trace.search_index.v1");
    assert.match(index.entries[0].checkpoint, /^[0-9a-f]+$/);
    assert.match(index.entries[0].session, /^[A-Za-z0-9-]+$/);
    assert.equal(index.entries[0].decisions, "- Use committed Markdown for reviewable memory");
    assert.equal(index.entries[0].lifecycle, "- total: 4\n- prompt: 1\n- response: 1\n- tool: 1\n- decision: 1");

    const decisionSearch = await runTrace(repo, ["search", "--field", "decisions", "reviewable"]);
    assert.match(decisionSearch.stdout, /\.trace\/commits\//);
    const intentSearch = JSON.parse((await runTrace(repo, ["search", "--field", "intent", "--json", "exists"])).stdout);
    assert.equal(intentSearch.field, "intent");
    assert.equal(intentSearch.matches, 1);
    assert.match(intentSearch.results[0].snippet, /remember why app text exists/);
    const summarySearch = JSON.parse((await runTrace(repo, ["search", "--field", "summary", "--json", "fixture"])).stdout);
    assert.equal(summarySearch.field, "summary");
    assert.equal(summarySearch.matches, 1);
    const lifecycleSearch = JSON.parse((await runTrace(repo, ["search", "--field", "lifecycle", "--json", "decision"])).stdout);
    assert.equal(lifecycleSearch.field, "lifecycle");
    assert.equal(lifecycleSearch.matches, 1);
    assert.match(lifecycleSearch.results[0].snippet, /decision: 1/);
    const toolSearch = JSON.parse((await runTrace(repo, ["search", "--field", "tools", "--json", "commit"])).stdout);
    assert.equal(toolSearch.field, "tools");
    assert.equal(toolSearch.matches, 1);
    const fileSearch = await runTrace(repo, ["search", "--field", "files", "app.txt"]);
    assert.match(fileSearch.stdout, /app.txt/);
    const validationSearch = JSON.parse((await runTrace(repo, ["search", "--field", "validation", "--json", "node"])).stdout);
    assert.equal(validationSearch.field, "validation");
    assert.equal(validationSearch.matches, 1);
    const handoffSearch = JSON.parse((await runTrace(repo, ["search", "--field", "handoff", "--json", "preserve"])).stdout);
    assert.equal(handoffSearch.field, "handoff");
    assert.equal(handoffSearch.matches, 1);
    assert.match(handoffSearch.results[0].snippet, /Preserve the decision/);
    const checkpointSearch = JSON.parse((await runTrace(repo, ["search", "--field", "checkpoint", "--json", payload.checkpoint])).stdout);
    assert.equal(checkpointSearch.field, "checkpoint");
    assert.equal(checkpointSearch.matches, 1);
    assert.equal(checkpointSearch.results[0].checkpoint, payload.checkpoint);
    const sessionSearch = JSON.parse((await runTrace(repo, ["search", "--field", "session", "--json", payload.session])).stdout);
    assert.equal(sessionSearch.field, "session");
    assert.equal(sessionSearch.matches, 1);
    assert.equal(sessionSearch.results[0].session, payload.session);
    const riskSearch = await runTrace(repo, ["search", "--field", "risks", "reviewable"]);
    assert.equal(riskSearch.stdout, "");

    const recall = await runTrace(repo, ["recall", "reviewable", "--limit", "1"]);
    assert.match(recall.stdout, /Trace Recall/);
    assert.match(recall.stdout, /Matches: 1/);
    assert.match(recall.stdout, /Checkpoint: `[0-9a-f]+`/);
    assert.match(recall.stdout, /Session: `[A-Za-z0-9-]+`/);
    assert.match(recall.stdout, /Use committed Markdown for reviewable memory/);
    assert.match(recall.stdout, /### Tool Activity\n\n- git commit wrote app.txt/);
    assert.match(recall.stdout, /### Files\n\n- `app.txt`/);
    assert.match(recall.stdout, /node --test/);

    const recallJson = JSON.parse((await runTrace(repo, ["recall", "reviewable", "--limit", "1", "--json"])).stdout);
    assert.equal(recallJson.schema_version, "trace.recall.v1");
    assert.equal(recallJson.query, "reviewable");
    assert.equal(recallJson.field, "text");
    assert.equal(recallJson.matches, 1);
    assert.equal(recallJson.results[0].score, 3);
    assert.equal(recallJson.results[0].file, payload.memory);
    assert.match(recallJson.results[0].checkpoint, /^[0-9a-f]+$/);
    assert.match(recallJson.results[0].session, /^[A-Za-z0-9-]+$/);
    assert.match(recallJson.results[0].lifecycle, /decision: 1/);
    assert.match(recallJson.results[0].decisions, /Use committed Markdown/);
    assert.match(recallJson.results[0].responses, /created a minimal text fixture/);
    assert.match(recallJson.results[0].tools, /git commit wrote app.txt/);
    assert.match(recallJson.results[0].files, /app.txt/);
    assert.match(recallJson.results[0].validation, /node --test/);
    assert.match(recallJson.results[0].handoff, /Preserve the decision/);

    const recallPath = join(repo, "trace-recall.md");
    const recallWrite = JSON.parse((await runTrace(repo, ["recall", "reviewable", "--limit", "1", "--output", recallPath])).stdout);
    assert.equal(recallWrite.schema_version, "trace.recall_output.v1");
    assert.equal(recallWrite.output, recallPath);
    assert.equal(recallWrite.matches, 1);
    assert.equal(recallWrite.bytes, (await readFile(recallPath, "utf8")).length);
    assert.match(await readFile(recallPath, "utf8"), /# Trace Recall/);
    assert.match(await readFile(recallPath, "utf8"), /Use committed Markdown for reviewable memory/);

    const recallJsonPath = join(repo, "trace-recall.json");
    const recallJsonWrite = JSON.parse((await runTrace(repo, ["recall", "reviewable", "--limit", "1", "--json", "--output", recallJsonPath])).stdout);
    assert.equal(recallJsonWrite.schema_version, "trace.recall_output.v1");
    const recallJsonFile = JSON.parse(await readFile(recallJsonPath, "utf8"));
    assert.equal(recallJsonFile.schema_version, "trace.recall.v1");
    assert.equal(recallJsonFile.matches, 1);

    const decisionRecall = await runTrace(repo, ["recall", "--field", "decisions", "reviewable", "--limit", "1"]);
    assert.match(decisionRecall.stdout, /Field: `decisions`/);
    assert.match(decisionRecall.stdout, /Use committed Markdown for reviewable memory/);
    const validationRecall = JSON.parse((await runTrace(repo, ["recall", "--field", "validation", "--json", "node"])).stdout);
    assert.equal(validationRecall.field, "validation");
    assert.equal(validationRecall.matches, 1);
    assert.match(validationRecall.results[0].validation, /node --test/);
    const riskRecall = JSON.parse((await runTrace(repo, ["recall", "--field", "risks", "--json", "reviewable"])).stdout);
    assert.equal(riskRecall.field, "risks");
    assert.equal(riskRecall.matches, 0);

    const checkpointRecall = JSON.parse((await runTrace(repo, ["recall", "--checkpoint", payload.checkpoint, "--json"])).stdout);
    assert.equal(checkpointRecall.checkpoint, payload.checkpoint);
    assert.equal(checkpointRecall.matches, 1);
    assert.equal(checkpointRecall.results[0].score, 10);
    assert.equal(checkpointRecall.results[0].file, payload.memory);

    const sessionRecall = await runTrace(repo, ["recall", "--session", payload.session, "--limit", "1"]);
    assert.match(sessionRecall.stdout, new RegExp(`Session Filter: \`${payload.session}\``));
    assert.match(sessionRecall.stdout, /remember why app text exists/);

    const sessionRecap = await runTrace(repo, ["session", "recap", payload.session, "--limit", "1"]);
    assert.match(sessionRecap.stdout, /Trace Session Recap/);
    assert.match(sessionRecap.stdout, /Commit Memory Events: 4/);
    assert.match(sessionRecap.stdout, /## Decisions\n\n- Use committed Markdown for reviewable memory/);
    assert.match(sessionRecap.stdout, /## Handoff\n\n- Preserve the decision: Use committed Markdown for reviewable memory/);

    const sessionRecapJson = JSON.parse((await runTrace(repo, ["session", "recap", payload.session, "--json"])).stdout);
    assert.equal(sessionRecapJson.schema_version, "trace.session_recap.v1");
    assert.equal(sessionRecapJson.field, "all");
    assert.equal(sessionRecapJson.session, payload.session);
    assert.equal(sessionRecapJson.events, 4);
    assert.equal(sessionRecapJson.commitMemoryEvents, 4);
    assert.deepEqual(sessionRecapJson.sections.agents, []);
    assert.deepEqual(sessionRecapJson.sections.lifecycle, ["total: 4", "prompt: 1", "response: 1", "tool: 1", "decision: 1"]);
    assert.deepEqual(sessionRecapJson.sections.prompts, ["remember why app text exists"]);
    assert.deepEqual(sessionRecapJson.sections.decisions, ["Use committed Markdown for reviewable memory"]);
    assert.deepEqual(sessionRecapJson.sections.handoff, ["Preserve the decision: Use committed Markdown for reviewable memory"]);

    const sessionRecapPath = join(repo, "trace-session-recap.md");
    const sessionRecapWrite = JSON.parse((await runTrace(repo, ["session", "recap", payload.session, "--field", "handoff", "--output", sessionRecapPath])).stdout);
    assert.equal(sessionRecapWrite.schema_version, "trace.session_recap_output.v1");
    assert.equal(sessionRecapWrite.session, payload.session);
    assert.equal(sessionRecapWrite.field, "handoff");
    assert.equal(sessionRecapWrite.output, sessionRecapPath);
    assert.equal(sessionRecapWrite.bytes, (await readFile(sessionRecapPath, "utf8")).length);
    assert.match(await readFile(sessionRecapPath, "utf8"), /# Trace Session Recap/);
    assert.match(await readFile(sessionRecapPath, "utf8"), /Preserve the decision: Use committed Markdown for reviewable memory/);

    const sessionRecapJsonPath = join(repo, "trace-session-recap.json");
    const sessionRecapJsonWrite = JSON.parse((await runTrace(repo, ["session", "recap", payload.session, "--json", "--output", sessionRecapJsonPath])).stdout);
    assert.equal(sessionRecapJsonWrite.schema_version, "trace.session_recap_output.v1");
    const sessionRecapJsonFile = JSON.parse(await readFile(sessionRecapJsonPath, "utf8"));
    assert.equal(sessionRecapJsonFile.schema_version, "trace.session_recap.v1");
    assert.equal(sessionRecapJsonFile.session, payload.session);

    const decisionRecap = await runTrace(repo, ["session", "recap", payload.session, "--field", "decisions", "--limit", "1"]);
    assert.match(decisionRecap.stdout, /Field: `decisions`/);
    assert.match(decisionRecap.stdout, /## Decisions\n\n- Use committed Markdown for reviewable memory/);
    assert.doesNotMatch(decisionRecap.stdout, /## Handoff/);
    const handoffRecapJson = JSON.parse((await runTrace(repo, ["session", "recap", payload.session, "--field", "handoff", "--json"])).stdout);
    assert.equal(handoffRecapJson.field, "handoff");
    assert.deepEqual(Object.keys(handoffRecapJson.sections), ["handoff"]);
    assert.deepEqual(handoffRecapJson.sections.handoff, ["Preserve the decision: Use committed Markdown for reviewable memory"]);

    const sessionCheck = JSON.parse((await runTrace(repo, ["session", "check", payload.session, "--json"])).stdout);
    assert.equal(sessionCheck.schema_version, "trace.session_check.v1");
    assert.equal(sessionCheck.ok, true);
    assert.equal(sessionCheck.strict, false);
    assert.equal(sessionCheck.commitMemoryEvents, 4);
    assert.equal(sessionCheck.checks.find((check) => check.name === "commitMemoryEvents").ok, true);
    assert.equal(sessionCheck.checks.find((check) => check.name === "validation").level, "warning");

    const strictSessionCheck = await runTraceAllowFailure(repo, ["session", "check", payload.session, "--strict", "--json"]);
    assert.equal(strictSessionCheck.exitCode, 1);
    const strictSessionCheckPayload = JSON.parse(strictSessionCheck.stdout);
    assert.equal(strictSessionCheckPayload.strict, true);
    assert.equal(strictSessionCheckPayload.ok, false);
    assert.equal(strictSessionCheckPayload.checks.find((check) => check.name === "validation").ok, false);

    const fileRecall = await runTrace(repo, ["recall", "--files", "app.txt"]);
    assert.match(fileRecall.stdout, /Files: `app.txt`/);
    assert.match(fileRecall.stdout, /remember why app text exists/);

    const memoryLog = await runTrace(repo, ["log"]);
    assert.match(memoryLog.stdout, new RegExp(`${payload.commit.slice(0, 12)} remember why app text exists`));
    const memoryLogJson = JSON.parse((await runTrace(repo, ["log", "--json", "--limit", "1"])).stdout);
    assert.equal(memoryLogJson.schema_version, "trace.memory_log.v1");
    assert.equal(memoryLogJson.limit, 1);
    assert.equal(memoryLogJson.memories.length, 1);
    assert.equal(memoryLogJson.memories[0].commit, payload.commit);
    assert.equal(memoryLogJson.memories[0].memory, payload.memory);
    assert.equal(memoryLogJson.memories[0].intent, "remember why app text exists");
    assert.deepEqual(memoryLogJson.memories[0].decisions, ["Use committed Markdown for reviewable memory"]);
    assert.deepEqual(memoryLogJson.memories[0].files, ["app.txt"]);
    assert.match(memoryLogJson.memories[0].checkpoint, /^[0-9a-f]+$/);
    assert.match(memoryLogJson.memories[0].session, /^[A-Za-z0-9-]+$/);

    const summary = await runTrace(repo, ["summary", "HEAD"]);
    assert.match(summary.stdout, /Trace Summary/);
    assert.match(summary.stdout, /remember why app text exists/);
    assert.match(summary.stdout, /## Handoff\n\n- Preserve the decision: Use committed Markdown for reviewable memory/);

    const summaryJson = JSON.parse((await runTrace(repo, ["summary", "HEAD", "--json"])).stdout);
    assert.equal(summaryJson.schema_version, "trace.summary.v1");
    assert.equal(summaryJson.kind, "range");
    assert.deepEqual(summaryJson.intent, ["remember why app text exists"]);
    assert.deepEqual(summaryJson.lifecycle, ["decision: 1", "prompt: 1", "response: 1", "tool: 1", "total: 4"]);
    assert.deepEqual(summaryJson.decisions, ["Use committed Markdown for reviewable memory"]);
    assert.deepEqual(summaryJson.files, ["app.txt"]);
    assert.deepEqual(summaryJson.validation, ["node --test"]);
    assert.match(summaryJson.handoff[0], /Preserve the decision/);
    assert.equal(summaryJson.commits[0].commit.length, 40);
    assert.match(summaryJson.commits[0].checkpoint, /^[0-9a-f]+$/);
    assert.match(summaryJson.commits[0].session, /^[A-Za-z0-9-]+$/);
    assert.equal(summaryJson.commits[0].memory, payload.memory);
    assert.deepEqual(summaryJson.commits[0].lifecycle, ["total: 4", "prompt: 1", "response: 1", "tool: 1", "decision: 1"]);
    assert.deepEqual(summaryJson.commits[0].files, ["app.txt"]);
    assert.deepEqual(summaryJson.commits[0].validation, ["node --test"]);
    assert.deepEqual(summaryJson.commits[0].decisions, ["Use committed Markdown for reviewable memory"]);
    assert.match(summaryJson.commits[0].handoff[0], /Preserve the decision/);

    const releaseNotes = await runTrace(repo, ["release-notes", "HEAD"]);
    assert.match(releaseNotes.stdout, /Trace Release Notes/);
    assert.match(releaseNotes.stdout, /## Highlights\n\n- created a minimal text fixture/);
    assert.match(releaseNotes.stdout, /## Changed Files\n\n- `app.txt`/);
    assert.match(releaseNotes.stdout, /## Validation\n\n- node --test/);
    assert.match(releaseNotes.stdout, /## Handoff\n\n- Preserve the decision: Use committed Markdown for reviewable memory/);

    const prBodyPath = join(repo, "trace-pr-body.md");
    const prBodyWrite = JSON.parse((await runTrace(repo, ["pr-body", "HEAD", "--output", prBodyPath])).stdout);
    assert.equal(prBodyWrite.schema_version, "trace.summary_output.v1");
    assert.equal(prBodyWrite.kind, "pr");
    assert.equal(prBodyWrite.output, prBodyPath);
    assert.equal(prBodyWrite.bytes, (await readFile(prBodyPath, "utf8")).length);
    assert.match(await readFile(prBodyPath, "utf8"), /# Trace PR Summary/);
    assert.match(await readFile(prBodyPath, "utf8"), /Use committed Markdown for reviewable memory/);

    const summaryJsonPath = join(repo, "trace-summary.json");
    const summaryJsonWrite = JSON.parse((await runTrace(repo, ["summary", "HEAD", "--json", "--output", summaryJsonPath])).stdout);
    assert.equal(summaryJsonWrite.schema_version, "trace.summary_output.v1");
    assert.equal(summaryJsonWrite.kind, "range");
    const summaryJsonFile = JSON.parse(await readFile(summaryJsonPath, "utf8"));
    assert.equal(summaryJsonFile.schema_version, "trace.summary.v1");
    assert.equal(summaryJsonFile.kind, "range");
    assert.deepEqual(summaryJsonFile.decisions, ["Use committed Markdown for reviewable memory"]);

    const ref = await git(repo, ["rev-parse", "--verify", "refs/trace/checkpoints"]);
    assert.match(ref.stdout.trim(), /^[0-9a-f]{40}$/);
  } finally {
    await rm(repo, { recursive: true, force: true });
  }
});

test("generic agent hook captures JSON payloads for PR summaries", async () => {
  const repo = await tempRepo();

  try {
    await git(repo, ["config", "user.name", "Trace Test"]);
    await git(repo, ["config", "user.email", "trace@example.com"]);
    await writeFile(join(repo, "service.txt"), "v1\n");
    await git(repo, ["add", "service.txt"]);
    await git(repo, ["commit", "-m", "Create service"]);
    await runTrace(repo, ["init"]);

    const promptCapture = JSON.parse((await runTraceWithInput(repo, ["hook", "agent", "prompt"], JSON.stringify({
      session_id: "session-json",
      agent: "codex",
      prompt: "add retry memory for service",
    }))).stdout);
    assert.equal(promptCapture.schema_version, "trace.agent_hook_result.v1");
    assert.equal(promptCapture.dryRun, false);
    assert.equal(promptCapture.session, "session-json");
    assert.equal(promptCapture.event, "prompt");
    await runTraceWithInput(repo, ["hook", "agent", "decision"], JSON.stringify({
      session_id: "session-json",
      agent: "codex",
      message: "Keep raw checkpoint data outside the project tree",
    }));
    await runTraceWithInput(repo, ["hook", "agent", "risk"], JSON.stringify({
      session_id: "session-json",
      agent: "codex",
      message: "token=super-secret-token should be redacted",
    }));

    await writeFile(join(repo, "service.txt"), "v2\n");
    await git(repo, ["add", "service.txt"]);
    await git(repo, ["commit", "-m", "Update service"]);
    await runTrace(repo, ["record", "--session", "session-json", "--validation", "npm --prefix trace test"]);

    const prBody = await runTrace(repo, ["pr-body", "HEAD"]);
    assert.match(prBody.stdout, /Trace PR Summary/);
    assert.match(prBody.stdout, /add retry memory for service/);
    assert.match(prBody.stdout, /## Agents\n\n- adapter: codex/);
    assert.match(prBody.stdout, /## Lifecycle\n\n- total: 3\n- prompt: 1\n- decision: 1\n- risk: 1/);
    assert.match(prBody.stdout, /Keep raw checkpoint data outside the project tree/);
    assert.match(prBody.stdout, /## Handoff\n\n- Preserve the decision: Keep raw checkpoint data outside the project tree/);
    assert.match(prBody.stdout, /token=REDACTED/);
    assert.doesNotMatch(prBody.stdout, /super-secret-token/);

    const prBodyJson = JSON.parse((await runTrace(repo, ["pr-body", "HEAD", "--json"])).stdout);
    assert.deepEqual(prBodyJson.agents, ["adapter: codex"]);
    assert.deepEqual(prBodyJson.lifecycle, ["decision: 1", "prompt: 1", "risk: 1", "total: 3"]);
    assert.deepEqual(prBodyJson.commits[0].agents, ["adapter: codex"]);
    assert.deepEqual(prBodyJson.commits[0].lifecycle, ["total: 3", "prompt: 1", "decision: 1", "risk: 1"]);

    const agentSearch = JSON.parse((await runTrace(repo, ["search", "--field", "agents", "--json", "codex"])).stdout);
    assert.equal(agentSearch.field, "agents");
    assert.equal(agentSearch.matches, 1);
    assert.match(agentSearch.results[0].snippet, /adapter: codex/);
    const lifecycleSearch = JSON.parse((await runTrace(repo, ["search", "--field", "lifecycle", "--json", "risk"])).stdout);
    assert.equal(lifecycleSearch.field, "lifecycle");
    assert.equal(lifecycleSearch.matches, 1);
    assert.match(lifecycleSearch.results[0].snippet, /risk: 1/);
  } finally {
    await rm(repo, { recursive: true, force: true });
  }
});

test("search ranks committed memories by term frequency", async () => {
  const repo = await tempRepo();

  try {
    await git(repo, ["config", "user.name", "Trace Test"]);
    await git(repo, ["config", "user.email", "trace@example.com"]);
    await runTrace(repo, ["init"]);

    await writeFile(join(repo, "low.txt"), "low\n");
    await git(repo, ["add", "low.txt"]);
    await git(repo, ["commit", "-m", "Add low search memory"]);
    await runTrace(repo, ["capture", "--session", "low-search", "--event", "prompt", "--message", "searchrank low context"]);
    const lowRecord = JSON.parse((await runTrace(repo, ["record", "--session", "low-search", "--validation", "node --test"])).stdout);
    await git(repo, ["add", ".trace"]);
    await git(repo, ["commit", "-m", "Commit low Trace memory"]);

    await writeFile(join(repo, "high.txt"), "high\n");
    await git(repo, ["add", "high.txt"]);
    await git(repo, ["commit", "-m", "Add high search memory"]);
    await runTrace(repo, ["capture", "--session", "high-search", "--event", "prompt", "--message", "searchrank searchrank high context"]);
    await runTrace(repo, ["capture", "--session", "high-search", "--event", "decision", "--message", "searchrank decision keeps ranking"]);
    const highRecord = JSON.parse((await runTrace(repo, ["record", "--session", "high-search", "--validation", "searchrank validation"])).stdout);
    await git(repo, ["add", ".trace"]);
    await git(repo, ["commit", "-m", "Commit high Trace memory"]);

    const ranked = JSON.parse((await runTrace(repo, ["search", "--json", "--limit", "2", "searchrank"])).stdout);
    assert.equal(ranked.matches, 2);
    assert.equal(ranked.results[0].file, highRecord.memory);
    assert.equal(ranked.results[1].file, lowRecord.memory);
    assert.ok(ranked.results[0].score > ranked.results[1].score);

    const text = await runTrace(repo, ["search", "--limit", "1", "searchrank"]);
    assert.match(text.stdout, /score=\d+/);
    assert.match(text.stdout, new RegExp(highRecord.commit.slice(0, 12)));
  } finally {
    await rm(repo, { recursive: true, force: true });
  }
});

test("record check-session blocks lifecycle-only memory", async () => {
  const repo = await tempRepo();

  try {
    await git(repo, ["config", "user.name", "Trace Test"]);
    await git(repo, ["config", "user.email", "trace@example.com"]);
    await writeFile(join(repo, "empty-session.txt"), "empty\n");
    await git(repo, ["add", "empty-session.txt"]);
    await git(repo, ["commit", "-m", "Add empty session target"]);

    await runTrace(repo, ["init"]);
    await runTrace(repo, ["session", "start", "lifecycle-only"]);

    const blocked = await runTraceAllowFailure(repo, ["record", "--check-session", "--dry-run", "--session", "lifecycle-only"]);
    assert.equal(blocked.exitCode, 1);
    const payload = JSON.parse(blocked.stdout);
    assert.equal(payload.schema_version, "trace.session_check.v1");
    assert.equal(payload.ok, false);
    assert.equal(payload.commitMemoryEvents, 0);
    assert.equal(payload.checks.find((check) => check.name === "commitMemoryEvents").level, "error");

    const missingMemory = await runTraceAllowFailure(repo, ["show", "HEAD"]);
    assert.equal(missingMemory.exitCode, 1);
    const missingCheckpoint = await run(repo, ["git", "rev-parse", "--verify", "refs/trace/checkpoints"], fixedEnv);
    assert.notEqual(missingCheckpoint.exitCode, 0);
  } finally {
    await rm(repo, { recursive: true, force: true });
  }
});

test("run captures command results as validation and risk events", async () => {
  const repo = await tempRepo();

  try {
    await git(repo, ["config", "user.name", "Trace Test"]);
    await git(repo, ["config", "user.email", "trace@example.com"]);
    await writeFile(join(repo, "run.txt"), "run\n");
    await git(repo, ["add", "run.txt"]);
    await git(repo, ["commit", "-m", "Add run file"]);
    await runTrace(repo, ["init"]);

    const passed = await runTrace(repo, ["run", "--", "node", "-e", "console.log('validation ok')"]);
    assert.match(passed.stdout, /validation ok/);

    const failed = await runTraceAllowFailure(repo, ["run", "--", "node", "-e", "process.exit(7)"]);
    assert.equal(failed.exitCode, 7);

    const commonDir = (await git(repo, ["rev-parse", "--git-common-dir"])).stdout.trim();
    const sessionId = (await readFile(join(repo, commonDir, "trace/current_session"), "utf8")).trim();
    const session = await readFile(join(repo, commonDir, `trace/sessions/${sessionId}.jsonl`), "utf8");
    const events = session.trim().split("\n").map((line) => JSON.parse(line));
    assert.deepEqual(events.map((event) => event.event), ["validation", "risk"]);
    assert.deepEqual(events.map((event) => event.source), ["trace-run", "trace-run"]);
    assert.match(events[0].message, /validation passed: 'node' '-e'/);
    assert.match(events[0].message, /stdout: validation ok/);
    assert.match(events[1].message, /risk failed exit 7: 'node' '-e'/);

    await runTrace(repo, ["record"]);
    const memory = (await runTrace(repo, ["show", "HEAD"])).stdout;
    assert.match(memory, /validation passed: 'node' '-e'/);
    assert.match(memory, /stdout: validation ok/);
    assert.match(memory, /risk failed exit 7: 'node' '-e'/);
  } finally {
    await rm(repo, { recursive: true, force: true });
  }
});

test("branch summary derives branch context from committed memories", async () => {
  const repo = await tempRepo();

  try {
    await git(repo, ["config", "user.name", "Trace Test"]);
    await git(repo, ["config", "user.email", "trace@example.com"]);
    await writeFile(join(repo, "base.txt"), "base\n");
    await git(repo, ["add", "base.txt"]);
    await git(repo, ["commit", "-m", "Create base"]);
    await git(repo, ["checkout", "-b", "feature/trace-memory"]);

    await writeFile(join(repo, "branch.txt"), "branch\n");
    await git(repo, ["add", "branch.txt"]);
    await git(repo, ["commit", "-m", "Add branch memory"]);
    await runTrace(repo, ["init"]);
    await runTrace(repo, ["capture", "--event", "prompt", "--role", "user", "--message", "summarize this feature branch"]);
    await runTrace(repo, ["capture", "--event", "decision", "--message", "Derive branch text from commit memories"]);
    await runTrace(repo, ["record", "--validation", "node --test"]);
    await git(repo, ["add", ".trace"]);
    await git(repo, ["commit", "-m", "Commit branch Trace memory"]);

    const summary = await runTrace(repo, ["branch-summary", "feature/trace-memory", "--base", "main"]);
    assert.match(summary.stdout, /Trace Branch Summary/);
    assert.match(summary.stdout, /Branch: `feature\/trace-memory`/);
    assert.match(summary.stdout, /Base: `main`/);
    assert.match(summary.stdout, /summarize this feature branch/);
    assert.match(summary.stdout, /Derive branch text from commit memories/);
    assert.match(summary.stdout, /branch\.txt/);
    assert.match(summary.stdout, /## Handoff\n\n- Preserve the decision: Derive branch text from commit memories/);

    const summaryJson = JSON.parse((await runTrace(repo, ["branch-summary", "feature/trace-memory", "--base", "main", "--json"])).stdout);
    assert.equal(summaryJson.kind, "branch");
    assert.equal(summaryJson.branch, "feature/trace-memory");
    assert.equal(summaryJson.base, "main");
    assert.deepEqual(summaryJson.files, ["branch.txt"]);
    assert.match(summaryJson.handoff[0], /Derive branch text/);
  } finally {
    await rm(repo, { recursive: true, force: true });
  }
});

test("record distills noisy raw sessions into compact memories", async () => {
  const repo = await tempRepo();

  try {
    await git(repo, ["config", "user.name", "Trace Test"]);
    await git(repo, ["config", "user.email", "trace@example.com"]);
    await writeFile(join(repo, "noise.txt"), "noise\n");
    await git(repo, ["add", "noise.txt"]);
    await git(repo, ["commit", "-m", "Add noisy trace case"]);

    await runTrace(repo, ["init"]);
    await runTrace(repo, ["session", "start", "noisy-session"]);
    await runTrace(repo, ["capture", "--event", "prompt", "--role", "user", "--message", "capture only the useful memory"]);
    await runTrace(repo, ["capture", "--event", "decision", "--message", "Keep the durable memory short"]);
    await runTrace(repo, ["capture", "--event", "decision", "--message", "Keep the durable memory short"]);
    await runTrace(repo, ["capture", "--event", "response", "--role", "assistant", "--message", `long response ${"detail ".repeat(80)}`]);
    for (const risk of ["risk one", "risk two", "risk three", "risk four", "risk five", "risk six", "risk seven"]) {
      await runTrace(repo, ["capture", "--event", "risk", "--message", risk]);
    }
    await runTrace(repo, ["session", "end", "noisy-session"]);

    const record = JSON.parse((await runTrace(repo, ["record", "--session", "noisy-session"])).stdout);

    const memory = (await runTrace(repo, ["show", "HEAD"])).stdout;
    assert.equal((sectionText(memory, "Decisions").match(/Keep the durable memory short/g) ?? []).length, 1);
    assert.match(memory, /long response detail .*\.{3}/);
    assert.match(memory, /2 more events omitted from this compact memory/);
    assert.doesNotMatch(memory, /risk seven/);
    assert.doesNotMatch(memory, /session started/);
    assert.doesNotMatch(memory, /session ended/);
    assert.match(memory, /## Handoff\n\n- Preserve the decision: Keep the durable memory short/);

    const checkpoint = JSON.parse((await git(repo, ["show", `refs/trace/checkpoints:checkpoints/${record.checkpoint}.json`])).stdout);
    assert.deepEqual(checkpoint.events.filter((event) => event.source === "trace-session").map((event) => event.message), ["session started", "session ended"]);
  } finally {
    await rm(repo, { recursive: true, force: true });
  }
});

test("record reuses Trace commit trailers for checkpoint and session identity", async () => {
  const repo = await tempRepo();

  try {
    await git(repo, ["config", "user.name", "Trace Test"]);
    await git(repo, ["config", "user.email", "trace@example.com"]);
    await runTrace(repo, ["init"]);
    await runTrace(repo, ["capture", "--session", "manual-session", "--event", "prompt", "--role", "user", "--message", "reuse trailer session"]);
    await writeFile(join(repo, "trailers.txt"), "trailers\n");
    await git(repo, ["add", "trailers.txt"]);
    await git(repo, ["commit", "-m", "Add trailer case", "-m", "Trace-Checkpoint: manual-checkpoint\nTrace-Session: manual-session"]);

    const record = JSON.parse((await runTrace(repo, ["record", "--validation", "node --test"])).stdout);
    assert.equal(record.checkpoint, "manual-checkpoint");
    assert.equal(record.session, "manual-session");

    const memory = (await runTrace(repo, ["show", "HEAD"])).stdout;
    assert.match(memory, /Checkpoint: `manual-checkpoint`/);
    assert.match(memory, /Session: `manual-session`/);
    assert.match(memory, /reuse trailer session/);

    const listed = JSON.parse((await runTrace(repo, ["checkpoint", "list"])).stdout);
    assert.deepEqual(listed.checkpoints.map((checkpoint) => checkpoint.checkpoint_id), ["manual-checkpoint"]);
  } finally {
    await rm(repo, { recursive: true, force: true });
  }
});

test("check fails on uncommitted Trace memories and passes after committing them", async () => {
  const repo = await tempRepo();

  try {
    await git(repo, ["config", "user.name", "Trace Test"]);
    await git(repo, ["config", "user.email", "trace@example.com"]);
    await writeFile(join(repo, "check.txt"), "check\n");
    await git(repo, ["add", "check.txt"]);
    await git(repo, ["commit", "-m", "Add check file"]);

    await runTrace(repo, ["init"]);
    await runTrace(repo, ["capture", "--event", "prompt", "--role", "user", "--message", "check committed trace state"]);
    await runTrace(repo, ["record", "--validation", "node --test"]);

    const review = await runTrace(repo, ["review"]);
    assert.match(review.stdout, /Trace Memory Review/);
    assert.match(review.stdout, /Mode: pending memories/);
    assert.match(review.stdout, /check committed trace state/);
    assert.match(review.stdout, /node --test/);
    assert.match(review.stdout, /Checkpoint: `[0-9a-f]+`/);
    assert.match(review.stdout, /Session: `[A-Za-z0-9-]+`/);
    assert.match(review.stdout, /## Files\n\n- `check.txt`/);
    assert.match(review.stdout, /## Handoff\n\n- Last known validation: node --test/);

    const reviewJson = JSON.parse((await runTrace(repo, ["review", "--json"])).stdout);
    assert.equal(reviewJson.schema_version, "trace.review.v1");
    assert.equal(reviewJson.mode, "pending");
    assert.equal(reviewJson.memories.length, 1);
    assert.equal(reviewJson.memories[0].status, "untracked");
    assert.match(reviewJson.memories[0].checkpoint, /^[0-9a-f]+$/);
    assert.match(reviewJson.memories[0].session, /^[A-Za-z0-9-]+$/);
    assert.equal(reviewJson.memories[0].files, "- `check.txt`");
    assert.match(reviewJson.memories[0].handoff, /Last known validation: node --test/);

    const reviewPath = join(repo, "trace-review.md");
    const reviewWrite = JSON.parse((await runTrace(repo, ["review", "--output", reviewPath])).stdout);
    assert.equal(reviewWrite.schema_version, "trace.review_output.v1");
    assert.equal(reviewWrite.mode, "pending");
    assert.equal(reviewWrite.output, reviewPath);
    assert.equal(reviewWrite.memories, 1);
    assert.equal(reviewWrite.bytes, (await readFile(reviewPath, "utf8")).length);
    assert.match(await readFile(reviewPath, "utf8"), /# Trace Memory Review/);
    assert.match(await readFile(reviewPath, "utf8"), /check committed trace state/);

    const reviewJsonPath = join(repo, "trace-review.json");
    const reviewJsonWrite = JSON.parse((await runTrace(repo, ["review", "--json", "--output", reviewJsonPath])).stdout);
    assert.equal(reviewJsonWrite.schema_version, "trace.review_output.v1");
    const reviewJsonFile = JSON.parse(await readFile(reviewJsonPath, "utf8"));
    assert.equal(reviewJsonFile.schema_version, "trace.review.v1");
    assert.equal(reviewJsonFile.memories.length, 1);

    const dirty = await runTraceAllowFailure(repo, ["check"]);
    assert.equal(dirty.exitCode, 1);
    const dirtyPayload = JSON.parse(dirty.stdout);
    assert.equal(dirtyPayload.ok, false);
    assert.ok(dirtyPayload.uncommitted.some((entry) => entry.includes(".trace/commits/")));

    await git(repo, ["add", ".trace"]);
    await git(repo, ["commit", "-m", "Commit Trace memory"]);

    const clean = await runTrace(repo, ["check"]);
    const cleanPayload = JSON.parse(clean.stdout);
    assert.equal(cleanPayload.ok, true);
    assert.equal(cleanPayload.uncommitted.length, 0);
    assert.equal(cleanPayload.checkpointIntegrity, null);
    assert.equal(cleanPayload.memoryQuality, null);

    const strictMemory = await runTraceAllowFailure(repo, ["check", "--strict-memory"]);
    assert.equal(strictMemory.exitCode, 1);
    const strictMemoryPayload = JSON.parse(strictMemory.stdout);
    assert.equal(strictMemoryPayload.ok, false);
    assert.equal(strictMemoryPayload.memoryQuality.ok, false);
    assert.equal(strictMemoryPayload.memoryQuality.checked, 1);
    assert.ok(strictMemoryPayload.memoryQuality.findings.some((finding) => finding.reason === "missing decision signal"));

    await runTrace(repo, ["enable"]);
    const strictDoctor = await runTraceAllowFailure(repo, ["doctor", "--strict-memory"]);
    assert.equal(strictDoctor.exitCode, 1);
    const strictDoctorPayload = JSON.parse(strictDoctor.stdout);
    const doctorMemoryQuality = strictDoctorPayload.checks.find((check) => check.name === "memoryQuality");
    assert.equal(doctorMemoryQuality.level, "error");
    assert.equal(doctorMemoryQuality.ok, false);
    assert.ok(doctorMemoryQuality.findings.some((finding) => finding.reason === "missing decision signal"));

    const cleanWithCheckpoints = JSON.parse((await runTrace(repo, ["check", "--checkpoints"])).stdout);
    assert.equal(cleanWithCheckpoints.ok, true);
    assert.equal(cleanWithCheckpoints.checkpointIntegrity.ok, true);
    assert.equal(cleanWithCheckpoints.checkpointIntegrity.present, true);
    assert.equal(cleanWithCheckpoints.checkpointIntegrity.linkedMemories, 1);

    await runTrace(repo, ["checkpoint", "cleanup", "--keep", "0"]);
    const missingCheckpointData = await runTraceAllowFailure(repo, ["check", "--checkpoints"]);
    assert.equal(missingCheckpointData.exitCode, 1);
    const missingCheckpointReport = JSON.parse(missingCheckpointData.stdout);
    assert.equal(missingCheckpointReport.ok, false);
    assert.equal(missingCheckpointReport.checkpointIntegrity.ok, false);
    assert.equal(missingCheckpointReport.checkpointIntegrity.present, true);
    assert.ok(missingCheckpointReport.checkpointIntegrity.errors.some((entry) => entry.error.includes("missing checkpoint payload")));

    const doctorMissingCheckpoint = await runTraceAllowFailure(repo, ["doctor"]);
    assert.equal(doctorMissingCheckpoint.exitCode, 1);
    const doctorMissingCheckpointReport = JSON.parse(doctorMissingCheckpoint.stdout);
    const doctorCheckpointRef = doctorMissingCheckpointReport.checks.find((check) => check.name === "checkpointRef");
    assert.equal(doctorCheckpointRef.level, "error");
    assert.equal(doctorCheckpointRef.present, true);
    assert.equal(doctorCheckpointRef.linkedMemories, 1);
    assert.ok(doctorCheckpointRef.errors.some((entry) => entry.error.includes("missing checkpoint payload")));

    const pendingReview = await runTrace(repo, ["review"]);
    assert.match(pendingReview.stdout, /No pending Trace memories found/);
    const allReview = await runTrace(repo, ["review", "--all"]);
    assert.match(allReview.stdout, /check committed trace state/);
  } finally {
    await rm(repo, { recursive: true, force: true });
  }
});

test("check rejects malformed committed memory files", async () => {
  const repo = await tempRepo();

  try {
    await git(repo, ["config", "user.name", "Trace Test"]);
    await git(repo, ["config", "user.email", "trace@example.com"]);
    await writeFile(join(repo, "malformed.txt"), "malformed\n");
    await git(repo, ["add", "malformed.txt"]);
    await git(repo, ["commit", "-m", "Add malformed memory target"]);
    await runTrace(repo, ["init"]);

    const sha = (await git(repo, ["rev-parse", "HEAD"])).stdout.trim();
    const memoryDir = join(repo, ".trace/commits", sha.slice(0, 2));
    await mkdir(memoryDir, { recursive: true });
    await writeFile(join(memoryDir, `${sha}.md`), `# malformed\n\nSchema: \`trace.memory.v0\`\nCommit: \`${sha}\`\n\n## Intent\n\nbad\n`);

    const checked = await runTraceAllowFailure(repo, ["check"]);
    assert.equal(checked.exitCode, 1);
    const payload = JSON.parse(checked.stdout);
    assert.ok(payload.invalidMemories.some((entry) => entry.reason === "unsupported schema trace.memory.v0"));
    assert.ok(payload.invalidMemories.some((entry) => entry.reason === "missing Checkpoint field"));
    assert.ok(payload.invalidMemories.some((entry) => entry.reason === "missing Session field"));
    assert.ok(payload.invalidMemories.some((entry) => entry.reason === "missing Created field"));
    assert.ok(payload.invalidMemories.some((entry) => entry.reason === "missing Summary section"));
    assert.ok(payload.invalidMemories.some((entry) => entry.reason === "missing Risks section"));
    assert.ok(payload.invalidMemories.some((entry) => entry.reason === "missing Handoff section"));
  } finally {
    await rm(repo, { recursive: true, force: true });
  }
});

test("check rejects memories whose commit is not reachable", async () => {
  const repo = await tempRepo();

  try {
    await git(repo, ["config", "user.name", "Trace Test"]);
    await git(repo, ["config", "user.email", "trace@example.com"]);
    await runTrace(repo, ["init"]);

    const missingSha = "a".repeat(40);
    const memoryDir = join(repo, ".trace/commits", missingSha.slice(0, 2));
    await mkdir(memoryDir, { recursive: true });
    await writeFile(join(memoryDir, `${missingSha}.md`), `# ${missingSha.slice(0, 12)} missing

Schema: \`trace.memory.v1\`
Commit: \`${missingSha}\`
Checkpoint: \`checkpoint-missing\`
Session: \`session-missing\`
Created: \`2026-05-23T00:00:00.000Z\`

## Intent

missing commit memory

## Summary

- unreachable memory should fail

## Decisions

- Not recorded.

## Responses

- Not recorded.

## Tool Activity

- Not recorded.

## Files

- \`missing.txt\`

## Validation

- Not recorded.

## Risks

- No known open risks recorded.

## Handoff

- Review this memory and the commit diff before changing related code.
`);

    const checked = await runTraceAllowFailure(repo, ["check"]);
    assert.equal(checked.exitCode, 1);
    const payload = JSON.parse(checked.stdout);
    assert.ok(payload.invalidMemories.some((entry) => entry.reason === `missing commit ${missingSha}`));
  } finally {
    await rm(repo, { recursive: true, force: true });
  }
});

test("doctor reports hook and local memory health without mutating caches", async () => {
  const repo = await tempRepo();

  try {
    await runTrace(repo, ["init"]);

    const missingHooks = await runTraceAllowFailure(repo, ["doctor"]);
    assert.equal(missingHooks.exitCode, 1);
    const missingPayload = JSON.parse(missingHooks.stdout);
    const missingHookCheck = missingPayload.checks.find((check) => check.name === "hooks");
    assert.equal(missingPayload.ok, false);
    assert.equal(missingHookCheck.ok, false);
    assert.equal(missingHookCheck.preCommit, false);
    assert.equal(missingHookCheck.prepareCommitMsg, false);
    assert.equal(missingHookCheck.postCommit, false);

    await runTrace(repo, ["enable"]);

    const installDir = join(repo, "trace-bin");
    const doctor = await runTrace(repo, ["doctor", "--prefix", installDir]);
    const payload = JSON.parse(doctor.stdout);
    const hooks = payload.checks.find((check) => check.name === "hooks");
    const dirtyTrace = payload.checks.find((check) => check.name === "dirtyTrace");
    const checkpointRef = payload.checks.find((check) => check.name === "checkpointRef");
    const searchIndex = payload.checks.find((check) => check.name === "searchIndex");
    const install = payload.checks.find((check) => check.name === "install");

    assert.equal(payload.ok, true);
    assert.equal(hooks.ok, true);
    assert.equal(dirtyTrace.level, "warning");
    assert.ok(dirtyTrace.uncommitted.some((entry) => entry.includes(".trace/config.json")));
    assert.equal(checkpointRef.present, false);
    assert.equal(checkpointRef.level, "warning");
    assert.equal(searchIndex.present, false);
    assert.equal(searchIndex.rebuild, "trace index");
    assert.equal(install.level, "warning");
    assert.equal(install.installed, false);
    assert.equal(install.valid, false);
    assert.equal(install.installDir, installDir);
    assert.equal(install.target, join(installDir, "trace"));
    assert.match(install.installCommand, /trace\/install\.sh --prefix /);

    const strictDoctor = await runTrace(repo, ["doctor", "--strict-memory", "--prefix", installDir]);
    const strictPayload = JSON.parse(strictDoctor.stdout);
    const memoryQuality = strictPayload.checks.find((check) => check.name === "memoryQuality");
    assert.equal(strictPayload.ok, true);
    assert.equal(memoryQuality.ok, true);
    assert.equal(memoryQuality.checked, 0);
  } finally {
    await rm(repo, { recursive: true, force: true });
  }
});

test("ci checks memory coverage while skipping trace-only memory commits", async () => {
  const repo = await tempRepo();

  try {
    await git(repo, ["config", "user.name", "Trace Test"]);
    await git(repo, ["config", "user.email", "trace@example.com"]);
    await writeFile(join(repo, "ci.txt"), "ci\n");
    await git(repo, ["add", "ci.txt"]);
    await git(repo, ["commit", "-m", "Add ci file"]);

    await runTrace(repo, ["init"]);
    const missing = await runTraceAllowFailure(repo, ["ci", "HEAD"]);
    assert.equal(missing.exitCode, 1);
    const missingPayload = JSON.parse(missing.stdout);
    assert.equal(missingPayload.ok, false);
    assert.equal(missingPayload.checked, 1);
    assert.equal(missingPayload.missingMemories.length, 1);
    assert.match(missingPayload.missingMemories[0].expected, /^\.trace\/commits\/[0-9a-f]{2}\//);

    const coverage = await runTrace(repo, ["coverage", "HEAD"]);
    const coveragePayload = JSON.parse(coverage.stdout);
    assert.equal(coveragePayload.ok, false);
    assert.equal(coveragePayload.covered, 0);
    assert.equal(coveragePayload.missing, 1);
    assert.equal(coveragePayload.commits[0].status, "missing");

    await runTrace(repo, ["capture", "--event", "prompt", "--role", "user", "--message", "ci memory coverage"]);
    await runTrace(repo, ["record", "--validation", "node --test"]);
    await git(repo, ["add", ".trace"]);
    await git(repo, ["commit", "-m", "Commit Trace memory"]);

    const covered = await runTrace(repo, ["ci", "HEAD"]);
    const coveredPayload = JSON.parse(covered.stdout);
    assert.equal(coveredPayload.ok, true);
    assert.equal(coveredPayload.checked, 2);
    assert.equal(coveredPayload.covered, 1);
    assert.equal(coveredPayload.skipped, 1);
    assert.deepEqual(coveredPayload.missingMemories, []);
    assert.deepEqual(coveredPayload.unsafeFiles, []);
    assert.deepEqual(coveredPayload.invalidMemories, []);
    assert.deepEqual(coveredPayload.redactionFindings, []);
    assert.equal(coveredPayload.agentContracts, null);
    assert.equal(coveredPayload.checkpointIntegrity, null);
    assert.equal(coveredPayload.memoryQuality, null);
    assert.deepEqual(coveredPayload.commits.map((commit) => commit.status), ["covered", "skipped"]);

    const strictMemory = await runTraceAllowFailure(repo, ["ci", "HEAD", "--strict-memory"]);
    assert.equal(strictMemory.exitCode, 1);
    const strictMemoryPayload = JSON.parse(strictMemory.stdout);
    assert.equal(strictMemoryPayload.ok, false);
    assert.equal(strictMemoryPayload.memoryQuality.ok, false);
    assert.equal(strictMemoryPayload.memoryQuality.checked, 1);
    assert.ok(strictMemoryPayload.memoryQuality.findings.some((finding) => finding.reason === "missing decision signal"));

    const withCheckpoints = JSON.parse((await runTrace(repo, ["ci", "HEAD", "--checkpoints"])).stdout);
    assert.equal(withCheckpoints.ok, true);
    assert.equal(withCheckpoints.checkpointIntegrity.ok, true);
    assert.equal(withCheckpoints.checkpointIntegrity.present, true);
    assert.equal(withCheckpoints.checkpointIntegrity.checked, 1);
    assert.equal(withCheckpoints.checkpointIntegrity.linkedMemories, 1);

    const coverageWithCheckpoints = JSON.parse((await runTrace(repo, ["coverage", "HEAD", "--checkpoints"])).stdout);
    assert.equal(coverageWithCheckpoints.ok, true);
    assert.equal(coverageWithCheckpoints.checkpointIntegrity.ok, true);
    assert.equal(coverageWithCheckpoints.checkpointIntegrity.linkedMemories, 1);

    const missingAgents = await runTraceAllowFailure(repo, ["ci", "HEAD", "--agents"]);
    assert.equal(missingAgents.exitCode, 1);
    const missingAgentsPayload = JSON.parse(missingAgents.stdout);
    assert.equal(missingAgentsPayload.ok, false);
    assert.equal(missingAgentsPayload.covered, 1);
    assert.equal(missingAgentsPayload.agentContracts.ok, false);
    assert.ok(missingAgentsPayload.agentContracts.agents.some((agent) => agent.errors.some((error) => error.includes("missing adapter config"))));

    const coverageWithMissingAgents = JSON.parse((await runTrace(repo, ["coverage", "HEAD", "--agents"])).stdout);
    assert.equal(coverageWithMissingAgents.ok, false);
    assert.equal(coverageWithMissingAgents.agentContracts.ok, false);

    await runTrace(repo, ["agent", "add", "all"]);
    const withAgents = JSON.parse((await runTrace(repo, ["ci", "HEAD", "--agents"])).stdout);
    assert.equal(withAgents.ok, true);
    assert.equal(withAgents.agentContracts.ok, true);
    assert.deepEqual(withAgents.agentContracts.agents.map((agent) => agent.agent), ["codex", "claude-code", "gemini", "generic"]);
    assert.deepEqual(withAgents.agentContracts.agents.map((agent) => agent.event), ["tool", "prompt", "response", "validation"]);

    const coverageWithAgents = JSON.parse((await runTrace(repo, ["coverage", "HEAD", "--agents", "--checkpoints"])).stdout);
    assert.equal(coverageWithAgents.ok, true);
    assert.equal(coverageWithAgents.agentContracts.ok, true);
    assert.equal(coverageWithAgents.checkpointIntegrity.ok, true);

    const fullCi = JSON.parse((await runTrace(repo, ["ci", "HEAD", "--agents", "--checkpoints"])).stdout);
    assert.equal(fullCi.ok, true);
    assert.equal(fullCi.agentContracts.ok, true);
    assert.equal(fullCi.checkpointIntegrity.ok, true);

    await runTrace(repo, ["checkpoint", "cleanup", "--keep", "0"]);
    const coverageMissingCheckpointData = JSON.parse((await runTrace(repo, ["coverage", "HEAD", "--checkpoints"])).stdout);
    assert.equal(coverageMissingCheckpointData.ok, false);
    assert.equal(coverageMissingCheckpointData.checkpointIntegrity.ok, false);
    const missingCheckpointData = await runTraceAllowFailure(repo, ["ci", "HEAD", "--checkpoints"]);
    assert.equal(missingCheckpointData.exitCode, 1);
    const missingCheckpointPayloadReport = JSON.parse(missingCheckpointData.stdout);
    assert.equal(missingCheckpointPayloadReport.ok, false);
    assert.equal(missingCheckpointPayloadReport.checkpointIntegrity.ok, false);
    assert.equal(missingCheckpointPayloadReport.checkpointIntegrity.present, true);
    assert.equal(missingCheckpointPayloadReport.checkpointIntegrity.linkedMemories, 1);
    assert.ok(missingCheckpointPayloadReport.checkpointIntegrity.errors.some((entry) => entry.error.includes("missing checkpoint payload")));

    await git(repo, ["update-ref", "-d", "refs/trace/checkpoints"]);
    const missingCheckpoint = await runTraceAllowFailure(repo, ["ci", "HEAD", "--checkpoints"]);
    assert.equal(missingCheckpoint.exitCode, 1);
    const missingCheckpointPayload = JSON.parse(missingCheckpoint.stdout);
    assert.equal(missingCheckpointPayload.ok, false);
    assert.equal(missingCheckpointPayload.checkpointIntegrity.ok, false);
    assert.equal(missingCheckpointPayload.checkpointIntegrity.present, false);
  } finally {
    await rm(repo, { recursive: true, force: true });
  }
});

test("ci rejects unsafe raw transcript files in the project tree", async () => {
  const repo = await tempRepo();

  try {
    await git(repo, ["config", "user.name", "Trace Test"]);
    await git(repo, ["config", "user.email", "trace@example.com"]);
    await writeFile(join(repo, "raw.txt"), "raw\n");
    await git(repo, ["add", "raw.txt"]);
    await git(repo, ["commit", "-m", "Add raw file"]);
    await runTrace(repo, ["init"]);
    await mkdir(join(repo, ".trace/sessions"), { recursive: true });
    await writeFile(join(repo, ".trace/sessions/leak.jsonl"), "{\"message\":\"full transcript\"}\n");

    const result = await runTraceAllowFailure(repo, ["ci", "HEAD"]);
    assert.equal(result.exitCode, 1);
    const payload = JSON.parse(result.stdout);
    assert.equal(payload.ok, false);
    assert.ok(payload.unsafeFiles.includes(".trace/sessions/leak.jsonl"));
  } finally {
    await rm(repo, { recursive: true, force: true });
  }
});

test("ci rejects malformed or unredacted committed memories", async () => {
  const repo = await tempRepo();

  try {
    await git(repo, ["config", "user.name", "Trace Test"]);
    await git(repo, ["config", "user.email", "trace@example.com"]);
    await writeFile(join(repo, "unsafe-memory.txt"), "unsafe\n");
    await git(repo, ["add", "unsafe-memory.txt"]);
    await git(repo, ["commit", "-m", "Add unsafe memory target"]);
    await runTrace(repo, ["init"]);
    await runTrace(repo, ["capture", "--event", "prompt", "--message", "unsafe memory ci"]);
    await runTrace(repo, ["record", "--validation", "node --test"]);

    const sha = (await git(repo, ["rev-parse", "HEAD"])).stdout.trim();
    const memoryPath = join(repo, ".trace/commits", sha.slice(0, 2), `${sha}.md`);
    await writeFile(memoryPath, `${await readFile(memoryPath, "utf8")}\ntoken=visible-secret\n`);
    await git(repo, ["add", ".trace"]);
    await git(repo, ["commit", "-m", "Commit unsafe Trace memory"]);

    const result = await runTraceAllowFailure(repo, ["ci", "HEAD~1"]);
    assert.equal(result.exitCode, 1);
    const payload = JSON.parse(result.stdout);
    assert.equal(payload.ok, false);
    assert.deepEqual(payload.missingMemories, []);
    assert.ok(payload.redactionFindings.some((finding) => finding.rule === "secret-assignment"));
  } finally {
    await rm(repo, { recursive: true, force: true });
  }
});

test("checkpoint commands list verify sync and cleanup local checkpoint data", async () => {
  const repo = await tempRepo();

  try {
    await git(repo, ["config", "user.name", "Trace Test"]);
    await git(repo, ["config", "user.email", "trace@example.com"]);
    await writeFile(join(repo, "checkpoint.txt"), "checkpoint\n");
    await git(repo, ["add", "checkpoint.txt"]);
    await git(repo, ["commit", "-m", "Add checkpoint file"]);

    await runTrace(repo, ["init"]);
    await runTrace(repo, ["capture", "--event", "prompt", "--role", "user", "--message", "checkpoint ref controls"]);
    const record = JSON.parse((await runTrace(repo, ["record", "--checkpoint", "checkpoint-a", "--validation", "node --test"])).stdout);

    const listed = JSON.parse((await runTrace(repo, ["checkpoint", "list"])).stdout);
    assert.equal(listed.ok, true);
    assert.equal(listed.ref, "refs/trace/checkpoints");
    assert.equal(listed.checkpoints.length, 1);
    assert.equal(listed.checkpoints[0].checkpoint_id, record.checkpoint);
    assert.equal(listed.checkpoints[0].events, 1);
    assert.equal(listed.checkpoints[0].integrity, true);

    const verified = JSON.parse((await runTrace(repo, ["checkpoint", "verify"])).stdout);
    assert.equal(verified.ok, true);
    assert.equal(verified.checked, 1);
    assert.deepEqual(verified.errors, []);

    const checkpointPath = `checkpoints/${record.checkpoint}.json`;
    const rawCheckpoint = JSON.parse((await git(repo, ["show", `refs/trace/checkpoints:${checkpointPath}`])).stdout);
    assert.equal(rawCheckpoint.integrity.algorithm, "sha256");
    assert.match(rawCheckpoint.integrity.payload_sha256, /^[0-9a-f]{64}$/);

    const shown = await runTrace(repo, ["checkpoint", "show", "checkpoint-a"]);
    assert.match(shown.stdout, /Trace Checkpoint/);
    assert.match(shown.stdout, /Checkpoint: `checkpoint-a`/);
    assert.match(shown.stdout, /Events: 1/);
    assert.match(shown.stdout, /\[prompt user\] manual: checkpoint ref controls/);

    const shownJson = JSON.parse((await runTrace(repo, ["checkpoint", "show", "checkpoint-a", "--json"])).stdout);
    assert.equal(shownJson.schema_version, "trace.checkpoint_detail.v1");
    assert.equal(shownJson.path, "checkpoints/checkpoint-a.json");
    assert.equal(shownJson.integrity.ok, true);
    assert.equal(shownJson.checkpoint.checkpoint_id, "checkpoint-a");
    assert.equal(shownJson.checkpoint.events[0].message, "checkpoint ref controls");

    const missingCheckpoint = await runTraceAllowFailure(repo, ["checkpoint", "show", "missing-checkpoint"]);
    assert.equal(missingCheckpoint.exitCode, 1);
    assert.match(missingCheckpoint.stderr, /checkpoint not found: missing-checkpoint/);

    rawCheckpoint.subject = "tampered checkpoint";
    const tamperedPath = join(repo, "tampered-checkpoint.json");
    const tamperIndex = join(repo, "tamper-index");
    const tamperEnv = { GIT_INDEX_FILE: tamperIndex };
    await writeFile(tamperedPath, `${JSON.stringify(rawCheckpoint, null, 2)}\n`);
    await gitWithEnv(repo, ["read-tree", "refs/trace/checkpoints^{tree}"], tamperEnv);
    const tamperedBlob = (await git(repo, ["hash-object", "-w", tamperedPath])).stdout.trim();
    await gitWithEnv(repo, ["update-index", "--add", "--cacheinfo", `100644,${tamperedBlob},${checkpointPath}`], tamperEnv);
    const tamperedTree = (await gitWithEnv(repo, ["write-tree"], tamperEnv)).stdout.trim();
    const checkpointHead = (await git(repo, ["rev-parse", "refs/trace/checkpoints"])).stdout.trim();
    const tamperedCommit = (await gitWithEnv(repo, ["commit-tree", tamperedTree, "-p", checkpointHead, "-m", "Tamper checkpoint"], tamperEnv)).stdout.trim();
    await git(repo, ["update-ref", "refs/trace/checkpoints", tamperedCommit]);

    const tamperedVerify = await runTraceAllowFailure(repo, ["checkpoint", "verify"]);
    assert.equal(tamperedVerify.exitCode, 1);
    const tamperedPayload = JSON.parse(tamperedVerify.stdout);
    assert.equal(tamperedPayload.ok, false);
    assert.ok(tamperedPayload.errors.some((entry) => entry.error === "checkpoint integrity mismatch"));

    await git(repo, ["update-ref", "refs/trace/checkpoints", checkpointHead]);

    await writeFile(join(repo, "checkpoint-2.txt"), "checkpoint 2\n");
    await git(repo, ["add", "checkpoint-2.txt"]);
    await git(repo, ["commit", "-m", "Add second checkpoint file"]);
    await runTrace(repo, ["capture", "--event", "decision", "--message", "checkpoint retention keeps the newest payload"]);
    const secondRecord = JSON.parse((await runTrace(repo, ["record", "--checkpoint", "checkpoint-b", "--validation", "node --test"])).stdout);
    assert.equal(secondRecord.checkpoint, "checkpoint-b");

    const beforeCleanup = JSON.parse((await runTrace(repo, ["checkpoint", "list"])).stdout);
    assert.equal(beforeCleanup.total, 2);
    assert.equal(beforeCleanup.limit, null);
    assert.equal(beforeCleanup.checkpoints.length, 2);

    const limitedCheckpoints = JSON.parse((await runTrace(repo, ["checkpoint", "list", "--limit", "1"])).stdout);
    assert.equal(limitedCheckpoints.total, 2);
    assert.equal(limitedCheckpoints.limit, 1);
    assert.deepEqual(limitedCheckpoints.checkpoints.map((checkpoint) => checkpoint.checkpoint_id), ["checkpoint-b"]);

    const bundlePath = join(repo, "trace-checkpoints.json");
    const exported = JSON.parse((await runTrace(repo, ["checkpoint", "export", "--output", bundlePath])).stdout);
    assert.equal(exported.ok, true);
    assert.equal(exported.checkpoints, 2);
    const bundle = JSON.parse(await readFile(bundlePath, "utf8"));
    assert.equal(bundle.schema_version, "trace.checkpoint_bundle.v1");
    assert.equal(bundle.checkpoints.length, 2);

    await git(repo, ["update-ref", "-d", "refs/trace/checkpoints"]);
    const emptyList = JSON.parse((await runTrace(repo, ["checkpoint", "list"])).stdout);
    assert.deepEqual(emptyList.checkpoints, []);

    const importPreview = JSON.parse((await runTrace(repo, ["checkpoint", "import", bundlePath, "--dry-run"])).stdout);
    assert.equal(importPreview.ok, true);
    assert.equal(importPreview.dryRun, true);
    assert.equal(importPreview.imported, 2);
    assert.equal(importPreview.retained, 2);
    const emptyAfterPreview = JSON.parse((await runTrace(repo, ["checkpoint", "list"])).stdout);
    assert.deepEqual(emptyAfterPreview.checkpoints, []);

    const imported = JSON.parse((await runTrace(repo, ["checkpoint", "import", bundlePath])).stdout);
    assert.equal(imported.ok, true);
    assert.equal(imported.dryRun, false);
    assert.equal(imported.imported, 2);
    const restored = JSON.parse((await runTrace(repo, ["checkpoint", "list"])).stdout);
    assert.deepEqual(restored.checkpoints.map((checkpoint) => checkpoint.checkpoint_id), ["checkpoint-a", "checkpoint-b"]);

    const bareRemote = join(repo, "checkpoint-origin.git");
    await git(repo, ["init", "--bare", bareRemote]);
    await git(repo, ["remote", "add", "origin", bareRemote]);
    const missingRemoteStatus = JSON.parse((await runTrace(repo, ["checkpoint", "status", "origin"])).stdout);
    assert.equal(missingRemoteStatus.schema_version, "trace.checkpoint_status.v1");
    assert.equal(missingRemoteStatus.localPresent, true);
    assert.equal(missingRemoteStatus.remotePresent, false);
    assert.equal(missingRemoteStatus.inSync, false);
    assert.equal(missingRemoteStatus.pushCommand, "git push origin refs/trace/checkpoints:refs/trace/checkpoints");

    const pushed = JSON.parse((await runTrace(repo, ["checkpoint", "push", "origin"])).stdout);
    assert.equal(pushed.schema_version, "trace.checkpoint_sync.v1");
    assert.equal(pushed.action, "push");
    assert.equal(pushed.dryRun, false);
    assert.equal(pushed.before.localPresent, true);
    assert.equal(pushed.before.remotePresent, false);
    assert.equal(pushed.after.inSync, true);
    const syncedStatus = JSON.parse((await runTrace(repo, ["checkpoint", "status", "origin"])).stdout);
    assert.equal(syncedStatus.localPresent, true);
    assert.equal(syncedStatus.remotePresent, true);
    assert.equal(syncedStatus.inSync, true);
    assert.equal(syncedStatus.ahead, 0);
    assert.equal(syncedStatus.behind, 0);

    const push = JSON.parse((await runTrace(repo, ["checkpoint", "push", "origin", "--dry-run"])).stdout);
    assert.equal(push.schema_version, "trace.checkpoint_sync.v1");
    assert.equal(push.action, "push");
    assert.equal(push.dryRun, true);
    assert.equal(push.command, "git push origin refs/trace/checkpoints:refs/trace/checkpoints");
    assert.equal(push.before.inSync, true);
    assert.equal(push.after.inSync, true);

    const fetch = JSON.parse((await runTrace(repo, ["checkpoint", "fetch", "origin", "--dry-run"])).stdout);
    assert.equal(fetch.schema_version, "trace.checkpoint_sync.v1");
    assert.equal(fetch.action, "fetch");
    assert.equal(fetch.dryRun, true);
    assert.equal(fetch.command, "git fetch origin refs/trace/checkpoints:refs/trace/checkpoints");
    assert.equal(fetch.before.inSync, true);
    assert.equal(fetch.after.inSync, true);

    const commonDir = (await git(repo, ["rev-parse", "--git-common-dir"])).stdout.trim();
    const sessionId = (await readFile(join(repo, commonDir, "trace/current_session"), "utf8")).trim();
    const sessionFile = join(repo, commonDir, `trace/sessions/${sessionId}.jsonl`);
    assert.match(await readFile(sessionFile, "utf8"), /checkpoint ref controls/);
    const refBeforeCleanup = (await git(repo, ["rev-parse", "--verify", "refs/trace/checkpoints"])).stdout.trim();

    const cleanupPreview = JSON.parse((await runTrace(repo, ["checkpoint", "cleanup", "--sessions-before-days", "0", "--keep", "1", "--dry-run"])).stdout);
    assert.equal(cleanupPreview.ok, true);
    assert.equal(cleanupPreview.dryRun, true);
    assert.ok(cleanupPreview.removed.some((entry) => entry.endsWith(`${sessionId}.jsonl`)));
    assert.deepEqual(cleanupPreview.checkpoints.removed, ["checkpoints/checkpoint-a.json"]);
    assert.equal(cleanupPreview.checkpoints.retained, 1);
    assert.equal(await readFile(sessionFile, "utf8").then((content) => /checkpoint ref controls/.test(content)), true);
    const refAfterPreview = (await git(repo, ["rev-parse", "--verify", "refs/trace/checkpoints"])).stdout.trim();
    assert.equal(refAfterPreview, refBeforeCleanup);

    const cleanup = JSON.parse((await runTrace(repo, ["checkpoint", "cleanup", "--sessions-before-days", "0", "--keep", "1"])).stdout);
    assert.equal(cleanup.ok, true);
    assert.equal(cleanup.dryRun, false);
    assert.equal(cleanup.sessionsBeforeDays, 0);
    assert.ok(cleanup.removed.some((entry) => entry.endsWith(`${sessionId}.jsonl`)));
    assert.deepEqual(cleanup.checkpoints.removed, ["checkpoints/checkpoint-a.json"]);
    assert.equal(cleanup.checkpoints.retained, 1);

    const afterCleanup = JSON.parse((await runTrace(repo, ["checkpoint", "list"])).stdout);
    assert.deepEqual(afterCleanup.checkpoints.map((checkpoint) => checkpoint.checkpoint_id), ["checkpoint-b"]);

    const ref = await git(repo, ["rev-parse", "--verify", "refs/trace/checkpoints"]);
    assert.match(ref.stdout.trim(), /^[0-9a-f]{40}$/);
  } finally {
    await rm(repo, { recursive: true, force: true });
  }
});

test("custom redaction rules apply to raw events and commit memories", async () => {
  const repo = await tempRepo();

  try {
    await git(repo, ["config", "user.name", "Trace Test"]);
    await git(repo, ["config", "user.email", "trace@example.com"]);
    await writeFile(join(repo, "redact.txt"), "redact\n");
    await git(repo, ["add", "redact.txt"]);
    await git(repo, ["commit", "-m", "Add redact file"]);

    await runTrace(repo, ["init"]);
    const added = JSON.parse((await runTrace(repo, ["redact", "add", "codename", "PROJECT-[A-Z]+"])).stdout);
    assert.equal(added.schema_version, "trace.redaction_rule.v1");
    assert.equal(added.action, "add");
    const listed = JSON.parse((await runTrace(repo, ["redact", "list"])).stdout);
    assert.equal(listed.schema_version, "trace.redaction_rules.v1");
    assert.deepEqual(listed.rules, [{ label: "codename", pattern: "PROJECT-[A-Z]+" }]);

    const preview = JSON.parse((await runTrace(repo, [
      "redact",
      "preview",
      "--text",
      "ship PROJECT-ORION with token=visible-secret",
      "--json",
    ])).stdout);
    assert.equal(preview.schema_version, "trace.redaction_preview.v1");
    assert.equal(preview.redacted, "ship [REDACTED_CODENAME] with token=REDACTED");

    const stdinPreview = await runTraceWithInput(repo, ["redact", "preview"], "Authorization: Bearer short-token");
    assert.equal(stdinPreview.stdout, "Authorization: Bearer REDACTED\n");

    await runTrace(repo, [
      "capture",
      "--event",
      "prompt",
      "--role",
      "user",
      "--message",
      "ship PROJECT-ORION with token=visible-secret",
    ]);
    const record = JSON.parse((await runTrace(repo, ["record", "--validation", "PROJECT-ORION validation"])).stdout);

    const commonDir = (await git(repo, ["rev-parse", "--git-common-dir"])).stdout.trim();
    const sessionId = (await readFile(join(repo, commonDir, "trace/current_session"), "utf8")).trim();
    const session = await readFile(join(repo, commonDir, `trace/sessions/${sessionId}.jsonl`), "utf8");
    assert.match(session, /\[REDACTED_CODENAME\]/);
    assert.match(session, /token=REDACTED/);
    assert.doesNotMatch(session, /PROJECT-ORION/);
    assert.doesNotMatch(session, /visible-secret/);

    const memory = (await runTrace(repo, ["show", "HEAD"])).stdout;
    assert.match(memory, /\[REDACTED_CODENAME\]/);
    assert.doesNotMatch(memory, /PROJECT-ORION/);

    const audit = JSON.parse((await runTrace(repo, ["redact", "audit"])).stdout);
    assert.equal(audit.ok, true);
    assert.equal(audit.schema_version, "trace.redaction_audit.v1");
    assert.deepEqual(audit.findings, []);
    assert.ok(audit.scanned.some((entry) => entry.includes("refs/trace/checkpoints:checkpoints/")));

    const checkpointPath = `checkpoints/${record.checkpoint}.json`;
    const rawCheckpoint = JSON.parse((await git(repo, ["show", `refs/trace/checkpoints:${checkpointPath}`])).stdout);
    rawCheckpoint.note = "PROJECT-ORION token=visible-secret";
    const checkpointHead = (await git(repo, ["rev-parse", "refs/trace/checkpoints"])).stdout.trim();
    const tamperedPath = join(repo, "tampered-redaction-checkpoint.json");
    const tamperIndex = join(repo, "redaction-tamper-index");
    const tamperEnv = { GIT_INDEX_FILE: tamperIndex };
    await writeFile(tamperedPath, `${JSON.stringify(rawCheckpoint, null, 2)}\n`);
    await gitWithEnv(repo, ["read-tree", "refs/trace/checkpoints^{tree}"], tamperEnv);
    const tamperedBlob = (await git(repo, ["hash-object", "-w", tamperedPath])).stdout.trim();
    await gitWithEnv(repo, ["update-index", "--add", "--cacheinfo", `100644,${tamperedBlob},${checkpointPath}`], tamperEnv);
    const tamperedTree = (await gitWithEnv(repo, ["write-tree"], tamperEnv)).stdout.trim();
    const tamperedCommit = (await gitWithEnv(repo, ["commit-tree", tamperedTree, "-p", checkpointHead, "-m", "Tamper redaction checkpoint"], tamperEnv)).stdout.trim();
    await git(repo, ["update-ref", "refs/trace/checkpoints", tamperedCommit]);

    const failedCheckpointAudit = await runTraceAllowFailure(repo, ["redact", "audit"]);
    assert.equal(failedCheckpointAudit.exitCode, 1);
    const failedCheckpointPayload = JSON.parse(failedCheckpointAudit.stdout);
    assert.ok(failedCheckpointPayload.findings.some((finding) => finding.file.includes("refs/trace/checkpoints:checkpoints/") && finding.rule === "codename"));
    assert.ok(failedCheckpointPayload.findings.some((finding) => finding.file.includes("refs/trace/checkpoints:checkpoints/") && finding.rule === "secret-assignment"));

    const sha = (await git(repo, ["rev-parse", "HEAD"])).stdout.trim();
    const memoryPath = join(repo, ".trace/commits", sha.slice(0, 2), `${sha}.md`);
    await writeFile(memoryPath, `${await readFile(memoryPath, "utf8")}\nPROJECT-ORION token=visible-secret\n`);
    const failedAudit = await runTraceAllowFailure(repo, ["redact", "audit"]);
    assert.equal(failedAudit.exitCode, 1);
    const failedPayload = JSON.parse(failedAudit.stdout);
    assert.equal(failedPayload.ok, false);
    assert.ok(failedPayload.findings.some((finding) => finding.rule === "codename"));
    assert.ok(failedPayload.findings.some((finding) => finding.rule === "secret-assignment"));

    await runTrace(repo, ["redact", "remove", "codename"]);
    const removed = JSON.parse((await runTrace(repo, ["redact", "list"])).stdout);
    assert.equal(removed.schema_version, "trace.redaction_rules.v1");
    assert.deepEqual(removed.rules, []);
  } finally {
    await rm(repo, { recursive: true, force: true });
  }
});

test("built-in redaction handles environment secrets and authorization headers", async () => {
  const repo = await tempRepo();

  try {
    await git(repo, ["config", "user.name", "Trace Test"]);
    await git(repo, ["config", "user.email", "trace@example.com"]);
    await writeFile(join(repo, "builtin-redact.txt"), "redact\n");
    await git(repo, ["add", "builtin-redact.txt"]);
    await git(repo, ["commit", "-m", "Add builtin redact file"]);
    await runTrace(repo, ["init"]);

    await runTrace(repo, [
      "capture",
      "--event",
      "prompt",
      "--role",
      "user",
      "--message",
      "OPENAI_API_KEY=sk-test Authorization: Bearer short-token x-api-key: header-secret",
    ]);
    await runTrace(repo, ["record", "--validation", "GITHUB_TOKEN=gh-test"]);

    const commonDir = (await git(repo, ["rev-parse", "--git-common-dir"])).stdout.trim();
    const sessionId = (await readFile(join(repo, commonDir, "trace/current_session"), "utf8")).trim();
    const session = await readFile(join(repo, commonDir, `trace/sessions/${sessionId}.jsonl`), "utf8");
    assert.match(session, /OPENAI_API_KEY=REDACTED/);
    assert.match(session, /Authorization: Bearer REDACTED/);
    assert.match(session, /x-api-key: REDACTED/);
    assert.doesNotMatch(session, /sk-test|short-token|header-secret/);

    const memory = (await runTrace(repo, ["show", "HEAD"])).stdout;
    assert.match(memory, /GITHUB_TOKEN=REDACTED/);
    assert.doesNotMatch(memory, /gh-test/);

    const sha = (await git(repo, ["rev-parse", "HEAD"])).stdout.trim();
    const memoryPath = join(repo, ".trace/commits", sha.slice(0, 2), `${sha}.md`);
    await writeFile(memoryPath, `${await readFile(memoryPath, "utf8")}\nOPENAI_API_KEY=sk-live\nAuthorization: Bearer live-token\n`);

    const audit = await runTraceAllowFailure(repo, ["redact", "audit"]);
    assert.equal(audit.exitCode, 1);
    const payload = JSON.parse(audit.stdout);
    assert.equal(payload.ok, false);
    assert.equal(payload.schema_version, "trace.redaction_audit.v1");
    assert.ok(payload.findings.some((finding) => finding.rule === "secret-assignment" && finding.count >= 2));
  } finally {
    await rm(repo, { recursive: true, force: true });
  }
});

test("custom redaction rules reject invalid regex patterns", async () => {
  const repo = await tempRepo();

  try {
    const result = await runTraceAllowFailure(repo, ["redact", "add", "bad", "["]);
    assert.equal(result.exitCode, 1);
    assert.match(result.stderr, /invalid redaction pattern/);
  } finally {
    await rm(repo, { recursive: true, force: true });
  }
});

test("agent add list remove manages local hook adapter configs", async () => {
  const repo = await tempRepo();

  try {
    await runTrace(repo, ["init"]);

    const added = await runTrace(repo, ["agent", "add", "codex"]);
    const addedPayload = JSON.parse(added.stdout);
    assert.equal(addedPayload.ok, true);
    assert.equal(addedPayload.schema_version, "trace.agent_add.v1");
    assert.equal(addedPayload.agent, "codex");
    assert.equal(addedPayload.config, ".trace/agents/codex.json");
    assert.equal(addedPayload.command, "trace hook agent --adapter codex");

    const config = JSON.parse(await readFile(join(repo, ".trace/agents/codex.json"), "utf8"));
    assert.equal(config.schema_version, "trace.agent.v1");
    assert.equal(config.agent, "codex");
    assert.equal(config.adapter, "codex");
    assert.deepEqual(config.events, ["prompt", "response", "tool", "decision", "validation", "risk", "note"]);
    assert.deepEqual(config.contract, {
      fixture: "examples/codex-tool-call.json",
      event: "tool",
      message_includes: ["codex tool shell", "npm --prefix trace test"],
    });

    const listed = await runTrace(repo, ["agent", "list"]);
    const listedPayload = JSON.parse(listed.stdout);
    assert.equal(listedPayload.schema_version, "trace.agent_list.v1");
    assert.deepEqual(listedPayload.agents.map((agent) => agent.agent), ["codex"]);
    assert.equal(listedPayload.agents[0].valid, true);
    assert.equal(listedPayload.agents[0].contract.event, "tool");
    assert.deepEqual(listedPayload.agents[0].errors, []);

    const checked = JSON.parse((await runTrace(repo, ["agent", "check", "codex"])).stdout);
    assert.equal(checked.ok, true);
    assert.equal(checked.schema_version, "trace.agent_check.v1");
    assert.deepEqual(checked.agents.map((agent) => agent.agent), ["codex"]);
    assert.equal(checked.agents[0].event, "tool");
    assert.equal(checked.agents[0].fixture, "examples/codex-tool-call.json");

    const status = await runTrace(repo, ["status", "--prefix", join(repo, "trace-bin")]);
    const statusPayload = JSON.parse(status.stdout);
    assert.equal(statusPayload.schema_version, "trace.status.v1");
    assert.deepEqual(statusPayload.agents.map((agent) => agent.agent), ["codex"]);
    assert.equal(statusPayload.install.ok, true);
    assert.equal(statusPayload.install.installed, false);
    assert.equal(statusPayload.install.target, join(repo, "trace-bin", "trace"));

    const removedOne = JSON.parse((await runTrace(repo, ["agent", "remove", "codex"])).stdout);
    assert.equal(removedOne.schema_version, "trace.agent_remove.v1");
    const removed = await runTrace(repo, ["agent", "list"]);
    assert.deepEqual(JSON.parse(removed.stdout).agents, []);

    const gemini = JSON.parse((await runTrace(repo, ["agent", "add", "gemini"])).stdout);
    assert.equal(gemini.agent, "gemini");
    assert.equal(gemini.command, "trace hook agent --adapter gemini");

    const all = JSON.parse((await runTrace(repo, ["agent", "add", "all"])).stdout);
    assert.equal(all.schema_version, "trace.agent_add.v1");
    assert.deepEqual(all.agents.map((agent) => agent.agent), ["codex", "claude-code", "gemini", "generic"]);

    const allListed = JSON.parse((await runTrace(repo, ["agent", "list"])).stdout);
    assert.deepEqual(allListed.agents.map((agent) => agent.agent), ["claude-code", "codex", "gemini", "generic"]);
    assert.equal(allListed.agents.every((agent) => agent.valid), true);
    const allChecked = JSON.parse((await runTrace(repo, ["agent", "check", "all"])).stdout);
    assert.equal(allChecked.ok, true);
    assert.deepEqual(allChecked.agents.map((agent) => agent.agent), ["codex", "claude-code", "gemini", "generic"]);
    assert.deepEqual(allChecked.agents.map((agent) => agent.event), ["tool", "prompt", "response", "validation"]);

    const removedAll = JSON.parse((await runTrace(repo, ["agent", "remove", "all"])).stdout);
    assert.equal(removedAll.schema_version, "trace.agent_remove.v1");
    assert.deepEqual(removedAll.removed.map((agent) => agent.agent), ["codex", "claude-code", "gemini", "generic"]);
    assert.deepEqual(JSON.parse((await runTrace(repo, ["agent", "list"])).stdout).agents, []);
    const missing = await runTraceAllowFailure(repo, ["agent", "check", "all"]);
    assert.equal(missing.exitCode, 1);
    assert.match(missing.stdout, /missing adapter config/);
  } finally {
    await rm(repo, { recursive: true, force: true });
  }
});

test("session start creates and switches current lifecycle sessions", async () => {
  const repo = await tempRepo();

  try {
    await runTrace(repo, ["init"]);

    const started = JSON.parse((await runTrace(repo, ["session", "start", "task-auth-retry"])).stdout);
    assert.equal(started.ok, true);
    assert.equal(started.session, "task-auth-retry");
    assert.equal(started.event, "note");
    assert.match(started.path, /trace\/sessions\/task-auth-retry\.jsonl$/);

    const current = JSON.parse((await runTrace(repo, ["session", "current"])).stdout);
    assert.equal(current.current, "task-auth-retry");

    const emptyList = JSON.parse((await runTrace(repo, ["session", "list"])).stdout);
    assert.equal(emptyList.current, "task-auth-retry");
    assert.equal(emptyList.sessions[0].session, "task-auth-retry");
    assert.equal(emptyList.sessions[0].events, 1);
    assert.deepEqual(emptyList.sessions[0].counts, { note: 1 });
    assert.deepEqual(emptyList.sessions[0].sources, ["trace-session"]);

    const lifecycleOnly = await runTraceAllowFailure(repo, ["session", "check", "task-auth-retry", "--json"]);
    assert.equal(lifecycleOnly.exitCode, 1);
    const lifecycleOnlyPayload = JSON.parse(lifecycleOnly.stdout);
    assert.equal(lifecycleOnlyPayload.ok, false);
    assert.equal(lifecycleOnlyPayload.commitMemoryEvents, 0);
    assert.equal(lifecycleOnlyPayload.checks.find((check) => check.name === "commitMemoryEvents").level, "error");

    await runTrace(repo, ["capture", "--event", "decision", "--message", "session start controls capture"]);
    const shown = JSON.parse((await runTrace(repo, ["session", "show", "task-auth-retry"])).stdout);
    assert.equal(shown.events.length, 2);
    assert.equal(shown.events[0].message, "session started");
    assert.equal(shown.events[1].message, "session start controls capture");

    const capturedCheck = JSON.parse((await runTrace(repo, ["session", "check", "task-auth-retry", "--json"])).stdout);
    assert.equal(capturedCheck.ok, true);
    assert.equal(capturedCheck.commitMemoryEvents, 1);
    assert.equal(capturedCheck.checks.find((check) => check.name === "decisions").ok, true);

    const strictCapturedCheck = await runTraceAllowFailure(repo, ["session", "check", "task-auth-retry", "--strict", "--json"]);
    assert.equal(strictCapturedCheck.exitCode, 1);
    const strictCapturedPayload = JSON.parse(strictCapturedCheck.stdout);
    assert.equal(strictCapturedPayload.strict, true);
    assert.equal(strictCapturedPayload.checks.find((check) => check.name === "intent").ok, false);

    const wrongEnd = await runTraceAllowFailure(repo, ["session", "end", "other-session"]);
    assert.equal(wrongEnd.exitCode, 1);
    assert.match(wrongEnd.stderr, /current session is task-auth-retry/);

    const ended = JSON.parse((await runTrace(repo, ["session", "end", "task-auth-retry"])).stdout);
    assert.equal(ended.ended, "task-auth-retry");
    assert.equal(ended.current, null);
    assert.equal(ended.event, "note");
    const afterEnd = JSON.parse((await runTrace(repo, ["session", "current"])).stdout);
    assert.equal(afterEnd.current, null);
    const endedSession = JSON.parse((await runTrace(repo, ["session", "show", "task-auth-retry"])).stdout);
    assert.deepEqual(endedSession.events.map((event) => event.message), ["session started", "session start controls capture", "session ended"]);

    const generated = JSON.parse((await runTrace(repo, ["session", "start"])).stdout);
    assert.match(generated.session, /^2026-05-23-[0-9a-f]{16}$/);

    const invalid = await runTraceAllowFailure(repo, ["session", "start", "../bad"]);
    assert.equal(invalid.exitCode, 1);
    assert.match(invalid.stderr, /session id may only contain/);
  } finally {
    await rm(repo, { recursive: true, force: true });
  }
});

test("agent adapters normalize Codex Claude Code Gemini and generic lifecycle events", async () => {
  const repo = await tempRepo();

  try {
    await runTrace(repo, ["init"]);
    await runTraceWithInput(repo, ["hook", "agent", "--adapter", "codex"], JSON.stringify({
      session_id: "adapter-session",
      type: "tool_call",
      tool_name: "shell",
      arguments: "npm test",
    }));
    await runTraceWithInput(repo, ["hook", "agent", "--adapter", "claude-code"], JSON.stringify({
      session_id: "adapter-session",
      hook_event_name: "UserPromptSubmit",
      prompt: "explain the storage tradeoff",
    }));
    await runTraceWithInput(repo, ["hook", "agent", "--adapter", "gemini"], JSON.stringify({
      session_id: "adapter-session",
      kind: "model_response",
      content: "memory summary completed",
    }));
    await runTraceWithInput(repo, ["hook", "agent", "--adapter", "generic", "validation"], JSON.stringify({
      session_id: "adapter-session",
      message: "npm --prefix trace test passed",
    }));
    const batch = JSON.parse((await runTraceWithInput(repo, ["hook", "agent", "--adapter", "generic"], JSON.stringify([
      {
        session_id: "adapter-session",
        event: "decision",
        message: "batch adapters keep lifecycle ordering",
      },
      {
        session_id: "adapter-session",
        event: "risk",
        message: "batch adapters must preserve risk events",
      },
    ]))).stdout);
    assert.deepEqual(batch.events.map((event) => event.event), ["decision", "risk"]);
    const ndjson = JSON.parse((await runTraceWithInput(repo, ["hook", "agent", "--adapter", "generic"], [
      JSON.stringify({
        session_id: "adapter-session",
        event: "note",
        message: "ndjson adapters capture streamed notes",
      }),
      JSON.stringify({
        session_id: "adapter-session",
        event: "validation",
        message: "ndjson adapters preserve streamed validation",
      }),
    ].join("\n"))).stdout);
    assert.deepEqual(ndjson.events.map((event) => event.event), ["note", "validation"]);

    const commonDir = (await git(repo, ["rev-parse", "--git-common-dir"])).stdout.trim();
    const session = await readFile(join(repo, commonDir, "trace/sessions/adapter-session.jsonl"), "utf8");
    const events = session.trim().split("\n").map((line) => JSON.parse(line));
    assert.deepEqual(events.map((event) => event.event), ["tool", "prompt", "response", "validation", "decision", "risk", "note", "validation"]);
    assert.deepEqual(events.map((event) => event.adapter), ["codex", "claude-code", "gemini", "generic", "generic", "generic", "generic", "generic"]);
    assert.match(events[0].message, /codex tool shell input=npm test/);
    assert.equal(events[1].message, "explain the storage tradeoff");
    assert.equal(events[2].message, "memory summary completed");
    assert.equal(events[3].message, "npm --prefix trace test passed");
    assert.equal(events[4].message, "batch adapters keep lifecycle ordering");
    assert.equal(events[5].message, "batch adapters must preserve risk events");
    assert.equal(events[6].message, "ndjson adapters capture streamed notes");
    assert.equal(events[7].message, "ndjson adapters preserve streamed validation");

    const listed = JSON.parse((await runTrace(repo, ["session", "list"])).stdout);
    assert.equal(listed.current, "adapter-session");
    assert.equal(listed.sessions[0].session, "adapter-session");
    assert.equal(listed.sessions[0].events, 8);
    assert.deepEqual(listed.sessions[0].counts, { tool: 1, prompt: 1, response: 1, validation: 2, decision: 1, risk: 1, note: 1 });
    assert.deepEqual(listed.sessions[0].adapters, ["claude-code", "codex", "gemini", "generic"]);

    const current = JSON.parse((await runTrace(repo, ["session", "current"])).stdout);
    assert.equal(current.current, "adapter-session");

    const shown = JSON.parse((await runTrace(repo, ["session", "show", "adapter-session", "--limit", "2"])).stdout);
    assert.equal(shown.session, "adapter-session");
    assert.deepEqual(shown.events.map((event) => event.event), ["note", "validation"]);

    const inferredPrompt = JSON.parse((await runTraceWithInput(repo, ["hook", "agent", "--adapter", "codex", "--dry-run"], JSON.stringify({
      session_id: "inferred-session",
      prompt: "codex prompt inferred from payload",
    }))).stdout);
    assert.equal(inferredPrompt.events[0].event, "prompt");
    assert.equal(inferredPrompt.events[0].message, "codex prompt inferred from payload");

    const agentRecap = await runTrace(repo, ["session", "recap", "adapter-session", "--field", "agents"]);
    assert.match(agentRecap.stdout, /Field: `agents`/);
    assert.match(agentRecap.stdout, /## Agents\n\n- adapter: codex\n- adapter: claude-code\n- adapter: gemini\n- adapter: generic/);

    const lifecycleRecap = JSON.parse((await runTrace(repo, ["session", "recap", "adapter-session", "--field", "lifecycle", "--json"])).stdout);
    assert.deepEqual(Object.keys(lifecycleRecap.sections), ["lifecycle"]);
    assert.deepEqual(lifecycleRecap.sections.lifecycle, ["total: 8", "prompt: 1", "response: 1", "tool: 1", "decision: 1", "validation: 2", "risk: 1", "note: 1"]);

    await git(repo, ["config", "user.name", "Trace Test"]);
    await git(repo, ["config", "user.email", "trace@example.com"]);
    await writeFile(join(repo, "adapter.txt"), "adapter\n");
    await git(repo, ["add", "adapter.txt"]);
    await git(repo, ["commit", "-m", "Add adapter memory target"]);
    await runTrace(repo, ["record", "--session", "adapter-session"]);
    const memory = (await runTrace(repo, ["show", "HEAD"])).stdout;
    assert.match(memory, /## Lifecycle\n\n- total: 8\n- prompt: 1\n- response: 1\n- tool: 1\n- decision: 1\n- validation: 2\n- risk: 1\n- note: 1/);
    assert.doesNotMatch(sectionText(memory, "Lifecycle"), /omitted/);
  } finally {
    await rm(repo, { recursive: true, force: true });
  }
});

test("documented example agent payloads are accepted by adapters", async () => {
  const repo = await tempRepo();

  try {
    await runTrace(repo, ["init"]);
    const examplesDir = join(repoRoot, "trace/examples");
    await runTraceWithInput(repo, ["hook", "agent", "--adapter", "codex"], await readFile(join(examplesDir, "codex-tool-call.json"), "utf8"));
    await runTraceWithInput(repo, ["hook", "agent", "--adapter", "claude-code"], await readFile(join(examplesDir, "claude-code-user-prompt.json"), "utf8"));
    await runTraceWithInput(repo, ["hook", "agent", "--adapter", "gemini"], await readFile(join(examplesDir, "gemini-model-response.json"), "utf8"));
    await runTraceWithInput(repo, ["hook", "agent", "--adapter", "generic"], await readFile(join(examplesDir, "generic-validation.json"), "utf8"));

    const commonDir = (await git(repo, ["rev-parse", "--git-common-dir"])).stdout.trim();
    const session = await readFile(join(repo, commonDir, "trace/sessions/example-session.jsonl"), "utf8");
    const events = session.trim().split("\n").map((line) => JSON.parse(line));
    assert.deepEqual(events.map((event) => event.event), ["tool", "prompt", "response", "validation"]);
    assert.match(events[0].message, /codex tool shell input=npm --prefix trace test/);
    assert.match(events[1].message, /Trace memory storage model/);
    assert.match(events[2].message, /verified the Trace tests/);
    assert.match(events[3].message, /npm --prefix trace test passed/);
  } finally {
    await rm(repo, { recursive: true, force: true });
  }
});

test("agent hook dry-run normalizes payloads without writing local session state", async () => {
  const repo = await tempRepo();

  try {
    const payload = JSON.stringify({
      session_id: "dry-run-session",
      type: "tool_call",
      tool_name: "shell",
      arguments: "GITHUB_TOKEN=visible-secret npm --prefix trace test",
    });
    const preview = JSON.parse((await runTraceWithInput(repo, ["hook", "agent", "--adapter", "codex", "--dry-run"], payload)).stdout);
    assert.equal(preview.ok, true);
    assert.equal(preview.schema_version, "trace.agent_hook_result.v1");
    assert.equal(preview.dryRun, true);
    assert.equal(preview.events.length, 1);
    assert.equal(preview.events[0].schema_version, "trace.event.v1");
    assert.equal(preview.events[0].session_id, "dry-run-session");
    assert.equal(preview.events[0].event, "tool");
    assert.equal(preview.events[0].adapter, "codex");
    assert.match(preview.events[0].message, /GITHUB_TOKEN=REDACTED/);

    const status = await git(repo, ["status", "--short"]);
    assert.equal(status.stdout, "");
    const commonDir = (await git(repo, ["rev-parse", "--git-common-dir"])).stdout.trim();
    const missingSession = await run(repo, ["test", "!", "-e", join(repo, commonDir, "trace/sessions/dry-run-session.jsonl")], fixedEnv);
    assert.equal(missingSession.exitCode, 0);
  } finally {
    await rm(repo, { recursive: true, force: true });
  }
});

test("capture rejects unsupported lifecycle events", async () => {
  const repo = await tempRepo();

  try {
    await runTrace(repo, ["init"]);
    const preview = JSON.parse((await runTrace(repo, [
      "capture",
      "--event",
      "risk",
      "--session",
      "manual-dry-run",
      "--message",
      "GITHUB_TOKEN=visible-secret",
      "--dry-run",
    ])).stdout);
    assert.equal(preview.schema_version, "trace.capture_result.v1");
    assert.equal(preview.dryRun, true);
    assert.equal(preview.session, "manual-dry-run");
    assert.equal(preview.preview.event, "risk");
    assert.match(preview.preview.message, /GITHUB_TOKEN=REDACTED/);
    const commonDir = (await git(repo, ["rev-parse", "--git-common-dir"])).stdout.trim();
    const missingSession = await run(repo, ["test", "!", "-e", join(repo, commonDir, "trace/sessions/manual-dry-run.jsonl")], fixedEnv);
    assert.equal(missingSession.exitCode, 0);

    const rejected = await runTraceAllowFailure(repo, ["capture", "--event", "memory", "--message", "bad event"]);
    assert.equal(rejected.exitCode, 1);
    assert.match(rejected.stderr, /unsupported capture event memory/);
  } finally {
    await rm(repo, { recursive: true, force: true });
  }
});

test("agent hook expands structured lifecycle memory fields", async () => {
  const repo = await tempRepo();

  try {
    await git(repo, ["config", "user.name", "Trace Test"]);
    await git(repo, ["config", "user.email", "trace@example.com"]);
    await writeFile(join(repo, "structured.txt"), "structured\n");
    await git(repo, ["add", "structured.txt"]);
    await git(repo, ["commit", "-m", "Add structured memory target"]);
    await runTrace(repo, ["init"]);

    const captured = JSON.parse((await runTraceWithInput(repo, ["hook", "agent", "--adapter", "generic"], JSON.stringify({
      session_id: "structured-session",
      event: "response",
      message: "implemented structured lifecycle fanout",
      decisions: ["Use structured fields as durable memory ingredients"],
      validations: ["npm --prefix trace test passed"],
      risks: ["Review adapter payload mapping before release"],
    }))).stdout);
    assert.equal(captured.schema_version, "trace.agent_hook_result.v1");
    assert.equal(captured.dryRun, false);
    assert.deepEqual(captured.events.map((event) => event.event), ["response", "decision", "validation", "risk"]);

    await runTrace(repo, ["record", "--session", "structured-session"]);
    const memory = (await runTrace(repo, ["show", "HEAD"])).stdout;
    assert.match(memory, /## Summary\n\n- implemented structured lifecycle fanout/);
    assert.match(memory, /## Decisions\n\n- Use structured fields as durable memory ingredients/);
    assert.match(memory, /## Validation\n\n- npm --prefix trace test passed/);
    assert.match(memory, /## Risks\n\n- Review adapter payload mapping before release/);
    assert.match(memory, /## Handoff\n\n- Preserve the decision: Use structured fields as durable memory ingredients/);

    const structuredOnly = JSON.parse((await runTraceWithInput(repo, ["hook", "agent", "--adapter", "generic"], JSON.stringify({
      session_id: "structured-only-session",
      decisions: ["Keep structured-only payloads concise"],
      validations: ["npm --prefix trace test"],
      risks: ["Avoid synthetic JSON note events"],
    }))).stdout);
    assert.deepEqual(structuredOnly.events.map((event) => event.event), ["decision", "validation", "risk"]);

    const commonDir = (await git(repo, ["rev-parse", "--git-common-dir"])).stdout.trim();
    const structuredOnlySession = await readFile(join(repo, commonDir, "trace/sessions/structured-only-session.jsonl"), "utf8");
    assert.doesNotMatch(structuredOnlySession, /"event":"note"/);
    assert.doesNotMatch(structuredOnlySession, /"decisions":/);
  } finally {
    await rm(repo, { recursive: true, force: true });
  }
});

test("record extracts labeled memory signals from agent responses", async () => {
  const repo = await tempRepo();

  try {
    await git(repo, ["config", "user.name", "Trace Test"]);
    await git(repo, ["config", "user.email", "trace@example.com"]);
    await writeFile(join(repo, "signals.txt"), "signals\n");
    await git(repo, ["add", "signals.txt"]);
    await git(repo, ["commit", "-m", "Add signal extraction target"]);
    await runTrace(repo, ["init"]);

    await runTraceWithInput(repo, ["hook", "agent", "--adapter", "generic"], JSON.stringify({
      session_id: "signal-session",
      event: "response",
      message: [
        "Implemented signal extraction.",
        "Intent: preserve labeled agent memory",
        "Decision:",
        "- Promote labeled response lines into durable memory",
        "Validation: npm --prefix trace test",
        "Risk - Keep extraction line-based and predictable",
      ].join("\n"),
    }));

    const sessionCheck = JSON.parse((await runTrace(repo, ["session", "check", "signal-session", "--strict", "--json"])).stdout);
    assert.equal(sessionCheck.ok, true);
    assert.equal(sessionCheck.checks.find((check) => check.name === "intent").ok, true);
    assert.equal(sessionCheck.checks.find((check) => check.name === "decisions").ok, true);
    assert.equal(sessionCheck.checks.find((check) => check.name === "validation").ok, true);

    await runTrace(repo, ["record", "--session", "signal-session", "--check-session", "--strict"]);
    const memory = (await runTrace(repo, ["show", "HEAD"])).stdout;
    assert.match(memory, /## Intent\n\npreserve labeled agent memory/);
    assert.match(memory, /## Decisions\n\n- Promote labeled response lines into durable memory/);
    assert.match(memory, /## Validation\n\n- npm --prefix trace test/);
    assert.match(memory, /## Risks\n\n- Keep extraction line-based and predictable/);

    const strictMemoryCi = JSON.parse((await runTrace(repo, ["ci", "HEAD", "--strict-memory"])).stdout);
    assert.equal(strictMemoryCi.ok, true);
    assert.equal(strictMemoryCi.memoryQuality.ok, true);
  } finally {
    await rm(repo, { recursive: true, force: true });
  }
});

test("agent command validates names and reports malformed configs", async () => {
  const repo = await tempRepo();

  try {
    const missing = await runTraceAllowFailure(repo, ["agent", "add"]);
    assert.equal(missing.exitCode, 1);
    assert.match(missing.stderr, /agent name is required/);

    const unsupported = await runTraceAllowFailure(repo, ["agent", "add", "unknown"]);
    assert.equal(unsupported.exitCode, 1);
    assert.match(unsupported.stderr, /unsupported agent unknown/);

    await runTrace(repo, ["init"]);
    await mkdir(join(repo, ".trace/agents"), { recursive: true });
    await writeFile(join(repo, ".trace/agents/bad.json"), "{bad json");
    const listed = await runTrace(repo, ["agent", "list"]);
    const payload = JSON.parse(listed.stdout);
    assert.equal(payload.agents[0].agent, "bad");
    assert.equal(payload.agents[0].valid, false);
    assert.match(payload.agents[0].errors[0], /JSON/);

    await writeFile(join(repo, ".trace/agents/codex.json"), JSON.stringify({
      schema_version: "trace.agent.v1",
      agent: "codex",
      adapter: "generic",
      command: "trace hook agent --adapter generic",
      events: ["prompt"],
      stdin: "json",
      contract: {
        fixture: "examples/wrong.json",
        event: "prompt",
        message_includes: ["wrong"],
      },
    }, null, 2));
    const invalid = JSON.parse((await runTrace(repo, ["agent", "list"])).stdout);
    const codex = invalid.agents.find((agent) => agent.agent === "codex");
    assert.equal(codex.valid, false);
    assert.ok(codex.errors.some((error) => error.includes("adapter must match")));
    assert.ok(codex.errors.some((error) => error.includes("events missing")));
    assert.ok(codex.errors.some((error) => error.includes("contract fixture")));
    assert.ok(codex.errors.some((error) => error.includes("contract event")));

    const checked = await runTraceAllowFailure(repo, ["agent", "check", "codex"]);
    assert.equal(checked.exitCode, 1);
    const checkedPayload = JSON.parse(checked.stdout);
    assert.equal(checkedPayload.ok, false);
    assert.ok(checkedPayload.agents[0].errors.some((error) => error.includes("adapter must match")));

    const doctor = await runTraceAllowFailure(repo, ["doctor"]);
    assert.equal(doctor.exitCode, 1);
    const doctorPayload = JSON.parse(doctor.stdout);
    const agents = doctorPayload.checks.find((check) => check.name === "agents");
    assert.equal(agents.ok, false);
    assert.ok(agents.invalidAgents.some((agent) => agent.agent === "codex"));
  } finally {
    await rm(repo, { recursive: true, force: true });
  }
});

test("generated agent command captures source without treating it as event", async () => {
  const repo = await tempRepo();

  try {
    await runTrace(repo, ["agent", "add", "codex"]);
    await runTraceWithInput(repo, ["hook", "agent", "--source", "codex"], "plain hook payload");

    const commonDir = (await git(repo, ["rev-parse", "--git-common-dir"])).stdout.trim();
    const sessionId = (await readFile(join(repo, commonDir, "trace/current_session"), "utf8")).trim();
    const session = await readFile(join(repo, commonDir, `trace/sessions/${sessionId}.jsonl`), "utf8");
    const event = JSON.parse(session.trim());
    assert.equal(event.event, "note");
    assert.equal(event.source, "codex");
    assert.equal(event.adapter, "codex");
    assert.equal(event.message, "plain hook payload");
  } finally {
    await rm(repo, { recursive: true, force: true });
  }
});

test("enable installs git hooks that link commits and write post-commit memory", async () => {
  const repo = await tempRepo();

  try {
    await git(repo, ["config", "user.name", "Trace Test"]);
    await git(repo, ["config", "user.email", "trace@example.com"]);
    await runTrace(repo, ["enable"]);
    await runTrace(repo, ["capture", "--event", "prompt", "--role", "user", "--message", "hook captured intent"]);
    await writeFile(join(repo, "feature.txt"), "feature\n");
    await git(repo, ["add", "feature.txt"]);
    await git(repo, ["commit", "-m", "Add feature"]);

    const body = await git(repo, ["log", "-1", "--format=%B"]);
    assert.match(body.stdout, /Trace-Checkpoint: [0-9a-f]{12}/);
    assert.match(body.stdout, /Trace-Session: /);

    const sha = (await git(repo, ["rev-parse", "HEAD"])).stdout.trim();
    const memory = await readFile(join(repo, ".trace/commits", sha.slice(0, 2), `${sha}.md`), "utf8");
    assert.match(memory, /hook captured intent/);

    const status = await runTrace(repo, ["status"]);
    const payload = JSON.parse(status.stdout);
    assert.equal(payload.hooks.preCommit, true);
    assert.equal(payload.hooks.prepareCommitMsg, true);
    assert.equal(payload.hooks.postCommit, true);
    assert.equal(payload.hooks.details.preCommit.valid, true);
    assert.equal(payload.hooks.details.prepareCommitMsg.valid, true);
    assert.equal(payload.hooks.details.postCommit.valid, true);
    assert.match(payload.hooks.details.postCommit.command, /trace\.mjs'? hook post-commit/);
  } finally {
    await rm(repo, { recursive: true, force: true });
  }
});

test("enable disable and doctor validate managed hook bodies", async () => {
  const repo = await tempRepo();

  try {
    await git(repo, ["config", "user.name", "Trace Test"]);
    await git(repo, ["config", "user.email", "trace@example.com"]);
    const hookPath = join(repo, ".git/hooks/post-commit");
    await writeFile(hookPath, "#!/bin/sh\nprintf existing-hook\\n\n");

    await runTrace(repo, ["enable"]);
    await runTrace(repo, ["enable"]);
    const enabled = await readFile(hookPath, "utf8");
    assert.equal(enabled.match(/# trace:start/g)?.length, 1);
    assert.match(enabled, /printf existing-hook/);

    await writeFile(hookPath, enabled.replace(/hook post-commit "\$@"/, "hook unknown \"$@\""));
    const doctor = await runTraceAllowFailure(repo, ["doctor"]);
    assert.equal(doctor.exitCode, 1);
    const doctorPayload = JSON.parse(doctor.stdout);
    const hooks = doctorPayload.checks.find((check) => check.name === "hooks");
    assert.equal(hooks.ok, false);
    assert.equal(hooks.postCommit, true);
    assert.equal(hooks.details.postCommit.valid, false);

    await runTrace(repo, ["enable"]);
    await runTrace(repo, ["disable"]);
    const disabled = await readFile(hookPath, "utf8");
    assert.doesNotMatch(disabled, /# trace:start/);
    assert.match(disabled, /printf existing-hook/);
  } finally {
    await rm(repo, { recursive: true, force: true });
  }
});

test("managed pre-commit hook rejects staged raw Trace transcript files", async () => {
  const repo = await tempRepo();

  try {
    await git(repo, ["config", "user.name", "Trace Test"]);
    await git(repo, ["config", "user.email", "trace@example.com"]);
    await runTrace(repo, ["enable"]);
    await mkdir(join(repo, ".trace/sessions"), { recursive: true });
    await writeFile(join(repo, ".trace/sessions/leak.jsonl"), "{\"message\":\"full transcript\"}\n");
    await git(repo, ["add", ".trace/sessions/leak.jsonl"]);

    const blocked = await run(repo, ["git", "commit", "-m", "Commit leaked Trace transcript"], fixedEnv);
    assert.equal(blocked.exitCode, 1);
    assert.match(blocked.stderr, /Trace blocked unsafe raw memory files/);
    assert.match(blocked.stderr, /\.trace\/sessions\/leak\.jsonl/);

    await git(repo, ["rm", "--cached", ".trace/sessions/leak.jsonl"]);
    await writeFile(join(repo, "safe.txt"), "safe\n");
    await git(repo, ["add", "safe.txt"]);
    await git(repo, ["commit", "-m", "Commit safe file"]);
  } finally {
    await rm(repo, { recursive: true, force: true });
  }
});

async function tempRepo() {
  const repo = await mkdtemp(join(tmpdir(), "trace-test-"));
  await git(repo, ["init", "-b", "main"]);
  return repo;
}

async function runTrace(cwd, args) {
  const result = await run(cwd, ["node", cliPath, ...args], fixedEnv);
  assert.equal(result.exitCode, 0, `${args.join(" ")}\nstdout:\n${result.stdout}\nstderr:\n${result.stderr}`);
  return result;
}

async function runTraceWithInput(cwd, args, input) {
  const result = await run(cwd, ["node", cliPath, ...args], fixedEnv, input);
  assert.equal(result.exitCode, 0, `${args.join(" ")}\nstdout:\n${result.stdout}\nstderr:\n${result.stderr}`);
  return result;
}

async function runTraceAllowFailure(cwd, args) {
  return run(cwd, ["node", cliPath, ...args], fixedEnv);
}

async function git(cwd, args) {
  const result = await run(cwd, ["git", ...args], fixedEnv);
  assert.equal(result.exitCode, 0, `git ${args.join(" ")}\nstdout:\n${result.stdout}\nstderr:\n${result.stderr}`);
  return result;
}

async function gitWithEnv(cwd, args, env) {
  const result = await run(cwd, ["git", ...args], { ...fixedEnv, ...env });
  assert.equal(result.exitCode, 0, `git ${args.join(" ")}\nstdout:\n${result.stdout}\nstderr:\n${result.stderr}`);
  return result;
}

function sectionText(markdown, name) {
  const match = markdown.match(new RegExp(`^## ${name}\\n\\n([\\s\\S]*?)(?=\\n## |\\n?$)`, "m"));
  return match?.[1] ?? "";
}

async function run(cwd, command, env = process.env, input = null) {
  return new Promise((resolveRun) => {
    const child = spawn(command[0], command.slice(1), { cwd, env, stdio: ["pipe", "pipe", "pipe"] });
    let stdout = "";
    let stderr = "";
    child.stdout.on("data", (chunk) => { stdout += chunk; });
    child.stderr.on("data", (chunk) => { stderr += chunk; });
    child.on("close", (exitCode) => resolveRun({ exitCode, stdout, stderr }));
    if (input != null) {
      child.stdin.end(input);
    } else {
      child.stdin.end();
    }
  });
}
