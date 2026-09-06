# Independent 3D advanced fairness and progression review

Reviewer: independent fairness agent. Date: 2026-09-06. This is a fresh runtime review after the procedural 3D rebuild and shared physical block-envelope correction. Prior 2D approvals are not treated as current gameplay evidence.

## Method and save provenance

I copied `user://review-fairness-late.json` byte-for-byte to isolated `user://review-3d-advanced.json`. The source contains genuinely earned crowns 1–9: the lead reviewer earned 1–3 and this reviewer independently earned 4–9 during the historical 2D review. The copied data was not edited. It enables late-season replay but is **not** evidence of earning all nine seasons on the new 3D revision.

The native Godot 4.7.2 Metal runtime used port 45903 and `/tmp/spike-advanced3d-review/` for captures. Every input was selected manually by the reviewer through the opt-in console. No tests, gameplay bots, outcome changes, or unlock overrides were created. Ordinary 1x play is separated below from slowed timing inspection and 4x flow verification.

## Ordinary 1x season-nine challenge

I completed the season-nine quarterfinal at ordinary, unpaused 1x with automatic contacts and no upgrades. Result: **9–7 win**, 309.0 simulated seconds, longest rally 57 contacts. This includes actual decision delays; it is not an optimized match-duration benchmark. Full point ledger: `season-09-normal-challenge.json`. Captures: `s09-normal-opening.png` and `s09-normal-quarterfinal-upgrades.png`.

Observed tactical consequences:

- Repeated left tips caused short-shot memory to pull the rivals forward. Some were returned and the rival scored through open court. The opening two point scores were 1–0 and 1–1; the first Sol point came from a rival attack being blocked, not proof that the tip itself was unanswerable.
- Switching to deep right rolls did not guarantee a point. Rivals dug them and scored open-court points, taking the score from 2–1 to 2–3.
- A stale deep-power exchange continued to 57 contacts. A lane change during release sent that attack into the committed block and lost at 163.0 seconds. This was a real late decision, not an intentionally injected failure.
- A short right tip into reopened space scored at 172.1 seconds, followed by another open-court point at 184.4. Later, switching between hitter routes produced both a block loss and a successful open-court attack. Incorrect predictions had costs.
- At 7–7, changing from repeatedly returned deep power to a short right tip ended a 27-contact rally for 8–7. Another six-contact rally produced 9–7. The cap-nine deuce rule worked.

The tactics remain consequential at normal speed and late opponents have real counters. **Pacing caveat:** 57-contact and 27-contact exchanges can occur under unchanged predictable choices. They ended with subsequent choices, so this is not evidence of an unavoidable infinite loop. The five-minute quarterfinal is longer than an efficient championship leg; slower reviewer decisions contributed materially. This does not certify subjective fun or a high competitive ceiling.

## Meaningful timing upgrade; excellent is not an automatic point

The quarterfinal draft offered Perfect connection (passive set quality), Quiet confidence (timing window), and Together, faster (team movement). I chose Quiet confidence; the next round started with `upgrades: ["window"]`.

For a focused timing check, I used 0.5x/0.25x setup and 0.05x inspection with pauses. I deliberately kept center power through the committed left-side blocking route, then pressed contact at **0.17 seconds remaining**. This is outside the base 0.13-second excellent window and inside the upgraded 0.18-second window. The runtime reported **EXCELLENT**, demonstrating a concrete benefit from the chosen upgrade. Evidence: `season-09-excellent-contact.json`, capture `s09-excellent-window-contact.png`.

The excellent attack was still blocked, and the point score became 0–2 at 18.5 match seconds. Evidence: `season-09-excellent-blocked.json`, capture `s09-excellent-still-blocked.png`. Excellent timing therefore strengthened execution without overriding the poor route decision or guaranteeing a point. This was assisted inspection, not evidence of native-speed timing skill.

## Defeat, temporary reset, and replay

After that inspection, I kept stale center tips and reviewed the remaining semifinal at 4x. It ended **0–5 defeat** at 56.8 simulated match seconds. The last three opponent points were open-court losses, each after six contacts. `upgrades` was empty on defeat; inherited permanent crowns 1–9 remained. Evidence: `season-09-defeat-reset.json`, capture `s09-defeat-upgrade-reset.png`.

I restored speed to 1x and started season nine again normally. The returned state was round one, score 0–0, empty temporary upgrades, empty ledger, `best_rally: 0`, and preserved permanent crowns. Evidence: `season-09-replay-reset.json`. This establishes reset and replay on the current code, not a new season-nine unlock.

