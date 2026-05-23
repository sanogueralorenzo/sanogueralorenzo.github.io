# Jury CLI Reference

Jury is a dependency-free local CLI:

```shell
node jury/bin/jury.mjs <command> [flags]
```

Use `--state-dir <path>` to keep review state outside the default `.jury/` directory. Use `--json` for machine-readable output.

## Local Scripts

From `jury/`:

```shell
npm test
npm run demo
npm run check
```

The package is private and has no runtime dependencies. To install a local `jury` command while developing:

```shell
cd jury
npm link
jury help
```

## Core Flow

```shell
node jury/bin/jury.mjs init
node jury/bin/jury.mjs claim create --id claim_ready --summary "change is ready" --scope jury --impact high
node jury/bin/jury.mjs claim transition --claim claim_ready --status screening
node jury/bin/jury.mjs claim transition --claim claim_ready --status in_review
node jury/bin/jury.mjs check add --id check_tests --claim claim_ready --type verifier --summary "tests must pass"
node jury/bin/jury.mjs evidence add --claim claim_ready --type command --command "node --test jury/test/*.test.mjs" --exit-code 0
node jury/bin/jury.mjs critic run --claim claim_ready --role tests
node jury/bin/jury.mjs critic run --claim claim_ready --role security
node jury/bin/jury.mjs critic run --claim claim_ready --role scope --changed-files jury/bin/jury.mjs,jury/test/jury.test.mjs
node jury/bin/jury.mjs check update --id check_tests --status passed --resolution "tests passed"
node jury/bin/jury.mjs judge --claim claim_ready --out verdict.json
node jury/bin/jury.mjs gate --claim claim_ready --verdict verdict.json
node jury/bin/jury.mjs bundle export --claim claim_ready --out review-bundle.json --source local --revision unknown
node jury/bin/jury.mjs check --strict
```

## Commands

- `init`: creates append-only JSONL state files.
- `claim create`: creates a submitted claim.
- `claim transition`: moves a claim through the allowed lifecycle.
- `check add`: creates a durable review condition.
- `check update`: appends a new check state.
- `evidence add`: records command, file, citation, manual, policy, or tool evidence.
- `critic run`: runs deterministic `tests`, `security`, or `scope` critics.
- `objection add`: records a manual objection.
- `objection resolve`: appends a resolved objection state.
- `waiver add`: records explicit risk acceptance for an objection.
- `status`: prints the current claim review bundle.
- `judge`: emits and records a verdict.
- `gate`: exits zero only for an `accept` verdict that matches current claim state.
- `bundle export`: writes a portable `jury.review_bundle.v1` for one claim, including producer and provenance metadata.
- `bundle preflight`: validates a `jury.review_bundle.v1` without creating or mutating state.
- `bundle import`: imports a `jury.review_bundle.v1` into a state directory and can materialize its latest verdict with `--verdict-out`.
- `check --strict`: validates JSONL files, schema files, and cross-record consistency.
- `demo code-change`: creates a failing-then-passing code-change transcript plus an accepted final verdict.

## Diagnostics

`gate --claim <id>` reports `missing_fields`, `unresolved_objections`, `next_actions`, and `consistency_errors` when the verdict does not match current state.

`bundle preflight --bundle review-bundle.json` reports all bundle schema, record, cross-reference, and trust policy errors before import. It exits non-zero for invalid or untrusted bundles and does not create `.jury/` files.

`bundle export` accepts `--producer-name`, `--producer-version`, `--source`, `--revision`, `--workflow`, and `--run-id` for CI provenance. Defaults come from the local CLI and GitHub Actions environment when present.

`bundle preflight` and `bundle import` accept `--expect-producer-name`, `--expect-producer-version`, `--expect-source`, and `--expect-revision-pattern` so CI can reject bundles from unexpected producers or revisions before state is mutated.

`bundle export --attest-key <secret> --attestation-key-id <id>` signs the unsigned bundle payload with an `hmac-sha256` attestation. `bundle export --attest-private-key private.pem --attestation-key-id <id>` signs with an `rsa-sha256` attestation. Signing modes are mutually exclusive. `bundle preflight` and `bundle import` accept `--require-attestation true`, `--verify-attestation-key <secret>`, `--verify-attestation-public-key public.pem`, and `--expect-attestation-key-id <id>` so CI can verify that metadata was produced by a holder of the signing key. The verification mode must match the bundle attestation type.

`bundle preflight --key-policy jury-key-policy.json` and `bundle import --key-policy jury-key-policy.json` load a `jury.key_policy.v1` manifest with trusted producers and RSA public keys. A policy producer can set `name`, optional `version`, optional `source`, optional `revision_pattern`, and `keys` with `key_id`, `type: rsa-sha256`, and either `public_key` or `public_key_path`. Public key paths are resolved relative to the policy file. Keys can also set `valid_from`, `valid_until`, `revoked_at`, and `revoked_reason`; the signed bundle export time must be within the validity window, and revoked keys are rejected.

When `--key-policy` is set, `bundle preflight` and failed `bundle import` output includes `key_policy.matching_producers` and `key_policy.considered_keys` diagnostics. Key diagnostics report producer/key indexes, key id, public-key source, validity/revocation metadata, status, and per-key errors. Considered keys are every key under matching producer entries; statuses include `not_selected`, `usable`, `verified`, `revoked`, `blocked_by_revocation`, `outside_validity`, `read_error`, and `signature_mismatch`.

`check --strict` reports malformed JSON, schema problems, missing claim references, missing evidence/check/objection/waiver references, cross-claim references, and verdict claim-version mismatches.
