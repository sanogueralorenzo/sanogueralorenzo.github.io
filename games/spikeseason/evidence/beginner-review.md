# Independent beginner accessibility review

Reviewer: independent accessibility agent, 2026-09-05. This is a manual runtime review, not an automated test. Godot 4.7.2 rendered a native game window. A separate local review session used port 45902 and the isolated `beginner` save profile. Individual commands invoked ordinary menu and keyboard actions; there were no bots, assertions, score overrides, or unlock overrides.

## Demonstrated at normal speed (1x)

### Warm-up and simple tactical choice

The first warm-up began with the default middle roll and no contact input. Automatic movement and contacts sustained play. The rivals scored at 7.0 seconds after three contacts, then at 48.6 seconds after a 30-contact rally. The score was 0–2 at 67.3 seconds.

I manually chose right aim at 80.2 seconds and power at 86.4 seconds. The ongoing rally continued to 59 contacts. At 121.5 seconds I changed only the shot to tip, without pressing Space. Sol scored at 123.5 seconds, ending a 60-contact rally. Keeping that accessible choice scored at 136.2, 149.0, 165.1, and 177.8 seconds, with subsequent rallies of 6, 6, 9, and 6 contacts. The warm-up result appeared at 179.8 seconds with a 5–2 win.

This demonstrates that a beginner can sustain rallies and win by choosing placement and shot type without precise movement or timing. It does not prove the game is fun or broadly balanced. Repeating right tip was sufficient against this first opponent; later-season counterplay was not reviewed in this session.

Snapshots were visually inspected. All six players were distinguishable, the selected teammate had a ground ring, the aim marker was visible, and the HUD named `REN / LEFT` as the next attacker. Persistent shot choices and the explicit automatic-contact label make the primary controls understandable. The picture has clear team colors and warm coastal scenery, though it is substantially simpler than the supplied visual target.

The first reviewed build had a significant pacing concern: the 60-contact rally lasted approximately 73 seconds. This was reported immediately. The developer subsequently changed blocked-ball rebounds; a focused follow-up is recorded below.

Screenshots from this session:

- `/tmp/spike-beginner-review/01-unattended-default-roll.png`
- `/tmp/spike-beginner-review/02-unattended-warmup-result.png` (despite its filename, this captures ongoing play)
- `/tmp/spike-beginner-review/03-beginner-right-power.png`
- `/tmp/spike-beginner-review/04-right-tip-result.png`
- `/tmp/spike-beginner-review/05-right-tip-warmup-finish.png`

## Follow-up: old-build loss attempt, assisted completion abandoned

An ordinary season-1 run used persistent middle roll and no timing input. At 1x the rivals scored at 7.0, 48.4, and 125.5 seconds, with 3, 30, and 60 contacts. At 188.0 game seconds I manually changed playback to 4x. A fourth rival point occurred at 315.3 game seconds after 150 contacts. The fifth rally reached 288 contacts at 688.2 game seconds; changing aim left did not end it. I restored 1x and stopped that old process to review the already available fix.

This old-build run **did not demonstrate defeat**. Its accelerated segment is assisted evidence only and must not be cited as ordinary match duration or responsiveness. The misleadingly named `06-season-one-defeat-assisted.png` captures an incomplete 0–4 match, not a defeat screen.

## Follow-up: revised block behavior and defeat, entirely at 1x

I restarted Godot after the developer changed blocked balls from a slow recoverable lob to a short downward rebound. In a fresh ordinary season-1 run, I chose right aim and power, leaving the initial attacker selected and never timing a contact. The rivals won 0–5. The last four points were caused by blocks; the last three ended at 24.5, 33.3, and 42.1 game seconds. Each rally had three contacts. The actual defeat screen appeared at 44.1 seconds with `unlocked: 1`, `upgrades: []`, a season-selection button, and a replay button.

The focused blocked-power loop is therefore resolved in demonstrated runtime behavior. A wrong persistent tactical choice now loses promptly through an identified physical cause instead of producing the previous extended rebound loop. This check does not establish that every possible rally loop is eliminated.

- `/tmp/spike-beginner-review/07-revised-power-blocks.png`
- `/tmp/spike-beginner-review/08-revised-native-speed-defeat.png` — visually inspected actual defeat screen.

## Follow-up: attacker selection, entirely at 1x

I replayed season 1 with the same right-power choice. After the initial opponent point, I pressed only Tab at 10.9 seconds to select the other attacker. The same landing lane and shot then scored for Sol at 16.0 seconds after three contacts and at 28.6 seconds after six contacts, leading 2–1. No contact timing was used. The session was paused at 36.8 seconds.

This demonstrates a meaningful, accessible team decision: changing the attacking route can turn a repeatedly blocked attack into an open-court winner. Screenshot: `/tmp/spike-beginner-review/09-attacker-route-response.png`.

## Final finding and resolution

