# Minimal Palette — independent usability and visual review

Reviewer: usability and visual coherence. No implementation edits or automated tests.

## Baseline source findings

1. **High — the core clipboard loop lives inside a desktop workspace.** `PaletteHost.swift` sizes Clipboard at 1040 × 680 and centers it; `ClipboardView.tsx` permanently renders source sidebar, history column, preview, metadata, type filters, and footer. This consumes attention and screen space before the user can reuse one item. Replace it with one compact corner panel, roughly 460–520px wide, using search, a compact source-app picker, and a content list. Preserve the warm neutral surfaces and overlapping squares. Show a larger preview only when requested.
2. **High — two product entry points compete.** The app normally opens a launcher, exposes two global shortcuts, and makes the Palette brand a Back-to-launcher control. Clipboard should be the only primary view and summon target. Remove app/file search, commands, extensions, recent command runs, the breadcrumb, and Back navigation.
3. **Medium — actions repeat and create an unnecessary modal.** Copy/paste appear in a permanent preview, footer, and Actions dialog; pin appears both in preview and dialog. Keep one clear default reuse action with Return and a secondary Copy command. Put pin/delete in a native context menu or compact overflow; Escape should close the immediate transient surface, then dismiss the utility.
4. **Medium — settings expose storage mechanics.** A maximum-clip number field and raw app identifier textarea burden ordinary use. Use a sensible fixed capacity, a short retention choice, capture pause, and recognizable app names for exclusions. Essential sensitive-pasteboard protection should be on by default; avoid offering an implementation switch without clear everyday value.
5. **Medium — persistence must not become invisible deletion during simplification.** Existing pins, source grouping, text, rich text, images, files, and stored history need migration/use checks in the native app. Keep explicit, comprehensible failure feedback; do not present failed loading as an empty history.

## Native review

Pending coordination of shared desktop control. Native review must cover compact visual proportions, source retrieval, arrows/Return/Copy, search text editing, preview, settings, Escape, click-away, and reopening. Source findings are not claims of runtime verification.

## Requested focused recheck

After implementation, provide the built app and isolated review-profile path, and hand over native UI control for an independent focused pass. Close findings only against the final source and observed native behavior.

### Installed native baseline observed

The installed Palette is an older 680 × 420 native WebView build, not the current three-column source. It opens a launcher with Clipboard History and Run History, then a plain dark clipboard list without source organization or useful previews. The installed app uses real user history, so no screenshots were saved and no existing item was copied, changed, or deleted.

Using only a synthetic unmatched search query, the running app rendered “No clipboard items,” conflating no matches with empty history. Escape returned to the launcher rather than dismissing Clipboard; another Escape cleared the lingering query while the launcher remained available in accessibility state. This confirms the need for one primary clipboard surface, distinct no-match wording, and a direct dismissal route. Final runtime recheck must use the explicit new build and isolated synthetic review profile.

The proposed native AppKit direction—420 × 550 dark lavender corner panel, native source popup, inline Space preview, and compact footer—is visually coherent with Palette and directly addresses findings 1–3.

## First native rewrite recheck

Independently controlled the explicit new `build/Palette.app` using `/tmp/palette-native-migration`, an isolated clone of prior review history with capture paused. Four legacy encrypted items were visible: rich text, file, image (still pinned), and a prior review URL. No new captures or existing-item mutations were performed.

- The 420 × 550 dark lavender panel, overlapping-squares identity, compact source popup, list, and copy/paste footer make the clipboard loop much clearer. Launcher, sidebar, type tabs, metadata panel, and Actions modal are gone.
- Native source popup filtered Preview to its one image. Search filtered the rich-text entry; Command+A and replacement typing worked. Down moved focus into the list; Space toggled both image and text previews.
- Settings is a readable, compact native sheet with capture, retention, recognizable excluded apps, and essential local-storage/privacy explanation. Escape closed the sheet and returned focus to search. Screenshots were observed in tool output; none were saved to the repository.
- **High — image preview widened the utility from 420px to 932px**, leaving a white/cropped region to the right and a tiny image. Hiding the preview did not restore the original width. Set the preview image's compression resistance low and ensure its intrinsic size cannot grow the window; rebuild and recheck both text and image within the fixed panel.
- **Low — hidden empty-state text remained in accessibility output** alongside visible matching rows (“No matches” and “No clips from this app”). Exclude this text from accessibility when hidden if a small targeted change suffices.

