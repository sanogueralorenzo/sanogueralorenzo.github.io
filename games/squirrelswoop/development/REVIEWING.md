# Manual runtime review

This is an opt-in development console, not an automated test runner. Normal game launches have no socket listener. Review launches use `user://development.cfg` rather than the player's records.

```sh
godot --path games/squirrelswoop -- --review-port=45871 --seed=482193
```

Connect to `127.0.0.1:45871`, write one JSON command per line, and read one JSON telemetry snapshot per command. Only one reviewer should control an instance. Commands take effect in the running rendered game; physics continues at real time between commands.

- `{"action":"launch"}` leaves the summit.
- `{"action":"input","steer":-0.7,"pitch":0,"dive":false}` holds these flight controls until another input command. Positive pitch pulls up. An `input` command with omitted values releases all three controls.
- `{"action":"pause"}` / `{"action":"resume"}` use the actual pause flow.
- `{"action":"retry","same":true}` retries; `same:false` chooses a new mountain.
- `{"action":"seed","value":752041}` returns to a specific summit.
- `{"action":"status"}` reads live distance, position, speed, clearance, score, route, memory-window size, generation count, backlog, settings, and frame rate.
- `{"action":"capture","path":"res://development/evidence/example.png"}` captures the rendered viewport after drawing. Capture during flight for gameplay evidence.
- `{"action":"settings","volume":0.35,"assistance":true,"reduced_motion":true,"invert_pitch":false}` exercises persisted settings.
- `{"action":"summit"}` returns to the summit and saves records.
- `{"action":"inspect","distance":2300,"x":76,"height":5.5}` moves the review scene and camera **only while flight is stopped**. Mark captures from this command as visual studies, never as completed descents. Start a fresh run afterward.
- `{"action":"quit"}` saves and exits.

F3 diagnostics and F12 screenshots are also available without the console. Discrete console inputs can demonstrate motion and reproducibility, but do not establish how a physical keyboard/controller feels to a human player.
