extends Node

signal setting_changed(section: StringName, key: StringName, value: Variant)
signal bindings_changed(action: StringName)

const SETTINGS_PATH := "user://settings.cfg"

var _values := SettingsSchema.defaults()
var _default_bindings: Dictionary = {}
var _preserved_values: Dictionary = {}
var _writes_blocked := false


func _ready() -> void:
	_capture_default_bindings()
	load_settings()
	apply_all()


func get_setting(section: StringName, key: StringName) -> Variant:
	if not SettingsSchema.has_setting(section, key):
		push_error("Unknown AEOLIAN setting: %s/%s" % [section, key])
		return null
	return _values[String(section)][String(key)]


func set_setting(section: StringName, key: StringName, value: Variant, persist := true) -> bool:
	if not SettingsSchema.has_setting(section, key):
		AppLog.warning(&"settings", "Rejected unknown setting", {"section": section, "key": key})
		return false
	var normalized: Variant = SettingsSchema.normalize(section, key, value)
	_values[String(section)][String(key)] = normalized
	_apply_setting(section, key, normalized)
	setting_changed.emit(section, key, normalized)
	if persist:
		return save_settings() == OK
	return true


func reset_section(section: StringName) -> bool:
	if not SettingsSchema.DEFAULTS.has(String(section)):
		return false
	for key: String in SettingsSchema.DEFAULTS[String(section)]:
		set_setting(section, key, SettingsSchema.DEFAULTS[String(section)][key], false)
	return save_settings() == OK


func replace_bindings(action: StringName, events: Array[InputEvent], persist := true) -> bool:
	if action not in InputService.REMAPPABLE_ACTIONS or not InputMap.has_action(action):
		return false
	var encoded: Array[Dictionary] = []
	for event: InputEvent in events:
		var data := InputBindingCodec.encode(event)
		if data.is_empty():
			return false
		encoded.append(data)
	if encoded.is_empty():
		return false
	InputMap.action_erase_events(action)
	for event: InputEvent in events:
		InputMap.action_add_event(action, event)
	bindings_changed.emit(action)
	if persist:
		return save_settings() == OK
	return true


func reset_binding(action: StringName, persist := true) -> bool:
	if not _default_bindings.has(action):
		return false
	var events: Array[InputEvent] = []
	for event: InputEvent in _default_bindings[action]:
		events.append(event.duplicate(true))
	return replace_bindings(action, events, persist)


func save_settings(path := SETTINGS_PATH) -> Error:
	if _writes_blocked:
		AppLog.warning(&"settings", "Refused to overwrite settings from a newer schema")
		return ERR_UNAVAILABLE
	var config := ConfigFile.new()
	for preserved_section: String in _preserved_values:
		for preserved_key: String in _preserved_values[preserved_section]:
			config.set_value(
				preserved_section,
				preserved_key,
				_preserved_values[preserved_section][preserved_key]
			)
	config.set_value("meta", "schema_version", SettingsSchema.CURRENT_VERSION)
	for section: String in _values:
		for key: String in _values[section]:
			config.set_value(section, key, _values[section][key])
	for action: StringName in InputService.REMAPPABLE_ACTIONS:
		var encoded: Array[Dictionary] = []
		for event: InputEvent in InputMap.action_get_events(action):
			var data := InputBindingCodec.encode(event)
			if not data.is_empty():
				encoded.append(data)
		config.set_value("bindings", String(action), encoded)
	var error := SafeConfigFile.save(config, path)
	if error != OK:
		AppLog.error(&"settings", "Could not save settings", {"error": error})
	return error


