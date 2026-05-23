import test from "node:test";
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { mkdtemp, readFile, readdir, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const repoRoot = resolve(__dirname, "../..");
const cliPath = join(repoRoot, "precedent/bin/precedent.mjs");

test("hook and session trace storage redact secrets before persistence", async () => {
  const stateDir = await mkdtemp(join(tmpdir(), "precedent-redaction-test-"));
  const secret = "sk-live-1234567890abcdef";

  try {
    await runJson(["init", "--state-dir", stateDir, "--json"]);

    await runJson(["hook", "--state-dir", stateDir, "--json"], {
      schema_version: "precedent.v1",
      hook: "context.before_turn",
      sessionId: "demo",
      task: `debug webhook with Bearer ${secret}`,
      scope: "feature:webhooks",
      changedFiles: ["features/webhooks/providers/stripe.ts"],
    });

    await runJson(["hook", "--state-dir", stateDir, "--json"], {
      schema_version: "precedent.v1",
      hook: "validation.after_run",
      sessionId: "demo",
      command: `curl -H "Authorization: Bearer ${secret}"`,
      exitCode: 1,
      stdout: `api_key=${secret}`,
      stderr: `password=${secret}`,
    });

    await runJson(["observe", "--state-dir", stateDir, "--session", "demo", "--json"]);

    const stateText = await readTreeText(stateDir);
    assert.doesNotMatch(stateText, new RegExp(secret, "u"));
    assert.match(stateText, /\[REDACTED:bearer_token\]/u);
    assert.match(stateText, /\[REDACTED:credential\]/u);
  } finally {
    await rm(stateDir, { force: true, recursive: true });
  }
});

test("run records redacted command output while preserving wrapped exit code", async () => {
  const stateDir = await mkdtemp(join(tmpdir(), "precedent-redaction-test-"));
  const secret = "ghp_1234567890abcdef1234567890abcdef1234";

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
      `process.stdout.write('${secret}'); process.stderr.write('token=${secret}'); process.exit(5)`,
    ]);

    assert.equal(result.exitCode, 5);
    assert.match(result.stdout, new RegExp(secret, "u"));

    const stateText = await readTreeText(stateDir);
    assert.doesNotMatch(stateText, new RegExp(secret, "u"));
    assert.match(stateText, /\[REDACTED:github_token\]/u);
    assert.match(stateText, /token=\[REDACTED:github_token\]/u);
  } finally {
    await rm(stateDir, { force: true, recursive: true });
  }
});

test("replay artifacts and promotion traces redact command output and precedent text", async () => {
  const stateDir = await mkdtemp(join(tmpdir(), "precedent-redaction-test-"));
  const secret = "xoxb-1234567890-secret-token";
  const caseDir = await mkdtemp(join(tmpdir(), "precedent-redaction-case-"));
  const casePath = join(caseDir, "case.json");
  const tracePath = join(stateDir, "trace.json");

  try {
    await writeFile(casePath, JSON.stringify({
      schema_version: "precedent.v1",
      id: "redaction-replay",
      task: `handle Slack token ${secret}`,
      scope: "feature:webhooks",
      baseline: {
        command: `${process.execPath} -e "process.stderr.write('${secret}'); process.exit(1)"`,
      },
      rerun: {
        command: `${process.execPath} -e "process.stdout.write('${secret}')"`,
      },
      precedent: {
        id: "prec_redaction_replay",
        scope: "feature:webhooks",
        trigger: `task mentions ${secret}`,
        lesson: `Never inject ${secret}`,
        artifact: "skill",
        paths: ["features/webhooks"],
        evidence: [`stdout contained ${secret}`],
        injection: `Do not repeat ${secret}.`,
      },
    }, null, 2));

    const replay = await runJson([
      "replay",
      "--state-dir",
      stateDir,
      "--case",
      casePath,
      "--trace-out",
      tracePath,
      "--json",
    ]);

    assert.equal(replay.replay.improved, true);
    const stateText = await readTreeText(stateDir);
    assert.doesNotMatch(stateText, new RegExp(secret, "u"));
    assert.match(stateText, /\[REDACTED:slack_token\]/u);
  } finally {
    await rm(stateDir, { force: true, recursive: true });
    await rm(caseDir, { force: true, recursive: true });
  }
});

async function readTreeText(root) {
  const chunks = [];
  const entries = await readdir(root, { withFileTypes: true });

  for (const entry of entries) {
    const path = join(root, entry.name);

    if (entry.isDirectory()) {
      chunks.push(await readTreeText(path));
      continue;
    }

    if (entry.isFile()) {
      chunks.push(await readFile(path, "utf8"));
    }
  }

  return chunks.join("\n");
}

function runJson(args, stdinJson = null) {
  return runProcess(args, stdinJson).then((result) => {
    if (result.exitCode !== 0) {
      throw new Error(`precedent ${args.join(" ")} failed\n${result.stderr}`);
    }

    return JSON.parse(result.stdout);
  });
}

function runProcess(args, stdinJson = null) {
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
