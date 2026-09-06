# Independent fairness and progression review

Reviewer: independent fairness agent. Date: 2026-09-05.

Method: source inspection and reviewer-chosen commands to a running Godot 4.7.2 game through its opt-in localhost review console. No automated tests, gameplay bots, score overrides, or unlock overrides were used. The review profile is separate from ordinary player progress. Accelerated time is explicitly identified below.

## Final verdict

**No remaining blocking fairness or progression defect was demonstrated after the reviewed corrections.** Actual play established consequences for stale placement, short-shot repetition, a blocked hitting route, and slow attacks against later defenders. It also established viable counters: changing lane, alternating short and deep attacks as the defense moves, selecting another hitter, and choosing a relevant temporary upgrade. Opponents retained finite movement, reach, and landing recovery; the observed late-game losses had visible physical causes.

The late game is a readable tactical puzzle. A reviewer who understands the depth and lane memories can win decisively without contact timing. That is compatible with the automatic-contact accessibility goal, but these assisted runs do **not** establish a high competitive skill ceiling, ordinary unpaused execution difficulty, or long-term enjoyment. The season-nine final included an 18-contact rally in which upgraded rolls were returned; changing to a tip after the defenders retreated ended it. A good choice was consequential, while a selected upgrade did not turn every repeated attack into a point.

All six later championships were independently earned, then all nine saved crowns and the season-nine replay reset were verified after a process restart. Seasons 1–3 in that later profile originated from the lead reviewer's earned file; this reviewer additionally completed a separate season-one championship and restart check. The records below distinguish that provenance.

## Findings raised and addressed

- Initial attack travel budgets let settled wings cover every target. The director shortened attacking flights and introduced map/season defensive formations and lane memory. Runtime now produces open-court points and block points; the original static coverage guarantee no longer applies.
- Initial receive timing was discarded before the attack. The revised `perform_attack` weights receive, set, and attack quality at 20%, 30%, and 50%. This is a real mechanical connection, although the magnitude of its benefit remains situation dependent.
- Court vision originally displayed information without an actionable response. Matching defensive aim to the displayed rival lane now reduces reaction delay by 0.13 seconds.
- The initial scouting text overstated behavioral differences. Opponents now vary formation depth/spread and introduce recent-lane and frequency memory. Shared movement and block reach limits remain explicit.
- Run-local longest-rally and lane-history values now reset on replay. A manual replay returned `best_rally` to zero.
- The first revised runtime still depended materially on render frame duration: at 4x speed and about 29 FPS, power into a committed block sustained 60 contacts without a point. Changing that same rally to 1x led to a block loss after contact 63. Reaction expiration was crediting an entire frame of movement. The director subsequently introduced fixed 120 Hz simulation and fractional reaction expiration. The post-fix comparison is recorded below.
- Advice to use the far landing lane against a same-side block was geometrically misleading: deep shots from one outside hitter cross a narrow part of the net regardless of chosen landing lane. The advice now recommends a roll or another hitter.

## Runtime evidence

### Defeat and replay

Before the fixed-step correction, season one with Sunkeepers, automatic contacts, middle aim, power, and the default attacker ended 0–5. All five losses were blocks. The result screen was `defeat`, unlocked seasons remained one, and upgrades were empty. Selecting play again started a fresh match with zero score, empty ledger and upgrades, and zero longest-rally count.

### Post-fix speed comparison

After restarting on the fixed-step implementation, the same stationary selections at both 4x and 1x ended 0–5 at exactly 43.7 simulated seconds, with the final point at 41.7 seconds. Every scoring rally had three contacts. The last three point timestamps matched at 24.3, 33.0, and 41.7 seconds. The former long block/save loop did not recur. This narrow deterministic comparison supports the correction; it is not an exhaustive frame-rate certification. Telemetry reported 60 FPS during the completed normal-speed comparison.

### A meaningful route decision

A fresh season-one run kept the same middle power and automatic contact selections, changing only the chosen attacker once before the first set. At 4x, the quarterfinal ended in a 5–1 win at 68.0 simulated seconds, compared with the 0–5 loss above. The last three winning rallies each had six contacts and ended at 41.0, 53.5, and 66.0 seconds. The upgrade screen offered Sand instincts, Soft touch, and Court vision. I selected Court vision, and the semifinal began at zero score with `read` in the temporary upgrade list. This demonstrates consequential attacker selection and functional draft transition without contact timing; it does not establish that Court vision itself caused a point.

### Additional substantive block-loop finding

