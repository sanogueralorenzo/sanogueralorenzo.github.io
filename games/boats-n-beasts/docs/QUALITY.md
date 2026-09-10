# Verification

## Fast iteration

Choose checks based on the changed behavior. Stop when those checks pass; do not expand every change into a full game review.

| Change | Default check |
| --- | --- |
| Documentation | Review the diff and links. No build or game launch. |
| Procedural art, materials, shaders or proportions | Run `./run.command --preview`; inspect one representative island with the boat at normal scale. No voyage, Release build, export or reinstall. |
| Shared coastline generation or geometry bounds | Review the shared invariants; inspect a small, large or concave example only when the changed logic affects that case. Focused deterministic checks are appropriate for geometry guarantees. |
| Movement, collision, camera input/projection, encounters or combat | Build Debug and check the affected behavior in a short ordinary voyage. Check streaming/revisits only when placement, streaming or cache ownership changes. |
| Packaging or requested installation | Build Release, export, install and check launch/signature once at the end of the batch. |

The preview uses production geometry, materials and camera code without creating a Voyage. Start with the regression crescent (`B`); use size (`R`), shape (`Space`) and seed (`V`) controls when a specific concern warrants it. Exhaustively cycling every island family is not a default requirement. C# changes need an incremental build and preview restart; this launcher does not hot-reload C#.

`run.command` builds Debug incrementally. It imports resources on first use; add `--import` after adding or renaming resources, changing import settings, or encountering a missing-resource error. Ordinary geometry and shader edits reuse the existing imports.

## Procedural guarantees

Keep terrain, shallows, collision and chart derived from the same coastline. Use island-relative dimensions with sensible bounds, deterministic seeds, positive shelf widths and full prop-footprint clearance. Prefer these shared guarantees over per-shape exceptions. A preview establishes appearance; it does not prove every possible seed. Add a focused check for a concrete geometry regression when useful, without injecting gameplay state.

## Evidence and reporting

Report what changed, the focused checks performed and material unresolved issues. Save an unedited F12 capture only when useful for a visual comparison or bug; paired gameplay telemetry is useful for behavior or performance claims. Do not require screenshots, runtime-log copies, benchmark measurements or a documentation entry for every tweak. Update documentation when the workflow, intended behavior or a meaningful baseline changes; keep iteration history in Git.

## Visual baseline — 2026-09-10

Procedural pirate ships use the readable flag and height-based health bar. Zoom is 0.70, foreshortening 0.78 and boat scale is 15% above the original proportions. Islands retain rounded coastline offsets, visible inner shallows, prop clearance and the simple sand-to-grass blend. See [art direction](ART_DIRECTION.md) for the current constraints.

The cleanup passed Debug/Release builds and macOS installation/signature checks. Preview examples: [crescent](../evidence/cleanup-crescent.png), [small](../evidence/cleanup-small.png), [large](../evidence/cleanup-large.png). Installed play checked [shore contact](../evidence/cleanup-shore.png), departure, upgrades and [offshore unloading](../evidence/cleanup-offshore.txt). The return check was stopped at the user's request. These are historical checks, not a checklist to repeat for visual tweaks.

## Research provenance

Code and art are original; no proprietary code or assets are imported. These findings describe inspected versions only.

- **Sno:** informed deterministic randomness, bounded placement, clearance and chunk ownership; implementation is independent.
- **Megabonk:** partial [spawning disassembly](megabonk-spawning-disassembly.txt) informed separate spawn income and population targets. [Silver inspection](megabonk-silver-disassembly.txt) established a time gate; initial setup and other reward paths remain unresolved. Our balance and random 45–90-second silver interval are custom.
- **Nova Drift:** demo descriptions informed readable combinations and combat. No implementation or tuning was recovered; our progression uses simple weapon/stat choices.
