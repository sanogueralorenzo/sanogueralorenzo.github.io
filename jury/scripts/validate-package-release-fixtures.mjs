#!/usr/bin/env node
import { createHash } from "node:crypto";
import { readFile, writeFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const packageRoot = dirname(dirname(fileURLToPath(import.meta.url)));
const args = parseArgs(process.argv.slice(2));
const fixtureDir = args.fixtureDir ?? join(packageRoot, "examples/ci/fixtures/package-release");
const evidenceSchemaPath = join(packageRoot, "schemas/package-release-evidence.schema.json");
const archiveManifestSchemaPath = join(packageRoot, "schemas/package-release-archive-manifest.schema.json");
const evidenceSchema = await readJson(evidenceSchemaPath);
const archiveManifestSchema = await readJson(archiveManifestSchemaPath);
const archiveEvidenceFiles = [
  "jury-pack-dry-run-record.json",
  "failed-npm-view.json",
  "downstream-failure-gate.json",
  "rollback-audit.json",
  "replacement-npm-view.json",
  "replacement-downstream-gate.json",
  "replacement-patch-audit.json",
];
const fixtureRead = await readRequiredFixtures([
  "rollback-audit.json",
  "replacement-patch-audit.json",
  "jury-pack-dry-run-record.json",
  "failed-npm-view.json",
  "downstream-failure-gate.json",
  "replacement-npm-view.json",
  "replacement-downstream-gate.json",
]);
if (fixtureRead.errors.length > 0) {
  process.stderr.write(`${fixtureRead.errors.join("\n")}\n`);
  process.exit(1);
}
const rollback = fixtureRead.fixtures.get("rollback-audit.json");
const replacement = fixtureRead.fixtures.get("replacement-patch-audit.json");
const failedRecord = fixtureRead.fixtures.get("jury-pack-dry-run-record.json");
const failedNpmView = fixtureRead.fixtures.get("failed-npm-view.json");
const failedGate = fixtureRead.fixtures.get("downstream-failure-gate.json");
const replacementNpmView = fixtureRead.fixtures.get("replacement-npm-view.json");
const replacementGate = fixtureRead.fixtures.get("replacement-downstream-gate.json");
const archiveManifest = tryBuildArchiveManifest();
const archiveDriftManifestPath = args.checkArchiveDrift
  ? join(fixtureDir, "retained-package-release-evidence-manifest.json")
  : null;
const errors = [
  ...schemaDocumentErrors(evidenceSchema, "jury.package_release_evidence.v1", rollback, "rollback-audit.json"),
  ...schemaDocumentErrors(evidenceSchema, "jury.package_release_evidence.v1", replacement, "replacement-patch-audit.json"),
  ...archiveManifest.errors,
  ...relationshipErrors(),
];
if (args.verifyManifest) {
  errors.push(...await verificationErrorsForManifest(args.verifyManifest));
}
if (archiveDriftManifestPath) {
  errors.push(...await verificationErrorsForManifest(archiveDriftManifestPath, { archiveDrift: true }));
}

if (errors.length > 0) {
  process.stderr.write(`${errors.join("\n")}\n`);
  process.exit(1);
}

if (args.manifestOut) {
  await writeFile(args.manifestOut, `${JSON.stringify(archiveManifest.value, null, 2)}\n`);
}

process.stdout.write(`${JSON.stringify({
  ok: true,
  schema: "schemas/package-release-evidence.schema.json",
  archiveManifestSchema: "schemas/package-release-archive-manifest.schema.json",
  manifestOut: args.manifestOut ?? null,
  verifiedManifest: args.verifyManifest ?? null,
  archiveDriftManifest: archiveDriftManifestPath,
  fixtures: [
    "rollback-audit.json",
    "replacement-patch-audit.json",
  ],
}, null, 2)}\n`);

async function readRequiredFixtures(names) {
  const fixtures = new Map();
  const rawFixtures = new Map();
  const errors = [];
  for (const name of names) {
    try {
      const raw = await readFile(join(fixtureDir, name), "utf8");
      fixtures.set(name, JSON.parse(raw));
      rawFixtures.set(name, raw);
    } catch (error) {
      if (error.code === "ENOENT") {
        errors.push(`${name} is required in package release evidence directory ${fixtureDir}`);
      } else {
        errors.push(`${name} could not be read: ${error.message}`);
      }
    }
  }
  return { fixtures, rawFixtures, errors };
}

async function readVerificationManifest(path) {
  try {
    return { value: await readJson(path), errors: [] };
  } catch (error) {
    if (error.code === "ENOENT") {
      return { value: null, errors: [`${path} is required for retained package release manifest verification`] };
    }
    return { value: null, errors: [`${path} could not be read: ${error.message}`] };
  }
}

async function readJson(path) {
  return JSON.parse(await readFile(path, "utf8"));
}

function parseArgs(argv) {
  const parsed = { fixtureDir: null, manifestOut: null, verifyManifest: null, checkArchiveDrift: false };

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
    if (arg === "--manifest-out") {
      const value = argv[index + 1];
      if (!value) {
        fail("missing value for --manifest-out");
      }
      parsed.manifestOut = value;
      index += 1;
      continue;
    }
    if (arg === "--verify-manifest") {
      const value = argv[index + 1];
      if (!value) {
        fail("missing value for --verify-manifest");
      }
      parsed.verifyManifest = value;
      index += 1;
      continue;
    }
    if (arg === "--check-archive-drift") {
      parsed.checkArchiveDrift = true;
      continue;
    }

    fail(`unknown argument ${arg}`);
  }

  return parsed;
}

