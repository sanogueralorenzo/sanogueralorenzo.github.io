#!/usr/bin/env node
import { spawnSync } from "node:child_process";
import { readFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const packageRoot = dirname(dirname(fileURLToPath(import.meta.url)));
const release = JSON.parse(await readFile(join(packageRoot, "release.json"), "utf8"));

const pack = spawnSync("npm", ["pack", "--dry-run", "--json"], {
  cwd: packageRoot,
  encoding: "utf8",
  stdio: ["ignore", "pipe", "pipe"],
});

if (pack.status !== 0) {
  process.stderr.write(pack.stderr);
  process.exit(pack.status ?? 1);
}

let manifest;
try {
  const parsed = JSON.parse(pack.stdout);
  manifest = Array.isArray(parsed) ? parsed[0] : parsed;
} catch (error) {
  process.stderr.write(`Could not parse npm pack manifest JSON: ${error.message}\n`);
  process.exit(1);
}

const packedPaths = new Set((manifest.files ?? []).map((file) => file.path));
const requiredPaths = [
  "package.json",
  "release.json",
  release.packagePublication.notes,
  release.ciAdoption.guide,
  ...release.ciAdoption.workflows.map((workflow) => workflow.path),
  ...release.packagePublication.requiredFiles,
];

const missing = [...new Set(requiredPaths)].filter((requiredPath) => {
  if (packedPaths.has(requiredPath)) {
    return false;
  }

  return ![...packedPaths].some((packedPath) => packedPath.startsWith(`${requiredPath}/`));
});

const payload = {
  ok: missing.length === 0,
  package: manifest.id,
  checked_paths: [...new Set(requiredPaths)].sort(),
  missing,
};

process.stdout.write(`${JSON.stringify(payload, null, 2)}\n`);

if (!payload.ok) {
  process.exit(1);
}
