# Independent review: integrated 3D scene

**Overall final-image art-direction judgment:** see [overall-art-direction-verdict.md](overall-art-direction-verdict.md). The scoped construction/readability passes below remain valid, but the explicit final normal-frame comparison does not certify the original reference-fidelity bar as fully met.

Latest scoped verdict: **passes the representative-coast construction/readability recheck and the finite reported corrections.** A final restart shows restored faces/eye whites, closed rounded shoulders, and no tan skin wedges through the jersey in ready and receiving poses. Normal portraits retain distinct expressions, and the fuller darker headlands form coherent distant layers. This is a scoped approval of the corrected stylized 3D presentation, not a claim of equal painterly fidelity to the reference or approval of the full game. Final evidence and limits are recorded at the end; older failures below are historical.

Reviewed 2026-09-06 against the approved `volleyball-art-direction-3v3.png`. This is a fresh review; earlier 2D approvals do not apply. Used a separate Godot 4.7.2 Forward Plus runtime on port 45902, profile `3d-visual`, normal simulation speed 1.0, and the authored camera first. Source inspected: `scripts/three_d/presentation.gd`, `athlete.gd`, `geometry.gd`, the uniform shader, and the current HUD. No game source edits or automated tests.

## Verdict

**Not approved for the requested finished visual standard.** This is genuine dimensional geometry with meaningful parallax, real shadows, a 3D net/court, and a recognizable coastal setting. Those are a substantial change from the 2D baseline. The current ordinary gameplay composition nevertheless reads as a distant toy-scale sports court in front of a simple architectural blockout. The faces, clothing junctions, net visibility, and scene materials do not yet support the approved image's expressive athletes and painterly coastal depth.

The highest priority is the ordinary camera and character presentation, followed by net/HUD contrast and environment depth/material variation. A close camera inspection does not substitute for normal-play fidelity.

## Authored-camera evidence

| File | Observed state | What it establishes |
|---|---|---|
| `review-normal-wide.png` | Receive, remaining approximately 0.04 s; authored camera near `(1.6,4.86,16.85)` | Ordinary deep-target framing, six-player scale, net/HUD visibility |
| `review-normal-set.png` | Set, remaining approximately 0.01 s; same backed-out camera | Attacking hands/ball are very small against architecture; far pair partially overlap |
| `review-normal-attack.png` | Attack, remaining approximately 0.13 s; camera near `(1.6,4.46,15.23)` | Camera moves forward during the setup, but players remain small relative to background and HUD |
| `review-normal-states.json` | Runtime snapshots for the normal sequence | `camera_inspection=false`, simulation speed 1.0, phases/positions; timestamps precede the rendered image by a frame |

The normal captures are unmodified runtime images. Reported FPS dropped during repeated screenshot readback while other runtimes were active, so these captures do not establish an isolated performance benchmark.

## Initial prioritized findings (recheck status below)

### P1 — The camera makes the athletes secondary to architecture

In the backed-out 1280×720 frame, the near-back athlete is approximately 150–160 pixels high, while far defenders are around 65–80 pixels. The target gives the near-side setter/cover athletes much greater foreground presence and distinct facial/body silhouettes. Here the buildings occupy most of the upper half, while the six athletes read as small pieces on a board. The far ball is barely more than a few pixels across.

`presentation.gd` uses the maximum of each near player's current and target depth to retreat from Z=14.8/FOV39 to Z=17/FOV43. Thus a deep future target can shrink the entire rally before a player reaches it. The normal sequence also moves the camera forward during setup and backward at the following receive. Refine the camera around visible current court/action extents with deliberate anticipation; do not retreat solely because any off-ball target is deep. Keep near-side faces/torso larger in ordinary play, while explicitly preserving the baseline serve and the deepest valid receive. Increasing every body mesh independently of court physics would be a poor substitute for solving framing.

### P1 — Player construction remains visibly mannequin-like

A labeled close inspection (`review-DEBUG-character-closeup.png`) confirms volumetric meshes rather than billboards, but also exposes junction/material problems:

