# Engine abstraction

Crest has one engine contract with two bindings, WebKit and Chromium, and keeps
every browser rule in the portable core. This document lists who owns what,
the rules every engine keeps, what each engine lacks, and how to place a new
feature. Read [ControlPlane.md](ControlPlane.md) for how the design works, and
[CoreArchitecture.md](CoreArchitecture.md) for the modeling rules.

## Ownership

| Layer | Owns | Never owns |
| --- | --- | --- |
| Portable core (`CrestCore`) | Every piece of browser state and every rule that must behave the same on both engines and both platforms: sessions, windows and what each shows, pages and their live state, prompts, downloads, site permissions, credential policy, search and completion, import and export, setup, shortcuts, launch policy, behavior preferences, engine registrations and per-site engine choices, storage and sync | Rendering, input, scrolling, compositing, engine handles, image bytes, OS services |
| Engine bindings (`CrestEngines/Chromium`, `WebKitEngineBinding` and the WebKit page code in `CrestShared` and `CrestMac`) | Page creation and disposal, loads, engine navigation history, find, zoom, capture, printing, export, DevTools, extensions, download transfer, website data and cookie stores, reporting what happened to the core | Deciding browser rules; changing browser state other than by reporting events |
| Shared Swift (`CrestShared`, `CrestMac`, `CrestMobile`) | Views, layout, animation, presentation of prompts and notices, native windows and cards, OS services (Keychain, CloudKit transport, notification delivery, LaunchServices) | Engine types or `#if CREST_CHROMIUM_HOST` outside the engine code; second copies of core rules |

Scrolling, pointer input, compositing, focus and page zoom stay inside the
engine and never cross the core boundary. A core intent owns every saved or
shared transition, and a binding reports what the engine did.

Rules every engine keeps:

- A Space is one profile on every engine. No path may share a profile across
  Spaces, or create a page, transfer, export or network request for a locked
  Space without a grant. The core gate covers intents and borrowing; the
  presentation layer must not build content for a locked Space.
- A private window is incognito on every engine. Its profile is new each time
  private browsing opens, shares nothing with any Space, runs no extension a
  person installed, and is destroyed with everything in it when the window
  closes.
- Crest never opens a window the person did not ask for. New windows appear
  only from a person's action or an extension's `windows.create` for a normal
  window. An extension's popup opens as a tab in the current window, and a
  window a page asks for, such as a sign-in popup, opens as a Quick Window over
  its opener's window. DevTools and side panels dock inside the Crest window.
- A page another page opens stays on its opener's engine. A site's engine
  choice and the default engine apply only to pages the person opens.
- Capability declarations in `BrowserEngineRegistration` describe what the
  binding really does. The core offers what the default engine supports and
  what each engine a page is open on supports, and the page's own engine
  enables it. UI never gates on build flags.
- Unsupported features have explicit product behavior. Reader, built-in
  content blocking and protected media are unavailable on Chromium by
  decision; a page that needs protected media switches to WebKit after before-unload checks, unless a website rule already chooses its engine.
  Whole-page translation works on both engines: each engine adapter supplies
  the page's main document as a `BrowserTranslationDocument`, which runs the
  same translation bridge through WebKit's content world or Chromium's content
  scripting. Selection translation works on both engines.

## Current state

The core owns the session, the device and the pages on every shipping target.
On macOS the Chromium composition (`CrestChromiumUIProduct`, packaged by
`package-chromium-host.py --product`) is the only desktop product, with
WebKit registered beside it. The WebKit-only `Crest` target is not published;
its Developer ID export supplies the product's resolved entitlements. `CrestMobile`
runs WebKit on iPhone and iPad.

