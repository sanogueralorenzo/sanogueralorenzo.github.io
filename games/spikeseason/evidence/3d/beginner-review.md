# Independent 3D beginner/runtime review

Reviewer: independent beginner-accessibility agent, 2026-09-06. Isolated Godot process, port 45904, profile `3d-beginner`, fresh progress with only season 1 unlocked. Source and other review instances were not modified. The authored rally camera was used throughout. Commands were individual ordinary menu/key inputs through the local review console; there were no bots, automated tests, score overrides, or unlock overrides.

## Method and limits

All play reported below ran at **ordinary 1x simulation speed**. The completed warm-up and championship used no Space/contact inputs or movement input. A separate short post-championship inspection queued one early contact, as detailed below. The introduction, season-selection screen, upgrade screen, and live court screenshots were visually inspected. The console directly invoked the ordinary warm-up/start-run menu functions; it does not expose the how-to or squad-selection UI navigation, so those particular button paths were inspected in source rather than clicked. I read the README and had prior implementation knowledge, so this is not a blind novice study. It cannot establish subjective fun.

The native 3D window rendered throughout. Sampled FPS varied from roughly 25 to 55 while other review instances were active; this is not a standalone performance measurement. Initial startup included shader/loading delay before normal rendering.

## Ordinary-speed warm-up: completed win

I began with default middle roll and no inputs. The rival scored after three contacts at 7.0 seconds. The second rally reached 22 contacts by 38.5 seconds. I then pressed Right and E, choosing right tip at 38.5–38.8 seconds, consistent with the visible advice that deep wings can be pulled forward by a tip.

That change ended the ongoing rally at 44.7 seconds after 27 contacts, tying the score. The rival scored again at 53.6 seconds. Sol then scored at 62.7, 75.4, 88.1, and 100.8 seconds with rallies of 3, 6, 6, and 6 contacts. The actual warm-up result appeared at 102.8 seconds: **5–2**.

This demonstrates that automatic positioning/handoff can sustain a rally, and a simple persistent tactical change can produce short scoring rallies without contact timing. It does not support claiming that every starting tactic is effective or that long rallies are always enjoyable. The separately reported unchanged left-tip loss is compatible with this result: placement matters.

## First-season championship run

The season-selection screen showed season 1 available and seasons 2–9 locked with explicit predecessor requirements. I started Sunkeepers in season 1, retaining the successful right-tip choice.

- Quarterfinal: **5–1**, result at **68.8 game seconds**, zero contact inputs. Chose **Soft touch** over reach or Court vision, to strengthen the established short-placement plan.
- Semifinal: **5–1**, result at **68.8 game seconds**, zero contact inputs. Chose **Perfect connection** over power or a wider timing window, supporting automatic sets.
- Championship: **5–1**, result at **95.5 game seconds**, zero contact inputs. Unchanged right tip initially stalled at 0–1 and 26 contacts against the right front defender. I pressed Left twice at 41.2–41.4 seconds; the next left tip scored at 43.2 seconds, ending a 27-contact rally. Four subsequent six-contact rallies scored at 55.4, 68.1, 80.8, and 93.4 seconds.

The complete championship run took **233.0 game seconds**, across **18 rallies**, with a longest rally of **27 contacts**. All three wins occurred at ordinary 1x, without pauses or slowed playback. Changing the landing lane while retaining the same finish was a sufficient response to the final's covered-tip rally. These are demonstrated outcomes, not a claim that the game is fun or balanced for every player.

The first upgrade menu was readable and described three distinct effects. Temporary-upgrade duration and reset conditions were explicit.

## Complete championship ledger and progression evidence

The complete ledger below was read from the runtime and from `review-3d-beginner-last-run.json` before stopping the isolated process. **Every row belongs to season 1 and records reason `OPEN COURT • beyond the dive`.** Times are seconds within the corresponding match; the two-second result transition is not included in each scoring timestamp.

