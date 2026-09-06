# Clipboard iteration evidence — September 6, 2026

This is an implementation checkpoint, not completion of every acceptance criterion
in [GOAL.md](GOAL.md). No automated tests were created or run. Validation used
TypeScript checking, a production macOS build, independent source/visual reviews,
and deliberate UI interactions in an isolated native review profile.

## Build and review

- `npm --prefix tools/palette run typecheck` passed.
- `npm --prefix tools/palette run build:macos` passed: production React UI, Node
  daemon, Rust indexer, native Swift host, icon generation, and ad-hoc signing.
- The final review app used `sh.palette.Desktop.Review`, `--review --clipboard`,
  and `build/review-profile`; production user history was not used for evidence.
- Three independent reviewers covered [visuals](reviews/visual.md),
  [workflow](reviews/workflow.md), and [reliability](reviews/reliability.md).
  Baseline findings, fixes, and follow-up verdicts are retained in those reports.
  Reviewers did not control the live app; runtime checks below were performed by
  the coordinating agent. Their final source reviews found no remaining concrete
  blocker, and visual review passed the four submitted native states at 1040×680.

## Observed native behavior

| Check | Observation |
| --- | --- |
| Native panel | The built app renders the new three-column clipboard surface at 1040×680 with the overlapping-square header icon. |
| Text capture | Synthetic multiline text appears in history and wraps in the preview. Background UI automation did not provide trustworthy source identity; see limitations below. |
| File capture and restore | Finder copied the approved concept PNG. Palette captured a file item with Finder provenance. Copy restored a native file URL; Finder pasted it into `build/paste-destination`. `cmp` confirmed the pasted file was byte-identical to the original. |
| Image capture and restore | Preview's rectangular selection copied a 1536×1024 image. Palette captured an image with Preview provenance, dimensions, and thumbnail. After Palette Copy, Preview's New from Clipboard opened an Untitled image from the restored bytes. |
| Self-capture | History count remained stable after native image/file restores during the capture check. |
| Persistence | Restarting into the final native build retained eight clips, the pinned image, and paused capture. |
| Combined filters | Preview source + Images type + search `image` returned the single captured image. Pinned view showed the same saved image. |
| Action focus | Actions → Copy closed the dialog; immediately typing `image` entered the search field. Copy status remained visible. |
| Pin and unpin | `⌘ P` changed Pinned 1 → 0 → 1 and updated the selected image's pin state and feedback. |
| Delete | `⌘ ⌫` with a row focused removed that row, reduced the count, and selected the next clip. |
| Capacity | Saving maximum clips = 2 reduced nine review clips to the newest unpinned file plus the older pinned image. |
| Settings | Capture state, capacity, sensitive toggle, and excluded-app identifier were visible and saved. The dialog fit within the native window with Cancel and Save accessible. |
| Direct paste without permission | The app reported the missing Accessibility permission and offered Copy. Permission-enabled return-to-app paste remains unverified. |

The separate review profile still reads the shared system clipboard when capture
is enabled. Capture was paused between later checks; an unrelated copy that
arrived during review was removed from the review profile before final screenshots.
Committed screenshots contain synthetic review content only. Profile files,
encryption keys, and pasted fixture files remain under ignored `build/`.

## Comparable visual evidence

- [Original browser baseline](evidence/baseline-browser.png): the previous plain
  text list, at a different window size; useful for hierarchy rather than pixel comparison.
- [First native iteration](evidence/iteration-1-native.png): initial three-column build.
- [Final native text](evidence/final-native-text.png): wider sidebar, readable
  metadata, mixed history, text preview, actions, and paused state.
- [Final pinned image](evidence/final-native-image.png): saved pin, image containment,
  dimensions, and native source icon.
- [Final combined filters](evidence/final-native-filtered.png): source, type, query,
  result selection, and Copy feedback together.
- [Final settings](evidence/final-native-settings.png): all policy controls visible.
- [Restored image in Preview](evidence/restored-image-preview.png): actual native
  image restoration. The image is the approved concept used as a synthetic fixture.

## Remaining acceptance work and known limits

- Source identity is inferred from foreground application changes, not an
  authoritative pasteboard writer. Finder and Preview were correctly identified
  in the successful captures above. Other background automation copies were
  labeled as an unrelated foreground app. In a later exclusion attempt, copying
  `review-note.txt` from background Finder while another app was foreground
  produced a file labeled Microsoft Edge, bypassing a Finder exclusion. This is
  a demonstrated limitation, not a passed excluded-app runtime check. Ordinary
  foreground exclusion still needs a controlled check with stable foreground focus.
- Accessibility authorization is pending. Permission-enabled paste, app-activation
  failure recovery, and representative five-second keyboard retrieval remain to
  be exercised in the native app.
- Sensitive pasteboard markers and rich HTML restoration,
  multi-file copying, missing-file errors, time-based expiration, image/payload
  rejection limits, and corrupted-storage recovery have source review coverage
  but do not yet have complete native runtime evidence.
- The narrow layout now stacks the preview below the history instead of removing
  it. Smaller native window sizes, long-content scrolling,
  empty-history states, histories at the full supported limit, and broader
  image-heavy workloads still need runtime coverage. The 1,000-clip observations
  below cover a limited workload and do not establish all performance acceptance.
