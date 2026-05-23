# Jury Key Policy Fixtures

These fixtures are a copyable trusted-producer verification example for CI consumers.

- [review-bundle.signed.json](review-bundle.signed.json): signed `jury.review_bundle.v1` bundle for `claim_ci_change`.
- [jury-key-policy.json](jury-key-policy.json): `jury.key_policy.v1` manifest that trusts the fixture producer and public key.
- [jury-key-policy.untrusted-producer.json](jury-key-policy.untrusted-producer.json): negative fixture where a downloaded artifact is still signed, but producer metadata no longer matches trusted policy.
- [ci-public.pem](ci-public.pem): RSA public key referenced by the policy.

Verify the signed bundle:

```shell
node jury/bin/jury.mjs bundle preflight --bundle jury/examples/ci/fixtures/key-policy/review-bundle.signed.json --key-policy jury/examples/ci/fixtures/key-policy/jury-key-policy.json
```

Import the trusted bundle into a fresh state directory:

```shell
node jury/bin/jury.mjs bundle import --state-dir .jury-key-policy-imported --bundle jury/examples/ci/fixtures/key-policy/review-bundle.signed.json --key-policy jury/examples/ci/fixtures/key-policy/jury-key-policy.json --verdict-out imported-verdict.json
```

The private signing key is not included. These fixtures are for downstream verification and policy wiring.

Troubleshoot an artifact whose producer metadata is no longer trusted:

```shell
node jury/bin/jury.mjs bundle preflight --bundle jury/examples/ci/fixtures/key-policy/review-bundle.signed.json --key-policy jury/examples/ci/fixtures/key-policy/jury-key-policy.untrusted-producer.json
```

Use [../../jury-trusted-bundle-verify.yml](../../jury-trusted-bundle-verify.yml) when the downstream check should run as a reusable GitHub Actions workflow.

[../key-policy-rotation](../key-policy-rotation) shows how to trust old and new producer keys during a rotation overlap window.

Regenerate the signed fixture artifacts:

```shell
npm --prefix jury run fixtures:key-policy
```

Check fixture drift without writing files:

```shell
npm --prefix jury run fixtures:key-policy:check
```
