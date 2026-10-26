# Changelog

All notable changes to Crest are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/2.0.0/),
and Crest uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.8.50] - 2026-10-22

Crest 0.8.50 brings Chromium 155 with its latest security fixes and stops
trusting the compromised eMudhra certificate authorities. It also rebuilds
setup on the Mac, translates whole pages in Chromium, and fixes several
crashes and problems quitting. On iPhone and iPad, Crest appears in the share
sheet and an edge swipe goes back or forward. iPhone also gains swipes between
tabs on the address bar and support for iPhone Duo.

### Added

- Set up Crest on the Mac in a rebuilt, full-screen setup that asks whether your Spaces wear Crest’s heraldic banners and crests or a modern gradient and icon, and carries that look through importing and making your Spaces yours.
- Translate whole pages on device in Chromium too, with the same translation toolbar, automatic translation and Show Original as WebKit pages.
- Use Crest on iPhone Duo: the controls move to the side bar, pages use the outer display’s full width, and folded like a book, the sidebar and page, or a Split View’s two pages, each take one side of the fold.
- Open links in Crest from the share sheet on iPhone and iPad, including the first link in shared text.
- Swipe left or right on the iPhone address bar to move through your Space’s tabs in sidebar order, with the page sliding along under your finger.
- Swipe in from a page’s left edge to go back and from its right edge to go forward on iPhone and iPad.

### Changed

- Chromium is updated to 155.0.8059.84.
- Resizing the window, a split or the sidebar is smoother, and so is showing and hiding the sidebar with several Spaces open.
- The History, Archive and Downloads shortcuts open and close their list, even with the sidebar hidden, and Command-F searches the list that is open.
- Back and Forward keep working after a page moves to the other engine, and tabs keep that history after Crest relaunches or when duplicated.
- Next Space and Previous Space slide around from the last Space to the first and back.
- Typing a local address such as 192.168.0.1 or printer.local opens it over http, as other browsers do.
- A link route set to “Is Exactly” with just a site’s name, such as docs.google.com, matches that site’s home page.
- Pins fill each row to the number chosen in Settings, as far as the sidebar width allows.
- With tinted or clear app icons, Crest’s icon sits on the same background as other apps.
- On iPhone, tapping the address bar selects the whole address.
- On iPad and iPhone Duo, the sidebar starts narrower and its tabs scroll on into the bottom corner of the screen.
- A new iPhone or iPad that syncs with iCloud uses the default search your other devices use, and turning Crest Passwords on or off for a Space reaches your other devices.

### Fixed

- Crest no longer quits when you submit a form with a payment card or address in Chromium, open an http:// address that can’t be reached, or choose Download Languages in Page Translation settings.
- Restart and Update installs the update right away, and Quit in the Dock works again, even after another app has used AppleScript with Crest.
- Crest quits instead of waiting indefinitely when a Space couldn’t be fully deleted, and finishes deleting it the next time it opens.
- On macOS 26, switches, pickers and other controls in Settings take every click.
- Page commands, Translate, Reader, content blocking, the Web Inspector and moving a page to the other engine work in a Quick Window.
- Closing find in page or a Peek gives the keyboard back to the page, so the arrow keys and Space scroll right away.
- A hidden sidebar hides again when the pointer moves on to another app, and no longer slides back out on its own.
- Space switches keep sliding when you switch again or show or hide the sidebar during the slide, and the window buttons move with the sidebar when it changes sides.
- Pressing Option-Command-I again closes the Web Inspector or Chromium DevTools.
- Opening a link in another Space shows the link there instead of the Start Page.
- Control-A and Control-E move to the start and end of the line in the address bar.
- Pages in more languages, such as Swedish, translate, and a page Apple Translation can’t translate says so.
- Right-clicking an extension in Site Controls shows its menu without closing Site Controls.
- Link route address fields take clicks and typing, and Crest Studio no longer covers the Settings sidebar in a narrow window.
- A tab whose page couldn’t be opened shows the site it tried to open.
- While setup reads a browser you chose to import, it says so and offers Cancel.
- On iPhone and iPad, full-screen video shows instead of a black screen, Quick Windows stay on screen, and no empty band is left for a keyboard that isn’t showing.
- On iPhone and in a Mac Quick Window, leaving the address bar without going anywhere puts the page’s address back.
- On iPhone Duo, opening or closing the phone keeps you in the same Space, and a Split View shows both of its pages.

### Security

- Chromium 155.0.8059.84 brings upstream’s latest security fixes.
- Chromium no longer trusts the eight eMudhra certificate authorities whose keys were compromised, or the emSign ECC Root CA - G3 root, matching Chrome. Sites whose certificates still rely on that root stop loading in the Chromium engine and show a certificate warning instead. WebKit follows macOS’s own certificate trust.

### Upgrading

- The iPhone and iPad changes reach those devices separately, through the App Store.

## [0.8.1] - 2026-10-12

### Fixed

- On pinned tabs, the sound and sharing badge sits in the tile’s bottom corner instead of over the site icon, so the icon is easy to click.

## [0.8.0] - 2026-10-12

Crest 0.8 brings coding agents to Crest on Mac, a rebuilt command palette
and Settings, many more browsers to import from, and a quicker, more
consistent sidebar.

### Added

- Let coding agents such as Claude Code and Codex use Crest as their browser on Mac, in the Spaces you choose, from Settings › Agents. Crest asks before each new agent connects, and every tab an agent uses shows its badge.
- Search with a rebuilt command palette that ranks the pages and tabs you use most, completes sites you visit, lists recent tabs before you type, and searches a site or asks an assistant directly with Tab.
- Set one default search for every Space and one for private windows in the new Search section of Settings, and turn search engines, AI assistants and websites on or off.
- Import from Brave, Microsoft Edge, Vivaldi, Opera, Dia, Comet, Aside, ego lite, Chromium, and Chrome Beta, Dev, and Canary, and bring the Chrome Web Store extensions each profile used.
- See extension tab groups, such as the tabs Claude works in, as folders in the Space’s open tabs on Mac.
- Share a single Chromium tab with its sound when sharing your screen.
- See which tabs are playing sound, mute them from their icon, and see which tabs are sharing.
- Design a Space’s crest in Crest Studio, with previews on the Space’s own background and a color for each part.
- Choose how much the sidebar’s layers show the background through, from Ultra Thin to Ultra Thick, in Look and Feel settings.
- Choose how wide the window edge is that reveals a hidden sidebar.
- Start on a new tab in your default Space on iPhone and iPad.

### Changed

- Settings has a cleaner native look, with a page for each Space in its sidebar and a separate Tabs page.
- Switching tabs on Mac uses a fraction of the CPU and energy it did, without blank frames in between.
- Tabs, folders, Split Views, pinned tabs and the address bar share one shape and spacing that follows your corner setting, including Capsule.
- Site Controls, Peek, notices and other floating panels use the sidebar’s material.
- Imports keep split views and tab groups, bring every Zen and Firefox profile with open tabs, and keep as much as fits instead of stopping.
- Setup reads another browser’s data only when you choose to import from it.
- Page corners on Mac follow the window’s rounded corners.
- Sync settings say Up to date only when every change has reached iCloud, and iCloud sync catches up each time Crest opens.
- Chromium tabs keep their back and forward history across relaunches and updates.
- Chromium is updated to 154.0.8037.97.

### Fixed

- Crest no longer quits when you press a site’s Login button, allow the camera or microphone, or switch Spaces on macOS 26.
- iPhone and iPad open again instead of closing at launch.
- Large Chrome Web Store extensions such as Keeper install, and an extension installed right after launch no longer waits up to three minutes.
- Extensions that sign in at startup, such as Claude, stay signed in after Crest restarts.
- iCloud sync no longer stops on other devices after a tab moves to another Space.
- Restarting to install an update no longer gets stuck.
- Site Controls opens in full screen, and full-screen windows no longer show a dark band or flicker along the top.
- The back and forward history menus open at once instead of freezing Crest.
- Site icons are sharp on Retina displays.
- While a Peek is open, page commands act on the Peek, and Close Tab closes it.
- Command-G and Command-Shift-G move between find-in-page matches.
- Tabs with very long or unusual addresses reopen where they were instead of turning into a search.
- Imports from Chrome, Safari and Zen bring the right profiles, pinned tabs, bookmarks and passwords.
- Buttons in iPad and iPhone Settings respond to a single tap.

