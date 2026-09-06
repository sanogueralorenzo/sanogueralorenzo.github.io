# Manual runtime review

This is an opt-in development console, not an automated test runner. Normal game launches have no socket listener. Review launches use `user://development.cfg` rather than the player's records.

```sh
godot --path games/squirrelswoop -- --review-port=45871 --seed=482193
```

Connect to `127.0.0.1:45871`, write one JSON command per line, and read one JSON telemetry snapshot per command. Only one reviewer should control an instance. Commands take effect in the running rendered game; physics continues at real time between commands.

- `{"action":"launch"}` leaves the summit.
- `{"action":"input","steer":-0.7,"pitch":0,"dive":false}` holds these flight controls until another input command. Positive pitch pulls up. An `input` command with omitted values releases all three controls.
- `{"action":"key","code":65,"pressed":true}` injects an actual Godot key event through the game's input path; send the matching `pressed:false` event to release it. ASCII codes include A=65, D=68, S=83, Space=32, R=82, and N=78; Godot Enter=4194309 and Escape=4194305. This also releases console control overrides. It does not emulate a human's physical keyboard feel.
- `{"action":"pause"}` / `{"action":"resume"}` use the actual pause flow.
- `{"action":"retry","same":true}` retries; `same:false` chooses a new mountain.
- `{"action":"seed","value":752041}` returns to a specific summit.
- `{"action":"status"}` reads live distance, position, speed, clearance, score, route, generation count, backlog, settings, flight state, assisted-recovery intensity, and frame metrics.
- `{"action":"metrics_reset"}` starts a fresh frame-time window. Telemetry reports p50/p95/worst intervals over the latest 1,800 active frames, process/physics time, Godot static allocation, nodes, objects, draw calls, and triangles. Measure process RSS separately; Godot static allocation is not total resident memory. Exclude image capture, loading, and staged jumps from flight benchmarks.
- `{"action":"capture","path":"res://development/evidence/example.png"}` captures the rendered viewport after drawing. Capture during flight for gameplay evidence.
- `{"action":"settings","volume":0.35,"assistance":true,"reduced_motion":true,"invert_pitch":false}` exercises persisted settings.
- `{"action":"summit"}` returns to the summit and saves records.
- `{"action":"inspect","distance":2300,"x":76,"height":5.5}` moves the review scene and camera **only while flight is stopped**. Mark captures from this command as visual studies, never as completed descents. Start a fresh run afterward.
- Staged views display `STUDY` and report `staged:true`. Before capturing one, wait for both `pending:0` and `building:false`; an empty pending queue alone can still leave one section under construction. `generation_slice_ms` measures an individual live build interval, while `generation_ms` measures the complete section build.
- `{"action":"quit"}` saves and exits.

F3 diagnostics and F12 screenshots are also available without the console. Discrete console inputs can demonstrate motion and reproducibility, but do not establish how a physical keyboard/controller feels to a human player.

Forward+ telemetry also includes the actual `renderer`, `driver`, `camera_transform`, viewport texture size, and pitch-inversion setting. PNG dimensions are the authoritative capture resolution; the viewport proxy can report scaled logical dimensions with `canvas_items` stretch.

`{"action":"rendering","taa":false,"msaa":2,"ssao_enabled":true}` changes an opt-in manual comparison instance only. Supported fields also include `ssr_enabled`, `ssil_enabled`, `sdfgi_enabled`, `angular_distance`, volumetric-fog enable/density/length/reprojection, ambient-light energy/sky contribution, and `background_energy_multiplier`. Restart to recover the shipped profile; these choices are never saved as player settings. An SDFGI study must additionally classify moving geometry correctly; toggling the environment alone is insufficient. Do not use comparison toggles for final-default benchmarks.