## Interim scope before forward review (superseded below)

No blocking fairness or progression defect is demonstrated by the checks above. Shared finite block reach has separate actual-contact evidence in `animation-review.md` and `contact-repairs/`. Current 3D forward unlocks, all nine championship completions, save/restart after new unlocks, and final map variants remain to be reviewed. Map 2/3 art is being built concurrently; opening captures must not be presented as final map-fidelity approval.

## Forward progression from a fresh 3D-earned crown

For the forward pass I stopped the historical-profile instance and byte-copied `user://review-3d-beginner.json` to isolated `user://review-3d-forward.json`. The source was actually earned in the independent 3D beginner review and contained crown `[1]`, `unlocked: 2`, mute/reduced-motion settings enabled. No unlock data was edited. The following runs use manually selected ordinary controls with **4x assisted playback** for progression coverage; they do not replace the ordinary 1x late challenge above.

First season-two attempt: stale left tips won quarterfinal and semifinal **5–0, 5–0**, with automatic contacts. I chose team speed and then short-tip placement. The final lost **0–5**: the changed blocking formation returned the short shots and rivals scored into deep right court. This does not isolate an upgrade effect, because the round also changes the blocker lane. It demonstrates that the successful opening policy did not automatically win the championship. The saved unlock remained 2/crown 1 and temporary upgrades cleared. Full ledger: `season-02-forward-tip-upgrade-defeat.json`.

Season-two reattempt: identical squad and draft (speed, tip), quarterfinal/semifinal again **5–0, 5–0** with left tips. I changed to right tips for the final and won **5–1**. Same draft, different final placement, different outcome: this supports meaningful tactical placement without claiming a perfectly controlled timing experiment. Champion state saved crowns `[1,2]` and unlocked 3 with no save error. Full ledger: `season-02-forward-champion.json`; capture `s02-forward-champion.png`. The total championship time was 185.0 simulated seconds at 4x assisted playback.

