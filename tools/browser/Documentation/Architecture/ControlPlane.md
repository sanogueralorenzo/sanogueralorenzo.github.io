# Portable browser control plane

Crest's browser state and rules live in one portable core, `CrestCore`, written
in C# and compiled with NativeAOT. Each Apple platform supplies its SwiftUI and
AppKit or UIKit views, its engine bindings and its OS services. On macOS
Chromium is the default engine and WebKit stays registered beside it; iPhone
and iPad use WebKit. Both engines, both platforms and every composition share
the same core, the same UI and the same sync records.

This document describes the design as the code implements it.
[Core architecture](CoreArchitecture.md) sets out the layers and the modeling
rules, and [Engine abstraction](EngineAbstractionCompletion.md) lists what each
engine lacks. [The contract](../../CrestContracts/README.md) describes the C ABI
and the wire in detail.

## Compositions

| Target | UI | Engines | Launch |
| --- | --- | --- | --- |
| `CrestChromiumUIProduct`, packaged by `package-chromium-host.py --product` | `CrestShared` and `CrestMac` inside the Chromium host | Chromium (default), WebKit | Installed; the default desktop download |
| `Crest` | `CrestShared` and `CrestMac` | WebKit | Not published. Its Developer ID export supplies the resolved entitlements for release and local release packages |
| `CrestMobile` | `CrestShared` and `CrestMobile` | WebKit | Installed |
| `CrestChromiumUI`, `CrestNativeCore`, `CrestMobileNativeCore` | The same UI | As their product | Review: `CREST_REVIEW_BUILD` names an isolated launch |

A review build keeps its own named isolation, session, credentials prefix and
website data stores, so it never reads or writes the installed app's data. A
test run the Mac review build hosts stays unnamed and keeps nothing, as in
every other host.

## Ownership

| Owner | Responsibilities |
| --- | --- |
| `CrestCore` | Every piece of browser state and every rule: workspaces, Spaces and their profiles, tabs, folders, splits, history, archive, windows and what each shows, pages and their live state, the questions pages ask, downloads, site permissions, credential policy, search and completion, import and export, setup, shortcuts, launch policy, behavior preferences, engine registrations and per-site engine choices, storage and sync |
| Engine bindings | Creating, loading and closing pages; engine navigation history; find, zoom, capture, export, printing and DevTools; extensions; network, cookie and website data stores; reporting what happened to the core |
| Apple OS services | CloudKit transport and account state, Keychain and system authentication, notification delivery, file panels, default-browser registration, software updates, the favicon image store |
| SwiftUI and AppKit/UIKit | Views, layout, animation, hover, scroll position, window frames, sidebar width, appearance preferences, presenting the prompts the core asks for, embedding engine views |

Rendering, input, scrolling, compositing and focus stay in the engine and the
views. They never make a round trip through the core. Image bytes and opaque
engine data stay outside the core's records, except where a record names them
by reference.

### Two paths

The UI reaches the core and the engines through two objects, and each call
site shows which one it uses.

- **Through the core.** A state change is an intent sent with `core.send`,
  and a question is a query asked with `core.query`; a query that needs no
  session is asked with `CrestCore.answer`. The UI reads state only from the
  read model, `core.state`.
- **Direct to the engine.** View work goes to the page's engine: embedding
  the view, input, scrolling, zoom, find, reload, back and forward, DevTools,
  printing, capture and export. What that work causes, such as a committed
  navigation, reaches the core as an engine event.

## The typed contract

Everything that crosses the boundary is a C# record or fixed set in the
`CrestCore.Contracts` namespace. The contracts share the core's one assembly
with its domain and application, which keep folders and namespaces of their own
(`Contracts`, `Domain` and `Application` under `CrestCore/src/CrestCore`):

- **Intents** change state (`OpenTab`, `ChooseSiteEngine`).
- **Queries** answer without changing it (`PaletteSuggestions`, `SiteDecision`).
  A query that needs no session, such as `LaunchIsolation` or `NormalizeBranding`,
  is a `StandaloneQuery`, which `crest_core_answer` answers without an app.
- **Changes** carry the state an intent or the core's own work produced
  (`TabsChanged`, `EnginesChanged`), or name an event the UI reacts to
  (`PageRehosted`).
- **Rejections** name the rule that refused an intent (`SpaceLocked`,
  `UnregisteredEngine`). A rejection a person reads carries its `[Localized]`
  message.
- **Engine commands, engine events, page requests and engine presentations**
  form the engine contract (see "Engines").

Each message carries its own behavior. `Intent` declares `Route(CrestApp)`,
and each family's base routes its cases to the area that owns them, most in
one of the app's turns (`CrestApp.Turn`), which stamps pages, prunes what a
gone page asked and delivers engine commands afterwards. Each case overrides
its family's own method with its logic: `SessionIntent.Edit`,
`WindowIntent.Apply` and the other device families' `Apply`,
`PageIntent.Apply`, and the families of downloads, prompts, close
preparations, data deletion, Space access and cloud sync
(`CloudSyncControlIntent.Steps`, for one). A prompt's answer knows which area
asked it. An engine event routes itself the same way (`EngineEvent.Route`),
and the page, prompt and download events each apply themselves to their area.
A query answers itself (`Query.Answer(CrestApp)`), under the app's lock unless
it says it reads nothing the app holds (`AnsweredUnderLock`); a
`StandaloneQuery` answers from the question alone
(`Answer(StandaloneContext)`), which is how `StandaloneAnswers` answers a host
without an app. An engine's question answers itself the same way
(`EngineQuestion.Answer`). The records keep the `CrestCore.Contracts`
namespace and live beside the area that receives them, and a new case without
its logic does not compile.

Swift receives each union as an enum, and each case's payload carries its
logic the same way, in an extension beside its receiver: a change applies
itself to the read model (`apply(to: CoreState)`, in
`CrestShared/Infrastructure/Core/Changes/<Area>/<Change>+CoreState.swift`), an
engine command performs itself on the WebKit binding (`perform(on:)`, in
`Infrastructure/WebKit/Commands`), a page request answers itself from WebKit's
pages (`answer(on:)`, a requirement of `PageRequest`, in
`Infrastructure/WebKit/Requests`), and a presentation presents itself on the
Chromium engine (`present(on:)`, in
`CrestEngines/Chromium/Apple/EnginePresentations`). Each
enum's method only forwards, with an exhaustive switch: the generator writes
`Change.apply(to:)` and `EnginePresentation.pageID`, and each binding writes
its own forwarder beside its payloads' files. A new case without its logic
does not compile. Code that listens for a few cases, such as the prompts a
page shows, matches them with `if case`.

