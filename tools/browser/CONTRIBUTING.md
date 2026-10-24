# Contributing to Crest

Crest is licensed under the Mozilla Public License 2.0. Contributions are
accepted under the same license. The Crest name and visual identity remain
covered by [`TRADEMARKS.md`](TRADEMARKS.md).

## Local setup

1. Install Xcode with SDKs supporting the macOS 26.1 and iOS 26.1 deployment targets.
2. Install [XcodeGen](https://github.com/yonaskolb/XcodeGen).
3. Install the .NET SDK pinned by `CrestCore/global.json`, for example with
   `Scripts/control-plane/install-dotnet.sh`.
4. Use Python 3.11 or later for the Chromium and release tools. Check that
   `python3 --version` resolves to that interpreter.
5. Install [ripgrep](https://github.com/BurntSushi/ripgrep) for the script
   test suite, and Node.js 20 or later if you build the Help Center in
   `HelpCenter/`. `swift-format` ships with Xcode; the checks call it through
   `xcrun`.
6. Run `Scripts/bootstrap.sh` from the repository root.

Building the `Crest` scheme produces the WebKit composition of the Mac app. The
published Mac app also packages a prebuilt Chromium engine; see
[`CrestEngines/Chromium/README.md`](CrestEngines/Chromium/README.md) before
changing engine inputs.

`project.yml` is authoritative. Do not hand-edit target membership or build settings only in Xcode, because the next project generation will replace those changes.

## Validation

Run `Scripts/validate-identity.sh` after product metadata or persistent identifier changes. Run `Scripts/validate-cache-hygiene.sh` after building or testing, and run `Scripts/validate.sh` for the macOS and iOS unit gates. The validation script reuses one temporary Derived Data directory and removes it on success, failure, or interruption.

For repository-only changes, run `Scripts/check-architecture.py`,
`Scripts/check-vertical-structure.py`, and `Scripts/check-swift-format.sh`; use
`--base main` to include committed branch changes in the formatting check. The
vertical check uses an exact debt ledger: structural refactors remove their
resolved entries in the same commit, while new violations are rejected.
`Scripts/audit-periphery.sh` repeats the dead-code evidence audit across every
app scheme and configuration when Periphery is installed. Its output never
justifies deletion without reference, build, and test proof. See
[`Documentation/RepositoryGuardrails.md`](Documentation/RepositoryGuardrails.md)
for the enforced contracts and current exact exemptions.

**Build Crest** runs on pull requests and pushes to `main`, and can also be
dispatched manually. It checks source, core tests and analyzers, architecture,
scripts, Swift formatting, native contracts, macOS and iOS builds, and the Help
Center. Release publication calls the same workflow for the exact source SHA
and waits for it to pass. Run the relevant local validation before opening a
pull request; builds do not replace native app acceptance checks.

Run `Scripts/audit-licenses.py` whenever a package, website dependency, copied
source file, font, or other third-party asset changes. New runtime dependencies
must have a redistributable license and a preserved notice before they land.

The project supports Apple silicon only. Keep new targets, destinations, and scripts arm64-native.

## Community and planning

Use [r/CrestBrowser](https://www.reddit.com/r/CrestBrowser) to discuss early
ideas, user questions, and compatibility experiences before they become
actionable engineering work. Use GitHub Issues for reproducible bugs and
concrete outcomes. The public
[Crest Roadmap project](https://github.com/users/pauljoda/projects/3) and
release milestones summarize planned work. [The roadmap](Documentation/ROADMAP.md)
is generated from public GitHub issues with `Scripts/render-roadmap.py --write`.
The renderer updates only its marked section, preserving the platform notes.

See [SUPPORT.md](SUPPORT.md) for reporting routes and
[GOVERNANCE.md](GOVERNANCE.md) for the current ownership and decision model.

## Change discipline

- Keep SwiftUI presentation native and adaptive.
- Preserve exact Space isolation for website data, credentials, history, tabs, settings, and synchronization.
- Cover important behavioral contracts with focused regression tests. Review visual appearance, layout, and animation in the running app.
- Keep build products, diagnostic captures, audit reports, submission packets, user state, credentials, signing exports, and local environment files out of Git. Documentation should help public users and contributors; keep private planning and machine-specific instructions local.
- Do not add task-specific Markdown results or closeout reports, including under Documentation, or upload them as release or issue attachments. Summarize validation in the task or issue discussion. Keep necessary local evidence outside the checkout; maintained docs should describe lasting behavior and instructions, not dated test totals or cleanup narratives.
- Keep personal editor and coding-assistant state local. The tracked exceptions are the root `AGENTS.md` and the `crest-contribution` skill; `Scripts/check-public-source.py` rejects everything else.
- Do not enable the managed iOS default-browser entitlement until Apple approves it for the Crest App ID.

## AI-assisted contributions

You may use AI tools. Any change an AI tool helped produce must follow the
[`crest-contribution` skill](.agents/skills/crest-contribution/SKILL.md),
which carries the code style, architecture, UI, test, verification and
writing rules a reviewer will hold the change to. Claude Code discovers it
through `.claude/skills/crest-contribution`, Codex through `.agents/skills`,
and every other agent is pointed to it by [`AGENTS.md`](AGENTS.md). Load it
before the agent changes anything and keep it loaded while it works.

The pull request template has an AI usage section with two boxes: that AI
tools helped, and that the skill was run and its output reviewed. The
**Contribution checks** workflow fails a pull request that ticks the first
without the second, or that removed the section. You remain responsible for
understanding, validating and explaining everything you submit.

`Config/Version.xcconfig` is the only source for Crest's public version. Versions
use complete `X.Y.Z` semantic versioning. Once a fix is verified and ready to
commit, run `Scripts/set-version.sh --patch`, stage the version file with the
fix, and run `Scripts/check-version.sh --fix-commit`. Each independently
verified fix advances the patch component once; when several already verified
fixes intentionally share one commit, use `Scripts/set-version.sh --patch N` to
account for all of them.

Changing the major or minor release line is a separate release decision. Use
`Scripts/set-version.sh --release X.Y.Z` only when that release and its tag have
been explicitly approved. Xcode Cloud continues to own distributed integer
build numbers while the repository keeps build `1` as its local fallback.

Every user-visible or architecture-significant work commit adds a new entry to
`Documentation/ReleaseNotes.json`. The stable lowercase kebab-case ID is the
entry's identity across rebases and history rewrites; never reuse, reorder, or
delete one, and append new entries at the end. Choose `new`, `improved`, or
`fixed` for public notes and write the message as a concise user-facing outcome.
Use `internal` to record architecture, release, or tooling work that should not
appear to users. The fix-commit check requires the new staged entry alongside
the patch bump.

Keep commits focused and use a Conventional Commit subject such as
`refactor(settings): adopt native split navigation`. Commit subjects remain
useful development history, but rolling release copy comes from the explicit
catalog. `CHANGELOG.md` remains the curated stable-release history. Release
commits freeze its `Unreleased` section under an ISO date and receive an
annotated `vX.Y.Z` tag. Do not invent historical release tags.

## Developer Certificate of Origin

Crest uses the [Developer Certificate of Origin 1.1](https://developercertificate.org/).
Sign off each commit with `git commit -s` to certify that you have the right to
submit the contribution under this project's license. The sign-off is a commit
trailer, not a transfer of copyright:

```text
Signed-off-by: Your Name <you@example.com>
```

The **Contribution checks** workflow fails a pull request when any of its
commits lacks the trailer. Merge commits are skipped, and pull requests
opened by bots or by the repository owner are exempt.
