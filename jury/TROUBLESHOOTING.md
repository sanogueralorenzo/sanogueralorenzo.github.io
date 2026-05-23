# Jury CI Troubleshooting

Use this guide when a Jury CI gate emits a non-accept verdict.

## Inspect Artifacts

Start with `gate.json`. It is the small CI result that tells the job whether to proceed:

- `ok`: `true` only when the verdict is accepted.
- `decision`: `accept`, `reject`, `retry`, or `human_decision`.
- `reason`: the judge's short explanation.
- `missing_fields`: required claim or evidence fields missing from current state.
- `unresolved_objections`: blocking objections that still need resolution.
- `next_actions`: concrete follow-up work for retry or human-decision verdicts.

Then inspect `review-bundle.json`. It is the portable state snapshot for the claim:

- `claim_id`: the claim under review.
- `producer`: the tool name, version, and command that produced the bundle.
- `provenance`: the source, revision, workflow, and run id attached at export time.
- `attestation`: optional `hmac-sha256` or `rsa-sha256` signature metadata for verifying the bundle payload.
- `records.claims`: claim versions and lifecycle transitions.
- `records.checks`: required checks and their current status.
- `records.evidence`: command, citation, manual, or tool-call evidence.
- `records.objections`: reviewer objections still attached to the claim.
- `records.verdicts`: verdict history exported with the bundle.

```shell
node -e "const gate=JSON.parse(require('node:fs').readFileSync('gate.json','utf8')); console.log(JSON.stringify({ok:gate.ok,decision:gate.decision,reason:gate.reason,missing_fields:gate.missing_fields,unresolved_objections:gate.unresolved_objections,next_actions:gate.next_actions},null,2))"
node -e "const bundle=JSON.parse(require('node:fs').readFileSync('review-bundle.json','utf8')); console.log(JSON.stringify({claim_id:bundle.claim_id,producer:bundle.producer,provenance:bundle.provenance,claims:bundle.records.claims.length,checks:bundle.records.checks.length,evidence:bundle.records.evidence.length,objections:bundle.records.objections.length,verdicts:bundle.records.verdicts.length},null,2))"
node jury/bin/jury.mjs bundle preflight --bundle review-bundle.json --expect-producer-name @sanogueralorenzo/jury --expect-producer-version 0.1.0 --expect-source local --expect-revision-pattern "^unknown$"
node jury/bin/jury.mjs bundle preflight --bundle review-bundle.json --require-attestation true --verify-attestation-key "$JURY_BUNDLE_ATTEST_KEY"
node jury/bin/jury.mjs bundle preflight --bundle review-bundle.json --require-attestation true --verify-attestation-public-key ci-public.pem
node jury/bin/jury.mjs bundle preflight --bundle review-bundle.json --key-policy jury-key-policy.json
```

## Common Causes

- `reject`: command evidence failed, such as a test or smoke command with a non-zero exit code.
- `retry`: required evidence is missing, a required check is pending, a claim has no explicit scope, or a blocking objection is unresolved.
- `human_decision`: the claim needs explicit approval before the system should proceed.
- stale verdict: the claim changed after `verdict.json` was written, so the verdict no longer matches current claim state.
- downloaded artifact no longer trusted: the signed bundle may still verify cryptographically, but `bundle preflight --key-policy` rejects it when the bundle producer `source` or `revision` no longer matches reviewed policy metadata.
- package manifest missing CI metadata: `npm --prefix jury run package:manifest:check` rejects a package tarball that omits `release.json`, `CI_ADOPTION.md`, supported workflow files, or required package files from [PUBLISHING.md](PUBLISHING.md).
- stale or mismatched dry-run publication artifact: `jury-pack-dry-run-record.json` was generated for a different package version or tarball name, so the publish job must stop before `NODE_AUTH_TOKEN` is exposed.
- package release evidence replay failed: `package-release-evidence-replay` downloaded the wrong `jury-package-release-evidence` artifact path, the artifact is missing rollback or replacement audit files, or the uploaded audit data no longer satisfies the package release evidence schema.
- retained package release manifest replay failed: `--verify-manifest` found that `retained-package-release-evidence-manifest.json` no longer matches the archived rollback audit, replacement audit, retention policy, or provenance artifacts.
- published package fails downstream verification: npm accepted the package and provenance, but downstream Jury bundle or package checks reject the published version.

