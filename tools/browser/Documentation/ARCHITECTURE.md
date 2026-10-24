# Crest architecture

Crest is a native SwiftUI browser for Apple silicon. It treats a **Space** as the primary privacy and organization boundary.

From Crest 0.7, browser rules live in a portable .NET core and pages render through engine adapters. On Mac, one app hosts both engines: Chromium is the default, and a person or website rule can choose WebKit. Protected-video requests trigger an automatic switch to WebKit unless the person has chosen an engine for the site. The core validates the document and completes before-unload checks before moving it or remembering a website rule. Cancellation leaves both unchanged. Chromium loads the first time a page or extension needs it. Extensions run only in Chromium. iPhone and iPad use WebKit. Both engines share the same core, UI and sync records. See [Portable browser control plane](Architecture/ControlPlane.md) and [Engine abstraction](Architecture/EngineAbstractionCompletion.md).

## Source map

```text
CrestCore/            Portable .NET core: session, sync, access and policy rules
CrestContracts/       C ABI header and native ABI test for the core library
CrestShared/
  Application/       Cross-platform coordination and stores
  DesignSystem/      Tokens, reusable components, and modifiers
  Domain/            Value types, policies, and state transitions
  Features/          Shared feature presentation by user purpose
  Infrastructure/    Core adapters, engine ports, WebKit adapter, Keychain, and sync transport
  Resources/         Localizations, privacy manifest, and app icon
CrestMac/             macOS app, page host, WebKit adapter, commands, and presentation
CrestMobile/          iPhone/iPad app, adaptive chrome, and WebKit host
CrestEngines/Chromium Chromium host overlay, patches, and Chromium adapter
```

`project.yml` is the target and build-setting source of truth. XcodeGen produces `Crest.xcodeproj`.

## Space isolation

Every persistent Space owns its own browsing state. A Space boundary includes:

- the engine profile: a WebKit website data store or a Chromium profile, with its cookies, cache, and sessions
- tabs, pinned sites, folders, history, archive, and appearance
- Crest Passwords and credential matching
- content-blocking and permission state
- synchronization records and deletion tombstones

Private Spaces use non-persistent engine storage and do not join normal persistence or sync. Quick Window and Peek are transient presentations, but deliberately borrow the selected Space's session boundary when a signed-in preview is useful.

Space deletion is coordinated across browser state, website data, credentials, sync records, and window restoration. A stale synced record must not resurrect a deleted Space.

## Data and synchronization

Local state is durable first. CloudKit synchronizes portable Space, tab, history, and preference records while secrets remain in the Keychain. Ordered collections use fractional positions so independent devices can insert and reorder without renumbering every record. Merge behavior is deterministic, and deletion wins through tombstones.

Crest can import browser bookmarks and sessions, and its portable archive format keeps migration separate from live CloudKit records. Archive readers validate identifiers and relationships before applying imported state.

The core reads other browsers' data. Its import readers share URL and whitespace sanitation while retaining their own title limits, fallback rules, and errors. An import is one core intent, saved with its sync journal before it returns.

## Windows on macOS

**New Window** opens another view of the same browsing workspace. The core owns the session and what each window shows (`ShowSpace`, `ShowTab`). Each window's `BrowserStore` reads the core's read model and sends intents, so an edit is visible in every window before it is saved. A sync merge commits only against the revision it read, so stale background work is refused. A restored window keeps its own Space and tab selections, including an intentionally empty selection.

Normal windows share a `BrowserPageRuntimeStore` and one `BrowserPageHost` over the workspace. Each tab has one `BrowserTabRuntime` owning its live page and native history. The focused window hosts the live view; other windows showing the same tab use its preview and can take over presentation. Native tab models share the same workspace lifetime. Closing a normal window releases its presentation while retaining shared tabs and their loaded state.

**Blank Window** creates a temporary workspace with no initial tabs. It borrows the source Space's website profile, credentials, permissions, identity, and settings. Its tabs, pins, folders, history, archive, favicons, and tab-state storage remain local and in memory, with no sync coordinator or window restoration. Settings edit the canonical source profile through a separate selection facade. Source policy changes apply immediately; removing or replacing the source profile ends the temporary workspace. Closing it discards its local browsing records.

Dragging one tab between workspaces moves its existing identity and runtime, including native content models and retained navigation state. The destination receives a Current tab without source folder or split membership, and the transfer does not archive the source tab. An empty source window stays open. A tear-off prepares a destination first and commits only after the native window attaches and both model and runtime assignments pass validation. Cancellation or a stale assignment leaves the source tab in place.

The torn-off window appears with the grabbed point on its measured sidebar row aligned to the release location, constrained to that display's usable frame. Placement is applied once before revealing the window; later sidebar layout changes do not move it. If the row cannot be measured promptly, the committed window appears at the drop location without discarding its tab.

A window a page asks for, such as a sign-in popup, opens as a Quick Window over the window that shows its opener, in the opener's Space and on the opener's engine. It never becomes a window of its own.

Crest's windows stay movable, so Move & Resize, the green button's tiling, the Globe-Control tiling keys and a display change all move them. The window's content extends under the title bar, where the window server would otherwise drag the window by a press at the very top of a page. While the pointer is on a page under the title bar, or 32 points below it, the page's `BrowserPageTitleBarTracker` claims the window's `BrowserWindowTitleBarGuard`, which makes the window unmovable until the pointer leaves; holding Globe and Control hands the window back for the tiling keys. Crest's own chrome, the navigation strip and the backdrop, acts as the title bar (`BrowserWindowTitleBarSurface`): it moves the window and runs the double-click action the person chose in System Settings.

