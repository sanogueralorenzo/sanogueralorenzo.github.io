---
name: crest-contribution
description: Required before any AI-assisted change to Crest. Loads the project's C# and Swift style, the core-owns-state and engine-adapter architecture rules, the single-window and design-system UI rules, the test policy, and the pull request, verification and writing requirements. Use whenever an AI tool writes, refactors, reviews or describes Crest source, tests, documentation or pull request text.
---

# Contributing to Crest with an AI agent

Every pull request that an AI tool helped produce must follow this skill, and
the pull request template asks the author to confirm that it did. Read it in
full before changing anything, then keep it loaded while you work. It adds the
rules that are not obvious from the code; `CONTRIBUTING.md`,
`Documentation/RepositoryGuardrails.md` and `Documentation/ARCHITECTURE.md`
remain the base contract.

## Before you start

1. Read `CONTRIBUTING.md` and `AGENTS.md` at the repository root.
2. Run `Scripts/bootstrap.sh` once per clone. It generates the Xcode project
   and verifies this skill is linked for Claude Code.
3. Work from the issue or the maintainer's description. Keep the pull request
   to that one outcome.

## Code style

The full style guide for C# and Swift is in
[`references/library-style.md`](references/library-style.md). Apply it to every
type you touch. The rules that matter most:

- **Section layout.** Members of every type follow the same order in both
  languages: Static Variables, Variables, Initializers (Constructors),
  Abstract Methods, Actions grouped by purpose, Mutators. C# uses
  `#region`, Swift uses `// MARK: -`. Large purposes move to
  `Type.Purpose.cs` or `Type+Purpose.swift`.
- **Objects describe themselves.** A type owns its data and every behavior that
  depends on it. No sibling `*Codes`, `*Policy`, `*Rules`, `*Helper` or
  `*Utilities` types, and no extension files that switch over its kinds.
- **Behavior gets a file, plain data does not.** A type with behavior is the
  primary type of its own file. Data-only records, structs and case-only enums
  live in a `Types` region at the top of their one owner's file, or in one
  shared concept file when many consumers share them.
- **Self-describing fixed sets.** Modes, reasons, states, statuses, roles and
  capabilities are one type whose static instances define the members, each
  constructed with the values that make its behavior emerge. Methods never
  switch on a particular member.
- **Typed values, never raw codes.** Decode a wire string once at the boundary
  and dispatch on the typed value. No `status == "supported"`,
  `execute("tab.open")` or string-matched errors. Wire and persisted payloads
  are typed `Codable` or record models, not dictionaries.
- **Messages implement their own behavior.** Intents, queries and events are
  dispatched by polymorphism: each case overrides the method its family
  declares. No type switches, handler interfaces or generated dispatch.
- **Touch-only.** Apply the layout to the files your change touches. A feature
  pull request never carries a repository-wide reformatting pass.
- **Formatters and builds.** Before finishing, run
  `Scripts/check-swift-format.sh` for Swift changes,
  `Scripts/control-plane/lint-dotnet.sh` for CrestCore changes, and build the
  affected targets.

## Architecture

- **The core owns shared state.** Spaces, tabs, folders, splits, windows,
  history and behavior preferences live in CrestCore. Swift renders that state
  and sends intents. Never mutate `BrowserStore.session` or any other shared
  state directly from Swift; add or use a core intent and apply the change it
  returns. Only appearance preferences, window geometry and transient
  presentation stay in Swift.
- **Everything is a named object.** Intents, changes, engine commands and
  events are named record types. There are no operation strings and no code
  tables; the generator owns the wire tags. Rule failures are objects such as
  `TabLimitReached(limit)`, never string codes. Identifiers are plain
  `Guid`/`UUID` used at boundaries, with no one-field wrapper types; a wrapper
  exists only for an invariant or behavior, such as `SiteOrigin`. Make the
  difference between a core intent and a direct engine call visible at the call
  site.
- **Engines stay behind adapters.** Shared code never calls WebKit or Chromium
  APIs; it talks to the engine abstraction. A page opened by another page runs
  in the opener's engine. Per-site and default engine rules apply only to
  navigations a person starts.

## Windows and UI

- **Crest is a single-window app.** Never create a window the person did not
  ask for. Page and extension popups open as a Quick Window in the opener's
  engine and Space, where the person keeps or drops them. DevTools docks
  inside the window. An unexpected window during validation is a defect, not a
  detail.
- **Reuse the design system.** Interactive rows and tiles use
  `crestInteractiveSurface`; small glyph buttons use `CrestChromeButtonStyle`;
  colours come from the Crest tokens and the template house palettes. No
  ad-hoc opacity fills, no system rainbow colours, no bespoke buttons or
  cards. Every interactive control has hover and pressed states from the
  system. Search `CrestShared/DesignSystem` before writing any new fill or
  control.
- **No modal notices.** Informational feedback such as "copied" or "captured"
  goes through the top-of-window notice capsule
  (`BrowserChromeState.showNotice`). Alerts and sheets appear only when the
  person must decide something.

