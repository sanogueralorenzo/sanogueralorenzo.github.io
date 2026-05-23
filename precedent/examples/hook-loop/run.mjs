#!/usr/bin/env node

import { spawn } from "node:child_process";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const repoRoot = resolve(__dirname, "../../..");
const cliPath = join(repoRoot, "precedent/bin/precedent.mjs");
const eventsDir = join(__dirname, "events");
const tracesDir = join(__dirname, "traces");
const firstTurnEvent = join(eventsDir, "before-delivery-turn.json");
const followupTurnEvent = join(eventsDir, "before-refund-turn.json");
const followupTrace = join(tracesDir, "followup-webhook-turn.json");
const replayCase = join(repoRoot, "precedent/examples/replay/webhook-case.json");
const stateDir = await mkdtemp(join(tmpdir(), "precedent-hook-loop-"));
const replayTrace = join(stateDir, "webhook-replay-trace.json");

try {
  const beforeFirstTurn = await runPrecedent([
    "hook",
    "--state-dir",
    stateDir,
    "--event-file",
    firstTurnEvent,
    "--json",
  ]);

  await runPrecedent([
    "replay",
    "--state-dir",
    stateDir,
    "--case",
    replayCase,
    "--trace-out",
    replayTrace,
    "--json",
  ]);

  await runPrecedent([
    "observe",
    "--state-dir",
    stateDir,
    "--trace",
    replayTrace,
    "--json",
  ]);

  const beforeFollowupTurn = await runPrecedent([
    "hook",
    "--state-dir",
    stateDir,
    "--event-file",
    followupTurnEvent,
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

  assert(beforeFirstTurn.contextBlock === "", "first hook context block should be empty");
  assert(beforeFirstTurn.injections.length === 0, "first hook should not inject precedent");
  assert(beforeFollowupTurn.contextBlock.startsWith("Precedent:"), "follow-up hook should return a context block");
  assert(
    beforeFollowupTurn.injections.some((injection) => injection.id === "prec_webhook_replay_boundary"),
    "follow-up hook should inject webhook precedent",
  );
  assert(report.precedents === 1, "ledger should contain one promoted precedent");
  assert(report.events === 5, "ledger should contain hook, replay, and observed trace events");

  process.stdout.write(`${JSON.stringify({
    ok: true,
    hookLoop: [
      {
        hook: "context.before_turn",
        contextBlock: beforeFirstTurn.contextBlock,
        injections: beforeFirstTurn.injections,
      },
      {
        hook: "conversation.observe",
        trace: "webhook-replay-trace.json",
      },
      {
        hook: "context.before_turn",
        contextBlock: beforeFollowupTurn.contextBlock,
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