## Scenes on iPhone and iPad

The mobile app declares a `WindowGroup` keyed by `MobileWindowRequest` and supports multiple scenes on iPad. Each scene shows its own selections over the shared workspace, so tab and Space edits reach other scenes immediately. Each scene owns a separate `MobileBrowserPageStore`, live WebKit views, native tab runtimes, and private browsing session. Sharing tab records does not share a live page or its form state between mobile scenes.

The macOS window coordinator, live-page handoff and mirrored preview, Blank Window commands, and tab tear-off placement are composed only by the Mac app. Mobile keeps its existing scene lifecycle and keyboard shortcuts; it uses the shared data and persistence safeguards without adopting those Mac presentation features.

## Credentials and privacy

Crest Passwords are stored in the Keychain and matched by origin. Each Space can disable Crest-owned suggestions, generation, save prompts, and HTTP-auth reuse without deleting its stored credentials. Sensitive reveals and exports require device authentication. Page-to-app credential messages are schema-checked and origin-bound.

The privacy manifest is shipped from `CrestShared/Resources/PrivacyInfo.xcprivacy`. The macOS app declares Apple's approved Web Browser Public Key Credential entitlement for system passkey access and the iCloud Passwords helper. Its signing profiles must include that capability; system passkey access also requires the user's authorization. Other managed capabilities remain gated on platform-specific Apple approval.

On macOS, Crest requests browser-wide passkey consent through AuthenticationServices when the first foreground HTTPS page opens, only if the system decision is undetermined. WebKit handles website credential requests directly, and Chromium sends them to the system passkey sheet; Crest does not intercept WebAuthn calls or insert permission checks into sign-in. Settings shares the same consent controller. On WebKit, file uploads validate reads in the host app before handing paths to the engine, retain picker security scopes until the page is removed, and surface denied access with a route to system settings. Chromium uses its own file chooser.

## Engine boundary

The core decides navigation, download, content-blocking, authentication, permission, failure-recovery and website-data rules. `BrowserPage` holds an engine-neutral `BrowserPageEngineAdapter`, whose `BrowserPageEngine` supplies the page view, and each engine adapter supplies the engine services. Capabilities declared in `BrowserEngineRegistration` decide which features the UI offers. Shared policy adapts presentation to the current layout and input capabilities.

`BrowserFaviconSession` owns capture, fallback, and retry lifetime through a document adapter on WebKit; Chromium reports favicons itself. Authenticated icon discovery stays inside the live WebKit context; public fallback remains credential-free and profile-scoped. Native pages invalidate requests on navigation and icon changes and stop them on removal.

`BrowserReaderModeSession` owns request cancellation and document changes through a document adapter; Reader is WebKit-only. `BrowserCredentialSession` shares origin validation and filling on both engines: WebKit pages deliver its content bridge through their own user content controller, and Chromium pages through the engine port's `BrowserPageContentScripting`, which runs Crest's bridges in an isolated world the page cannot reach. Each page's live state, its address and the one it is heading to, title, loading, back and forward availability, security, failure and media activity, lives in the core's `Pages`: the engine reports a `PageSnapshot` at most once per turn through `EnginePageReporter`, and views read the page's `PageStateModel` from `CoreState.pages`. Progress, find, hovered links, fullscreen and zoom stay on the page as presentation. An address the person types or chooses, and a page's first load, go through the core's `Navigate`, which resolves it by the Space's search rules and asks the page's engine to load it.

Shared page operations own common navigation and media behavior. `BrowserPageContentRuleSession` tracks only Crest's WebKit content rules, and `BrowserTabStateCoordinator` owns archive eligibility and pending copies without retaining pages. Platform stores apply a shared reconciliation plan and retain their own presentation and memory-pressure policies. On macOS, each `BrowserTabRuntime` owns one live page. Releasing the tab releases that page and its native history.

## Platform shape

Regular-width layouts share a persistent sidebar, page surface, Space switcher, pinned sites, saved tabs, current tabs, and archive. Compact-width layouts present the same data through compact navigation and sheets. Settings belongs in the browsing canvas at regular width and uses a sheet only at compact width; the current layout determines presentation, including after a window resize.

Shared views read independent interaction capabilities from their environment. Touch, hover, organization, and navigation transitions describe what the hosting shell supports; they are not device identities. Container width and Dynamic Type remain environmental inputs. Shared components own common content and actions, with accessory slots or optional actions for native presentation differences.

Each window and browsing mode owns a `BrowserSidebarInteractionState` for drag sessions and measured reorder geometry. The root supplies it to sidebar and page surfaces; repeated root composition reuses its live connection. Practice and previews compose their own owner. Geometry registration and target resolution are separate collaborators of the reorder lifecycle. `BrowserStore` reports session reset and tab relocation through a weak, domain-only observer, so application state never constructs or retains feature presentation.

Platform roots compose scenes, supply persistence and system services, host the engine's page views, and translate native input. Shared handlers own interaction state, source validation, cancellation, and commitment. Content-blocking reconciliation decides reload policy once, while platform page stores apply that decision to their resident pages.

Split large views at responsibilities such as a widget deck, media controls, or an import workflow. Keep related local helpers with their owner, reuse components wherever behavior repeats, and name interaction thresholds and design metrics where they are owned. Comments explain constraints and lifecycle decisions that the code cannot state directly.

The application supports Apple silicon only.

## Validation

Use focused tests for browsing state, persistence, privacy, and other durable behavior. Run the relevant tests and affected platform suite. Repository scripts cover identity, cache hygiene, browser fixtures, and release validation. Review layout, animation, and styling in the running app.
