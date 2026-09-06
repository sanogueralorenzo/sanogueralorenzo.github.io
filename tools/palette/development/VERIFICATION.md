# Native refinement verification — September 6, 2026

This supersedes the older launcher verification. No automated tests were created or run. Builds, source inspection, and deliberate native app interaction were used. Historical screenshots elsewhere in this directory describe the earlier implementation, not this refinement.

## Implementation removed

- Launcher, app/file search, process commands, local extensions, command registry and shortcuts, run history, notifications, and associated automated test harnesses.
- React/WebView presentation, Node daemon and bundled runtime, Rust indexer, IPC/contracts/services, package manifests/lockfile, and incomplete Windows/Linux hosts.
- Permanent sidebar, type filters, command palette, separate preview column, implementation-level settings, and repeated recovery/fallback paths.

The application now consists of one native AppKit process with explicit clipboard storage, pasteboard support, a corner panel, and a settings sheet. No third-party dependencies or downloaded runtime. The overlapping-squares app/menu/panel identity is retained.

## Measured build

The earlier bundle was 107 MB; the native build is about 824 KB (reported by `du -sh`, architecture-specific). The final primary panel is 340×300 instead of 1040×680. User sizing follow-ups reduced the first native 420×550 and 380×380 iterations further. Rows are now single-line, 30px high. Copy/Paste buttons, counts, footer hints, empty states, and status banners were removed. Space replaces the list with a full-area preview. Hover plus ⌘C restores a clip immediately. `scripts/build-macos-app.sh` compiles successfully, validates Info.plist, and ad-hoc signs the app. No tests were run.

## Legacy history

An isolated clone of `build/review-profile` was opened as `/tmp/palette-native-migration` using the new native executable. Its Node-written version-1 AES-GCM envelope, review key, four clipboard entries, pinned image, source apps, RTF data, file references, disabled capture, retention, capacity, and Finder exclusion load without an export or replacement key. The original review profile remains untouched. Production files were not used for screenshots or evidence.

## Independent reviewer iterations

The usability reviewer inspected the installed baseline and the new native panel. They verified app filtering, query replacement, Down selection, Space text/image previews, settings layout, and sheet Escape. Their image-preview finding (intrinsic image size widening the panel) was fixed and rechecked at 420×550, including after closing the preview. Lavender selection was restored. Row-width and hidden empty-state accessibility findings received focused fixes.

The implementation/reliability reviewer independently challenged the service architecture and storage migration. Their findings resulted in fail-closed settings/history loading, retention on load/settings/unpin/open, normal-quit write completion, selected-row keyboard pinning, and preservation of native Copy for selected preview text. Later user steering moved failure details out of the primary panel and into an on-demand More menu action.

See [usability review](reviews/minimal-usability.md) and [reliability review](reviews/minimal-reliability.md) for observations, focused rechecks, and remaining limitations.

## Native interaction evidence

Fresh final-build captures were made through native Copy in TextEdit (RTF), Microsoft Edge (HTML and address-bar URL), Preview (PNG), and Finder (file URL). The saved native envelope was inspected without logging payloads: RTF, HTML, PNG, and file-URL representations are retained alongside plain text where the source supplied it. Both rapid TextEdit Copy→summon and Preview Copy→summon saved their items after the pre-activation flush fix.

The Finder file was located with Palette search, restored with Copy, and pasted into a separate Finder folder. Finder displayed the new file and the sample contents matched. The independent reviewer separately restored the migrated RTF into TextEdit with its bold header and restored the migrated image as a native image attachment.

Native automation targets background application windows without necessarily activating them. The source fields therefore correctly reflect the macOS-reported foreground processes (ChatGPT/Steam Helper during final automation), not necessarily the windows targeted by the tool. Those copies establish capture/format behavior, not ordinary foreground attribution. An optional manual foreground copy was requested from the user; successful direct paste and authoritative foreground exclusion behavior must not be claimed from these background-window checks.

The final privacy check captured an ordinary TextEdit control phrase, then skipped a synthetic `password:` string (zero search matches, prior history unchanged). Pause was enabled through the native More menu; a subsequent ordinary copy was absent from history. Native file references continued working after a file move. Removing the disposable source file produced an explicit missing-file error before clipboard clearing; a confusing unresolved-reference filename was replaced with the saved original filename and rechecked.

