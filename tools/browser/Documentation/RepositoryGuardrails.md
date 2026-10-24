# Repository guardrails

Crest keeps repository checks narrow enough to express real architecture contracts. They intentionally do not guess whether a number is a design token, whether a declaration reported by static analysis is safe to delete, or how many declarations and folders a cohesive feature needs.

## Changed-file formatting

The root `.swift-format` configuration preserves Crest's four-space indentation and 120-column style. Check current staged, unstaged, and untracked Swift changes without rewriting them:

```sh
Scripts/check-swift-format.sh
```

For a branch or pull request, include every Swift file changed since a known base:

```sh
Scripts/check-swift-format.sh --base main
```

The script only invokes strict `swift-format lint`. It never runs formatter write mode and never performs a repository-wide formatting pass.

## Fix commit versions

Every verified fix advances the patch component of Crest's public version in
the same commit:

```sh
Scripts/set-version.sh --patch
git add Config/Version.xcconfig
Scripts/check-version.sh --fix-commit
```

Pass a positive count to `--patch` only when one focused commit intentionally
contains that many independently verified fixes. The fix-commit check reads the
Git index and rejects a missing, unstaged, non-increasing, or major/minor bump.
Changing release lines uses `Scripts/set-version.sh --release X.Y.Z` and remains
an explicit release-and-tag decision. Neither path changes
`CURRENT_PROJECT_VERSION`; Xcode Cloud owns distributed build numbers.

## Explicit release-note entries

`Documentation/ReleaseNotes.json` is the machine-readable source for GitHub and
Sparkle release copy. Its `entries` object maps a stable lowercase kebab-case ID
to exactly one category and message. `new`, `improved`, and `fixed` entries are
public; `internal` records a commit that should not be announced. Messages state
the user outcome directly and do not inherit commit wording.

The IDs, rather than commit hashes, survive rebases and history rewrites. Never
reuse, rewrite, reorder, or delete an ID; append new entries so catalog order
remains release order. The schema 2 `publicationBaselines` are immutable
bootstrap cursors for the currently published stable, nightly, and development
builds. Successful publications keep the live per-channel cursors in the
workflow-owned `updates` branch and advance only the selected channel in the
same commit as its signed appcast. Every product or architecture commit adds at
least one new entry. `Scripts/check-version.sh --fix-commit` validates the staged
catalog and rejects a patch bump without a new entry. Validate the working
catalog directly with:

```sh
python3 Scripts/release_note_catalog.py
```

## Architecture and Xcode 27 compatibility

Run:

```sh
Scripts/check-architecture.py
```

The check enforces these high-confidence contracts:

- Domain imports Foundation only; Application imports Foundation, Observation, and Dispatch only.
- SwiftUI presentation stays out of shared Infrastructure.
- AppKit, CoreServices, and SecurityInterface stay under `CrestMac`; UIKit stays under `CrestMobile`.
- Production code does not introduce `ObservableObject`, `@Published`, or `AnyView`.
- Conservative checks cover the documented Xcode 27 `@State` initialization and composition hazards, nested `TupleView` constraints, empty MapKit builders, and modified shape styles passed to non-builder `background` or `overlay` forms.

The Xcode 27 patterns follow Apple's [TN3211](https://developer.apple.com/documentation/technotes/tn3211-resolving-swiftui-source-incompatibilities-for-state-and-contentbuilder). They supplement compiler validation; they do not attempt to parse every legal Swift expression.

`Config/ArchitectureGuardrails.json` is the machine-readable exception register. Every entry is exact and carries a reason. All Application, Infrastructure, and platform-adapter paths are enrolled; none are hidden behind a path exclusion. Consult the register for the current exemptions.

An exemption is not precedent for another file: add new debt only with a focused review and a written reason, and prefer removing entries as ownership improves.

## Vertical feature organization

Run:

```sh
Scripts/check-vertical-structure.py
```

The guard applies Crest's deliberately small organization contract across `CrestShared`, `CrestMac`, and `CrestMobile`:

- Organize code by user-visible feature or runtime capability. Folder names describe the behavior a developer is looking for; `Components`, `Models`, `Services`, and `Support` are available vocabulary, not mandatory layers.
- A file holds one cohesive concept. Name it for either its primary owner or the role of a tightly related group; small single-use values, private helpers, related global declarations, and nested types should live with that concept. Multiple extensions may share a file when they extend that same owner. Use `// MARK:` sections named for the behavior they contain, rather than generic labels such as `Utilities` or `Animation`.
- Split a type only at a boundary that improves comprehension: a meaningful subview, a distinct lifecycle, a protocol conformance with real platform value, a large independently testable policy, or a cross-target/framework constraint. File count and line count are evidence, not goals; roughly 100–400 lines is a comfortable range and larger cohesive owners are acceptable.
- A protocol needs at least two production implementations or a genuine system boundary that cannot run in tests, previews, or the current process. Prefer a concrete store configured with disposable dependencies over paired production/in-memory protocols whose only second conformer is a test double.
- Root screens compose meaningful, narrowly scoped `View` types. Large root `body` implementations and large computed view builders remain guarded, but small owner-scoped subviews and values may stay in the same file.
- Put previews beside the components that own editable UI: controls, rows, cards, artwork, and meaningful content sections. A view that only arranges other components does not need another preview; use the children's canvases when tweaking their appearance. Keep the existing screen previews for integration review. Use named `#Preview` blocks inside `#if DEBUG`, representative states, realistic dimensions, and `@Previewable @State` bindings for interactive controls. Preview a button style through a real button in the style's source file. Any preview that exists must remain deterministic and reject known live persistence, network, Keychain, filesystem, WebKit-store, default-web-view, asynchronous remote-image, and production-composition dependencies. Reuse the feature's preview fixtures, keep identities and dates fixed, and separate saved preferences from the visual content before previewing a view that owns `@AppStorage` state.