Chromium's binding is portable C++ inside the engine, keeps Chromium's
`Browser`s and reports to the core directly; its Mac shell only hosts page
views, popups and system sign-in in the windows Crest's shell opens. WebKit's
binding is Swift, shared by macOS and iOS. `BrowserPage`
(`CrestMac/Infrastructure/Pages`) holds an `any BrowserPageEngineAdapter` and
names no engine type. `MobileBrowserPage` is typed over WebKit by design,
since iPhone and iPad run only WebKit. `project.yml` selects each composition's entry point,
engine registration and engine-contributed views by file, and no Swift outside
`CrestEngines` tests `CREST_CHROMIUM_HOST`.

One shared page host, `BrowserPageHost`, keeps each workspace's pages on the
Mac, iPhone and iPad, and one shared page owner, `BrowserPageOwner`, does the
rest of the work both platforms' pages have in common, including hosting the
pages the core opens itself. `BrowserPagePool` and `MobileBrowserPageStore`
keep only presentation and each platform's own commands. WebKit's binding
keeps each profile's website data store and compiles the content rules its
pages are built with.

Engine glue, the page hosts and the tests read the core's read model.

Both Mac products run one AppKit shell (`CrestMac/App/Shell`), which owns
every window, the menu bar, launch and recovery, reopen, the Dock menu and
tile, external opens, system sign-in and quit. The WebKit product owns its
process through `CrestMain`. The dual-engine product starts Crest's native
application, core and shell before loading Chromium. `ChromiumRuntime`
starts Chromium's normal browser loop on the first page or extension that
needs it, attaches its binding to the existing core and replays pending
commands. Crest retains its application delegate and windows throughout the
handoff. Chromium supplies an event adapter for its native views and
accessibility, and receives termination notifications for its normal shutdown.
Once loaded, Chromium remains initialized until quit. A local key monitor runs
Crest's shortcuts before Crest's own views, and only the commands the core
reserves from pages before a focused page, which sees the rest first and hands
what it lets go to the menu bar. The shell's decisions are core queries
and intents: the windows a launch reopens and the setup in front of them, the
window a reopen opens, where external opens and an engine's own windows land,
whether a quit or a window's close may go ahead, and the menu layout and the
launcher's commands. The shell keeps only what AppKit does: window kinds,
frames, focus, AppKit's standard menus, and the Dock tile, which draws the icon
the person picked and a badge for the core's download progress.

A new engine on the Mac supplies:

- a binding for the engine contract, with the capabilities
  `BrowserEngineRegistration` declares for it;
- a `BrowserMacEngineHost`: the About panel's credits, releasing what it kept
  for a closed window and the profiles named, and a key equivalent no Crest
  command claimed;
- an on-demand runtime integration when the engine needs its own browser
  loop, preserving the native application's delegate, windows and core.

A new platform shell supplies:

- its windows, with their kinds, frames and focus;
- menus built from `ShortcutMenu`, a launcher offering each command that
  `OffersInPalette`, both narrowed to what the device offers;
- the presentation of the core's answers to launch, reopen, external opens,
  engine windows, the app icon's menu, and quit and close;
- its own standard menus, the app icon and its badge, and the OS services.

## How each engine behaves

Both engines:

- Script dialogs, before-unload, and HTTP Basic and Digest challenges are
  questions the binding raises with the core, which the page's host presents.
- Permission requests are questions the binding raises with the core, which
  answers from the Space's choices or asks the person. Chromium receives
  decisions as content settings; WebKit applies them through its delegates, and
  withdrawing a camera or microphone grant ends capture.
- Each page's live state carries an engine-neutral `PageSecurity`, whose
  members carry the title, symbol and detail Site Controls shows. Chromium
  reports it in every snapshot; WebKit derives it from the scheme, mixed
  content, the trust result and any override.
- On the Mac, a document's notifications reach Crest's own system delivery:
  the core decides whether one shows, a click brings its tab forward, and the document
  hears the click.
- Both engines run their downloads as the engine's own and report them to the
  core's ledger. Archives follow the engine: `.webarchive` on WebKit, `.mhtml`
  on Chromium.