The following semifinal exposed a remaining center-route block/save loop after the fixed-step correction. With the same middle-power selections, the score stayed 0–1 while the second rally reached 190 contacts at 191.2 match seconds. I changed only playback from 4x to 1x. The same rally continued to 232 contacts at 230.7 seconds. At that point I selected roll; the rally finally ended at 255 contacts and 257.8 seconds, with an opponent open-court point. The point therefore does not demonstrate that unchanged power would have escaped its loop.

The center hitter could cover its own downward block because the rebound was only approximately 1.415 m from the hitter, inside reach plus post-reaction movement. I reported this as a substantive pacing/physical-fairness issue and recommended shared per-athlete landing recovery after a spike, allowing other teammates to cover while preventing the airborne hitter from immediately sprinting to its own rebound.

Changing to right tip subsequently produced Sol points at 266.9 seconds (three contacts) and 279.6 seconds (six contacts), tying the match 2–2 at normal speed. This supports tactical agency but does not excuse the unchanged-choice loop. Capture: `/tmp/spike-fairness-review/postfix-semifinal-loop.png`.

**Corrected-build recheck:** I restarted after shared per-athlete recovery was added: spike 0.48 seconds, set 0.20 seconds, block 0.40 seconds, and dig 0.10 seconds. The same quarterfinal again ended 5–1. After selecting Court vision, the unchanged middle-power semifinal now finished 5–2 at 72.9 simulated seconds, with a longest rally of six contacts for the entire replayed run. The ledger included block and open-court points. This was reviewed at 4x on the fixed-step engine. The targeted center-block loop is resolved in demonstrated runtime behavior; this is not proof that every possible stationary-input cycle is eliminated.

### Championship, saved unlock, and replay

The earlier mixed-speed season-one run completed all three matches: quarterfinal 5–1, semifinal 5–2 after changing to right tip, and championship 5–1 after changing to left tip against the right-side block. I chose Court vision and then Perfect connection. The final match took 64.8 simulated seconds at 4x. The result state was `champion`, with `unlocked: 2` and `crowns: [1]`.

The actual isolated progress file contained version 1, unlocked season count 2, and crown 1. After terminating and relaunching Godot on the same profile, the introduction retained those values. Replaying season one started with zero score, no upgrades, an empty ledger, and longest rally zero. Thus the reviewer independently demonstrated one complete championship, next-season unlock, persistent save/restart, and replay reset. This run contains the explicitly documented old center-block loop and must not be presented as an example of tuned overall run duration.

## Scope limits

The normal-speed comparisons, losses, and restart checks above are narrow demonstrations. Later championship decisions were assisted by pauses and playback control, as described below. Timing-window feel and ordinary controller/keyboard responsiveness require the separate native-speed review evidence. Enjoyment and long-term tactical depth are subjective and are not certified by these observations.

## Independent later-season progression — before shot-depth adaptation

The lead reviewer provided an actually earned profile with seasons 1–3 crowned and season 4 unlocked. I copied that file byte-for-byte to the isolated `fairness-late` profile; no unlock data was edited. Later unlocks below were earned through complete normal championship transitions.

- **Season 4:** Won 5–0, 5–3, and 5–1; selected First step and Sand instincts. Total 239.0 simulated seconds; longest rally nine contacts. Static right tip fell 0–3 in the semifinal; alternating left/right tips recovered to win. No contact timing was used. Portions were reviewed at 1x and portions at 0.25x/0.5x. Champion evidence: `season-04-independent-run.json`, unlocked 5.
- **Season 5:** An uncontrolled 2x attempt ended 3–5 while several points elapsed between reviewer decisions; this is not evidence of unwinnability. A deliberate replay won all three matches 5–0 using only alternating left/right tips, no timing, no attacker switches, and no shot changes. Selected Court vision and First step. Total 184.2 simulated seconds; longest rally six contacts. Historical champion evidence: `season-05-pre-adaptation-run.json`, unlocked 6.
- **Season 6 partial review:** Frequency memory punished one blind alternating tip at 4–0. That wrong-lane tip was returned, and the rival won a nine-contact rally. Returning to the opposite-block tip won the quarterfinal 5–1. The same opposite-block-tip approach led the semifinal 3–0, again through six-contact rallies. The lead developer requested stopping this pre-adaptation run. `season-06-pre-adaptation-review.json` is a paused partial run, **not a season-six championship**.

