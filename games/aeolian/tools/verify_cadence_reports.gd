extends SceneTree

const CAPS := ["30", "60", "120"]
const REPORT_DIRECTORY := "res://reports/cadence"
const EXPECTED_OUTCOMES := [
	{"name": "crest", "state": "grounded", "crash_cause": ""},
	{"name": "bank", "state": "grounded", "crash_cause": ""},
	{"name": "jump", "state": "airborne", "crash_cause": ""},
	{"name": "wall", "state": "crashed", "crash_cause": "wall_impact"},
]


func _initialize() -> void:
	var reports := {}
	for cap: String in CAPS:
		var path := "%s/cap-%s.json" % [REPORT_DIRECTORY, cap]
		if not FileAccess.file_exists(path):
			printerr("Missing cadence report: %s" % path)
			quit(24)
			return
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not parsed is Dictionary:
			printerr("Invalid cadence report: %s" % path)
			quit(25)
			return
		var requested_fps := float(cap)
		var measured_fps := float(parsed.get("measured_render_fps", 0.0))
		if String(parsed.get("cap", "")) != cap \
				or int(parsed.get("physics_hz", 0)) != 60 \
				or String(parsed.get("rendering_method", "")) != "forward_plus" \
				or String(parsed.get("rendering_driver", "")).is_empty() \
				or String(parsed.get("video_adapter", "")).is_empty() \
				or measured_fps < requested_fps * 0.95 \
				or measured_fps > requested_fps * 1.10:
			printerr("Invalid cadence conditions cap=%s physics=%s fps=%.1f renderer=%s/%s" % [
				cap,
				parsed.get("physics_hz", 0),
				measured_fps,
				parsed.get("rendering_method", ""),
				parsed.get("rendering_driver", ""),
			])
			quit(26)
			return
		reports[cap] = parsed
	var failures := 0
	var baseline: Dictionary = reports["60"]
	if not _valid_baseline(baseline):
		quit(27)
		return
	for cap: String in ["30", "120"]:
		var candidate: Dictionary = reports[cap]
		if candidate.scenarios.size() != baseline.scenarios.size():
			failures += 1
			printerr("Cadence scenario count mismatch cap=%s" % cap)
			continue
		for index in baseline.scenarios.size():
			var expected: Dictionary = baseline.scenarios[index]
			var actual: Dictionary = candidate.scenarios[index]
			var position_delta := _vector(actual.position).distance_to(_vector(expected.position))
			var speed_delta := absf(float(actual.speed_mps) - float(expected.speed_mps))
			var matches: bool = actual.name == expected.name \
				and actual.state == expected.state \
				and actual.crash_cause == expected.crash_cause \
				and actual.events == expected.events \
				and position_delta <= 0.05 \
				and speed_delta <= 0.10
			if not matches:
				failures += 1
				printerr("Cadence mismatch cap=%s scenario=%s position=%.4f speed=%.4f" % [
					cap, expected.name, position_delta, speed_delta,
				])
	if failures == 0:
		print("Native 30/60/120 FPS cadence reports match for crest, bank, jump, and wall.")
	quit(mini(failures, 125))


func _vector(values: Array) -> Vector3:
	return Vector3(float(values[0]), float(values[1]), float(values[2]))


func _valid_baseline(report: Dictionary) -> bool:
	var scenarios: Variant = report.get("scenarios", null)
	if not scenarios is Array or scenarios.size() != EXPECTED_OUTCOMES.size():
		printerr("Cadence baseline must contain the four expected scenarios.")
		return false
	for index in EXPECTED_OUTCOMES.size():
		var scenario: Variant = scenarios[index]
		var expected: Dictionary = EXPECTED_OUTCOMES[index]
		if not scenario is Dictionary \
				or String(scenario.get("name", "")) != expected.name \
				or String(scenario.get("state", "")) != expected.state \
				or String(scenario.get("crash_cause", "")) != expected.crash_cause \
				or not scenario.get("events", null) is Array:
			printerr("Cadence baseline outcome mismatch at scenario %d." % index)
			return false
		var position: Variant = scenario.get("position", null)
		var speed := float(scenario.get("speed_mps", NAN))
		if not position is Array or position.size() != 3 or not is_finite(speed):
			printerr("Cadence baseline has invalid numeric data at scenario %s." % expected.name)
			return false
		for coordinate: Variant in position:
			if not (coordinate is float or coordinate is int) or not is_finite(float(coordinate)):
				printerr("Cadence baseline has a non-finite position at scenario %s." % expected.name)
				return false
	return true