An invalid-settings profile displayed a failure without modifying its ciphertext (SHA-256 remained `3abe149551ad252bb498d1e0e63e567fabaaab233cf2397229ed93d83d9ae398`). The final minimal interface keeps these details behind More and disables settings/capture mutations while storage is unavailable. The underlying fail-closed storage behavior is unchanged. After a missing-file Copy failed, native paste into a new TextEdit document still produced the previously copied control phrase.

Final review limitations: native background-window automation does not establish true foreground attribution or successful paste into the intended foreground app. The user was asked for an optional manual foreground copy. Exclusion selection and persistence are verified; exclusion enforcement against a real foreground source remains unverified. Normal native Copy/reuse across the supported formats, privacy text skipping, pause, settings, persistence, and storage-preservation failure paths were exercised. No automated tests were created or run.

## Final compact interaction closure

The independent reviewer verified hover + Command+C takes priority over a different keyboard-selected row by pasting the resulting URL into TextEdit. Selected search and preview text still copy natively. A final native recheck left the pointer over a row, focused search with Command+F, and entered `ordinary`, an actual Space keystroke, then `privacy`: the search remained focused with one matching row and no preview. Settings uses the concise `None` placeholder for no excluded apps.

The reliability reviewer closed a final source finding: if pins or a preserved legacy retention/capacity policy prevent a new capture from surviving pruning, capture now reports through the existing on-demand Details path. It preserves saved history and pinned recopies. This specific capacity guard received source review; the ordinary failure path had already been exercised natively.

The final signed bundle was installed at `~/Applications/Palette.app` and launched with `--background`. Its executable matches the verified build, and signature verification passes. The preceding installed bundle is preserved under the ignored build directory.

## Settings simplification follow-up

Removed the duplicate Save clipboard history checkbox; Pause/Resume capture remains in More. The settings sheet is now 360×260. A native review-profile inspection confirmed the checkbox is absent and the remaining controls fit. Saving through the native Save button preserved the paused state in settings.json. The build and installed signature pass; no automated tests were created or run.

## Menu-bar anchoring follow-up

The primary panel now uses the menu-bar button’s screen and bounds, aligns its right edge with the icon, and extends to the left with a 6-point gap beneath the menu bar. Horizontal placement is constrained to the screen. If macOS supplies an offscreen status-item frame, shortcut access remains onscreen below the menu bar.

The user confirmed a native click opened the panel beneath the icon, then requested the final right-edge alignment. That alignment change passed compilation and source inspection. Native window inspection confirmed the final 340×300 panel remains onscreen; the invalid-anchor path was encountered during launch and corrected before completion. The installed signature passes. No automated tests were created or run.

## Search and default-preview simplification

Removed the All apps/Pinned dropdown and its population/filtering code. Search remains case-insensitive across clip content, titles, and source-app names. The list receives focus on opening and after Settings closes; search is entered by clicking it or Command+F. Pins remain available in the item context menu.

Native checks in the paused synthetic profile confirmed immediate Space preview after opening; pointer-row Space preview despite a different keyboard selection; `microsof` matching the Microsoft Edge clip by its source; and clicking search then entering `steam`, an actual Space key, and `helper` showing all three Steam Helper clips. The 340×300 screenshot has no dropdown. Build and installed signature pass; no automated tests were created or run.

## Two-action header follow-up

Replaced More with pause/resume and clear-all icons. Removed SettingsPanel.swift, its build input, the settings and Details menus, and the unused per-item pin/delete actions. The native Quit shortcut remains. The serial store now owns capture toggling and clear-all directly, while honoring legacy privacy policy and pinned-history retention. Ordinary failures tint the existing pause/resume icon amber and remain readable in its tooltip; no extra panel or menu is added.

Native interaction used `/tmp/palette-header-review.K5FV9Z`, a disposable clone of the four-item migration profile containing legacy pins. Resume switched to Pause; Pause switched back to Resume. Clear opened a native confirmation, Cancel preserved all four clips, and confirmation removed every clip and disabled the empty-history bin. A normal quit/relaunch preserved both the empty history and paused capture. Original profiles and production history were not cleared. Build and installed signature checks pass; no automated tests were created or run.

## Panel alignment correction

The latest direction supersedes the earlier left-extending alignment: the panel now starts at the icon’s left edge (`anchor.minX`) and extends right. Existing screen-edge constraints remain. The focused source change builds successfully and the installed signature verifies; no automated tests were created or run.

## Narrow panel and direct controls

Reduced the panel from 340×300 to 280×300. Pause/resume is now part of the clickable Palette title, retaining the overlapping-squares identity. The bin clears history immediately without a confirmation, as requested. A separated full-width Quit row displays ⌘Q at the bottom. Removed the obsolete confirmation and sheet guards; preview text uses the scroll view’s available width.

