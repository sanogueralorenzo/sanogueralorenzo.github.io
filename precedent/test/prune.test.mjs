import test from "node:test";
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { spawn } from "node:child_process";
import { appendFile, mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const repoRoot = resolve(__dirname, "../..");
const cliPath = join(repoRoot, "precedent/bin/precedent.mjs");

test("prune dry-run reports old records without mutating state", async () => {
  const stateDir = await mkdtemp(join(tmpdir(), "precedent-prune-test-"));

  try {
    await seedPruneState(stateDir);
    const before = await readFile(join(stateDir, "events.jsonl"), "utf8");
    const result = await runJson([
      "prune",
      "--state-dir",
      stateDir,
      "--before",
      "2026-01-15T00:00:00.000Z",
      "--dry-run",
      "--json",
    ]);
    const after = await readFile(join(stateDir, "events.jsonl"), "utf8");

    assert.equal(result.dryRun, true);
    assert.equal(result.removedEvents, 1);
    assert.equal(before, after);
  } finally {
    await rm(stateDir, { force: true, recursive: true });
  }
});

test("prune removes old events, session events, and replay artifacts", async () => {
  const stateDir = await mkdtemp(join(tmpdir(), "precedent-prune-test-"));

  try {
    await seedPruneState(stateDir);
    const result = await runJson([
      "prune",
      "--state-dir",
      stateDir,
      "--before",
      "2026-01-15T00:00:00.000Z",
      "--json",
    ]);

    assert.equal(result.removedEvents, 1);
    assert.equal(result.keptEvents, 1);
    assert.equal(result.removedSessionEvents, 1);
    assert.equal(result.keptSessionEvents, 1);
    assert.equal(result.removedFiles.length, 1);

    const events = await readJsonLines(join(stateDir, "events.jsonl"));
    const session = await readJsonLines(join(stateDir, "sessions/demo.jsonl"));
    const precedents = await readJsonLines(join(stateDir, "precedents.jsonl"));

    assert.deepEqual(events.map((event) => event.id), ["new-event"]);
    assert.deepEqual(session.map((event) => event.id), ["new-session"]);
    assert.equal(precedents.length, 1);

    const check = await runJson(["check", "--state-dir", stateDir, "--json"]);
    assert.equal(check.ok, true);
  } finally {
    await rm(stateDir, { force: true, recursive: true });
  }
});

async function seedPruneState(stateDir) {
  await runJson(["init", "--state-dir", stateDir, "--json"]);
  await appendFile(join(stateDir, "events.jsonl"), `${JSON.stringify({
    id: "old-event",
    observedAt: "2026-01-01T00:00:00.000Z",
  })}\n`);
  await appendFile(join(stateDir, "events.jsonl"), `${JSON.stringify({
    id: "new-event",
    observedAt: "2026-02-01T00:00:00.000Z",
  })}\n`);
  await appendFile(join(stateDir, "sessions/demo.jsonl"), `${JSON.stringify({
    id: "old-session",
    receivedAt: "2026-01-01T00:00:00.000Z",
  })}\n`);
  await appendFile(join(stateDir, "sessions/demo.jsonl"), `${JSON.stringify({
    id: "new-session",
    receivedAt: "2026-02-01T00:00:00.000Z",
  })}\n`);
  const keepReplay = `${JSON.stringify({
    id: "keep-replay",
    completedAt: "2026-02-01T00:00:00.000Z",
    baseline: { exitCode: 1 },
    rerun: { exitCode: 0 },
    promotion: {
      baseline_failures: 1,
      rerun_failures: 0,
    },
    improved: true,
  })}\n`;
  await appendFile(join(stateDir, "precedents.jsonl"), `${JSON.stringify({
    id: "prec_keep",
    promotion_status: "promoted",
    evidence: ["test evidence"],
    replay: {
      id: "keep-replay",
      path: join(stateDir, "replays/keep-replay/replay.json"),
      baseline_failures: 1,
      rerun_failures: 0,
      baseline_exit_code: 1,
      rerun_exit_code: 0,
      artifact_sha256: createHash("sha256").update(keepReplay).digest("hex"),
    },
    promotion: {
      baseline_failures: 1,
      rerun_failures: 0,
      baseline_exit_code: 1,
      rerun_exit_code: 0,
    },
  })}\n`);
  await mkdir(join(stateDir, "replays/keep-replay"), { recursive: true });
  await writeFile(join(stateDir, "replays/keep-replay/replay.json"), keepReplay);
  await mkdir(join(stateDir, "replays/old-replay"), { recursive: true });
  await writeFile(join(stateDir, "replays/old-replay/replay.json"), JSON.stringify({
    id: "old-replay",
    completedAt: "2026-01-01T00:00:00.000Z",
    baseline: { exitCode: 1 },
    rerun: { exitCode: 0 },
  }));
}

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
      resolvePromise({ exitCode, stdout, stderr });
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
