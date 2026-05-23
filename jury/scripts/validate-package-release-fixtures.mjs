#!/usr/bin/env node
import { readFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const packageRoot = dirname(dirname(fileURLToPath(import.meta.url)));
const args = parseArgs(process.argv.slice(2));
const fixtureDir = args.fixtureDir ?? join(packageRoot, "examples/ci/fixtures/package-release");
const schemaPath = join(packageRoot, "schemas/package-release-evidence.schema.json");
const schema = await readJson(schemaPath);
const rollback = await readFixture("rollback-audit.json");
const replacement = await readFixture("replacement-patch-audit.json");
const failedRecord = await readFixture("jury-pack-dry-run-record.json");
const failedNpmView = await readFixture("failed-npm-view.json");
const failedGate = await readFixture("downstream-failure-gate.json");
const replacementNpmView = await readFixture("replacement-npm-view.json");
const replacementGate = await readFixture("replacement-downstream-gate.json");
const errors = [
  ...schemaErrors(schema, rollback, "rollback-audit.json"),
  ...schemaErrors(schema, replacement, "replacement-patch-audit.json"),
  ...relationshipErrors(),
];

if (errors.length > 0) {
  process.stderr.write(`${errors.join("\n")}\n`);
  process.exit(1);
}

process.stdout.write(`${JSON.stringify({
  ok: true,
  schema: "schemas/package-release-evidence.schema.json",
  fixtures: [
    "rollback-audit.json",
    "replacement-patch-audit.json",
  ],
}, null, 2)}\n`);

async function readFixture(name) {
  return readJson(join(fixtureDir, name));
}

async function readJson(path) {
  return JSON.parse(await readFile(path, "utf8"));
}

function parseArgs(argv) {
  const parsed = { fixtureDir: null };

  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    if (arg === "--fixture-dir") {
      const value = argv[index + 1];
      if (!value) {
        fail("missing value for --fixture-dir");
      }
      parsed.fixtureDir = value;
      index += 1;
      continue;
    }

    fail(`unknown argument ${arg}`);
  }

  return parsed;
}

function schemaErrors(schemaDocument, audit, label) {
  const errors = [];
  if (schemaDocument.properties?.schema_version?.const !== "jury.package_release_evidence.v1") {
    errors.push("schema must define jury.package_release_evidence.v1");
  }
  validateSchemaObject(schemaDocument, audit, label, errors);
  return errors;
}

function validateSchemaObject(schemaNode, value, path, errors) {
  const type = schemaNode.type ?? ((schemaNode.required || schemaNode.properties || schemaNode.allOf || schemaNode.additionalProperties !== undefined) ? "object" : null);

  if (type === "object") {
    if (!value || typeof value !== "object" || Array.isArray(value)) {
      errors.push(`${path} must be an object`);
      return;
    }
    for (const key of schemaNode.required ?? []) {
      if (value[key] === undefined) {
        errors.push(`${path}.${key} is required`);
      }
    }
    for (const [key, propertySchema] of Object.entries(schemaNode.properties ?? {})) {
      if (value[key] !== undefined) {
        validateSchemaObject(propertySchema, value[key], `${path}.${key}`, errors);
      }
    }
    if (schemaNode.additionalProperties === false) {
      const allowed = new Set(Object.keys(schemaNode.properties ?? {}));
      for (const key of Object.keys(value)) {
        if (!allowed.has(key)) {
          errors.push(`${path}.${key} is not allowed`);
        }
      }
    }
    for (const clause of schemaNode.allOf ?? []) {
      if (matchesIfClause(clause.if, value)) {
        validateSchemaObject(clause.then, value, path, errors);
      }
    }
    return;
  }

  if (type === "array") {
    if (!Array.isArray(value)) {
      errors.push(`${path} must be an array`);
      return;
    }
    if (schemaNode.minItems !== undefined && value.length < schemaNode.minItems) {
      errors.push(`${path} must contain at least ${schemaNode.minItems} item`);
    }
    for (const [index, item] of value.entries()) {
      validateSchemaObject(schemaNode.items, item, `${path}[${index}]`, errors);
    }
    return;
  }

  if (type === "string") {
    if (typeof value !== "string") {
      errors.push(`${path} must be a string`);
      return;
    }
    if (schemaNode.minLength !== undefined && value.length < schemaNode.minLength) {
      errors.push(`${path} must not be empty`);
    }
    if (schemaNode.pattern && !new RegExp(schemaNode.pattern).test(value)) {
      errors.push(`${path} must match ${schemaNode.pattern}`);
    }
  }

  if (type === "boolean" && typeof value !== "boolean") {
    errors.push(`${path} must be a boolean`);
  }

  if (schemaNode.const !== undefined && value !== schemaNode.const) {
    errors.push(`${path} must equal ${schemaNode.const}`);
  }

  if (schemaNode.enum && !schemaNode.enum.includes(value)) {
    errors.push(`${path} must be one of ${schemaNode.enum.join(", ")}`);
  }
}