## Tests

- **Default to no new test.** Add a permanent test only for a contract that
  breaks silently: extension compatibility and recovery, persistence and
  migration, Space and window ownership, privacy and authorization boundaries,
  the sync codec, Keychain access, native input routing, and security
  decisions such as download risk or update trust.
- **Never test appearance.** No tests for layout numbers, copy, SF Symbol
  names, animation, settings-pane structure, previews, file layout, or
  source-text greps. Review those in the running app.
- **One test at the owning layer.** Do not duplicate a shared contract across
  platform test targets unless the adapters genuinely diverge, and do not add
  trivial wrapper tests.
- **Remove probes; never delete to go green.** Temporary probes, fixtures and
  harnesses used while reproducing a problem come out before the pull request.
  A failing test is resolved by deciding whether the contract or the
  expectation changed, never by deleting it.

## Pull request

- **Version and release note.** Every commit that changes app code runs
  `Scripts/set-version.sh --patch`, appends a new entry with a unique
  lowercase kebab-case ID to `Documentation/ReleaseNotes.json`, stages
  `Config/Version.xcconfig` with the change, and passes
  `Scripts/check-version.sh --fix-commit`. Never change
  `CURRENT_PROJECT_VERSION`.
- **One focused pull request.** No scope widening and no drive-by refactors.
  When a change regenerates `CrestShared/Resources/Localizable.xcstrings`,
  the regenerated catalog is part of that change. Edit `project.yml` and run
  `xcodegen generate`; never hand-edit the Xcode project.
- **Engine inputs need a maintainer.** Changes under
  `CrestEngines/Chromium` (patches, overlay, the host header, the
  control-plane prepare, apply, configure and build scripts) require a
  prebuilt engine that only maintainers can publish. Say so in the pull
  request description so the publish is planned with the merge.
- **Declare AI use.** Tick both boxes in the pull request template's AI usage
  section. A continuous-integration check reads them.

## Verification and reporting

- **Report exactly what ran.** Run the relevant gates before saying a change
  is done, and state in the pull request which tests and builds ran and their
  results. Never describe untested work as verified.
- **Verify UI in the running app.** Visual and layout changes are checked in
  the real app, Simulator or browser, never only by tests. Launch fixtures and
  validation sessions with `CREST_ISOLATED_SESSION=1` so they never touch
  real browsing data.
- **Remove test copies when you finish.** Every copy of Crest you build,
  install or launch for testing registers with macOS under the same bundle
  identifier as the person's own Crest, so macOS can hand links, passkey
  requests and later test launches to the wrong copy. Before handing off,
  quit those copies, unregister each with
  `/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u <path>`,
  then delete it. Unregister first, because an app moved to the Trash
  registers again at its Trash path. Never remove or replace the person's
  installed Crest.
- **Show visual changes in the pull request.** A pull request that changes
  what people see includes screenshots of each change in its description, so
  a reviewer can check it without building. Add a short recording where the
  change moves, before-and-after pairs where the difference is subtle, and
  both appearances where light and dark differ. Take them in the running app
  or Simulator, attach them to the pull request, and never commit them.
- **Regressions: read history, restore once.** When a second regression
  appears in the same area after a refactor, stop guessing. Read the commits
  that built the working behavior, compare the current behavior against the
  last known good revision, and restore every gap in one pass.
- **No artifacts in the repository.** Task reports, audit write-ups,
  screenshots, benchmark logs and closeout packets never enter the tree,
  including `Documentation/`. Evidence belongs in the pull request text.

## Writing

- **Release notes are user outcomes.** An entry says what changed for the
  person using Crest, never a commit subject, implementation detail, issue ID
  or test description.
- **Minimal native copy.** User-facing strings are short and read like the
  platform. No eyebrow labels, subtitles or explanatory text for what the UI
  already shows. Strings go through `String(localized:)` and the catalog.
- **Plain pull request descriptions.** What changed, why, what was validated,
  screenshots of any visual change, and the AI declaration. No filler, no
  generated-sounding prose, no emoji headings.
- **Documentation describes lasting behavior.** Maintained product behavior
  and contributor instructions only; never dated totals, machine paths,
  investigation transcripts or cleanup narratives.

## Checklist before opening the pull request

- [ ] Touched types follow the section layout and typed-value rules.
- [ ] Formatter, linter and affected builds ran clean.
- [ ] Shared state changes go through core intents; no direct engine calls in shared code.
- [ ] No new windows, ad-hoc fills or modal notices.
- [ ] Tests only for silent-breaking contracts; probes removed.
- [ ] Patch bump, release-note entry and `check-version.sh --fix-commit` pass.
- [ ] Pull request lists what ran, and both AI usage boxes are ticked.
- [ ] Visual changes are shown in screenshots attached to the pull request.
- [ ] Test copies of Crest are quit, unregistered and deleted.
