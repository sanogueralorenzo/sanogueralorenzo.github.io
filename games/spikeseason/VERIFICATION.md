# Runtime verification

This record separates observed behavior, assisted review, source inspection, and subjective judgment. No automated tests, score overrides, unlock overrides, or gameplay bots were used. The opt-in local console sends individual manual inputs through the ordinary game functions and exposes live state and screenshots.

## Environment

Godot 4.7.2, macOS on Apple M3 Max, Compatibility renderer, 1440×900 design viewport rendered in a 1280×800 window. Runtime parser/import checks were clean apart from Godot reporting active synthesized audio playback resources at abrupt headless shutdown. The playable runtime logs were inspected for script errors. Background caching and reducing the painterly shader's sample count brought observed review sessions to roughly 55–60 FPS, with some concurrent final native sessions briefly at 45–57 FPS; earlier simultaneous uncached review instances ran at 26–42 FPS. These observations are not a cross-platform benchmark. The launch script was also exercised from a fresh project-only temporary copy, excluding Cozy Sora, evidence, and the existing `.godot` cache; it launched successfully with the same shutdown-only audio warning.

## Independent reviews

- [Beginner accessibility and agency](evidence/beginner-review.md): no-timing warm-up victory at normal speed; real defeat; replay and attacking-route counterplay.
- [Fairness and advanced challenge](evidence/fairness-review.md): bounded movement and reaction checks, frame-rate dependence, block loops, landing recovery, championship/save/replay, and later-season review.
- [Visual and contact review](evidence/visual-review.md): direct comparison with the supplied art target; ordinary receive/set/attack/block captures; repeated focused rechecks after corrections.

The reports retain earlier failures rather than silently treating the first build as verified. Later follow-up sections identify corrected behavior. Temporary capture paths in the review logs are reviewer working files; selected final images and state records are included alongside this document.

## Demonstrated normal-speed behavior

- A beginner warm-up finished **5–2 in 179.8 seconds without any Space timing input**. Changing to a short tip against the observed coverage turned an initial 0–2 deficit into scoring rallies.
- Repeated power into a committed block finished in an actual **0–5 defeat in 44.1 seconds**. The defeat screen showed no upgrades and retained the unlocked season.
- Replaying that tactic and changing only the attacker generated points at 16.0 and 28.6 seconds, turning the same shot and landing lane into a useful attack.
- The first primary championship finished **5–1, 5–2, 5–1 in 217.1 seconds** at 1x. It exercised both upgrade selections and the championship unlock. This was an earlier tuning build; its duration is historical evidence, not a promise for every run.
- A fresh launch retained earned crowns and unlocked seasons. A replay reset score, upgrades, rally ledger, and longest-rally statistics.
- Independent final contact inspection showed a successful receive meeting the ball and an unreachable ball remaining beyond capped hands before a missed-receive point. See [successful contact](evidence/visual-contact.png), [missed contact](evidence/visual-miss.png), and [supporting live states](evidence/visual-contact-states.json).

## Substantive failures found and corrected

1. Initial settled defenses covered too much court. Faster distinct attack flights and readable formation commitments created actual openings.
2. Receive timing had no downstream effect. Dig quality now affects the attack combination, and excellent digs extend reachable saves within bounded limits.
3. Court vision exposed information without a defensive use. Matching the revealed lane now improves defensive reaction, and aiming also chooses the block lane.
4. Attacker selection was unnamed. The HUD now identifies the teammate and route, and explicitly queues changes for the next set.
5. Low frame rates and accelerated playback shortened reaction delays. The match now advances at fixed 120 Hz with exact partial movement when reaction/recovery expires. Independent 1x and 4x replay of the same stationary inputs produced the same 0–5 result at **43.7 simulated seconds**, with identical point timestamps.
6. Slow blocked-ball rebounds and immediate post-spike movement created long loops. Blocks now drop sharply; both teams share finite landing recovery. The formerly looping center-power semifinal completed **5–2 in 72.9 simulated seconds**, with a longest rally of six, in the focused fixed-step recheck.
7. Hitting animations jumped after contact, hands missed the ball, and receive height snapped between flights. Preparation now precedes contact, bounded two-bone targeting aligns reachable hands, and outgoing passes start at the incoming height. The serve has its own toss and preparation.
8. Enlarging the net initially left its mesh close to the floor. The final net is a suspended band with clear space beneath it.
9. Set/block recovery formerly snapped raised hands into the ready pose. A final independent runtime recheck observed smooth lowering; the shared ready crouch removes a torso reset jump. Pose-derived connected shadows, bark planes, shoreline facets/foam, distinct fringes, and tapered shaded limbs passed the final specific art recheck. See [visual-art-final.png](evidence/visual-art-final.png).
10. Later lane memory alone allowed a dominant alternating-tip strategy. From season five, recent short landings visibly pull the wings forward, exposing deep corners. Independent replay observed tips returned and deep rolls scoring against the shallow formation.
11. Longest-rally statistics leaked across attempts, and review run records could share a filename. Statistics reset per run and records use the active save profile's name.

## Championship progression evidence

