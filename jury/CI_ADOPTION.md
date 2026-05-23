# Jury CI Adoption Guide

Use this guide to pick the smallest Jury CI path that still matches the trust boundary of the repository.

The same workflow paths and artifact expectations are listed in [release.json](release.json) under `ciAdoption` so release tooling can consume the contract without parsing this guide.

## Choose a Workflow

| Need | Use | Produces | Trust boundary |
| --- | --- | --- | --- |
| Single-job verdict and portable review state | [examples/ci/jury-review-gate.yml](examples/ci/jury-review-gate.yml) | `verdict.json`, `gate.json`, `review-bundle.json`, `.jury/*.jsonl` | Same job produces and consumes the verdict. |
| Single producer job with signed output | [examples/ci/jury-signed-review-gate.yml](examples/ci/jury-signed-review-gate.yml) | `verdict.json`, `gate.json`, `review-bundle.signed.json`, `.jury/*.jsonl` | Producer signs the bundle with `secrets.JURY_CI_PRIVATE_KEY`. |
| Producer and consumer jobs in one workflow | [examples/ci/jury-signed-artifact-handoff.yml](examples/ci/jury-signed-artifact-handoff.yml) | Producer `verdict.json`, `gate.json`, `review-bundle.signed.json`, `.jury/*.jsonl`, plus `downstream-verdict.json`, `downstream-gate.json`, and `.jury-downstream/*.jsonl` | Consumer downloads the signed artifact and verifies it with `jury-key-policy.json`. |
| Reusable downstream verifier | [examples/ci/jury-trusted-bundle-verify.yml](examples/ci/jury-trusted-bundle-verify.yml) | `imported-verdict.json`, `trusted-gate.json`, and `.jury-trusted/*.jsonl` | A downstream workflow receives a signed bundle and reviewed key policy. |
| Reusable code-change adoption fixture | [examples/ci/jury-code-change-adoption.yml](examples/ci/jury-code-change-adoption.yml) | `verdict.retry.json`, `gate.retry.json`, `review-bundle.retry.json`, `review-bundle.retry.signed.json`, `verdict.accept.json`, `gate.accept.json`, `review-bundle.accept.json`, `review-bundle.accept.signed.json`, and `${{ inputs.state-dir }}/*.jsonl` | A reusable workflow signs retry and accept bundles with `secrets.JURY_CI_PRIVATE_KEY` for downstream verification. |

## Setup Checklist

1. Start with [QUICKSTART.md](QUICKSTART.md) and [examples/ci/jury-review-gate.yml](examples/ci/jury-review-gate.yml) until the unsigned local gate is stable.
2. Move to [examples/ci/jury-signed-review-gate.yml](examples/ci/jury-signed-review-gate.yml) when another job, workflow, or repository must trust the producer output.
3. Use [examples/ci/jury-signed-artifact-handoff.yml](examples/ci/jury-signed-artifact-handoff.yml) when the downstream verifier downloads the producer artifact with `actions/download-artifact@v4`.
4. Use [examples/ci/jury-trusted-bundle-verify.yml](examples/ci/jury-trusted-bundle-verify.yml) when the verifier should be reusable and parameterized by bundle, key policy, state, verdict, gate, and claim paths.
5. Use [examples/ci/jury-code-change-adoption.yml](examples/ci/jury-code-change-adoption.yml) when downstream jobs need retry and accept code-change review bundles from the checked-in adoption fixture. Configure `JURY_CI_PRIVATE_KEY` and, if needed, override `attestation-key-id` so consumers can verify the signed bundles.

## Code-Change Adoption Handoff

Downstream jobs can download the `jury-code-change-adoption` artifact and verify the accepted bundle before consuming the verdict:

```shell
node jury/bin/jury.mjs bundle preflight --bundle review-bundle.accept.signed.json --key-policy jury-key-policy.json
node jury/bin/jury.mjs bundle import --state-dir .jury-code-change-downstream --bundle review-bundle.accept.signed.json --key-policy jury-key-policy.json --verdict-out downstream-verdict.accept.json
node jury/bin/jury.mjs gate --state-dir .jury-code-change-downstream --claim claim_checkout_ready --verdict downstream-verdict.accept.json --json > downstream-gate.accept.json
node jury/bin/jury.mjs check --state-dir .jury-code-change-downstream --strict
```

The retry bundle remains available as `review-bundle.retry.signed.json` so consumers can inspect the original `docs/checkout-notes.md` scope objection and confirm the accepted bundle carries the later `ev_scope_corrected` evidence and resolved objection state.

## Key Policy Fixtures

[examples/ci/fixtures/key-policy](examples/ci/fixtures/key-policy) contains the signed-bundle happy path and an untrusted-producer troubleshooting policy. [examples/ci/fixtures/code-change-adoption-key-policy](examples/ci/fixtures/code-change-adoption-key-policy) contains signed retry and accept code-change adoption bundles plus the matching trusted-producer policy. [examples/ci/fixtures/key-policy-rotation](examples/ci/fixtures/key-policy-rotation) contains old/new key overlap and revoked-old cutover examples.

Run this before changing CI trust policy fixtures:

```shell
npm --prefix jury run fixtures:key-policy:check
```

## Release Validation

```shell
npm --prefix jury test
npm --prefix jury run check -- --state-dir /tmp/jury-ci-adoption --json
```