## Package Manifest Failure

Use the package manifest check when CI package publication fails before publishing:

```shell
npm --prefix jury run package:manifest:check
```

The command runs `npm pack --dry-run --json` and prints `ok`, `checked_paths`, and `missing`. If `ok` is `false`, every entry in `missing` is a contract file that would be absent from the package tarball.

Common missing paths:

- `release.json`: release tooling cannot discover the CI adoption contract.
- `CI_ADOPTION.md`: humans cannot inspect the selected CI workflow path from the package.
- `examples/ci/jury-trusted-bundle-verify.yml`: downstream reusable verification cannot be copied from the package.
- `examples/ci/fixtures/key-policy`: signed-bundle trust policy examples are absent.

To debug a saved pack manifest without rerunning `npm pack`, replay it:

```shell
node jury/scripts/check-package-manifest.mjs --pack-manifest npm-pack.json
```

Fix the package file list or restore the omitted file, then rerun `npm --prefix jury run package:manifest:check`.

## Package Release Evidence Replay Failure

Use this when `package-release-evidence-replay` fails after downloading `jury-package-release-evidence`. First confirm `JURY_PACKAGE_RELEASE_EVIDENCE_DIR` points at the downloaded artifact directory, then replay the audit and inspect the artifact contents locally:

```shell
npm --prefix jury run fixtures:package-release:check -- --fixture-dir <downloaded-artifact-dir>
node -e 'const fs=require("node:fs"); const dir=process.argv[1]; const required=["README.md","jury-pack-dry-run-record.json","failed-npm-view.json","downstream-failure-gate.json","rollback-audit.json","replacement-npm-view.json","replacement-downstream-gate.json","replacement-patch-audit.json"]; const missing=required.filter((file)=>!fs.existsSync(`${dir}/${file}`)); if (missing.length) throw new Error(`missing package release evidence files: ${missing.join(", ")}`); console.log(JSON.stringify({ok:true, artifact:"jury-package-release-evidence", files: required}, null, 2));' <downloaded-artifact-dir>
```

If the replay command reports a schema field such as `replacement-patch-audit.json.checks is required`, rerun `package-release-fixtures` from the same revision and upload a fresh artifact. If file inspection reports `missing package release evidence files`, fix the `actions/download-artifact` path or `JURY_PACKAGE_RELEASE_EVIDENCE_DIR`. If relationship errors remain, compare `rollback-audit.json` and `replacement-patch-audit.json` with `jury-pack-dry-run-record.json`, npm metadata, and downstream gate files before allowing `dry-run-publication`.

## Retained Package Release Manifest Replay Failure

Use this when `--verify-manifest retained-package-release-evidence-manifest.json` fails while closing or auditing the release archive. First replay the retained manifest against the archived evidence, then inspect the manifest identity, retention, and provenance summary:

