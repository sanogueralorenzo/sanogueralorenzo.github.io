# Independent visual and athletic-animation review

Latest review status: all concrete correction requests below have been implemented and received their scoped follow-up checks. The final scene is `visual-art-final.png`; its ordinary runtime snapshot is `visual-art-final-state.json`. Historical findings and their resolutions are retained to distinguish initial defects from the final state. The finished visual treatment is a coherent procedural graphic illustration; it remains flatter and less naturalistic than the supplied painterly reference.

Reviewed 2026-09-05 by an independent agent. Compared the supplied volleyball-art-direction.png with evidence/08-lantern-harbor.png and a fresh Godot 4.7.2 runtime using review port 45904, isolated profile `visual`, and normal simulation speed (1.0). Read athlete.gd, scenery.gd, and main.gd. No gameplay state overrides, bots, automated tests, or code edits were used. A bounded screenshot sequence recorded ordinary assisted warm-up play; a manual power-shot selection exercised the existing input path.

## Verdict

The revised game is substantially clearer than evidence/02-warmup-auto.png: six-player court width, full teal opposing kits, larger face portraits, longer athletic proportions, foliage framing, building roofs and balconies, and pre-contact set anticipation are all improvements visible in runtime. The previous grounded-contact/late-jump defect is corrected for ordinary set/attack preparation in code and the observed set sequence.

It still does not match the target's painterly naturalism or convincing athletic staging. It is a coherent, stylized flat illustration with procedural characters. This distinction should remain explicit in delivery claims. The visual target has volumetric bodies, directional pose silhouettes, richer material variation, larger expressive faces, and naturally structured foliage; noise/grain and more decorative details alone cannot close that gap.

## Initial substantive findings (historical; see focused recheck below)

1. **Net anatomy and opponent visibility.** main.gd draw_net uses top height 183 and a bottom at ground minus 22, producing a roughly 161-pixel mesh skirt extending almost to the floor. The target net is a suspended band; current geometry obscures much of opponents' bodies and makes the court read like a fenced enclosure. Preserve the top height and suspend a roughly 85–90-pixel mesh band beneath it, leaving visible clearance below. Match vertical strands, horizontal rows, and bottom tape to that band.

2. **Receive contact remains detached from the forearms.** In normal-speed action-13.png (reported 0.07 seconds before contact), the ball is left of the receiver's chest while joined hands are roughly 25 pixels right and down. In action-14.png just after contact the ball is still around chest level. The pose has joined hands but does not orient its platform into the incoming ball. Supply projected ball offset to the rig and blend the forearm platform toward a physically reachable contact point during the final approach; use the body lean and elbow position to support that reach. Avoid arm stretching without anatomical bounds.

3. **Spike hand calibration is close vertically but offset horizontally.** rally-13.png is 0.06 seconds before attack contact; the right hand still sits below and to the right of the ball. At action=0.5, the current mathematical right-hand offset is about +24 pixels from a ball centered over the actor's world position, while vertical reach is approximately aligned. Ball radius partly conceals the gap. Calibrate hand target to the actual incoming ball and then move through a clear one-arm follow-through. The current two raised arms make a roll/spike silhouette look too similar to a set.

4. **Serve retains the old timing defect.** serve() still assigns action=1.0 at launch, unlike animate_contact() assigning 0.5. No pre-serve anticipation is present in the inspected tick branch. The serve therefore begins its jump after launch. Add a visible toss/wind-up during the end of the serve countdown and begin follow-through at impact. The ball's held height and flight start height also change abruptly (about 1.25 to 1.7).

5. **Ball height discontinuity at a receive.** perform_attack ends the incoming flight at 0.75, while the subsequent pass launches at 0.95. Even when the assisted contact succeeds, this creates a small vertical pop between trajectories. Carry forward the incoming contact height or deliberately align both to the rig's contact point. The good setter calibration provides a useful baseline: action-22.png, 0.03 seconds before contact, shows the ball plausibly between/above the setter's hands.

## Remaining art-direction gap