Season three: stale right tips lost the opening attempt 0–5 (observed runtime snapshot; that initial attempt's full ledger was not retained). I switched to deep left power and earned the championship **5–0, 5–0, 5–0**, choosing Heavy hand then Perfect connection. The winning run lasted 169.8 simulated seconds with six-contact rallies and unlocked season four. Full ledger: `season-03-forward-champion.json`. This establishes an effective accessible opening strategy, not a high skill ceiling for season three.

Season four's different formation immediately countered that unchanged deep-left-power policy: **0–5 defeat**, 63.2 simulated seconds. Full ledger: `season-04-stale-power-defeat.json`. No crown/unlock or temporary bonus was retained from the failed attempt.

Season-four reattempt: alternating short corners opposite the committed blocker won **5–3, 5–0, 5–0** and unlocked 5. The quarterfinal used 1x unpaused play after an initial approximately 0.7 simulated seconds at 4x during setup; late lane switches cost three points. Semifinal/final used 4x with manually placed pauses. Draft: First step, Soft touch. Full ledger: `season-04-forward-champion.json`; total 224.0 simulated seconds. This provides additional representative normal-speed play but is not labelled a wholly 1x run.

Season five: **5–2, 5–0, 5–0**, with Heavy hand then Together, faster; unlocked 6. The opener's repeated tips were returned after short-shot memory activated. I then scored deep while the wings covered short, followed by a short right tip after the old short attacks aged out of the four-shot memory. Semifinal/final followed that short/deep response manually with 4x playback and pauses. Full ledger: `season-05-forward-champion.json`. This demonstrates readable adaptation and useful attack variety, while the clean assisted wins should not be presented as evidence of demanding execution under pressure.

## Completed 3D championship chain

All eight further crowns were earned by actual wins on the new 3D rules, carrying the fresh beginner review's season-one crown forward. No score, match result, player position, or unlock override was used. The table summarizes the retained complete point ledgers, not scripted tests.

| Season | Quarterfinal | Semifinal | Final | Run seconds | Draft | Unlock after win |
|---|---|---|---|---:|---|---:|
| 2 | 5–0 | 5–0 | 5–1 | 185.0 | speed, tip | 3 |
| 3 | 5–0 | 5–0 | 5–0 | 169.8 | power, set | 4 |
| 4 | 5–3 | 5–0 | 5–0 | 224.0 | tempo, tip | 5 |
| 5 | 5–2 | 5–0 | 5–0 | 206.8 | power, speed | 6 |
| 6 | 5–0 | 5–1 | 5–0 | 195.0 | roll, read | 7 |
| 7 | 5–0 | 5–0 | 5–0 | 182.6 | window, roll | 8 |
| 8 | 5–1 | 5–0 | 5–0 | 194.5 | roll, read | 9 |
| 9 | 5–0 | 5–1 | 5–0 | 197.2 | window, roll | 9 |

Files: `season-02-forward-champion.json` through `season-09-forward-champion.json`. Season one is independently documented in `beginner-review.md`; I did not replay that championship here. Seasons 2–8 and the season-nine quarterfinal used 4x assisted playback, with pauses where described. **The season-nine semifinal and final were wholly ordinary, unpaused 1x.** All run times are simulated gameplay seconds and exclude reviewer pause/menu deliberation. No perfect-timing input was used in these forward wins.

Season six's lane-frequency blocker returned an incorrectly alternated tip and caused the single semifinal loss. The same short/deep response nevertheless carried through all later seasons. That matters to the finding below: a readable early counter exists, but the late defense does not develop an adequate counter to the learned response.

## Historical [P1] Advanced challenge: the late short/deep memory cycle becomes dominant

**Approval withheld for advanced challenge.** The late-season opponents repeatedly expose both deep corners together, and the reviewer can turn that into an almost unopposed fixed cycle with automatic contacts. This contradicts a strong claim of nine progressively harder tactical seasons.

Concrete reproduction on the reviewed revision:

1. Tip into a corner away from the committed blocker until two recent attacks are short. On a fresh run this can require switching the first tip's side; with established left-heavy lane history, right tips are sufficient.
2. Switch to deep left power for three attacks. Leave placement, hitter, and timing unchanged throughout that section.
3. When the short memories age out and wings move back, return to the open short corner. Repeat the same memory cycle.

Observed results: this won season seven **5–0 / 5–0 / 5–0** and season eight **5–1 / 5–0 / 5–0**. The season-seven draft was Quiet confidence plus High horizon; neither was used by the automatic-contact tip/power policy. More decisively, the season-nine **normal 1x semifinal won 5–1 in 72.9 seconds**, and its **normal 1x final won 5–0 in 60.8 seconds**. There were no contact presses, hitter changes, or responsive defensive inputs. Each match used an initial right-tip selection followed by one switch to deep left power; the semifinal's delayed switch allowed an extra returned tip and one lost point. The final's five points all came from six-contact rallies. Evidence: `season-09-cycle-normal-semifinal.json` and `season-09-forward-champion.json`.

This normal-speed result supersedes any inference that the earlier 9–7 exploratory quarterfinal alone established a demanding late ceiling. That earlier run remains valid evidence that poor/stale choices lose and rallies are possible. It does **not** disprove a dominant learned strategy.

Source mechanism: `scripts/main.gd:460`–`469` applies the same short-depth commitment to **both** defending wings after two short memories, regardless of the repeated deep corner that follows. `scripts/main.gd:444`–`450` adapts only the inboard block lane. The shared finite reach is physically appropriate; it should not be enlarged to hide the tactical issue. The current deep-left sideline power remains outside that blocker and repeatedly reaches the abandoned backcourt. Faster late reaction/quality alone does not correct the formation. Reviewed `main.gd` SHA-256: `35ea027b5b7bdcfba81808347384f08e55e0b491d78b8548229719c48da2f72a`.

Suggested focused repair: from the late seasons, retain one deep wing or shift a deep wing toward a repeatedly attacked corner while the other covers short. Make the commitment readable, derive it from historical committed attacks rather than hidden current input, and preserve the existing shared speed/reach/recovery bounds. Then replay the dominant cycle and an adaptive mixed response at 1x. The counter should force a different decision, not grant teleporting digs or arbitrary misses. This reviewer made no gameplay edits.

## Restart, saved crowns, and replay reset

After the season-nine champion screen, I stopped only my port-45903 runtime and launched a fresh process with the same `review-3d-forward` profile. The actual saved JSON contained crowns `[1,2,3,4,5,6,7,8,9]`, `unlocked: 9`, and the original mute/reduced-motion settings. The fresh runtime loaded those values with no save error. Its season-selection screen displayed all nine checkmarks and replay availability. Evidence: `all-nine-restart-state.json` and `advanced-runtime/all-nine-crowns-restart.png`.

I then selected season nine through the ordinary menu action. Its immediate state was round one, 0–0, zero run/best-rally counts, empty temporary upgrades, and empty ledger, with all permanent crowns retained. Evidence: `all-nine-replay-reset.json`. A fresh ordinary-camera opening rally is captured in `advanced-runtime/latest-citrus-gameplay.png`; all six athletes are visible. This is presentation context, not blanket visual-fidelity approval. Final champion evidence: `advanced-runtime/s09-forward-champion.png`.

## Pre-repair scope and verdict (superseded by targeted re-review below)

- **Demonstrated:** current 3D season-one crown provenance plus actual forward wins of 2–9; permanent incremental unlocks; victory; failed championship attempts; temporary-upgrade reset; excellent timing benefiting from the chosen window without overriding a valid block; restart persistence; all-nine replay availability; clean replay run state. Shared finite block geometry/contact has separate runtime evidence in `animation-review.md` and `contact-repairs/`.
- **Open substantive finding:** the P1 learned late-season cycle above. Advanced-challenge approval is withheld until it is countered and independently replayed. No unfair reach or broken progression was demonstrated in this pass.
- **Limits:** no automated tests or bots were created. Most championship coverage used assisted playback; only specifically labelled matches establish native-speed behavior. An enjoyable subjective experience, competitive longevity, every possible upgrade combination, every pose, and final visual-target fidelity are not certified by these wins. The introductory/keyboard-accessibility and map-art reviews remain separately owned.

## Targeted re-review after the late-defense repair — final verdict

**The original P1 dominant-cycle finding is resolved in the tested policies.** The earlier withheld verdict is historical and is superseded by this section. This is scoped approval of the demonstrated tactical counter, physical fairness, and late championship flow, not a claim of universal balance or subjective fun.

### Revision and method

The lead implemented asymmetric late coverage: from season seven, one wing retains deep coverage selected from committed landing history while the other covers short; from season eight, the blocker can shade toward a remembered hitter route. I found the initial `perform_attack` implementation overwrote that new commitment with the old inboard target. The lead repaired it by storing/restoring `committed_block_target`, and I restarted before the results below. That pre-repair startup was abandoned and is not approval evidence.

I byte-copied the genuinely earned all-nine 3D save to isolated `user://review-3d-counter.json`, without editing its contents. Both files had SHA-256 `5dfa2a451ee6a65d8b5519da29a72db93e3aee6bbb381957ff2e4a1e41bedfe4` at copying, crowns 1–9, unlocked 9, sound on, and reduced motion enabled. These are **replay championships**, not newly claimed unlocks. The prior forward chain still establishes unlock/save flow; the modified season-seven-to-nine gameplay was replayed here.

The championship runtime used the corrected commitment rules. A subsequent restart loaded the final text/unused-trail cleanup and corrected directional coaching for contact inspection. Final inspected `main.gd` SHA-256: `71be3f4b51aa8095c0288afcc5075441f221c0d505dbee053c3c957b312b7228`. The lead confirmed those intervening changes did not alter gameplay rules. All commands remained individually selected by the reviewer; no tests, gameplay bots, score/position overrides, or unlock edits were used.

### Old policy counter and alternative exploit checks

At ordinary, unpaused **1x**, the old repeated-tip/deep-left-power policy family lost season nine's quarterfinal **3–5 in 89.7 seconds**. The repeated left powers now lost through valid blocks at scores 3–2, 3–3, 3–4, and 3–5. Full ledger: `counter-09-old-cycle-defeat.json`. Model/tool delay prolonged both the tip and power phases, so this is explicitly **not** an exact controlled two-tip/three-power input replay. It is direct native-speed evidence that the formerly automatic deep-left scoring section is countered.

Repeated right tips from a fresh season-nine run lost **0–5 in 63.7 seconds** with assisted 4x playback: `counter-09-stale-right-tip-defeat.json`. Repeated left tips were returned and could sustain a long exchange. They did not become an automatic winning lane. Changing hitter and then using deep power into the uncovered corner ended the retained 63-contact sample on the next Sol attack, and further adaptive choices won that match. Evidence: `counter-09-stale-left-tip-long-rally.json` and the subsequent `counter-09-adaptive-champion.json` ledger (longest completed rally 69 contacts).

The new defense therefore changes the needed decisions. Keeping the same power corner/hitter can be blocked or dug; changing the hitter can bypass the remembered corridor; changing depth or side can attack the wing's visible commitment. The retained deep wing does not teleport into the open corner, and the block's reach was not enlarged to manufacture this counter.

### Revised late championship results

| Season | Quarterfinal | Semifinal | Final | Run seconds | Draft | Method |
|---|---|---|---|---:|---|---|
| 7 | 5–0 | 5–0 | 5–0 | 192.1 | power, roll | Quarterfinal wholly unpaused 1x; later matches 4x with manual pauses |
| 8 | 5–2 | 5–0 | 5–0 | 211.8 | roll, power | Quarterfinal wholly unpaused 1x; later matches 4x with manual pauses |
| 9 | 5–1 | 5–3 | 5–0 | 310.0 | window, roll | 4x with manual pauses; includes deliberate long-rally investigation |

Full point ledgers: `counter-07-adaptive-champion.json`, `counter-08-adaptive-champion.json`, and `counter-09-adaptive-champion.json`. The ordinary season-eight quarterfinal also has its own retained state: `counter-08-normal-adaptive-quarterfinal.json`.

The normal season-eight quarterfinal finished **5–2 in 84.4 seconds**. I changed tip corner, power corner, and hitter after coverage punished late or repeated attacks. The last point came from a rival attack being blocked; I do not claim that every attempted placement directly scored. No timed contact presses were needed. In the season-nine semifinal, covered tips fell behind **1–3**, and changing hitter plus deep placement, followed by tips at the deep wing, recovered to **5–3**. In its final, I changed hitter before the remembered block caught the repeated right power, then changed to the opposite deep corner as coverage shifted. These are accessible automatic contacts combined with meaningful tactical choices.

The clean assisted wins demonstrate that the revised opponents remain beatable. They are not evidence of demanding execution under pressure. Timing still has the separately demonstrated upgrade benefit and is not required merely to participate in the late game.

### Physical shaded block and accurate coaching

I restarted the latest code and inspected a naturally reached shaded block in slowed 0.05x playback. The rival blocker stood at logical **x −3.14, y −0.75**, reached up through the finite rig, and met the actual ball at the net. Just before crossing, measured ball/hand surface separation was approximately **−0.009 m** (slight contact overlap), followed by the actual **ROOFED** rebound with approximately **−0.065 m** overlap. The closeup shows the ball at the palms, finite arm lengths, and an airborne block. This is an inspection-camera capture, explicitly not an ordinary gameplay camera claim.

Evidence: `counter-shaded-block-contact.json`, `counter-shaded-block-rebound.json`, and `counter-runtime/counter-shaded-block-contact-closeup.png` / `counter-shaded-block-rebound-closeup.png`. The scoring check retains the same height-dependent envelope, 2.9 m ceiling, movement cap, and recovery rules for both teams. No remote or unreachable awarded block was demonstrated in this sample.

I also reached a different commitment where the old remembered `block_lane` was **2 (right)** but the actual committed blocker target was **x −1.844 (left)**. The final ordinary HUD correctly displayed **“Front defender LEFT”**, agreeing with the physical defender rather than the old landing-lane value. Evidence: `counter-actual-block-coaching.json` and `counter-runtime/counter-actual-left-block-coaching.png`.

### Long-rally coaching is actionable with one simple choice

On the final restart, I deliberately kept left tips until an ordinary-camera rally reached **33 contacts at 40.1 seconds**, with score 0–0. The HUD displayed: **“Same lane covered? Try the other side (← →), or TAB for another hitter.”** Evidence: `counter-long-rally-guidance.json` and `counter-runtime/counter-long-rally-guidance.png`.

I changed **only the aiming lane to right**. Shot remained TIP, hitter remained unchanged, and contacts remained automatic. The **next Sol attack scored at 43.7 seconds, ending the rally at 36 contacts**. Evidence: `counter-long-rally-one-choice-escape.json`. Thus the cue recommends an action that actually ends the sampled ineffective-choice loop; it does not require precise movement, a timing input, or hidden fatigue. Beginners who ignore the cue can still sustain long rallies, which remains a disclosed pacing limitation, but this is not an unavoidable or mechanically trapped match.

### Final scoped assessment

- The original repeated two-short/three-deep-left exploit has a demonstrated tactical counter. No replacement always-right-tip or always-left-tip winning lane was demonstrated in the targeted checks.
- Revised seasons 7–9 remain winnable; ordinary 1x season-eight adaptive play and ordinary 1x season-nine failure of the stale policy provide representative challenge evidence. The full earlier forward chain, failure/reset, all-nine restart persistence, and replay checks remain documented above.
- Shared physical limits were preserved, and the sampled new shaded block visibly contacts the ball. The corrected front-defender cue and long-rally advice were both verified at runtime.
- No remaining substantive fairness/progression defect was demonstrated in this bounded review. Long unchanged-choice rallies remain possible and should not be hidden in duration or fun claims. Most championship coverage was assisted; exhaustive balance, every upgrade combination, competitive longevity, and subjective enjoyment are not certified.
