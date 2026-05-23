#!/usr/bin/env node

import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { spawn } from "node:child_process";

const __dirname = dirname(fileURLToPath(import.meta.url));
const repoRoot = resolve(__dirname, "../../..");
const cliPath = join(repoRoot, "precedent/bin/precedent.mjs");
const stateDir = await mkdtemp(join(tmpdir(), "precedent-attach-example-"));

try {
  await runJson(["init", "--state-dir", stateDir, "--json"]);
  const traceOut = join(stateDir, "trace.json");
  await runJson([
    "replay",
    "--state-dir",
    stateDir,
    "--case",
    "precedent/examples/replay/webhook-case.json",
    "--trace-out",
    traceOut,
    "--json",
  ]);
  await runJson(["observe", "--state-dir", stateDir, "--trace", traceOut, "--json"]);

  const taskFile = join(stateDir, "task.txt");
  await writeFile(taskFile, "add webhook handler");
  const adapter = await runJson([
    "attach",
    "--state-dir",
    stateDir,
    "--session",
    "demo",
    "--task-file",
    taskFile,
    "--scope",
    "feature:webhooks",
    "--changed-files",
    "features/webhooks/providers/stripe.ts",
    "--json",
  ]);
  const beforeTurn = await runJsonFromCommand(adapter.adapter.beforeTurn.command);
  await runJsonFromCommand(adapter.adapter.afterValidation.command, {
    schema_version: "precedent.v1",
    hook: "validation.after_run",
    sessionId: adapter.sessionId,
    command: "pnpm test:webhooks",
    exitCode: 0,
    stdout: "passed",
  });
  await runJsonFromCommand(adapter.adapter.afterOutcome.command, {
    schema_version: "precedent.v1",
    hook: "outcome.after_task",
    sessionId: adapter.sessionId,
    success: true,
    status: "success",
    notes: "adapter example completed",
  });

  const report = await runJson(["report", "--state-dir", stateDir, "--json"]);
  process.stdout.write(`${JSON.stringify({
    sessionId: adapter.sessionId,
    contextBlock: beforeTurn.contextBlock,
    precedentHealth: report.precedentHealth,
  }, null, 2)}\n`);
} finally {
  await rm(stateDir, { force: true, recursive: true });
}

function runJsonFromCommand(command, stdinJson = null) {
  return runJson(command.slice(2), stdinJson);
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