- Athletes still face the camera regardless of their place on court. Moving pupils help, but a near-side athlete should have a three-quarter body/head angle toward the ball and opponents. Add visible shoulder/hip opposition, stronger knee bend, and side-facing approach poses. Characters currently read as articulated paper figures rather than weight-bearing athletes.
- Hair differences are chiefly scaling one silhouette. More distinct fringe profiles, eye/brow proportions, and asymmetric mouth shapes would make original teammates recognizable without jersey numbers. Portrait labels visibly overlap the very bottom of the jersey silhouette; reserve a solid label strip below the art.
- Cloud circles remain visibly scalloped and stamped. Use a smaller number of large, irregular connected masses with cooler undersides and warmer crowns. Vary their edge detail; leave quiet blue-sky areas.
- Town façades now have useful roof/balcony depth, but uniform pale values weaken the target's sunlit coastal character. Deepen awning/window recesses and introduce cool shadow planes under balconies, retaining warm lit walls.
- Directional player shadows are an improvement, but they are repeated angular wedges without changing arm/leg silhouettes. Derive simplified silhouettes from the pose, keep both foot contacts legible, and soften distant edges. Ground foliage shade is still an even scatter rather than connected branches and clustered light gaps.

## Evidence and limits

Fresh normal-speed screenshots are in `/tmp/spike-visual-review/`: `action-13.png` / `action-14.png` (receive), `action-22.png` / `action-23.png` (set), `rally-11.png` through `rally-14.png` (approach and attack), and `rally-22.png` / `rally-23.png` (rival receive). A manually selected power attack produced a visible block and the ROOFED feedback in `power-12.png` through `power-14.png`; the subsequent failed coverage awarded a rival point through normal play. This establishes that block presentation occurs, but these spaced captures do not isolate the exact hand-impact frame. The corresponding `action-states.json`, `rally-states.json`, and `power-states.json` record phase, timing, and simulation speed. Timing values are from the command response immediately before the rendered capture, so frame-exact contact cannot be claimed from these screenshots. Contact-offset calculations additionally use the inspected rig/projection formulas.

This review does not establish subjective fun, audio quality, advanced tactical fairness, nine-season completion, or save reliability. Those require separate gameplay evidence. Re-review the corrected contact frames, serve, and suspended net before claiming those findings resolved.


## Focused recheck after five fixes

A second fresh runtime used isolated profile `visual-recheck`, port 45904, and simulation speed 1.0. Captures are `/tmp/spike-visual-recheck/check-00.png` through `check-52.png`, with `states.json`. No gameplay automation or state overrides were used; this sequence recorded ordinary default assisted warm-up play.

- **Suspended net: resolved in source and observed.** Top is ground minus 183; bottom is ground minus 102, with ten horizontal rows. The far team's lower bodies and court separation are visibly clearer across the new captures.
- **Serve anticipation: resolved at the earlier defect's level.** Source now prepares the pose during the final 0.45 seconds, tosses from held height to 2.6, and releases at action 0.5. `check-12.png`, `check-14.png`, and `check-15.png` show the wind-up/toss/release sequence. The jump is no longer triggered only after ball launch.
- **Receive trajectory height: resolved in source.** The outgoing pass inherits current ball_height. `check-28.png` / `check-29.png` show coherent contact-to-pass progression rather than the earlier prescribed height jump.
- **Hand alignment: improved, with an important new failure case.** The final-window hand targeting brings the hands toward the actual ball in the observed successful receive (`check-28.png`, 0.03 seconds before contact) and attacking follow-through (`check-46.png`, immediately after attack). However, the target is not constrained to anatomical reach: see the blocking finding below.

### Remaining blocking animation finding

**Unbounded hand targeting makes failed receives look physically possible.** `check-51.png` is 0.03 seconds before a failed near-side receive. Ren's forearms stretch roughly 100 screen pixels sideways, approximately twice the ordinary combined arm length, until his hands visibly touch the ball. The next phase awards a rival point. This is both an anatomy problem and misleading feedback about a physically unreachable contact. Cap shoulder-to-hand length (approximately 50–55 local pixels is a reasonable starting bound for this rig), support the extension with a finite lunge/lean, and let unreachable balls pass beyond the hand. Full contact alignment must be reserved for contacts within the same reach limits used by gameplay. Retain forearm/elbow segment proportions rather than merely moving an elbow to the midpoint of an arbitrarily distant hand.