`CrestCore.Generator` reads the records, the types the core exports in that
namespace, and writes the core's codec, the Swift
models and codec, the C header with each type's tag and the schema
fingerprint, and the C++ engine codec. No source spells a wire tag, and no
model is written twice by hand. Run `Scripts/control-plane/generate-contracts.sh`
after changing a contract; the lint script and the Apple core build fail while
the generated files are stale.

- A fixed set is a sealed class whose static instances carry their data, their
  `[Localized]` titles and any rule that differs by member. Swift receives a
  struct with the same members. A member's wire tag is its index in `All`, so
  `All` only grows at the end. A set with runtime members, such as a Space's
  custom search engines, is `[OpenSet]` and never crosses by tag.
- A record whose constructor normalizes its fields, such as `SiteOrigin`, is
  `[NormalizedOnConstruction]`; Swift gets only a labeled wire initializer and
  a normalizing platform initializer.
- A message's byte limit is data on its type (`[MessageLimit]`), which the
  dispatcher checks before it reads the message.
- A record that holds a password is `[HoldsSecrets]`: its text names no
  secret, and a containment test proves no change, intent, stored session,
  device record or sync journal reaches it. An answer buffer is cleared when
  it is freed. The credential questions keep no state: capture, fill and save
  take only identities and metadata, and importing or exporting a password
  file are the only questions that carry passwords, which the core answers
  from the question alone.

### Resolved values and seeds

A `[Resolved]` property is a value the core computes from a record's fields
and publishes with it, such as a tab's icon mode or a Space's sidebar outline,
so no UI works out the rule again. Resolved values travel only from the core
to the platform. Where a message the platform sends holds a record with
resolved values, the generator emits a fields-only seed, `X.Seed`, and the
message takes the seed: `OpenWorkspace` takes a `SessionState.Seed`, for
instance. The core resolves the rest when it reads it. A published record
gives its seed back as `.seed`. No stored or synced format holds a resolved
value, because the stored and synced formats have hand-written codecs.

Every other record a message the platform sends holds is one the platform
builds, such as a Space's branding or the app's preferences, so its Swift
fields are variables, as a seed's are. A settings pane reads the record from
the read model, edits a copy in place and sends the whole record back.

### The C ABI

The ABI is synchronous and handle-based. `crest_app.h` is the typed
application API (`crest_app_create`, `dispatch`, `query`, `drain`,
`set_wake`, `end_turn`, `restore`, `settle_sync`), `crest_engine.h` the engine
contract (`crest_engine_register`, `report`, `unregister`), and
`crest_core.h` the version and the standalone answers. `crest_app_create`
takes the schema fingerprint and refuses any other, so a stale prebuilt core
fails at launch instead of misreading data. Nothing crosses as JSON.

## The read model

The core publishes typed changes and never resends unchanged state. It derives
them by comparing each accepted state with the one before, so no change can be
forgotten. Changes are keyed by workspace, because the persistent session,
private browsing, borrowed workspaces and Quick Windows are open at once.

An intent answers with the changes still pending from earlier, then its own,
so an older change never lands after a newer one and the caller reads the new
state straight away. Changes the core starts itself (a finished save, a sync
merge, an engine event) arrive through a payload-free wake callback that the
UI answers by draining the pending batch, at most once per main-queue turn.

`CoreState` is the Swift read model. Only the changes `CrestCore` receives
update it, each through its own `apply(to:)`. It is observable per entity:
each workspace, Space, tab, folder, window and page is an object that notifies
only when one of its values really changes, so a tab's new title redraws that
tab's row and nothing else. Every value is stored
before it is announced (`BrowserStoreFirstObservable`), so a view rendering
during an announcement reads the new value. A generator check refuses views
that read a whole read-model list's `.values`.

Views, engine glue and page hosts read the read model directly. `BrowserStore`
is the per-window facade that sends intents and answers what a window shows;
it holds no browser state of its own. Tests and previews build sessions as
typed seeds (`SessionState.Seed`) and read them back from the read model.

Each workspace also announces its session as a whole: its `sessionRevision`
advances once for each batch that changed any of it. A window's revision
(`BrowserSessionRevision`) joins it with the window's own moves, and the
window's root view follows that one value to reconcile the window's pages and
what the window keeps of its own, such as its multi-selection. The read model
keeps the images of the session the core keeps in its file in the favicon store
beside that file, following each batch that changes the session.

## State the core keeps

| Object | Holds | Saved | Synced |
| --- | --- | --- | --- |
| Workspaces (`NativeSessionAuthority`) | The persistent session and every memory-only one: Spaces with their profiles, tabs, folders, splits, history, archive, app preferences | The persistent session | Yes, through the journal |
| `Device` | Windows and what each shows, split column shares, per-site engine choices, site permission choices, shortcuts, link preferences, setup, adoptions | In the device store; memory-only Spaces' choices stay in memory | Never |
| `Pages` | Each open page: its owner, window, engine, phase and live state | Never | Never |
| `Prompts`, `ClosePreparations` | Questions waiting on the person; a close or quit in progress | Never | Never |
| `Engines` | The registered bindings, their capabilities and what the device offers | Never | Never |
| Downloads | The ledger of this run's downloads | Never | Never |

### Sessions and commands

Each store family's session lives in one `NativeSessionAuthority`, attached to
the core's device as a workspace (`OpenWorkspace`, `BorrowSpace`). Every edit
is a typed intent that names the window that issued it, because some rules
read what that window shows. An intent is prepared against the state it saw
and commits only while that state is still the accepted one; a rejected or
stale preparation changes nothing. When it commits, the device moves the
issuing window to what the intent chose and repairs every other window of the
workspace.

Each session intent carries its own edit: `SessionIntent` declares
`Edit(NativeSessionAuthority, SessionTurn)`, which returns the `SessionEdit`
the intent makes to the accepted session the turn reads, and every case
overrides it in its own file under `Application/Session/Intents`. The
authority computes the basis, hands the turn to the intent under its gate and
validates what comes back. A sidebar drop commits the intent its kind decides
(`Committed`), an import checks the session it leaves whole, and only a tab
moving to another workspace's window moves across workspaces.

A Space and its profile are one to one in every accepted document. Borrowed
workspaces (Blank Windows, detached tabs) bind their source Space and profile,
keep their own local collections that are never saved or staged, and close
when the source Space goes. A borrowed workspace never edits its Space's
settings; the core refuses with `BorrowedProfileRequiresOwner`.

The session model covers tab lifecycle and placement, folders, splits,
multi-selection batches, cross-Space and cross-workspace moves, Quick Window
and Peek promotion, history and archive with their retention, sidebar outlines
and drop targets, imports, and Space creation, identity, appearance,
preferences, access policy and deletion.

### Locked Spaces

`SpaceAccessAuthority` holds this process's grants, driven by
`BeginUnlockingSpace`, `FinishUnlockingSpace`, `LockSpace` and `LockAllSpaces`,
each of which publishes `SpaceLockChanged`. The native access controller
presents Apple's authentication prompt, answers with its result and reads each
lock from the read model. Grants match both Space and profile identity and
never enter storage or sync.