Escape on the primary panel calls the expected source dismiss route, but immediate CUA observation of Palette reopens it via the app reopen handler, resetting query/source. That tool sequence cannot independently establish hidden state. Observe another surface after dismissal instead. The prior source-attribution limitation remains: CUA can interact with a target app while the actual foreground app remains ChatGPT; this pass did not claim fresh multi-app capture verification.

Focused image-layout recheck requested after the concrete fix. No automated tests created or run.

## Focused image-layout recheck

Independently inspected the rebuilt native app with the same isolated paused profile. Preview-source filter, Down, and Space now show the migrated image centered inside the panel; screenshot stayed **420 × 550**. Closing the preview preserved the same compact geometry. The high-priority image-width finding is resolved. Rounded lavender selection restores visual coherence without introducing another surface.

One concrete visual follow-up: the row title truncated as “Image · 1536 ×...” around 180px despite the right half of the 388px row being empty. Let the labels stack occupy the available horizontal row width so everyday text remains recognizable. The hidden empty-state label also still appeared in accessibility output beside the visible image row; this remains a low-priority accessibility observation. Requested these focused changes and handed UI control back for the reliability reviewer. No further broad usability redesign requested.

### Row and accessibility source follow-up

Independently inspected the final targeted source changes: the labels stack now has low horizontal hugging and a trailing constraint to the cell's inset, and populated results clear the hidden empty label text while suppressing its accessibility element. These directly address the two remaining observations. No additional usability blocker identified in this focused source recheck; final native row-width verification is handed to the reliability reviewer's already scheduled pass.

## Final smaller-panel native recheck

The user requested a still smaller primary surface and full preview on Space. Independently inspected the final native build using `/tmp/palette-native-final` with five synthetic samples; no copies, deletes, settings changes, or new captures were performed.

**Passed:** the panel remains **380 × 380**. Down then Space replaces the history list with a useful full-area image preview; Down while previewing advances to the next text preview; Space returns to the same selected history row. Space followed by Command+F returns to the list with search focused. The More button opens its three-item native menu, and Escape closes that menu. Rounded lavender selection, compact rows, and the overlapping-squares identity remain coherent.

The prior row-width follow-up is closed in native runtime: “Image · 1536 × 1024” now fits fully, while long text uses the available row width before truncation. Hidden empty-state text no longer appeared in accessibility output. No expansion, unexpected second panel, or additional usability blocker was found in this focused final pass.

Fresh multi-app source attribution is outside this pass: existing sample labels included ChatGPT and Steam Helper, consistent with the previously documented automation foreground limitation. UI control was handed back for the coordinator's final privacy and failure checks. No automated tests created or run.

## User-directed final compact interaction recheck

The latest user direction removes primary Copy/Paste buttons, footer, count, and status/empty messages, and asks for compact rows with hover + Command+C reuse. Independently inspected the **340 × 300** native panel with six synthetic items in the paused `/tmp/palette-native-final` profile.

- Six one-line rows and source icons fit clearly, with no primary action buttons or status/footer region. Space replaces the list with full-area text preview and returns to the list. Settings is a clear **360 × 300** native sheet; Escape closes it and restores search.
- **Hover copy passed through real native interaction:** clicked the URL row to leave the pointer there, pressed Down to select the image row, then Command+C. Pasting into a newly created TextEdit scratch document (`Untitled 6`) produced `https://example.com/`, proving pointer-target copy takes priority over keyboard selection as requested.
- **Native text copy passed:** with the pointer in search, selected search text `ordinary` and copied/pasted into the scratch document; only `ordinary` appeared. Selected `privacy` within the text preview and copied/pasted; only `privacy` appeared. These operations did not restore whole historical items.
- A concrete source concern from reliability review was accepted: ordinary Space typing in the search field must remain native even if the pointer is over a row. The coordinator changed this to require non-search focus for Space preview and will perform the focused native recheck after rebuilding. Hover override remains specific to Command+C.

No further layout or copy-interaction blocker found. The excluded-app placeholder truncates slightly (“No excluded ap...”) but remains understandable. Native source attribution was not reverified in this pass. UI control handed back for final rebuild, commit, and installation. No automated tests created or run.

### Final search-space closure

The coordinator reports the rebuilt 340 × 300 native app passed the exact focused scenario: click a row and leave the pointer there; Command+F; type `ordinary`; press Space; type `privacy`. Accessibility output showed the complete query `ordinary privacy`, one matching result, search still focused, and no preview. This closes the search-Space concern against coordinator-supplied native evidence. The excluded-app empty placeholder is now the untruncated “None.” No remaining substantive usability finding is open.
