# Minimal Palette: independent implementation and reliability review

September 6, 2026. This review is independent of implementation. No automated tests were created or run. The initial pass is source inspection; runtime observations and rechecks will be recorded separately below.

## Initial assessment

The existing native clipboard support is worth retaining: bounded native text/HTML/RTF/image/file URL representations, sensitive pasteboard markers, foreground/deactivation source attribution, preflight missing-file checks, suppression of self-restores, per-source deduplication, stable pins, encrypted atomic history writes, and explicit failure feedback. These solve everyday clipboard problems directly.

The launcher scaffolding does not earn its place in a clipboard utility. Commands, extensions, command dispatch/history/notifications, two search implementations, Rust indexing, process execution, platform abstraction contracts, and unsupported alternate platform shells should be removed. Native AppKit can own the small window, keyboard behavior, capture and persistence without React, WebKit, a bundled Node runtime or a service protocol. The dependency reduction is valuable only if old history remains readable.

### Required improvement

**P1 — Unreadable settings silently disable privacy preferences and can prune history.** `JsonSettingsStore.load()` catches every read/parse failure and returns enabled capture, no excluded apps, 200 items and 30 days. A temporarily unreadable or malformed existing settings file can therefore resume recording a paused/excluded application and prune history with different limits. Default only for a missing profile. Existing unreadable settings should produce an actionable error with capture disabled and no pruning until readable settings are available.

### Migration requirements

- Preserve the existing `clipboard.json` version-1 AES-256-GCM envelope, including `iv`, `authTag`, and `ciphertext`. CryptoKit must consume the separate nonce/tag/ciphertext directly. Preserve the existing Keychain service `sh.palette.Desktop.clipboard` and account `default`.
- Keep item IDs, source app IDs/names, timestamps, pins and native representations. Existing rich and file clips must remain reusable; retain the narrow old plain-text/file fallback where representations are absent.
- Preserve `settings.json`'s `clipboard` wrapper and existing enabled/retention/capacity/exclusion values. Removing a capacity control from the interface is not permission to reset its persisted value and delete old clips. Making sensitive-marker/content protection unconditional is a sensible privacy improvement.
- Treat unavailable or invalid keys, malformed encrypted history and unreadable settings as errors. Never overwrite unreadable history with an empty store. A review profile's invalid/missing key must not be replaced when encrypted history already exists.
- Serialize mutations under one clear owner, publish the new snapshot only after a successful atomic write, and keep failures visible without logging clipboard contents. Prevent quitting from discarding a queued capture or settings write.
- Preserve native paste preflight and a working copy path when Accessibility permission is absent. Do not claim paste succeeded merely because the shortcut was posted; verify actual destination content through native interaction.

The source app remains a foreground/deactivation inference because macOS has no authoritative clipboard writer identity. The documentation should retain this limitation; background writes can evade an app exclusion through misattribution. Do not build an elaborate attribution fallback framework.

## Runtime and focused recheck

Pending the replacement native build. The reviewer will independently operate a synthetic isolated profile after the coordinator releases native UI control. Source approval alone is not a runtime pass.

## Native store source pass

The first `ClipboardStore.swift` implementation preserves the envelope and item schema, reuses the existing Keychain identity, rejects missing review keys when history exists, and publishes state after successful queued writes. The fail-closed settings/history load addresses the initial P1. The existing production settings file's shape was checked without reading clipboard contents and matches the new wrapper and fields.

**P2 — Retention currently runs only on capture.** The first native implementation invokes `pruned()` from `capture()` alone. A paused profile keeps expired entries indefinitely; changing retention does not update history, and unpinning an expired entry leaves it visible. Apply the same simple queued pruning on load, retention change and unpin. Ensure a last pending write finishes before application termination. These are source findings pending the coordinator's next revision and a focused runtime check.

## Native replacement focused source recheck

Confirmed retention is now queued after load and policy save and applied during pin/unpin. `applicationWillTerminate` captures a pending pasteboard change and waits for the serial write queue, addressing the prior capture-write termination concern. Existing AES-GCM envelope and clipboard schema compatibility, Keychain identity, native format restore, per-source deduplication, stable IDs/pins, and fail-closed loading remain intact. Ordinary settings failures retain the previously active policy. Native image and missing-file guards remain small and explicit.

Two concrete keyboard/native-behavior findings were returned for improvement:

- **P2 — Keyboard pin can target a stale clicked row.** `actionClip` always prefers `table.clickedRow`, including the `⌘P` path. Click row A, arrow-select B, then pin: the action can still use A. Keyboard actions should use selected row; only a context-menu action should prefer clicked row.
- **P2 — Preview text selection loses native Copy behavior.** The global `⌘C` handler excludes only the search editor. When a user selects part of the selectable preview text, it restores the full clipboard item and dismisses Palette instead of letting NSTextView copy the selection. Leave native text-copy handling intact when preview text has a selection.

