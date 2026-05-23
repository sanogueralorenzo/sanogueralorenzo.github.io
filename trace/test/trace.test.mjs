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
    await runTrace(repo, ["capture", "--event", "prompt", "--role", "user", "--message", "remember why app text exists"]);
    await runTrace(repo, ["capture", "--event", "decision", "--message", "Use committed Markdown for reviewable memory"]);
    const record = await runTrace(repo, ["record", "--validation", "node --test"]);
    const payload = JSON.parse(record.stdout);

    assert.equal(payload.ok, true);
    assert.match(payload.memory, /^\.trace\/commits\/[0-9a-f]{2}\//);

    const show = await runTrace(repo, ["show", "HEAD"]);
    assert.match(show.stdout, /remember why app text exists/);
    assert.match(show.stdout, /Use committed Markdown/);
    assert.match(show.stdout, /node --test/);

    const search = await runTrace(repo, ["search", "reviewable"]);
    assert.match(search.stdout, /\.trace\/commits\//);

    const summary = await runTrace(repo, ["summary", "HEAD"]);
    assert.match(summary.stdout, /Trace Summary/);
    assert.match(summary.stdout, /remember why app text exists/);

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

    await runTraceWithInput(repo, ["hook", "agent", "prompt"], JSON.stringify({
      session_id: "session-json",
      agent: "codex",
      prompt: "add retry memory for service",
    }));
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
    assert.match(prBody.stdout, /Keep raw checkpoint data outside the project tree/);
    assert.match(prBody.stdout, /token=REDACTED/);
    assert.doesNotMatch(prBody.stdout, /super-secret-token/);
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
    const record = JSON.parse((await runTrace(repo, ["record", "--validation", "node --test"])).stdout);

    const listed = JSON.parse((await runTrace(repo, ["checkpoint", "list"])).stdout);
    assert.equal(listed.ok, true);
    assert.equal(listed.ref, "refs/trace/checkpoints");
    assert.equal(listed.checkpoints.length, 1);
    assert.equal(listed.checkpoints[0].checkpoint_id, record.checkpoint);
    assert.equal(listed.checkpoints[0].events, 1);

    const verified = JSON.parse((await runTrace(repo, ["checkpoint", "verify"])).stdout);
    assert.equal(verified.ok, true);
    assert.equal(verified.checked, 1);
    assert.deepEqual(verified.errors, []);

    const push = JSON.parse((await runTrace(repo, ["checkpoint", "push", "origin", "--dry-run"])).stdout);
    assert.equal(push.command, "git push origin refs/trace/checkpoints:refs/trace/checkpoints");

    const fetch = JSON.parse((await runTrace(repo, ["checkpoint", "fetch", "origin", "--dry-run"])).stdout);
    assert.equal(fetch.command, "git fetch origin refs/trace/checkpoints:refs/trace/checkpoints");

    const commonDir = (await git(repo, ["rev-parse", "--git-common-dir"])).stdout.trim();
    const sessionId = (await readFile(join(repo, commonDir, "trace/current_session"), "utf8")).trim();
    const sessionFile = join(repo, commonDir, `trace/sessions/${sessionId}.jsonl`);
    assert.match(await readFile(sessionFile, "utf8"), /checkpoint ref controls/);

    const cleanup = JSON.parse((await runTrace(repo, ["checkpoint", "cleanup", "--sessions-before-days", "0"])).stdout);
    assert.equal(cleanup.ok, true);
    assert.equal(cleanup.sessionsBeforeDays, 0);
    assert.ok(cleanup.removed.some((entry) => entry.endsWith(`${sessionId}.jsonl`)));

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
    await runTrace(repo, ["redact", "add", "codename", "PROJECT-[A-Z]+"]);
    const listed = JSON.parse((await runTrace(repo, ["redact", "list"])).stdout);
    assert.deepEqual(listed.rules, [{ label: "codename", pattern: "PROJECT-[A-Z]+" }]);

    await runTrace(repo, [
      "capture",
      "--event",
      "prompt",
      "--role",
      "user",
      "--message",
      "ship PROJECT-ORION with token=visible-secret",
    ]);
    await runTrace(repo, ["record", "--validation", "PROJECT-ORION validation"]);

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

    await runTrace(repo, ["redact", "remove", "codename"]);
    const removed = JSON.parse((await runTrace(repo, ["redact", "list"])).stdout);
    assert.deepEqual(removed.rules, []);
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
    assert.equal(addedPayload.agent, "codex");
    assert.equal(addedPayload.config, ".trace/agents/codex.json");
    assert.equal(addedPayload.command, "trace hook agent --source codex");

    const config = JSON.parse(await readFile(join(repo, ".trace/agents/codex.json"), "utf8"));
    assert.equal(config.schema_version, "trace.agent.v1");
    assert.equal(config.agent, "codex");
    assert.deepEqual(config.events, ["prompt", "decision", "validation", "risk", "note"]);

    const listed = await runTrace(repo, ["agent", "list"]);
    const listedPayload = JSON.parse(listed.stdout);
    assert.deepEqual(listedPayload.agents.map((agent) => agent.agent), ["codex"]);

    const status = await runTrace(repo, ["status"]);
    const statusPayload = JSON.parse(status.stdout);
    assert.deepEqual(statusPayload.agents.map((agent) => agent.agent), ["codex"]);

    await runTrace(repo, ["agent", "remove", "codex"]);
    const removed = await runTrace(repo, ["agent", "list"]);
    assert.deepEqual(JSON.parse(removed.stdout).agents, []);
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
    assert.match(payload.agents[0].error, /JSON/);
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
    assert.equal(event.event, "agent");
    assert.equal(event.source, "codex");
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
    assert.equal(payload.hooks.prepareCommitMsg, true);
    assert.equal(payload.hooks.postCommit, true);
  } finally {
    await rm(repo, { recursive: true, force: true });
  }
});

test("enable and disable preserve existing hook bodies", async () => {
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

    await runTrace(repo, ["disable"]);
    const disabled = await readFile(hookPath, "utf8");
    assert.doesNotMatch(disabled, /# trace:start/);
    assert.match(disabled, /printf existing-hook/);
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