### Upgrading

- iCloud sync that stopped after moving a tab between Spaces resumes once all your devices are on this version.

## [0.7.0] - 2026-10-02

Crest 0.7 brings Chromium and WebKit together in one Mac app, with Chromium as
the default and a shared browser core across Mac, iPhone, and iPad.

### Added

- Run Chrome Web Store extensions in each Mac Space, including popups, side panels, shortcuts, and supported native companion apps.
- Choose Chromium or WebKit for new pages, one page, or a website. Use WebKit for Reader, whole-page translation, built-in blocking, and supported FairPlay video.
- Pause and resume Chromium downloads, including interrupted transfers when the server supports recovery.
- Receive local service-worker and extension notifications while Crest runs, with Space access and notification permissions respected.

### Changed

- Use one browser core for Space isolation, navigation, persistence, permissions, and synchronization across the Apple apps.
- Inspect Chromium pages with DevTools and save them as MHTML archives; WebKit keeps Web Inspector and web archives.
- Check the exact release source and both platform builds before signing and publication.

### Fixed

- Resume interrupted Chromium profile upgrades without losing track of existing profiles.
- Honor unsaved-changes prompts before switching engines or restarting for an update.
- Refuse unavailable page actions during engine startup instead of running them later unexpectedly.
- Advertise the macOS version required by the whole app when offering updates.

### Upgrading

- Mac requires Apple silicon and macOS 26.1 or later. iPhone and iPad continue to use WebKit on iOS and iPadOS 26.1 or later.
- Spaces, tabs, history, and Crest Passwords carry over from the previous stable release. Chromium and WebKit keep separate website data, so switching engines can require signing in again.
- Reinstall older WebKit extensions from the Chrome Web Store in the Spaces where you want them.
- See the [engine guide](HelpCenter/docs/browsing/engines.md) for feature differences, screen-sharing limits, and notification support.

## [0.6.33] - 2026-09-18

Crest 0.6.33 is a stability release with stronger permission boundaries, more
reliable extension and window behavior, and smoother browsing with large
sessions.

### Added

- Choose extension access during installation and install independent copies in multiple Spaces.
- Middle-click a split title to close the split and all its tabs.
- Choose to return saved tabs to their saved URL with one favicon click on Mac.

### Changed

- Find settings and customize Spaces more easily with distinct card headers and icons.
- See your chosen app icon, app details, and software updates together in a cleaner About page.
- Keep extensions responsive when browsing with many tabs and windows.
- Check installed translation languages more efficiently in Settings.
- Reduce delays when opening and closing large tab folders.
- Scroll more smoothly through long lists of saved and current tabs.
- Open and search large browsing histories with fewer pauses.
- Choose whether unloaded tabs appear dimmed in Look and Feel settings.
- Quick Window Space indicators now use balanced padding.
- Choose whether Now Playing appears in the sidebar.

### Fixed

- Rename Spaces without freezing Settings on macOS.
- Open new tabs and search from empty Spaces on macOS.
- Keep selected search results visible when navigating with arrow keys.
- Keep the selected pinned tab's glow from being cut off below the address bar.
- Keep site controls and permission prompts readable in light-colored Spaces.
- Keep General settings responsive while checking system permissions.
- Keep browsing responsive while large sessions and history sync in the background.
- Drag tabs through long sidebars more reliably, with edge scrolling that follows your display's refresh rate.
- Move large tab selections between Spaces reliably.
- Reduce memory growth when repeatedly opening the address bar.
- Avoid repeated background requests and memory growth on pages without a site icon.
- Keep the address bar and Back and Forward history in sync when following links within sites such as Reddit.
- Stop sharing your location immediately when you block or reset a site's location permission.
- Keep blocked and expired extension permissions disabled after reloads and restarts.
- Open a single browser window when finishing setup.
- Honor changed extension permissions and locked Spaces during pending operations.
- Show successful extension installations when copies in other Spaces cannot be completed.
- Extensions recover after becoming unresponsive without duplicating page scripts or clearing their session state.
- Keep permissions and private data separate when importing unsigned Firefox extensions.
- Select webpage text and use controls near the top edge without moving the window.
- Save the displayed PDF directly from the built-in preview.
- Quick Windows follow your browser border size while keeping balanced spacing around their controls.
- Image-converter extensions can save JPEGs repeatedly and keep their image menus after restarting Crest.
- Return from Picture in Picture to the tab and browser window that started playback.
- Prevent password manager popups and login-field suggestions from repeatedly reloading webpages.
- Settings remain fully visible while switching between Spaces.

## [0.6.3] - 2026-09-14

Crest 0.6 brings more ways to organize, personalize, and work across pages on
Mac, iPhone, and iPad.

### Added

- Create Space banners in Crest Studio with templates, heraldic artwork, shapes, patterns, independent colors, emoji, monograms, and searchable symbols.
- Customize sidebar placement, borderless windows, tab shape and scale, pin layout, address-field colors, app icon palettes, and page zoom from 25% to 500% in Look and Feel, with live previews and individual resets.
- Translate webpages on device with language detection and optional automatic translation. Supported languages may require a download.
- Open multiple Mac windows with shared Spaces and tabs while keeping your place in each window. Open disposable blank windows with the Space's cookies and extensions, or tear off a tab where you want its window to appear.
- Drag webpage links into a live Peek on Mac. Peeks stay with their tabs when opening another tab or switching Spaces.
- Use compatible extension side panels, Firefox sidebars, tab groups, and approved page debugging on Mac. Extension compatibility still depends on WebKit and the APIs each extension requires.
- Preview phone, desktop, and custom viewport sizes from the Mac developer toolbar with Shift-Command-I.

### Changed

- Select tabs, Split Views, and folders together to move and organize them on every platform, including touch menus and VoiceOver actions on iPhone and iPad.
- Drag individual tabs out of a Split View, or move the whole group from its header. Return pinned and saved tabs to their home URL with a double-click or an optional reset when closing.
- Open Settings in the browsing canvas on wider layouts and in a dismissible sheet on compact layouts. Keep Settings and Getting Started where you left them when switching tabs or Spaces.
- Choose folder icons from the full searchable SF Symbols catalog or use emoji. Customize folder colors and tab counts, with semibold tinted titles that adjust for stronger contrast. Reorder Spaces directly in Settings.
- Preview link destinations on hover, complete addresses from the current Space, and copy a tab's link from its menu. Search selected text in a new Crest tab.
- Use native link and image menus and choose Photos, camera, or Files for webpage uploads on iPhone and iPad. Clear current tabs with a dedicated control while retaining pinned and saved tabs.
- Open Getting Started in the first Space after setup, and rerun onboarding from Advanced settings.
- Open a blank Mac window with Command-Option-N and a Quick Window with Command-Option-Shift-N.

### Fixed

- Keep a collapsed Mac sidebar collapsed when opening the address editor with Command-L.
- Use the system dark background for Crest's app icon and every color palette.
- Keep wide folder symbols fully visible in Icon only mode.
- Keep pinned-tab outline colors consistent when pages unload. Prefer favicon colors when site themes are neutral, preserve black and white logos, and fade smoothly between color changes.
- Recover missing iCloud changes with a confirmed Pull from iCloud action. Preserve Space customization during overlapping sync, and keep blank, built-in, and extension pages from blocking web-tab synchronization.
- Keep page titles, history, Reader requests, favicons, extension panels, and sign-in links attached to their owning page and Space.
- Keep visible pages loaded when switching windows during memory cleanup, and reduce unnecessary background work while preserving loaded browsing state.
- Improve extension sign-in, background wake-up, popups, screenshots, permission prompts, and side-panel restoration, with stronger cookie and request-rule boundaries.
- Restore website camera and notification permission prompts with remembered per-Space choices, and stop camera capture when permission is revoked.
- Keep private and locked Space actions protected, clear unfinished drags when private browsing ends, and keep site-icon discovery private with bounded downloads.
- Improve first-page loading on iPhone and iPad, Space switching, webpage editor focus, high-resolution canvas rendering, and tab dragging through long sidebars.
- Keep sidebar selection, address completions, icon pickers, touch navigation, download feedback, and media controls consistent as pages and layouts change.