Native interaction in disposable `/tmp/palette-title-review.xxbxW7` confirmed both title toggle states, immediate clearing to an empty list with no sheet, and termination through the Quit row. Native screenshots showed image preview and wrapped text preview contained within 280×300 with Quit still visible. Production history was not cleared. Build and installed-signature checks pass; no automated tests were created or run.

## Native AppKit menu refactor

Replaced the custom borderless NSPanel with NSMenu containing one clipboard view, a native separator, and a native Quit Palette item. Removed the painted background, explicit corners/border/shadow, forced dark appearance, manual screen-position calculations, window-dismissal delegate, and imitation Quit button. AppKit now owns the menu surface and tracking. The clipboard view is 280×260; native window inspection measured the resulting menu at 280×305 on this Mac.

The user confirmed that the native menu has the desired system appearance, then reported the play/resume icon looked off-center. Its title button now uses native imageHugsTitle grouping and matching font/symbol metrics. Hover tracking uses activeAlways because native menu windows do not need to become key windows. The SDK documents custom menu views receiving keyboard/mouse events and attachment on each open.

Independent source review caught two concrete lifecycle issues: a paste-focus failure attempted to open the blocking menu before reporting its error, and normal Quit could wait behind a blocked Keychain lookup before any history was available. Errors are now reported before scheduling menu presentation through the run loop; Quit drains accepted writes only after successful history loading. Both fixes received focused reviewer closure. Main-menu tracking was observed in a native process sample; capture uses common run-loop modes, and presentation does not run from a blocking main-dispatch callback.

Desktop CUA inspection timed out for the menu-only window, so previous panel interaction results are not claimed for this container. In the disposable profile at `/tmp/palette-menu-review.ywDCzs`, the user explicitly confirmed the corrected alignment and interactions after checking hover + Space, hover + Command+C, and typing an app name in search. The usability reviewer separately rechecked the title grouping and hover tracking in source and closed the findings. Build and signature verification pass; no automated tests were created or run.

## Image-only preview and shorter hints

Shortened row hints to `⌘C Copy`, adding `Space Preview` only for images. Space opens previews only for images; text, links, and files remain in the list. Removed the text-preview scroll view and its selection/shortcut handling. Moving from an image preview to a non-image restores the list.

The macOS build, installed signature, and diff checks pass. Source inspection covers the image-only hint and Space guards. Native desktop inspection timed out for the menu-only app, so this follow-up has no fresh native interaction confirmation. The existing instance was still waiting on its initial Keychain read, with no accepted history writes, and was stopped before installing the update. History files and the Keychain key were retained. No automated tests were created or run.

## Quiet launch and native status-item opening

Removed automatic menu presentation on launch/reopen and the manually positioned NSMenu.popUp path. Launch now only adds the menu-bar icon. The shortcut invokes the status-item button's native click, sharing its attached menu behavior with an actual icon click. Invalid review arguments report through the existing icon tooltip without forcing a popup. The obsolete background-launch option is no longer needed.

The installed build was launched normally with no arguments, then reopened through macOS Launch Services. Native CGWindow inspection found no Palette windows after either operation. A real Command+Shift+V keyboard event opened its 280×305 native menu at screen coordinates (1048, 34), beneath the menu bar rather than at the bottom-left corner. Escape removed the menu; a subsequent native window query returned no Palette windows. Build, installed signature, and diff checks pass. Independent source review approved the simplified opening path and unchanged capture/quit lifecycle. No automated tests were created or run.

## Capture state in the title

Removed the play/pause symbol and its layout configuration. Palette's clickable title now indicates capture state: soft mint #A8D5B5 when on, muted rose #E7A5A5 when off. Dynamic native colors use darker #2F7046 / #A43F3F in light appearance for legibility. Tooltip and accessibility action labels retain Pause capture / Resume capture, and failures remain in the title and menu-bar tooltips. Capture and persistence behavior are unchanged.

Build, installed signature, and diff checks pass. Color selection and symbol removal were checked in source; this change has no fresh visual or toggle interaction confirmation. No automated tests were created or run.

## Content-fitting height with stable search

The clipboard view now wraps empty/short history and stops at its existing 260-point maximum. The title row is fixed at 22 points, search at 26, and history uses its native 32-point row pitch. Empty history hides the scroll area. Clicking search, using Command+F, or typing sets a per-opening expansion flag; clearing the query does not collapse it. Opening the menu again resets that flag. Image previews retain the maximum height, and geometry changes clear stale hover targeting.

