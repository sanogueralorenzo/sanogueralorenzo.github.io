# Clipboard workflow review

## Baseline — September 6, 2026

Independent source review of `src/ui/PaletteApp.tsx`, `src/ui/webview-bridge.ts`, `src/ui/styles.css`, and `native/macos/PaletteHost.swift`, compared with `development/GOAL.md` and `clipboard-target.png`. No app control or automated tests performed. Findings below are verified implementation gaps; runtime effects and timing remain to be checked manually.

- **High — direct clipboard shortcut is advertised but unregistered.** The menu tooltip says ⌘⇧V, but has an empty key equivalent; the single registered Carbon hotkey calls `toggleLauncher`, which opens the launcher. Register a dedicated clipboard action and report conflicts truthfully. (`PaletteHost.swift:154`, `:442–478`.)
- **High — the primary retrieval action cannot complete the task.** Enter and row clicks only copy and leave the panel open. The bridge has no paste action. Native dismissal already remembers the previous app, which can support return-to-app paste with explicit permission failure and copy fallback. (`PaletteApp.tsx:82–104`; `PaletteHost.swift:167–187`.)
- **High — history can be stale on reopen, and queries can show the wrong response.** Open callbacks reset only view/query; reopening an already selected clipboard view with an empty query does not trigger its fetch effect. There is no capture subscription. Search promises are unguarded, so older responses can overwrite newer searches. Add explicit refresh on open and ignore obsolete responses. (`PaletteApp.tsx:35–54`.)
- **High — keyboard selection becomes invisible in longer histories.** Arrow keys change an index without scrolling the selected row into view. Highlighted selection has no accessible selected/active-descendant semantics. The complete result section is a live region, potentially announcing excessive content. Keep selection visible and expose a focused result model without announcing the entire history. (`PaletteApp.tsx:82–85`, `:124–125`; `styles.css:.palette-results`.)
- **High — keyboard commands stop working outside search.** The handler is attached only to the input. Tabbing to capture or a row loses Escape and list navigation; input Escape takes two presses to dismiss clipboard, contrary to the concept's “esc Close”. Keep global dismissal/search commands available across controls while preserving native text editing and form controls. (`PaletteApp.tsx:82–95`, `:122–125`.)
- **High — app-based retrieval and item management are absent.** Only text search and a flat list are presented; no source names/icons, app/Pinned/type filters, rich preview, pin/unpin/delete actions, settings controls, or shortcut discovery. Rows immediately mutate the system clipboard on click, preventing safe inspection. Separate selection/preview from explicit copy/paste and expose parallel mouse and keyboard actions. (`PaletteApp.tsx:119–128`.)
- **Medium — result selection may refer to the wrong item after refresh.** Selection is an index reset on length changes; content replacement at the same length can silently move it to another item. Preserve identity when present and intentionally select the nearest remaining item after deletion. (`PaletteApp.tsx:55`.)
- **Medium — failure/empty states are misleading.** An absent optional copy method reports success because only `false` is rejected; initial load, empty storage, and zero search matches all say “No clipboard items”. Add capability-aware actions, loading/no-match guidance, and truthful pending/success/failure feedback. (`PaletteApp.tsx:98–104`, `:126`.)

## Final manual acceptance scenarios

Use an isolated review profile and synthetic clipboard content. Record actual final-build results, not inferred passes; keep personal contents out of captures.

1. From an editable destination in two different apps, invoke the dedicated clipboard shortcut, combine source/type/query filters, arrow to a result, and press Enter. Verify exact destination, actual insertion, panel dismissal, and elapsed time. Repeat with at least five known targets in a history of 100+ entries; report per-task times against the five-second goal.
2. Navigate beyond the visible results and back using only keys. Verify selected row stays visible, preview follows, and assistive selection names are meaningful. Tab through app filters, type filters, preview actions, settings, and capture toggle; verify visible focus, global Escape, and search shortcut in each region.
3. Copy rather than paste, then return to the destination and manually paste. Repeat with Accessibility permission denied and unavailable/terminated previous app; ensure Palette explains the outcome and never claims insertion occurred.
4. Copy a new item while Palette is closed, reopen the unchanged view/query, and verify fresh history. Enter and clear queries quickly, including zero matches; ensure late responses cannot replace the current result set.
5. Pin and unpin from keyboard and mouse; delete selected and final results; switch Pinned/app/type filters. Verify focus and selection remain predictable, selection never causes copy, and empty states provide a way forward.
6. Inspect short/long text, multiline code, links, images, and multiple-file items. Confirm scrolling and text selection do not conflict with navigation, and copy uses the intended item rather than silently overwriting selected preview/search text.
7. Pause/resume and edit retention/capacity/exclusions entirely with keys. Verify changes and validation are understandable, cancelled edits are discarded, and focus returns to the invoking control when settings close.
8. Restart after capture and pinning; verify app identity, filters, pins, policy, and contents persist. Repeat a known item from another source and confirm app-specific retrieval and pinned identity remain intact.