## [0.5.7] - 2026-08-27

### Added

- Added a public Crest 0.5 project and milestone, clear Reddit/GitHub/security support routes, maintainer governance, a documentation index, and Ko-fi and GitHub Sponsors links.
- Added simple monthly sponsor levels with optional public recognition and clear boundaries around access, endorsement, and roadmap influence.

### Fixed

- Made setup request Safari access before reading protected data, stopped empty Arc records from tripping the Space limit, and kept browser import to only the Spaces explicitly reviewed, finishing setup without an extra blank Space or manual-customization detour.
- Made a site's allowed location request resume immediately with a real Core Location result, and surfaced the macOS system-privacy block with a direct Settings recovery path instead of failing invisibly or asking again after refresh.
- Delivered allowed website notifications through macOS Notification Center, while keeping Crest's per-site decision boundary and surfacing the system notification setting when macOS blocks delivery.

## [0.4.0] - 2026-08-18

### Changed

- Added an explicit `CrestMobile Production` Xcode scheme that runs a Release build against production CloudKit, while keeping the ordinary mobile scheme on Debug and development CloudKit.
- Advanced Crest's development builds to the 0.4.0 release line.
- Enabled automatic update checks, downloads, and installation by default for direct macOS builds while keeping both controls available in Settings.

### Fixed

- Replaced extension-specific WebKit package patches with a capability-selected compatibility runtime shared by Manifest V2 and V3 backgrounds, declared content scripts, and extension-owned pages. It preserves native WebKit APIs, supplies bounded missing surfaces from a temporary runtime copy, uses each package's declared manifest and resource paths, and no longer blames Developer ID signing for ordinary runtime failures. Newly verified archives remain untouched, while a temporary-load migration removes a legacy Crest-generated worker prelude from packages saved by earlier builds without rewriting the stored package.
- Made an installed Development or Nightly artifact select its own update channel on first launch instead of inheriting a saved channel from a differently packaged build, while preserving later explicit channel choices.
- Told extensions about a Peek's page and about each card a selection presents before those pages start loading, so an extension's content scripts can reach its background on the first try. WebKit answers a content script only for a web view it can map onto an announced tab, so a Peek — whose page the session never carried as a tab at all — left extensions like Dark Reader holding the partial styling they applied while asking, until the page was reloaded. Promoting such a Peek into a tab or a split card carried the half-styled document with it.
- Named public nightly tags, release titles, and assets with their UTC date and source commit instead of an opaque workflow run number, while retaining the monotonic build number only for Sparkle's internal update ordering.
- Kept the release tag as a directory in generated Sparkle download URLs and made publication reject an appcast that does not point to its exact GitHub Release asset.
- Authenticated the release workflow's isolated update-feed repository so a notarized GitHub Release can create and advance the Sparkle appcast branch.
- Removed absolute build-machine paths from the published Help Center assets and made every Help Center build sanitize its generated configuration before publication.
- Restored extension popups that open against a background WebKit has already put to sleep. A nonpersistent background is evicted seconds into a session — Dark Reader's was started at launch and stopped 5.6 seconds later — and Crest was relying on WebKit to bring it back when the popup asked it something. It does not: the popup's opening message was answered with nothing at all, and an extension that reads that answer without guarding it never recovers. Dark Reader destructures the reply, so the exception it threw left the promise its popup awaits unsettled and the popup on "Loading, please wait" for the rest of the session, with the pages its content scripts had begun styling left half-dressed behind it. Crest now loads an extension's background content before the popup document does, and unloads the document WebKit preloads the moment the popover is asked for, so the popup that opens is one whose opening handshake can be answered. A background that genuinely fails to load never reports back at all, so the popup is presented anyway after a short deadline rather than leaving a broken extension's button inert.
- Made a Split View divider follow the pointer instead of fighting it. A divider is drawn at the boundary its own drag moves, and the drag was measured against that moving handle rather than against the row it sits in, so every frame reported the pointer's travel minus the handle's: the boundary tracked at half speed, and a hand holding still was amplified into a standing oscillation that shook the pages either side. The drag is now measured in the columns row, which does not move while fractions change, and applies without an implicit animation, so a divider tracks the pointer exactly and stops when the pointer stops. The material veil that was covering the pages mid-drag is gone with it: cards render live through a resize.
- Restored drop feedback for saved tabs in every shape a sidebar can take. A folder holding every saved tab measures exactly what the saved list around it measures, and overlapping runs were ranked by area alone — so the list could end up owning the rows nested inside it, and the drag went dark: nothing stepped aside, no insertion line appeared, and releasing quietly unfiled the tab instead of putting it where it was pointed. Nesting now outranks area, so a folder's rows always answer for the pointer over them. A run with no rows of its own draws its own insertion line as well, since the line is normally drawn by the row beside the gap and an empty run has none — an unfiled saved list under a folder that holds everything, a pinned grid nobody has filled, a current list just cleared. The unfiled saved run also keeps a small band below the folders, so it stays somewhere a tab can be dropped outside them.
- Restored the live drop feedback a sidebar section shows when a tab is dragged into it from elsewhere. A row that changes section — dragged out of the current list into the saved one, or into a folder — keeps its identity but is a different view on either side of the move, and the one it left runs its `onDisappear` after the new one has already measured itself. That late removal wiped the measurement the arrival had just made, leaving the row with no geometry at all: the section it landed in no longer opened a gap for later drops, no insertion line anchored on it, and drops aimed straight past it — landing in the right list, but not where they were pointed. Row measurements now name the view that made them, the way section and split-card measurements already do, so only the view genuinely leaving can clear one.
- Kept a lifted sidebar row visible for the whole of its drag on macOS. The preview that follows the pointer — a tab, a folder, or a whole split group — is now drawn in a transparent, click-through window ordered above the browser window from the moment the row lifts until it lands, rather than being handed over at the edge of the page. Handing it over only moved the seam: the page's web view is an AppKit subtree that paints over anything SwiftUI draws beside it, but window chrome and the insets around the content area clipped a travelling preview just as effectively. The row keeps its place in the list — the gap it leaves, its neighbours stepping aside, the insertion line — and the pinned-tile and page-card morphs are unchanged, only relocated.
- Made the drag-to-split drop preview the exact card it is standing in for. The slot under the pointer is now a real column of the split, wearing the same page surface, rounding, seam, and border every card wears, at the exact width and position the dropped tab will get — half the row beside a lone tab, a third among two, a quarter among three, rather than a fixed narrow strip. Releasing swaps the card into that column without moving anything else.
- Restored the missing lift on iPhone and iPad split-group sidebar rows: pulling a group now lifts and reorders the whole run as one row, through the same drag-and-drop path tab and folder rows use, while holding still keeps opening the group's context menu.
- Restored the help center's mobile navigation flyout by keeping the header blur from constraining its fixed drawer to the navbar height.
- Avoided an Xcode 26.6 actor-isolation compiler crash in macOS onboarding while preserving Release batch compilation.
- Added breathing room between the Quick Window traffic lights and its inline address toolbar.
- Made pinned tabs visually indicate when they are unloaded, matching the residency appearance and accessibility state of saved and current tabs.
- Aligned Quick Window traffic lights with its inline toolbar using the same unified native titlebar metrics as the main browser window.
- Opened a mobile Peek or Quick Window promotion directly into its newly selected tab instead of leaving the compact browser in the tab viewer.
- Restored predictable tab-close navigation with a per-Space activation history, returning to the most recently visible surviving tab and showing the unloaded state when no prior tab remains.
- Restored scripted in-page handoffs to external apps behind Crest's exact origin, scheme, and Space-scoped consent prompt instead of silently blocking meeting and sign-in links.
- Rasterized SVG site icons into durable favicon image data, preferred scalable web-manifest branding, carried the page's browser identity into protected icon requests, and prioritized browser icons over legacy touch artwork so modern site icons render correctly in tabs and restored sessions.
- Bound macOS extension flyouts to their invoking controls and unloaded a dismissed extension popup through WebKit’s own close-popup lifecycle so reopening it reaches a live background instead of a stale loader.
- Removed Crest’s Dark Reader package rewrite so the signed Chrome Web Store package installs, loads, and restores unmodified on current WebKit.
- Corrected Peek’s keep shortcuts and auxiliary mouse routing so Return stays in Peek, explicit keep actions still promote, page history wins under web content, and Space navigation remains the fallback.
- Aligned Quick Window and Peek around the originating web-content region's shared 80% geometry, clipped fullscreen chrome materials to the active window bounds, and removed the native toolbar reservation while fullscreen.
- Repaired ten stale optional regional ad-filter sources and kept successfully updated lists active when another enabled source fails.
- Restored Microsoft portal favicons by discovering late cross-origin and manifest icons in-page, rejecting HTML fallback responses, then downloading real image candidates with Space-scoped cookies and cache bypassing.
- Restored live tab and folder drag previews on macOS by returning native drag-source ownership to the initiating gesture coordinators, with event-owned sessions and eagerly rasterized drag images, plus clear folder reordering and nesting drop targets.
- Stabilized the compact iPhone Space editor layout while renaming so live preview updates cannot trigger a collection-view layout feedback loop.

