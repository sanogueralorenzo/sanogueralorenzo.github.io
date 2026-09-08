# Independent map and atmosphere review

Latest scoped verdict: the two identified map findings are corrected in a fresh S6/S7 normal-camera restart. The lighthouse now has a connected stone jetty, and Gardens has broken-up retaining walls with irregular planted/vine groups. No new court occlusion was observed. See the final recheck below; initial findings remain historical evidence.

Reviewed 2026-09-06 with Godot 4.7.2 Forward Plus on the reviewer's isolated port 45902/profile `3d-visual-maps`. This review covers normal authored-camera replays of S3 golden-hour Marea, S4/S6 Harbor and S7/S8/S9 Gardens. It does not inherit the representative-coast scoped pass as blanket approval of new maps.

## Save provenance and evidence boundaries

For replay access only, copied `/Users/mario/Library/Application Support/Godot/app_userdata/Spike Season/review-fairness-late.json` to `review-3d-visual-maps.json`. The source is historically earned review progress with unlocked=9 and crowns 1–9, SHA-256 `e57b1889106419c99f97d03c72c8a47d55bfb1820870fb6e739fd9b3b765ae3a`. No unlock/score fields were edited. This copy establishes access to replay these visual variants; it is **not evidence that this reviewer freshly won all nine championships in the 3D build**.

Used ordinary `menu play`, pause/leave, and state/capture review commands. All included images have camera inspection false and simulation speed 1.0. Captured serve and ordinary rally frames for each requested season. No debug camera, game-source edits, automated tests or score overrides. The reviewer operated only their own runtime.

| Season | Rally phase | Match seconds | Observed FPS at capture request | Evidence |
|---|---|---|---|---|
| 3 | attack | 5.7 | 49 | `map-review/s3-normal-rally.png` |
| 4 | attack | 5.9 | 43 | `map-review/s4-normal-rally.png` |
| 6 | set | 4.8 | 39 | `map-review/s6-normal-rally.png` |
| 7 | attack | 5.8 | 44 | `map-review/s7-normal-rally.png` |
| 8 | attack | 5.8 | 45 | `map-review/s8-normal-rally.png` |
| 9 | attack | 5.8 | 45 | `map-review/s9-normal-rally.png` |

The corresponding serve and rally state JSON files accompany each image in `map-review/`.

## Findings

**P2 — Harbor lighthouse lacks a supporting offshore foundation.** The lighthouse roof now fits normal framing, and the tower is a useful distinct landmark. However, its base appears to float offshore. Source places the tower at `(-19.6,0.1,-47)` above ocean height -5, while the breakwater box spans approximately Z -35.5 to -30.5. It does not support the tower footprint. Add a tapered stone islet/foundation extending below the waterline or connect a pier/breakwater to that location. `s4-normal-rally.png` and `s6-normal-rally.png` show the base and surrounding water. This is a concrete scene-placement defect, not a player occlusion or fairness issue.

**P2 — Gardens' long bare retaining walls limit the inviting garden character.** The orchard, fruit, pergolas, fountain and flower borders distinguish this venue from coast and harbor. The reduced orchard density leaves court action open. Nevertheless, two broad uniform green-gray wall bands dominate the backdrop, with very regularly spaced hanging vine bunches. The scene reads more utilitarian than the reference's interleaved architecture/planting. Break the lower wall with a few coherent planted or buttressed sections and cluster vines asymmetrically. Preserve a quiet readable background behind the ball; adding many tiny repeated props would not address the large mass. This is an art-polish finding, not a functional blocker.

**No environment obstruction of the playable court was observed in the captured ordinary rallies.** Trees, rails, bollards, planters, benches, moored boats and pergolas stay outside the athlete/ball court space in these views. Tall map landmarks do not cover active players. The actual dark net and cream timing/rival UI remain readable. This is bounded observation of ordinary serve/setup/attack framing, not exhaustive coverage of every deep dive or camera extreme.

## Atmosphere and map distinction

