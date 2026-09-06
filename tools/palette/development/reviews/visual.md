# Visual review — baseline

Reviewed September 6, 2026 against `../clipboard-target.png` and `../GOAL.md`. Source inspection only: `src/ui/PaletteApp.tsx`, `src/ui/styles.css`, and native window/icon declarations. No live app was controlled and no automated tests were created or run. A final visual pass requires fresh runtime captures.

## Prioritized findings

1. **P1 — Clipboard information architecture is absent.** The current clipboard view is one text list with search and pause. Implement the concept's three areas: app sidebar (All apps, Pinned, source names/icons/counts), history with type filters, and selected-item preview. Keep search and app/type selection combinable and visibly active. Native macOS's 680 × 420 window cannot accommodate the reference's proportions; choose a larger clipboard size constrained to the actual visible screen and adapt narrow layouts deliberately.
2. **P1 — Clipboard content cannot be visually identified reliably.** Every row displays the first 120 content characters and its kind. Add image thumbnails, file/link/text type tiles, source app identity, relative time, pin indication, and a full preview with useful metadata. Handle long unbroken text and filenames with bounded list truncation plus selectable/wrapped or scrollable preview content. Empty or binary image payloads must never appear as `(empty)`.
3. **P1 — Selection, preview, and actions need distinct presentation.** Rows currently copy immediately on click; there is no preview selection or visible copy/paste/manage area. Select on click, place primary paste and secondary copy actions in the preview, and expose pin/delete with honest action feedback. Match the reference's restrained lavender selected row border/tint and a persistent keyboard-action footer.
4. **P2 — Header and capture controls need stable layout.** Pause is absolutely positioned over the right side of the search field, with no reserved input space. Create a real header with the Palette mark, Clipboard context, pause/resume, and settings; keep search in its own row. Provide readable paused, unavailable, empty-history, and no-match states rather than using one generic empty message.
5. **P2 — Visual hierarchy and sizing need a complete pass.** The current shell uses 12px padding, a 330px results cap, gray selection, and no section dividers or preview hierarchy. Establish restrained dark surfaces, 1px separators, consistent radii, muted metadata, comfortable thumbnail rows, and explicit independently scrolling columns. Keep header/search/footer stable when results or preview overflow.
6. **P2 — The approved mark is missing.** The interface has no brand icon; macOS uses `command.circle`. Use two diagonally overlapping rounded outlined squares consistently in the interface, app bundle, and menu bar. Verify outline separation and legibility at menu-bar scale and icon appearance in macOS app surfaces.

## Visual acceptance criteria for follow-up

- Fresh synthetic-content captures show the running native app at its default clipboard window size and a smaller supported size; no overlaps, clipped actions, accidental horizontal scrolling, or hidden selected row.
- Header, search, source sidebar, filters, history, preview, and footer follow the approved concept's hierarchy; app identity/counts and content metadata remain legible without dominating titles.
- Text, long text/code, link, image, and file selections each have meaningful list and preview states. Images preserve aspect ratio; filenames/URLs remain recoverable in preview.
- All apps, Pinned, app-filtered, combined-filter, empty, no-match, and paused captures communicate their state clearly. Selection is distinct from hover and keyboard focus is visible.
- Independent history/preview scrolling leaves controls accessible, and switching item type does not unexpectedly resize the window or displace primary actions.
- The overlapping-square mark is consistent and crisp in the app header, bundled app icon, and menu bar.
- A final pass compares fresh captures from the final build to the baseline and concept; source inspection or a staged browser image alone is insufficient.

# Visual review — iteration 1

Inspected `../evidence/iteration-1-native.png` (1040 × 680) and current `ClipboardView.tsx` / `clipboard.css`. The three-column hierarchy, overlapping-square header mark, dark surfaces, lavender selection, and persistent action area now substantially follow the concept. The screenshot contains only two synthetic text clips; source-label correctness is a known issue under separate investigation and is not graded here.

1. **P2 — App sidebar truncates an ordinary app name at the default size (verified screenshot).** “Microsoft E…” is already truncated with only two sources and single-digit counts. The fixed 178px column is narrower proportionally than the reference. Use roughly 200–210px at 1040px (retain narrower breakpoints), ensure counts never shrink, and give names the remaining width. Full app names should be available on focus as well as hover when unavoidable truncation occurs.
2. **P2 — Secondary text and keyboard help are overly small (verified screenshot and CSS).** History metadata is 11px, kind labels 10px, and the footer 10px, which makes the retrieval information noticeably harder to scan than the reference. Raise row titles to 14px, source/time metadata to 12px, and kind/footer labels to at least 11px at the default size; maintain compact rows. Check after populating six or more varied clips so the denser state drives the choice.
3. **P1 if narrow windows are supported — Preview vanishes below 650px with no visible replacement (source verified, not runtime verified).** The breakpoint sets `.clip-preview` to `display:none`, removing full content and the primary copy/paste controls. Either constrain native clipboard width to a viable three-column minimum or provide a keyboard-accessible detail view for narrow widths. Do not claim narrow-layout acceptance from this 1040px capture.
4. **P2 — Settings and large-content states still need visual evidence.** A single short text state cannot establish image sizing, file path wrapping, long text scrolling, settings scroll/access to Save, app-list overflow, or feedback/footer behavior. Capture these on the final native build. In particular, validate the 440px settings dialog against the smallest supported window and tall image containment before accepting the CSS.

Acceptance remains pending for mixed-content history, image/file/link previews, settings, narrow supported size, empty/paused states, and final app/menu-bar icon surfaces. The current short-text default-size capture has no observed overlap or clipped primary action.

# Visual review — final submitted build

Independently reviewed `final-native-text.png`, `final-native-image.png`, `final-native-filtered.png`, and `final-native-settings.png`, all native 1040 × 680 captures, against the approved target. Also inspected the updated narrow-layout CSS, `native/macos/GenerateIcon.swift`, menu-bar icon declaration, and interface icon geometry. No live UI was controlled and no automated tests were created or run.

**Assessment: the submitted default-size visual states pass this review.** The source sidebar, searchable mixed-content list, selected preview, lavender treatment, metadata, and keyboard footer form a coherent realization of the approved concept. No new blocking visual defect is visible in these captures.

- The sidebar is now 202px; Microsoft Edge is fully readable. Increased row-title, source/time, kind, and footer sizes address the first-pass readability findings while retaining six visible history rows.
- The text state demonstrates realistic mixed history and independent list overflow. The pinned-image state shows clear pin feedback, a contained image retaining its aspect ratio, and dimensions metadata.
- The combined query + source + Images state communicates all three filters visibly. Its copy feedback occupies a dedicated strip without overlapping the preview buttons or footer.
- The settings dialog fits within the default window with all fields, policy explanations, and both final actions visible. The focused close button has a clear outline; the backdrop separates the dialog from history.
- Narrow-layout source now stacks a visible preview beneath history in the scrolling workspace instead of removing it. This resolves the earlier source-level loss of preview/actions; the narrow rendering itself has not been captured or independently verified.
- The interface and generated macOS application asset both use two diagonally overlapping rounded outlined squares; the menu bar uses the matching `square.on.square` template symbol. Source confirms replacement and the header appearance is verified. Finder/Dock/menu-bar rendered appearance remains unverified in the supplied evidence.

Limits: these four captures do not establish link/file detail layout, long-text/code behavior, extremely tall images, many source apps, empty/no-match rendering, or narrow/small-screen behavior. Source-label accuracy on synthetic background writes is explicitly outside this visual pass and remains subject to the native review. This is a visual assessment, not a claim that clipboard fidelity, retrieval timing, or every goal criterion has passed.
