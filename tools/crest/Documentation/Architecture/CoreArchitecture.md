# Core architecture

Crest's state and app logic live in one portable core, `CrestCore`, written in
C#. Each platform supplies only its UI, its engine bindings and its OS
services. Adding a platform means writing those three things and nothing else.

This document sets out the layers, the two paths from the UI and the
modeling rules. [ControlPlane.md](ControlPlane.md) describes how the code
implements them, and [EngineAbstractionCompletion.md](EngineAbstractionCompletion.md)
lists what each engine lacks.

## Layers

| Layer | Owns | Never owns |
| --- | --- | --- |
| Platform UI (SwiftUI on macOS, iOS and iPadOS; WinUI 3 on Windows later) | Views, layout, animation, hover, scroll position, window frames, sidebar width, appearance preferences, presenting the prompts the core asks for, embedding engine views | Browser state, rules, persistence, deciding what happens next |
| `CrestCore` | Every piece of browser state and every rule: Spaces, tabs, folders, splits, history, archive, windows and what each window shows, which windows a launch reopens and where external opens land, pages and their live state, preferences, downloads, permissions, credentials policy, import and export, search and completion, the commands and how the menu bar and launcher lay them out, onboarding and setup flows, Quick Window and Peek rules, storage, sync | Rendering, input, compositing, engine handles, image bytes, OS services |
| Engine bindings (Chromium in portable C++ with a thin shell per OS; WebKit in Swift) | Creating and closing pages, loading, engine navigation history, find, zoom, capture, printing, DevTools, extensions, network and cookie stores | Deciding browser rules; changing browser state other than by reporting events |
| OS services (supplied by each platform) | CloudKit transport, Keychain, authentication prompts, notification delivery, file pickers, default-browser registration, software updates | Rules; deciding when to save or sync |

`CrestCore` builds as one assembly. Its contracts, domain and application are
folders and namespaces of that assembly rather than projects, so a message can
reach the internal state of the area that receives it without that state
becoming public.

Sync stays Apple-only. CloudKit transport is an OS service the Apple hosts
supply through a port, and the core owns records, merging, ordering and
scheduling.

## Two paths, visible in the code

The UI reaches the core and the engines through two objects, and each call
site shows which one it uses.

- **Through the core.** Anything that changes state is an intent object sent
  to the core: `core.send(OpenTab(...))`, with the intent naming its window.
  The UI reads state only from the core's published model: `core.state`.
- **Direct to the engine.** View work goes straight to the page's engine
  through an `EnginePage`: embedding the view, input, scrolling, zoom, find,
  reload, back and forward, DevTools, printing and capture. `EnginePage` has
  no method that changes browser state. What those actions cause, such as a
  committed navigation, reaches the core as an engine event. Presentation
  values that change constantly and that no rule reads also come straight
  from `EnginePage`: load progress, find highlights, the hovered link,
  fullscreen and the zoom value. Routing them through the core would add
  work on every update and buy nothing.

```swift
// Direct to the engine: view work on the page's current engine.
page.enginePage.zoom(to: 1.25)
page.enginePage.reload(bypassingCache: false)

// Through the core: moving the page to WebKit changes state, so it is an
// intent. The page's host re-hosts the view when the page's engine changes.
try core.send(RehostPage(pageID: page.corePage.id, engine: .webKit))
```

A search for `core.send(` lists every state change the UI can start. A search
for `EnginePage` lists every direct engine call.

## Modeling rules

1. Everything that crosses a boundary is a named type. Intents (`OpenTab`),
   published changes (`TabsChanged`), engine commands (`LoadPage`) and engine
   events (`NavigationCommitted`) are records. Nothing is identified by an
   operation string or a code. The generator gives each type its wire tag, and
   the source never spells one.