A session rejects a prepared intent that would read or change a locked Space
with `SpaceLocked`, before any preparation runs. Raising protection, deletion,
and retention sweeps still apply to a locked Space, since none of them
returns its content. Sync is not gated, so background convergence continues,
but a merge can raise protection and never remove it where this device holds
no grant. Native page, credential and extension callers keep their own gates,
so the core gate is defence in depth.

### Windows belong to the device

Which Space a window shows and the tab it shows in each Space are the device's
window state, never part of the session. A window opens with `OpenWindow`,
closes with `CloseWindow`, and changes what it shows with `ShowSpace`,
`ShowTab`, `DismissShownTab` and `ResizeSplitColumns`; the core publishes
`WindowChanged` and Swift renders each window from `core.state.windows`.
Showing a tab records its `lastActivatedAt` as a change of its own. Cleanup
keeps every tab an open window shows and every tab a saved window's record
shows. Windows over the persistent session are saved in the device store, the
sixteen used last. Sidebar width and presentation stay the platform's.

The Dock icon's menu is the core's answer to `DockMenu`, asked over the
windows as the platform stacks them: the window commands (`DockMenuCommand`),
then the persistent session's Spaces in order, each with whether the frontmost
window shows it and whether it is locked, and the window a chosen Space shows
in. That window is the frontmost over the persistent session, never a private
or borrowed one; with none open, a chosen Space opens a window on itself. Both
Mac apps draw it with the Space switcher's icons.

### Storage

The core owns `session.sqlite`. The host passes only a storage directory in
`AppConfiguration`. The core validates, opens and loads the file, keeps a
recovery copy, and repairs the session as its first save. The session's
parts live in the `checkpoint(part, data)` table, and the device store in its
own additive `device_*` tables beside it, which older builds ignore.

Every accepted revision is saved behind on the core's storage worker, newest
first, skipping parts whose bytes did not change, so editing continues while
an older revision is written. Commits whose effects outside the core depend on
the file save before they return: sync commits with their journal, Space
deletion, imports, batches, cross-Space moves and workspace transfers. The core
publishes `Saved(revision)` and `StorageFailed(reason)`; the `PendingSave`
query names the newest revision not yet on disk, and quitting and backgrounding
wait for it. Private, temporary and borrowed workspaces stay in memory.

An unreadable file opens native recovery UI before browser services or sync
start. `crest_app_restore`, while no app has the directory open, validates the
recovery checkpoint read-only, keeps the original database and sidecars in a
separate recovery directory, and uses an interruption marker so a partial
restore cannot become a first-install seed. A file saved by a newer storage
version asks for an app update.

## Sync

Sync stays Apple-only. CloudKit transport is an OS service; the core owns the
records, merging, ordering, scheduling and the payload codec.

- `NativeSyncAuthority` is attached to the persistent workspace and owns the
  accepted journal and its staging. Private and temporary workspaces cannot
  attach it. The core stages every accepted revision itself, on a worker,
  from the revision's immutable state. Each intent carries the reason its
  removals are deleted for and how soon it stages. A burst of edits stages
  once, and each removed record keeps the reason of the edit that removed it.
  Each session change that removes records names them itself
  (`Change.RemovedRecords`): a Space that is gone takes its folders, tabs,
  archive and history with it.
- `NativeSyncJournal` updates immutable journal snapshots through `Stage`,
  `Merge`, `Replace`, `Overwrite` and `Acknowledge`. The rules that differ by
  kind of record belong to that kind's `SyncPayloadType`. A failed update
  leaves the records, clock and pending uploads intact.
- `SyncRecordBody` reads and writes each payload or tombstone in the journal's
  form and in the CloudKit form, keeps the members this build does not know,
  and computes the schema a record needs. Swift's `BrowserCloudRecordCodec` only maps
  those bytes and the envelope onto a `CKRecord`.
- Incoming records arrive as cloud sync intents (`MergeSyncRecords`,
  `MergeCloudSnapshot`, `ReplaceWithCloudRecords`,
  `ReplaceSeedWithCloudRecords`, `OverwriteCloud`). A merge computes on the
  transport's thread against a snapshot, outside the core's lock, then takes
  the lock only to commit with a revision check. The session and the journal
  are written in one transaction before either publishes. A record the core
  cannot read, or whose schema is newer, is skipped and counted in the
  `SyncRecordsSkipped` receipt; a snapshot with any skipped record is refused
  whole.
- `CloudTransportStore` keeps the transport's cursor, per-record server fields
  and flags in the device store, cleared with the reconciliation flag in one
  transaction. `CloudSyncControl` is the sync controller's state machine: its
  intents answer `CloudSyncAdvanced(status, steps)`, and the Swift controller
  only takes the steps (CloudKit calls, the transport, timers).
- The core publishes `Saved(revision)`, so the transport stores its server
  token only after the merge it covers is on disk.

### Cross-engine sync contract

The CloudKit format is engine independent: Space and profile identifiers,
Space appearance and browsing preferences, folders, HTTP and HTTPS tabs with
their saved and pinned placement, split membership, history and archive. The
same tab can be a Chromium page on the Mac and a WebKit page on an iPhone. A
profile UUID is the shared identity; its Chromium directory or WebKit data
store is the binding's detail.

Cookies and website data, engine history stacks, caches, device permissions,
per-site engine choices, extensions and their access never enter sync. Native
Settings and Start Pages, `chrome://`, `chrome-extension://`, files and other
non-web tabs stay on the device that opened them and survive incoming merges.
Private and temporary workspaces never upload. A device must not delete a
shared record because it lacks a capability. Explicit deletion stays distinct
from absence and retention: only an explicit Space deletion from another device
authorizes cleaning up the local profile.

### Isolated CloudKit review

A provisioned review app can opt into real transport with
`CREST_ISOLATED_SESSION=1`, its own `CREST_ISOLATED_PERSISTENCE_ID`, and
`CREST_ISOLATED_CLOUD_SYNC_ID`. The cloud ID is a shared lowercase ASCII slug
of at most 48 characters. Devices with the same cloud ID use the
`CrestReview-<id>` zone; each keeps its own local profile. Tests, previews,
unnamed profiles and malformed cloud IDs cannot opt in. The transport scopes
fetches, writes, references and deletion handling to that zone, and its cursor
and server metadata stay separate from production. Fresh review profiles use
the disposable first-install seed, so an existing cloud session replaces their
sample Spaces before publication.

Device builds of `CrestMobileNativeCore` request CloudKit without the
production browser entitlement. For macOS provisioning, build
`CrestNativeCore` with
`CREST_NATIVE_CORE_ENTITLEMENTS=CrestNative/Apple/Composition/MacCloudReview.entitlements`.
Chromium packaging accepts the resulting profile through
`--provisioning-profile`, validates the identity and CloudKit grant, embeds the
profile and keeps Chromium's runtime entitlements. The review package uses the
Development CloudKit environment.

