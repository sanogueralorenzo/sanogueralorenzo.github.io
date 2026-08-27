class_name RunPacing
extends RefCounted

const RUN_DURATION := 20.0 * 60.0
const APEX_TIME := 18.0 * 60.0
const ELITE_TIMES: Array[float] = [3.0 * 60.0, 7.0 * 60.0, 12.0 * 60.0, 15.0 * 60.0]
const PHASE_STARTS: Array[float] = [0.0, 3.0 * 60.0, 7.0 * 60.0, 12.0 * 60.0, APEX_TIME]
const PHASE_IDS: Array[StringName] = [&"breakaway", &"pressure", &"redline", &"overrun", &"apex"]
const PHASE_NAMES: Array[String] = ["BREAKAWAY", "PRESSURE RISES", "REDLINE", "OVERRUN", "THE APEX"]
const BUILD_MILESTONE_WINDOWS := {
	&"engine": Vector2(8.0, 45.0),
	&"evolution": Vector2(45.0, 240.0),
	&"arsenal": Vector2(150.0, 480.0),
	&"catalyst": Vector2(360.0, 900.0),
}


func get_phase_index(elapsed_time: float) -> int:
	for index in range(PHASE_STARTS.size() - 1, -1, -1):
		if elapsed_time >= PHASE_STARTS[index]:
			return index
	return 0


func get_phase_id(elapsed_time: float) -> StringName:
	return PHASE_IDS[get_phase_index(elapsed_time)]


func get_phase_name(elapsed_time: float) -> String:
	return PHASE_NAMES[get_phase_index(elapsed_time)]


func get_intensity(elapsed_time: float) -> float:
	var progress := clampf(elapsed_time / RUN_DURATION, 0.0, 1.0)
	var phase_boost := get_phase_index(elapsed_time) * 0.12
	return 1.0 + progress * 2.25 + phase_boost


func get_population_limit(elapsed_time: float) -> int:
	return mini(96, 16 + floori(elapsed_time / 18.0) + get_phase_index(elapsed_time) * 4)


func get_spawn_interval(elapsed_time: float) -> float:
	return maxf(0.24, 1.05 / get_intensity(elapsed_time))


func get_pack_size(elapsed_time: float) -> int:
	return mini(4, 1 + get_phase_index(elapsed_time) / 2)


func get_crossed_elite_indices(previous_time: float, current_time: float) -> PackedInt32Array:
	var crossed := PackedInt32Array()
	for index in range(ELITE_TIMES.size()):
		if previous_time < ELITE_TIMES[index] and current_time >= ELITE_TIMES[index]:
			crossed.append(index)
	return crossed


func crossed_apex_time(previous_time: float, current_time: float) -> bool:
	return previous_time < APEX_TIME and current_time >= APEX_TIME


func crossed_deadline(previous_time: float, current_time: float) -> bool:
	return previous_time < RUN_DURATION and current_time >= RUN_DURATION


func is_build_milestone_available(milestone_id: StringName, elapsed_time: float) -> bool:
	if not BUILD_MILESTONE_WINDOWS.has(milestone_id):
		return false
	var window: Vector2 = BUILD_MILESTONE_WINDOWS[milestone_id]
	return elapsed_time >= window.x


func get_build_cadence_failures(milestone_times: Dictionary) -> Array[StringName]:
	var failures: Array[StringName] = []
	for milestone_id in BUILD_MILESTONE_WINDOWS:
		if not milestone_times.has(milestone_id):
			failures.append(StringName(milestone_id))
			continue
		var window: Vector2 = BUILD_MILESTONE_WINDOWS[milestone_id]
		var milestone_time := float(milestone_times[milestone_id])
		if milestone_time < window.x or milestone_time > window.y:
			failures.append(StringName(milestone_id))
	return failures
