extends SceneTree

const ProgressProfileModel = preload("res://scripts/progress_profile.gd")
const RunProtocolCatalog = preload("res://scripts/run_protocols.gd")

var _failures: Array[String] = []
var _test_path := ""


func _init() -> void:
	_test_path = "user://overrush_profile_test_%d.json" % Time.get_ticks_usec()
	_test_unlock_progression_without_permanent_power()
	_test_atomic_round_trip_and_backup_recovery()
	_test_schema_one_migration()
	_test_corrupt_profile_falls_back_safely()
	_cleanup()
	if _failures.is_empty():
		print("Progress profile validation passed — unlocks, schema migration, comfort settings, atomic save, and recovery.")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _test_unlock_progression_without_permanent_power() -> void:
	var profile := ProgressProfileModel.new()
	var first_result := profile.record_run(1200.0, 100, true)
	_expect(int(first_result.momentum_earned) == 200, "A baseline full victory should award deterministic Momentum.")
	_expect(RunProtocolCatalog.REDLINE in first_result.new_unlocks, "The first strong run should unlock Redline Protocol.")
	_expect(RunProtocolCatalog.GLASS_VELOCITY not in profile.get_unlocked_protocols(), "Later protocols should require additional runs.")
	_expect(profile.select_protocol(RunProtocolCatalog.REDLINE), "An unlocked challenge protocol should be selectable.")
	var second_result := profile.record_run(1200.0, 100, true)
	_expect(int(second_result.momentum_earned) == 270, "Protocol reward multipliers should affect progression rewards.")
	_expect(RunProtocolCatalog.GLASS_VELOCITY in second_result.new_unlocks, "Repeated successful runs should unlock a new tradeoff, not raw power.")


func _test_atomic_round_trip_and_backup_recovery() -> void:
	var profile := ProgressProfileModel.new()
	profile.momentum = 470
	profile.completed_runs = 2
	profile.victories = 2
	profile.best_time_seconds = 1200.0
	profile.selected_protocol = RunProtocolCatalog.REDLINE
	profile.reduced_motion = true
	profile.high_contrast_telegraphs = true
	profile.guidance_enabled = false
	profile.onboarding_completed = true
	_expect(profile.save(_test_path), "A valid profile should save atomically.")
	var loaded := ProgressProfileModel.new()
	_expect(loaded.load(_test_path), "A saved profile should load.")
	_expect(loaded.momentum == 470 and loaded.selected_protocol == RunProtocolCatalog.REDLINE, "Profile state should survive a save/load round trip.")
	_expect(loaded.reduced_motion and loaded.high_contrast_telegraphs, "Visual accessibility preferences should survive a save/load round trip.")
	_expect(not loaded.guidance_enabled and loaded.onboarding_completed, "Guidance preferences should survive a save/load round trip.")

	var absolute_path := ProjectSettings.globalize_path(_test_path)
	profile.momentum = 520
	_expect(profile.save(_test_path), "A later atomic save should succeed and retain the previous profile as a backup.")
	var corrupt_primary := FileAccess.open(absolute_path, FileAccess.WRITE)
	corrupt_primary.store_string("{ interrupted write")
	corrupt_primary.close()
	var recovered := ProgressProfileModel.new()
	_expect(recovered.load(_test_path), "A corrupt primary profile should recover from its retained backup.")
	_expect(recovered.momentum == 470, "Backup recovery should preserve progression state.")


func _test_schema_one_migration() -> void:
	var legacy_path := _test_path + ".legacy"
	var legacy_file := FileAccess.open(ProjectSettings.globalize_path(legacy_path), FileAccess.WRITE)
	legacy_file.store_string(JSON.stringify({
		"schema_version": 1,
		"momentum": 300,
		"completed_runs": 2,
		"victories": 1,
		"best_time_seconds": 780.0,
		"selected_protocol": "glass_velocity",
	}))
	legacy_file.close()
	var migrated := ProgressProfileModel.new()
	_expect(migrated.load(legacy_path), "A schema-one profile should migrate without losing progression.")
	_expect(migrated.momentum == 300 and migrated.selected_protocol == RunProtocolCatalog.GLASS_VELOCITY, "Schema migration should retain earned Momentum and protocol selection.")
	_expect(not migrated.reduced_motion and not migrated.high_contrast_telegraphs and migrated.guidance_enabled, "Schema migration should apply safe accessibility defaults.")
	for suffix in ["", ".tmp", ".bak"]:
		var target: String = ProjectSettings.globalize_path(legacy_path) + suffix
		if FileAccess.file_exists(target):
			DirAccess.remove_absolute(target)


func _test_corrupt_profile_falls_back_safely() -> void:
	var absolute_path := ProjectSettings.globalize_path(_test_path)
	var file := FileAccess.open(absolute_path, FileAccess.WRITE)
	file.store_string("{ definitely not valid json")
	file.close()
	var profile := ProgressProfileModel.new()
	_expect(not profile.load(_test_path), "A corrupt profile without a backup should report a failed load.")
	_expect(profile.momentum == 0 and profile.selected_protocol == RunProtocolCatalog.STANDARD, "Corrupt data should reset to safe defaults.")


func _cleanup() -> void:
	var absolute_path := ProjectSettings.globalize_path(_test_path)
	for suffix in ["", ".tmp", ".bak"]:
		var target: String = absolute_path + suffix
		if FileAccess.file_exists(target):
			DirAccess.remove_absolute(target)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
