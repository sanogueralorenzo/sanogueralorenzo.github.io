class_name ProgressProfile
extends RefCounted

const RunProtocolCatalog = preload("res://scripts/run_protocols.gd")
const RunBuildModel = preload("res://scripts/run_build.gd")
const VelocityChainModel = preload("res://scripts/velocity_chain.gd")
const SCHEMA_VERSION := 12
const MINIMUM_SUPPORTED_SCHEMA := 1
const DEFAULT_PATH := "user://overrush_profile.json"
const RUN_HISTORY_LIMIT := 20
const PLAYTEST_REPORT_FORMAT := "overrush_playtest_report"
const PLAYTEST_REPORT_VERSION := 1
const REPLAY_INTENTS: Array[String] = ["no", "maybe", "yes"]
const POSITIVE_PLAYTEST_TAGS: Array[String] = ["movement_highlight", "build_highlight", "climax_highlight"]
const ISSUE_PLAYTEST_TAGS: Array[String] = ["readability_issue", "terrain_issue", "difficulty_issue"]
const PLAYTEST_TAGS: Array[String] = POSITIVE_PLAYTEST_TAGS + ISSUE_PLAYTEST_TAGS
const PLAYTEST_TAG_NAMES := {
	"movement_highlight": "MOVEMENT",
	"build_highlight": "BUILD",
	"climax_highlight": "CLIMAX",
	"readability_issue": "READABILITY",
	"terrain_issue": "TERRAIN",
	"difficulty_issue": "DIFFICULTY",
}
const EVOLUTION_MASTERY_IDS: Array[StringName] = [&"ramjet", &"gravity_knot", &"twin_current", &"tempest_anchor", &"storm_lance", &"arc_orbit"]
const ARSENAL_MASTERY_IDS: Array[StringName] = [RunBuildModel.HUNTER_ARRAY, RunBuildModel.DRIFT_BLADES, RunBuildModel.BACKDRAFT_MINE]
const DRIVE_MASTERY_IDS: Array[StringName] = [RunBuildModel.REDLINE_CORE, RunBuildModel.AIRFRAME_CORE, RunBuildModel.PULSE_CORE]
const MASTERY_IDS: Array[StringName] = [
	&"ramjet", &"gravity_knot", &"twin_current", &"tempest_anchor", &"storm_lance", &"arc_orbit",
	RunBuildModel.HUNTER_ARRAY, RunBuildModel.DRIFT_BLADES, RunBuildModel.BACKDRAFT_MINE,
	RunBuildModel.REDLINE_CORE, RunBuildModel.AIRFRAME_CORE, RunBuildModel.PULSE_CORE,
]

var momentum := 0
var completed_runs := 0
var victories := 0
var best_time_seconds := 0.0
var best_clear_count := 0
var best_damage := 0.0
var best_distance_meters := 0.0
var best_velocity_chain := 0
var last_run_summary: Dictionary = {}
var run_history: Array[Dictionary] = []
var mastered_build_ids: Array[StringName] = []
var selected_protocol: StringName = RunProtocolCatalog.STANDARD
var reduced_motion := false
var high_contrast_telegraphs := false
var guidance_enabled := true
var onboarding_completed := false
var master_volume := 0.8
var music_volume := 0.55
var effects_volume := 1.0