- Shoulder attachments read as separate flat circular caps; upper arms meet a hard shirt edge without a convincing deltoid/armhole transition. Shape shoulder/upper-arm overlap so the contour is continuous, and add a thin sleeveless armhole edge integrated into the shirt surface.
- The gold collar is made from thick protruding bars floating above the chest, resembling armor straps. Replace those with a thin curve or surface-following trim around a visible neckline opening.
- The long, constant-width neck, smooth round nose tip/ear blobs, and symmetric cheek surfaces give a mannequin face. Shorten/taper the neck, preserve a visible jaw-to-neck transition, and shape the nose bridge/cheek planes more deliberately.
- The expression is nearly neutral and half-lidded. The target's character appeal comes from focused eyes, strong brows, jaw/mouth expression, and directional head posing. Use visibly different brow/upper-lid/mouth configurations for ready focus and exertion, not just a small mouth-height scale. Keep eyeballs/lids integrated into the face surface rather than pasted bright shapes.
- The three identities currently differ mainly by hair/skin parameters. Give the portrait-visible jaw, eye/brow proportions, and hair mass/fringe profiles enough difference to recognize teammates without labels.

These are concrete procedural-mesh/face-authoring changes, not a request for downloaded models.

### P1 — Portraits undercut the intended character quality

The three lower-left portraits are dark, flat, and framed almost identically. They read less expressive than the former drawn cards, despite using genuine 3D models. The portraits are the only consistently large faces during gameplay, so their quality cannot be deferred to a debug closeup. The dedicated viewport camera/light should show a warm face key light, cool but gentle fill, visible iris highlights, a slight three-quarter view, enough hair/shoulder margin, and distinct expressions/poses. Re-check them at the actual 71×103 HUD draw size, not just their 213×309 render source. Avoid hair clipping against the top edge and faces sinking into dark brown values.

### P1 — Net strands become a pale dotted ladder

In normal frames, net strands have weak dark continuity and break into bright dotted/sparkling intersections against the pale cafe terrace. The top tape is not a sufficiently clear organizing line. The current 512×128 alpha-scissored net texture uses one-pixel strands, then mipmaps/downsampling reduce their coverage. Increase strand coverage/resolution consistently or use thin actual geometry for the key strands; preserve a continuous dark grid at gameplay scale without making an opaque fence. Strengthen the pale top tape and dark net/post contrast. The existing physical band height/clearance is reasonable and should be retained.

### P1 — Two important HUD labels lose contrast over scenery

The top-right rival/team/rules text is dark directly over dark foliage and is difficult to read. It needs a small cream backing or a reliable contrasting region. The bottom optional-timing labels and narrow meter are pale against bright ground/foliage and similarly weak. Keep the compact layout, but provide a stable dark/cream backplate for the whole timing group. This is a functional readability correction, not ornamental UI expansion.

### P2 — The default stance communicates waiting, not readiness

All non-contact athletes often read as hands-on-hips, with elbows far out and little meaningful knee/hip loading. The target's defenders look alert and able to react. The source's default wrist near `torso + (side*.31,.13,-.11)` combined with outward elbow hints creates the hands-on-hips impression. Place ready wrists forward and lower, elbows closer to the body, hips slightly back, knees bent, and weight unevenly on the feet. The animation/fairness reviewer owns timing and foot-plant verification; this finding concerns the silhouette visible in ordinary play.

### P2 — Environment masses remain overly uniform and unfinished

The implementation agent is already addressing camera and environment; these observations independently confirm the same priorities:

- Ocean is a broad blue plane with evenly spaced horizontal streaks, without natural scale variation or a convincing near-shore transition.
- The distant headland is one smooth/blocky pale mass with almost no rocky silhouette or layered atmospheric depth.
- Architecture repeats the same flat cream material, regular window rectangles, and oversized uninterrupted walls. Two near-identical CAFE SOL facades expose modular repetition.
- The steep stairway is a broad geometrically uniform ramp of steps, without landing breaks, irregular wall heights, planting interruptions, or human-scale detail.
- Tree trunks are clean polygonal poles and branching forks; planting repeats a closely spaced row of equal round pots. The leaf-card canopy is the strongest environment element, but the whole landscape still needs clustered variation and larger lit/shadow planes.

