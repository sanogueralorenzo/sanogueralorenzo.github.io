# Boats ’n’ Beasts

- For visual work, use `./run.command --preview`: production art, no voyage. It watches edits; C# rebuilds automatically, shaders refresh without a build. `--once` disables watching.
- Start with one representative island and boat at gameplay scale. Check other shapes/sizes only for a concrete concern. Prefer shared geometric guarantees and bounded, seeded proportions over per-island exceptions.
- Keep art generated in code; do not import assets or duplicate production rendering in the preview.
- Check only what changed. Gameplay checks are for simulation or interaction changes. Release/export/reinstall only for packaging changes or an explicit installation request, once per batch.
- No default screenshot collection, exhaustive island tours, extended voyages or verification diaries. Record useful evidence and material gaps briefly; stop when focused checks pass.
- Keep this file concise. See `docs/ART_DIRECTION.md` for appearance and `docs/QUALITY.md` for check selection.