The inverse-transform expression also adds the torso's vertical offset after rotation; the offset belongs inside the inverse rotation. This is a smaller calibration issue (approximately 8 pixels at a strongly leaning spike) and was sent to the implementation agent. It does not negate the larger improvement observed here.

### Most valuable remaining art-direction work

After bounding reach, the highest-value tractable improvement is pose direction and weight: turn the near-side torso/head three-quarters toward the rally, deepen ready-stance knees, and make spike shoulder/hip rotation visibly different from a set. The current camera-facing anatomy is still the strongest mismatch with the target's convincing athletic motion. For scenery, replace the repeated scalloped clouds with several irregular broad masses and consistent cool undersides, and add dark balcony/awning recesses to increase sunlit depth. These changes would contribute more than additional grain or small props.

Current verdict: the five earlier fixes materially improve court anatomy and contact presentation, but the newly visible elastic-arm failure must be corrected before contact animation can pass this review. The remaining overall target-fidelity gap should still be disclosed; no claim of matching the reference's painterly naturalism is supported.


## Final bounded-reach recheck

A fresh final runtime used isolated profile `visual-final`, review port 45904, and simulation speed 1.0. Source now caps shoulder-to-wrist reach at 52 local pixels, uses the 28/26 two-segment elbow solution, and correctly applies the inverse torso transform. The same ordinary opening rally reproduced both a successful opposing receive and the previously elastic failed near-side receive.

- **Successful contact:** `visual-contact.png` records the receive approximately 0.03 seconds before its resolution. The following frame increments the rally-contact count and begins the pass. Forearms meet the ball without the prior detached platform.
- **Missed contact:** `visual-miss.png` records the failed near-side receive approximately 0.06 seconds before resolution. The extended arms stay finite and the ball remains visibly beyond the hands. The following frame awards the rival point with OPEN COURT feedback. This directly revisits the failure shown in the earlier `check-51.png`; the approximately doubled elastic arms are no longer present.
- `visual-contact-states.json` preserves the before/after runtime snapshots for these two observations. Extra captures remain in `/tmp/spike-visual-final/`. Capture timestamps are approximate, not frame-exact.

**Final focused verdict:** the suspended-net, serve-preparation, receive-height, hand-calibration, and unbounded-arm findings are resolved to the extent demonstrated by these inspected sources and ordinary runtime contact/miss frames. No further blocking contact-presentation defect was observed in this focused check. This is a pass for those concrete corrections, not a claim that every possible contact animation is verified or that the game matches the target's painterly naturalism. The documented camera-facing character poses, limited weight transfer, repeated clouds, and simplified lighting remain substantive art-direction limitations. The review runtime was stopped after capture.


## Follow-up art and pose review after shading/turn revision

Fresh runtime profile `visual-art-final`, simulation speed 1.0, recorded an ordinary opening rally in `/tmp/spike-art-final/`. `visual-art-final.png` is an unmodified runtime capture of the rival's attack preparation. Successful receive, set, and the previously failed reach were also inspected (`art-00.png`, `art-09.png`, and `art-23.png`). The finite-arm miss remains clear; no regression of the earlier contact bounds was observed.

Visible improvements: the new broad cloud masses remove the repeated scalloped pattern and leave quieter sky; Jun now has a distinct fringe silhouette; shaded tapered limbs and jersey folds add form; asymmetrical shoulders and attack lean introduce more direction. These are demonstrated changes, though the body turn is still subtle at gameplay size.

### Concrete remaining corrections

1. **Finish the recovery animation instead of snapping into ready.** The set/block branches keep both hands around local y=-127 until action reaches zero, when tick immediately switches to ready with hands around y=-56. This is a roughly 70-local-pixel wrist discontinuity. The observed opposing setter has raised hands in `art-11.png` and hands near his hips in the next capture, `art-12.png`; source establishes that this is a discontinuous switch rather than a smoothly sampled recovery. Blend hands and elbows toward the moving ready pose over the final action 0.30-to-0 interval. Spike's guide arm should lower during follow-through instead of remaining overhead until the same reset. This is the highest-impact remaining tractable animation correction.

