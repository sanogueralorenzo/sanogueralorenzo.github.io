extends RefCounted


static func run(suite: RefCounted) -> void:
	print("SettingsSchema")
	suite.run_test("defaults are deep copies", func() -> void:
		var first := SettingsSchema.defaults()
		first.controls.steer_sensitivity = 0.25
		suite.assert_equal(SettingsSchema.defaults().controls.steer_sensitivity, 1.0)
	)
	suite.run_test("numeric values clamp", func() -> void:
		suite.assert_near(SettingsSchema.normalize("audio", "master_db", -100), -60.0, 0.0001)
		suite.assert_near(SettingsSchema.normalize("controls", "gamepad_deadzone", 2.0), 0.5, 0.0001)
		suite.assert_near(SettingsSchema.normalize("controls", "vibration_strength", -2.0), 0.0, 0.0001)
	)
	suite.run_test("invalid types fall back", func() -> void:
		suite.assert_equal(SettingsSchema.normalize("graphics", "vsync", "yes"), true)
		suite.assert_equal(SettingsSchema.normalize("graphics", "preset", "ultra"), "high")
		suite.assert_equal(SettingsSchema.normalize("audio", "master_db", NAN), 0.0)
		suite.assert_equal(SettingsSchema.normalize("controls", "gamepad_deadzone", INF), 0.15)
	)
	suite.run_test("candidate normalization ignores unknown data", func() -> void:
		var candidate := {
			"controls": {"steer_sensitivity": 1.5, "unknown": 99},
			"unknown": {"value": true},
		}
		var normalized := SettingsSchema.normalize_all(candidate)
		suite.assert_near(normalized.controls.steer_sensitivity, 1.5, 0.0001)
		suite.assert_false(normalized.has("unknown"))
		suite.assert_false(normalized.controls.has("unknown"))
	)
