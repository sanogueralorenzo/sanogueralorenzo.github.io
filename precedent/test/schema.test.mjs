import test from "node:test";
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const repoRoot = resolve(__dirname, "../..");
const cliPath = join(repoRoot, "precedent/bin/precedent.mjs");

test("observe rejects traces without the v1 schema version", async () => {
  const stateDir = await mkdtemp(join(tmpdir(), "precedent-schema-test-"));

  try {
    const tracePath = join(stateDir, "trace.json");
    await writeFile(tracePath, JSON.stringify({ id: "missing-schema" }));

    const result = await runPrecedent(["observe", "--state-dir", stateDir, "--trace", tracePath, "--json"]);

    assert.equal(result.exitCode, 1);
    assert.match(result.stderr, /trace\.schema_version must be "precedent\.v1"/u);
  } finally {
    await rm(stateDir, { force: true, recursive: true });
  }
});

test("hook rejects events without the v1 schema version", async () => {
  const result = await runPrecedent(["hook", "--json"], {
    hook: "context.before_turn",
    task: "add webhook handler",
  });

  assert.equal(result.exitCode, 1);
  assert.match(result.stderr, /event\.schema_version must be "precedent\.v1"/u);
});

test("replay rejects cases without the v1 schema version", async () => {
  const stateDir = await mkdtemp(join(tmpdir(), "precedent-schema-test-"));

  try {
    const casePath = join(stateDir, "case.json");
    await writeFile(casePath, JSON.stringify({
      id: "missing-schema",
      baseline: { command: "true" },
      rerun: { command: "true" },
      precedent: {
        id: "prec_missing_schema",
        scope: "repo",
        trigger: "anything",
        lesson: "anything",
        artifact: "skill",
        injection: "anything",
      },
    }));

    const result = await runPrecedent(["replay", "--state-dir", stateDir, "--case", casePath, "--json"]);

    assert.equal(result.exitCode, 1);
    assert.match(result.stderr, /case\.schema_version must be "precedent\.v1"/u);
  } finally {
    await rm(stateDir, { force: true, recursive: true });
  }
});

function runPrecedent(args, stdinJson = null) {
  return new Promise((resolvePromise, reject) => {
    const child = spawn(process.execPath, [cliPath, ...args], {
      cwd: repoRoot,
      stdio: ["pipe", "pipe", "pipe"],
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

    if (stdinJson) {
      child.stdin.end(`${JSON.stringify(stdinJson)}\n`);
    } else {
      child.stdin.end();
    }
  });
}