Arrow-key modifier handling also needs a native check: `.isEmpty` is used after retaining `.numericPad` and `.function`, flags that native arrow events can carry. This is an inspection concern rather than an independently reproduced failure.

Native verification is still pending coordinated access; the coordinator reports targeted app interactions while the foreground application is `loginwindow`, so those observations cannot establish ordinary foreground source attribution or direct paste behavior.

## Independent native runtime verification and closure

The reviewer independently controlled the replacement AppKit build through CUA using `/tmp/palette-native-migration`, a coordinator-prepared clone of an older Node-encrypted review profile. Capture stayed paused throughout. No automated tests or synthetic event scripts were created or run.

Observed directly:

- All four imported clips were usable in the native history: rich text, ordinary text, file reference and pinned 1536×1024 image. Row titles used the compact panel's available width, and the image retained its source and pin.
- Clicking rich-text row A, then Down and `⌘P`, pinned selected row B. The clicked-row/keyboard-pin finding is closed by actual interaction. Native arrow navigation worked after giving the list focus with a coordinate click. An accessibility-only row click selected a row without focusing the list; that tooling distinction is not evidence of a keyboard regression.
- Selecting `ordinary body.` in the preview and pressing `⌘C` kept Palette open. Pasting into a new TextEdit document produced only `ordinary body.`. Native selected-text Copy is restored.
- The explicit Copy button dismissed Palette. Pasting the legacy rich clip into TextEdit restored both lines and the bold first line, confirmed by accessibility text and a screenshot.
- The legacy pinned image copied into TextEdit as a native attached image, confirmed by accessibility and a screenshot. Preview CUA initialization timed out twice, so this is an image restore into TextEdit, not a Preview round-trip claim.
- Paste with no remembered destination displayed `No destination app. Use Copy, then paste where you need it.` and left a usable panel. This verifies that failure path, not successful return-to-app paste or the Accessibility-denied path.
- The Settings app picker accepted `/System/Applications/TextEdit.app`; the exclusion menu then contained Finder and TextEdit. Save kept capture paused and 30-day retention. Normal `⌘Q`, followed by an explicit executable relaunch with the same review arguments, preserved all four clips, both pins, pause, retention and both exclusions. Exclusion persistence is verified; enforcement with a genuinely foreground excluded app is not established by this pass.
- A nonexistent query produced zero rows, disabled Copy/Paste, and only the correct no-matches message in both accessibility and screenshot. Clearing search restored all four rows. No false empty-state accessibility text remained.

Source recheck confirms distinct context-menu and keyboard pin targets, native preview selection Copy, and filtering modifier flags to actual command/control/option/shift keys. The final whitespace-trim change retains the earlier JWT privacy classifier's behavior. Remembering shortcut registration failure prevents a successful initial load from erasing it. Flushing clipboard capture with the outgoing foreground app before activating Palette is a straightforward improvement for rapid copy→summon; the coordinator will verify that runtime sequence separately.

One narrow guard was requested for the last change: an invalid review launch can show the panel before `store` exists, so capture should require an initialized store or a disabled initial policy. No broader recovery framework is needed.

The implementation/reliability review supports this replacement with these explicit limits. This reviewer did not independently establish ordinary multi-app source attribution, excluded-app enforcement, native file pasting, rapid capture→summon, or successful direct paste. Those remain coordinator verification work. UI control was returned with the isolated profile paused and unfiltered.

Final guard recheck: `capture()` begins with `guard let store else { return }`, so invalid review startup cannot dereference an absent store. That narrow concern is closed. No unresolved substantive finding remains in this review's inspected and exercised scope.

## Final failure-presentation source closure

Focused source recheck of the store availability callback, native menu validation and missing-file naming found no new substantive issue. The serial store snapshots `ready` together with clips/policy/error before delivering to main. The host distinguishes loading, unavailable and successfully empty history, suppresses misleading counts while unavailable, and disables capture/settings actions through `NSMenuItemValidation`; `openSettings` also checks availability. Save failures keep the already loaded history available, which preserves a useful copy path instead of treating every write failure as an unreadable store.

Missing-file validation still runs before clearing the current pasteboard and still uses saved native file URLs for existence checks. Its error now obtains a human-readable name from saved display content when a stale native file reference resolves without a usable path. The coordinator reports native confirmation of the filename error and that subsequent TextEdit paste retained the previous clipboard. These are coordinator observations, separate from this source recheck. The coordinator is repeating invalid-settings presentation on the final build; no additional automated tests or UI actions were performed in this pass.

## Compact hover interface source review

