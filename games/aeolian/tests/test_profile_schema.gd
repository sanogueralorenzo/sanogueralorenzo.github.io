extends RefCounted


static func run(suite: RefCounted) -> void:
	print("ProfileSchema")
	suite.run_test("version zero migrates explicitly", func() -> void:
		var migrated := ProfileSchema.migrate({
			"unlocks": ["edge_control", "edge_control", "aerial"],
			"runs": 4,
			"completions": 2,
			"best_time_ms": 620000,
		})
		suite.assert_equal(migrated.schema_version, 1)
		suite.assert_equal(migrated.unlocks, PackedStringArray(["edge_control", "aerial"]))
		suite.assert_equal(migrated.stats.runs_started, 4)
		suite.assert_equal(migrated.stats.runs_completed, 2)
	)
	suite.run_test("invalid values clamp safely", func() -> void:
		var candidate := ProfileSchema.defaults()
		candidate.stats.runs_started = -5
		candidate.stats.runs_completed = 200
		candidate.checkpoint.valid = true
		candidate.checkpoint.plan_signature = ""
		candidate.checkpoint.biome_index = 99
		var normalized := ProfileSchema.normalize(candidate)
		suite.assert_equal(normalized.stats.runs_started, 0)
		suite.assert_equal(normalized.stats.runs_completed, 0)
		suite.assert_false(normalized.checkpoint.valid)
		suite.assert_equal(normalized.checkpoint.biome_index, 2)
	)
	suite.run_test("future schema is refused", func() -> void:
		var candidate := ProfileSchema.defaults()
		candidate.schema_version = ProfileSchema.CURRENT_VERSION + 1
		suite.assert_true(ProfileSchema.migrate(candidate).is_empty())
	)
	suite.run_test("legacy ConfigFile adapter preserves v0 statistics", func() -> void:
		var legacy := ConfigFile.new()
		legacy.set_value("progress", "unlocks", PackedStringArray(["aerial"]))
		legacy.set_value("stats", "runs", 7)
		legacy.set_value("stats", "completions", 3)
		legacy.set_value("stats", "best_time_ms", 610000)
		var migrated := ProfileSchema.migrate(ProfileConfigCodec.decode(legacy))
		suite.assert_equal(migrated.unlocks, PackedStringArray(["aerial"]))
		suite.assert_equal(migrated.stats.runs_started, 7)
		suite.assert_equal(migrated.stats.runs_completed, 3)
		suite.assert_equal(migrated.stats.best_time_ms, 610000)
	)
