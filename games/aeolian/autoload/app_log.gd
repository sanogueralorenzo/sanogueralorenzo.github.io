extends Node

## Small structured logger shared by runtime systems. The in-memory tail feeds the
## development overlay and future player-facing diagnostic export.

const MAX_RECENT_ENTRIES := 200

var _recent_entries: Array[Dictionary] = []


func debug(category: StringName, message: String, fields: Dictionary = {}) -> void:
	_write("DEBUG", category, message, fields)


func info(category: StringName, message: String, fields: Dictionary = {}) -> void:
	_write("INFO", category, message, fields)


func warning(category: StringName, message: String, fields: Dictionary = {}) -> void:
	_write("WARN", category, message, fields)


func error(category: StringName, message: String, fields: Dictionary = {}) -> void:
	_write("ERROR", category, message, fields)


func recent_entries() -> Array[Dictionary]:
	return _recent_entries.duplicate(true)


func _write(level: String, category: StringName, message: String, fields: Dictionary) -> void:
	var entry := {
		"timestamp": Time.get_datetime_string_from_system(true, true),
		"level": level,
		"category": String(category),
		"build": ProjectSettings.get_setting("application/config/version", "unknown"),
		"message": message,
		"fields": fields.duplicate(true),
	}
	_recent_entries.append(entry)
	if _recent_entries.size() > MAX_RECENT_ENTRIES:
		_recent_entries.pop_front()

	var suffix := ""
	if not fields.is_empty():
		suffix = " " + JSON.stringify(fields)
	var line := "[AEOLIAN][%s][%s] %s%s" % [level, category, message, suffix]
	if level == "ERROR":
		push_error(line)
	elif level == "WARN":
		push_warning(line)
	else:
		print(line)
