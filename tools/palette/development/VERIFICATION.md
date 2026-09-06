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
- Sensitive pasteboard markers, rich HTML/RTF restoration, URL restoration,
  multi-file copying, missing-file errors, time-based expiration, image/payload
  rejection limits, and corrupted-storage recovery have source review coverage
  but do not yet have complete native runtime evidence.
- The narrow layout now stacks the preview below the history instead of removing
  it. Smaller native window sizes, long-content scrolling, empty states, and
  larger/image-heavy histories still need runtime coverage. A single process RSS
  snapshot is insufficient to claim bounded growth or performance acceptance.
- Header icon rendering is verified. Bundle icon generation and the menu-bar
  overlapping-square symbol are implemented; rendered OS icon surfaces still
  need a final visual check.

Continue the active goal with the same three review roles and no automated tests.
Do not treat this checkpoint or the reviewers' scoped approvals as full acceptance.