- The core publishes the registered engines and what the device offers as
  `EnginesChanged`. Menus, the launcher, settings and the shortcut settings
  offer that, and the page a command acts on enables it through its own
  engine: on the Chromium product, Reader appears once a WebKit page is open
  and stays dimmed on Chromium pages. Internal pages follow the
  `internal-pages` capability, and every declared capability gates UI or
  services or belongs to `EngineCapability.Required`.

Chromium:

- Crest's bridges run in an isolated world the page cannot reach. Link hover,
  user activity, blocked popups, media sessions and favicons arrive as engine
  presentations. The credential bridge runs through the same content-script
  channel; capture, fill, save and recency rules are core queries that carry
  no password. The host turns Chromium's password manager off for every page.
- Page fullscreen reports its state to the shared shell, which shows the video
  without browser chrome and restores the shell on Escape.
- The file chooser and the color picker are Chromium's own surfaces, since the
  host has no hook for them.
- Focus restoration relies on the engine's responder chain.
- Certificate errors show Chromium's own interstitial, and proceeding is the
  engine profile's decision, as its registration declares. Crest has no
  proceed-anyway of its own.
- The host has no command to stop live camera, microphone or location use;
  revocation relies on Chromium ending capture once the setting blocks it.
- Local service-worker and extension notifications belong to the profile,
  independent of an open page. The core checks Space access and site permission
  through `ProfileNotificationDisplayCheck`; Chromium also checks extension
  permissions. The native host checks again around asynchronous system delivery
  and before clicks, and withdraws notifications after access is revoked.
  Private profiles do not deliver them. This does not provide remote Web Push
  or wake the app after it quits.
- Chromium reports whether each download can pause or resume. Core intents
  authorize the action and the binding calls the existing `DownloadItem`;
  resuming never approves a dangerous-download warning or recreates a removed
  download record. WebKit does not expose pause and resume through this contract.
- Relayed blocked popups follow each Space's automatic-popup decision, and
  allowing the site opens the popups the blocker held back.

WebKit:

- WebKit reports each page's media activity to the core as it changes,
  including its Picture in Picture activity, so residency never asks pages
  first. A page it closes keeping its state hands the core its history, which
  the tab's next page restores.
- A staged Peek carries the URL and referrer only, because WebKit does not
  expose the initiating frame's security context to a second page; the
  registration declares that limit.
- WebKit has no extensions; its registration declares `extensions`
  unavailable.
- Two shared files still name WebKit types: `CredentialContentBridge.swift`
  installs the WebKit credential bridge, and the transient page lease carries
  WebKit content-rule lists.

Neither Quick Window nor the setup windows host an extension side panel.

## The core's surface

Every rule aggregate is core domain and application code with focused tests,
reached through typed intents and queries. Queries that need no session are
answered without an app (`crest_core_answer`): address and page comparisons,
translation choices, import discovery, launch isolation, branding
normalization, page presentation, external links and local documents, scheme
handling, authentication handling and labels, media session arbitration,
secure origins, notification requests, blocked popups and automatic
downloads. Launch cleanup and retention run as the core's
`SweepExpiredRecords` intent.

| Aggregate | Core surface |
| --- | --- |
| Downloads | The download intents and changes, and the `DownloadProgress` and `DownloadRisk` queries; the engine download events and commands |
| Credentials and passkeys | The capture, fill, save-check, recency, save-match, save, strong-password, passkey and system-password queries, which carry no password; `CredentialImportPreview`, `PasswordImportPreview` and `CredentialExport`, which carry passwords the core never keeps |
| Site permissions | The permission intents and the `SiteDecision` and `CaptureDecision` queries |
| Search, completion and the palette | `SearchProvider`, the search engine intents, `PaletteSuggestions` |
| Windows, sidebar and setup | The window intents, the sidebar outline and drop targets, `SelectionPreview`, the setup draft and flow intents and `FinishSetup` |
| Shortcuts, menus, launch and media | The shortcut intents, `NumberedSelections` and the `ShortcutMenu` layout; `LaunchIsolation`, the launch plan, `LaunchWindows`, `WindowToReopen`, `EngineWindowPlacement` and `PrepareToQuit`; media session arbitration |
| Behavior preferences | The session's `appPreferences` record behind `SetAppPreferences`, `SetTranslationRule` and `ImportAppPreferences` |
| Links and Quick Window | `LinkNavigation`, `RouteExternalLink`, `RouteLocalDocument`, `ExternalWebLink`, `ChooseExternalLinkDestination`, `RememberQuickWindowSpace` and the link preference intents |
| Engines | `EnginesChanged`, `EnginePreferencesChanged`, `SelectDefaultEngine`, `EditEngineRule`, `ForgetEngineRule`, `ChooseSiteEngine`, `RehostPage`, `ProtectedMediaUnavailable` |

