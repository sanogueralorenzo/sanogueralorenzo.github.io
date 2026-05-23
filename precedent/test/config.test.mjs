import test from "node:test";
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const repoRoot = resolve(__dirname, "../..");
const cliPath = join(repoRoot, "precedent/bin/precedent.mjs");

test("init creates deterministic versioned runtime config", async () => {
  const stateDir = await mkdtemp(join(tmpdir(), "precedent-config-test-"));

  try {
    const initialized = await runJson(["init", "--state-dir", stateDir, "--json"]);
    const config = JSON.parse(await readFile(join(stateDir, "config.json"), "utf8"));

    assert.ok(initialized.files.includes(join(stateDir, "config.json")));
    assert.deepEqual(config, {
      enabledHooks: [
        "context.before_turn",
        "validation.after_run",
        "diff.after_edit",
        "outcome.after_task",
      ],
      failurePolicy: "fail_open",
      hookTimeoutMs: 1500,
      maxInjections: 2,
      redaction: {
        enabled: true,
      },
      retentionDays: 30,
      schema_version: "precedent.config.v1",
      stateDir,
    });
  } finally {
    await rm(stateDir, { force: true, recursive: true });
  }
});

test("invalid config schema fails with an exact field error", async () => {
  const stateDir = await mkdtemp(join(tmpdir(), "precedent-config-test-"));

  try {
    await writeFile(join(stateDir, "config.json"), JSON.stringify({ stateDir }));

    const result = await runProcess(["report", "--state-dir", stateDir, "--json"]);

    assert.equal(result.exitCode, 1);
    assert.match(result.stderr, /config\.schema_version must be "precedent\.config\.v1"/u);
  } finally {
    await rm(stateDir, { force: true, recursive: true });
  }
});

test("PRECEDENT_CONFIG supplies defaults for state dir and injection limit", async () => {
  const stateDir = await mkdtemp(join(tmpdir(), "precedent-config-state-"));
  const configDir = await mkdtemp(join(tmpdir(), "precedent-config-file-"));
  const configPath = join(configDir, "config.json");

  try {
    await runJson(["init", "--state-dir", stateDir, "--json"]);
    await promoteWebhookPrecedent(stateDir);
    await writeFile(configPath, JSON.stringify({
      schema_version: "precedent.config.v1",
      stateDir,
      maxInjections: 1,
      hookTimeoutMs: 900,
      failurePolicy: "fail_open",
      retentionDays: 7,
      redaction: { enabled: true },
      enabledHooks: ["context.before_turn", "outcome.after_task"],
    }));

    const context = await runJson([
      "context",
      "--task",
      "add webhook handler",
      "--scope",
      "feature:webhooks",
      "--json",
    ], { PRECEDENT_CONFIG: configPath });

    assert.equal(context.injections.length, 1);
    assert.equal(context.source.limit, 1);

    const manifest = await runJson(["manifest", "--json"], { PRECEDENT_CONFIG: configPath });
    assert.equal(manifest.stateDir, stateDir);
    assert.equal(manifest.configPath, configPath);
    assert.equal(manifest.defaults.maxInjections, 1);
    assert.equal(manifest.defaults.hookTimeoutMs, 900);
    assert.equal(manifest.hooks["context.before_turn"].timeoutMs, 900);
    assert.match(manifest.configHash, /^[a-f0-9]{64}$/u);
  } finally {
    await rm(stateDir, { force: true, recursive: true });
    await rm(configDir, { force: true, recursive: true });
  }
});

test("CLI flags override configured state dir and limit", async () => {
  const configuredStateDir = await mkdtemp(join(tmpdir(), "precedent-config-state-a-"));
  const cliStateDir = await mkdtemp(join(tmpdir(), "precedent-config-state-b-"));
  const configDir = await mkdtemp(join(tmpdir(), "precedent-config-file-"));
  const configPath = join(configDir, "config.json");

  try {
    await runJson(["init", "--state-dir", configuredStateDir, "--json"]);
    await runJson(["init", "--state-dir", cliStateDir, "--json"]);
    await promoteWebhookPrecedent(cliStateDir);
    await writeFile(configPath, JSON.stringify({
      schema_version: "precedent.config.v1",
      stateDir: configuredStateDir,
      maxInjections: 2,
    }));

    const context = await runJson([
      "context",
      "--state-dir",
      cliStateDir,
      "--task",
      "add webhook handler",
      "--scope",
      "feature:webhooks",
      "--limit",
      "1",
      "--json",
    ], { PRECEDENT_CONFIG: configPath });

    assert.equal(context.injections.length, 1);
    assert.equal(context.source.limit, 1);
    assert.equal(context.source.command, "context");
  } finally {
    await rm(configuredStateDir, { force: true, recursive: true });
    await rm(cliStateDir, { force: true, recursive: true });
    await rm(configDir, { force: true, recursive: true });
  }
});

async function promoteWebhookPrecedent(stateDir) {
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
}

function runJson(args, env = {}) {
  return runProcess(args, env).then((result) => {
    if (result.exitCode !== 0) {
      throw new Error(`precedent ${args.join(" ")} failed\n${result.stderr}`);
    }

    return JSON.parse(result.stdout);
  });
}

function runProcess(args, env = {}) {
  return new Promise((resolvePromise, reject) => {
    const child = spawn(process.execPath, [cliPath, ...args], {
      cwd: repoRoot,
      env: { ...process.env, ...env },
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
