#!/usr/bin/env node

import { spawn } from "node:child_process";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const repoRoot = resolve(__dirname, "../../..");
const cliPath = join(repoRoot, "precedent/bin/precedent.mjs");
const tracesDir = join(__dirname, "traces");
const failedTrace = join(tracesDir, "failed-webhook-turn.json");
const followupTrace = join(tracesDir, "followup-webhook-turn.json");
const stateDir = await mkdtemp(join(tmpdir(), "precedent-hook-loop-"));

try {
  const beforeFirstTurn = await runPrecedent([
    "hook",
    "before-turn",
    "--state-dir",
    stateDir,
    "--task",
    "add a webhook handler for provider delivery events",
    "--scope",
    "feature:webhooks",
    "--json",
  ]);

  await runPrecedent([
    "observe",
    "--state-dir",
    stateDir,
    "--trace",
    failedTrace,
    "--json",
  ]);

  const beforeFollowupTurn = await runPrecedent([
    "hook",
    "before-turn",
    "--state-dir",
    stateDir,
    "--task",
    "add a webhook handler for provider refund events",
    "--scope",
    "feature:webhooks",
    "--json",
  ]);

  await runPrecedent([
    "observe",
    "--state-dir",
    stateDir,
    "--trace",
    followupTrace,
    "--json",
  ]);

  const report = await runPrecedent([
    "report",
    "--state-dir",
    stateDir,
    "--json",
  ]);

  assert(!beforeFirstTurn.injected, "first hook should not inject precedent");
  assert(beforeFirstTurn.block === "", "first hook block should be empty");
  assert(beforeFollowupTurn.injected, "follow-up hook should inject precedent");
  assert(
    beforeFollowupTurn.injections.some((injection) => injection.id === "prec_webhook_provider_boundary"),
    "follow-up hook should inject webhook precedent",
  );
  assert(report.precedents === 1, "ledger should contain one promoted precedent");
  assert(report.events === 4, "ledger should contain two hook events and two observed trace events");

  process.stdout.write(`${JSON.stringify({
    ok: true,
    hookLoop: [
      {
        hook: "context.before_turn",
        task: beforeFirstTurn.task,
        injected: beforeFirstTurn.injected,
        block: beforeFirstTurn.block,
      },
      {
        hook: "conversation.observe",
        trace: "failed-webhook-turn.json",
      },
      {
        hook: "context.before_turn",
        task: beforeFollowupTurn.task,
        injected: beforeFollowupTurn.injected,
        block: beforeFollowupTurn.block,
        injections: beforeFollowupTurn.injections,
      },
      {
        hook: "conversation.observe",
        trace: "followup-webhook-turn.json",
      },
      {
        hook: "report",
        report,
      },
    ],
  }, null, 2)}\n`);
} finally {
  await rm(stateDir, { force: true, recursive: true });
}

async function runPrecedent(args) {
  const result = await spawnNode([cliPath, ...args]);

  if (result.status !== 0) {
    throw new Error(`precedent ${args.join(" ")} failed\n${result.stderr}`);
  }

  return JSON.parse(result.stdout);
}

function spawnNode(args) {
  return new Promise((resolvePromise, reject) => {
    const child = spawn(process.execPath, args, {
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
    child.on("close", (status) => {
      resolvePromise({ status, stdout, stderr });
    });
  });
}

function assert(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}
