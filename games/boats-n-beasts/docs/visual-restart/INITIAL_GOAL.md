# Initial prompt for the new conversation

Set an active goal to bring Boats n Beasts to the selected visual concept, with convincing native gameplay evidence. The current implementation is a baseline to improve or replace, not a style to preserve. Previous visual passes were rejected because they looked flatter, less attractive and less coherent than the concept. Do not defend or accumulate those changes just because they build.

Primary checkout: `/Users/mario/AndroidStudioProjects/boats-n-beasts-worktree`.
Game: `games/boats-n-beasts`.
Read AGENTS.md, docs/OBJECTIVE.md, docs/ART_DIRECTION.md and the latest docs/QUALITY.md entries. This prompt supersedes conflicting historical design decisions. Use the selected direction image in this folder as the visual target. Recommend one direction at the start; do not mix all three styles.

## Main-agent ownership and parallel work

You are the creative director and integration owner. You must delegate concrete independent work to GPT-6 Astra subagents (`model: gpt-6-astra`, `reasoning_effort: high`, `fork_turns: none` with self-contained briefs). With four available agent slots, keep at most three workers plus yourself active. Do useful local integration, inspection or runtime work while workers run.

Start with these independent assignments, adjusting boundaries after reading the code:
1. Environment: sea, organic shallows, beaches, rocks, foliage, harbor buildings.
2. Subjects: boat hulls/cabins/equipment and expressive monsters with consistent depth, lighting and proportions.
3. Motion and visual critique: wake/surf/projectile/fishing readability; independently compare baseline screenshots with the target, then own effects files that do not overlap the other workers.

Give each agent a bounded outcome, owned files, shared camera/palette/light constraints and acceptance criteria. Use an isolated branch/worktree per implementer. Agents return commits, evidence and limitations; they must not push main, merge other branches, reset shared changes, or control the main native game instance. Use separate temporary art preview instances if needed.

Only the main agent integrates branches, resolves every merge conflict, checks cross-system consistency, runs the final game, and commits/pushes to main. Resolve conflicts by understanding the intended combined behavior, never by blindly choosing ours/theirs. You remain responsible for reviewing and fixing subagent work; delegation is not acceptance. If work conflicts or regresses appearance, reject or revise it. Rotate a worker into independent final critique when implementation tasks finish.

## Visual requirements

- Preserve the spacious pulled-back camera: near overhead, slight tilt, no horizon. Small readable subjects in broad open water; no zooming in to disguise weak art.
- One coherent art direction and upper-left light source. Convincing volume, occlusion, contact shadows and appropriate material contrast throughout.
- Petrol-blue ocean with restrained depth variation and natural surface detail. Organic turquoise shallows connected to land, without neon halos, concentric rings or tiled noise blobs.
- Warm irregular sandy islands, sculpted rocks with convincing ledges, clustered natural vegetation and attractive, proportionate harbor cottages. Buildings must not look like flat boxes or striped awnings.
- Distinct Gunboat, Mage and Aura silhouettes. Shaded hulls, readable cabins/windows and mounted equipment; Mage crystal stays upright while steering. No detached or rotating fake height.
- Rounded expressive monsters, readable faces and attack cues, consistent scale and volume. Enemies should feel in the water through contact shadows, foam and movement.
- Curved broken foamy wakes, restrained surf, luminous curved magic trails and visible coral hostile projectiles. Effects reinforce movement without obscuring play.
- Fishing schools look submerged and rewarding, with minimal ripples and no floating marker icon. Treasure and wrecks feel grounded in the same world.
- Preserve minimal HUD: top XP strip; horizontal icon counters for time/silver/gold/kills; LVL in the far upper-right corner separated from the nautical map; equipment centered at bottom; small red boat health bar.

## Technical approach and scope

Do not assume more hand-drawn polygons or switching Compatibility to Forward+ will solve the art. First inspect the rendering architecture and run a small native visual spike for the hardest subject. You may replace brittle presentation code with procedural 3D meshes, an orthographic render-to-texture approach or another suitable procedural technique if it demonstrably moves toward the target. Choose the renderer based on verified needs and performance, not prestige. Keep the plain C# simulation isolated from presentation.

All shipped art remains original procedural code, shaders, geometry or engine-generated textures. Generated concept images are reference-only; do not ship them as game sprites. No unrelated gameplay rewrite, external art or audio scope expansion. A dedicated native art preview scene is permitted to compare subjects reliably; do not alter or inject live gameplay state to fabricate verification. Respect the existing no-automated-tests project instruction; use builds, source review and native play.

Preserve the latest gameplay decisions: three boat identities; two total weapon slots including the starter; three offers from one category per harbor; one clear improvement per upgrade; immediate free upgrade choices when leveling up at sea, with combat frozen until selection; no harbor requirement for level-ups; one cast per fishing school; no fishing result popup or cargo capacity; automatic catch sales on docking; scarce randomized persistent silver; no settings, seed UI, mid-run boat switching or Soaked mechanic. Preserve current speed controls, progression, collision and economy unless I explicitly request changes.

## Verification and completion

1. Capture an honest baseline and identify the five largest visual gaps before editing. Save a compact ranked gap list.
2. Establish one successful native sample before rolling a technique across the game. Compare at actual gameplay scale, not only enlarged asset previews.
3. For each integrated pass, compare current and baseline native screenshots against the selected concept at matching resolution/camera/scene where practical. Judge shape, proportions, depth, palette, composition and readability. Revert visible regressions instead of endlessly tinting them.
4. Main agent must verify actual sailing, turns/boost, combat with multiple enemy types, all three boats, fishing, harbor entry and immediate level-up/resume. Check streaming and subject/terrain occlusion. No worker should compete for the same game controls.
5. Build Debug and Release, inspect rendering/runtime logs, and measure sustained movement/combat performance on the same machine and resolution. Target smooth 60 FPS; report mean/p95/p99 timings and any regressions honestly.
6. Save native screenshots and concise findings in evidence and update ART_DIRECTION.md, QUALITY.md and HANDOFF.md. Keep a working preview available. Commit and push reviewed integrated work to main.
7. Completion requires a convincing coherent match in actual gameplay and independent critique with no major unresolved visual or functional gaps. A checklist, successful build, added shader, subagent claim or generated image is not proof. Keep the full goal active while material gaps remain.

Be autonomous within this scope. Communicate meaningful changes and remaining gaps, not repeated promises. Do not ask me to approve every routine iteration. If the chosen technical approach cannot reach the target, say why with evidence and change the approach; do not quietly lower the target.