### Added

- Added a signed Development update channel that publishes the latest public `main` commit through a rolling GitHub prerelease and a dedicated Sparkle appcast.
- Added a SwiftUI-native Sparkle 2 update experience for direct macOS releases, with stable and nightly channels backed by signed GitHub Release appcasts.
- Added GitHub workflows that validate the source, sign and notarize arm64 Mac disk images, publish checksums and provenance, deploy the product site, and advance the update feed only after immutable release assets exist.
- Opened the project under the Mozilla Public License 2.0 with explicit third-party notices, contributor and security guidance, and a separate trademark policy that reserves Crest branding for official distributions.
- Added **Split View**: two to four tabs from a Space held together as side-by-side cards in the main view. Each card is a full content surface with the window's own rounding, the resize handles live in the gaps between cards rather than on their edges, and a group's column widths are remembered per window and per device. The whole split reads as one stacked row in the sidebar — the split glyph, the member count, and its members gathered below them — and clicking a member opens the group with that member focused. On macOS a member is simply the Space's ordinary tab row nested inside the group's container: the same height, favicon, hover, close or unload control, rename, and selection accent every other tab has, with **Remove from Split** added to its menu. Only the group carries the lift, so members never tear out of a run mid-drag: dragging any of them reorders the whole split as one block. The address field, back and forward, Find, zoom, share, and every keyboard shortcut speak for the focused card, which wears a Space-accent focus ring whenever more than one card shows. Clicking a card focuses it; the opt-in **Focus Follows Mouse in Split View** setting extends that to the pointer, and never moves focus while the address bar is being edited. Scrolling and trackpad back/forward always act on the card under the pointer, focused or not. Groups travel with their tabs through iCloud, so a split made on the Mac opens on iPhone and iPad. Make one by dragging a tab onto the page, from a tab or split context menu, from the **Tabs** menu, from the command palette, or by right-clicking a link.
- Added a resize pointer to Split View dividers. Hovering one shows the column-resize pointer on macOS and the pointer highlight on iPad, so the boundary reads as draggable before it is grabbed, and a capsule marks the divider that a drag has hold of.
- Added **Open Link in Split View** to the macOS web-content menu. Right-clicking a link opens it as a new card beside the page it came from, focused, the same way a dropped tab joins a split. The item appears only where it can act: over an actual `http`/`https` link, on a card whose group still has room under the four-member cap, and never on a pinned tab or a Start Page. The link comes from the page's own `contextmenu` event rather than a second hit test, and is retired with the menu that used it, so a right-click on plain text can never inherit the last link.
- Added rearranging the cards inside a split, by keyboard and by menu, on every platform. **Move Split Card Left** and **Move Split Card Right** are on ⇧⌘← and ⇧⌘→ — rebindable on the Mac, fixed on an iPad keyboard — and sit in the **Tabs** menu and the command launcher beside the other Split View commands. Every tab's context menu grows **Move Left** and **Move Right** while that tab is in a split, so a right-click on the Mac and a long press on iPhone and iPad reach the same two moves. A card steps one place at a time and stops at the ends rather than wrapping around, and the items dim once it has nowhere further to go; the card being moved keeps focus, so the address field and every page command go on speaking for the page you are reading. "Left" and "Right" mean the sides of the screen, so under a right-to-left layout — where the cards themselves are mirrored — they still move a card the way they read.
- Added carrying a Split View card on the pointer on macOS. Holding **⇧⌘** and pressing a card picks it up — the pointer's half of **⇧⌘←** and **⇧⌘→**, so one idea is reached two ways: the card rises off the row and follows the cursor at the exact point it was grabbed, its own column becomes an empty slot, and the cards it passes step aside into the order a release would leave them in. Every card can be picked up, the one the chrome is currently speaking for included; a card becomes the focused one *because* it was picked up, never in order to be. It is the page itself being carried, not a token standing in for it — the card shows its live rendering, asked of WebKit inside the press that started the carry, before the row has been told anything, and crossfaded in behind the pointer so the pickup never waits on it, with the tab's title and favicon in the meantime. A card that is not showing a live page — a Start Page, or one that has not loaded — carries that title and favicon for the whole trip rather than a picture of the empty web view it was handed but never used. Releasing drops the card into the slot the gap is standing in, and Escape or a right-click puts it back where it started with nothing changed. So does anything that takes the pointer away mid-carry — the window losing focus, the app going to the background, the card leaving the row — each of which returns the row to rest rather than leaving a press half-held. The columns keep their widths through all of it, and the pages stay live the whole time, including the one being carried. A press without ⇧⌘ still focuses the card and reaches the page as it always has, presses on a resize divider still resize, and a window showing a single tab has nothing to carry. Known trade-off: ⇧⌘-clicking a link conventionally opens it in a new foreground tab, and inside a multi-card split the carry claims that press instead — plain ⌘-click, ⌥-click to download, and ⌥⇧⌘ all still reach the page untouched, and a window that is not showing a split is unaffected.
- Added drag-to-split on macOS: dragging a sidebar tab over the page morphs its lift into a page-shaped card and opens a real column at the slot under the pointer — beside a lone tab as readily as between existing cards — which releases into a new or extended split. That column is the card it is standing in for, drawn early: the same page surface at the same width the drop will give it, so releasing changes what is in the slot and nothing else. Drops that would do nothing show no column at all: a folder, a whole group, a tab from another Space, a tab already on show, and a split already at four members are all refused before it appears.
- Added Split View to iPhone and iPad. iPad lays a split out as the same resizable columns the Mac uses, focused by tapping a card. iPhone pages the same cards one at a time: the horizontal toolbar swipe now moves between cards instead of switching Spaces, and does nothing outside a split — Spaces still switch from the tab viewer and with ⌥⌘←/→. A hardware keyboard gets Focus Next and Previous Split Card on ⌃⌘→ and ⌃⌘←, Separate All Tabs on ⌥⌘U, and all five Split View commands in the command launcher. Cards near the one you are reading stay live; under critical memory pressure only cards more than one swipe away are ever reclaimed, and they come back as you reach them.
- Added per-Space retention controls for history, archived tabs, and download records, with warned immediate cleanup, active-session sweeps, and sync tombstones that keep expired records from returning.
- Added full-color search-provider logos to command-palette search actions and every Space search-engine menu on macOS and mobile.
- Added an Arc-style hover Clear action for archiving every current tab without touching pinned or saved tabs, transient page-zoom percentage feedback on macOS and mobile, and a session-only Proceed Anyway path scoped to the exact Space profile, host, port, and leaf certificate.
- Added a secondary-click menu to pinned extension buttons and site-popover extension actions, carrying the extension's own WebExtension menu items and commands alongside Extension Settings, pinning, and Manage Extensions.
- Added the WebExtension tab capabilities Crest can answer honestly: tab size, reader-mode availability, state, and toggling wired to Crest's reader mode, webpage locale detection, and visible-tab snapshot capture.
- Added real window geometry for `browser.windows`, reporting the frame, screen frame, and derived state of the window presenting a Space.
- Added Web Inspector access to extension background content and popups, listed under each extension's display name.
- Added automatic updates for Chrome Web Store extensions, with a global on/off switch, a daily, weekly, or every-two-weeks cadence, a **Check for Updates Now** action, and a last-checked status row in Extensions settings. Crest asks the store which version it publishes, compares it against the installed version numerically, and only then downloads a replacement through the existing signed-CRX3 verification, publisher pin, and rollback path. Only installations recorded as Chrome Web Store sourced and currently switched on are updated; unpacked and app-hosted extensions are left alone, and pinning, permission decisions, keyboard shortcuts, and the original install date survive a replacement.
- Added Firefox extension installation from addons.mozilla.org, with an in-page **Add to Crest** button, a native review sheet, and per-Space installation. Crest resolves the add-on through Mozilla's public API and refuses any package that does not reproduce the exact SHA-256 digest, byte count, gecko identity, and Mozilla signing artifacts that listing published.
- Added the app-side services behind Crest's WebExtension emulation layer as independently testable ports: notifications, per-Space history and top sites, web authentication, and address-bar keyword suggestions, each with an adapter, an in-memory double, and no dependency on WebKit or the extension subsystem.
- Added emulated notification delivery with a forgery-resistant per-extension identity scheme, per-extension grouping and button categories, host-truth enumeration, and interaction streams that reach only the extension that posted the notification.
- Added per-Space history search, visit lookup, targeted URL and date-range deletion, and frecency-ranked top sites, all bound to an exact Space and browsing-profile assignment, plus history change events derived from Observation so ordinary browsing raises them without polling.
- Added targeted history removal to the session and store (`removeHistory`, `deleteHistory`) with narrowed per-Space save scopes and explicit-delete tombstones, replacing whole-Space clearing as the only option.
- Added a web authentication service that refuses redirect shapes the system session cannot intercept instead of hanging on them, and re-checks the returned redirect against the prefix the caller asked for.
- Added an address-bar keyword seam: a keyword registry, an async suggestion provider port, command-palette routing and rendering for keyword mode, acceptance dispatch carrying the open disposition, and context-menu removal for provider-deletable rows.
- Documented the emulation services, the fields Crest's history cannot supply, and the associated-domain constraint that blocks `chromiumapp.org` redirects, in `Documentation/ExtensionEmulationServices.md`.
- Established one strict semantic-version source and automated drift checks for every app target and build configuration.
- Added a readable release history and focused commit contract for the 0.3.0 architecture cleanup.
- Added changed-file Swift formatting, architecture and Xcode 27 compatibility guards, plus a repeatable evidence-only dead-code audit.
- Added verified WebExtension companion/native-messaging support for Direct builds on macOS.
- Added an exact vertical-feature debt ledger and executable checks for one-type files, view/component ownership, large computed view builders, deterministic colocated previews, and preview data isolation.
- Added live action-popup coverage that drives WebKit's own action popup across ordinary and Chrome Web Store tabs, after both a fresh install and a launch restoration, and fails when a host call the popup depends on never settles.

