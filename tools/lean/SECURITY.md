# Security policy

## Supported versions

Security fixes are shipped on the latest stable Crest release. Nightly builds
are test builds and may receive a fix first, but they are not a separate
supported release line.

## Report a vulnerability privately

Use GitHub's **Report a vulnerability** form in the Security tab of this
repository. Please do not open a public issue for a suspected vulnerability.

Include the affected Crest version and platform, the security boundary you
expected, reproducible steps or a proof of concept, and the impact you believe
is possible. Remove browsing data, account tokens, passwords, private URLs, and
other personal information before attaching evidence.

The project will acknowledge a useful report, investigate it, coordinate a fix
and release when warranted, and credit the reporter if requested. Please allow
time for a signed and notarized update to reach users before public disclosure.

## Scope

High-value boundaries include Space isolation, engine profiles and website
data stores, Keychain access, extension installation and native messaging,
update signatures, archive import, external navigation, and CloudKit
synchronization. Ordinary website behavior inside the page engine, unsupported
extension APIs, and reports that require access to somebody else's device or
account are generally outside the project's control.