## Engines

The engine contract is a set of contract records like intents and changes:

- **Engine commands** the core issues to one binding: `CreatePage`,
  `LoadPage`, `ClosePage`, `RecoverPage`, `ExitPictureInPicture` for a page a
  window shows again or one of a locked Space, `CheckBeforeUnload`, the prompt
  settlements, the download commands, the erasures (`EraseProfileData`,
  `EraseSiteData`), `AdoptOfferedPage` and `RejectOfferedPage` for a page the
  engine offered, and `StageNavigation` and `DropStagedLink` for a staged link.
  The core delivers them in the order it issued them, never while it holds a
  lock and never on the stack of the report that caused them.
- **Engine events** a binding reports: `PageCreated`, `PageCreationFailed`,
  `PageClosed`, `PageCloseRequested`, the navigation events,
  `PageStateChanged` with a `PageSnapshot`, `PageIconChanged`, `PageCrashed`,
  the prompt events, the download events, `BeforeUnloadAnswered`,
  `DataErased`, `ProtectedMediaUnavailable`, `PictureInPictureReturned`,
  `PageOffered` and `StagedLinkUnavailable`. A report is never refused; one
  about a page the core no longer knows, or one from an engine that no longer
  hosts the page, changes nothing.
- **Engine questions** a binding asks the core and has answered at once,
  changing nothing, through `crest_engine_ask`: `LinkActivation` asks where a
  link the person followed goes, by the same rules as the `LinkNavigation`
  query.
- **Page requests** the UI makes of a page's binding directly for view work,
  answered at once, and **engine presentations** the binding sends back when
  such work finishes later or when the view must show something the core does
  not keep (link hover, fullscreen, the engine's bars, extension changes, a
  document's notifications). The core never sees these.

The engine contract has its own fingerprint, covering only its wire, so an
edit elsewhere in the contracts leaves a prebuilt engine valid. The generator
writes it as portable C++20 (`crest_engine_contract.h`) that uses the standard
library alone and never throws.

### Registration, capabilities and offering

Each composition registers its bindings with its app's core: WebKit always,
and Chromium as the default in the Chromium product. `EngineRegistration`
carries the engine's kind, the `EngineCapability` members it supports and
whether new pages open on it. Every engine must support the required
capabilities (`pages`, `navigation`, `workspace-profiles`,
`profile-deletion`), and one is the default. Registration is local to the
process and never saved or synced.

The core publishes the registered engines as `EnginesChanged(EngineRoster)`,
with what the device offers: what the default engine supports, and what each
engine a page is open on supports. It republishes them when an engine
registers or goes, or when what is offered changes because a page opened on an
engine no page used or an engine's last page went. Menus, the launcher, the
settings and the shortcut settings offer what the device offers, and the page
a command acts on enables it through its own engine. A capability an engine
lacks has explicit product behavior, declared in `BrowserEngineRegistration`.
The Mac shell's AppKit menu bar (`BrowserMacMenuBar`), which both Mac products
run, builds the core's `ShortcutMenu`s, reads the same answer and hides what the
device does not offer.

### Chromium's binding

Chromium's binding is portable C++ in the engine itself
(`CrestEngines/Chromium/Overlay/chrome/browser/ui/crest/crest_engine_*`). The
engine hands the Chromium composition its binding table and its page-request
table when the UI framework starts; the composition registers the binding with
the engine contract's fingerprint, and from then on the core's commands reach
the binding directly and the binding reports to the core itself, with no Swift
or Objective-C between them. `CreatePage` names the page's window, so Chromium
creates the page in that window's `Browser` as soon as the core asks.

The binding also keeps Chromium's `Browser`s (`EngineBrowsers`): one for each
profile whose pages a Crest window shows, and those the engine creates for
itself for `chrome.windows.create`, a renderer's popup or an extension's app
window. It creates, finds and closes them, moves a page's tab between them
when its view attaches in another window, offers the tabs the engine opens
by itself, and closes a profile's `Browser`s when its Space is deleted or its
private window closes. An extension's popup is the exception to moving: its
tab shows in the person's window but stays in the popup's `Browser`, which
remains the extension's window.

Chromium's Mac shell (`crest_chrome_host.mm` behind the typed `CrestMacShell`
and `CrestMacUI` protocols in `CrestChromiumHost.h`) does only what AppKit
must: it reserves and opens the Crest windows the binding's `Browser`s show
in, hosts each page's view and the views an extension or the inspector puts
beside it, shows extension popups, runs system sign-in, and answers the close
and quit preflight. Each `Browser` is built on the shell's
`CrestBrowserWindow`, which Chromium's window factory makes for it, since
Chromium gives a `Browser` its window from its creator only in tests. Objects
and blocks never enter .NET.

A private window works like incognito and shares nothing with any Space. Its
Space gets a new profile each time private browsing opens
(`ResetPrivateBrowsing` on close), and `CreatePage` marks its pages private.
Chromium gives each private profile its own in-memory profile, always derived
from the engine's own startup profile, which no Space owns and no page browses
in, and destroys it when the window closes and the profile is released. No
extension a person installed runs in a private profile, whatever its own
setting.

### WebKit's binding

WebKit's binding (`WebKitEngineBinding`) is Swift, shared by macOS, iPhone and
iPad. It builds each page the core asks WebKit to create, raises script
dialogs, sign-ins and permission requests with the core, runs WebKit's
downloads as the engine's own, and settles each question the core answers.
It keeps each profile's website data store: a private page's profile, and
every profile of a launch that keeps nothing on disk, browses in a
non-persistent store of its own, made the first time a page of the profile
opens and dropped when the core erases the profile; any other profile opens
its store on disk. Private browsing ending erases its profiles
(`DeleteProfileData`, ephemeral), so the next private window starts in a new
store. The binding also compiles Crest's content rules once and builds each
page with the rules its Space's protection applies; each page owner still
applies a changed protection to its live pages. A popup WebKit makes keeps the
configuration WebKit derived from its opener's.

The binding asks the core `LinkActivation` for each link the person follows
in one of its pages, as Chromium's does, and keeps a modified link bound for
a Peek staged with its referrer: the platform asks the core `StageLink` to
hand it to the Peek's page, which the core allows only on the same engine and
profile and before the page has loaded anything, and WebKit drops a link the
core discards, one that no longer applies, and those of a page that closes.

