class_name ProgressProfile
extends RefCounted

const RunProtocolCatalog = preload("res://scripts/run_protocols.gd")
const SCHEMA_VERSION := 4
const MINIMUM_SUPPORTED_SCHEMA := 1
const DEFAULT_PATH := "user://overrush_profile.json"

var momentum := 0
var completed_runs := 0
var victories := 0
var best_time_seconds := 0.0
var best_clear_count := 0
var best_damage := 0.0
var best_distance_meters := 0.0
var last_run_summary: Dictionary = {}
var selected_protocol: StringName = RunProtocolCatalog.STANDARD
var reduced_motion := false
var high_contrast_telegraphs := false
var guidance_enabled := true
var onboarding_completed := false
var master_volume := 0.8
var music_volume := 0.55


func reset() -> void:
	momentum = 0
	completed_runs = 0
	victories = 0
	best_time_seconds = 0.0
	best_clear_count = 0
	best_damage = 0.0
	best_distance_meters = 0.0
	last_run_summary.clear()
	selected_protocol = RunProtocolCatalog.STANDARD
	reduced_motion = false
	high_contrast_telegraphs = false
	guidance_enabled = true
	onboarding_completed = false
	master_volume = 0.8
	music_volume = 0.55


func get_unlocked_protocols() -> Array[StringName]:
	return RunProtocolCatalog.get_unlocked(momentum)


func select_protocol(protocol_id: StringName) -> bool:
	if protocol_id not in get_unlocked_protocols():
		return false
	selected_protocol = protocol_id
	return true


func record_run(elapsed_time: float, enemies_defeated: int, victory: bool, summary: Dictionary = {}) -> Dictionary:
	var unlocked_before := get_unlocked_protocols()
	var definition := RunProtocolCatalog.get_definition(selected_protocol)
	var base_reward := elapsed_time / 12.0 + maxi(enemies_defeated, 0) * 0.25 + (75.0 if victory else 0.0)
	var earned := maxi(1, roundi(base_reward * float(definition.reward_multiplier)))
	var safe_elapsed := maxf(0.0, elapsed_time)
	var safe_clears := maxi(0, enemies_defeated)
	var run_damage := maxf(0.0, float(summary.get("damage_dealt", 0.0)))
	var run_distance := maxf(0.0, float(summary.get("distance_meters", 0.0)))
	var new_records: Array[StringName] = []
	if safe_elapsed > best_time_seconds:
		new_records.append(&"survival")
	if safe_clears > best_clear_count:
		new_records.append(&"clears")
	if run_damage > best_damage:
		new_records.append(&"damage")
	if run_distance > best_distance_meters:
		new_records.append(&"distance")
	momentum += earned
	completed_runs += 1
	if victory:
		victories += 1
	best_time_seconds = maxf(best_time_seconds, safe_elapsed)
	best_clear_count = maxi(best_clear_count, safe_clears)
	best_damage = maxf(best_damage, run_damage)
	best_distance_meters = maxf(best_distance_meters, run_distance)
	last_run_summary = _sanitize_run_summary(summary)
	last_run_summary["elapsed_seconds"] = snappedf(safe_elapsed, 0.1)
	last_run_summary["enemies_defeated"] = safe_clears
	last_run_summary["victory"] = victory
	last_run_summary["protocol_id"] = str(selected_protocol)
	var new_unlocks: Array[StringName] = []
	for protocol_id in get_unlocked_protocols():
		if protocol_id not in unlocked_before:
			new_unlocks.append(protocol_id)
	return {
		"momentum_earned": earned,
		"momentum_total": momentum,
		"new_unlocks": new_unlocks,
		"new_records": new_records,
	}


func save(path: String = DEFAULT_PATH) -> bool:
	var absolute_path := ProjectSettings.globalize_path(path)
	var temporary_path := absolute_path + ".tmp"
	var backup_path := absolute_path + ".bak"
	var file := FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(_to_dictionary(), "\t"))
	file.flush()
	file.close()

	if FileAccess.file_exists(backup_path):
		DirAccess.remove_absolute(backup_path)
	if FileAccess.file_exists(absolute_path):
		if DirAccess.rename_absolute(absolute_path, backup_path) != OK:
			DirAccess.remove_absolute(temporary_path)
			return false
	if DirAccess.rename_absolute(temporary_path, absolute_path) != OK:
		if FileAccess.file_exists(backup_path):
			DirAccess.rename_absolute(backup_path, absolute_path)
		return false
	return true


func load(path: String = DEFAULT_PATH) -> bool:
	reset()
	var absolute_path := ProjectSettings.globalize_path(path)
	if _load_absolute_path(absolute_path):
		return true
	var backup_path := absolute_path + ".bak"
	if _load_absolute_path(backup_path):
		save(path)
		return true
	reset()
	return false


