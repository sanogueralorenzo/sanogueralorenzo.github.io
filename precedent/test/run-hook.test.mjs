import test from "node:test";
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { mkdtemp, readFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const repoRoot = resolve(__dirname, "../..");
const cliPath = join(repoRoot, "precedent/bin/precedent.mjs");

test("run captures successful validation output into a session", async () => {
  const stateDir = await mkdtemp(join(tmpdir(), "precedent-run-test-"));

  try {
    const result = await runProcess([
      "run",
      "--state-dir",
      stateDir,
      "--session",
      "demo",
      "--",
      process.execPath,
      "-e",
      "process.stdout.write('pass output')",
    ]);

    assert.equal(result.exitCode, 0);
    assert.equal(result.stdout, "pass output");

    const events = await readJsonLines(join(stateDir, "sessions/demo.jsonl"));
    assert.equal(events.length, 1);
    assert.equal(events[0].hook, "validation.after_run");
    assert.equal(events[0].exitCode, 0);
    assert.match(events[0].command, /pass output/u);
    assert.equal(events[0].stdoutSummary, "pass output");
    assert.match(events[0].stdoutPath, /validation_after_run\.stdout\.txt$/u);

    const observed = await runJson(["observe", "--state-dir", stateDir, "--session", "demo", "--json"]);
    assert.equal(observed.observed.traceId, "session-demo");
    assert.equal(observed.observed.failures.length, 0);
  } finally {
    await rm(stateDir, { force: true, recursive: true });
  }
});

test("run captures failed validation output and preserves exit code", async () => {
  const stateDir = await mkdtemp(join(tmpdir(), "precedent-run-test-"));

  try {
    const result = await runProcess([
      "run",
      "--state-dir",
      stateDir,
      "--session",
      "demo",
      "--",
      process.execPath,
      "-e",
      "process.stderr.write('fail output'); process.exit(7)",
    ]);

    assert.equal(result.exitCode, 7);
    assert.equal(result.stderr, "fail output");

    const events = await readJsonLines(join(stateDir, "sessions/demo.jsonl"));
    assert.equal(events.length, 1);
    assert.equal(events[0].exitCode, 7);
    assert.deepEqual(events[0].failureSignals, ["non_zero_exit", "stderr_output"]);
    assert.equal(events[0].stderrSummary, "fail output");
    assert.match(events[0].stderrPath, /validation_after_run\.stderr\.txt$/u);

    const observed = await runJson(["observe", "--state-dir", stateDir, "--session", "demo", "--json"]);
    assert.match(observed.observed.failures[0], /non_zero_exit/u);
  } finally {
    await rm(stateDir, { force: true, recursive: true });
  }
});

test("run requires a session id", async () => {
  const result = await runProcess([
    "run",
    "--",
    process.execPath,
    "--version",
  ]);

  assert.equal(result.exitCode, 1);
  assert.match(result.stderr, /run\.session must be a non-empty string/u);
});

function runJson(args) {
  return runProcess(args).then((result) => {
    if (result.exitCode !== 0) {
      throw new Error(`precedent ${args.join(" ")} failed\n${result.stderr}`);
    }

    return JSON.parse(result.stdout);
  });
}

function runProcess(args) {
  return new Promise((resolvePromise, reject) => {
    const child = spawn(process.execPath, [cliPath, ...args], {
      cwd: repoRoot,
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

async function readJsonLines(path) {
  const content = await readFile(path, "utf8");

  return content
    .split("\n")
    .filter((line) => line.trim().length > 0)
    .map((line) => JSON.parse(line));
}