The binding runs each `LoadPage` in its page once the page's host is ready
for it. A page the core closes keeping its state reports `PageClosed` with
WebKit's history and the address it shows; a popup and a private page keep
nothing. A tab's next page gets that back through `CreatePage` and restores
it in place of its first load, when its host attaches. Every page it builds
carries a media bridge in an isolated world, which tells the binding when
media in any frame starts, stops or ends; the page then asks WebKit what it
runs and reports it, as it does for capture and Picture in Picture, so the
core decides residency on current media. Each tab's history also goes to a
Swift archive on disk (`BrowserTabStateArchive`) when its page goes and when
its scene stops being active, because the core keeps restore state in memory
only: a relaunch, or a tab whose state the core no longer holds, restores
from there.

`BrowserPageHost` keeps a workspace's pages on the Mac, iPhone and iPad: each
tab's resident page, the Quick Window and Peek leases, and the state a tab's
page leaves behind. Every Mac window over a workspace shares one host through
its runtime store; each iPhone or iPad scene has its own. When the core moves
a page to another engine, the page takes the new engine's adapter and view in
place, so its tab, lease and window keep it. WebKit's binding builds a page
the core moved to WebKit from its own stores and rules, and hands it over
before the core loads it. A page an engine opened by itself that the core
adopted for a tab (`OfferedPageAdopted`) is hosted by the shared page owner
of the window that opened the tab, whichever engine opened it. When closing
a saved or pinned tab puts its page away (`TabPagePutAway`), the page host of
the window that asked lets the page go, keeping what brings it back unless
the tab returned to its saved address. What a page
owner does beyond that is shared too (`BrowserPageOwner`): `BrowserPagePool`
(Mac) and `MobileBrowserPageStore` (iPhone and iPad) keep only presentation
and each platform's own commands.

### Multiple engines

Each page belongs to one engine, and capabilities are read from the page's
engine.

- **Site choices.** `ChooseSiteEngine(space, origin, engine)` records which
  engine a site's new pages open on. A choice made in a persistent-session
  Space holds for every Space and the device store keeps it, the most recent
  512; one made in a private or other memory-only Space holds for that Space
  alone and stays in memory. A tab's page opens on the engine chosen for the
  site the tab shows, when that engine is registered, and otherwise on the
  default engine. A restore state kept by one engine is never handed to
  another.
- **Opened pages keep their opener's engine.** A page another page opened runs
  on its opener's engine, whatever the site's choice: a script's window, a
  `target=_blank` link or form, a popup, a link the person follows into a new
  tab with a modifier or the context menu, and the Peek or split a link opens.
  `OpenPage` names such a page's opener (`OpenerPageId`), and a page an engine
  opened by itself (`PageOffered`) stays on that engine. The site's choice and
  the default engine apply to pages the person opens: typed addresses,
  bookmarks and links from other apps.
- **Moving a page.** `RehostPage(page, engine, remembersSite)` checks the page's
  `beforeunload` decision before closing it on its engine,
  keeping nothing, creates it on the other in the same profile and window, and
  loads the address it showed once that engine created it. The page keeps its
  identity, owner and window; its history and form state stay behind, and the
  questions its old engine asked end. A load the person asks for toward a site
  chosen for another engine moves the page there the same way, and so does a
  navigation the document starts in a page no other page opened; a page
  another page opened stays with its opener's engine, which keeps a sign-in
  window's redirects inside it. Every move publishes
  `PageRehosted(page, space, origin, from, to, reason)`.
- **Site Controls** shows which engine the site opens in when more than one is
  registered, and choosing another moves the page and records the choice.
  The Chromium product's Page menu also moves the shown page alone to any
  other registered engine (**Open Page in WebKit**), recording no choice.
  Both read the registered engines, not what the device offers, so they are
  there before any page has opened on the other engine.
- **Protected media.** Crest's Chromium carries no Widevine. When a page, or
  a frame of its own site, asks for Widevine or PlayReady, Chromium reports
  `ProtectedMediaUnavailable`. The core automatically attempts a move once per
  document to an engine with the `protected-media` capability, which WebKit has
  through the platform's FairPlay. It checks `beforeunload` before moving and
  validates that the document and website choice have not changed while waiting.
  Only an allowed move records that engine for the site. Cancelling preserves
  the page and its website choice without another prompt for that document.
  No automatic move starts when no engine plays protected media, when the page
  already moved for this reason, when another close is pending, or when the
  site already has a choice. The
  Mac window shows a notice with **Move Back**, which records the engine the
  page left for the site and moves it back.
- **Profiles and website data.** A Space is one profile on every engine. The
  profile's Chromium directory and its WebKit website data store share the
  profile's identifier; a named isolated launch derives its own WebKit store
  identifiers, and private and ephemeral launches use non-persistent stores.
  Deleting the Space erases both, and the locked-Space gate covers both.
  Sign-in never moves between engines.

## Page lifecycle

The core owns page identity. A page's owner (a tab, or a Quick Window, Peek or
Settings request) opens it through the core (`OpenPage`) from its window,
hands it to another owner (`MovePage`) and releases it (`ReleasePage`). The
core refuses a page in a locked Space, in one being deleted, or for a tab that
already has one in that window. It asks the page's engine to create, load and close the
engine's page. Typed addresses, the command palette, Open Location and every
first load go through `Navigate`, which the core resolves by the Space's
address and search rules before it issues `LoadPage`.

Each page intent and each engine report about a page carries its own logic.
`PageIntent` declares `Apply(Pages, PageTurn)` and `PageEvent`
`Apply(Pages, Page, PageTurn)`, where `PageTurn` holds the change feed and the
engine commands the message causes. Every case overrides it in its own file
under `Application/Pages/Intents` or `Events`, so a case without its logic does
not compile. `Pages` keeps the open pages, the restore states and the rules
they share, internal to the core, and its dispatchers hand it to each message:
`intent.Apply(this, turn)`. A report reads its page once; one about a page the
core no longer hosts, or that another engine hosts, changes nothing.

- **Offered pages.** A page an engine opens by itself, such as a
  `window.open` popup or an extension's `chrome.windows.create`, arrives as
  `PageOffered`, and the core decides where it goes. WebKit offers the popup
  it made while it waits for the popup's web view: the core adopts or refuses
  it on the same stack, the binding builds the adopted page from the
  configuration WebKit derived from the opener's, and the page's owner hosts it
  before WebKit starts its first navigation, so `window.opener` stays
  connected. A refused popup gets no window, never a tab of its own.
  A window a page asked for, which its engine made a window of its own
  (`SpaceId` with a source: Chromium's popup and new-window dispositions,
  WebKit's popup window features, as HTML's "popup window is requested"
  decides), becomes a Quick Window page in its opener's Space and window,
  published as `OfferedWindowAdopted` with the page that asked for it. The
  window that routes that page now, which is the one the person is using
  rather than the one the core recorded, hosts the popup's page at once in
  the page host every window over the workspace shares, and opens a Quick
  Window over itself that takes it, so a sign-in popup is one window whose
  redirects stay in it; its `window.close()` closes the Quick
  Window, and Open in makes it a tab with its opener intact. Otherwise a
  transient page keeps what it opens: the core rejects the offer and loads
  the address in the Quick Window or Peek itself, in one page with its native
  history. A web address or the empty document at a fragment loads there; the
  bare `about:blank` an engine reports for a window with no address yet loads
  nothing. WebKit loads the window's own request there, keeping its method,
  body and referrer, and offers a `window.open()` with no address as
  `about:blank`. A tab's offer becomes a new
  tab beside the tab, in its Space and window. Anything else joins the
  window's reserved Space, or else the Space it shows, after the tab it shows.
  The core refuses an offer for a locked or deleting Space, one of another
  profile, a closed window or a full Space, with `RejectOfferedPage`.
  Otherwise it opens the tab, issues `AdoptOfferedPage` and publishes
  `OfferedPageAdopted`, and the window that hosts the tab shows the page the
  engine made. iPhone and iPad have no Quick Window, so WebKit offers every
  popup there as a tab.
