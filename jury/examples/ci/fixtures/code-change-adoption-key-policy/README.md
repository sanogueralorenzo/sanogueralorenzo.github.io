# Jury Code-Change Adoption Key Policy Fixtures

These fixtures are a copyable downstream verification example for signed retry and accept code-change adoption bundles.

- [review-bundle.retry.signed.json](review-bundle.retry.signed.json): signed retry `jury.review_bundle.v1` bundle for `claim_checkout_ready`.
- [review-bundle.accept.signed.json](review-bundle.accept.signed.json): signed accepted `jury.review_bundle.v1` bundle for `claim_checkout_ready`.
- [jury-key-policy.json](jury-key-policy.json): `jury.key_policy.v1` manifest that trusts the code-change adoption fixture producer and public key.
- [jury-key-policy.untrusted-producer.json](jury-key-policy.untrusted-producer.json): negative fixture where a downloaded artifact is still signed, but producer metadata no longer matches trusted policy.
- [ci-code-change-public.pem](ci-code-change-public.pem): RSA public key referenced by the policy.

Verify both signed bundles without raw public-key flags:

```shell
node jury/bin/jury.mjs bundle preflight --bundle jury/examples/ci/fixtures/code-change-adoption-key-policy/review-bundle.retry.signed.json --key-policy jury/examples/ci/fixtures/code-change-adoption-key-policy/jury-key-policy.json
node jury/bin/jury.mjs bundle preflight --bundle jury/examples/ci/fixtures/code-change-adoption-key-policy/review-bundle.accept.signed.json --key-policy jury/examples/ci/fixtures/code-change-adoption-key-policy/jury-key-policy.json
```

Import and gate the accepted bundle in a fresh downstream state directory:

```shell
node jury/bin/jury.mjs bundle import --state-dir .jury-code-change-trusted --bundle jury/examples/ci/fixtures/code-change-adoption-key-policy/review-bundle.accept.signed.json --key-policy jury/examples/ci/fixtures/code-change-adoption-key-policy/jury-key-policy.json --verdict-out imported-verdict.accept.json
node jury/bin/jury.mjs gate --state-dir .jury-code-change-trusted --claim claim_checkout_ready --verdict imported-verdict.accept.json --json > trusted-gate.accept.json
node jury/bin/jury.mjs check --state-dir .jury-code-change-trusted --strict
```

The retry bundle is intentionally gate-failing after import, which lets consumers inspect the original scope objection before trusting the later accepted bundle.

```shell
node jury/bin/jury.mjs bundle import --state-dir .jury-code-change-retry-trusted --bundle jury/examples/ci/fixtures/code-change-adoption-key-policy/review-bundle.retry.signed.json --key-policy jury/examples/ci/fixtures/code-change-adoption-key-policy/jury-key-policy.json --verdict-out imported-verdict.retry.json
node jury/bin/jury.mjs gate --state-dir .jury-code-change-retry-trusted --claim claim_checkout_ready --verdict imported-verdict.retry.json --json > trusted-gate.retry.json || test "$?" -eq 1
node jury/bin/jury.mjs check --state-dir .jury-code-change-retry-trusted --strict
```

Troubleshoot an artifact whose producer metadata is no longer trusted:

```shell
node jury/bin/jury.mjs bundle preflight --bundle jury/examples/ci/fixtures/code-change-adoption-key-policy/review-bundle.accept.signed.json --key-policy jury/examples/ci/fixtures/code-change-adoption-key-policy/jury-key-policy.untrusted-producer.json
```

Use [../../jury-trusted-bundle-verify.yml](../../jury-trusted-bundle-verify.yml) with `bundle-path`, `key-policy-path`, and `claim-id: claim_checkout_ready` when the downstream check should run as a reusable GitHub Actions workflow.

Regenerate the signed fixture artifacts:

```shell
npm --prefix jury run fixtures:key-policy
```

Check fixture drift without writing files:

```shell
npm --prefix jury run fixtures:key-policy:check
```