func reset() -> void:
	momentum = 0
	completed_runs = 0
	victories = 0
	best_time_seconds = 0.0
	best_clear_count = 0
	best_damage = 0.0
	best_distance_meters = 0.0
	best_velocity_chain = 0
	last_run_summary.clear()
	run_history.clear()
	mastered_build_ids.clear()
	selected_protocol = RunProtocolCatalog.STANDARD
	reduced_motion = false
	high_contrast_telegraphs = false
	guidance_enabled = true
	onboarding_completed = false
	master_volume = 0.8
	music_volume = 0.55
	effects_volume = 1.0


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
	var run_velocity_chain := maxi(0, int(summary.get("best_velocity_chain", 0)))
	var flow_momentum_bonus := VelocityChainModel.get_momentum_bonus_for(run_velocity_chain)
	var earned := maxi(1, roundi(base_reward * float(definition.reward_multiplier)) + flow_momentum_bonus)
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
	if run_velocity_chain > best_velocity_chain:
		new_records.append(&"flow")
	momentum += earned
	completed_runs += 1
	if victory:
		victories += 1
	best_time_seconds = maxf(best_time_seconds, safe_elapsed)
	best_clear_count = maxi(best_clear_count, safe_clears)
	best_damage = maxf(best_damage, run_damage)
	best_distance_meters = maxf(best_distance_meters, run_distance)
	best_velocity_chain = maxi(best_velocity_chain, run_velocity_chain)
	last_run_summary = _sanitize_run_summary(summary)
	last_run_summary["elapsed_seconds"] = snappedf(safe_elapsed, 0.1)
	last_run_summary["enemies_defeated"] = safe_clears
	last_run_summary["victory"] = victory
	last_run_summary["protocol_id"] = str(selected_protocol)
	run_history.push_front(last_run_summary.duplicate(true))
	if run_history.size() > RUN_HISTORY_LIMIT:
		run_history.resize(RUN_HISTORY_LIMIT)
	var new_masteries: Array[StringName] = []
	if victory:
		for field_name in ["evolution_id", "arsenal_id", "catalyst_id"]:
			var mastery_id := StringName(str(last_run_summary.get(field_name, "")))
			if mastery_id in MASTERY_IDS and mastery_id not in mastered_build_ids:
				mastered_build_ids.append(mastery_id)
				new_masteries.append(mastery_id)
	var new_unlocks: Array[StringName] = []
	for protocol_id in get_unlocked_protocols():
		if protocol_id not in unlocked_before:
			new_unlocks.append(protocol_id)
	return {
		"momentum_earned": earned,
		"momentum_total": momentum,
		"flow_momentum_bonus": flow_momentum_bonus,
		"new_unlocks": new_unlocks,
		"new_records": new_records,
		"new_masteries": new_masteries,
	}


func get_mastery_count() -> int:
	return mastered_build_ids.size()


func is_build_mastered(mastery_id: StringName) -> bool:
	return mastery_id in mastered_build_ids


func get_mastery_count_for(mastery_ids: Array[StringName]) -> int:
	var count := 0
	for mastery_id in mastery_ids:
		if is_build_mastered(mastery_id):
			count += 1
	return count


func get_next_mastery_goal() -> String:
	for mastery_id in MASTERY_IDS:
		if mastery_id not in mastered_build_ids:
			return "BREAK THE APEX WITH %s" % RunBuildModel.UPGRADE_NAMES[mastery_id]
	return "ALL BUILD MASTERIES COMPLETE"


func get_recent_win_count(limit: int = 5) -> int:
	var wins := 0
	for index in range(mini(limit, run_history.size())):
		if bool(run_history[index].get("victory", false)):
			wins += 1
	return wins


func get_recent_run_count(limit: int = 5) -> int:
	return mini(limit, run_history.size())


func record_latest_replay_intent(intent: String) -> bool:
	var safe_intent := intent.to_lower()
	if safe_intent not in REPLAY_INTENTS or last_run_summary.is_empty() or run_history.is_empty():
		return false
	last_run_summary["replay_intent"] = safe_intent
	run_history[0]["replay_intent"] = safe_intent
	last_run_summary["playtest_tag"] = ""
	run_history[0]["playtest_tag"] = ""
	return true


func record_latest_playtest_tag(tag: String) -> bool:
	var safe_tag := tag.to_lower()
	if safe_tag not in PLAYTEST_TAGS or last_run_summary.is_empty() or run_history.is_empty():
		return false
	var replay_intent := str(last_run_summary.get("replay_intent", ""))
	var valid_tags := POSITIVE_PLAYTEST_TAGS if replay_intent == "yes" else ISSUE_PLAYTEST_TAGS
	if replay_intent not in REPLAY_INTENTS or safe_tag not in valid_tags:
		return false
	last_run_summary["playtest_tag"] = safe_tag
	run_history[0]["playtest_tag"] = safe_tag
	return true


func get_latest_playtest_report() -> Dictionary:
	if last_run_summary.is_empty():
		return {}
	return {
		"format": PLAYTEST_REPORT_FORMAT,
		"format_version": PLAYTEST_REPORT_VERSION,
		"profile_schema": SCHEMA_VERSION,
		"run": _sanitize_run_summary(last_run_summary),
	}


func get_latest_playtest_report_json() -> String:
	var report := get_latest_playtest_report()
	return "" if report.is_empty() else JSON.stringify(report, "\t")