Do not add small props before correcting these large masses. The approved scene has a distinct cafe terrace, receding side streets, broken roof heights, interleaved vegetation, and a coast that falls away below the court. Actual 3D depth exists now; it needs more careful composition and material/light separation.

## Debug evidence boundaries

`review-DEBUG-character-closeup.png` used a deliberately moved inspection camera, slowed simulation to 0.05, and is explicitly **not ordinary gameplay framing**. It was taken after the authored-camera sequence to inspect mesh construction. It must not be used as proof of final gameplay composition, normal responsiveness, or target-level facial readability. The temporary inspection camera was confined to this reviewer's isolated session.

## What to re-review next

Obtain a fresh ordinary-camera frame for deep receive and near-side attack after camera changes; examine faces both at real portrait size and a labeled mesh closeup after the shoulder/collar/face pass; confirm continuous net strands and stable rival/timing text contrast. Keep the real court dimensions, coherent world-space contacts, and genuine 3D environment. Until those concrete issues are addressed, the current source should be described as an integrated 3D implementation under refinement, not a finished visual match.


## Fresh recheck after net, HUD, portrait, collar, ready-pose and camera changes

Restarted only the reviewer's own port 45902 process, isolated profile `3d-visual-recheck`. The new normal-camera sequence is preserved in `recheck-normal-wide.png`, `recheck-normal-set.png`, `recheck-normal-attack.png`, and `recheck-normal-states.json`; camera inspection is false and simulation speed is 1.0. Architecture was still being revised by the implementation agent, so these images establish this source snapshot, not later environment changes.

| Finding | Recheck result |
|---|---|
| Net continuity | **Resolved in observed normal frames.** Actual dark merged strands give a continuous net band; the earlier pale dotted ladder is gone. |
| Top-right rival text | **Resolved.** Cream backing restores stable contrast over foliage. |
| Portrait exposure/framing | **Substantially improved.** Faces are brighter, full hair silhouettes fit, and head angles differ. The cards now show recognizable identities rather than dark cropped busts. Their facial expression remains simple and mostly neutral compared with the target. |
| Floating collar bars | **Corrected in source and reduced at gameplay/portrait scale.** Thick detached beams were removed and replaced by a thin neck-opening ring. No new post-fix debug closeup is claimed in this check. |
| Shoulder/neck form | **Partial.** Source reduces joint caps and shortens the neck; a new detailed face/shoulder inspection remains necessary before claiming the underlying mannequin-like form fully resolved. |
| Hands-on-hips ready silhouette | **Improved in observed frames.** Wrists now sit forward/down and elbows no longer flare outward. Timing/foot mechanics remain the animation reviewer's scope. |
| Ocean striping | **Improved.** The close water is now turquoise with finer variable glints; the original broad even blue bands are reduced. Distant headland and architecture remain visibly simple in this capture. |
| Ordinary player scale | **Unresolved.** See below. |
| Optional-timing label contrast | **Unresolved.** Pale labels/meter still lie over bright ground and are weak in the final lower-right group. |

### Camera change currently compensates itself

The deep-frame camera is closer (approximately Z=14.45 rather than 16.85), but its FOV also expands from around 43 to around 51. In the new ordinary deep frame, the near-back athlete remains about 150–160 pixels high at 720p, essentially the same as before; far defenders remain about 65–80 pixels. Thus the source settings changed substantially but the intended increase in ordinary athlete presence is not demonstrated. The target still gives characters much greater visual importance.

A tractable alternative to ever-wider FOV is to make the rendered 3v3 court coherently shallower: for example, map logical depth 16 into world depth 12–13 using one shared depth scale for court, actors, ball, targets and shadows. Then the camera can move closer without clipping the deepest legal receive. This is a proposed composition adjustment, not a claimed verified solution, and must preserve world-space contact/animation consistency. The implementation agent owns that decision. The important acceptance condition is measured normal-screen player size and readability, not a particular camera position number.

