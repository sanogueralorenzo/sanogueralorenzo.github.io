# Sunny Bay — stopped prototype

Development stopped at the user’s request because the procedural town does not meet the coastal reference’s visual quality. This is unfinished work, not a completed destination milestone.

The prototype is isolated in the `sanogueralorenzo/sunny-bay` worktree. Existing map content and standalone games are unchanged. No fishing implementation or shared player/application modifications remain.

## What was verified

A native Godot run drove the real cat controller through the complete harbor → café street → hillside garden → coastal return → harbor loop and onto the pier, without jumps or blocked waypoints. Evidence and logs from that run live in `/tmp/sunny-bay-evidence` and `/tmp/sunny-walk.log`; these temporary files are not committed. Later map dressing changes have not had another complete runtime pass.

## Quality and verification gaps

The buildings remain repetitive, terrain and planting lack the reference’s detail, and the composition does not reach its depth or finish. The preview is an actual early Sunny Bay gameplay capture. Flight, perching, switching, the latest dressing changes, all side paths, and consistent performance across the whole town are not fully verified. There is no fishing or catch notebook. Performance varied from roughly 30 to 60 FPS during native inspection; screenshot readbacks caused additional spikes. This prototype must not be presented as polished or complete.

## Ownership

The town owns its layout and dressing. Its geometry/material helpers adapt Harbor Hills’ project-owned implementation locally and use Cozy Sora’s shared primitives, batching, collision and leaf painter. The pond shader adapts Daan Gardens; the sky shader adapts Last Cast. There is no runtime dependency on another map or game folder.