- Header icon rendering is verified. Bundle icon generation and the menu-bar
  overlapping-square symbol are implemented; rendered OS icon surfaces still
  need a final visual check.

Continue the active goal with the same three review roles and no automated tests.
Do not treat this checkpoint or the reviewers' scoped approvals as full acceptance.


## Second iteration: larger histories and native editing

The reviewer-led scaling pass identified overlapping refresh requests, unchanged
full-history transfers, quadratic pruning, main-thread JSON decoding, and repeated
payload hashing. This iteration adds one in-flight background refresh, revision
responses for unchanged history, linear pruning, an ordered background response
reader with a scan cursor, cached immutable-item fingerprints/sizes, and a virtual
history list. Selection, filtering, and explicit Home/End/Page navigation reveal
the selected row; passive polling does not move the user's browsing position.
Relative timestamps still advance each minute when the panel is visible.

A standard native Edit menu now supplies Select All, Cut, Copy, Paste, Undo and
Redo through the responder chain. This resolved an observed Command-A failure in
search and settings. Native Copy remains separate from the historical-copy action
when text is selected. The following were checked in the running build:

- Command-A visibly selected the complete query; replacement typing replaced it.
- With a search caret or the history list explicitly focused, Command-C restored
  the selected saved URL after another app replaced the clipboard with a marker.
  A read-only `pbpaste` comparison confirmed the URL, without printing clipboard data.
- With query text selected, Command-C copied only the query into scratch TextEdit.
- In the settings textarea, Select All/Cut cleared a synthetic identifier, Paste
  restored it, Undo cleared it, and Redo restored it. The draft was canceled.
- Actual TextEdit capture preserved an RTF bold heading and ordinary body. Palette
  Copy restored both into a new scratch TextEdit document; see
  [rich-text restoration](evidence/restored-rich-text.png).
- Actual TextEdit copying of `https://example.com/palette-native` produced a Link
  item. Copy restored it after the system clipboard was changed to a marker.
  Background source attribution was again incorrect (`godot`), so this proves
  native URL capture/restoration, not correct foreground provenance.

The clipboard is asynchronous and shared. One attempted paste happened before the
restore had completed, and an earlier check was interrupted by another clipboard
write. These attempts were not counted as passes. Final URL checks explicitly
focused the intended Palette control, waited for Copy feedback, and read back
only boolean comparisons against the two known synthetic values.

### Large-history conditions and observations

A separate `build/large-review-profile` was populated with encrypted synthetic data:
1,000 clips (890 text, 100 links, ten image entries), 28,134,655 bytes of serialized
plaintext before encryption. The images reuse the previously captured synthetic
1536×1024 PNG under distinct review source IDs. This is a rendering/storage fixture,
not evidence of 1,000 real clipboard captures or ten different image encodings.
Capture was paused during navigation/memory observations. The later actual URL
capture replaced one unpinned fixture row under the 1,000-item capacity policy.

- The native UI loaded the full count, rendered about 15 history options near the
  top, and reached clip 0999 with End. Home returned to the first row, including
  when that row remained selected while scrolled offscreen.
- Space scrolled the focused list without changing selection. After multiple
  two-second polling intervals, the same older rows remained in view. The preview
  continued to show the selected clip. Native wheel-scroll automation returned
  `noWindowsAvailable`; keyboard scrolling supplied the actual runtime evidence.
- Search `0999` followed by Copy and result/status observations took **978 ms** in
  one CUA sequence with the panel already open. This is a limited search-and-copy
  measurement, not a human usability study or permission-enabled paste measurement.
- Pinning clip 0999 completed and changed Pinned 11 → 12, verifying that mutation
  invalidated the revision cache. Restarting retained the new pin.
- [Large native history](evidence/large-native-history.png) shows the latest build;
  [no matching clips](evidence/large-native-empty.png) shows the recoverable empty
  filter state. Clear filters remains available.

Process snapshots (RSS in KiB) during this run:

| Observation | Native host | Node service |
| --- | ---: | ---: |
| Initial browsing | 114,544 | 313,632 |
| About 2m25s, after pinning | 126,976 | 333,952 |
| About 4m45s, after idle polling/collection | 113,568 | 203,632 |

These samples show memory falling after the operation rather than growing
monotonically over this short run. They do not measure all WebKit helper memory,
a long soak, the 10,000-item maximum, or the 64 MiB storage boundary. The persistent
JSON store still rewrites encrypted history on mutations; this limitation remains
relevant for heavier workloads.

The review bundle now has distinct bundle name/display name `Palette Review` to
avoid confusion with the installed app. Optional `--keep-visible` is honored only
with `--review --data-dir`; it keeps the review panel visible on focus loss for
side-by-side inspection. Explicit dismissal still works. Normal app focus-loss
behavior and direct-paste acceptance must be verified without that option.

Build and TypeScript checks passed again. All three independent reviewer roles
performed follow-up review; their reports distinguish source conclusions from the
coordinator's runtime evidence. No automated tests were created or run. The active
goal remains incomplete pending the remaining acceptance work above, particularly
permission-enabled paste and controlled foreground-app attribution/exclusions.