```shell
npm --prefix jury run fixtures:package-release:check -- --fixture-dir <retained-evidence-dir> --verify-manifest <retained-manifest>
node -e 'const fs=require("node:fs"); const dir=process.argv[1]; const required=["README.md","jury-pack-dry-run-record.json","failed-npm-view.json","downstream-failure-gate.json","rollback-audit.json","replacement-npm-view.json","replacement-downstream-gate.json","replacement-patch-audit.json"]; const missing=required.filter((file)=>!fs.existsSync(`${dir}/${file}`)); if (missing.length) throw new Error(`missing retained package release evidence files: ${missing.join(", ")}`); console.log(JSON.stringify({ok:true, artifact:"retained-package-release-evidence", files: required}, null, 2));' <retained-evidence-dir>
node -e 'const fs=require("node:fs"); const manifest=JSON.parse(fs.readFileSync(process.argv[1],"utf8")); const summary={schema_version:manifest.schema_version,failedPackageVersion:manifest.failed?.packageVersion,replacementPackageVersion:manifest.replacement?.packageVersion,retentionArtifacts:manifest.retention?.artifacts,provenanceArtifacts:(manifest.provenance?.artifacts??[]).map((artifact)=>artifact.name)}; console.log(JSON.stringify(summary,null,2));' <retained-manifest>
node -e 'const fs=require("node:fs"); const manifest=JSON.parse(fs.readFileSync(process.argv[1],"utf8")); const required=["jury-package-dry-run","jury-package-release-evidence","rollback-audit.json","replacement-patch-audit.json"]; const missing=required.filter((artifact)=>!manifest.retention?.artifacts?.includes(artifact)); const provenanceMissing=["jury-package-dry-run","jury-package-release-evidence"].filter((name)=>!(manifest.provenance?.artifacts??[]).some((artifact)=>artifact.name===name)); if (missing.length || provenanceMissing.length) throw new Error(`missing retained archive evidence: retention=${missing.join(", ") || "none"} provenance=${provenanceMissing.join(", ") || "none"}`); console.log(JSON.stringify({ok:true, retentionArtifacts: required, provenanceArtifacts:["jury-package-dry-run","jury-package-release-evidence"]}, null, 2));' <retained-manifest>
```

If verification reports that the manifest path `is required for retained package release manifest verification`, restore `retained-package-release-evidence-manifest.json` from the release archive or regenerate it with `--manifest-out` before closing the record. If verification reports a required file such as `replacement-patch-audit.json is required in package release evidence directory`, or the file helper reports `missing retained package release evidence files`, restore the missing file from the promoted release archive before trusting the manifest. If verification reports `does not match retained package release evidence`, regenerate the manifest from the same archived evidence directory with `--manifest-out` and compare the diff before replacing the release record copy. If it reports `schema_version must equal jury.package_release_archive_manifest.v1`, restore a manifest generated by the current fixture validator. If it reports `must contain an item matching required archive evidence`, keep the release open until the manifest includes both `jury-package-dry-run` and `jury-package-release-evidence` provenance artifacts plus `rollback-audit.json` and `replacement-patch-audit.json` in retention artifacts.

## Dry-Run Publication Artifact Failure

Use this when the npm publish workflow fails before credentials are exposed with `packageVersion did not match` or `tarballName did not match`. The downloaded `jury-package-dry-run` artifact must contain `jury-pack-dry-run.json` and `jury-pack-dry-run-record.json` from the same `dry-run-publication` job that followed the package manifest check.

```shell
node -e 'const fs=require("node:fs"); const pkg=JSON.parse(fs.readFileSync("jury/package.json","utf8")); const record=JSON.parse(fs.readFileSync("jury-pack-dry-run-record.json","utf8")); const expectedTarball=`sanogueralorenzo-jury-${pkg.version}.tgz`; if (record.packageVersion !== pkg.version) throw new Error(`packageVersion ${record.packageVersion} did not match ${pkg.version}`); if (record.tarballName !== expectedTarball) throw new Error(`tarballName ${record.tarballName} did not match ${expectedTarball}`); console.log(JSON.stringify({packageVersion: record.packageVersion, tarballName: record.tarballName}, null, 2));'
```

If the command fails, rerun `dry-run-publication` after `package-manifest` instead of reusing an older artifact. Do not map `secrets.NPM_TOKEN` to `NODE_AUTH_TOKEN` until the downloaded record verifies against the current `jury/package.json`.

## Published Package Verification Failure

Use this when npm publication succeeds but a downstream Jury verifier rejects the published package. Treat the version as immutable: keep the retained `jury-package-dry-run` artifact, `GITHUB_STEP_SUMMARY`, npm metadata output, and downstream failure logs together until a replacement release passes.