Final runtime review: pending implementation and a coordinated review slot.

## Iteration 1 — independent source review

Reviewed the new `ClipboardView.tsx`/`clipboard.css`, host shortcut/paste paths, and parent view lifecycle. The first pass addresses the baseline's missing app/type/Pinned controls, rich preview, explicit actions, direct hotkey, clipboard remount on open, scoped keyboard handler, identity-based row selection, scroll visibility, and copy capability errors. These are source-observed improvements; no runtime acceptance is claimed.

Remaining substantive findings:

- **High — normal query editing can delete stored clips.** `onKeyDown` handles Command+Backspace before checking its target (`ClipboardView.tsx:146`). In macOS search this normally deletes text to the start of the line; it instead calls `remove()`, potentially permanently deleting a pinned clip. Do not bind destructive item actions while an editable input has focus; restrict deletion to list/actions or use a nonconflicting explicit shortcut. Verify typing a query, placing the caret mid-word, and invoking normal macOS deletion.
- **High — IME confirmation can paste and dismiss.** The search/list handler has no composition guard before Enter (`ClipboardView.tsx:133–155`). Confirming Japanese/Chinese composition can invoke direct paste. Ignore clipboard command keys during composition, including the WebKit composition-ending Enter case. Check actual IME composition manually.
- **High — closing actions can strand keyboard focus.** `perform()` removes the actions popover (`:93–97`), including its autofocus button, without moving focus back to a connected control. Command+K toggling it closed has the same issue. Focus can fall to the document body, outside the shell handler; subsequent Escape/search/navigation then fail. Restore a connected invoking control or list/search focus when closing, including after success/failure. Manually open actions and copy, pin, delete, close via Command+K, and fail paste; immediately use Escape/Command+F/arrows without clicking.
- **Medium — the initially previewed item is not actually retained by identity.** Initial/filter-reset `selectedId` remains undefined (`:89–90`), so every poll falls back to the newest row. A new captured item can replace the preview and Enter target while the user reads the initial item. Commit the initial selected identity when loading/filtering; retain it while present. Validate a background clipboard change while previewing without arrow/click interaction.
- **Medium — filter shortcuts override native word movement.** Option+Left/Right switches content type even inside the search field (`:150–151`), stealing macOS word-wise caret movement; Shift+Option variants also change filters instead of extending text selection. Use a modifier combination that preserves text editing or scope these keys to a noneditable region, and update help.
- **Medium — failed target focus may reopen without its explanation.** `PaletteHost.swift:456–457` calls `showLauncher(.clipboard)` before resolving the original paste request. That callback increments `clipboardSession` and remounts `ClipboardView`, while the error belongs to the old view's promise/state. Preserve the current session when reopening after failure or pass a fresh host error to the mounted view. Force activation failure and verify the reopened panel visibly explains the copy fallback.
- **Medium — search's active-result accessibility is incomplete.** The search input supplies `aria-activedescendant` without a combobox role/state (`ClipboardView.tsx:168`); its implicit textbox semantics do not define the advertised result interaction. Use a correctly labelled expanded combobox associated with the listbox, then manually confirm the selected result changes are announced by VoiceOver while focus stays in search.

Final review remains pending fixes and actual native/manual evidence.

## Iteration 2 — independent source follow-up

Verified in source: Command+Backspace now preserves editor deletion; ordinary composing events are ignored; initial row identity is committed; actions use a native modal dialog; operations request search focus; native paste focus failure reopens the existing view rather than remounting it. The new explicit hidden event avoids dependence on WKWebView's unreliable `document.hidden`. Parent reports the hidden-state problem was observed in runtime; this reviewer did not control the app.

Substantive remaining fixes:

- **Medium — history polling does not resume after paste focus failure.** The refresh effect sets its local `visible = false` on `paletteHidden` and has no matching visible/resume event. `sendPaste` failure now brings the same panel/view back, so that view remains permanently paused. Add and handle an explicit shown event on this recovery path; verify new captures appear after recovery without closing/reopening again.
- **Medium — Enter cannot activate the no-match “Clear filters” button.** `target.closest('[role="listbox"]')` includes this nested button, so the result keyboard branch prevents default Enter, attempts to paste the nonexistent selection, and does nothing. Restrict result navigation/activation to the listbox itself or ignore nested interactive controls. Verify keyboard focus on Clear filters, then Enter restores results.
- **Medium — Option+Left/Right still steals native search word navigation and Shift+Option selection.** This iteration retains the earlier finding. Preserve editor shortcuts and expose filter switching through a nonconflicting combination or noneditable focus context.
- **Medium — search still lacks its combobox role/state.** `aria-activedescendant` is still attached to the implicit textbox. The correctly labelled listbox helps when it owns focus; add proper search-result combobox semantics and verify selected-result announcements with VoiceOver.

Manual follow-up required: modal focus after successful/failed actions and Command+K close. `input.focus()` currently runs before React unmounts the open modal, while background content is inert; source alone cannot establish that WKWebView leaves the intended control focused. Close the dialog first or schedule explicit focus after unmount if actual behavior fails. Confirm composition-ending Enter with a native IME, since an ordinary `isComposing` guard alone is not final runtime evidence.

No automated tests, UI control, or source edits performed. Final acceptance remains pending final-build native evidence.

## Final candidate — source assessment

Independently re-read the current view and native focus/paste paths. The iteration 2 polling-resume, Clear filters Enter, and combobox-semantic findings are fixed in source. Native event-allocation failure now resolves with copy-fallback guidance, and focus failure restores the same panel and dispatches `paletteShown`, preserving its error recipient and restarting refresh. Editor-safe deletion and stable initial selection remain present.

**Remaining concrete medium finding:** changing filter cycling to Option+Shift+arrows does not fully preserve native text editing: Option+Shift+Left/Right extends selection by word in the search input, and the global handler still prevents that behavior. Exclude editable targets from these filter branches or use a nonconflicting combination including Command; keep the help text aligned. Verify ordinary Option navigation and Option+Shift text selection in search, then filter cycling with result-list focus.

**Runtime acceptance still required:** independently source-reviewing a final candidate does not establish five-second retrieval, actual destination insertion, VoiceOver announcements, composition-ending Enter, or focus restoration after closing modal actions. In particular, `perform()` currently calls `input.focus()` before React removes the modal (while its background is inert); the parent has been asked to verify Copy/pin/delete from Actions followed immediately by typing and Escape. If focus does not return to a useful connected control, close the modal before focus restoration or schedule focus after unmount.

No additional source blockers identified in the reviewed scope. No automated tests, native app control, or implementation edits performed by this reviewer.

## Final source follow-up — findings resolved

Verified the final focused corrections in `ClipboardView.tsx`: both Option+Shift filter branches now exclude input, textarea, and contenteditable targets, preserving horizontal word-selection editing; shortcut help explains list focus. Both native HTML dialogs explicitly close during cleanup, and the parent view restores search focus in an effect after actions/settings close. That addresses the earlier pre-unmount focus-ordering concern in source.

No remaining concrete blocker found in these reviewed changes. This is source sign-off for the keyboard/focus fixes, not a claim that the entire goal's manual acceptance matrix passed. The parent is performing the final native action-to-typing check; actual paste destinations, timed retrieval, VoiceOver, and native IME behavior require the recorded runtime evidence. No automated tests or UI control were performed by this reviewer.

## Large-history iteration — virtualization review

Independently reviewed the uncommitted windowed result list. Fixed CSS row height (75px) agrees with virtual offsets; spacer nodes are hidden from assistive technology; rendered options expose one-based `aria-posinset` and the full filtered `aria-setsize`; overscan and ResizeObserver provide bounded row rendering across window sizes. Existing selection is still stored by item identity.

**Medium regression:** the selected-row scroll effect now depends on the entire `visible` array. Every successful two-second poll replaces items and recreates that array even when its contents are unchanged. A user scrolling away from the selected row to browse older history is therefore snapped back to the selected row at the next poll. Depend on the selected identity/index and relevant actual geometry instead of the whole result-array reference; retain manual browsing scroll when neither selection nor its position changed. Manually scroll midway through 500+ entries without clicking, wait longer than one poll, and verify position remains stable; then use arrows to verify explicit selection navigation still scrolls correctly.