func get_recent_replay_feedback_count(limit: int = 5) -> int:
	var count := 0
	for index in range(mini(limit, run_history.size())):
		if str(run_history[index].get("replay_intent", "")) in REPLAY_INTENTS:
			count += 1
	return count


func get_recent_replay_yes_count(limit: int = 5) -> int:
	var count := 0
	for index in range(mini(limit, run_history.size())):
		if str(run_history[index].get("replay_intent", "")) == "yes":
			count += 1
	return count


func get_recent_playtest_tag_count(limit: int = 10) -> int:
	var count := 0
	for index in range(mini(limit, run_history.size())):
		if str(run_history[index].get("playtest_tag", "")) in PLAYTEST_TAGS:
			count += 1
	return count


func get_recent_playtest_tag_frequency(tag: String, limit: int = 10) -> int:
	if tag not in PLAYTEST_TAGS:
		return 0
	var count := 0
	for index in range(mini(limit, run_history.size())):
		if str(run_history[index].get("playtest_tag", "")) == tag:
			count += 1
	return count


func get_top_recent_playtest_tag(limit: int = 10) -> String:
	var counts := {}
	for index in range(mini(limit, run_history.size())):
		var tag := str(run_history[index].get("playtest_tag", ""))
		if tag in PLAYTEST_TAGS:
			counts[tag] = int(counts.get(tag, 0)) + 1
	var top_tag := ""
	var top_count := 0
	for tag in PLAYTEST_TAGS:
		var count := int(counts.get(tag, 0))
		if count > top_count:
			top_tag = tag
			top_count = count
	return top_tag


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
	best_velocity_chain = maxi(0, int(data.get("best_velocity_chain", 0)))
	var saved_summary = data.get("last_run_summary", {})
	last_run_summary = _sanitize_run_summary(saved_summary if saved_summary is Dictionary else {})
	run_history = _sanitize_run_history(data.get("run_history", []))
	mastered_build_ids = _sanitize_mastery_ids(data.get("mastered_build_ids", []))
	var saved_protocol := StringName(str(data.get("selected_protocol", RunProtocolCatalog.STANDARD)))
	selected_protocol = saved_protocol if saved_protocol in get_unlocked_protocols() else RunProtocolCatalog.STANDARD
	reduced_motion = bool(data.get("reduced_motion", false))
	high_contrast_telegraphs = bool(data.get("high_contrast_telegraphs", false))
	guidance_enabled = bool(data.get("guidance_enabled", true))
	onboarding_completed = bool(data.get("onboarding_completed", false))
	master_volume = clampf(float(data.get("master_volume", 0.8)), 0.0, 1.0)
	music_volume = clampf(float(data.get("music_volume", 0.55)), 0.0, 1.0)
	effects_volume = clampf(float(data.get("effects_volume", 1.0)), 0.0, 1.0)
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
		"best_velocity_chain": best_velocity_chain,
		"last_run_summary": last_run_summary,
		"run_history": run_history,
		"mastered_build_ids": mastered_build_ids.map(func(id: StringName) -> String: return str(id)),
		"selected_protocol": str(selected_protocol),
		"reduced_motion": reduced_motion,
		"high_contrast_telegraphs": high_contrast_telegraphs,
		"guidance_enabled": guidance_enabled,
		"onboarding_completed": onboarding_completed,
		"master_volume": master_volume,
		"music_volume": music_volume,
		"effects_volume": effects_volume,
	}