Current overall verdict remains **not approved for the final visual target**. Several practical contrast and construction defects are fixed, and the scene is clearly improving. The ordinary camera still leaves the athletes secondary to large simple architecture, while the remaining facial/material depth and environment composition require a further pass. No debug closeup has been substituted for that normal-play judgment.


## Compact-court, environment and character recheck

Fresh runtime `3d-visual-compact` on the reviewer's own port 45902. The ordinary sequence used authored camera, speed 1.0, with no camera override: `compact-normal-serve.png`, `compact-normal-receive.png`, `compact-normal-attack.png`, and `compact-normal-states.json`. A later ordinary deep-right receive was captured read-only near its contact; `compact-normal-deep-corner.png` and `compact-deep-corner-state.json` preserve it. A conditional screenshot trigger selected a near-contact frame but sent no gameplay input or score/physics changes.

### Demonstrated improvements

The shared shallow-court mapping now increases actual ordinary athlete presence: near athletes are approximately 175–190 pixels high at 720p in the centered action examples, and far defenders about 95–105 pixels. This is a meaningful improvement over the earlier wide-FOV compensation. The net stays legible and the selected ring is clear. The single cafe, lower front row, warmer building variation, ivy, irregular pots and stair opening improve the depth hierarchy. The optional-timing group now has a stable cream backing and readable dark labels. Hair masses are more coherent, the detached collar bars are gone, ready arms remain forward, and portrait exposure/framing remains improved.

### P1 — Deep-corner action is hidden by the HUD

The later near-contact frame is decisive: at ball world position approximately `(3.86,1.14,5.69)`, receive time remaining 0.05 seconds, inspection camera false and speed 1.0, the deep-right athlete and the ball/contact region are almost entirely hidden behind the lower-right control group. Only five athletes are readable. The body, ball and landing region cannot be judged merely by checking centered attacks. The ordinary deep-left serve also partly overlaps the portrait group.

Reserve the projected deep-corner contact volumes from HUD occlusion. Move/condense controls into safe margins or a thinner bottom row, or use a carefully designed context-aware relocation/fade that preserves control discoverability. Do not solve it solely by pulling back to the earlier tiny-athlete camera. Recheck both deep corners, actual serve positions, and their forearm/hand contact locations after the fix. This remains a functional blocker regardless of improvements to scenery.

### P1 — Facial appeal and organic construction remain unfinished

`compact-DEBUG-face-jun.png` is a labeled inspection-camera closeup at speed 0.05 and is not gameplay framing. It confirms the thinner collar and coherent swept hair, but Jun still has a button-like spherical nose tip, nearly symmetric broad face, neutral oval mouth and limited eye/brow expression. The shoulder joints remain visually separate rounded caps at the armholes. Compared with the reference's angular cheeks, expressive eyes and athletic shoulder anatomy, the character reads as a stylized mannequin.

Highest-impact concrete corrections:

- Integrate the deltoid into the armhole/upper-arm silhouette; avoid a separate skin ball sitting outside a hard-edged shirt opening.
- Reduce the round nose-tip bulb and shape the bridge/tip as a small wedge with a shaded underside; the current protruding sphere dominates the face at portrait scale.
- Give each teammate distinct jaw taper, eye aperture/brow angle, and mouth corners, beyond hair/skin parameters. Preserve an intentional focused expression in readiness.
- Use a curved neutral lip line and a dark inner mouth/teeth shape for exertion or smiling. Scaling a single brown oval produces a generic vacant/open-mouth look.
- Let the eyes/upper lids and brows communicate ball focus and exertion clearly. Their closeup detail should remain readable when reduced to the real HUD portrait size.

These changes should be judged in an ordinary portrait-sized render as well as a labeled closeup. The current broad bright face lighting is readable, but it does not by itself create expression or convincing form.

### P2 — Remaining scene-depth polish

The composition is more coherent, but the large blank upper wall above the cafe and regular window grids remain dominant simple surfaces. The front-row roof/eave and balcony shadow planes can be stronger and more varied without adding lots of props. The clay remains a broad even orange field; restrained larger-scale tonal scuffs/mottling would support the painterly reference better than uniform fine noise. The pale headland still reads as a single smooth silhouette. These are secondary to fixing the hidden deep-right action and the character face/shoulder construction.