### Changed

- Focused hosted automation on publishable-source compliance, clean macOS and iOS compilation from the authoritative `project.yml`, Help Center generation, and signed release packaging; the broader test suites and generated-project byte comparison remain local gates while the public workflow settles, and dependency updates arrive as grouped monthly maintenance instead of a stream of individual pull requests.
- Made GitHub Releases the only macOS distribution path while retaining TestFlight and the App Store for iPhone and iPad.
- Reduced built-in content blocking to Crest's bundled local tracking-prevention rules. Downloadable AdGuard-compatible lists and their conversion pipeline were removed; broader blocking remains available through user-installed extensions.
- Kept tabs loaded after they are first opened so switching tabs does not reload them, while continuing to load only the selected tab at launch and releasing the oldest eligible background pages under memory pressure. Active tabs, playing media, camera or microphone use, and tabs marked **Keep Loaded** remain resident; mobile uses a more conservative release budget.
- Updated the public site and help center with Firefox Add-ons installation, everyday-use, updating, compatibility, and troubleshooting guidance alongside Chrome Web Store support.
- Clarified the public homepage’s Space customization copy around Crest’s Apple-device availability.
- Made command-palette editing a native single scrolling line and placed the search action—with its search icon—first for non-URL queries.
- Refined the public homepage to describe Crest without first-person creator copy and gave the iPhone platform capture enough room to read at desktop and mobile widths.
- Eliminated the final vertical-structure debt by promoting independently owned nested models, colocating deterministic previews with meaningful visible components, and keeping persisted AppStorage screens as explicit effect boundaries.
- Split aggregate Commands, extension import, WebKit page, credential, popup, sync, archive, favicon, and website-data adapters into matching owners while preserving their existing platform and Space/profile boundaries.
- Kept scope-dependent private implementation helpers and closure aliases nested, while moving public feature support into shallow standard ownership and correcting extension filenames to match their owners and conformances.
- Replaced Design System preview wrapper buckets with deterministic previews beside each visible component, kept style-owned rendering surfaces private to their button styles, and split the controls-gallery placement model into its matching file without changing runtime controls.
- Reorganized Space paging, swipe gestures, auxiliary mouse navigation, and platform scroller suppression into focused vertical owners, and prevented a delayed post-drag recenter from overriding a newer exact Space selection.
- Reorganized shared Chrome layout, navigation, utility, and sidebar-resizing foundations into focused vertical owners without changing Space identity or presentation behavior.
- Decomposed the shared navigation-failure surface into previewable content, action, suggestion, and technical-detail owners while preserving exact retry/back page callbacks, compact and regular layouts, and failure copy.
- Rewrote the public homepage in a more personal voice and moved extension audits, signing gates, and other implementation details out of its product story and into the help guides.
- Synced the measured extension compatibility, native-companion boundaries, and troubleshooting guidance from the current main branch.
- Unified the macOS, iPhone, iPad, App Store, and Direct build metadata under the 0.3.0 release line.
- Centralized pinned, saved, current, folder, and cross-Space tab moves under one exhaustive placement policy.
- Rebuilt macOS Settings with native split navigation and sidebar search while separating navigation state, page shells, Space editing, and window sizing into focused owners.
- Split Advanced Settings setup actions, buttons, and section composition into matching vertical owners with deterministic previews while preserving each platform's setup capabilities.
- Split shared Settings bindings, selection-repair presentation, and their `BrowserStore` and `View` extensions into matching component and support files without changing SpaceID-bound edits.
- Decomposed the shared Settings pane and header into previewable pane, icon, copy, and layout owners while preserving each platform's shipped metrics and accessibility identifiers.
- Decomposed mobile Settings into compact and regular shells, destination routing, Space customization, credentials, and preview support owners while preserving search, exact SpaceID selection, and platform-adaptive navigation.
- Moved the mobile Archive, History, and saved-password sheets into dedicated feature roots with focused content, credential-state, and presentation owners while preserving exact Space-scoped restore, history, Keychain, and export behavior.
- Moved mobile navigation state, layout values, transition policies, and tab-promotion targeting out of WebKit infrastructure into matching Browser feature owners without changing compact/regular navigation behavior.
- Decomposed the mobile browser root into previewable compact, regular, sidebar, detail, utility, and command-palette components while preserving exact Tab, Space, profile, and private-browsing routing.
- Decomposed mobile onboarding into directly previewable page, lifecycle, setup, and action owners, with an injected draft boundary that keeps previews off persisted setup state while preserving exact Space and profile setup behavior.
- Simplified the vertical architecture guard to preserve cohesive SwiftUI composition, require direct previews for visible components rather than invisible modifiers and bridges, and keep macOS Sidebar support shallow while preserving exact Space/profile selection, lock, drag, and utility behavior.
- Flattened shared, macOS, and mobile extension-manager ownership into standard feature roles, distributed deterministic direct previews to visible components, and replaced preview package access with fixed in-memory dependencies without changing Space-scoped extension behavior.
- Flattened the remaining macOS onboarding policies, launch-window seams, and legacy-draft cleanup into standard support ownership, colocated its chrome previews, and split failure presentation into a matching model without changing setup behavior.
- Flattened macOS and mobile Settings platform seams into standard component and support ownership, colocated previews for visible extension and privacy sections, and split the native window-sizing host without changing platform destination availability or window behavior.
- Distributed Privacy Settings previews beside the pane and its visible sections, with fixed in-memory Space, permission, and filter-list dependencies, and moved its layout into standard support ownership without changing Space-bound privacy behavior.
- Colocated Extension Settings preview coverage with the pane using fixed in-memory Space and extension dependencies, and removed its unused layout owner without changing requested-Space selection or private-Space gating.
- Split keyboard shortcut values, policies, persistence, platform input, and settings UI into focused vertical owners while preserving every command raw value and default, the `crest.keyboard-shortcuts.v1` JSON contract, conflict/reset behavior, and extension selection by stable Space ID.
- Moved mobile browser selection, lifecycle, command, sidebar, and page-synchronization workflows into a typed observable root model while keeping compact and regular presentation state in SwiftUI and preserving private browsing and Space/profile isolation.
- Separated external-link routing policy, observable preferences, and UserDefaults serialization into Domain, Application, and Infrastructure owners without changing saved settings.
- Moved SwiftUI color-scheme mapping into the design system so Space foreground contrast remains a framework-neutral Domain policy.
- Reorganized portable tab migration into feature-local browser adapters, models, sanitization policy, and orchestration without changing imported data.
- Reorganized Crest archives, bookmark adapters, history normalization, file documents, and SQLite import under the Data Portability feature without changing serialized formats or imported Space isolation.
- Decomposed Data Portability into previewable export, import, progress, document, workflow, adapter, codec, and file-service owners while preserving archive formats, exact existing Space/profile identities, fresh imported identities, and protected-Space export checks.
- Moved import-review destinations, Space customization, selection state, and merge planning into focused Data Portability models without changing review behavior.
- Moved default-browser and passkey workflow controllers into Application and their framework adapters into shared or platform Infrastructure, leaving Domain framework-neutral.
- Split Quick Window scene, view, picker, external-link handling, and link-click policy types into focused transient-browsing owners.
- Decomposed Quick Window into previewable scene, surface, toolbar, address, destination, and page-state owners, and bound requests, transient leases, history, archives, and promotion to the exact Space and browsing-profile assignment so Space replacement or deletion cannot reuse another profile's WebKit state.
- Decomposed macOS Peek and mobile transient browsing into previewable vertical component families, with exact Space/profile request identity, lock-safe WebKit release and restoration, request-scoped dismissal, and assignment-bound history, archive, retargeting, and promotion behavior.
- Bound private-Space unlock grants, Sidebar pager settlement, saved-location restoration, tab moves, utility chrome, and captured history deletion to exact Space and browsing-profile assignments, rejecting locked, replaced, or deleting destinations.
- Decomposed the mobile Sidebar and Downloads surfaces into previewable Chrome, Space, utility, action, tab, and folder owners while preserving exact Space/profile routing and using only fixed in-memory preview dependencies.
- Split manual-setup values into focused Domain files and moved its stable `UserDefaults` draft adapter into Infrastructure without changing saved drafts.
- Extracted the manual-setup sidebar preview and centralized its feature-specific layout geometry under a local metrics owner.
- Split password settings into dedicated policy, observable workflow, platform-layout, pane, and descriptor-row files while preserving Space-scoped Keychain behavior.
- Split Chromium password import into explicit model, service, Keychain, crypto, and SQLite owners without changing import behavior or Space-scoped credential storage.
- Split the credential vault into framework-neutral Keychain values and ports, an application codec and actor, and a Security-only adapter without changing storage, synchronization, or Space-isolation behavior.
- Split site-permission values, observable decisions, persistence, and WebKit conversion into Domain, Application, and Infrastructure owners without changing Codable records, default storage, or Space isolation.
- Moved onboarding discovery, import queueing, review, commit, retry, cancellation, summaries, and failures into a typed observable workflow while keeping presentation state in the view.
- Decomposed the macOS onboarding window into previewable Welcome, Import, Space-review, manual-setup, and completion component families while preserving its typed workflow and SpaceID-bound presentation state.
- Decomposed onboarding source, Crest-result, sidebar, and Space-customization import previews into deterministic vertical components while preserving source and destination Space/profile identity.
- Split the macOS onboarding tutorial into previewable copy, artwork, tabs, sync, and presentation-model owners without changing its steps, actions, or localized guidance.
- Split shared onboarding palette, typography, panel, and button-style owners into matching Components, Models, and Support files without changing their visual roles.
- Decomposed manual Space setup into previewable content, editor, picker, placement, and sidebar component families with focused model and support owners while preserving exact SpaceID and browsing-profile identity.
- Split installed-browser discovery, profile and password-store location, security-scoped access, file picking, and import reading into focused onboarding owners without changing detection or import behavior.
- Rehomed macOS installed-browser discovery and Chromium password import values, services, and adapters under Onboarding’s Models, Services, and Support roles without changing access, Keychain, SQLite, or Space-bound import behavior.
- Decomposed shared Space branding into banner, crest, identity, shape, rendering, model, and platform-support owners with deterministic colocated previews while preserving the existing heraldic mappings and platform artwork output.
- Decomposed the Space branding editor into previewable foundation, crest, field, gallery, mark, and pattern owners while preserving atomic normalized binding updates and the existing forge order.
- Reorganized the shared Space selector into previewable rail, icon, and menu families while preserving exact SpaceID selection, private-Space indicators, commands, and button interaction states.
- Decomposed the shared Command Palette into previewable presentation, card, result, matching, and action owners, and bound its source and destination actions to exact Tab, Space, and browsing-profile assignments so locked, replaced, or deleting Spaces cannot leak results or receive stale actions.
- Decomposed pinned-tab, tab/folder organization, and cross-platform Sidebar drag surfaces into previewable vertical owners, with exact source and destination Space/profile validation and session-bound drag completion so stale or duplicate tab identities cannot cross browsing profiles.
- Decomposed shared Archive, History, and Downloads list presentation into previewable state, section, row, action, fan-control, model, service, and support owners while preserving exact Space/profile preparation and captured action routing.
- Revalidate automatic-download retries after WebKit returns so deleted, replaced, canceled, or superseded Space/profile work cannot register a stale download.
- Deferred onboarding summaries and known failures through localized resources, with whole-phrase English and Arabic plural rules for every independent count.
- Split Cloud sync values, policies, application ports, CKSyncEngine delegation, and UserDefaults transport state into explicit layer owners without changing record, account, or persistence semantics.
- Split the observable Cloud sync workflow from CloudKit account and snapshot access, transport creation, diagnostics values, and UserDefaults preferences without changing reconciliation, account-change, or Space-isolation behavior.
- Separated automatic-download policy, risk values, progress normalization, and per-profile download ledgers into Domain owners while keeping localized warnings in Presentation and WebKit lifecycle, authentication, destination, quarantine, and Space-scoped permission behavior in Infrastructure.
- Split browser authentication values and policies, the typed credential session, and Foundation challenge adapters into Domain, Application, and Infrastructure owners without changing retry, trust, save, or Space-isolation behavior.
- Split session save scope, the persistence port, UserDefaults transport, private in-memory storage, and BrowserStore composition into explicit Application and Infrastructure owners without changing keys, migration, history, favicon, or Space-isolation behavior.
- Split browser navigation values and policies, external-scheme consent workflow, and WebKit policy translation into explicit Domain, Application, and Infrastructure owners without changing link, download, or hand-off behavior.
- Split filter-list selection and rule policies, the observable refresh workflow, persistence and network ports, converter, cache, notification, and WebKit adapters into explicit owners without changing source, update, compiled-list, or Space-isolation behavior.
- Decomposed Filter List Settings into deterministic shared and platform owners, bound its sheet to the initiating Space/profile assignment, and made custom-list synchronization, refresh scheduling, and compiled-rule publication reject canceled or stale work.
- Decomposed credential details into deterministic shared and platform owners, bound reveal and copy operations to the exact credential and Space/profile assignment, and made dismissal, profile replacement, and clipboard expiry reject stale secret publication.
- Decomposed the mobile browser root into standard component, model, and support owners with direct deterministic previews while preserving exact selection, Space/profile, WebKit, toolbar, and navigation lifecycle behavior.
- Decomposed the macOS browser root and native window-control seam into standard component, model, and support owners with direct deterministic previews and injected sidebar-width persistence.
- Moved the observable Peek/Quick Window coordinator and activity clock from Domain into Application while preserving transient browsing state and inactivity behavior.
- Split favicon palette values and perceptual color selection, the bounded coalescing cache, ImageIO decoding, and SwiftUI color mapping into explicit Domain, Application, Infrastructure, and Presentation owners without changing extracted accents or cache behavior.
- Decomposed tab-favicon rendering and Start Page artwork into deterministic vertical owners, with exact payload and render-request identity plus generation-bound image and per-profile fallback caches so canceled or invalidated work cannot display or restore a stale cross-Space icon.
- Decomposed cross-platform Link Settings into deterministic vertical owners, made deferred route edits UUID-scoped and field-specific, and excluded missing or deleting Spaces before external-link routing without silently rewriting saved choices.
- Split Reader Mode state, typed bridge actions, localized presentation, snapshot decoding, and WebKit JavaScript execution into explicit owners without changing selection, sanitization, restoration, or page behavior.
- Centralized launch, test-isolation, onboarding, performance-harness, and credential environment parsing in one typed launch value without changing flag precedence or defaults.
- Split WebExtension tab and window projections, mutation ports, WebKit adapters, and macOS permission and popover presentation into explicit owners while preserving command routing, source-origin access, and strict Space/profile isolation.
- Split WebExtension installation, restoration, runtime-context, permission, persistence, command, toolbar, and observation responsibilities behind the existing controller-pool facade while preserving persisted records and Space isolation; rejected first-time installs now discard provisional state, and observer tokens release with their owner.
- Split page-owned credential capture and save-prompt states into focused application models, then unified macOS and mobile prompt copy, actions, retry routing, and localized Space context under one exhaustive presentation route without changing save or system Passwords ordering.
- Decomposed mobile credential fill chrome into previewable prompt surfaces, headers, strong-password actions, suggestion states, rows, and fixed nonpersistent support without changing page- or Space-bound credential operations.
- Centralized macOS window transparency in one launch-scoped observable store with in-memory isolated composition, exact persisted keys, and previewable settings and AppKit bridge owners.
- Moved WebExtension artwork hashing and bounded asynchronous decoding out of SwiftUI rendering, with typed Space-scoped identities, coalesced requests, and identity-gated presentation that preserves the existing fallback.
- Split WebExtension compatibility and access values into Domain, runtime summaries into Application, and discovery and presentation into shared SwiftUI and platform adapters while preserving native-messaging security, persisted records, and exact Space scope.
- Centralized macOS and mobile page-surface routing under one exhaustive framework-neutral presentation policy while preserving failure handling and compact unloaded-tab restoration; mobile page chrome, commands, metadata, and content-blocking actions now validate the exact selected Tab, Space, and browsing profile before touching WebKit or browser preferences.
- Split macOS browser detail, web content, find, credential, Chrome Web Store, and platform WebKit presentation into vertical feature components with exhaustive routes and isolated deterministic previews while preserving exact Tab, Space, and profile ownership.
- Decomposed macOS developer tools, Start Page, Site Settings, and WebKit hosting into previewable vertical components and explicit platform infrastructure while preserving active-page navigation, certificate review, and exact Space-scoped permission decisions.
- Decomposed macOS pinned-extension and site-control surfaces into previewable Sidebar component families and WebKit popup-anchor infrastructure while preserving exact Space and tab action routing.
- Decomposed the macOS Space switcher into previewable selection, icon, drop, and utility controls while preserving exact SpaceID selection and cross-Space profile rebuilding.
- Decomposed the macOS Sidebar address field into previewable editor, security, clear-button, and loading-surface owners without changing certificate review, accessibility identifiers, or unloaded-page presentation.
- Decomposed the macOS Sidebar tab row into previewable activation, rename, favicon, trailing-action, drag/drop, and middle-click owners while preserving exact TabID and SpaceID routing.
- Split Chrome Web Store verification, routing, package, identifier, protobuf, and data-format owners into matching files, and made one file-scope declaration per Swift file an enforced repository contract.
- Decomposed the macOS saved-folder row into previewable header, tab, drag/drop, interaction, and layout owners while preserving exact SpaceID, FolderID, and TabID routing.
- Split the macOS Space pager's scroller policy extension, observer view, and previewable representable into matching platform files.
- Split Space-selector initializer extensions and optional accessibility modifiers into one file-scope owner per Swift file.
- Split session, credential-suggestion, and WebExtension tab/window port defaults and BrowserStore gateways into dedicated extension files.
- Split Cloud account and synchronization phase descriptions from their value declarations into dedicated extension files.
- Split production favicon and WebExtension icon decoder instances from their public convenience extensions into dedicated infrastructure owners.
- Split the window-state persistence port, default behavior, UserDefaults transport, and in-memory adapter into matching Application and Infrastructure files without changing the `crest.windows.v1` format or per-window selection semantics.
- Split navigation-failure phase and kind values into Domain models, WebKit error classification into an Infrastructure extension, and diagnostic copy into feature-local presentation without changing retry or interruption behavior.
- Split process-recovery actions and the bounded automatic-reload policy into matching framework-neutral Browser Page Lifecycle domain files.
- Split Space foreground tone and contrast selection into matching files beside the rest of the Space branding domain while retaining SwiftUI mapping in the Design System.
- Split address intent from URL and search resolution so each framework-neutral browser address value has one matching Domain file.
- Split browser history records from URL normalization so both framework-neutral history owners have matching Domain files.
- Split collapsed-folder visibility state from folder-row presentation policy, placing each in a matching Chrome Models or Support file.
- Split memory-pressure severity, signal coalescing, and idle-page unloading into matching Browser Page Lifecycle domain owners.
- Split Settings privacy decisions from the Space-data request value, placing each in a matching shared Support or Models file.
- Split Reload, Export, and Developer Page Action values from their policies so every file-scope owner has a matching file.
- Reorganized platform address-input modifiers into matching Chrome component families, with a separate mobile keyboard policy and deterministic previews.
- Split macOS onboarding step policy, import output, reader port, and live reader into matching Support, Models, and Services files.
- Split the shared onboarding coordinator from its request value so both Application owners have matching files.
- Split the WebExtension native-messaging error and handler port into matching Infrastructure files under a dedicated NativeMessaging family.
- Decomposed private-Space Settings access into a Section, Row, identity, and unlock-control component family with fixed-ID, no-system-authentication previews.
- Verticalized shared Application onboarding into Models, Services, and Support owners for requests, progress, coordination, and welcome policy.
- Split Space deletion errors, the deletion port, the retained-view release barrier, and its weak release probe into matching vertical Application owners.
- Split Space color presentation and WebKit find conformance into dedicated extensions, and scoped favicon URL validation inside its capture owner.
- Scoped navigation-response classification inside its intent owner and split tab-placement section logic into a matching domain file.
- Split preview and showcase session composition, factories, and page-style data into matching fixture owners.
- Removed the global tab-placement maximum overload so synchronization ordering stays owned by its named value extension.
- Split tab-dismissal actions and policies out of the session lifecycle extension into matching domain files.
- Scoped manual-setup placement order and URL-title helpers inside their sole plan owner instead of file-level extensions.
- Split portable archive Space, folder, tab, archived-tab, and history records into matching file-scope model owners without changing the serialized archive contract.

