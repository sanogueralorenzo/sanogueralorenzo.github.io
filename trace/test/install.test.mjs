import test from "node:test";
import assert from "node:assert/strict";
import { lstat, mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { spawn } from "node:child_process";

const repoRoot = resolve(import.meta.dirname, "../..");
const installScript = join(repoRoot, "trace/install.sh");

test("install script installs updates and uninstalls trace", async () => {
  const installDir = await mkdtemp(join(tmpdir(), "trace-install-"));

  try {
    const installed = await run(["bash", installScript, "--prefix", installDir]);
    assert.equal(installed.exitCode, 0, installed.stderr);
    assert.match(installed.stdout, /Installed trace -> /);
    assert.equal((await lstat(join(installDir, "trace"))).isSymbolicLink(), true);

    const help = await run([join(installDir, "trace"), "help"]);
    assert.equal(help.exitCode, 0, help.stderr);
    assert.match(help.stdout, /Trace records compact commit memory/);

    const updated = await run(["bash", installScript, "--update", "--prefix", installDir]);
    assert.equal(updated.exitCode, 0, updated.stderr);
    assert.match(updated.stdout, /Updated trace -> /);

    const uninstalled = await run(["bash", installScript, "--uninstall", "--prefix", installDir]);
    assert.equal(uninstalled.exitCode, 0, uninstalled.stderr);
    assert.match(uninstalled.stdout, /Uninstalled trace from /);

    const repeated = await run(["bash", installScript, "--uninstall", "--prefix", installDir]);
    assert.equal(repeated.exitCode, 0, repeated.stderr);
    assert.match(repeated.stdout, /Trace is not installed at /);
  } finally {
    await rm(installDir, { recursive: true, force: true });
  }
});

test("install script rejects malformed arguments", async () => {
  const missingPrefix = await run(["bash", installScript, "--prefix"]);
  assert.equal(missingPrefix.exitCode, 1);
  assert.match(missingPrefix.stderr, /Missing value for --prefix/);

  const unknown = await run(["bash", installScript, "--bad"]);
  assert.equal(unknown.exitCode, 1);
  assert.match(unknown.stderr, /Unknown option: --bad/);
});

async function run(command) {
  return new Promise((resolveRun) => {
    const child = spawn(command[0], command.slice(1), { stdio: ["ignore", "pipe", "pipe"] });
    let stdout = "";
    let stderr = "";
    child.stdout.on("data", (chunk) => { stdout += chunk; });
    child.stderr.on("data", (chunk) => { stderr += chunk; });
    child.on("close", (exitCode) => resolveRun({ exitCode, stdout, stderr }));
  });
}
