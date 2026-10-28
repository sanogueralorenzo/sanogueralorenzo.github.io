# Local builds

Run from `tools/lean`:

```sh
Scripts/run-local.sh --release --build-only
```

This builds `LeanNext.app` with an ad-hoc signature, a distinct review bundle
identifier and the `CREST_REVIEW_BUILD` configuration. It uses the installed
Xcode and the .NET SDK pinned in `CrestCore/global.json`. Set
`LEAN_DERIVED_DATA` to choose the build directory.

Omit `--build-only` to open a named isolated profile. The command never replaces
an application in `/Applications`. Build and test data must stay separate from
the installed browser’s profile.

Managed Apple capabilities require provisioning for the new application
identity. The local review build omits those entitlements. Upstream Crest’s
release workflows and Chromium packaging are not used by this project.
