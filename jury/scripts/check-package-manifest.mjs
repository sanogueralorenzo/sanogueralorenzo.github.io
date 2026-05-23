#!/usr/bin/env node
import { spawnSync } from "node:child_process";
import { readFile } from "node:fs/promises";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const packageRoot = dirname(dirname(fileURLToPath(import.meta.url)));
const release = JSON.parse(await readFile(join(packageRoot, "release.json"), "utf8"));
const args = parseArgs(process.argv.slice(2));

let manifest;
try {
  const parsed = JSON.parse(args.packManifest
    ? await readFile(resolve(process.cwd(), args.packManifest), "utf8")
    : runPackDryRun());
  manifest = Array.isArray(parsed) ? parsed[0] : parsed;
} catch (error) {
  process.stderr.write(`Could not read npm pack manifest JSON: ${error.message}\n`);
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

function parseArgs(argv) {
  const parsed = { packManifest: null };

  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    if (arg === "--pack-manifest") {
      const value = argv[index + 1];
      if (!value) {
        fail("missing value for --pack-manifest");
      }
      parsed.packManifest = value;
      index += 1;
      continue;
    }

    fail(`unknown argument ${arg}`);
  }

  return parsed;
}

function runPackDryRun() {
  const pack = spawnSync("npm", ["pack", "--dry-run", "--json"], {
    cwd: packageRoot,
    encoding: "utf8",
    stdio: ["ignore", "pipe", "pipe"],
  });

  if (pack.status !== 0) {
    process.stderr.write(pack.stderr);
    process.exit(pack.status ?? 1);
  }

  return pack.stdout;
}

function fail(message) {
  process.stderr.write(`${message}\n`);
  process.exit(1);
}