| Match | Score after point | Contacts | Point time |
|---|---|---:|---:|
| Quarterfinal | 0–1 | 3 | 7.0 |
| Quarterfinal | 1–1 | 3 | 16.0 |
| Quarterfinal | 2–1 | 6 | 28.7 |
| Quarterfinal | 3–1 | 6 | 41.4 |
| Quarterfinal | 4–1 | 6 | 54.1 |
| Quarterfinal | 5–1 | 6 | 66.8 |
| Semifinal | 0–1 | 3 | 7.0 |
| Semifinal | 1–1 | 3 | 16.0 |
| Semifinal | 2–1 | 6 | 28.7 |
| Semifinal | 3–1 | 6 | 41.4 |
| Semifinal | 4–1 | 6 | 54.1 |
| Semifinal | 5–1 | 6 | 66.8 |
| Championship | 0–1 | 3 | 7.0 |
| Championship | 1–1 | 27 | 43.2 |
| Championship | 2–1 | 6 | 55.4 |
| Championship | 3–1 | 6 | 68.1 |
| Championship | 4–1 | 6 | 80.8 |
| Championship | 5–1 | 6 | 93.4 |

Saved run metadata: `result: champion`, `season: 1`, `round: 3`, `seconds: 233.033333333286`, `best_rally: 27`, `upgrades: ["tip", "set"]`. The champion runtime state reported `save_error: ""`.

Fresh-profile progression before the run was `unlocked: 1`, `crowns: []`. After winning, both the champion runtime and the actual saved file at `~/Library/Application Support/Godot/app_userdata/Spike Season/review-3d-beginner.json` reported:

```json
{
  "crowns": [1],
  "muted": false,
  "reduced_motion": false,
  "unlocked": 2,
  "version": 1
}
```

The champion screenshot visibly announced season 2 unlocked. Returning through the ordinary season-selection menu showed the earned progression. This was a genuinely earned first unlock in a fresh isolated profile, not a copied or edited progression file. A subsequent ordinary warm-up start showed temporary upgrades cleared to `[]` while `unlocked: 2` remained. Persistence was checked by reading the saved file, not by restarting the process in this particular review.

## Separate contact-feedback inspection

After the completed championship, I started another warm-up and queued one contact approximately 1.02 seconds before an attack ended, at 35.5 game seconds. The immediate ordinary-speed screenshot showed the SPACE CONTACT button highlighted, confirming the buffered input; the rally continued and Sol later scored. This was an early optional input, not a demonstrated excellent-timing hit. The brief post-contact rating itself was not captured, so I do not claim to have verified the readability of every timing-result message. The completed championship evidence above remains entirely free of contact inputs.

## Concrete findings sent to the developer

1. **P1 — The lower-right HUD obscures playable space.** At the ordinary authored camera, the deep-right teammate and landing area can sit behind the shot/timing panels. `03-warmup-rally.png` shows Jun substantially obscured by those controls. This interferes with seeing the handoff and physical reason for a right-backcourt save or miss. The HUD should reserve space outside reachable players/ball targets, or the authored camera should keep the entire playable footprint clear of the panels.
2. **P2 — Long-rally advice is too generic and can reinforce an ineffective tip.** The long-rally coach says “Change the finish. Look for open space,” while the attack coach repeatedly suggests a short tip against deep wings. A repeated covered tip may instead need a different lane/route. The successful right-tip change demonstrates why guidance should identify the uncovered front corner or recommend tipping away from the committed blocker. Make that advice persistent enough to read; currently it is small text at the bottom and changes with brief contact phases.
3. **Readability limitation — the optional timing cue is far from the ball.** The bar is at the bottom right while contact can occur anywhere on court. Optional automatic contact prevents this from blocking beginner play, but novice timing feedback requires a large gaze shift. I did not demonstrate excellent timing in this run.

