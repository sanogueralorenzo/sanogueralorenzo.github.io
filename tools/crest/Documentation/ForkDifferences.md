# Fork differences

These are the intentional product differences from upstream Crest. They describe the current behavior, rather than the sequence of experiments that produced it.

## Appearance and navigation

- Follow system light/dark appearance with monochrome surfaces; no themes or palettes.
- Use a frameless Mac window and a hover-only sidebar, with 32-point reveal and dismissal margins. Keep the sidebar visible in empty Spaces. Leave native window controls in their standard macOS positions.
- Use six fixed, bright Space color dots, one Space editor, and direct Space deletion.
- Keep navigation, search, the More menu, and compact Now Playing controls at the top. Show assigned keyboard shortcuts beside relevant actions.
- Use icon-only pins, inline tab renaming, always-visible saved tabs, and New Tab after the list.
- Keep the solid blue sail and coral sun app icon.

## Fixed browsing behavior

- Open directly into the browser; retain initialization, session recovery, and import in Settings.
- Resume saved and pinned tabs at their last address. Command-W returns a durable tab to its saved address first, then sleeps it and selects the next active page.
- Sleep idle background WebKit pages after five minutes, protecting visible pages, active media, and unsaved edits.
- Delete folders with their nested folders and tabs directly; tabs remain recoverable in Archive.
- Open preview links as regular tabs; retain website sign-in popups. Remove Peek and user-created Quick Windows.
- Remove Space locking, built-in password saving/autofill, configurable external-link routing, per-site engine rules, and tab behavior preferences.
- Keep fixed shortcuts, startup/session restoration, download destination, command-palette behavior, and manual tab archiving.
- Keep one global search provider in General, Google by default. Keep search suggestions off by default with one global switch below the provider; when enabled, send them only to that provider when supported; use history instead of learned choices.
- Keep automatic Picture in Picture, manual developer tools, and optional automatic translation to the language chosen in General, off by default with excluded languages. Remove capture tools and WebKit spelling controls.
- Keep Now Playing without the widget carousel or widget switches.

## Integrations and content blocking

GitHub creates a live folder after sign-in, without requiring a pinned GitHub tab. Refreshes use the Space's session even when GitHub pages are unloaded. New folders include PRs created by or assigned to the person, include drafts, and refresh every 30 minutes. Deleting the folder dismisses automatic creation in that Space; add it again through **More → Live Folder → GitHub**. Private Spaces do not collect results.

WebKit uses expanded, refreshed host blocking and native EasyList cosmetic rules to collapse blocked ad containers, with generic handling of Funding Choices recovery overlays. Bundled lists retain their attribution and licensing notices.

## Upstream maintenance

`origin` is this fork; `upstream` is `pauljoda/Crest`. Keep upstream history and merge updates into `main`; do not replay the old website-repository commits or rewrite published branches.

```sh
git fetch upstream
git merge upstream/main
```

Resolve conflicts against the decisions above, retaining unrelated upstream improvements. Regenerate contracts with `Scripts/control-plane/generate-contracts.sh`, regenerate the project with XcodeGen, and run the affected core, Mac, and iOS checks. Keep removals complete instead of restoring unused choices to settle a merge. Submit generally useful fixes upstream on separate branches based on `upstream/main`.

Upstream release/signing workflows require the upstream team's credentials and a matching published Chromium engine; the local WebKit runner is the supported development path here.