The parent is adding list-focused Home/End/PageUp/PageDown and suppressing active-descendant IDs for unrendered options; those announced follow-up changes were not yet present in the source read and need final inspection. Current unrendered selected options otherwise leave a dangling active-descendant reference until keyboard selection causes scroll/render. Validate first/last/page navigation, filtering a deeply scrolled history to a handful of matches, deleting near the last row, and VoiceOver option position announcements on the final build.

No automated tests, runtime controls, or implementation edits performed in this review.

### Virtualization follow-up

Confirmed that selection scrolling now depends on selected ID and filter inputs, so fresh polling arrays and newly inserted items no longer trigger it. Both search and list omit active-descendant when the selected option is unrendered. Home/End/PageUp/PageDown are implemented only when the result list owns focus, preserving those keys in search.

**Medium remaining navigation edge:** Home/End only change selected ID and rely on the selection effect to scroll. If the requested boundary item is already selected but manually scrolled offscreen, its unchanged ID does not trigger the effect: open history with its first item selected, scroll far down without selecting another row, then press Home; the viewport stays down. End has the equivalent case. Explicit navigation should ensure its requested row is visible even when selection identity does not change, while passive refresh remains non-scrolling. Verify this alongside the parent’s unchanged-poll scroll check.

### Virtualization source closure

Verified the final `revealRow(index)` helper is used both by selection changes and explicit `navigate()`. Home/End now route through navigation and reveal the requested boundary even when its ID is unchanged; page and arrow navigation share that behavior. Passive refresh still does not depend on the new items-array reference. Conditional active-descendant and complete option positions remain present. Both virtualization findings are resolved in source; no additional concrete blocker found in this focused recheck. Final large-history performance, scroll stability, and keyboard behavior must be confirmed by the parent's native runtime evidence. No automated tests or UI control performed.

## Native editing follow-up — proposed Edit menu

Parent runtime evidence reports that 1,000-item Home/End and manual scrolling across polls work, and a synthetic search-and-copy action completed in 978ms. Parent also observed Command+A appending instead of replacing search text and a settings-number-field selection issue. Source inspection confirms the native host currently has no `NSApp.mainMenu` or standard Edit responder-chain actions; adding these is a reasonable targeted correction.

The proposed Copy menu equivalent introduces an interaction risk with React's custom Command+C: native menu dispatch may consume the key before the DOM handler or perform an unintended second copy. Actual AppKit/WKWebView ordering is not established by this source review. Keep standard text Copy targeted through the responder chain and do not manually dispatch both copy paths. Validate final native behavior with (1) no selected text in search: Command+C restores the selected historical item; (2) selected search/preview text: Command+C copies only that text; (3) settings fields: Select All/Cut/Copy/Paste/Undo/Redo edit the field without restoring a history item. If history Copy stops working, make one explicit copy owner choose between selection copy and history restore rather than layering another unconditional handler.

This review advises on the planned native menu; it does not mark that unimplemented change or its runtime behavior passed. No automated tests or UI control performed.

### Native editing closure — coordinator runtime evidence

Independently inspected the implemented `configureApplicationMenu()` and its launch call. Undo/Redo/Cut/Copy/Paste/Select All use standard selectors with nil targets, allowing the focused responder to own editing; there is no added unconditional copy dispatch alongside React.

The coordinating agent reports these checks passed in the running native app, using synthetic review content:

- Command+A visibly selected the entire search query; typing `0999` replaced it.
- With no query text selected, Command+C restored historical `Release note 0999`, verified by pasting into a scratch TextEdit document.
- With the complete query selected, Command+C copied only `0999`, verified in the scratch destination.
- In the settings textarea, Select All/Cut cleared the field, Paste restored `review.excluded`, Undo cleared it, and Shift+Command+Z restored it. The settings draft was cancelled.
- With 1,000 clips, native End/Home navigation worked. Space scrolling with list focus preserved the preview and viewport across polling refreshes. The earlier coordinator-measured synthetic search `0999` plus Copy completed in 978ms.

These observations address the native Edit-menu interaction risk and the focused large-history navigation checks. They are explicitly coordinator-supplied runtime evidence, not UI actions independently performed by this reviewer, and a single measured lookup does not establish every retrieval scenario's five-second target. No additional blocker identified by this source follow-up; no automated tests were created or run.