For deliberate season-five/six review, I paused between decisions, selected each input from the observed state, and resumed short rendered 4x play intervals before the next inspection. These are assisted tactical/flow observations. There was no gameplay decision bot, automatic assertion, score alteration, or unlock alteration. They do not demonstrate ordinary unpaused input responsiveness.

**Substantive challenge finding:** Lane memory alone left an overly narrow solution: tip into the lane opposite the announced block. Rivals never moved their deep wings forward in response to repeated tips, so shot variety, attacker choice, and contact timing were unnecessary for the demonstrated perfect season-five run. I recommended a visible physical depth adjustment after repeated short shots, exposing deep space in exchange for covering tips. The developer implemented that adjustment from season five, and I restarted and replayed the affected seasons on the corrected gameplay revision. The historical records above remain explicitly pre-adaptation evidence.

## Final gameplay revision: independently completed seasons

The short-shot memory now moves the rival wings forward after repeated short attacks. This is a positional tradeoff rather than a hidden speed or reach increase. The following records contain full native runtime state and complete per-point ledgers. Times are simulated match/run time, **not** ordinary wall-clock play duration.

| Season | Quarterfinal | Semifinal | Championship | Run seconds | Longest rally | Chosen upgrades |
| --- | --- | --- | --- | ---: | ---: | --- |
| 4 | 5–0 | 5–3 | 5–1 | 239.0 | 9 | First step, Sand instincts |
| 5 | 5–0 | 5–0 | 5–0 | 193.3 | 9 | Court vision, First step |
| 6 | 5–0 | 5–0 | 5–0 | 185.3 | 6 | High horizon, Heavy hand |
| 7 | 5–1 | 5–1 | 5–0 | 218.9 | 15 | Heavy hand, High horizon |
| 8 | 5–1 | 5–0 | 5–0 | 196.9 | 9 | High horizon, Perfect connection |
| 9 | 5–0 | 5–1 | 5–0 | 212.0 | 18 | Together, faster, High horizon |

Evidence files: `season-04-independent-run.json` through `season-09-independent-run.json`. Season 4's gameplay was unaffected by the later season-five-and-up adaptation patch. All season-five-through-nine rows are from the corrected gameplay revision.

Specific late-game observations:

- In season 5, shallow wings returned repeated tips. The forgiving opponent then lost several counterattacks to automatic blocks, so tip-only play could still win this introductory adaptive opponent. Switching to deep rolls or power produced six-contact open-court points; changing hitters avoided the committed block.
- In season 6, blind alternation was countered by frequency memory in the historical review. In the corrected review, inducing short coverage with tips, then switching deep, produced wins. The final also used a hitter switch when the frequent-lane block moved to that hitter's route.
- In season 7, the third stale tip was returned and the rival scored with power after nine contacts. Two automatic deep rolls were returned during a later rally; power with another hitter ended that 15-contact rally. An incorrect hitter-switch prediction in the semifinal was blocked for a real loss. High horizon subsequently made deep rolls more effective against short coverage.
- In season 8, even the opening automatic tip was dug, and the rival's power found open court. After moving the defense forward, another hitter's deep power scored. Upgraded rolls and tips into reopened short space completed the run.
- In season 9, both an automatic Sol block and a rival open-court power point occurred in the semifinal. The final's upgraded rolls were eventually dug; changing to a tip after the defense retreated ended an 18-contact rally. No contact-timing input was required to win, but stale shots and wrong routes did not universally succeed.

## Final save, all-nine selection, and replay

After the season-nine champion screen appeared with all nine crowns, I terminated Godot and relaunched the same `fairness-late` profile. The season-selection screen visibly retained all nine checkmarks and unlocked replay buttons. `all-nine-save-restart.json` records `unlocked: 9` and crowns 1–9 after that restart.

I selected season nine again through the ordinary start-run function. `season-09-replay-reset.json` records round one, score 0–0, no temporary upgrades, an empty ledger, and longest rally zero, with all nine crowns preserved. The opening rally then ran at 1x for the latest visual capture; it was paused afterward.

Visually inspected evidence:

- `season-09-champion.png` — actual final champion screen; captured immediately before the final visual-only restart.
- `all-nine-crowned-seasons.png` — all nine saved crowns after restart.
- `latest-citrus-gameplay.png` — fresh 1x season-nine replay on the latest visual source, all six athletes visible, rounded pose shadows and updated shoreline.
- `historical-citrus-gameplay.png` — prior visual revision, retained and labeled historical.

The final visual-only changes did not alter the gameplay algorithms exercised by the championship ledgers.
