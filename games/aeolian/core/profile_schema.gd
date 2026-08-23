class_name ProfileSchema
extends RefCounted

const CURRENT_VERSION := 1


static func defaults() -> Dictionary:
	return {
		"schema_version": CURRENT_VERSION,
		"unlocks": PackedStringArray(),
		"stats": {
			"runs_started": 0,
			"runs_completed": 0,
			"best_time_ms": -1,
		},
		"checkpoint": {
			"valid": false,
			"seed": 0,
			"plan_signature": "",
			"biome_index": 0,
			"upgrade_ids": PackedStringArray(),
		},
	}


static func migrate(candidate: Dictionary) -> Dictionary:
	var working := candidate.duplicate(true)
	var version := int(working.get("schema_version", 0))
	if version < 0 or version > CURRENT_VERSION:
		return {}
	while version < CURRENT_VERSION:
		match version:
			0:
				working = _migrate_v0_to_v1(working)
			_:
				return {}
		version = int(working.get("schema_version", -1))
	return normalize(working)


static func normalize(candidate: Dictionary) -> Dictionary:
	if int(candidate.get("schema_version", -1)) != CURRENT_VERSION:
		return {}
	var result := defaults()
	result.unlocks = _string_array(candidate.get("unlocks", PackedStringArray()))
	var stats: Dictionary = candidate.get("stats", {}) if candidate.get("stats", {}) is Dictionary else {}
	result.stats.runs_started = maxi(0, int(stats.get("runs_started", 0)))
	result.stats.runs_completed = clampi(int(stats.get("runs_completed", 0)), 0, result.stats.runs_started)
	result.stats.best_time_ms = maxi(-1, int(stats.get("best_time_ms", -1)))
	var checkpoint: Dictionary = candidate.get("checkpoint", {}) if candidate.get("checkpoint", {}) is Dictionary else {}
	result.checkpoint.valid = bool(checkpoint.get("valid", false))
	result.checkpoint.seed = int(checkpoint.get("seed", 0))
	result.checkpoint.plan_signature = String(checkpoint.get("plan_signature", ""))
	result.checkpoint.biome_index = clampi(int(checkpoint.get("biome_index", 0)), 0, 2)
	result.checkpoint.upgrade_ids = _string_array(checkpoint.get("upgrade_ids", PackedStringArray()))
	if result.checkpoint.valid and result.checkpoint.plan_signature.is_empty():
		result.checkpoint.valid = false
	return result


static func _migrate_v0_to_v1(old: Dictionary) -> Dictionary:
	var migrated := defaults()
	migrated.unlocks = _string_array(old.get("unlocks", PackedStringArray()))
	migrated.stats.runs_started = maxi(0, int(old.get("runs", 0)))
	migrated.stats.runs_completed = clampi(int(old.get("completions", 0)), 0, migrated.stats.runs_started)
	migrated.stats.best_time_ms = maxi(-1, int(old.get("best_time_ms", -1)))
	return migrated


static func _string_array(value: Variant) -> PackedStringArray:
	var result := PackedStringArray()
	if value is PackedStringArray or value is Array:
		for item: Variant in value:
			var text := String(item)
			if not text.is_empty() and text not in result:
				result.append(text)
	return result