func _sanitize_run_summary(summary: Dictionary) -> Dictionary:
	var replay_intent := str(summary.get("replay_intent", "")).to_lower()
	if replay_intent not in REPLAY_INTENTS:
		replay_intent = ""
	var playtest_tag := str(summary.get("playtest_tag", "")).to_lower()
	var valid_tags := POSITIVE_PLAYTEST_TAGS if replay_intent == "yes" else ISSUE_PLAYTEST_TAGS
	if replay_intent.is_empty() or playtest_tag not in valid_tags:
		playtest_tag = ""
	var safe := {
		"elapsed_seconds": maxf(0.0, float(summary.get("elapsed_seconds", 0.0))),
		"enemies_defeated": maxi(0, int(summary.get("enemies_defeated", 0))),
		"elite_defeats": maxi(0, int(summary.get("elite_defeats", 0))),
		"damage_dealt": maxf(0.0, float(summary.get("damage_dealt", 0.0))),
		"damage_taken": maxf(0.0, float(summary.get("damage_taken", 0.0))),
		"integrity_recovered": maxf(0.0, float(summary.get("integrity_recovered", 0.0))),
		"recovery_pickups": maxi(0, int(summary.get("recovery_pickups", 0))),
		"distance_meters": maxf(0.0, float(summary.get("distance_meters", 0.0))),
		"maximum_speed": maxf(0.0, float(summary.get("maximum_speed", 0.0))),
		"dash_count": maxi(0, int(summary.get("dash_count", 0))),
		"best_velocity_chain": maxi(0, int(summary.get("best_velocity_chain", 0))),
		"velocity_chain_defeats": maxi(0, int(summary.get("velocity_chain_defeats", 0))),
		"rerolls_used": maxi(0, int(summary.get("rerolls_used", 0))),
		"banishes_used": maxi(0, int(summary.get("banishes_used", 0))),
		"catalyst_id": str(summary.get("catalyst_id", "")).left(48),
		"arsenal_id": str(summary.get("arsenal_id", "")).left(48),
		"core_path": str(summary.get("core_path", "")).left(48),
		"evolution_id": str(summary.get("evolution_id", "")).left(48),
		"catalyst_uptime": clampf(float(summary.get("catalyst_uptime", 0.0)), 0.0, 1.0),
		"phase_reached": str(summary.get("phase_reached", "breakaway")).left(32),
		"apex_id": str(summary.get("apex_id", "")).left(48),
		"build_name": str(summary.get("build_name", "UNCOMMITTED")).left(80),
		"level": maxi(1, int(summary.get("level", 1))),
		"protocol_id": str(summary.get("protocol_id", RunProtocolCatalog.STANDARD)).left(48),
		"world_seed": int(summary.get("world_seed", 0)),
		"victory": bool(summary.get("victory", false)),
		"replay_intent": replay_intent,
		"playtest_tag": playtest_tag,
	}
	safe["upgrade_history"] = _sanitize_string_array(summary.get("upgrade_history", []), 64)
	safe["upgrade_events"] = _sanitize_upgrade_events(summary.get("upgrade_events", []))
	safe["damage_by_source"] = _sanitize_numeric_dictionary(summary.get("damage_by_source", {}), 16)
	safe["hits_by_source"] = _sanitize_numeric_dictionary(summary.get("hits_by_source", {}), 16)
	safe["damage_taken_by_source"] = _sanitize_numeric_dictionary(summary.get("damage_taken_by_source", {}), 16)
	safe["hits_taken_by_source"] = _sanitize_numeric_dictionary(summary.get("hits_taken_by_source", {}), 16)
	safe["defeats_by_archetype"] = _sanitize_numeric_dictionary(summary.get("defeats_by_archetype", {}), 16)
	safe["elite_traits_defeated"] = _sanitize_numeric_dictionary(summary.get("elite_traits_defeated", {}), 3)
	return safe


func _sanitize_upgrade_events(value) -> Array[Dictionary]:
	var safe: Array[Dictionary] = []
	if not (value is Array):
		return safe
	for item in value:
		if safe.size() >= 64:
			break
		if not (item is Dictionary):
			continue
		var milestone_kind := str(item.get("kind", "standard"))
		if milestone_kind not in ["standard", "engine", "evolution", "arsenal", "catalyst"]:
			milestone_kind = "standard"
		safe.append({
			"id": str(item.get("id", "")).left(48),
			"elapsed_seconds": maxf(0.0, float(item.get("elapsed_seconds", 0.0))),
			"level": maxi(1, int(item.get("level", 1))),
			"kind": milestone_kind,
		})
	return safe


func _sanitize_run_history(value) -> Array[Dictionary]:
	var safe: Array[Dictionary] = []
	if not (value is Array):
		return safe
	for item in value:
		if safe.size() >= RUN_HISTORY_LIMIT:
			break
		if item is Dictionary:
			safe.append(_sanitize_run_summary(item))
	return safe


func _sanitize_mastery_ids(value) -> Array[StringName]:
	var safe: Array[StringName] = []
	if not (value is Array):
		return safe
	for item in value:
		var mastery_id := StringName(str(item))
		if mastery_id in MASTERY_IDS and mastery_id not in safe:
			safe.append(mastery_id)
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
