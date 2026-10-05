# Android Steam delivery

## Objective and acceptance

Deliver a minimal, efficient, polished Android Steam experience on the S24 with a measured Arch ARM base, Steam-managed ARM64 Proton, native library/settings, Xbox-style controls alongside direct touch, reproducible updates and recovery. Preserve accounts, games, saves and settings. Users need no Linux desktop or shell. Defer native authentication experiments, Heroic, emulators and speculative frameworks.

Complete only after setup → Steam QR login → live owned library → gameplay → exit/relaunch → restart passes, including cold/warm starts, keyboard/touch/controller input, background/resume and clean shutdown. Validate a release, keep setup documentation brief, commit and push to main. Claims of efficiency require comparable measurements.

## Ordered work

- [x] Reconcile source/device baseline; separate verified behavior from experiments.
- [ ] Minimize Arch in small validated batches; audit dependencies, contents and Steam duplication; measure downloads, installed bytes and setup time against real Steam/gameplay.
- [ ] Validate a current reviewed dependency lock, deterministic rebuild and safe update/recovery. Keep required Android adaptations versioned and small.
- [ ] Compare DroidDeck source/installed APK; adopt only measured useful startup, graphics, pacing and input improvements.
- [ ] Default Xbox virtual controller; native layout selection; floating left stick, translucent pressed buttons, simultaneous direct touch, actual Linux recognition.
- [ ] Complete flow/release checks, native polish, brief docs and main delivery.

## Resume state

- Worktree: `/Users/mario/.codex/worktrees/androidsteam/sanogueralorenzo.github.io`, branch `sanogueralorenzo/androidsteam`, initial HEAD `3e6dfe404`. Main checkout is older (`e9e575b60`); reconcile into main after validation. S24 `RFCWC0YTYGW`, Android 16, Adreno 750. No owned Linux processes at baseline. Latest debug/test APKs installed with `install -r` for private device checks; no data clearing.
- Existing verified work: pinned Arch snapshot `20261004-2` (245 packages; 162610928-byte base download; ~817 MiB including graphics/adapters), deterministic rebuild and swap recovery, Steam-managed Proton, Superflight/Brotato/SNØ gameplay and audio, native library and per-game settings. See `docs/validation.md` for evidence and limits. These are prior results; recheck the final configuration.
- Login: use Valve's own runtime QR screen. Primary Steam home previously passed a delivered online-account observation; fresh isolated QR login remains unproved. Abandoned native login source is preserved at `/Users/mario/.codex/androidsteam-snapshot-dTN2GP`; every device home and encrypted token remains intact. No authentication files/logs should be exported.
- Controls: current layouts are digital keyboard overlays (Direct touch/Arrows/WASD), not Xbox emulation. Always-visible left stick and multi-touch interception need replacement. Preserve saved per-game choices.
- DroidDeck: upstream checked out at `/tmp/androidsteam-droiddeck-source`, commit `05608ac4d4da33cfebcc0d6783064ec04ac75aee`; installed debug 0.3.0. Source/render/input comparison exists in `docs/validation.md`; matched release measurement pending.
- Passed now: cached online-session/start-stop (39.407 s); source-matching debug/minified release builds, 27 unit tests and lint. Current core release is `/tmp/androidsteam-goal-release.apk` (development key). Superflight menu and saved score/profile render. Primary home contains five installed games; preserve them all. Prior isolated real Steam login/restart/live ownership passed in the previous chat; its temporary test was explicitly removed by the user, so do not restore it.
- Runtime batch 1: remove manuals while retaining legal notices, locale generators/source data (keep glibc C.UTF-8/gconv) and unused Mesa neural inference. Exact current upstream DB hashes still match the 245-package lock. `audit.py` records dependency paths/sizes/Steam overlap. Two builds match: 153760944 bytes, SHA-256 `59bae3f21e0e31375589e02deec5f813398342431b018f16102a3522d87745ab`. Isolated replacement/cancel/truncation/recovery test passes (134.835 s). Android runtime disk use: 817661 → 761463 KiB; preparation 72672 → 67518 ms, one sample each. The candidate is active on the S24; the original root is retained at `runtime-goal-baseline`. Ten focused dependency/font/DNS/audio/render/lifecycle checks pass (31.376 s). Source-matching release Superflight flight/touch steering/collision/Home-resume and two native Play/Quit cycles pass with Steam PID 15592 retained. Notification Stop reaps all Linux processes. See `docs/runtime-minimization.md` for comparable-condition samples and their thermal/scene limits; no runtime speedup claim. Evidence `/tmp/androidsteam-minimal-batch1-evidence.json`.
- Next: investigate unused packaged tools and a Zink-only Mesa build to remove the ~161 MiB LLVM dependency without breaking graphics; validate each subsequent batch against the retained runtime/game baseline. No new snapshot has been published. Build volume `/Volumes/AndroidSteamBuild`; verified cache `/tmp/androidsteam-arch-build/packages`.