function matchesIfClause(clause, value) {
  if (!clause) {
    return false;
  }
  for (const key of clause.required ?? []) {
    if (value[key] === undefined) {
      return false;
    }
  }
  for (const [key, propertySchema] of Object.entries(clause.properties ?? {})) {
    if (propertySchema.const !== undefined && value[key] !== propertySchema.const) {
      return false;
    }
  }
  return true;
}

function relationshipErrors() {
  const errors = [];
  const failedTarball = failedNpmView.dist?.tarball;
  const replacementTarball = replacementNpmView.dist?.tarball;

  if (rollback.audit_type !== "failed-publication-rollback") {
    errors.push("rollback-audit.json audit_type must be failed-publication-rollback");
  }
  if (replacement.audit_type !== "replacement-patch-supersedence") {
    errors.push("replacement-patch-audit.json audit_type must be replacement-patch-supersedence");
  }
  if (rollback.failed.packageVersion !== failedRecord.packageVersion) {
    errors.push("rollback failed packageVersion must match dry-run record");
  }
  if (rollback.failed.tarballName !== failedRecord.tarballName) {
    errors.push("rollback failed tarballName must match dry-run record");
  }
  if (failedNpmView.version !== failedRecord.packageVersion) {
    errors.push("failed npm metadata version must match dry-run record");
  }
  if (!failedTarball?.endsWith(failedRecord.tarballName)) {
    errors.push("failed npm metadata dist.tarball must end with failed tarballName");
  }
  if (failedGate.ok !== false || failedGate.decision !== "reject") {
    errors.push("downstream failure gate must reject the failed publication");
  }
  if (rollback.requiredNextAudit !== "replacement-patch-audit.json") {
    errors.push("rollback audit must require replacement-patch-audit.json");
  }
  for (const artifact of [
    "jury-package-dry-run",
    "jury-package-release-evidence",
    "jury-pack-dry-run-record.json",
    "failed-npm-view.json",
    "downstream-failure-gate.json",
    "rollback-audit.json",
    "GITHUB_STEP_SUMMARY",
  ]) {
    if (!rollback.retention?.artifacts?.includes(artifact)) {
      errors.push(`rollback retention must include ${artifact}`);
    }
  }
  if (rollback.retention?.retainUntil !== "180 days after replacement downstream verification passes") {
    errors.push("rollback retention must keep evidence until 180 days after replacement downstream verification passes");
  }
  if (rollback.retention?.storage !== "release record or incident archive") {
    errors.push("rollback retention storage must be release record or incident archive");
  }
  if (replacement.failed.packageVersion !== failedRecord.packageVersion) {
    errors.push("replacement audit failed packageVersion must match dry-run record");
  }
  if (replacement.failed.tarballName !== failedRecord.tarballName) {
    errors.push("replacement audit failed tarballName must match dry-run record");
  }
  if (replacement.replacement.packageVersion === failedRecord.packageVersion) {
    errors.push("replacement packageVersion must differ from failed packageVersion");
  }
  if (replacementNpmView.version !== replacement.replacement.packageVersion) {
    errors.push("replacement npm metadata version must match replacement audit");
  }
  if (replacementTarball !== replacement.replacement.distTarball) {
    errors.push("replacement npm metadata dist.tarball must match replacement audit");
  }
  if (replacementTarball?.endsWith(failedRecord.tarballName)) {
    errors.push("replacement dist.tarball must not end with failed tarballName");
  }
  if (replacementGate.ok !== true || replacementGate.decision !== "accept") {
    errors.push("replacement downstream gate must accept the replacement patch");
  }
  if (Array.isArray(replacement.checks) && !replacement.checks.includes("failed version deprecation result recorded when available")) {
    errors.push("replacement audit must record the deprecation evidence check");
  }
  for (const artifact of [
    "jury-package-dry-run",
    "jury-package-release-evidence",
    "jury-pack-dry-run-record.json",
    "failed-npm-view.json",
    "downstream-failure-gate.json",
    "rollback-audit.json",
    "replacement-npm-view.json",
    "replacement-downstream-gate.json",
    "replacement-patch-audit.json",
    "GITHUB_STEP_SUMMARY",
  ]) {
    if (!replacement.retention?.artifacts?.includes(artifact)) {
      errors.push(`replacement retention must include ${artifact}`);
    }
  }
  if (replacement.retention?.retainUntil !== "180 days after replacement downstream verification passes") {
    errors.push("replacement retention must keep evidence until 180 days after replacement downstream verification passes");
  }
  if (replacement.retention?.storage !== "release record or incident archive") {
    errors.push("replacement retention storage must be release record or incident archive");
  }

  return errors;
}

function fail(message) {
  process.stderr.write(`${message}\n`);
  process.exit(1);
}