Current verdict remains **not approved as the finished target match**. The ordinary centered action has passed the prior size concern at a useful level, and the timing contrast correction is visible. The deep-corner HUD occlusion is a fresh demonstrated blocker, while the facial appeal gap is supported by both real portrait scale and labeled close inspection. No gameplay animation/fairness certification is implied by this visual review.


## Fresh face, shoulder, ink and corner-HUD recheck

Restarted the reviewer's own port 45902 process using isolated profile `3d-visual-face-corners` after the thin ink/blink/open-mouth follow-on. Ordinary-camera captures were made first, at simulation speed 1.0. No game source was edited, no automated tests were created, and no parent runtime was operated. The snapshot includes the integrated sculpted nose/cheeks, different head scales/eye apertures/brow heights, upper-arm loft in place of shoulder spheres, and adaptive corner HUD.

Source identity at this review:
- `scripts/three_d/athlete.gd` SHA-256 `c95919024caabd65`
- `scripts/three_d/presentation.gd` SHA-256 `40eba9899b4d9aea`
- `scripts/interface.gd` SHA-256 `18b3123a6f86ec99`

### Demonstrated corrections

- **Left serve occlusion resolved in observed frame.** `face-corners-normal-left-serve.png` shows Ren fully visible, including shoes, while the portrait dock reduces to name chips. The state has `hud_compact_left=true`, `camera_inspection=false`, `speed=1`, ball `(-3.08,1.25,5.92)`, and match time 1.4 seconds. The remaining name row lies below the contact silhouette.
- **Deep-right receive occlusion resolved in observed frame.** `face-corners-normal-deep-right-receive.png` shows Jun, his receiving action, and the ball exposed instead of hidden behind large buttons. State: receive/near team, remaining 0.08 seconds, ball `(3.325278,1.154622,5.172702)`, authored camera `(1.2,4.58114,12.64342)`, `hud_compact_right=true`, speed 1, match time 48.0 seconds. The shot/lane information remains available in the top-right panel, with the low key legend at the bottom. This resolves the prior demonstrated functional composition blocker at that corner; it does not assert exhaustive coverage of every possible silhouette.
- **Portrait restoration observed.** `face-corners-normal-portraits.png` shows the full portrait dock restored once the left area is clear. All three hair silhouettes and faces fit and have usable exposure.
- **The attached nose-ball problem is corrected.** The debug closeup has a continuous nose/cheek surface with no separate round tip stuck onto the face. Source confirms sculpted geometry.
- **The detached circular shoulder mass is corrected.** The debug closeup shows continuous tapered upper arms. The thin gold edge is much less intrusive than the earlier caps. Neck opening remains thin, closed, and integrated.
- **Warm ink is restrained.** It strengthens edges without turning the observed normal scene into a thick black outline treatment. Blinking is present in source; these still images do not demonstrate its temporal quality.

### Remaining substantive art work

**P1 — Portrait expression still falls below the brief.** Judge `face-corners-normal-portraits.png` at its native 1280×720 size: hair and skin differentiate teammates, but all three faces read mostly straight ahead and emotionally neutral. Kai's white teeth strip is only a tiny line; Ren and Jun's mouths are scarcely visible. Their brows are partly concealed by fringe. The reference's cards communicate focused, excited, and composed personalities instantly. This is not solved by a higher-resolution viewport: the displayed face area and authored expression are the constraints. Tighten framing modestly toward head/face (there is currently substantial yellow upper-shirt area), preserve hair margin, and author three stronger expression poses with distinct brow angles, eye aperture, mouth width/shape, and cheek response. In source the portrait difference is principally head angles and mouth Y scale (`0.011` versus `0.004`); give those expressions distinct silhouettes instead of only scaling one lip shape. A slightly asymmetric focused Ren, openly smiling Kai, and composed Jun would be a concrete set to assess at native HUD size.