- **Navigation.** A binding reports each navigation as it starts, commits,
  finishes or fails. The core records one visit per document when it finishes,
  because both engines know the title only then. A page with a tab updates the
  tab's address and title and adds the visit to its Space's history in one
  revision; a Quick Window or Peek page adds only the visit. Nothing is
  recorded for a failed load, in a locked Space or one being deleted. A move
  within a document is a visit of its own when it reaches another page, and
  records nothing when only the fragment changes.
- **Live state.** A binding reports a page's `PageSnapshot` at most once per
  turn and only when it changed. The core keeps it, with the latest failure,
  as the page's `PageLiveState` and publishes `PageChanged` only when that
  differs. Load progress, find highlights, the hovered link and fullscreen
  come straight from the engine, because no rule reads them.
- **Crashes.** A page whose renderer stopped in view reloads through
  `RecoverPage` while its recovery budget lasts, and past it shows the
  failure until the person asks for the page again. A renderer that stopped
  while nobody saw it spends none of the budget and comes back when a window
  shows the page.
- **Closing.** A page whose script asks to close its window, as
  `window.close()` does once its document agreed to go, reports
  `PageCloseRequested` and stays open: WebKit from `webViewDidClose`,
  Chromium from a renderer's close request, which its host takes before
  `Browser::CloseContents` sees it. The core lets only a page another page
  opened close itself, the same way on both engines; a tab the person opened
  or saved stays, whatever its history. A `PageClosed` for a page the core
  still hosts means the engine closed it on its own authority, as an
  extension's `chrome.tabs.remove` or `chrome.windows.remove` does. Either
  way the core closes what owns the page as the person closing it would: a
  tab through `CloseTab`, once, and a Quick Window's or Peek's page through
  `TransientPageClosed`, which closes whatever shows it. A page in a Space
  being deleted has nothing left to close. The acknowledgement of a close the
  core asked for finds the page already gone or moved to another engine, and
  changes nothing. Chromium never discards a Crest page, since a discard
  would replace its WebContents; the core's memory pressure unloads pages
  instead.
- **Prompts.** Script dialogs, sign-ins, permission requests and extension
  installs are questions the binding raises with the core (`ScriptDialogOpened`,
  `AuthenticationChallenged`, `PermissionRequested`,
  `ExtensionInstallRequested`). The core answers a permission from the Space's
  choices when it holds one, and otherwise publishes the question
  (`PermissionAsked` and the others) for the page's host to show. The person's
  answer comes back as an intent, and the core settles the engine. A question
  whose page goes, stops holding its engine page or moves to another engine is
  settled as declined. A credential passes to the engine and is never kept,
  published or saved.
- **Downloads.** Both engines run their downloads as the engine's own and
  report them to the core, which keeps the ledger: record phases, order,
  progress and ETA (`DownloadProgress`), risk (`DownloadRisk`), where each file
  goes, approval of a file an engine warned about, and retention. A dangerous
  file is asked about before it has a place. A file a site sends without the
  person's gesture passes the site's automatic-download choice. The binding
  keeps the file handling: staging and moving the file, quarantined, to the
  place the core settled. Chromium reports pause and resume availability;
  `PauseDownload` and `ResumeDownload` validate the record and Space access
  before sending the command to the owning engine. The binding operates on the
  original transfer and cannot revive a removed record or approve a risk warning
  by resuming. The ledger is not persisted.
- **Close preparation.** Closing pages or windows, and quitting, run a close
  preparation (`PrepareToClosePages`, `PrepareToCloseWindows`,
  `PrepareToQuit`): the core asks each page with a before-unload handler, one
  at a time, through `CheckBeforeUnload`, and asks the person about downloads
  in progress before a quit. It publishes `CloseReady` with whether the close
  may proceed; it may not when a page that agreed has shown another document
  since. Closing the last window of a private or torn-off tab's workspace
  asks every page of that workspace, whichever window hosts it. A quit waits
  while a Space is being deleted and the engines are still erasing its
  profile: `PrepareToQuit` is refused with `SpaceDeletionUnderway`, the
  platform shows its notice and asks again once the deletion moves on. Once a
  quit is allowed, the windows still open stay the ones the next launch
  reopens.
- **Picture in Picture.** Each page reports its Picture in Picture activity
  in its snapshot. When a window shows a page again, or the page's Space locks,
  is being deleted or is gone, the core sends the page's engine
  `ExitPictureInPicture`, and it asks again at once if a page of a locked Space
  reports Picture in Picture. The Picture in Picture window's return control
  reports `PictureInPictureReturned`, and the core shows the page's tab in the
  window that hosts it (`WindowBroughtForward`); the return never opens a
  window. Automatic entry is the platform's, through each engine's own path
  (see [Desktop Picture in Picture](DesktopPictureInPicture.md)).
- **Web notifications.** A document's notifications on either engine show
  through Crest's own delivery on the Mac. Chromium presents
  `WebNotificationPosted` and `WebNotificationClosed`, and WebKit pages post
  through Crest's bridge in the page. The page shows each one as Crest's
  (`BrowserPage.showWebNotification`) when the Space's choice for the site
  allows notifications and the system lets Crest show them. A click brings the
  page's tab and Crest forward, then tells the document, which on Chromium
  hears it through `AnswerWebNotification`. A page whose document changes or
  that leaves its engine takes its notifications down. Chromium's local worker
  and extension notifications instead report `ProfileNotificationPosted` and
  `ProfileNotificationClosed`. `ChromiumProfileNotifications` checks
  `ProfileNotificationDisplayCheck` before and after delivery and before a
  click, and answers through `AnswerProfileNotification`. Space locks and
  permission changes withdraw inaccessible notifications. Chromium dispatches
  worker and extension click events in the owning profile even after the
  original tab closes. Private profiles, remote Web Push, and app wake-up are
  not supported by this delivery path.