func load_settings(path := SETTINGS_PATH) -> Error:
	_writes_blocked = false
	_preserved_values.clear()
	var config := ConfigFile.new()
	var error := config.load(path)
	if error == ERR_FILE_NOT_FOUND:
		error = config.load(path + ".bak")
		if error == ERR_FILE_NOT_FOUND:
			_values = SettingsSchema.defaults()
			return OK
	if error != OK:
		var backup := ConfigFile.new()
		var backup_error := backup.load(path + ".bak")
		if backup_error != OK:
			_values = SettingsSchema.defaults()
			AppLog.warning(&"settings", "Invalid settings and backup; defaults retained", {
				"main_error": error,
				"backup_error": backup_error,
			})
			return error
		config = backup
		if error != ERR_FILE_NOT_FOUND:
			_quarantine_invalid_file(path)
		AppLog.warning(&"settings", "Recovered settings from backup", {"main_error": error})
	var schema_version := int(config.get_value("meta", "schema_version", 0))
	if schema_version > SettingsSchema.CURRENT_VERSION:
		_values = SettingsSchema.defaults()
		_writes_blocked = true
		AppLog.warning(&"settings", "Newer settings schema left untouched", {
			"schema_version": schema_version,
		})
		return ERR_UNAVAILABLE
	if schema_version != SettingsSchema.CURRENT_VERSION:
		_values = SettingsSchema.defaults()
		AppLog.warning(&"settings", "Unsupported settings schema; defaults retained", {
			"schema_version": schema_version,
		})
		return ERR_INVALID_DATA
	_capture_preserved_values(config)
	var candidate := {}
	for section: String in SettingsSchema.DEFAULTS:
		candidate[section] = {}
		for key: String in SettingsSchema.DEFAULTS[section]:
			candidate[section][key] = config.get_value(section, key, SettingsSchema.DEFAULTS[section][key])
	_values = SettingsSchema.normalize_all(candidate)
	_load_bindings(config)
	return OK


func apply_all() -> void:
	for section: String in _values:
		for key: String in _values[section]:
			_apply_setting(section, key, _values[section][key])


func _apply_setting(section: StringName, key: StringName, value: Variant) -> void:
	match "%s/%s" % [section, key]:
		"audio/master_db":
			AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), float(value))
		"audio/music_db":
			_set_bus_volume(&"Music", float(value))
		"audio/effects_db":
			_set_bus_volume(&"Effects", float(value))
		"controls/gamepad_deadzone":
			for action: StringName in InputService.REMAPPABLE_ACTIONS:
				InputMap.action_set_deadzone(action, float(value))
		"graphics/vsync":
			if DisplayServer.get_name() != "headless":
				DisplayServer.window_set_vsync_mode(
					DisplayServer.VSYNC_ENABLED if value else DisplayServer.VSYNC_DISABLED
				)


func _set_bus_volume(bus_name: StringName, volume_db: float) -> void:
	var index := AudioServer.get_bus_index(bus_name)
	if index >= 0:
		AudioServer.set_bus_volume_db(index, volume_db)


func _capture_default_bindings() -> void:
	for action: StringName in InputService.REMAPPABLE_ACTIONS:
		var events: Array[InputEvent] = []
		for event: InputEvent in InputMap.action_get_events(action):
			events.append(event.duplicate(true))
		_default_bindings[action] = events


func _load_bindings(config: ConfigFile) -> void:
	for action: StringName in InputService.REMAPPABLE_ACTIONS:
		if not config.has_section_key("bindings", String(action)):
			continue
		var encoded: Variant = config.get_value("bindings", String(action), [])
		if not encoded is Array or encoded.is_empty():
			continue
		var decoded: Array[InputEvent] = []
		for item: Variant in encoded:
			if not item is Dictionary:
				decoded.clear()
				break
			var event := InputBindingCodec.decode(item)
			if event == null:
				decoded.clear()
				break
			decoded.append(event)
		if not decoded.is_empty():
			replace_bindings(action, decoded, false)


func _capture_preserved_values(config: ConfigFile) -> void:
	for section: String in config.get_sections():
		_preserved_values[section] = {}
		for key: String in config.get_section_keys(section):
			_preserved_values[section][key] = config.get_value(section, key)


func _quarantine_invalid_file(path: String) -> void:
	if not FileAccess.file_exists(path):
		return
	var quarantine := "%s.corrupt-%d" % [path, Time.get_unix_time_from_system()]
	var error := DirAccess.rename_absolute(
		ProjectSettings.globalize_path(path),
		ProjectSettings.globalize_path(quarantine)
	)
	if error != OK:
		AppLog.warning(&"settings", "Could not quarantine invalid settings", {"error": error})