**P2 — The closeup still exposes a very long, pointed lower face and small oval lip.** `face-corners-DEBUG-face-shoulder-jun.png` now has a better integrated nose, but the nose-to-chin region remains smooth and elongated and the lip reads as a flat brown oval rather than an expressive mouth crease. A modestly fuller lower jaw, clearer chin plane, and narrower closed-mouth crease with raised/uneven corners would improve the ready face. Exertion can retain the larger dark opening and teeth. The goal is not photorealism: it is the clear facial planes and purposeful expression already present in the approved stylized image.

**P2 — The armhole edge still reads partly as an armband.** Removing shoulder balls is a real correction. In the closeup, however, the gold ring surrounds the upper arm below the pointed shirt shoulder while the shirt edge remains angular. It is not a regression or a contact blocker; it is a remaining clothing-integration detail. Fit the sleeveless cutout to the shoulder contour and align the trim with that cutout instead of letting a complete ring sit below the shirt tip.

**P2 — Large environment masses still limit reference fidelity.** Current ordinary frames retain a nearly uninterrupted beige wall above the cafe, repeated dark window rectangles, a broad bright headland slab at the left horizon, and little visible fallaway into rocky shoreline. The foliage and real tree/court shadows provide the strongest painterly depth. The next effective scenery changes are to break that blank wall with a setback/terrace/planting mass and give the headland a lower irregular rocky silhouette with layered atmospheric values, rather than adding tiny distant props. This was observed in this snapshot; later environment revisions need their own comparison.

### Evidence boundaries and verdict

`face-corners-DEBUG-face-shoulder-jun.png` is a labeled inspection camera at approximately `(1.79,1.74,3.05)` with simulation slowed to 0.05. It is useful for sculpt/cloth junctions only and is not evidence of ordinary action scale. The preceding normal images all use authored camera and speed 1.0. Captures can reduce FPS during GPU readback and were made alongside other runtimes; they are not a clean performance benchmark. No claim about fun follows from these images.

**Scoped verdict:** the observed corner-HUD blocker is fixed; prior detached nose/shoulder defects are substantially corrected. The latest ordinary composition is readable and has an inviting summer palette. **Still not approved as a finished match to the requested character/art standard**, chiefly because actual portrait expression and the remaining large scenery masses visibly fall short. The specific changes above are finite, tractable authoring work, not a request to replace genuine 3D or acquire external assets.


## Expression, jaw, sleeveless jersey and scenery recheck

Fresh own runtime on port 45902, profile `3d-visual-expressions`, includes the revised portrait camera/expression poses, fuller jaw, true jersey cutouts, cafe facade spacing/balcony, coastal slope and angular distant headlands. Ordinary authored-camera captures came first at speed 1.0. `expressions-normal-scenery-serve.png` and `expressions-normal-portraits.png` are native runtime evidence; their corresponding state JSON records camera inspection false. No game-source edits or automated tests.

### Corrections demonstrated

- **Portrait expressions improve materially at native HUD size.** Ren now reads as focused, Kai visibly smiles, and Jun is composed. The faces occupy more of their cards and the exposed brows communicate expression. Full hair silhouettes still fit. This resolves the specific previous finding that Kai's smile was only a barely visible teeth strip and all cards looked emotionally neutral. These remain simple procedural faces rather than the reference's rich illustration, but repeating the earlier all-neutral finding would be inaccurate.
- **Jaw and ready mouth improve.** `expressions-DEBUG-ready-jaw-jersey-jun.png` shows a fuller, shorter chin and a narrow lip crease. The long pointed lower-face defect is substantially reduced. The face is still stylized/simple, but this scoped correction is clear.
- **Cafe blank wall is resolved.** The ordinary scenery image shows appropriately spaced windows, a projecting planted balcony and one cafe. The earlier oversized uninterrupted upper wall is no longer present in that facade.
- **Near-edge greenery now suggests coastal fallaway.** Some vegetation outside the left rail is visible in normal framing. Most of the actual slope/rocks remain hidden below the platform at this camera, so these images cannot establish a rich rocky-shore view comparable to the reference.

### Remaining concrete regressions

