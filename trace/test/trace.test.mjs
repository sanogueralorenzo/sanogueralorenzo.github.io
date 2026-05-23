import test from "node:test";
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
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