Positive observations: all six players and distinct team colors are apparent when clear of the HUD; a gold ground ring and highlighted portrait show automatic handoff; shot choices remain visibly selected; automatic contact is explained; scoring reasons and the score are easy to locate. Portrait names make the next-attacker choice clearer than anonymous option numbers.

## Fix status and remaining scope

After the report, the developer added concrete repeated-lane guidance recommending the other side or another hitter, and changed attack coaching to direct tips away from the front defender. I confirmed those strings and their repeated-lane condition in the current source. This addresses the substance of finding 2; the new copy was not re-captured in my already running process.

The developer also added HUD collapse when a projected athlete/contact silhouette intersects either corner panel. I confirmed the implementation exists in source. The separate visual reviewer owns runtime rechecking the exact Jun occlusion; this review does **not** mark finding 1 visually reverified. The optional timing cue's distance from the ball remains a minor readability consideration, with automatic contact providing a successful beginner path.

No further gameplay blocker was demonstrated in this bounded first-season review. Only my isolated port-45904 process was stopped after the contact inspection. Other instances and game source were not touched.

## Capture inventory

Captures are in `/tmp/spike-3d-beginner-review/`:

- `01-intro.png`
- `02-default-warmup.png`
- `03-warmup-rally.png`
- `04-right-tip-response.png`
- `05-warmup-result.png`
- `06-season-selection.png`
- `07-season-one-midmatch.png`
- `08-first-upgrade.png`
- `09-semifinal-result.png`
- `10-final-opening.png`
- `11-final-read-the-block.png` (a rival attack phase, not an own-attack coaching capture)
- `12-final-left-tip-response.png`
- `13-first-season-champion.png`
- `14-earned-season-two.png`
- `15-contact-input.png`

No claim about a full nine-season progression, later difficulty, or subjective enjoyment is made by this bounded review.

## Follow-up: actual restart, native menus, settings, and defeat reset

I launched a new process using the genuinely earned `review-3d-beginner.json`. At the introduction it loaded `unlocked: 2`, `crowns: [1]`, `upgrades: []`, and no save error. This closes the earlier limitation about only reading the save file: progression was now loaded after an actual process restart.

Native UI targeting required isolation because CUA's generic Godot bundle resolved to an unrelated Last Cast window. No input was sent there. I made a temporary copy of the installed Godot 4.7.2 application at `/tmp/SpikeSeasonBeginnerReview20260906.app`, changed only its review bundle identity/name, and locally re-signed that copy. The installed engine and game source were untouched. CUA then targeted only `games.spikeseason.beginner.review20260906`, while the game retained port 45904 and its isolated save profile. This temporary review application is not part of the game deliverable.

### Native keyboard and mouse flow

- Native **Return** from the introduction opened How to Play. **Tab, Return** selected Choose a season. These screens were actually navigated in this follow-up, extending the earlier source-only button-path inspection.
- Season 1 visibly had its crown, season 2 was enabled, and season 3 was disabled. A native click on season 3 left the selection screen unchanged.
- Native **Tab, Return** from the first season button selected season 2 and opened its squad screen. **Return** selected Sunkeepers and started season 2; **Escape** paused it at the initial serve.
- A native click on Leave this run returned to seasons. Two native **Return** presses selected and replayed season 1 with a fresh round and no upgrades. Native **Right, E** changed aim to right and finish to tip during play.
- After the later defeat described below, native **Tab, Return** activated Play this season again; **Escape** paused the fresh replay. Runtime state confirmed `season: 1`, `round: 1`, `score: [0,0]`, `run_seconds: 0`, `ledger: []`, `upgrades: []`, `unlocked: 2`, `crowns: [1]`, and `paused: true`.

The native app's accessibility tree exposes the window but not Godot's canvas buttons. Keyboard focus, visible screenshots, and the isolated runtime state were used together; this does not establish screen-reader support.

### Settings saved and loaded after another process restart