- **Residency.** Every device reports memory pressure with
  `ReportMemoryPressure`, and the core unloads the tab pages off screen longest, as many as the device's
  platform gives back: never one a window shows, one showing no document yet,
  one whose tab keeps its page loaded, or one playing, capturing or in Picture
  in Picture. It holds each unloaded page's engine restore state in memory,
  never saved, and hands it back to the tab's next page on the same engine
  while the tab still shows that address.
- **Erasure.** Deleting a Space saves a core-owned deletion intent first; the
  Space becomes unavailable across its windows, and launch resumes a saved
  intent until the engines confirm. Final removal and its sync tombstones share
  one transaction. The platform asks the core with `DeleteProfileData` or
  `DeleteSiteData`, and the core asks every registered engine, started or
  not, ending with `DataDeleted` once each answered. A Space finishes deleting
  only once this run erased its profile on every engine; one an engine could
  not erase stays being deleted, and the next launch erases it again.

## What stays in Swift

By design: heraldry vocabulary and composition, favicon image bytes and
palette extraction, sidebar widgets, Peek motion and presentation phases,
tear-off placement geometry, drag geometry, default-browser prompt cadence,
appearance preferences and the presentation of every prompt, notice and sheet.
Informational feedback uses the top-of-window notice capsule, which may offer
one action that undoes what it reports; a dialog appears only when the person
must decide.

## Upgrading an installed session

The upgrade carries exactly two values: the installed release's `UserDefaults`
session core with its per-Space history keys, and its sync journal. Everything
else keeps the identifier it had and is read in place, because the products
share one identity. `ProductIdentity` resolves the same `com.pauldavis.crest`
defaults domain, `Application Support/Crest` directory, keychain service
namespace and `iCloud.com.pauldavis.crest` container for the WebKit `Crest`
target, `CrestMobile` and the packaged Chromium product, which rewrites
`CFBundleIdentifier` to `com.pauldavis.crest` and omits `CREST_REVIEW_BUILD`.
None of these products is App-Sandboxed; adding the sandbox to either side
would move every path into a container and strand the installed data, so the
product package must be signed with the Mac target's own entitlements.

When the core's file holds no session, Swift reads the installed release's
values raw (`BrowserLegacySessionDefaults`) and sends them with the
first-launch seed as `AdoptLegacySession`. The core decodes them, writes the
result before the intent returns, and hands back the tab images a whole-graph
blob carried for the favicon store. A file that already holds a session adopts
nothing. An installed session the core cannot decode stays where it is; the
core leaves the cloud-recovery marker and installs the seed, which the Spaces
CloudKit still holds replace instead of being published as their deletion.
Device state an older release kept (window records, site permissions, link
preferences, shortcuts, setup completion) is adopted once into the device
store under an append-only adoption marker, and the old values stay readable
for older builds.

WebKit cookies and website data, and WebKit tab interaction-state archives,
are engine-specific and are not converted. Nothing deletes them, so returning
to the WebKit app finds them intact. A tab without a usable archive loads its
URL.

## Build workflow

Install the .NET SDK 10.0.201 or a servicing patch, Xcode and XcodeGen.
Regenerate `Crest.xcodeproj` with `xcodegen generate` after changing
`project.yml`.

The `Crest` and `CrestMobile` targets build and embed their core from source.
`Scripts/control-plane/build-apple-core.py` selects the runtime for the
destination, uses Release NativeAOT for Debug and Release apps, and caches it
under the build's products directory. No managed runtime is required on the
user's device. `CREST_CORE_LIBRARY_DIR` or `CREST_CORE_FRAMEWORK_DIR` overrides
use a previously published library, which must match the checked-out
contracts. CI installs the pinned SDK through
`Scripts/control-plane/install-dotnet.sh`; local builds find `dotnet` in
`PATH`, `~/.dotnet` or the standard macOS location, or through `CREST_DOTNET`.

For core-only development, run `dotnet test tests/CrestCore.Tests` from
`CrestCore`, and `Scripts/control-plane/lint-dotnet.sh`. The C and C++ ABI
checks, `CrestContracts/tests/native_abi.c` and `engine_abi.cc`, run against
the published library. `Scripts/control-plane/build-experiment.sh
/absolute/new/path/CrestNativeCore.app` runs the managed and native checks and
builds an isolated macOS app; `build-ios-experiment.sh` builds the iOS UI for
Simulator the same way.

To review the normal Mac target without registering the installed app's
identity, set `CREST_MAC_BUNDLE_IDENTIFIER` to a separate identifier and
`CREST_MAC_ENTITLEMENTS` to compatible entitlements, then launch with
`CREST_ISOLATED_SESSION=1` and a unique `CREST_ISOLATED_PERSISTENCE_ID`.

For iOS, publish `CrestCore.Native` for `ios-arm64` or `iossimulator-arm64`
with `-p:PublishAotUsingRuntimePack=true`, package the dylib with
`Scripts/control-plane/package-apple-core.py`, then build
`CrestMobileNativeCore` with `CREST_CORE_FRAMEWORK_DIR` set to its directory.

Limits are data the core reports through the `EnforcedLimits` query
(`CapacityLimits`): 64 Spaces and 5,000 tabs per Space, among others. Session
inputs and storage parts are limited to 64 MiB, and typed messages to their
`[MessageLimit]` or 16 MiB.

## The Mac shell

Both Mac products run one AppKit shell, `BrowserMacShell`
(`CrestMac/App/Shell`). It builds the
application (`BrowserMacApplication`), or shows native recovery when the session
cannot open and continues once it can; opens the windows the core names;
installs the menu bar and the Dock tile; starts sync; and then opens the links,
documents and sign-ins that arrived before it was ready.

- **Entry points.** The WebKit product enters through `CrestMain`, which runs
  `NSApplication` with `CrestAppDelegate`. The delegate's application hooks
  (terminate, reopen, open URLs and the Dock menu) call the shell. The Chromium
  product enters through `crest_native_host_run`, runs `ChromiumApplication`
  with `ChromiumApplicationDelegate`, and starts the same native shell and
  core before loading Chromium. The engine's first page or extension stops
  the initial AppKit loop and enters Chromium's normal browser loop. Crest
  keeps its delegate and windows; Chromium attaches its binding and event
  adapter to that existing application. Once started it remains until quit.
- **Shortcuts.** Both engines' page views take key equivalents before the
  menu bar does, so the shell offers every key down to its shortcuts first,
  through a local key monitor. While Crest's own views have focus, Crest's
  shortcuts win. While a page has focus it sees the key first, as in other
  browsers, and only the commands the core marks `IsReservedFromPages` run
  ahead of it: opening, closing and switching tabs and windows, plus quit. An
  extension's `chrome.commands` binding also goes ahead of the page, as in
  Chrome. WebKit hands a key the page lets go back to AppKit, and Chromium's
  browser window hands it to the menu bar; the menu bar's top menu runs the
  command, and asks the shell for a chord no item matches, such as ⌘= for
  zoom's ⌘+.