### Removed

- Removed superseded standalone Archive and History sheets and unused onboarding style shims after locking coverage around their active replacements.
- Removed browser extensions from iPhone and iPad: extensions are a macOS-only feature, so mobile Settings no longer offers the Extensions destination and the mobile shell no longer builds an extension controller pool, restores or reconciles extension state, or attaches a WebExtension controller to any page. The shared subsystem still compiles into the mobile app because it is tied closely to WebKit, but nothing on mobile instantiates it, and macOS support is unchanged.

### Fixed

- Stopped the extension popup readiness check from passing before the popup document parsed, since a popup that has not rendered yet has no startup loader to inspect.
- Reported tab loading and reader-mode transitions through `tabs.onUpdated`, which previously never fired for either, and replaced a hand-written WebKit constant with the SDK's own.
- Routed `runtime.openOptionsPage()` through Crest's Space-aware handling instead of WebKit's fallback, focusing an already-open options page rather than opening a duplicate.
- Granted `activeTab` when an extension's keyboard command fires, matching Chrome and Safari; only the extension whose shortcut matches receives it.
- Required the `tabs` permission before revealing the title of a tab that has no URL.
- Reported stored website-access patterns that WebKit's parser rejects as a needs-attention error instead of silently revoking that access.
- Gave an unpacked extension a stable identity derived from its manifest key or source path, so re-importing the same folder keeps its pin, permissions, command shortcuts, and stored data instead of creating a second installation.
- Enforced each Space's "save passwords" setting on iPhone and iPad, which previously changed nothing: form detection, autofill and save prompts, and HTTP-authentication saving now all stop when the setting is off, including for a Space turned off mid-session.
- Stopped a pop-up window's password forms from being read against, and saved under, the page that opened it on both platforms.
- Fixed critical memory pressure being handled as an ordinary warning, which kept Crest from releasing the transient surfaces a warning deliberately preserves.
- Closed a policy gap that let a page re-request the exact local file Crest had loaded for it, and stopped a `target="_blank"` link on an extension page from replacing that page instead of opening a tab.
- Let iPhone and iPad suspend background tabs the way macOS does, and stopped Crest from immediately reloading a background tab whose web process the system had just reclaimed.
- Stopped Crest from crashing on the second message a native companion sends, which every real password-manager companion sends.
- Kept a native companion's messages in order when its output arrives in several pieces.
- Kept the interface responsive while sending a large message to a native companion that has stopped reading it.
- Stopped a native companion that never answers from holding a process and its pipes for the rest of the session, and reported the timeout to the extension instead.
- Stopped a native companion that quits while Crest is still sending from taking Crest down with it.
- Stopped a first iCloud sync from deleting another device's tabs, folders, and history everywhere when their Space record arrived in a later batch than the records it owns.
- Kept saved tabs and nested folders when the folder above them arrives in a later iCloud batch, and stopped deleting a folder on one device from breaking the next sync on another. Both used to fail the whole download, which lost every record that travelled with it.
- Kept the readable records in a fetched iCloud batch when one record cannot be read, instead of abandoning the whole batch after its change token had already advanced.
- Let a record written by a newer version of Crest be skipped with an update signal rather than stopping iCloud Sync on older devices.
- Stopped "Replace iCloud with This Device" from erasing cloud content in categories this device is not syncing.
- Kept a pending "is this the same iCloud account?" decision when iCloud Sync is switched off and back on.
- Prevented iCloud Sync from continuing in the background when it is switched off while a launch is still in progress.
- Stopped iCloud Sync from reporting "Up to date" after a failure while applying downloaded records.
- Left Crest's iCloud data removed when somebody deletes it from iCloud, instead of immediately uploading it all again.
- Made iCloud Sync recover on its own after an iCloud sign-in, sign-out, account switch, or a launch that could not reach iCloud.
- Stopped a stored session that cannot be read from being replaced by a new-installation session and erased. Crest now tells "nothing saved yet" apart from "saved but unreadable": the original bytes are set aside before anything can write over them, and for the rest of that launch nothing removes a Space's history or sweeps its icons.
- Let a session written by a newer or older build keep loading when it names a Space tint, tab placement, tab icon mode, or Space access policy this build has never heard of, instead of failing the whole session and looking like a new installation. A stored access restriction that cannot be read now keeps the Space guarded rather than opening it.
- Made an import that lands real Spaces or tabs finish setting Crest up, so imported Spaces sync to iCloud instead of being held back and left replaceable by cloud content.
- Stopped a reviewed import from committing a blank Space name or symbol; both now fall back exactly as they do in manual setup, including for a newly created Space.
- Restored constant-cost favicon identity so showing a tab list no longer hashes and compares every visible icon's image data on each screen update, while keeping two different icons from ever being mistaken for each other.
- Capped the stored per-window restoration records, so repeatedly force-quitting on iPhone or iPad no longer leaves a permanent record behind for every window that never came back.
- Hosted Dark Reader’s signed MV3 background bundle in WebKit’s document environment so its popup leaves the startup loader promptly while preserving each Space’s existing extension identity, storage, and enabled state.
- Prevented XCTest app hosts from constructing Crest's installed browser UI, keeping window preferences and feature-level `@AppStorage` outside the user's profile during unit tests.
- Allowed isolated WebExtension contexts to access only their own nonpersistent data so content scripts and native companion ports keep working without creating persistent extension records.
- Composed launch-isolated system-credential boundaries for onboarding and mobile launches, preventing Safe Storage and System Passwords write-through without changing ordinary installed sessions.
- Kept XCTest, fixture, forced onboarding, setup, and credential-test launches on in-memory session, sync, onboarding, shortcut, link, and filter-list owners with nonpersistent WebKit stores, preventing sample Spaces from entering the installed profile.
- Locked existing Space IDs to their persisted WebKit profile UUIDs across add, reorder, manual-setup, reviewed-import, and Cloud materialization paths; only explicit Space deletion can remove that profile's website data.
- Made onboarding and manual-setup accessibility identifiers stable, unique, nonlocalized, and nonempty across repeated Space and tab controls.
- Replaced the Chrome Web Store verifier's forced invariant operations with explicit header rejection and named invariant checks without changing CRX3 identity or signature validation.
- Aligned repository structure checks with the current Application and Infrastructure owners and kept release-soak reporting compatible with Xcode's Python 3.9 runtime.

Crest releases before 0.3.0 predate this changelog. Their development history remains available in Git.

[Unreleased]: https://github.com/pauljoda/Crest/compare/v0.8.1...HEAD
[0.8.1]: https://github.com/pauljoda/Crest/compare/v0.8.0...v0.8.1
[0.8.0]: https://github.com/pauljoda/Crest/compare/v0.7.2...v0.8.0
[0.7.0]: https://github.com/pauljoda/Crest/compare/v0.6.33...v0.7.0
[0.6.33]: https://github.com/pauljoda/Crest/compare/v0.6.8...v0.6.33
[0.6.3]: https://github.com/pauljoda/Crest/compare/v0.5.7...v0.6.3
[0.5.7]: https://github.com/pauljoda/Crest/releases/tag/v0.5.7
[0.4.0]: https://github.com/pauljoda/Crest/releases/tag/v0.4.0
[0.3.0]: https://github.com/pauljoda/Crest/releases/tag/v0.3.0