On the season-selection screen I clicked the native Sound button to change it to **off**, then Motion to **reduced**. The visible labels and actual profile file both reflected the changes. I stopped only that isolated process and relaunched it. The new process's season-selection screenshot again showed **Sound: off**, **Motion: reduced**, season 1 crowned, and season 2 enabled.

The saved progression/settings after the native changes and restart were:

```json
{
  "crowns": [1],
  "muted": true,
  "reduced_motion": true,
  "unlocked": 2,
  "version": 1
}
```

This verifies the settings flags and displayed saved state, not a quantitative audio-level or motion-reduction measurement. The settings belong only to the isolated review profile.

### Earned upgrade, actual defeat, and temporary-upgrade reset

The native season-1 replay won its quarterfinal **5–2**, with the final point at 100.8 game seconds and the upgrade screen at 102.8. All scoring in that first match occurred at 1x. I changed playback to 4x only after the final point, then selected the genuinely earned **Court vision** upgrade through the ordinary upgrade action. The semifinal began with `upgrades: ["read"]`.

For a deliberate losing attempt I retained middle roll and did not adapt. The entire semifinal used explicitly **assisted 4x playback**, no contact input, no bot, and no score/stat override. It ended in an actual **0–5 defeat**, with `upgrades: []`, `unlocked: 2`, and `crowns: [1]`. The saved run reported 382.3 total game seconds and a longest rally of 60 contacts. These accelerated results must not be presented as ordinary reaction or match-length evidence, or as evidence that the unchanged plan was enjoyable.

Complete semifinal scoring ledger, all `OPEN COURT • beyond the dive`:

| Score | Contacts | Point time in semifinal |
|---|---:|---:|
| 0–1 | 3 | 7.0 |
| 0–2 | 30 | 48.1 |
| 0–3 | 60 | 124.6 |
| 0–4 | 60 | 201.0 |
| 0–5 | 60 | 277.5 |

The defeat screen appeared at 279.5 semifinal game seconds. Court vision was recorded as present at 197.1 seconds during that match, and absent on the defeat screen. The native post-defeat replay then reset score, round, run time, and ledger while preserving permanent progression, as detailed above.

### New findings and compact HUD check

1. **P1 — Pause-menu keyboard focus is missing.** Native Escape reliably paused the game, but Tab navigation showed no focused pause button; four Tabs followed by Return left the pause screen unchanged. A native mouse click on Leave worked. The reviewed source only called `focus_first.grab_focus` when `screen != "match"`, excluding the pause menu. This prevents keyboard-only access to pause-menu settings/leave, even though Escape can resume. Sent to the developer with the recommended first-button focus when paused; not yet reverified after a fix in this follow-up.
2. **P2 — Compact timing feedback loses size and queued-input indication.** The collapsed corner now visibly leaves Jun unobscured in `20-earned-upgrade-loss-attempt.png`, improving the original HUD finding. However, the timing bar shrinks from 332 to 62 logical pixels and is almost a hairline below SPACE; the compact SPACE button's source uses `shot == i` for index 3, which cannot highlight a queued contact. Suggested preserving a full-width low timing strip and using `timing_press >= 0` for SPACE's selected state. This remains optional for successful beginner play, but affects learning and using timing.

Updated repeated-lane coaching is visible in the live compact-HUD capture: it explicitly recommends the other side or another hitter. That part of the earlier guidance fix is now verified in rendered runtime, not just source.

Only my isolated runtime was stopped after the post-defeat replay check. Additional captures in `/tmp/spike-3d-beginner-review/`:

- `16-native-settings.png`
- `17-settings-after-process-restart.png`
- `18-native-season-two-squad.png`
- `19-native-season-two-paused.png`
- `20-earned-upgrade-loss-attempt.png`
- `21-assisted-defeat-check.png`
- `22-native-post-defeat-replay.png`

## Final focused verification of pause focus and compact timing fixes

I restarted the uniquely identified native review app into the latest source, still on isolated port 45904/profile `3d-beginner`. Only the two reported fixes were checked; no game source, score, unlock, or player state was edited.