The device stores a preferred default engine and exact-origin website rules
locally. Settings edits the same rules that page-menu choices and protected
media fallback use. Private choices remain scoped to their private Space.
Changing the default starts no engine and moves no existing page. An
unavailable preference is retained but falls back to the product's default.
Chromium is the dual-engine product's recommended default. WebKit preference
keeps Chromium unloaded until a Chromium website or extension is opened.

These stay in Swift by design: heraldry vocabulary and composition, favicon
palette extraction, sidebar widgets, Peek motion and presentation phases,
tear-off placement geometry, drag geometry and default-browser prompt cadence.

## Builds and packaging

- The builds are `Crest`, `CrestChromiumUI`, `CrestChromiumUIProduct` and
  `CrestMobile`, with `dotnet test`, `lint-dotnet.sh` and the C and C++ ABI
  checks.
- Review packaging for runtime checks runs
  `Scripts/control-plane/apply-chromium-host.py`, then
  `build-chromium-baseline.py`, then `package-chromium-host.py` in review mode
  with a throwaway user-data directory. Never launch the unbranded Chromium
  build directly, because its keychain item prompts.
- Product packaging: `.github/workflows/release.yml` and
  `.github/workflows/experimental-release.yml` download
  the prebuilt engine, packages `CrestChromiumUIProduct`, signs it with Crest's
  entitlements and embedded provisioning profile, and notarizes it.
  Never use the review entitlements file for the product: it turns on the app
  sandbox and would strand installed data.
- The Safe Storage keychain item name must not change. A rename rotates the
  encryption key and resets Chromium's tracked preferences.
- `release.yml` publishes the Chromium composition as the only Mac download.
  Each feed keeps a `-webkit` twin that offers the same installer, so an
  installed WebKit-only build updates into it. `project.yml` defaults to the
  development update channel. Update feeds follow the product family,
  independently of the chosen engine preference.

## Not built, by decision

- A Crest color picker for `<input type=color>`. Chromium's own picker is used.
- A Crest popups UI beyond the blocked-popup relay and Site Controls.
- A Crest presentation for JavaScript alerts beyond the shared dialog
  presenter.
- System Picture in Picture on Chromium. Chromium's video PiP uses its own
  Views window; a system PiP needs a video-frame bridge from Chromium's video
  surface. Do not use macOS's private PIP framework without a separate product
  decision.

## Ownership decision guide

Use this when a new feature arrives:

1. Must the outcome be identical on WebKit and Chromium, or on Mac and iPhone?
   Then it is a core rule: an intent when it changes state, a query when it is
   an answer, and a change or read-model value for what the UI shows.
2. Is it rendering, input, scrolling, compositing, an engine handle or a
   platform service? Then it is binding or platform work. Declare a capability
   in `BrowserEngineRegistration` if an engine may lack it.
3. Is it layout, animation or presentation state? Then it is shared Swift, and
   it gates on what the core offers and the page's engine supports, never on
   engine `#if` flags.
4. Does it touch a locked Space? The core gate must reject it, and the
   presentation layer must not build its content.
5. Does it open a window? Only from a person's action or an explicit extension
   request; a window a page asks for opens as a Quick Window over its opener's
   window. Otherwise it reuses the current window or docks inside it.