2. Rule failures are objects: `TabLimitReached(Limit)`, not `"tab_limit"`.
3. Objects describe themselves. A type owns its data and every behavior that
   depends on it. No sibling `*Codes`, `*Policy`, `*Rules` or `*Mapping` types,
   and no extension files that switch over its kinds. A fixed set is one type
   whose static instances define its members. Each instance is constructed with
   the values that make its behavior emerge: its stored spelling, labels,
   limits, and any rule that differs by kind, passed in as a value or a
   function. Methods are written once over those values and never name a
   particular member, so adding a kind means adding one instance.
   - In C#, this is a sealed class with a private constructor and static
     readonly instances (`TabIconMode.Automatic`, with `Name`, `All` and
     `Named(string)`).
   - In Swift, it is a struct with `static let` instances, which the generator
     emits from the C# instances so the data is written once. A member's wire
     tag is its index in `All`, so `All` only grows at the end.
   - Presentation lives on the instance too. User-facing text is English
     source marked `[Localized]`, with an optional `<Member>Comment` for
     translators, and Swift receives it as a `LocalizedStringResource`, so
     Xcode extracts it into the string catalog. Text that names a number
     spells it `%lld` and names the int member that supplies it, so every
     member shares one catalog key. SF Symbol names are plain strings. Views
     read `phase.title` and `phase.symbol` instead of switching over kinds.
   - A member's data may also be an enum, a flags enum, a record declared
     beside the set, or a list of these; Swift receives each as a literal.
     Every fixed set in the contracts reaches Swift, whether or not a record
     names it.
   - A set that also has members made at runtime, such as a Space's custom
     search engines beside the built-ins, is marked `[OpenSet]`. A runtime
     member has no index in `All`, so an open set never crosses the wire;
     Swift receives a struct with a memberwise initializer whose values are
     equal when their names are.

   A nested `Kinds` enum is used only where a switch cannot be avoided. Plain
   enums remain only for sets whose members carry nothing. Unions of message
   types (intents, queries, events, changes) are not fixed sets, and no switch,
   handler interface or generated dispatch picks their cases. Each message
   carries its own behavior: its family's base record declares an abstract
   method that takes its receiver and a small context record (`Apply`, or
   `Answer` for a query), each case overrides it in its own file beside the
   receiver, and the receiver's whole dispatcher is `intent.Apply(this, turn)`.
   A case without its logic does not compile. A fact that only tells cases
   apart, such as the page an event names, is a property of the family.
   Intents route themselves to the area that owns their family
   (`Intent.Route`), engine events likewise, and queries and engine questions
   answer themselves (`Answer`). Swift receives each union as an enum whose
   one method forwards, with an exhaustive switch, to its payload's own
   method (`change.apply(to: state)`, `command.perform(on: binding)`). A
   listener for some cases never picks them with `if case`: those cases
   conform to a protocol that calls the listener's contract
   (`prompt.present(on: host)`). A fixed set or union the platform performs
   forwards each member to a performer protocol with one method per member
   (`step.kind.take(step, on: performer)`), so a new member fails to compile
   until every platform handles it. Engine capabilities are a fixed
   set (`EngineCapability`). No capability is a string.
4. Identifiers are plain `Guid` in C# and `UUID` in Swift, and they appear only
   at boundaries. Inside the core, methods take the objects themselves
   (`window.Show(space, tab)`), not their identifiers. Crest does not wrap a
   GUID in a type just to name it; Swift uses `UUID` for every identity.
5. A wrapper type is justified only when it carries behavior or an invariant,
   as `SiteOrigin` does with normalization. A record whose constructor
   normalizes its fields is marked `[NormalizedOnConstruction]`. Swift receives
   it as `Hashable` with only a labeled wire initializer, `init(normalized …)`,
   which the codec alone calls; the generator refuses any other caller. The
   platform's initializer with the natural labels normalizes the same way,
   reading the same fixed-set data, such as `WebScheme.defaultPort`.
6. The core keeps no JSON in its model. JSON remains only where a stored or
   synced format already requires it, and those formats have hand-written
   codecs. The generator never defines a stored or synced key, because
   renaming a contract field must not rewrite anyone's data.
7. One schema. The C# contract records are the source of truth. The Swift
   models, the C header and the codecs are generated from them, so no model is
   written twice by hand.
8. Every protocol or interface has at least two real implementations, or it
   stands for an OS seam that cannot be faked. The engine contract has two:
   Chromium and WebKit.
9. A change is named for the state it changed and carries the resulting
   values (`TabsChanged`), so a UI never re-applies a rule to work out the
   result. Events the UI reacts to are named for what happened
   (`PageRehosted`).

## The core's model