`Config/VerticalStructureDebt.json` remains the exact ledger for the few machine-enforced rules. A new violation must be fixed or recorded with a focused reason; resolving one removes the stale entry in the same change.

Tests lock behavior whose regression would break a user workflow, persistence or migration contract, security boundary, data transformation, platform integration, or other costly invariant. Do not add tests merely to pin localization copy, design-token values, accessibility identifier strings, previews, file paths, declaration placement, or a mechanical refactor. Repository scripts may keep a small focused suite for their durable failure modes.

Share content, policies, and behavior across platforms while keeping macOS and mobile shells, framework delegates, and system adapters explicit in their platform roots.

UI components are canonical in `CrestShared` and read what their environment can do from `BrowserInteractionCapabilities` — independent bits like touch and hover, never a device or platform identity — with sizing and reveal rules derived in policies such as `BrowserSidebarInteractionPolicy`, and container width and Dynamic Type staying environmental. A platform tree may add a UI file only for a genuine platform seam: an AppKit/UIKit gesture or system adapter, a scene or presentation shell, a `BrowserPlatform*` same-name pair, or a port binding to a platform store. It may not fork a shared component's behavior; a divergence belongs in a capability bit, an explicit shell input, an optional closure on an actions value, or an accessory slot — chosen in that order of preference, and unified outright when the difference is harmless. This is a review rule, not a script: source-topology tests stay forbidden.

## Isolated validation sessions

Every fixture, forced-onboarding, setup, showcase, credential test, SwiftUI Preview, or automated app launch must use Crest's isolated launch graph. Set `CREST_ISOLATED_SESSION=1` for validation launches even when another fixture flag already implies isolation.

Use `CREST_ISOLATED_PERSISTENCE_ID=<name>` when a validation profile needs to survive relaunches. Keep fixture launches isolated from normal browsing data.

## Focused guard tests

The general architecture and vertical checks above are the supported
repository-wide gates. Run all retained script tests, including release,
version, isolation, and measurement contracts, with:

```sh
python3 -m unittest discover -s Scripts/Tests
```

`Scripts/validate.sh` runs this suite before the app tests. The manually
dispatched **Build Crest** workflow also runs it in a separate macOS job,
including release workflow, version, release-note publication, public-source,
and CloudKit environment contracts. These tests do
not build the app; the shell-based version tests require macOS `plutil`, Git,
zsh, and ripgrep.

`Scripts/check-public-source.py` separately inspects the exact Git index and
rejects coding-assistant instructions or state, machine-local editor files,
local environment configuration, and Apple signing or provisioning material.
The only tracked assistant files are the public `AGENTS.md`, the
`crest-contribution` skill under `.agents/skills/`, and its
`.claude/skills/crest-contribution` link; any other `.agents/` or `.claude/`
entry, nested `AGENTS.md`, or `CLAUDE.local.md` is rejected.
Ignored local worktrees do not enter the public snapshot, while an accidental
forced add fails the check.

Do not add feature-specific source-topology tests. The repository-wide guards
own framework and dependency direction; feature behavior belongs in focused
Swift tests or direct app validation.

The supported guards follow the same dependency direction as production code. Framework-neutral default-browser and passkey values and policies stay in Domain, their observable workflow controllers stay in Application, and AuthenticationServices, AppKit, UIKit, and Security bridges stay in shared or platform Infrastructure. Launch flags are parsed by `BrowserLaunchEnvironment`, evaluated by the Application launch policy, and read from the process only by the Infrastructure adapter; BrowserStore composition consumes that typed value.

Structural assertions check current owners and reject superseded paths. Keep those checks recursive where they protect a layer or framework boundary, and match declarations or signatures flexibly enough to allow formatting and typed parameters without accepting a different contract. The Python tooling itself must remain compatible with the Python 3.9 runtime bundled with Xcode.

## Periphery evidence audit

Install [Periphery](https://github.com/peripheryapp/periphery) when running the optional dead-code audit:

```sh
brew install periphery
Scripts/audit-periphery.sh
```

The script scans both app schemes across Debug and Release using one task-scoped Derived Data directory, then removes that directory. It retains Objective-C-accessible declarations and Codable properties up front. Its remaining findings are evidence only. Before deleting anything, prove references and target membership, run the affected builds and tests, and account for dynamic WebKit, AppKit, delegate, serialization, and preview entry points.