**P1 — Jersey cutouts expose unfinished shoulder junctions.** In `expressions-DEBUG-ready-jaw-jersey-jun.png`, both upper arms meet dark flat/open-looking tops below the outer shoulder, and the new gold trim sticks out as sharp tabs at shoulder and armpit. `expressions-DEBUG-jaw-jersey-jun.png` shows the same trim problem in a receiving pose. The old moving armband is removed, but the result does not yet read as cloth around a continuous human shoulder. The under-shirt skin loft reaches approximately ±0.195 m and does not close the junction to the arm in these poses. Bridge the chest/shoulder/deltoid surface through the cutout, conceal or close the exposed proximal arm end, and make the seam follow a smooth cloth edge flush against the body. Validate ready plus arms-forward/raised poses; do not only hide it in the portrait crop.

**P2 — Distant headlands now read as pale paper/ice strips.** In both ordinary screenshots, multiple almost-white low jagged bands sit on saturated blue water. They have lower silhouette complexity than the reference's natural layered rocky coast and are too close to cloud/foam value. Although source colors are muted green-gray (`829d98`, `99afaa`), the rendered result is washed out. Correct the final material/light/fog interaction and give each ridge a coherent darker base, irregular vertical profile, and restrained blue-green atmospheric separation. The proper criterion is the authored-camera render, not the nominal source hex colors. The earlier single slab needed replacement, but these thin bright polygons are not a finished solution.

### Limits and verdict

The two `DEBUG` captures use an inspection camera and simulation speed 0.05 solely to inspect face and clothing construction. They do not establish normal action scale or contact timing. Ball trail/pulse source was part of this snapshot; a still frame does not verify their temporal feel, and this review makes no such claim.

**Scoped verdict:** expression, jaw and cafe corrections are demonstrable. The new shoulder junction and headland issues need repair before this authoring pass is accepted. Overall art remains below the requested finished reference, with these two specific defects taking priority over adding more detail.


## Shoulder closure, headland material and rigid-mesh merge recheck

Used fresh isolated profiles `3d-visual-shoulder-final` and, after a discovered regression was fixed, `3d-visual-merged-fixed`, both on the reviewer's own port 45902. Normal camera evidence preceded inspection camera evidence. No game source edits or automated tests.

### Regression discovered and corrected during this check

The first restart revealed that the rigid mesh merge had removed the sculpted head surface and eye whites: ears, eyes, lips and hair floated against the background. `batch-regression-normal-portraits.png` and `batch-regression-DEBUG-ready-shoulder.png` preserve the failure. The cause was mixing unindexed generated meshes with indexed primitives in `SurfaceTool.append_from`, leaving original unindexed triangles unreferenced in the final indexed output. The implementation agent normalized source surfaces with `deindex()` before merging.

**The second fresh restart demonstrates correction.** `merged-fixed-normal-portraits.png` and `merged-fixed-DEBUG-ready-shoulder.png` have complete face geometry and eye whites. All three portrait expressions remain distinct and properly framed. This report does not carry the already-fixed missing-face defect forward as an open issue.

### Exact requested repairs

- **Shoulder closure: passes the observed ready and receiving poses.** The prior dark flat/open-looking upper-arm tops are gone. Jun's ready view and Kai's arms-forward receive view show rounded closed skin joining the shoulder region. Both are labeled debug views at speed 0.05, not normal gameplay framing.
- **One localized skin/cloth intersection remains.** In both `merged-fixed-DEBUG-ready-shoulder.png` and `merged-fixed-DEBUG-crouch-shoulder-framed.png`, a tan triangular wedge protrudes into the cream upper jersey on each side. It is particularly clear on Kai's darker skin. This is actual intersecting skin geometry rather than cloth shading. The widened underlay reaches width 0.210 at height 0.47 while nearby shirt width is 0.191 at height 0.48. Preserve lateral deltoid coverage, but keep the underlay's front/back surface beneath the cloth or limit its exposed geometry to the real opening. The smaller gold tabs are reduced; the tan intrusions are the remaining definite construction defect.
- **Headland washout is improved.** `merged-fixed-normal-headlands.png` shows muted blue-green land instead of nearly white cloud/ice values. The dedicated unshaded/fog-disabled material is doing useful work. The low ridges remain rather flat geometric slivers; they are acceptable as a simple distant layer, but do not establish the reference's richer rocky coastal depth. The visible near-edge vegetation helps place the court beside the sea, while much of the generated slope remains out of view.
- **Normal portraits and readable court presentation retained.** Six players, the real dark net, visible team identities, warm clay/cream palette, strong foliage shadows and the corrected cafe facade remain present after batching. No observed normal-frame HUD regression. Previously passed corner checks were not repeated, and no new claim of exhaustive corner coverage is made.

