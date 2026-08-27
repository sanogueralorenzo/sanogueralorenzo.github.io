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
	_test_schema_two_audio_migration()
	_test_schema_three_recap_migration()
	_test_corrupt_profile_falls_back_safely()
	_cleanup()
	if _failures.is_empty():
		print("Progress profile validation passed — unlocks, recap records, schema migration, comfort settings, atomic save, and recovery.")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _test_unlock_progression_without_permanent_power() -> void:
	var profile := ProgressProfileModel.new()
	var first_result := profile.record_run(1200.0, 100, true, {
		"damage_dealt": 12400.0,
		"distance_meters": 68400.0,
		"build_name": "DASHBREAKER • RAMJET",
	})
	_expect(int(first_result.momentum_earned) == 200, "A baseline full victory should award deterministic Momentum.")
	_expect(RunProtocolCatalog.REDLINE in first_result.new_unlocks, "The first strong run should unlock Redline Protocol.")
	_expect(&"damage" in first_result.new_records and &"distance" in first_result.new_records, "A first measured run should establish explicit personal records.")
	_expect(profile.best_damage == 12400.0 and str(profile.last_run_summary.build_name) == "DASHBREAKER • RAMJET", "Balance evidence and build identity should be retained after a run.")
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
	profile.best_clear_count = 144
	profile.best_damage = 18250.0
	profile.best_distance_meters = 71500.0
	profile.last_run_summary = {
		"build_name": "ARCSTORM • STORM LANCE",
		"damage_dealt": 18250.0,
		"distance_meters": 71500.0,
		"upgrade_history": ["velocity_coil", "storm_lance"],
	}
	profile.selected_protocol = RunProtocolCatalog.REDLINE
	profile.reduced_motion = true
	profile.high_contrast_telegraphs = true
	profile.guidance_enabled = false
	profile.onboarding_completed = true
	profile.master_volume = 0.35
	profile.music_volume = 0.4
	_expect(profile.save(_test_path), "A valid profile should save atomically.")
	var loaded := ProgressProfileModel.new()
	_expect(loaded.load(_test_path), "A saved profile should load.")
	_expect(loaded.momentum == 470 and loaded.selected_protocol == RunProtocolCatalog.REDLINE, "Profile state should survive a save/load round trip.")
	_expect(loaded.best_clear_count == 144 and loaded.best_damage == 18250.0 and loaded.best_distance_meters == 71500.0, "Personal run records should survive a save/load round trip.")
	_expect(str(loaded.last_run_summary.build_name) == "ARCSTORM • STORM LANCE" and (loaded.last_run_summary.upgrade_history as Array).size() == 2, "The bounded last-run snapshot should survive a save/load round trip.")
	_expect(loaded.reduced_motion and loaded.high_contrast_telegraphs, "Visual accessibility preferences should survive a save/load round trip.")
	_expect(not loaded.guidance_enabled and loaded.onboarding_completed, "Guidance preferences should survive a save/load round trip.")
	_expect(is_equal_approx(loaded.master_volume, 0.35) and is_equal_approx(loaded.music_volume, 0.4), "Audio mix preferences should survive a save/load round trip.")

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
	_expect(is_equal_approx(migrated.master_volume, 0.8) and is_equal_approx(migrated.music_volume, 0.55), "Older profiles should receive balanced default audio levels.")
	for suffix in ["", ".tmp", ".bak"]:
		var target: String = ProjectSettings.globalize_path(legacy_path) + suffix
		if FileAccess.file_exists(target):
			DirAccess.remove_absolute(target)


func _test_schema_two_audio_migration() -> void:
	var legacy_path := _test_path + ".legacy2"
	var legacy_file := FileAccess.open(ProjectSettings.globalize_path(legacy_path), FileAccess.WRITE)
	legacy_file.store_string(JSON.stringify({
		"schema_version": 2,
		"momentum": 550,
		"completed_runs": 4,
		"victories": 2,
		"best_time_seconds": 1200.0,
		"selected_protocol": "elite_hunt",
		"reduced_motion": true,
		"high_contrast_telegraphs": true,
		"guidance_enabled": false,
		"onboarding_completed": true,
	}))
	legacy_file.close()
	var migrated := ProgressProfileModel.new()
	_expect(migrated.load(legacy_path), "A schema-two profile should migrate when audio preferences are introduced.")
	_expect(migrated.reduced_motion and migrated.high_contrast_telegraphs and migrated.onboarding_completed, "Schema-two migration should retain existing comfort preferences.")
	_expect(is_equal_approx(migrated.master_volume, 0.8) and is_equal_approx(migrated.music_volume, 0.55), "Schema-two profiles should receive balanced default audio levels.")
	for suffix in ["", ".tmp", ".bak"]:
		var target: String = ProjectSettings.globalize_path(legacy_path) + suffix
		if FileAccess.file_exists(target):
			DirAccess.remove_absolute(target)


func _test_schema_three_recap_migration() -> void:
	var legacy_path := _test_path + ".legacy3"
	var legacy_file := FileAccess.open(ProjectSettings.globalize_path(legacy_path), FileAccess.WRITE)
	legacy_file.store_string(JSON.stringify({
		"schema_version": 3,
		"momentum": 700,
		"completed_runs": 6,
		"victories": 3,
		"best_time_seconds": 1200.0,
		"selected_protocol": "elite_hunt",
		"master_volume": 0.5,
		"music_volume": 0.45,
	}))
	legacy_file.close()
	var migrated := ProgressProfileModel.new()
	_expect(migrated.load(legacy_path), "A schema-three profile should migrate when bounded run recaps are introduced.")
	_expect(migrated.best_clear_count == 0 and migrated.best_damage == 0.0 and migrated.last_run_summary.is_empty() == false, "Schema-three profiles should receive safe empty recap defaults without losing progression.")
	_expect(migrated.momentum == 700 and migrated.victories == 3, "Recap migration should retain prior run progression.")
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
