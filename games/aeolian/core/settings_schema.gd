class_name SettingsSchema
extends RefCounted

const CURRENT_VERSION := 1
const DEFAULTS := {
	"audio": {
		"master_db": 0.0,
		"music_db": -3.0,
		"effects_db": 0.0,
	},
	"controls": {
		"steer_sensitivity": 1.0,
		"gamepad_deadzone": 0.15,
		"vibration_strength": 1.0,
		"invert_camera_y": false,
	},
	"graphics": {
		"preset": "high",
		"vsync": true,
	},
	"accessibility": {
		"camera_shake_strength": 1.0,
		"speed_lines_strength": 1.0,
	},
}


static func defaults() -> Dictionary:
	return DEFAULTS.duplicate(true)


static func has_setting(section: String, key: String) -> bool:
	return DEFAULTS.has(section) and DEFAULTS[section].has(key)


static func normalize(section: String, key: String, value: Variant) -> Variant:
	if not has_setting(section, key):
		return null

	match "%s/%s" % [section, key]:
		"audio/master_db", "audio/music_db", "audio/effects_db":
			if value is float or value is int:
				var numeric := float(value)
				if is_finite(numeric):
					return clampf(numeric, -60.0, 6.0)
		"controls/steer_sensitivity":
			if value is float or value is int:
				var numeric := float(value)
				if is_finite(numeric):
					return clampf(numeric, 0.25, 2.0)
		"controls/gamepad_deadzone":
			if value is float or value is int:
				var numeric := float(value)
				if is_finite(numeric):
					return clampf(numeric, 0.05, 0.5)
		"controls/vibration_strength", \
		"accessibility/camera_shake_strength", \
		"accessibility/speed_lines_strength":
			if value is float or value is int:
				var numeric := float(value)
				if is_finite(numeric):
					return clampf(numeric, 0.0, 1.0)
		"controls/invert_camera_y", "graphics/vsync":
			if value is bool:
				return value
		"graphics/preset":
			if value is String and value in ["low", "medium", "high"]:
				return value
	return DEFAULTS[section][key]


static func normalize_all(candidate: Dictionary) -> Dictionary:
	var normalized := defaults()
	for section: String in DEFAULTS:
		for key: String in DEFAULTS[section]:
			if candidate.has(section) and candidate[section] is Dictionary \
					and candidate[section].has(key):
				normalized[section][key] = normalize(section, key, candidate[section][key])
	return normalized