func _load_absolute_path(absolute_path: String) -> bool:
	if not FileAccess.file_exists(absolute_path):
		return false
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(absolute_path)) != OK:
		return false
	var data = parser.data
	if not (data is Dictionary):
		return false
	var schema_version := int(data.get("schema_version", -1))
	if schema_version < MINIMUM_SUPPORTED_SCHEMA or schema_version > SCHEMA_VERSION:
		return false
	momentum = maxi(0, int(data.get("momentum", 0)))
	completed_runs = maxi(0, int(data.get("completed_runs", 0)))
	victories = clampi(int(data.get("victories", 0)), 0, completed_runs)
	best_time_seconds = maxf(0.0, float(data.get("best_time_seconds", 0.0)))
	best_clear_count = maxi(0, int(data.get("best_clear_count", 0)))
	best_damage = maxf(0.0, float(data.get("best_damage", 0.0)))
	best_distance_meters = maxf(0.0, float(data.get("best_distance_meters", 0.0)))
	var saved_summary = data.get("last_run_summary", {})
	last_run_summary = _sanitize_run_summary(saved_summary if saved_summary is Dictionary else {})
	var saved_protocol := StringName(str(data.get("selected_protocol", RunProtocolCatalog.STANDARD)))
	selected_protocol = saved_protocol if saved_protocol in get_unlocked_protocols() else RunProtocolCatalog.STANDARD
	reduced_motion = bool(data.get("reduced_motion", false))
	high_contrast_telegraphs = bool(data.get("high_contrast_telegraphs", false))
	guidance_enabled = bool(data.get("guidance_enabled", true))
	onboarding_completed = bool(data.get("onboarding_completed", false))
	master_volume = clampf(float(data.get("master_volume", 0.8)), 0.0, 1.0)
	music_volume = clampf(float(data.get("music_volume", 0.55)), 0.0, 1.0)
	return true


func _to_dictionary() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"momentum": momentum,
		"completed_runs": completed_runs,
		"victories": victories,
		"best_time_seconds": best_time_seconds,
		"best_clear_count": best_clear_count,
		"best_damage": best_damage,
		"best_distance_meters": best_distance_meters,
		"last_run_summary": last_run_summary,
		"selected_protocol": str(selected_protocol),
		"reduced_motion": reduced_motion,
		"high_contrast_telegraphs": high_contrast_telegraphs,
		"guidance_enabled": guidance_enabled,
		"onboarding_completed": onboarding_completed,
		"master_volume": master_volume,
		"music_volume": music_volume,
	}


func _sanitize_run_summary(summary: Dictionary) -> Dictionary:
	var safe := {
		"elapsed_seconds": maxf(0.0, float(summary.get("elapsed_seconds", 0.0))),
		"enemies_defeated": maxi(0, int(summary.get("enemies_defeated", 0))),
		"elite_defeats": maxi(0, int(summary.get("elite_defeats", 0))),
		"damage_dealt": maxf(0.0, float(summary.get("damage_dealt", 0.0))),
		"damage_taken": maxf(0.0, float(summary.get("damage_taken", 0.0))),
		"distance_meters": maxf(0.0, float(summary.get("distance_meters", 0.0))),
		"maximum_speed": maxf(0.0, float(summary.get("maximum_speed", 0.0))),
		"dash_count": maxi(0, int(summary.get("dash_count", 0))),
		"rerolls_used": maxi(0, int(summary.get("rerolls_used", 0))),
		"banishes_used": maxi(0, int(summary.get("banishes_used", 0))),
		"phase_reached": str(summary.get("phase_reached", "breakaway")).left(32),
		"build_name": str(summary.get("build_name", "UNCOMMITTED")).left(80),
		"level": maxi(1, int(summary.get("level", 1))),
		"protocol_id": str(summary.get("protocol_id", RunProtocolCatalog.STANDARD)).left(48),
		"world_seed": int(summary.get("world_seed", 0)),
		"victory": bool(summary.get("victory", false)),
	}
	safe["upgrade_history"] = _sanitize_string_array(summary.get("upgrade_history", []), 64)
	safe["damage_by_source"] = _sanitize_numeric_dictionary(summary.get("damage_by_source", {}), 16)
	safe["hits_by_source"] = _sanitize_numeric_dictionary(summary.get("hits_by_source", {}), 16)
	safe["defeats_by_archetype"] = _sanitize_numeric_dictionary(summary.get("defeats_by_archetype", {}), 16)
	return safe


func _sanitize_string_array(value, limit: int) -> Array[String]:
	var safe: Array[String] = []
	if not (value is Array):
		return safe
	for item in value:
		if safe.size() >= limit:
			break
		safe.append(str(item).left(64))
	return safe


func _sanitize_numeric_dictionary(value, limit: int) -> Dictionary:
	var safe := {}
	if not (value is Dictionary):
		return safe
	for key in value:
		if safe.size() >= limit:
			break
		safe[str(key).left(64)] = maxf(0.0, float(value[key]))
	return safe
