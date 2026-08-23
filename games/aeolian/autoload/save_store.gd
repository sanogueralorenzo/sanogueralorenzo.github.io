extends Node

signal profile_loaded
signal profile_changed

const PROFILE_PATH := "user://profile.cfg"

var profile := ProfileSchema.defaults()
var _preserved_values: Dictionary = {}
var _writes_blocked := false


func _ready() -> void:
	load_profile()


func load_profile(path := PROFILE_PATH) -> Error:
	_writes_blocked = false
	_preserved_values.clear()
	var config := ConfigFile.new()
	var error := config.load(path)
	if error != OK:
		var backup := ConfigFile.new()
		var backup_error := backup.load(path + ".bak")
		if backup_error == OK:
			config = backup
			if error != ERR_FILE_NOT_FOUND:
				_quarantine_invalid_file(path)
			AppLog.warning(&"save", "Recovered profile from backup", {"main_error": error})
		elif error == ERR_FILE_NOT_FOUND and backup_error == ERR_FILE_NOT_FOUND:
			profile = ProfileSchema.defaults()
			profile_loaded.emit()
			return OK
		else:
			profile = ProfileSchema.defaults()
			_quarantine_invalid_file(path)
			AppLog.error(&"save", "Profile and backup were unreadable", {
				"main_error": error,
				"backup_error": backup_error,
			})
			profile_loaded.emit()
			return error

	var schema_version := int(config.get_value("meta", "schema_version", 0))
	if schema_version > ProfileSchema.CURRENT_VERSION:
		profile = ProfileSchema.defaults()
		_writes_blocked = true
		AppLog.warning(&"save", "Newer profile schema left untouched", {
			"schema_version": schema_version,
		})
		profile_loaded.emit()
		return ERR_UNAVAILABLE

	var candidate := ProfileConfigCodec.decode(config)
	var migrated: Dictionary = ProfileSchema.migrate(candidate)
	if migrated.is_empty():
		profile = ProfileSchema.defaults()
		_quarantine_invalid_file(path)
		AppLog.error(&"save", "Profile schema was unsupported and quarantined")
		profile_loaded.emit()
		return ERR_INVALID_DATA
	profile = migrated
	_capture_preserved_values(config, schema_version)
	profile_loaded.emit()
	return OK


func save_profile(path := PROFILE_PATH) -> Error:
	if _writes_blocked:
		AppLog.warning(&"save", "Refused to overwrite profile from a newer schema")
		return ERR_UNAVAILABLE
	profile = ProfileSchema.normalize(profile)
	if profile.is_empty():
		AppLog.error(&"save", "Refused to write an invalid in-memory profile")
		return ERR_INVALID_DATA
	var config := ConfigFile.new()
	for preserved_section: String in _preserved_values:
		for preserved_key: String in _preserved_values[preserved_section]:
			config.set_value(
				preserved_section,
				preserved_key,
				_preserved_values[preserved_section][preserved_key]
			)
	config.set_value("meta", "schema_version", ProfileSchema.CURRENT_VERSION)
	config.set_value("progress", "unlocks", profile.unlocks)
	for key: String in profile.stats:
		config.set_value("stats", key, profile.stats[key])
	for key: String in profile.checkpoint:
		config.set_value("checkpoint", key, profile.checkpoint[key])
	var error := SafeConfigFile.save(config, path)
	if error == OK:
		profile_changed.emit()
	else:
		AppLog.error(&"save", "Could not save profile", {"error": error})
	return error


func record_run_started() -> Error:
	profile.stats.runs_started += 1
	return save_profile()


func clear_checkpoint() -> Error:
	profile.checkpoint = ProfileSchema.defaults().checkpoint
	return save_profile()


func _quarantine_invalid_file(path: String) -> void:
	if not FileAccess.file_exists(path):
		return
	var quarantine := "%s.corrupt-%d" % [path, Time.get_unix_time_from_system()]
	var error := DirAccess.rename_absolute(
		ProjectSettings.globalize_path(path),
		ProjectSettings.globalize_path(quarantine)
	)
	if error != OK:
		AppLog.warning(&"save", "Could not quarantine invalid profile", {"error": error})


func _capture_preserved_values(config: ConfigFile, source_schema_version: int) -> void:
	for section: String in config.get_sections():
		_preserved_values[section] = {}
		for key: String in config.get_section_keys(section):
			if source_schema_version == 0 and section == "stats" \
					and key in ["runs", "completions"]:
				continue
			_preserved_values[section][key] = config.get_value(section, key)