The user's subsequent direction removes primary Copy/Paste controls and messages and makes hovering plus `⌘C` the direct copy interaction. The new table retains a pointer position in window coordinates and converts it when copying, so scrolling changes the row under the pointer correctly. Hover priority for `⌘C` is intentional even while search is focused; outside a hovered row the native search/selected-preview Copy path remains intact. The persistent store's privacy, migration and fail-closed behavior remain unchanged; unavailable history still disables settings/capture mutation controls and exposes failure through More → Details.

Two focused improvements requested before closure:

- **P2 — Search spaces are intercepted by hover preview.** The Space handler accepts a hovered row even while editing the search field. A multiword query typed with the pointer resting on a row therefore opens preview instead of inserting a space. Preserve native Space typing in search; the user's requested hover override is specifically `⌘C`.
- **P2 — Background success can erase an unseen failure.** Every successful store callback calls `report(nil)` when no shortcut error exists. An oversized capture failure can therefore disappear after another successful background copy before the user opens Details. Keep the existing issue until acknowledged, without adding a recovery framework. The store's unchanged-state guard already avoids an unnecessary no-op prune clearing it.

This pass is source inspection only; the usability reviewer is independently exercising the compact build.

### Compact-interface focused source closure

Confirmed Space now requires that search is not being edited; only `⌘C` retains the explicit hover override. Successful store callbacks retain the existing issue, successful Copy no longer clears it, and Details acknowledgement clears an ordinary issue only when history is available. An unreadable-store issue stays discoverable. These focused changes close both findings without adding new state layers. Runtime hover/search checks are assigned to the independent usability reviewer; this closure makes no additional native-interaction claim.

### Final capture-capacity source closure

The coordinator identified that a capacity entirely occupied by pinned clips could prune away a new unpinned copy and return an unchanged history silently. Confirmed the final capture path now requires its stable captured ID to survive pruning and throws a history-limits error otherwise. The existing serial mutation error path preserves saved memory/ciphertext and exposes the issue through Details. Paused/excluded captures still return without an error, and a recopy of an existing pinned item retains its ID/pin and survives. The same guard covers zero-retention rejection. No new state layer, automated test or runtime claim was added in this focused recheck. Source closure is approved.

## Native NSMenu lifecycle review

Reviewed the subsequent NSMenu implementation without editing code, running tests or taking native UI control. One custom clipboard content view, a real separator and native Quit item give menu tracking to AppKit. The timer is also registered in common run-loop modes. `menuWillOpen` flushes a pending copy using the outgoing foreground app, and paste retains a local destination before `menuDidClose` clears the remembered app. Those ownership decisions are consistent.

Two concrete issues were returned for correction:

- **P2 — Paste failure reopens a blocking menu from a main-dispatch callback.** The focus-failure closure invokes `show()` before `report()`. Since `NSMenu.popUp` tracks synchronously, its failure detail is not installed until that menu closes. It also recreates the main-dispatch-owned nested menu loop that the startup change deliberately avoided. Record the failure before scheduling menu presentation through `RunLoop.main.perform`.
- **P1 — Quit still blocks behind an unfinished Keychain lookup.** The coordinator's `/tmp/palette-before-menu.sample` shows the main thread waiting in `ClipboardStore.finishWrites` while the history queue is blocked in `SecItemCopyMatching`. The current unconditional termination drain preserves that problem. Only drain accepted writes once the main-thread availability snapshot confirms history loaded successfully. Before readiness, capture and mutation controls are disabled, so quitting need not wait for a Keychain read. Keep the existing write drain for a ready store.

Menu-window keyboard delivery, editable-search behavior, hover tracking and callback publication while a menu is open require the coordinator's current native check; this source pass does not claim them verified.

### Native-menu source closure

Confirmed termination now drains captures/writes only after a successful history load, so an unresolved startup Keychain read cannot block Quit. Confirmed paste focus failure records its message first and schedules the reopening through the main run loop rather than entering synchronous menu tracking from the dispatch callback. Both findings are closed by focused source inspection.

The coordinator's native sample contains `NSMenuTrackingSession` beneath AppKit's menu popup, establishing that this build uses native menu tracking. CUA accessibility calls currently time out against the menu-only app. That tool limitation leaves interactive keyboard/hover/copy verification of this latest menu revision incomplete; the sample alone is not a substitute for those checks.

## Process lifetime replaces pause state

Independent source review approved removing enabled from the decoded clipboard policy and deleting toggle persistence. Legacy enabled:false is ignored without a settings/history migration. Host capture remains gated by historyAvailable==true; store mutations still require ready and a key, and exclusions, strict settings/history loading, and ready-only shutdown draining remain intact. No hidden pause-state or history-loss blocker remained.

Coordinator native lifecycle evidence used a disposable legacy-disabled profile: marker A copied before Quit was saved, B copied while quit was absent, and C copied after reopening was saved. The old settings content remained unchanged. This is coordinator runtime evidence, separate from the independent source review; the source-attribution limitation is recorded in VERIFICATION.md.