- **S3 golden hour:** warm sky and longer leaf shadows clearly distinguish the atmosphere; white court lines, yellow jerseys, teal rivals and the ball retain usable contrast. It preserves an inviting summer setting.
- **S4 Harbor:** open sea, striped lighthouse, fishing boats, maritime warehouses, bollards and lantern strand give an immediately different venue identity. Lighthouse top is no longer cropped. Boats are visibly simple procedural forms but recognizable at gameplay scale.
- **S6 Harbor dusk:** violet/warm sky, longer shadows and illuminated lanterns distinguish evening while leaving the court bright enough for reading movement and contacts. No unacceptable darkening of players was observed.
- **S7 Gardens:** greener ambient light, citrus trees, pergolas and fountain create an orchard courtyard. The fountain is now visible left of center beyond the net; the near court is not obscured by its water arcs.
- **S8 Gardens overcast:** cooler, softer values and subdued sky are distinct from S7/S9. The ball remains visible against the steps and wall, and rival jerseys retain separation. It remains playable lighting rather than dark storm spectacle.
- **S9 Gardens warm finale:** warmer sky/court and large leaf shadows distinguish the final variation while retaining ball/team contrast. All three Gardens variants share geometry as intended.

## Performance observation

Capture request telemetry ranged from 39 to 49 FPS. A separate eight-second read-only sample without screenshot readback recorded 30–34 FPS with phase `point` and match time fixed at 65.4 seconds; this is a terminal display observation, not active-rally throughput. It is preserved in `map-review/performance-observation.json`. Four Godot runtimes were active during this review: the reviewer on 45902, the parent on 45901, advanced review on 45903, and an older comparison runtime on 45911. Therefore these readings do **not** establish isolated performance or a hardware-independent minimum. They do justify keeping the earlier optimized batching intact and obtaining a single-runtime benchmark if final performance claims are made. This reviewer did not stop other people's runtimes.

## Scoped verdict

The requested variants demonstrate distinct map identities and usable normal-camera gameplay lighting; no new map-related player/ball occlusion was found in this bounded check. Harbor's unsupported lighthouse base needs correction. Gardens' wall composition merits a focused art pass. This is not blanket approval of the full visual target: the same limits around simplified procedural cloth, scenery masses and reference-level painterly craft remain. No claim about fun, winning/losing runs, fresh unlock progression or every possible rally pose follows from this map review.


## Final S6/S7 map-correction recheck

Restarted only the reviewer's own port 45902 using the same copied-earned replay profile `3d-visual-maps`; provenance above still applies. Fresh evidence `map-review/final-s6-normal-correction.png` and `map-review/final-s7-normal-correction.png`, plus corresponding state JSON, shows ordinary authored-camera attack frames at speed 1.0. No debug camera or game-source edits.

- **Lighthouse support resolved.** A visible stone jetty connects the tower base to the existing breakwater. Source places its supporting mass at `(-19.6,-2.4,-40)` with dimensions `(5.4,5,19)`, so it reaches the lighthouse footprint and extends below the ocean. The ordinary S6 image no longer has an unsupported floating base.
- **Garden wall repetition improved enough to resolve the scoped finding.** Visible buttresses divide the lower retaining wall; planted bays and less evenly spaced, varied-length vines break the formerly repeated pattern. Fountain/pergola/tree identity remains clear. The court and ball trajectory remain open in the S7 frame.
- **No new obstruction or lighting regression observed in these two frames.** Six athletes, dark net strands, ball, white lines and HUD retain usable contrast. Other variants were not redundantly rechecked because the change concerns shared geometry, with no indicated atmosphere alteration.
- **Variant reuse is confirmed in source, not claimed as a separate runtime allocation measurement.** `presentation.gd.refresh()` returns early for an already built map, applies season lighting and Harbor `set_evening()` changes, and does not regenerate venue geometry for a variant-only change.

**Scoped result: both reported map corrections pass this focused normal-camera recheck.** This is approval of those finite defects and observed readability; it does not expand the prior visual-fidelity or performance claims. This reviewer stops their runtime so the parent can measure performance without this extra renderer.