**Pause focus — resolved in native runtime.** Native Escape opened the pause menu with a visible gold focus border around Back to the rally (`23-pause-default-focus-fixed.png`). Three native Tab presses moved that border to Leave this run (`24-pause-leave-keyboard-focus.png`). Native Return activated it and the isolated runtime changed to `screen: seasons`. Keyboard-only pause navigation therefore works in the demonstrated path.

**Compact timing — resolved in rendered runtime.** For this bounded visual inspection, I used ordinary 1x playback interspersed with explicitly assisted **0.05x** playback to capture contact states. This is not an ordinary-speed reaction assessment. A native Space input produced a clearly readable `GOOD CONTACT` banner in `25-compact-meter-native-space.png`; that particular capture shows the normal right dock, despite its historical filename.

I then queued another single contact through the ordinary input handler while inspecting the collapsed right dock. `26-compact-queued-contact-fixed.png` visibly shows SPACE highlighted teal, the restored full-width timing meter below the key row, a legible gold timing region, and Jun's complete body plus the ball clear of the controls. The runtime confirmed `hud_compact_right: true`. The prior 62-pixel meter and missing queued highlight are therefore corrected in actual rendering, and this state does not reintroduce the reported deep-defender occlusion.

The timing bar remains peripheral to the ball, but its size/queued-state regression is resolved, and the good-contact banner is visible. No new blocking finding arose in this focused check. It does not establish screen-reader support or subjective timing feel at full speed. Only my isolated runtime was stopped after verification.

Final captures, in `/tmp/spike-3d-beginner-review/`:

- `23-pause-default-focus-fixed.png`
- `24-pause-leave-keyboard-focus.png`
- `25-compact-meter-native-space.png`
- `26-compact-queued-contact-fixed.png`

Selected final native screenshots are preserved in the project under [native-flow](native-flow/), including restart settings, legal S2 selection, defeat/replay, pause focus and compact timing.


### Final Court vision regression review — 2026-09-06

Restarted the unique native reviewer app on isolated port 45904/profile `3d-beginner`, using the genuinely earned existing crown 1/unlocked 2 save. Replayed Season 1 and earned the quarterfinal 5–1 in 68.8 simulated seconds using right tip, with no Space contacts, bots, score overrides, or upgrade overrides. This bounded check used mixed ordinary 1x and assisted 4x progression, plus assisted 0.05x visual inspection; it is not ordinary-speed usability evidence. The full result/offer ledger is preserved in `scouting-independent-earned-offer.json`. Selected the legitimately offered Court vision at index 2.

Scoped verdict: pass. `scouting-independent-no-upgrade.png` shows a rival set with the ordinary preparation cue and no orange scouting ring. After earning the upgrade, `scouting-independent-rival-set.png` and its JSON show rival set, POWER to LEFT, `upgrades: ["read"]`, with the orange ring and cream outline on the left/deep target and the explicit coaching cue. `scouting-independent-rival-attack.png` retains both during rival attack. `scouting-independent-cleared.png` and its JSON show that both clear at the ensuing point; they were also absent during the following serve. The orange/cream ground marker remains distinguishable from the gold active-player ring and does not cover athlete bodies. At the left/deep target during the attack camera, it approaches the bottom edge/name chips, but enough of the outlined target remains visible to identify its position. No blocking legibility finding in these captures.

Source-only verification: `main.gd` prepare_receive still subtracts 0.13 seconds from the own team's reaction delay only when Court vision is owned and `aim_lane == rival_lane`, with a 0.05-second lower bound. This review did not measure the speed difference. Following the visible cue by manually selecting left during attack still lost the point, demonstrating that the upgrade does not guarantee a save; the defensive block lane had already committed right. Ring/text visibility conditions both require rival possession in set/attack and the upgrade. Stopped only this reviewer's runtime after inspection.