Native interaction in paused disposable `/tmp/palette-height-review.lyH6nC` measured 121 points total for empty history, 193 for two synthetic clips, and 305 for search. A pointer click into search followed by typing `whatsap` confirmed the field value and expansion; clearing the query retained 305, and Escape/reopening restored 121. Native focus checks caught an ineffective becomeFirstResponder hook, and reopen checks caught unstable fitted-header sizing; both were simplified and rechecked. Some subsequent injected keyboard/AX actions did not reach the field, so Command+F and populated-result filtering are source-checked, not claimed as consistent native passes in this session. No production clips were cleared or changed for these checks.

The final build, installed signature, and diff checks pass. The independent usability reviewer closed the source and observed resizing findings. No automated tests were created or run.

## White header and native capture row

Replaced the colored title button with a static white Palette label and white overlapping-squares header icon. Removed both dynamic state colors and the title-button action. A standard native menu item directly above Quit now reads Resume while paused and Pause while capturing; errors remain in the existing title, capture-row, and status-icon tooltips. The clipboard view maximum is reduced to 236 points to accommodate the native 24-point row while retaining the same 305-point overall maximum.

Native interaction in the disposable paused height-review profile confirmed Resume above Quit, Resume switching capture on and changing the row to Pause, and Pause switching it off again. The saved settings confirmed both changes. Accessibility inspection identifies Palette as static text rather than a button. The final build's six-clip disposable profile measured 280×305, confirming the overall maximum is unchanged. Build, installed signature, and diff checks pass. Production history was not cleared. No automated tests were created or run.

## Clear History in the native action group

Removed the header bin button and its tooltip/accessibility setup. The native bottom rows are now Pause/Resume, Clear History, and Quit Palette. Clear History retains immediate clearing without confirmation and is disabled when history is empty or unavailable. Removed the obsolete post-clear table-focus call. The clipboard view maximum is 212 points to accommodate the extra native row while keeping the overall maximum at 305.

Native interaction in disposable `/tmp/palette-clear-row-review.d7c817` confirmed the row order and a 280×305 full menu. Clicking Clear History cleared its synthetic clips directly; reopening showed the action disabled. After normal Quit, a read of that disposable encrypted history confirmed zero saved clips. Production history was not cleared. Build, installed signature, and diff checks pass. No automated tests were created or run.

## Quit and reopen replace Pause/Resume

Removed the native Pause/Resume row, toggle action, saved enabled policy, and settings-write path. Capture now requires successfully loaded history while the process is running. Older settings with enabled:false decode normally and the obsolete field is ignored; existing history, keys, retention, capacity, pins, and exclusions remain intact. Clear History and Quit are the only native action rows. The clipboard view returns to a 236-point maximum, keeping the overall maximum at 305.

In disposable `/tmp/palette-lifecycle-review.FyxIS1`, legacy settings still contained enabled:false. Native CUA copying from a synthetic TextEdit document saved marker A. Normal application termination and process absence were verified; marker B was copied while quit. Reopening the same app/profile and copying marker C saved C. Reading the disposable encrypted history confirmed A present, B absent, C present, while the legacy settings file remained unchanged. The native environment attributed A to ChatGPT despite the TextEdit interaction, so this check confirms capture lifecycle, not source-app attribution. No production history was cleared or migrated.

Independent reliability source review approved the removed pause state and retained history-readiness, exclusions, encryption, and accepted-write shutdown guards. The macOS build, installed signature, and diff checks pass. No automated tests were created or run.

## Search-first content and empty placeholder

Removed the permanent Palette header, icon, label, and title tooltip. Content now starts with search and results. Available but empty history shows the overlapping-squares icon with “Copied items appear here”; a search with no results uses “No matching clips”. Both use a centered, compact native view with a 64-point minimum and secondary label colors. Populated results hide the placeholder and clear its text. Loading or unavailable history does not show an empty-history reassurance; failures remain in the menu-bar icon tooltip.

Content sizing now accounts only for search, margins, and the results/placeholder body. The 236-point content maximum, 305-point overall maximum, and per-opening expanded-search behavior remain unchanged. Native Clear History and Quit rows remain at the bottom.

The independent usability reviewer inspected the implementation and found no substantive source issue. The build, installed signature, and diff checks pass. A disposable empty profile was launched for inspection, but CUA timed out on the menu-only window and no fresh visual or transition confirmation is claimed. No production history was cleared. No automated tests were created or run.
