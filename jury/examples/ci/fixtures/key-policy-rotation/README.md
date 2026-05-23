# Jury Key Policy Rotation Fixtures

These fixtures show a CI migration window where old and new producer signing keys are both trusted by one reviewed key policy.

- [jury-key-policy.rotation.json](jury-key-policy.rotation.json): `jury.key_policy.v1` manifest with overlapping old and new RSA keys.
- [jury-key-policy.revoked-old.json](jury-key-policy.revoked-old.json): post-migration policy that revokes `ci-old` and keeps `ci-new`.
- [review-bundle.old.signed.json](review-bundle.old.signed.json): signed `jury.review_bundle.v1` bundle using `ci-old`.
- [review-bundle.new.signed.json](review-bundle.new.signed.json): signed `jury.review_bundle.v1` bundle using `ci-new`.
- [ci-old-public.pem](ci-old-public.pem): public key for the old producer key.
- [ci-new-public.pem](ci-new-public.pem): public key for the new producer key.

The overlap window is May 15, 2026 through June 1, 2026. During that window, downstream CI can accept either key while producers roll from `ci-old` to `ci-new`.

Verify the old signed bundle:

```shell
node jury/bin/jury.mjs bundle preflight --bundle jury/examples/ci/fixtures/key-policy-rotation/review-bundle.old.signed.json --key-policy jury/examples/ci/fixtures/key-policy-rotation/jury-key-policy.rotation.json
```

Verify the new signed bundle:

```shell
node jury/bin/jury.mjs bundle preflight --bundle jury/examples/ci/fixtures/key-policy-rotation/review-bundle.new.signed.json --key-policy jury/examples/ci/fixtures/key-policy-rotation/jury-key-policy.rotation.json
```

After the migration window, remove or revoke `ci-old` in the policy and keep only `ci-new` for newly produced bundles.

The revoked-old policy proves the cutover: `review-bundle.old.signed.json` fails preflight because `ci-old` is revoked, while `review-bundle.new.signed.json` still verifies.

Verify the new bundle after `ci-old` is revoked:

```shell
node jury/bin/jury.mjs bundle preflight --bundle jury/examples/ci/fixtures/key-policy-rotation/review-bundle.new.signed.json --key-policy jury/examples/ci/fixtures/key-policy-rotation/jury-key-policy.revoked-old.json
```

Confirm the old bundle is rejected after `ci-old` is revoked:

```shell
node jury/bin/jury.mjs bundle preflight --bundle jury/examples/ci/fixtures/key-policy-rotation/review-bundle.old.signed.json --key-policy jury/examples/ci/fixtures/key-policy-rotation/jury-key-policy.revoked-old.json
```
