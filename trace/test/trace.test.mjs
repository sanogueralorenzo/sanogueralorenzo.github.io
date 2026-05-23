import test from "node:test";
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";

const repoRoot = resolve(import.meta.dirname, "../..");
const cliPath = join(repoRoot, "trace/bin/trace.mjs");
const fixedEnv = { ...process.env, TRACE_NOW: "2026-05-23T00:00:00.000Z" };

test("post-commit writes a redacted diff fallback memory automatically", async () => {
  const repo = await tempRepo();

  try {
    await git(repo, ["config", "user.name", "Trace Test"]);
    await git(repo, ["config", "user.email", "trace@example.com"]);
    await runTrace(repo, ["init"]);
    await runTrace(repo, ["enable"]);

    await writeFile(join(repo, "app.txt"), "hello\n");
    await git(repo, ["add", "app.txt"]);
    await git(repo, ["commit", "-m", "Add app text"]);

    const sha = (await git(repo, ["rev-parse", "HEAD"])).stdout.trim();
    const memoryPath = join(repo, ".trace/commits", `${sha}.md`);
    const memory = await readFile(memoryPath, "utf8");

    assert.match(memory, new RegExp(`Commit: \`${sha}\``));
    assert.match(memory, /Session: `none`/);
    assert.match(memory, /Subject: Add app text/);
    assert.match(memory, /## Intent\n\nAdd app text/);
    assert.match(memory, /app\.txt/);
    assert.match(memory, /Review the diff for "Add app text"/);

    const show = await runTrace(repo, ["show", "HEAD"]);
    assert.equal(show.stdout, memory);

    const search = JSON.parse((await runTrace(repo, ["search", "--json", "app"])).stdout);
    assert.equal(search.schema_version, "trace.search_results.v1");
    assert.equal(search.matches, 1);
    assert.equal(search.results[0].file, `.trace/commits/${sha}.md`);

    const recall = await runTrace(repo, ["recall", "--files", "app.txt"]);
    assert.match(recall.stdout, /Trace Recall/);
    assert.match(recall.stdout, /Files: `app\.txt`/);
    assert.match(recall.stdout, /Add app text/);
  } finally {
    await rm(repo, { recursive: true, force: true });
  }
});

test("codex and claude-code captures become useful commit memory", async () => {
  const repo = await tempRepo();

  try {
    await git(repo, ["config", "user.name", "Trace Test"]);
    await git(repo, ["config", "user.email", "trace@example.com"]);
    await runTrace(repo, ["init"]);
    await runTrace(repo, ["enable"]);

    const codex = JSON.parse((await runTraceWithInput(repo, ["hook", "agent", "--adapter", "codex"], JSON.stringify({
      session_id: "agent-session",
      prompt: "make Trace remember why commits changed",
    }))).stdout);
    assert.equal(codex.schema_version, "trace.agent_capture.v1");
    assert.equal(codex.adapter, "codex");
    assert.equal(codex.events[0].event, "prompt");

    const claude = JSON.parse((await runTraceWithInput(repo, ["hook", "agent", "--adapter", "claude-code"], JSON.stringify({
      session_id: "agent-session",
      decisions: ["Keep Trace to conversation plus diff into commit memory"],
      validations: ["npm --prefix trace test"],
      risks: ["token=visible-secret must be redacted"],
    }))).stdout);
    assert.equal(claude.adapter, "claude-code");
    assert.deepEqual(claude.events.map((event) => event.event), ["decision", "validation", "risk"]);

    await writeFile(join(repo, "memory.txt"), "memory\n");
    await git(repo, ["add", "memory.txt"]);
    await git(repo, ["commit", "-m", "Add commit memory fixture"]);

    const sha = (await git(repo, ["rev-parse", "HEAD"])).stdout.trim();
    const memory = await readFile(join(repo, ".trace/commits", `${sha}.md`), "utf8");
    assert.match(memory, /Session: `agent-session`/);
    assert.match(memory, /make Trace remember why commits changed/);
    assert.match(memory, /Keep Trace to conversation plus diff into commit memory/);
    assert.match(memory, /npm --prefix trace test/);
    assert.match(memory, /token=REDACTED/);
    assert.doesNotMatch(memory, /visible-secret/);
    assert.match(memory, /Preserve the decision: Keep Trace/);

    const recallJson = JSON.parse((await runTrace(repo, ["recall", "--field", "decisions", "--json", "conversation"])).stdout);
    assert.equal(recallJson.matches, 1);
    assert.match(recallJson.results[0].decisions[0], /conversation plus diff/);
  } finally {
    await rm(repo, { recursive: true, force: true });
  }
});

test("manual capture and record support review before writing memory", async () => {
  const repo = await tempRepo();

  try {
    await git(repo, ["config", "user.name", "Trace Test"]);
    await git(repo, ["config", "user.email", "trace@example.com"]);
    await runTrace(repo, ["init"]);

    await writeFile(join(repo, "manual.txt"), "manual\n");
    await git(repo, ["add", "manual.txt"]);
    await git(repo, ["commit", "-m", "Add manual memory target"]);

    await runTrace(repo, ["capture", "--session", "manual-session", "--event", "prompt", "--role", "user", "--message", "manual memory path"]);
    await runTrace(repo, ["capture", "--session", "manual-session", "--event", "decision", "--message", "Write Markdown that future agents can search"]);

    const dryRun = JSON.parse((await runTrace(repo, ["record", "--session", "manual-session", "--validation", "node --test", "--dry-run"])).stdout);
    assert.equal(dryRun.schema_version, "trace.record_result.v1");
    assert.equal(dryRun.dryRun, true);
    assert.equal(dryRun.source, "session");
    assert.match(dryRun.markdown, /manual memory path/);
    assert.match(dryRun.markdown, /Write Markdown that future agents can search/);

    const missing = await runTraceAllowFailure(repo, ["show", "HEAD"]);
    assert.equal(missing.exitCode, 1);
    assert.match(missing.stderr, /memory not found/);

    const record = JSON.parse((await runTrace(repo, ["record", "--session", "manual-session", "--validation", "node --test"])).stdout);
    assert.equal(record.session, "manual-session");
    assert.equal(record.memory, `.trace/commits/${record.commit}.md`);

    const showJson = JSON.parse((await runTrace(repo, ["show", "HEAD", "--json"])).stdout);
    assert.equal(showJson.memory.intent, "manual memory path");
    assert.deepEqual(showJson.memory.decisions, ["Write Markdown that future agents can search"]);
    assert.deepEqual(showJson.memory.validation, ["node --test"]);
  } finally {
    await rm(repo, { recursive: true, force: true });
  }
});

test("pre-commit rejects raw session files in the project tree", async () => {
  const repo = await tempRepo();

  try {
    await git(repo, ["config", "user.name", "Trace Test"]);
    await git(repo, ["config", "user.email", "trace@example.com"]);
    await runTrace(repo, ["init"]);
    await runTrace(repo, ["enable"]);

    await mkdir(join(repo, ".trace/sessions"), { recursive: true });
    await writeFile(join(repo, ".trace/sessions/leak.jsonl"), "{\"message\":\"raw\"}\n");
    await git(repo, ["add", ".trace/sessions/leak.jsonl"]);

    const blocked = await gitAllowFailure(repo, ["commit", "-m", "Try raw trace leak"]);
    assert.equal(blocked.exitCode, 1);
    assert.match(blocked.stderr, /Trace blocks raw session data/);
  } finally {
    await rm(repo, { recursive: true, force: true });
  }
});

async function tempRepo() {
  const repo = await mkdtemp(join(tmpdir(), "trace-test-"));
  await git(repo, ["init", "--initial-branch=main"]);
  return repo;
}

async function runTrace(cwd, args) {
  return run(cwd, ["node", cliPath, ...args], fixedEnv);
}

async function runTraceAllowFailure(cwd, args) {
  return run(cwd, ["node", cliPath, ...args], fixedEnv, { allowFailure: true });
}

async function runTraceWithInput(cwd, args, input) {
  return run(cwd, ["node", cliPath, ...args], fixedEnv, { input });
}

async function git(cwd, args) {
  const result = await run(cwd, ["git", ...args], fixedEnv);
  assert.equal(result.exitCode, 0, result.stderr || result.stdout);
  return result;
}

async function gitAllowFailure(cwd, args) {
  return run(cwd, ["git", ...args], fixedEnv, { allowFailure: true });
}

async function run(cwd, command, env, options = {}) {
  return new Promise((resolveRun) => {
    const child = spawn(command[0], command.slice(1), {
      cwd,
      env,
      stdio: ["pipe", "pipe", "pipe"],
    });
    let stdout = "";
    let stderr = "";
    child.stdout.on("data", (chunk) => { stdout += chunk; });
    child.stderr.on("data", (chunk) => { stderr += chunk; });
    child.on("close", (exitCode) => {
      if (!options.allowFailure) {
        assert.equal(exitCode, 0, stderr || stdout);
      }
      resolveRun({ exitCode, stdout, stderr });
    });
    child.stdin.end(options.input ?? "");
  });
}