async function verificationErrorsForManifest(manifestPath, options = {}) {
  const manifestRead = await readVerificationManifest(manifestPath);
  const errors = [...manifestRead.errors];
  if (manifestRead.value) {
    errors.push(
      ...schemaDocumentErrors(archiveManifestSchema, "jury.package_release_archive_manifest.v1", manifestRead.value, manifestPath),
      ...(archiveManifest.value ? manifestVerificationErrors(manifestRead.value, archiveManifest.value, manifestPath, options) : []),
    );
  }
  return errors;
}

function schemaDocumentErrors(schemaDocument, expectedSchemaVersion, value, label) {
  const errors = [];
  if (schemaDocument.properties?.schema_version?.const !== expectedSchemaVersion) {
    errors.push(`schema must define ${expectedSchemaVersion}`);
  }
  validateSchemaObject(schemaDocument, value, label, errors);
  return errors;
}

function validateSchemaObject(schemaNode, value, path, errors) {
  const type = schemaNode.type
    ?? ((schemaNode.contains || schemaNode.items) ? "array" : null)
    ?? ((schemaNode.required || schemaNode.properties || schemaNode.allOf || schemaNode.additionalProperties !== undefined) ? "object" : null);

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
    if (schemaNode.items) {
      for (const [index, item] of value.entries()) {
        validateSchemaObject(schemaNode.items, item, `${path}[${index}]`, errors);
      }
    }
    if (schemaNode.contains && !value.some((item) => schemaMatches(schemaNode.contains, item))) {
      errors.push(`${path} must contain an item matching required archive evidence`);
    }
    for (const clause of schemaNode.allOf ?? []) {
      validateSchemaObject(clause, value, path, errors);
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

  if (type === "number" && typeof value !== "number") {
    errors.push(`${path} must be a number`);
  }

  if (type === "integer" && (!Number.isInteger(value))) {
    errors.push(`${path} must be an integer`);
  }

  if (schemaNode.const !== undefined && value !== schemaNode.const) {
    errors.push(`${path} must equal ${schemaNode.const}`);
  }

  if (schemaNode.enum && !schemaNode.enum.includes(value)) {
    errors.push(`${path} must be one of ${schemaNode.enum.join(", ")}`);
  }
}

function schemaMatches(schemaNode, value) {
  const errors = [];
  validateSchemaObject(schemaNode, value, "value", errors);
  return errors.length === 0;
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
  errors.push(...retentionProvenanceErrors(rollback, "rollback"));
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
  errors.push(...retentionProvenanceErrors(replacement, "replacement"));
  if (rollback.retention?.provenance?.runId !== replacement.retention?.provenance?.runId) {
    errors.push("rollback and replacement retention provenance runId must match");
  }
  if (rollback.retention?.provenance?.sourceRevision !== replacement.retention?.provenance?.sourceRevision) {
    errors.push("rollback and replacement retention provenance sourceRevision must match");
  }

  return errors;
}

function retentionProvenanceErrors(audit, label) {
  const errors = [];
  const provenance = audit.retention?.provenance;
  const artifactMap = new Map((provenance?.artifacts ?? []).map((artifact) => [artifact.name, artifact]));

  if (provenance?.source !== "github-actions") {
    errors.push(`${label} retention provenance source must be github-actions`);
  }
  if (provenance?.workflow !== "jury-npm-publish.yml") {
    errors.push(`${label} retention provenance workflow must be jury-npm-publish.yml`);
  }
  if (!provenance?.runId) {
    errors.push(`${label} retention provenance runId is required`);
  }
  if (!provenance?.sourceRevision) {
    errors.push(`${label} retention provenance sourceRevision is required`);
  }

  for (const [artifactName, sourceJob, requiredFiles] of [
    ["jury-package-dry-run", "dry-run-publication", ["jury-pack-dry-run.json", "jury-pack-dry-run-record.json"]],
    ["jury-package-release-evidence", "package-release-fixtures", [
      "README.md",
      "jury-pack-dry-run-record.json",
      "failed-npm-view.json",
      "downstream-failure-gate.json",
      "rollback-audit.json",
      "replacement-npm-view.json",
      "replacement-downstream-gate.json",
      "replacement-patch-audit.json",
    ]],
  ]) {
    const artifact = artifactMap.get(artifactName);
    if (!artifact) {
      errors.push(`${label} retention provenance must include ${artifactName}`);
      continue;
    }
    if (artifact.sourceJob !== sourceJob) {
      errors.push(`${label} retention provenance ${artifactName} sourceJob must be ${sourceJob}`);
    }
    if (artifact.retentionDays !== 90) {
      errors.push(`${label} retention provenance ${artifactName} retentionDays must be 90`);
    }
    for (const file of requiredFiles) {
      if (!artifact.files?.includes(file)) {
        errors.push(`${label} retention provenance ${artifactName} must include ${file}`);
      }
    }
  }

  const provenanceFiles = new Set([...artifactMap.values()].flatMap((artifact) => artifact.files ?? []));
  for (const retained of audit.retention?.artifacts ?? []) {
    if (retained === "GITHUB_STEP_SUMMARY" || artifactMap.has(retained)) {
      continue;
    }
    if (!provenanceFiles.has(retained)) {
      errors.push(`${label} retained artifact ${retained} must be listed in retention provenance files`);
    }
  }

  return errors;
}

function buildArchiveManifest() {
  const retentionArtifacts = [...new Set([
    ...rollback.retention.artifacts,
    ...replacement.retention.artifacts,
  ])];
  const provenanceArtifacts = new Map();
  for (const artifact of [
    ...rollback.retention.provenance.artifacts,
    ...replacement.retention.provenance.artifacts,
  ]) {
    provenanceArtifacts.set(artifact.name, artifact);
  }

  return {
    schema_version: "jury.package_release_archive_manifest.v1",
    package: rollback.package,
    failed: {
      packageVersion: failedRecord.packageVersion,
      tarballName: failedRecord.tarballName,
      dryRunRecord: rollback.failed.dryRunRecord,
      npmView: rollback.failed.npmView,
      downstreamGate: rollback.failed.downstreamGate,
      rollbackAudit: "rollback-audit.json",
      deprecation: rollback.deprecation,
    },
    replacement: {
      packageVersion: replacement.replacement.packageVersion,
      npmView: replacement.replacement.npmView,
      distTarball: replacement.replacement.distTarball,
      downstreamGate: replacement.replacement.downstreamGate,
      replacementAudit: "replacement-patch-audit.json",
    },
    retention: {
      policy: rollback.retention.policy,
      storage: rollback.retention.storage,
      retainUntil: rollback.retention.retainUntil,
      artifacts: retentionArtifacts,
    },
    provenance: {
      source: rollback.retention.provenance.source,
      workflow: rollback.retention.provenance.workflow,
      runId: rollback.retention.provenance.runId,
      sourceRevision: rollback.retention.provenance.sourceRevision,
      artifacts: [...provenanceArtifacts.values()],
    },
    archiveEvidence: archiveEvidenceDigests(),
  };
}

function archiveEvidenceDigests() {
  return archiveEvidenceFiles.map((path) => ({
    path,
    sha256: `sha256:${sha256(fixtureRead.rawFixtures.get(path))}`,
  }));
}

function tryBuildArchiveManifest() {
  try {
    const value = buildArchiveManifest();
    return {
      value,
      errors: schemaDocumentErrors(
        archiveManifestSchema,
        "jury.package_release_archive_manifest.v1",
        value,
        "retained package release archive manifest",
      ),
    };
  } catch (error) {
    return {
      value: null,
      errors: [`retained package release archive manifest could not be built: ${error.message}`],
    };
  }
}

function manifestVerificationErrors(manifest, expected, manifestPath, options = {}) {
  const errors = [];
  if (stableStringify(manifest) !== stableStringify(expected)) {
    if (options.archiveDrift) {
      errors.push(`${manifestPath} archive drift detected against retained package release evidence`);
    } else {
      errors.push(`${manifestPath} does not match retained package release evidence`);
    }
  }
  if (manifest.schema_version !== "jury.package_release_archive_manifest.v1") {
    errors.push(`${manifestPath}.schema_version must equal jury.package_release_archive_manifest.v1`);
  }
  if (manifest.failed?.packageVersion !== failedRecord.packageVersion) {
    errors.push(`${manifestPath}.failed.packageVersion must match failed dry-run record`);
  }
  if (manifest.failed?.tarballName !== failedRecord.tarballName) {
    errors.push(`${manifestPath}.failed.tarballName must match failed dry-run record`);
  }
  if (manifest.replacement?.packageVersion !== replacement.replacement.packageVersion) {
    errors.push(`${manifestPath}.replacement.packageVersion must match replacement audit`);
  }
  if (manifest.retention?.retainUntil !== rollback.retention.retainUntil) {
    errors.push(`${manifestPath}.retention.retainUntil must match retained evidence policy`);
  }
  if (manifest.provenance?.runId !== rollback.retention.provenance.runId) {
    errors.push(`${manifestPath}.provenance.runId must match retained evidence provenance`);
  }
  if (manifest.provenance?.sourceRevision !== rollback.retention.provenance.sourceRevision) {
    errors.push(`${manifestPath}.provenance.sourceRevision must match retained evidence provenance`);
  }
  const expectedEvidence = new Map((expected.archiveEvidence ?? []).map((item) => [item.path, item.sha256]));
  const manifestEvidence = new Map((manifest.archiveEvidence ?? []).map((item) => [item.path, item.sha256]));
  for (const [path, digest] of expectedEvidence) {
    if (manifestEvidence.get(path) !== digest) {
      errors.push(`${manifestPath}.archiveEvidence ${path} sha256 must match retained evidence`);
    }
  }
  return errors;
}

function sha256(value) {
  return createHash("sha256").update(value).digest("hex");
}

function stableStringify(value) {
  if (Array.isArray(value)) {
    return `[${value.map(stableStringify).join(",")}]`;
  }
  if (value && typeof value === "object") {
    return `{${Object.keys(value).sort().map((key) => `${JSON.stringify(key)}:${stableStringify(value[key])}`).join(",")}}`;
  }
  return JSON.stringify(value);
}

function fail(message) {
  process.stderr.write(`${message}\n`);
  process.exit(1);
}
