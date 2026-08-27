class_name ProgressProfile
extends RefCounted

const RunProtocolCatalog = preload("res://scripts/run_protocols.gd")
const SCHEMA_VERSION := 2
const MINIMUM_SUPPORTED_SCHEMA := 1
const DEFAULT_PATH := "user://overrush_profile.json"

var momentum := 0
var completed_runs := 0
var victories := 0
var best_time_seconds := 0.0
var selected_protocol: StringName = RunProtocolCatalog.STANDARD
var reduced_motion := false
var high_contrast_telegraphs := false
var guidance_enabled := true
var onboarding_completed := false


func reset() -> void:
	momentum = 0
	completed_runs = 0
	victories = 0
	best_time_seconds = 0.0
	selected_protocol = RunProtocolCatalog.STANDARD
	reduced_motion = false
	high_contrast_telegraphs = false
	guidance_enabled = true
	onboarding_completed = false


func get_unlocked_protocols() -> Array[StringName]:
	return RunProtocolCatalog.get_unlocked(momentum)


func select_protocol(protocol_id: StringName) -> bool:
	if protocol_id not in get_unlocked_protocols():
		return false
	selected_protocol = protocol_id
	return true


func record_run(elapsed_time: float, enemies_defeated: int, victory: bool) -> Dictionary:
	var unlocked_before := get_unlocked_protocols()
	var definition := RunProtocolCatalog.get_definition(selected_protocol)
	var base_reward := elapsed_time / 12.0 + maxi(enemies_defeated, 0) * 0.25 + (75.0 if victory else 0.0)
	var earned := maxi(1, roundi(base_reward * float(definition.reward_multiplier)))
	momentum += earned
	completed_runs += 1
	if victory:
		victories += 1
	best_time_seconds = maxf(best_time_seconds, maxf(0.0, elapsed_time))
	var new_unlocks: Array[StringName] = []
	for protocol_id in get_unlocked_protocols():
		if protocol_id not in unlocked_before:
			new_unlocks.append(protocol_id)
	return {
		"momentum_earned": earned,
		"momentum_total": momentum,
		"new_unlocks": new_unlocks,
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
	var saved_protocol := StringName(str(data.get("selected_protocol", RunProtocolCatalog.STANDARD)))
	selected_protocol = saved_protocol if saved_protocol in get_unlocked_protocols() else RunProtocolCatalog.STANDARD
	reduced_motion = bool(data.get("reduced_motion", false))
	high_contrast_telegraphs = bool(data.get("high_contrast_telegraphs", false))
	guidance_enabled = bool(data.get("guidance_enabled", true))
	onboarding_completed = bool(data.get("onboarding_completed", false))
	return true


func _to_dictionary() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"momentum": momentum,
		"completed_runs": completed_runs,
		"victories": victories,
		"best_time_seconds": best_time_seconds,
		"selected_protocol": str(selected_protocol),
		"reduced_motion": reduced_motion,
		"high_contrast_telegraphs": high_contrast_telegraphs,
		"guidance_enabled": guidance_enabled,
		"onboarding_completed": onboarding_completed,
	}
