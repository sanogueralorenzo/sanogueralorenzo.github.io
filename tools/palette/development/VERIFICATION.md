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