**P1 — Block advice must describe the route, not just the landing lane.** The inspected HUD says a left block can be beaten by using the far lane. The runtime evidence above shows a left attacker aiming far right still crossing that left block and losing. The advice should instead explicitly recommend a roll or a different attacker before the set, or show the actual path through the net. This was sent to the developer with the demonstrated attacker-switch alternative.

**Resolved by subsequent source inspection:** the HUD now says `Roll over it or TAB to another hitter.` The observed attacker-switch outcome supports that advice. A minor wording suggestion is to add “next set,” because the note appears after the current attacking route is committed; the existing Tab toast already communicates that delay. The revised sentence was inspected in source, not re-captured in a restarted window.

No further beginner-blocking issue was demonstrated after the rebound fix. The normal-speed warm-up win and revised defeat provide narrow evidence of accessible agency and consequences; they do not constitute a blanket sign-off on all progression or difficulty.

## Scope and limits

The review inspected the initial gameplay code and raised the previously reported endless-rally risk, ineffectual receive timing, non-actionable Court vision, and unnamed attacker selection. Later code carries receive quality into attack quality, gives Court vision an aim-dependent reaction effect, and names the selected attacker. The latter is also visible in the runtime screenshots. The timing and Court vision effects were not isolated through runtime play here.

The initial review above did not verify all nine seasons, championship unlocks, saving, replay persistence, late-season challenge, gamepad support, or subjective enjoyment. The final-season-3 follow-up below adds a completed championship replay and run-reset evidence. The warm-up win, revised defeat, and attacker-switch follow-up were entirely at 1x. Only the explicitly labeled old-build loss attempt used faster-than-normal playback. The native window was rendered throughout; telemetry in those earlier sessions reported 26–42 FPS while multiple review instances were active. This is not a standalone performance benchmark.

## Final simulation: season 3 championship and replay reset

I restarted the latest runtime with isolated profile `beginner-final`, port 45902. The root review's legitimately earned `review-runtime.json` was copied byte-for-byte to `review-beginner-final.json`; both files had SHA-1 `d7bf9e8338dd9f83794533cd1ce9d999b7bd9883` before launch. That existing save contained crowns 1–3 and four unlocked seasons. No score, unlock, or crown value was edited. Consequently, this is evidence of completing an unlocked season again, not independently earning the initial season-4 unlock.

The complete three-match run used the Sunkeepers and **zero contact inputs**. I made individual directional and menu choices through the normal review controls. Some play ran at 1x; some ran at 0.25x, with manual pauses for planning. This is **assisted tactical completion**, not an unaided beginner playthrough or a normal-speed reaction assessment. No bots, automated decision loops, assertions, or score overrides were used. I had inspected the implementation and read runtime phase/block/position information, so this was not a blind novice study.

Results on the final simulation:

| Match | Score | Game time at result | Upgrade selected afterward |
|---|---|---|---|
| Quarterfinal | 5–0 | 66.7 seconds | Soft touch |
| Semifinal | 5–1 | 55.6 seconds | Together, faster |
| Championship | 5–0 | 56.8 seconds | None; championship completed |

The run finished in 179.0 game seconds over 16 rallies, with a longest rally of 18 contacts. These are simulation times, not wall-clock completion times. The full unmodified champion-state response is [season-03-final-run.json](season-03-final-run.json); the visually inspected result is [season-03-final-champion.png](season-03-final-champion.png).

The effective decisions were straightforward: move the tip to the other short corner when the rival block followed the previous landing, and commit defense toward the alternating rival attacker. In the quarterfinal, changing left tip to right tip ended the longest 18-contact rally at 43.8 seconds. In the final, the same placement change ended a 12-contact rally at 25.2 seconds. Defensive block choices also produced points with an explicit `BLOCK • no cover underneath` reason. The second match's one lost point showed that missed coverage still had a consequence. This supports season 3 being beatable through placement and team tactics without mandatory timing; it does not prove that all novices can execute the choices at full speed.

Soft touch was chosen to increase short-placement pressure instead of Court vision or Heavy hand. Together, faster was then selected to support recovery instead of the timing-window or set-quality options. Their selected IDs, `tip` and `speed`, appear in the champion state. This run demonstrates selecting and retaining the upgrades through the championship, but does not isolate their causal effect against an otherwise identical run.

After capturing the championship, I used ordinary replay to start season 3 again. The immediate state showed round 1, score 0–0, zero run time, an empty ledger, and no temporary upgrades, while crowns 1–3 and four unlocked seasons remained. The full response is [season-03-replay-reset.json](season-03-replay-reset.json). The new run was paused immediately. The championship reported no save error. Because this profile already contained the same permanent progression, this check demonstrates preservation and reset behavior, not a new permanent unlock.

No new blocker was found in this bounded final-simulation check. Season 3 rewards changing a repeated plan, while contact timing remains optional. Difficulty balance beyond this assisted evidence, all nine seasons, and subjective enjoyment remain outside this review's independent demonstration.
