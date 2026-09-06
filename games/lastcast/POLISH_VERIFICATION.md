# Last Cast — polish verification

Verified September 5–6, 2026 in the exported Godot 4.7.2 macOS app, GL Compatibility, Apple M3 Max. No automated tests were created or run. The original build record is [VERIFICATION.md](VERIFICATION.md); the results below are fresh checks of the revised project.

## What changed

The sailor now uses authored procedural anatomy, tailored clothing, articulated limbs and hand targets, with walking, steering, casting, reeling and landing poses. The skiff has a curved double-skin hull, fitted timber interior, ribs, rails, motor, connected tiller grip, buoyancy and feathered wake. The diagonal follow camera frames the boat and receding coast at a reference-like scale.

The harbor has smaller irregular paving, varied pastel rooflines, furnished shopfronts, layered vegetation, rounded coastal stones, connected stairs and expanded hillside architecture. Water uses quieter irregular ripples, depth transparency, a sloping seabed and restrained caustics. All geometry, textures, animation and audio remain generated locally. The supplied reference is not bundled.

Fishing uses a compact instrument card and projected fish/hook cues. Held counter direction, reel state, tension, fatigue and remaining signature reads remain visible. Optional detailed guidance is saved. Landing lifts the fish before showing the result; rescue, banking and new trips clear pending reveal state. Existing deterministic fishing rules, economy and version-1 saves are preserved.

## Fresh runtime results

| Flow | Demonstrated result |
| --- | --- |
| Fresh introduction and shore economy | Started at zero shells; banked three summer shore bream for 72; bought the 65-shell boat. No money or unlocks were seeded. |
| Harbor movement | Walked between piers and shop, purchased equipment, ascended to the upper stair landing at y≈3.25 and descended. Precise stair positioning used Focus pace. |
| Boat movement | Normal forward, reverse and turning; pier collision, boarding and repeated docking. A fully blocked hull now reports zero speed. Recorded coastal translation shows the corrected wake. |
| Shore and boat fishing | Fresh shore bream, offshore Sunscale Mullet, winter shore Moonpetal Koi and Stormglass Sailfish, plus a later boat bream. Shore signatures remain valuable after buying a boat. |
| Signature skill and unlocks | Sunscale banked for 70 and opened Jade; winter koi banked for 208 and opened Stormglass; winter sailfish banked for 304 and completed winter mastery. Each landed signature recorded two clean dash reads. |
| Fairness and recovery | Missed strikes spent one bait only. The winter koi visibly stopped at 92% with one response remaining; its feint reversed the counter arrow and a later correct release/read allowed landing. Rising tension cooled when the reel was released. |
| Upgrades and purchases | Patient hook + Golden hour added 75 seconds after the second catch. Silk leader combined with the permanent rod; Quick spool was used on another trip. Both rod and creel levels were purchased, reaching ten catch slots. |
| Successful expedition | Returned and docked the offshore signature, then banked it. Selling emptied the basket, ended the trip and saved income/unlocks. |
| Rescue | Reload retained an unbanked bream; confirmed rescue then lost that fish (24 shells) while preserving 344 banked shells, boat, rod 2, creel 2, both region unlocks and winter mastery. |
| Saving and replay | Reloads retained fresh earned purchases, unlocks, catch, remaining daylight, bait and perks. An interrupted cast was released without refunding its spent bait. New trips restocked eight bait and full daylight. |

Automatic sunset was separately verified on day 7: a visible return warning preceded expiry; one unbanked bream (24 shells) was lost, while all 344 shells and permanent progress survived. Day 8 then began with four minutes, eight bait and ten catch slots. Autumn showed Red Mullet as the current common quarry. The empty replay was docked and banked to finish in harbor.

## Input and evidence limits

Desktop input/observation latency sometimes exceeded the normal hook window. Signature presentation and required dash responses used the built-in Focus pace and manual observation pauses. Their final retrieves included normal pace with pauses. They prove the rules and feedback, not unassisted expert execution.

The later common-fish recordings include an uninterrupted normal-pace fight with purchased gear, after an assisted hook setup. Other fresh beginner fights included normal-speed portions. There is no claim that every full catch was completed at normal pace from cast to landing. No independent human playtest established subjective fun. Agent reviews assessed concrete controls, fairness, readability, visuals and sampled animation rather than substituting approval for play evidence.

Videos use Godot MovieWriter at fixed engine frame rates; they are not live performance measurements. Some desktop window captures became stale while the game continued; resizing refreshed the surface. Those stale observations are excluded. A long recording attempt was interrupted and its unfinished cast resumed safely as released; shorter recordings supplied the accepted motion evidence.

## Independent review and fixes

Separate agents reviewed equivalent views against the reference and audited fishing fairness/readability. Substantive findings were fixed and rechecked: hollow mesh winding in the sailor; obscured boat interior; shoreline dropping out of the follow view; underwater terrain seams; missing signature-gate guidance; invisible latched steering; stale landing state after rescue; Focus-stretched cosmetic timing; fish hidden behind the pier; backface-culled edge foam; and a large-fish hold intersecting the dock.

Final moving frames show upward-facing lateral foam and rounded propwash. Sampled landing frames show line-connected approach, lift over the gunwale and horizontal jaw hold without observed body/deck clipping. The large sailfish still confirms full fish clearance. The result card partly obscures the completed small-fish pose. Review identified no remaining substantive defect in those final captures; this is not a claim of pixel-identical reproduction of the reference.

## Performance and launch checks

Normal native 1280×800 F12 samples generally ranged around 35–60 FPS, with final open-water and fishing samples commonly 50–60 FPS. The final winter shore fight samples reached 60 FPS at roughly 16.6–19.4 ms CPU process time. Harbor views are heavier. Screenshot readback can stall a capture frame, so isolated CPU spikes are not benchmark averages. A later maximized-window check was substantially heavier (roughly 19–30 FPS); the default 1280×800 window is recommended. Samples taken while the desktop surface was stale are excluded. No locked-60-FPS guarantee or broader hardware claim is made.

The final source passed Godot headless parsing, a release export, and `git diff --check`. Runtime logs were inspected for script/render errors. Launch instructions and controls are in [README.md](README.md).

## Evidence

See [the evidence index](evidence/polish/README.md) for before/after images, short recordings, earned save milestones and the local voyage-event excerpt. These are ordinary gameplay captures; the reference image is comparison-only.

The original pre-polish local save was restored after verification. The fully earned final replay (344 shells, boat, rod 2, creel 2, both region unlocks and winter mastery) is preserved in `evidence/polish/final-earned-replay-save.json` and as `last_cast_after_polish_verified.json` beside the local save. No pre-existing save backup was removed.
