# Browser change log and release verification

## 2026-11-23

Changes are based on `cd27bf0c5e` in `sanogueralorenzo.github.io/browser`, which builds the `com.itsbrowser.Browser` app.

| Area | Change |
| --- | --- |
| Session checkpoints | Moved routine encoding, checksums, and disk writes to one serial background queue. Reused the validated checkpoint bytes for the backup and skipped scheduling writes for unchanged page metadata and window frames. Explicit close and quit still wait for a durable checkpoint. |
| Session recovery | Kept the recovery notice visible until dismissal. Normal background saves can clear a storage error without clearing the recovery notice. |
| First-run ad blocking | Bundled and digest-verified the existing uBlock Origin Lite archive. Removed the first-run download path and its progress state. Browser still checks the update feed after opening the browsing window. |
| Find in Page | Routed buttons and keyboard commands through one WebKit search path. Added no-match feedback, control names, and a compact layout for narrow split panes. |
| Sidebar and Spaces | Identified Private Spaces with an icon and accessibility label. Used the same UTF-8 cap for creating and renaming a Space so a long name cannot prevent checkpointing. |
| Address palette | Hid the underlying page and sidebar from accessibility navigation while the palette is open. |
| Browsing data | Used one Space-scoped confirmation for clearing history or website data. Added consistent empty and no-results states for history and downloads. |
| Private downloads | Cleaned up owned partial files when deleting a Private Space or quitting Browser. Completed files remain at their chosen destinations. |
| Media | Used the playing media element for the Now Playing state and skipped extra action lookups on pages without media. Restored Picture in Picture from a closed window through the session owner. |

## Release checks

- Built and signed the Release configuration using Xcode 26.6 on Apple silicon with macOS 26.5.2. Runtime fixtures used disposable profiles and separate bundle identifiers.
- Verified empty-window sidebar reveal, collapse after opening a tab, sidebar docking, Pinned, Saved, and current tab placement, native Tab entry into site-search mode, explicit command mode for Clear Tabs, separate persistent Space stores, and a nonpersistent Private Space store.
- Verified a real WebKit Find match and no-match result, long Unicode Space names on creation and rename, in-flight checkpoint ordering, backup recovery, preservation of a damaged checkpoint, and removal of closed-window state.
- Loaded a fresh profile from the bundled blocker, requested a local URL matching an EasyList rule, and confirmed the blocker rejected it while the control URL loaded. Verified that an invalid update hash was rejected and that the bundled package remained available after discarding an update.
- Verified Private Space partial-file cleanup and retention of completed and ordinary-Space files. Started two live WebKit downloads with the same filename, removed the window, and checked that both files arrived intact under distinct names.

## Performance

| Local workload | Before | After |
| --- | --- | --- |
| Largest main-thread scheduling gap per run during a routine checkpoint with a 24 MiB fixture payload | 428, 623, 421 ms | 7, 7, 7 ms |
| First local navigation from a disposable fresh profile | 14.04 s | 10.58 s |
| First local navigation from that profile on restart | 3.09 s | 3.18 s |
| Installed app bundle on disk | 5.3 MiB | 14 MiB |

Startup numbers are one launch per configuration. The bundle now includes the 8.6 MiB blocker archive, and a fresh profile uses that copy directly. The first launch still spends time preparing WebKit rules.

The Release candidate and Safari 26.5.2 ran the same local fixed-width fixture on this Mac with both documents hidden. Across eight measured samples per browser, median layout for 1,000 rows was 38 ms in both. Median time for 500 programmatic scroll-position changes was 2.5 ms in Browser and 3 ms in Safari. Interactive startup, tab switching, scroll smoothness, memory, and energy parity remain unverified.

## Coverage limits

The checks cover the release build, isolated core flows, and the synthetic workloads above. Full VoiceOver interaction, live Picture in Picture restore, and long-session memory and energy measurements remain outside this verification pass.
