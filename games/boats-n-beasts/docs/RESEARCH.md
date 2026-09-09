# Research provenance

Game code and art are original. References inform design; no proprietary code or assets are imported.

- **Sno:** local terrain/placement/population code informed coordinate-local randomness, bounded placement, clearance and chunk ownership. Boats n Beasts implements these independently.
- **Megabonk spawning:** partial installed-binary inspection recovered time-based spawn-credit and target-count arithmetic, with unresolved multipliers. It informed separating spawn income from population targets; our curves, caps, species and balance are custom. [Disassembly](megabonk-spawning-disassembly.txt).
- **Megabonk silver:** inspected enemy-death paths use a time gate, not a per-kill random roll. Initial timer setup and other reward paths were not fully recovered. Our independent 45–90 combat-second interval is custom; the next eligible kill awards silver and resets the timer without catch-up drops. [Excerpts and binary hash](megabonk-silver-disassembly.txt).
- **Nova Drift:** local demo descriptions informed readable combinations and satisfying combat. No combat implementation or numerical tuning was recovered. Progression remains simple weapon/stat choices, without prerequisite trees.

These findings describe the inspected versions, not a complete reconstruction or a claim about current releases.
