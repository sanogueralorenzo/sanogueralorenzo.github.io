# Boats ’n’ Beasts

- Keep changes small. Simulation belongs in `source/core`; presentation and the preview share production rendering.
- Generate art in code; do not import assets. Keep procedural guarantees beside their implementation.
- Iterate visually with `./run.command --preview` and one representative island at gameplay scale. Check other shapes only for a concrete concern.
- Check only what changed, then stop: diff/links for docs, preview for art, a short voyage for gameplay. Build Release and reinstall only for packaging changes or an explicit request. No routine evidence collection or exhaustive tours.
- Keep docs concise and current. Store tuning in code and completed work in Git history.
