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

test("preflight leaves unmatched prompts unchanged", async () => {
  const stateDir = await mkdtemp(join(tmpdir(), "precedent-preflight-test-"));

  try {
    const result = await runProcess([
      "preflight",
      "--state-dir",
      stateDir,
      "--prompt",
      "summarize the release checklist",
      "--session",
      "plain-session",
      "--event-prefix",
      "plain-1",
    ]);

    assert.equal(result.exitCode, 0);
    assert.equal(result.stderr, "");
    assert.equal(result.stdout, "summarize the release checklist");
  } finally {
    await rm(stateDir, { force: true, recursive: true });
  }
});

test("preflight prepends acknowledged context and stays idempotent", async () => {
  const stateDir = await mkdtemp(join(tmpdir(), "precedent-preflight-test-"));

  try {
    await promoteWebhookPrecedent(stateDir);

    const args = [
      "preflight",
      "--state-dir",
      stateDir,
      "--prompt",
      "add webhook handler",
      "--scope",
      "feature:webhooks",
      "--changed-files",
      "features/webhooks/providers/stripe.ts",
      "--session",
      "preflight-session",
      "--event-prefix",
      "delivery-1",
      "--json",
    ];
    const first = await runJson(args);
    const retry = await runJson(args);

    assert.equal(first.schema_version, "precedent.preflight.v1");
    assert.equal(first.originalPrompt, "add webhook handler");
    assert.match(first.prompt, /^Precedent:/u);
    assert.match(first.prompt, /\n\nadd webhook handler$/u);
    assert.deepEqual(first.attributedPrecedents, ["prec_webhook_replay_boundary"]);
    assert.match(first.deliveryId, /^del_[a-f0-9]+$/u);
    assert.equal(first.contextBlockHash, first.beforeTurn.contextBlockHash);
    assert.equal(first.injectionAck.status, "accepted");
    assert.equal(first.injectionAck.ack.contextInjectionAck.status, "accepted");
    assert.equal(first.beforeTurn.recorded, true);
    assert.equal(first.observation.recorded, true);

    assert.equal(retry.prompt, first.prompt);
    assert.equal(retry.deliveryId, first.deliveryId);
    assert.equal(retry.beforeTurn.deduped, true);
    assert.equal(retry.observation.deduped, true);
    assert.equal(retry.injectionAck.ack.deduped, true);

    const events = (await readFile(join(stateDir, "sessions/preflight-session.jsonl"), "utf8"))
      .trim()
      .split("\n")
      .map((line) => JSON.parse(line));
    assert.deepEqual(events.map((event) => event.hook), [
      "conversation.observe",
      "context.export",
      "context.after_inject",
    ]);
  } finally {
    await rm(stateDir, { force: true, recursive: true });
  }
});

test("preflight acknowledges observed conversation context", async () => {
  const stateDir = await mkdtemp(join(tmpdir(), "precedent-preflight-test-"));

  try {
    const args = [
      "preflight",
      "--state-dir",
      stateDir,
      "--prompt",
      "Use pnpm test:webhooks, not pnpm test.",
      "--scope",
      "feature:webhooks",
      "--changed-files",
      "features/webhooks/providers/stripe.ts",
      "--session",
      "observed-preflight-session",
      "--event-prefix",
      "observed-delivery-1",
      "--json",
    ];
    const first = await runJson(args);
    const retry = await runJson(args);

    assert.match(first.prompt, /^Precedent correction:/u);
    assert.equal(first.beforeTurn.deliveryReceipt, null);
    assert.equal(first.injectionAck.status, "not_needed");
    assert.equal(first.observationAck.status, "accepted");
    assert.equal(first.observationAck.ack.contextInjectionAck.contextBlockHash, first.observation.contextBlockHash);
    assert.equal(retry.observationAck.ack.deduped, true);

    const events = (await readFile(join(stateDir, "sessions/observed-preflight-session.jsonl"), "utf8"))
      .trim()
      .split("\n")
      .map((line) => JSON.parse(line));
    assert.deepEqual(events.map((event) => event.hook), [
      "conversation.observe",
      "context.export",
      "context.after_inject",
    ]);
    assert.equal(events[2].deliveryId, first.observation.deliveryReceipt.deliveryId);
  } finally {
    await rm(stateDir, { force: true, recursive: true });
  }
});

async function promoteWebhookPrecedent(stateDir) {
  const traceOut = join(stateDir, "webhook-replay-trace.json");
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
  await runJson([
    "observe",
    "--state-dir",
    stateDir,
    "--trace",
    traceOut,
    "--json",
  ]);
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