The JSON records are captures of actual live championship state and rally ledgers. Early records include tuning builds. Later independent records identify their playback speed and choices in the fairness review. Accelerated or slowed playback establishes flow and tactical consequences; it is not evidence of normal-speed player skill or responsiveness.

| Season | Evidence | Status |
| --- | --- | --- |
| 1 | [season-01-final-run.json](evidence/season-01-final-run.json) | Final simulation replay: 5–1, 5–2, 5–1; 205.7 simulated seconds; Court vision / Perfect connection |
| 2 | [season-02-final-run.json](evidence/season-02-final-run.json) | Final replay: 5–1, 5–0, 5–1; 187.3 simulated seconds; Shorebirds; set / speed |
| 3 | [season-03-final-run.json](evidence/season-03-final-run.json) | Final independent replay: 5–0, 5–1, 5–0; 179.0 simulated seconds; tip / speed; replay reset captured |
| 4 | [season-04-independent-run.json](evidence/season-04-independent-run.json) | 5–0, 5–3, 5–1; 239.0 simulated seconds; tempo / reach; earned season 5 |
| 5 | [season-05-independent-run.json](evidence/season-05-independent-run.json) | Final adaptation replay: 5–0, 5–0, 5–0; 193.3 simulated seconds; read / tempo |
| 6 | [season-06-independent-run.json](evidence/season-06-independent-run.json) | 5–0, 5–0, 5–0; 185.3 simulated seconds; roll / power; earned season 7 |
| 7 | [season-07-independent-run.json](evidence/season-07-independent-run.json) | 5–1, 5–1, 5–0; 218.9 simulated seconds; power / roll; earned season 8 |
| 8 | [season-08-independent-run.json](evidence/season-08-independent-run.json) | 5–1, 5–0, 5–0; 196.9 simulated seconds; roll / set; earned season 9 |
| 9 | [season-09-independent-run.json](evidence/season-09-independent-run.json) | 5–0, 5–1, 5–0; 212.0 simulated seconds; speed / roll; all nine crowns earned |

The final season-seven review observed a stale tip lose after the wings moved forward, unupgraded deep rolls being received, and a changed hitter’s power attack breaking a 15-contact rally. After choosing High horizon, faster rolls scored against shallow coverage. A guessed hitter route also lost to a real block. In season nine, upgraded rolls were still received; changing back to a tip after the defenders retreated ended an 18-contact rally. These observations support meaningful placement, route, and upgrade choices without requiring permanent stat improvements.

All nine earned crowns survived a full Godot restart: [saved state](evidence/all-nine-save-restart.json) and [crowned season menu](evidence/all-nine-crowned-seasons.png). A subsequent season-nine replay began at round one, 0–0, with empty upgrades and ledger while retaining all crowns: [replay reset](evidence/season-09-replay-reset.json). Final illustrations are visible in [Marea Hills](evidence/visual-art-final.png), [Lantern Harbor](evidence/final-harbor-gameplay.png), and [Citrus Gardens](evidence/latest-citrus-gameplay.png).

## Native menus and saved settings

The final introduction, season selection, sound toggle, and reduced-motion toggle were exercised through actual native window clicks. After closing and reopening Godot, the menu displayed Sound: off and Motion: reduced with the same earned crowns and locked-season boundaries. Both settings were then restored through the UI. Native clicks also selected Shorebirds and opened an earned harbor season. Escape paused the serve at 0.0 match seconds through subsequent observations, then resumed correctly. Native keyboard aim/tip/serve input produced a close match that continued at 4–5 and ended in defeat at 4–6 after 125.0 seconds, demonstrating the win-by-two rule ([native-harbor-defeat.json](evidence/native-harbor-defeat.json)). [final-settings.png](evidence/final-settings.png) records the saved choices; review profiles do not alter normal player progress.

## Final timing and failure checks

At explicitly slowed 0.05x playback, a manually timed roll produced EXCELLENT feedback. The rival received it and began setting with four contacts and an unchanged 0–1 score: [timing-excellent-roll-state.json](evidence/timing-excellent-roll-state.json). This demonstrates that perfect timing does not guarantee a point; it does not establish a human success rate at normal speed. A separate near-contact input on an unreachable receive still lost the point (`timed-contact-out-of-reach.png`).

A final-mechanics season-one run won the first two rounds, then lost the championship 2–5 by keeping middle power into the final opponent’s block (`season-01-final-defeat.json`). The loss cleared both temporary upgrades and retained earned season unlocks. A replay with a left tip in the final won 5–1. These deliberate replays ran at 4x; ordinary 1x accessibility evidence is listed separately above.

## Scope of claims

The game is an original procedural illustration inspired by the target's summer atmosphere, team palette, coastal composition, and sports-anime energy. Its characters and lighting remain more stylized and simpler than the supplied image's painterly naturalism. It does not contain external illustrations, textures, models, animations, or audio.

Review observations support accessible agency, readable tactical consequences, and the specific corrected behaviors above. They do **not** certify subjective fun, long-term balance, universal absence of rally loops, accessibility for every disability, or performance on untested hardware. Keyboard play was exercised; gamepad and touch gameplay are not implemented. Audio is synthesized locally; perceptual sound quality remains a subjective judgment.