2. **Use articulated shadows, not repeated wedges.** Every athlete still has essentially the same angular shadow despite raised arms, jumps, and crouches. In the attack capture the athlete floats over a shadow that retains the idle wedge silhouette. Reuse a simplified pose skeleton (torso/head plus two bent arms and legs), project it along the established sun direction, and vary opacity with jump. This makes the new anatomical shading and jump height legible as weight and light rather than disconnected decoration.

3. **Give foreground trunks the same material care as leaves.** The two large framing trunks remain broad, nearly uniform green strips. They occupy substantial visible area and conflict with the detailed generated foliage. Add a dark warm-brown core, an irregular lit edge, a few long broken bark strokes, and uneven taper/forks. Keep the texture directional and sparse; uniform grain will not supply bark structure.

4. **Connect the court to a recognizable shoreline.** The target has coastal rocks and bright foam marking the cliff/sea boundary. The current left edge reads as a flat cyan plane behind a railing, with no clear ground-to-water transition. A small set of layered rocky silhouettes with cool shadow faces and broken pale foam along their bases, restricted outside the court, would add coastal depth without impacting readability or requiring external assets.

The target-fidelity gap remains meaningful: procedural flat figures and shallow environment values still read more like a graphic illustration than the reference's painterly sports scene. However, the specific improvements above are achievable within the present renderer and would address motion discontinuity, grounding, material structure, and coastal geography rather than merely restating that gap. The prior focused contact pass remains valid, but the recovery snap should be corrected before the animation is described as polished.


## Recovery and pose-shadow follow-up

The final recovery blend was rechecked in a fresh normal-speed `visual-settle` runtime. `/tmp/spike-visual-settle/settle-02.png`, `settle-03.png`, and `settle-04.png` now show the setter's hands overhead, then visibly lowering, then in the ready pose. Source interpolates elbows and wrists during action 0.30-to-0 and preserves the receive's baseline crouch. **The recovery discontinuity is resolved in the observed sequence.**

A further fresh `visual-shadows` runtime verified that the previously identical wedges were replaced with separate foot/leg, torso, arm, and head projections; raised-arm and grounded poses now have different ground shapes. `visual-art-final.png` was refreshed from `/tmp/spike-visual-shadows/final-shadows.png` to show this latest scene. The screenshot is ordinary set preparation at simulation speed 1.0.

One small shadow-finishing issue remains visible: head shadows are separate circles and several overlapping translucent limb rectangles produce darker bands. Add a chest-to-head neck segment and rounded joint caps; for the cleanest result, composite the connected silhouette once at the intended opacity instead of accumulating translucent segments. This is a specific finishing issue rather than a request for a renderer rewrite.

Current concrete status: contact bounds, contact/miss presentation, net suspension, serve preparation, receive-height continuity, and recovery transitions pass the focused observations documented above. Pose-dependent shadows and stronger character/cloud rendering are visibly present. The remaining material/geography recommendations are warm textured foreground bark and a defined rocky/foam shoreline, alongside the broader limitation that the current renderer still produces a flatter and more graphic result than the supplied target. These have not been silently marked complete. No automated tests were created or run for any part of this visual review.


## Final finishing confirmation

Fresh runtime profile `visual-finish`, port 45904, simulation speed 1.0; captured an ordinary set preparation at match time approximately 4.9 seconds. `visual-art-final.png` and `visual-art-final-state.json` now contain this latest source's image/state.

- **Connected shadows confirmed:** rounded joints and a neck connection remove the detached head circles. The clay-preblended silhouette removes the previous darker overlap bands. Shadows remain distinguishable between the raised setter and grounded teammates.
- **Foreground bark confirmed:** long irregular strokes and separate lit/shadow planes are visible on both large trunks. The foreground now has material structure consistent with the detailed foliage.
- **Shoreline confirmed:** faceted rocks and broken foam trace the outer left edge of the court against the clearer blue water. They remain outside the playing area and do not obscure athlete or ball tracking.

No regression in the suspended net, six-player readability, selected-player cue, or ordinary setter pose was observed in this final scene. This was a scoped finishing inspection, not a replacement for the earlier normal-speed contact, miss, and recovery observations. The previously requested concrete visual corrections are resolved to their documented verification scope. No further specific correction request is raised by this final inspection. The broader stylistic difference from the original reference remains accurately described above. Runtime 45904 was stopped after inspection.