### Scoped quality judgment

The representative coast has moved beyond the initial architectural blockout: it is a coherent, inviting, readable stylized 3D volleyball scene with recognizable original teammates and functioning portrait expressions. That is a defensible **integration/presentation quality judgment**, not a statement that it matches the approved painterly illustration's craft or that the full goal is complete. The current face and scenery refinements should not be discarded merely because they are procedural.

Before accepting this exact authoring pass, correct the two visible skin wedges on the jersey. That is the remaining finite construction defect identified by this focused ready/receive review. Higher reference fidelity would still benefit from more visible near-shore depth, varied cloth planes/folds and more natural scenery silhouettes, but this review does not invent a new functional blocker from those stylistic differences. Animation timing, contact fairness, fun, match progression and all-map coverage belong to their independent runtime checks.


## Final localized junction recheck and representative-coast verdict

Restarted only the reviewer's own runtime, profile `3d-visual-junction-final`, after reducing the underlay front/back depth while preserving its lateral shoulder overlap. Evidence: `junction-final-normal-coast.png`, `junction-final-normal-portraits.png`, `junction-final-DEBUG-ready-junction.png`, `junction-final-DEBUG-receive-junction.png`, with accompanying state JSON.

**Ready and receiving junctions pass.** Jun's ready frame and Kai's arms-forward receiving frame show closed, rounded shoulder skin and uninterrupted cream cloth where the prior tan wedges protruded. The earlier dark proximal caps remain corrected. Small stylized trim angles remain visible, but no further cloth/skin construction blocker is identified in these views. The ready frame catches a blink; intact eye whites and faces are independently visible in the fresh normal portraits and receiving closeup. Debug cameras are explicitly labeled, use speed 0.05 and are not evidence of normal gameplay scale. Normal captures use authored camera and speed 1.0.

**The representative normal coast retains the corrected presentation.** The final normal image has the full cafe facade, planted balcony, readable dark net, six athletes, recognizable team colors and expressive portrait identities. The latest headland silhouettes have more vertical body and muted blue-green layer separation, so the previous near-white thin sliver defect is resolved at their intended distant scale. The fresh portrait image confirms that rigid merging no longer removes facial surfaces or sclera.

**Scoped verdict: PASS for representative-coast construction and gameplay readability, and for the concrete defects identified in these successive reviews.** This is a defensible limited quality bar: the scene is coherent, inviting and visibly authored as a dimensional coastal volleyball setting. It is not a claim of equal visual craft to the approved image, which still has richer cloth/skin plane work, more visible rocky coastal fallaway, less uniform architecture/foliage and more nuanced athletic illustration. Those differences remain relevant to any full-goal visual-fidelity claim. This review does not establish all-map visual consistency, animation quality across every action, fairness, progression, performance or fun; the other runtime reviews must supply their own evidence. No new substantive construction/readability blocker was observed in this final focused pass.

Final source fingerprints (SHA-256 prefixes):
- `scripts/three_d/athlete.gd`: `054f690d96966469`
- `scripts/three_d/geometry.gd`: `8c137969a39742a7`
- `scripts/three_d/coast.gd`: `0c892693d0de242e`
- `scripts/three_d/presentation.gd`: `7c991f4e7e28216e`


## New-map review

The distinct Harbor/Gardens variants received a fresh independent review in [maps-visual-review.md](maps-visual-review.md). It discloses copied historically earned replay-save provenance, normal-camera S3/S4/S6/S7/S8/S9 evidence, map-specific findings and performance limitations. The earlier representative-coast scoped pass is not blanket approval of these new maps.
