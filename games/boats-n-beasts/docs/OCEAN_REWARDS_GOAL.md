# Sparse ocean rewards — 2026-09-09

Keep the sea spacious while giving island exploration an occasional reward. The user's barrel concept is inspiration only; all shipped art remains procedural native geometry.

## Acceptance

- Replace floating treasure with one beach-edge chest on about 15% of offshore islands. Leave the home waters free of guaranteed loot. Chests must sit on land, remain visible in a clear patch, and be collectible from the boat without landing. Use a subtle glint and 35–55 gold per chest.
- Small wooden barrels are occasional open-water pickups: a 20% candidate chance per chunk, at most one per chunk, at least 900 units apart, with additional clearance around shores and other encounters. Rejected placements are omitted. No barrel groups, chart icons, overhead markers or persistent labels.
- Sailing through a barrel breaks it with a small splash and wooden fragments, awarding 3–6 gold. Both rewards show only a brief local `+gold` number. Depletion persists through chunk unloading and revisits within the voyage.
- Seed and coordinates determine placements independently of travel order; keep streaming and visual caches bounded. Preserve the island families, monster behavior and 22-minute boss progression.
- Verify Debug/Release builds, native appearance at normal camera scale, actual barrel contact, reachable island treasure, depletion/revisits and sparse exploration. Record evidence and limits in QUALITY.md, then commit and push to main. No automated tests or gameplay-state injection.

## Implemented and verified

The placement, rewards and restrained UI above are implemented. Two ordinary native voyages verify a small headland and a giant crescent chest, barrel contact, clear open water, reward amounts and persistence after unloading/revisiting. The final chest uses gold framing to separate it visually from a barrel. Debug/Release builds and both runtime logs are clean. [Evidence](../evidence/README.md) and [QUALITY.md](QUALITY.md) record the final captures, earlier pre-trim proof and coverage limits.
