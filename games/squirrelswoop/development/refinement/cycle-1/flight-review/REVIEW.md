# Cycle 1 independent flight review

Actual graphical Godot play through discrete manual review-console controls, 2026-09-06 06:41–06:49 UTC. No automated tests. Logical viewport1440×900, configured window1280×800, OpenGL compatibility, MSAA off. Three unrelated Godot processes were present (47800,51950,51963); reviewed process51934. Frame intervals varied with shared-machine conditions. Audio code ran without reported errors, but this review did not independently listen to sound or assess physical keyboard/controller tactile feel.

## Demonstrated continuous descents

- Seed752041: initial meadow bank3.3s while pulling, then continued full pull25s. Clearance13.31m at58m and15.10m at469m; speed settled16.50m/s, still descending. Wider useful height range; no runaway full-pull gain.
- From469m/15.10m clearance, tuck0.9s reached23.69m/s/11.53m. Release1.4s retained22.79m/s/10.44m, recovery intensity0. This preserves chosen altitude significantly longer than the old6m servo.
- Same uninterrupted descent continued to2060.88m, clearance6.51m,63active sections296generated,pending0. Pauses and captures occurred, but no teleport/reset during this run.
- Late tuck0.65s from2060m reduced clearance6.51→2.56m at26.19m/s. Release survived, recovering to2.77m after0.77s at24.84m/s. Recovery intensity0.154.
- Fresh seed482193: full right4.6s then release entered woods at104m/x36.57/11.77m clearance. Full left crossed back through stream at163m/x0.71, then meadow at253m/x−62.81. Seven close passes; all alive, no teleport.

## Controlled staged assistance comparison (not a continuous descent)

Explicitly positioned both fresh model runs at seed752041,d2060,x−61.05,6.5m clearance. Waited for all63chunks before launch. Both0.65s tucks produced identical release state: d2075.044922, clearance3.035517m, speed24.894589m/s, vertical−19.226046m/s.

After0.8s release: assistance OFF had2.1354m clearance/24.0023m/s; ON had3.0608m/23.8651m/s. Thus aid buys about0.93m clearance for a modest0.137m/s cost. Both survived. An earlier staged attempt launched before loading finished and hit ground before release; exclude it from the paired comparison.

## Performance windows

No PNG capture during these windows; screenshots can themselves stall rendering.

| Continuous interval | Frame p50/p95/max ms | RSS KiB |
|---|---|---|
|523→1495m,45s |16.721/30.873/148.680 |483904→487104|
|1495→2061m,26s |6.992/7.895/70.983 |see rss-windows.txt|

The metric ring stores1800recentframes. The second window ran faster under changed shared-machine scheduling, so do not interpret it as an implementation improvement.63active chunks remained bounded; static memory varied with terrain content. Woods before any capture: p50=28.688,p95=82.606,max169.519ms, around2.18million rendered triangles. This is a substantive responsiveness problem. A later PNG capture inflated max to596ms and must not be attributed to ordinary play.

## Substantive remaining gaps

1. `early-recovery.png`: distant forest forms a floating horizontal ribbon with sky showing underneath; meadow still appears nearly level. Root notified for next camera/backdrop cycle.
2. `woods-entry.png`: foreground canopy obscures the upcoming line, and the squirrel becomes almost black. Solid branches and openings are hard to judge. More foliage is not improving playability here.
3. Woods frame-time spikes and sustained low throughput need detail/generation work; they undermine responsive flight.
4. Close passes jumped4→7 over only7m near one tree. Group rewards/notices by logical obstacle owner instead of individual collider capsules. Audio already has a short whoosh cooldown, but scoring remains separate.
5. Automatic recovery momentum cost is demonstrated but modest. Preserve accessibility; describe it honestly rather than promising a major speed penalty.

Raw chronological records: `manual-play.jsonl`. RSS reads: `rss-windows.txt`. Captures are actual gameplay, except no screenshots were taken during the explicitly staged paired comparison. Runtime left paused at253.43m,seed482193 for root handoff.
