# Focused verification

Check the changed behavior, then stop.

| Change | Check |
| --- | --- |
| Docs | Review diff and links. |
| Art or shaders | Use `./run.command --preview`; inspect one representative island and boat. |
| Procedural geometry | Check shared invariants and the affected edge case. Use a focused deterministic check when useful. |
| Simulation or interaction | Build Debug and check the affected behavior in a short voyage. Check streaming only when its logic changes. |
| Packaging or requested installation | Build Release, export, install and verify launch/signature once per batch. |

Preserve deterministic generation, bounded placement and caches, shared coastlines, positive shelf widths and prop clearance. A preview checks appearance, not every seed.

Report the result and material gaps briefly. Capture evidence only when useful for a comparison or bug. Keep verification history in Git; do not add recurring checklists or require gameplay/reinstallation for visual tweaks.