| Object | Holds | Saved | Synced |
| --- | --- | --- | --- |
| `Session` | Spaces, each with its profile, tabs, folders, splits, history and archive | Yes | Yes |
| `Device` | Windows and what each shows (the Space, and the tab in each Space), split column shares, engine choices per site, site permission and shortcut choices, device-local preferences | Yes, in the device store (a private Space's choices stay in memory) | Never |
| `Pages` | Each open page: its owner (a tab, or a Quick Window, Peek or Settings request), its engine, and the live state rules read (URL and title before commit, loading, back and forward availability, security, failure, media activity) | Never | Never |
| `Prompts` | Permission, authentication and other questions waiting on the person | Never | Never |
| `Engines` | The registered engine bindings and their capabilities | Never | Never |
| `Downloads` | The download ledger | Never | Never |

The core publishes typed changes and never resends unchanged state. It
derives them by comparing each accepted state with the one before, never
from hand-written change lists, so no change can be forgotten. Changes are
named for the state they change and carry resolved values: a tab arrives with
its icon mode already decided, so no UI works out a rule again. Resolved
values travel only from the core: a platform that builds such a record to
send, such as the session a launch without a file opens from, builds its
generated seed, the record's fields alone, and the core resolves the rest
when it reads it. A view that draws Spaces no workspace holds, such as a
preview, a setup draft or an import under review, asks the core to resolve
its seed (`DetachedSession`) and draws the read-model objects it builds from
the answer, which nothing the core publishes ever reaches. The model is
keyed by workspace, because persistent, private, borrowed and Quick Window
sessions all live at once. Changes caused by an intent come back with the
call, after any changes still pending from earlier, so an older change can
never land after a newer one and the caller reads the new state straight
away. Changes the core starts itself, such as a finished save,
a sync merge or an engine event, arrive through a wake-up call that the UI
answers by draining the pending batch, at most once per main-queue turn. The
Apple UIs keep a generated read model that they update from those changes, so
reading state never calls into the core. The read model is observable per
entity (each window, Space, tab and folder is its own observable object that
notifies only when a value really changes), so a tab's new title redraws that
tab's row and nothing else. The Windows UI reads the core's
records directly.

Swift and the core always ship in one build, so the binary wire between them
has no versioning. The app checks a schema fingerprint when it creates the
core, so a stale prebuilt core fails at launch instead of misreading data.

The UI's intents change the core's model on the UI thread. The cloud
transport's intents run on the transport's own thread instead: a sync merge
computes there against a snapshot, outside the core's lock, then takes the lock
only to commit with a revision check, and what it changed reaches the UI
through the wake and one drain. Its queries read the journal without the lock,
and an intent about the journal alone, such as an acknowledged upload, never
takes it. The core owns the SQLite
schema and transactions, and the host supplies only a directory. Saves run on
the worker after the change is published, except where ordering matters:
sync commits, Space deletion, imports, batches, cross-Space moves and
transfers are saved before the intent returns. The core also stages sync
itself: each intent knows its deletion reason and urgency, and a durable
change writes the session and its journal together. The core
publishes `Saved(revision)`, so the CloudKit transport stores its server
token only after the merge it covers is on disk.

## Engines

The engine contract is a set of contract records like intents and changes:
commands the core issues (`CreatePage`, `LoadPage`, `ClosePage`,
`SettlePermission`, …) and events the binding reports (`NavigationCommitted`,
`PageCrashed`, `PermissionRequested`, `ProtectedMediaUnavailable`, …).
`crest_engine.h` carries them in the same generated wire format, and the
generator emits a C++ codec for the Chromium binding. Chromium implements it
in portable C++ and reports events straight to the core, with no Objective-C
or Swift in between. Chromium's Mac shell around it handles only view
embedding, popups and web authentication. Crest's own Mac shell, which both
Mac products run, owns the windows, menus, launch, reopen, external opens and
quit, and asks the core each decision it makes about them. WebKit implements
the same contract in Swift, once, for macOS and iOS.

Crest can run more than one engine at a time.

- A composition registers a default engine and any others it carries. On the
  Mac, Chromium is the default and WebKit is available. An engine that isn't
  the default starts the first time a page needs it, so it costs nothing until
  then.
- Each page belongs to one engine. Capabilities are read from the page's
  engine, not the app's, so the UI offers Reader on a WebKit page and
  extensions on a Chromium page.
- A Space is one profile on every engine. The profile's Chromium directory and
  its WebKit website data store share the profile's identifier. Deleting the
  Space erases both, and the locked-Space gate covers both.
- Clearing one site's data, or a time range's, asks every registered engine
  for its part, started or not, and succeeds only when each erased all of it.
  A site is its registrable domain, with what its third parties stored
  partitioned under it. The website data list is the sites every engine
  reports for the profile, merged by name.
- `RehostPage` moves a page to another engine. The core closes the page on
  its current engine, creates it on the new one and loads the same URL. The
  page keeps its tab, and the UI re-hosts the view because `page.engine`
  changed.
- A page another page opens stays on its opener's engine: a popup, a
  `target=_blank` link, and the Peek or split a link opens. A site's engine
  choice and the default engine apply only to pages the person opens.

### Recording navigations

A binding reports each page's navigations as `NavigationStarted`,
`NavigationCommitted`, `NavigationFinished` and `NavigationFailed`, and the
core records one visit per document, when the document finishes, because
both engines know the page's title only then. A page with a tab updates the
tab's address and title and adds the visit to its Space's history in one
revision; a Quick Window or Peek page adds only the visit. Nothing is recorded
for a failed load, in a locked Space or one being deleted. A report that
arrives while a transaction holds the session is recorded once it ends.

A move within a document, such as `history.pushState`, is a visit of its own
when it reaches another page, and records nothing when only the fragment
changes. Single-page sites are where people spend their time, and a video
watched or a message read is a page they will look for in history and expect
their tab to reopen. A fragment is part of the page it names, so recording it
would only count the same visit again. Such a move finishes once the page's
title settles, since those sites set the new title after they change the
address.

### Protected media fallback

Crest's Chromium has no Widevine. WebKit plays FairPlay through the system's
own content decryption, so a page whose video needs DRM can move to WebKit.
Crest licenses nothing for this: it uses the platform's WebKit.

1. A page asks for a key system Chromium cannot provide. The Chromium binding
   reports `ProtectedMediaUnavailable(page, keySystem)`.
2. The core picks an engine that supports FairPlay. It does nothing if there
   is none or if the page has already moved once for this reason, so a page
   never bounces between engines.
3. The core rehosts the page and records that this site opens in WebKit on
   this device.
4. The UI shows a notice with an action to move the page back. Later visits
   to the site open in WebKit directly, without the reload.

```csharp
public sealed record ProtectedMediaUnavailable(Guid PageId, KeySystem KeySystem) : PageEvent(PageId) {
    internal override void Apply(Pages pages, Page page, PageTurn turn) {
        if (page.Phase != PagePhase.Live || pages.Shown(page) is not { } space || page.MovedFor(RehostReason.ProtectedMedia)
            || pages.Engines.PlayingProtectedMedia(page.Engine) is not { } fallback
            || page.DocumentAddress is not { } address || new WebAddress(address).Origin is not { } origin
            || pages.Device.ChosenEngine(space.Id, origin) is not null)
            return;
        pages.Device.Choose(space.Id, origin, fallback.Kind);
        pages.Rehost(page, fallback, address, RehostReason.ProtectedMedia, turn);
    }
}
```

Chromium reports the event from the one place that knows the key system
itself is missing rather than a configuration: `WebEncryptedMediaClientImpl`'s
unsupported-key-system result. It passes through the frame's
`KeySystemConfigSelector` delegate and the frame host, and reaches the page's
`WebContentsObserver`. Only the main frame, or a frame of the same site, reports,
so an advertisement's probe moves nothing. The notice with "Move back" is the
top-of-window notice. Moving back records the engine the page left as the
site's choice, and the fallback never runs for a site that has a choice.

### Sign-in on a moved page

No cookies or other site data move between engines. A page that moves to
WebKit uses the WebKit website data store of its Space's profile, so the person
signs in there once and that store keeps the sign-in for later visits. Signing
out on one engine does not sign out the other.

## Windows, later

The Windows UI is WinUI 3 in C#, compiled with NativeAOT, with `CrestCore` as
a project reference in the same process. It calls the core directly and
reads its records, with no ABI crossing, serialization or second copy of the
state. As on the Mac, Chromium owns the process and the UI thread. A Windows
shell asks the core the questions the Mac shell asks, such as which windows a
launch reopens, where external opens land, whether a quit may go ahead and how
the menus lay out the commands, and mounts the WinUI views as XAML Islands in
its windows. A spike must prove that, along with hosting the page surface,
before any Windows work begins.