- **The core decides.** The shell asks the core and presents the answer.
  `LaunchWindows` names the windows a launch reopens, back to front, and the
  one that opens on the startup choice, or the setup a first run shows in front
  of them. `WindowToReopen` answers a Dock click with no window open.
  `RouteExternalLink` and `RouteLocalDocument` place what other apps open,
  `EngineWindowPlacement` places a browser the engine created for itself, and
  `DockMenu` fills the Dock menu. `PrepareToQuit` and `PrepareToCloseWindows`
  ask each page before a quit or a window's close; a quit waits with
  `SpaceDeletionUnderway` while a Space is deleted.
  `RememberWindowsForLaunch` keeps the windows open at an allowed quit. The
  menu bar builds the core's `ShortcutMenu`s, in their order and groups, and the
  launcher offers each `ShortcutCommand` that `OffersInPalette`, in catalog
  order; both show what `EnginesChanged` says the device offers.
- **What stays native.** Window kinds (`BrowserMacWindowKind`: browser,
  temporary, private, Quick Window, setup and update details), frames and
  cascading, key focus and window activity, and the close gate every window
  shares (`BrowserWindowCloseGate`), which asks the core before a person's
  close. The shell adds AppKit's application, Edit, Window and Help menus, and
  places full screen and whole-page translation in the core's menus. Its
  `BrowserMacDockTile` draws the icon the person picked, with a download badge
  from the core's download state.
- **The engine's part.** `BrowserMacEngineHost` is all the shell asks of the
  engine: the About panel's credits; letting go of what
  it kept for a closed window, and of the profiles named; and a key equivalent
  no Crest command claimed, such as an extension's `chrome.commands` binding.
  `ChromiumRuntimeShell` forwards to Chromium's Mac shell after it is loaded,
  and `WebKitShellHost` needs none of them.

## Chromium host

The host overlay uses Chromium's browser startup, `Browser` and
`TabStripModel`. A packaged host first loads only Crest's UI framework
(`CrestChromiumUIProduct`, or `CrestChromiumUI` for review), whose exported
`crest_native_host_run` starts the native shell. `ChromiumRuntime` exposes a
stable deferred binding to the core. On the first Chromium request, the
launcher loads Chromium and enters its normal startup. Chromium calls
`crest_chromium_ui_start` with its Mac shell, binding and page-request table;
the framework attaches these to the existing runtime and drains its queued
commands. It has no `@main`. Crest owns `NSApplication` and its delegate;
Chromium contributes native event processing and accessibility without
replacing them. A WebKit-only session never loads Chromium's framework.

Settings exposes the device's preferred default and exact-origin website
rules through `GetEnginePreferences`, `SelectDefaultEngine`,
`EditEngineRule` and `ForgetEngineRule`. These choices are local device data,
not synchronized browsing state. Private-page choices are absent from this
projection. Opening Extensions may start Chromium even with WebKit preferred;
merely visiting engine Settings does not.

- **Profiles.** Each Space uses a regular Chromium profile under the engine's
  user-data directory; the product keeps it in
  `~/Library/Application Support/Crest/Chromium`. A review package requires an
  explicit `--user-data-dir`. A private window uses a separate in-memory
  profile for each private Space, derived from the engine's own startup
  profile, never a Space's, and destroyed with the window; it runs no
  extension a person installed. Chromium's password manager is off for every
  page, in Space and private profiles alike.
- **Identity and lifecycle.** The packager includes Crest's icons and Dock
  tile plug-in. Crest's shell installs its menus, About identity and Dock tile,
  answers external URL and document opens, Dock reopen and the Dock menu in
  place of Chromium's profiles and incognito window, and reopens the windows
  open at quit. The product registers Crest for HTTP, HTTPS and HTML documents
  and carries the Sparkle feed.
- **Links.** Chromium's binding asks the core `LinkActivation` for each link
  the person follows in an owned page, from its modified-link hook and its
  protected-link throttle: saved-site protection, Peek priority and
  modified-link tab selection. A plain click on a link that opens a window of
  its own (`target="_blank"`) asks for the page it was followed in, as WebKit
  does; when the core answers Peek, the engine's new window closes before the
  core is offered it. A new tab a modified click asked for stays a tab. A link
  bound for a new tab or a Peek stays
  staged inside the engine with its verified referrer, initiator, headers and
  source SiteInstance. The platform asks the core `StageLink` to hand it to
  the new page, which the core allows only on the same engine and profile, or
  `DiscardStagedLink` to drop it; the new page receives only a one-shot token.
  Context-menu rows reach Crest as typed rows, never as dictionaries.
- **Internal pages.** Crest's session and address controls spell internal
  addresses `crest://`; the binding translates them to `chrome://` for
  navigation and back for observations. Internal navigation is gated by the
  `internal-pages` capability. The feature flags page Settings shows opens
  through the core like any page, owned by no tab (`TransientPresentation`
  `settings`), in the Settings tab's Space and window, so a private window's
  flags page is private too.
- **Extensions.** Chromium owns verification, runtime permissions, updates,
  execution and pin state. Crest's toolbar, Site Controls, install review,
  Space-scoped management and copying read the binding's model; the toolbar
  and Site Controls take their Space from the read model, and the install
  review shows the question the core asks (`ExtensionInstallAsked`). Action popups
  appear in a child window of the Crest window; side panels are cards in the
  page row that follow the focused tab, as Chromium's side panel does: a panel
  an extension gave one tab shows only beside that tab and returns with it,
  while its panel for every tab (`HasSidePanel` answers which) stays open as
  the person moves between tabs of the Space. A Chrome Web Store listing
  installs through Crest's review.
- **Downloads, favicons and archives.** Chromium's downloads report to the
  core's ledger; destinations resolve per Space. Opaque navigation archives
  carry an engine and version tag, stay local to the profile, and never enter
  the session or CloudKit; an incompatible archive falls back to the tab's
  saved URL.
- **Protected media.** Chromium reports a missing Widevine or PlayReady key
  system from the requesting frame through the frame host to the page, which
  reports `ProtectedMediaUnavailable` when the frame is the main frame or of
  the same site.
- **Services.** Exports, full-page captures and printing use a fixed,
  page-scoped in-process DevTools client that exposes no debugging socket.
  Archives use the engine's format: `.mhtml` for Chromium and `.webarchive`
  for WebKit. A docked inspector is mounted inside the page card it inspects.

Any change to the engine's inputs (the source lock, the host patch and its
reviewed input hashes, the overlay, the host header, the engine contract
headers and the prepare, apply, configure and build scripts) requires a new
published engine. See [Chromium source preparation](../../CrestEngines/Chromium/README.md).