```shell
npm view @sanogueralorenzo/jury@<packageVersion> version dist.tarball --json
npm deprecate @sanogueralorenzo/jury@<packageVersion> "Downstream Jury verification failed; use a later patch release."
```

Do not rerun `npm publish` for the same `packageVersion`. Fix the downstream verification issue, bump the package version, rerun the full release checklist, and publish a new patch version.

Before closing the incident, attach replacement patch evidence from [PUBLISHING.md](PUBLISHING.md). The evidence must include the failed `packageVersion`, failed `tarballName`, replacement `packageVersion`, replacement `dist.tarball`, downstream verification pass for the replacement, and the failed-version deprecation result when registry policy allows it. Use [examples/ci/fixtures/package-release](examples/ci/fixtures/package-release) as the rollback and replacement patch audit example.

## Downloaded Artifact Trust Failure

Use the negative key-policy fixture when a downstream job downloads `review-bundle.signed.json` successfully but the policy no longer trusts the producer metadata:

```shell
if node jury/bin/jury.mjs bundle preflight --bundle jury/examples/ci/fixtures/key-policy/review-bundle.signed.json --key-policy jury/examples/ci/fixtures/key-policy/jury-key-policy.untrusted-producer.json --json > gate.untrusted-producer.json; then exit 1; else test $? -eq 1; fi
```

Inspect `gate.untrusted-producer.json` for `key policy has no trusted producer`, then compare `bundle.provenance` with the trusted `source` and `revision_pattern` in the key policy.

## Retry Example

This example produces a retry verdict because the claim has no command evidence and the deterministic tests critic opens a blocking objection.

```shell
node jury/bin/jury.mjs init --state-dir .jury-retry
node jury/bin/jury.mjs claim create --state-dir .jury-retry --id claim_retry_missing_evidence --summary "change is ready"
node jury/bin/jury.mjs critic run --state-dir .jury-retry --claim claim_retry_missing_evidence --role tests
node jury/bin/jury.mjs judge --state-dir .jury-retry --claim claim_retry_missing_evidence --out verdict.retry.json
if node jury/bin/jury.mjs gate --state-dir .jury-retry --claim claim_retry_missing_evidence --verdict verdict.retry.json --json > gate.retry.json; then exit 1; else test $? -eq 1; fi
node jury/bin/jury.mjs bundle export --state-dir .jury-retry --claim claim_retry_missing_evidence --out review-bundle.retry.json
node jury/bin/jury.mjs check --state-dir .jury-retry --strict
```

Inspect `gate.retry.json` for `missing_fields`, `unresolved_objections`, and `next_actions`. Inspect `review-bundle.retry.json` for the objection record and the retry verdict.

## Reject Example

This example produces a reject verdict because command evidence records a failed test command.

```shell
node jury/bin/jury.mjs init --state-dir .jury-reject
node jury/bin/jury.mjs claim create --state-dir .jury-reject --id claim_reject_failed_tests --summary "change is ready" --scope jury
node jury/bin/jury.mjs evidence add --state-dir .jury-reject --id ev_failed_tests --claim claim_reject_failed_tests --type command --command "npm --prefix jury test" --exit-code 1
node jury/bin/jury.mjs judge --state-dir .jury-reject --claim claim_reject_failed_tests --out verdict.reject.json
if node jury/bin/jury.mjs gate --state-dir .jury-reject --claim claim_reject_failed_tests --verdict verdict.reject.json --json > gate.reject.json; then exit 1; else test $? -eq 1; fi
node jury/bin/jury.mjs bundle export --state-dir .jury-reject --claim claim_reject_failed_tests --out review-bundle.reject.json
node jury/bin/jury.mjs check --state-dir .jury-reject --strict
```

Inspect `gate.reject.json` for the failed decision and reason. Inspect `review-bundle.reject.json` for the failed command evidence and rejected verdict.
