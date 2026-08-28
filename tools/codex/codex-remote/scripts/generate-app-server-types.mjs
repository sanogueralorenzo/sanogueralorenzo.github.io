#!/usr/bin/env node
import { spawnSync } from "node:child_process";
import { mkdtempSync, readdirSync, readFileSync, rmSync, statSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const scriptDir = dirname(fileURLToPath(import.meta.url));
const projectRoot = resolve(scriptDir, "..");
const outputDir = resolve(projectRoot, "src/adapters/app-server/generated");
const checkOnly = process.argv.includes("--check");

const generatedDir = checkOnly ? mkdtempSync(join(tmpdir(), "codex-app-server-types-")) : outputDir;

try {
  if (!checkOnly) {
    rmSync(outputDir, { recursive: true, force: true });
  }

  const result = spawnSync(
    "codex",
    ["app-server", "generate-ts", "--out", generatedDir, "--experimental"],
    {
      cwd: projectRoot,
      encoding: "utf8",
      stdio: ["ignore", "pipe", "pipe"],
    }
  );

  if (result.status !== 0) {
    process.stderr.write(result.stderr || result.stdout);
    process.exit(result.status ?? 1);
  }

  rewriteGeneratedImports(generatedDir);

  if (checkOnly) {
    const diffs = compareDirectories(generatedDir, outputDir);
    if (diffs.length) {
      console.error("Generated app-server protocol types are stale:");
      for (const diff of diffs.slice(0, 20)) {
        console.error(`- ${diff}`);
      }
      if (diffs.length > 20) {
        console.error(`- ... ${diffs.length - 20} more`);
      }
      console.error("Run: npm run generate:app-server-types");
      process.exit(1);
    }
  }
} finally {
  if (checkOnly) {
    rmSync(generatedDir, { recursive: true, force: true });
  }
}

function rewriteGeneratedImports(root) {
  for (const file of listFiles(root)) {
    if (!file.endsWith(".ts")) {
      continue;
    }
    const source = readFileSync(file, "utf8");
    const next = source.replace(
      /((?:import|export) type [^;]+ from ")(\.[^"]+?)(";)/g,
      (_match, prefix, specifier, suffix) => {
        if (specifier.endsWith(".js")) {
          return `${prefix}${specifier}${suffix}`;
        }
        return `${prefix}${specifier}.js${suffix}`;
      }
    ).replace(
      /(export \* as \w+ from ")(\.[^"]+?)(";)/g,
      (_match, prefix, specifier, suffix) => {
        if (specifier.endsWith(".js")) {
          return `${prefix}${specifier}${suffix}`;
        }
        if (specifier.endsWith("/v2")) {
          return `${prefix}${specifier}/index.js${suffix}`;
        }
        return `${prefix}${specifier}.js${suffix}`;
      }
    );
    if (next !== source) {
      writeFileSync(file, next);
    }
  }
}

function compareDirectories(actualRoot, expectedRoot) {
  const actualFiles = listFiles(actualRoot).map((file) => relative(actualRoot, file)).sort();
  const expectedFiles = listFiles(expectedRoot).map((file) => relative(expectedRoot, file)).sort();
  const diffs = [];
  const allFiles = new Set([...actualFiles, ...expectedFiles]);

  for (const file of [...allFiles].sort()) {
    const actualPath = join(actualRoot, file);
    const expectedPath = join(expectedRoot, file);
    const actualExists = actualFiles.includes(file);
    const expectedExists = expectedFiles.includes(file);

    if (!actualExists) {
      diffs.push(`extra committed file ${file}`);
      continue;
    }
    if (!expectedExists) {
      diffs.push(`missing committed file ${file}`);
      continue;
    }
    if (readFileSync(actualPath, "utf8") !== readFileSync(expectedPath, "utf8")) {
      diffs.push(`changed file ${file}`);
    }
  }

  return diffs;
}

function listFiles(root) {
  const entries = [];
  let children;
  try {
    children = readdirSync(root);
  } catch {
    return entries;
  }

  for (const child of children) {
    const path = join(root, child);
    const stats = statSync(path);
    if (stats.isDirectory()) {
      entries.push(...listFiles(path));
    } else if (stats.isFile()) {
      entries.push(path);
    }
  }
  return entries;
}
