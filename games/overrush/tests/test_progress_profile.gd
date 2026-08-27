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
	_test_schema_four_history_migration()
	_test_schema_five_cadence_migration()
	_test_schema_six_feedback_migration()
	_test_schema_seven_incoming_damage_migration()
	_test_schema_eight_recovery_migration()
	_test_schema_nine_effects_migration()
	_test_schema_ten_playtest_tag_migration()
	_test_schema_eleven_flow_migration()
	_test_bounded_history_and_mastery()
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
		"rerolls_used": 2,
		"banishes_used": 1,
		"apex_id": "velocity_reaver",
		"catalyst_id": "redline_core",
		"arsenal_id": "hunter_array",
		"evolution_id": "ramjet",
		"catalyst_uptime": 0.64,
		"damage_taken_by_source": {"skimmer_charge": 42.0},
		"integrity_recovered": 36.0,
		"recovery_pickups": 3,
		"best_velocity_chain": 36,
		"velocity_chain_defeats": 72,
		"upgrade_events": [{"id": "dash_nova", "elapsed_seconds": 12.0, "level": 2, "kind": "engine"}],
	})
	_expect(int(first_result.momentum_earned) == 218 and int(first_result.flow_momentum_bonus) == 18, "A baseline victory should add a modest deterministic Flow bonus without changing combat power.")
	_expect(RunProtocolCatalog.REDLINE in first_result.new_unlocks, "The first strong run should unlock Redline Protocol.")
	_expect(&"damage" in first_result.new_records and &"distance" in first_result.new_records and &"flow" in first_result.new_records, "A first measured run should establish explicit combat, traversal, and Flow records.")
	_expect(profile.best_damage == 12400.0 and str(profile.last_run_summary.build_name) == "DASHBREAKER • RAMJET", "Balance evidence and build identity should be retained after a run.")
	_expect(int(profile.last_run_summary.rerolls_used) == 2 and int(profile.last_run_summary.banishes_used) == 1, "Persisted balance evidence should distinguish draft agency from favorable rolls.")
	_expect(str(profile.last_run_summary.apex_id) == "velocity_reaver", "Persisted recaps should retain the encountered Apex identity.")
	_expect(str(profile.last_run_summary.catalyst_id) == "redline_core" and is_equal_approx(float(profile.last_run_summary.catalyst_uptime), 0.64), "Persisted balance evidence should retain catalyst choice and empowered uptime.")
	_expect((profile.last_run_summary.upgrade_events as Array).size() == 1 and str(profile.last_run_summary.upgrade_events[0].kind) == "engine", "Persisted balance evidence should retain sanitized build milestone timing.")
	_expect(is_equal_approx(float(profile.last_run_summary.damage_taken_by_source.skimmer_charge), 42.0), "Persisted balance evidence should retain incoming damage attribution.")
	_expect(is_equal_approx(float(profile.last_run_summary.integrity_recovered), 36.0) and int(profile.last_run_summary.recovery_pickups) == 3, "Persisted balance evidence should retain recovery economy usage.")
	_expect(profile.best_velocity_chain == 36 and int(profile.last_run_summary.velocity_chain_defeats) == 72, "Best Flow and linked high-speed defeats should remain visible as movement-skill evidence.")
	_expect((first_result.new_masteries as Array).size() == 3 and profile.get_mastery_count() == 3, "A victory should master its evolution, arsenal, and catalyst without granting combat power.")
	_expect(profile.get_mastery_count_for(ProgressProfileModel.EVOLUTION_MASTERY_IDS) == 1 and profile.get_mastery_count_for(ProgressProfileModel.ARSENAL_MASTERY_IDS) == 1 and profile.get_mastery_count_for(ProgressProfileModel.DRIVE_MASTERY_IDS) == 1, "Mastery progress should remain legible across evolution, arsenal, and Drive categories.")
	_expect(profile.record_latest_replay_intent("yes"), "A completed run should accept optional replay-intent feedback.")
	_expect(profile.get_recent_replay_feedback_count() == 1 and profile.get_recent_replay_yes_count() == 1, "Recent playtest sentiment should remain measurable beside run telemetry.")
	_expect(profile.record_latest_playtest_tag("movement_highlight"), "A positive replay response should accept one actionable strength tag.")
	_expect(profile.get_recent_playtest_tag_count() == 1 and profile.get_recent_playtest_tag_frequency("movement_highlight") == 1 and profile.get_top_recent_playtest_tag() == "movement_highlight", "Recent playtest tags should remain measurable beside the exact run telemetry.")
	var report := profile.get_latest_playtest_report()
	var report_run: Dictionary = report.get("run", {})
	_expect(str(report.get("format", "")) == ProgressProfileModel.PLAYTEST_REPORT_FORMAT and int(report.get("format_version", 0)) == ProgressProfileModel.PLAYTEST_REPORT_VERSION, "A copied playtest report should carry an explicit, versioned contract.")
	_expect(str(report_run.get("build_name", "")) == "DASHBREAKER • RAMJET" and str(report_run.get("apex_id", "")) == "velocity_reaver" and int(report_run.get("best_velocity_chain", 0)) == 36, "A copied playtest report should retain build, climax, and movement-skill evidence needed for review.")
	_expect(str(report_run.get("replay_intent", "")) == "yes" and str(report_run.get("playtest_tag", "")) == "movement_highlight", "A copied playtest report should pair subjective feedback with the exact run telemetry.")
	_expect(not report.has("run_history") and not report.has("momentum") and not report.has("selected_protocol"), "A copied playtest report should exclude progression, history, and unrelated profile state.")
	var parsed_report = JSON.parse_string(profile.get_latest_playtest_report_json())
	_expect(parsed_report is Dictionary and str(parsed_report.get("format", "")) == ProgressProfileModel.PLAYTEST_REPORT_FORMAT, "The copied playtest report should be valid, machine-readable JSON.")
	_expect(not profile.record_latest_playtest_tag("terrain_issue") and str(profile.last_run_summary.playtest_tag) == "movement_highlight", "A tag from the wrong sentiment branch should not corrupt the recorded response.")
	_expect(not profile.record_latest_replay_intent("invalid") and str(profile.last_run_summary.replay_intent) == "yes", "Invalid feedback should not overwrite a valid playtest response.")
	var issue_profile := ProgressProfileModel.new()
	_expect(issue_profile.get_latest_playtest_report().is_empty() and issue_profile.get_latest_playtest_report_json().is_empty(), "A profile without a completed run should not invent an exportable playtest report.")
	issue_profile.record_run(420.0, 80, false, {"build_name": "STORMTRAIL • TWIN CURRENT"})
	_expect(issue_profile.record_latest_replay_intent("maybe") and issue_profile.record_latest_playtest_tag("terrain_issue"), "Maybe and No responses should accept one actionable issue tag.")
	_expect(not issue_profile.record_latest_playtest_tag("build_highlight") and issue_profile.get_top_recent_playtest_tag() == "terrain_issue", "Issue feedback should reject an incompatible positive tag.")
	_expect("GRAVITY KNOT" in profile.get_next_mastery_goal(), "The next mastery goal should direct the player toward an unexplored build.")
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
	profile.best_velocity_chain = 42
	profile.last_run_summary = {
		"build_name": "ARCSTORM • STORM LANCE",
		"damage_dealt": 18250.0,
		"damage_taken_by_source": {"apex_rift": 33.0},
		"integrity_recovered": 54.0,
		"recovery_pickups": 4,
		"distance_meters": 71500.0,
		"best_velocity_chain": 42,
		"velocity_chain_defeats": 108,
		"upgrade_history": ["velocity_coil", "storm_lance"],
		"upgrade_events": [{"id": "velocity_coil", "elapsed_seconds": 14.5, "level": 2, "kind": "engine"}],
		"replay_intent": "yes",
		"playtest_tag": "build_highlight",
	}
	profile.selected_protocol = RunProtocolCatalog.REDLINE
	profile.reduced_motion = true
	profile.high_contrast_telegraphs = true
	profile.guidance_enabled = false
	profile.onboarding_completed = true
	profile.master_volume = 0.35
	profile.music_volume = 0.4
	profile.effects_volume = 0.65
	profile.run_history = [{"victory": true, "build_name": "ARCSTORM • STORM LANCE", "best_velocity_chain": 42, "replay_intent": "yes", "playtest_tag": "build_highlight"}]
	profile.mastered_build_ids = [&"storm_lance", &"drift_blades"]
	_expect(profile.save(_test_path), "A valid profile should save atomically.")
	var loaded := ProgressProfileModel.new()
	_expect(loaded.load(_test_path), "A saved profile should load.")
	_expect(loaded.momentum == 470 and loaded.selected_protocol == RunProtocolCatalog.REDLINE, "Profile state should survive a save/load round trip.")
	_expect(loaded.best_clear_count == 144 and loaded.best_damage == 18250.0 and loaded.best_distance_meters == 71500.0 and loaded.best_velocity_chain == 42, "Personal combat, traversal, and Flow records should survive a save/load round trip.")
	_expect(str(loaded.last_run_summary.build_name) == "ARCSTORM • STORM LANCE" and (loaded.last_run_summary.upgrade_history as Array).size() == 2, "The bounded last-run snapshot should survive a save/load round trip.")
	_expect((loaded.last_run_summary.upgrade_events as Array).size() == 1 and is_equal_approx(float(loaded.last_run_summary.upgrade_events[0].elapsed_seconds), 14.5), "Timestamped draft evidence should survive a save/load round trip.")
	_expect(is_equal_approx(float(loaded.last_run_summary.damage_taken_by_source.apex_rift), 33.0), "Incoming threat attribution should survive a save/load round trip.")
	_expect(is_equal_approx(float(loaded.last_run_summary.integrity_recovered), 54.0) and int(loaded.last_run_summary.recovery_pickups) == 4, "Recovery economy evidence should survive a save/load round trip.")
	_expect(str(loaded.last_run_summary.replay_intent) == "yes" and loaded.get_recent_replay_yes_count() == 1, "Optional replay intent should survive a save/load round trip.")
	_expect(str(loaded.last_run_summary.playtest_tag) == "build_highlight" and loaded.get_top_recent_playtest_tag() == "build_highlight", "Actionable playtest tags should survive a save/load round trip.")
	_expect(loaded.reduced_motion and loaded.high_contrast_telegraphs, "Visual accessibility preferences should survive a save/load round trip.")
	_expect(not loaded.guidance_enabled and loaded.onboarding_completed, "Guidance preferences should survive a save/load round trip.")
	_expect(is_equal_approx(loaded.master_volume, 0.35) and is_equal_approx(loaded.music_volume, 0.4) and is_equal_approx(loaded.effects_volume, 0.65), "All three audio mix preferences should survive a save/load round trip.")
	_expect(loaded.run_history.size() == 1 and loaded.get_mastery_count() == 2, "Bounded run history and non-power mastery should survive a save/load round trip.")

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
	_expect(is_equal_approx(migrated.master_volume, 0.8) and is_equal_approx(migrated.music_volume, 0.55) and is_equal_approx(migrated.effects_volume, 1.0), "Older profiles should receive balanced default audio levels.")
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
	_expect(is_equal_approx(migrated.master_volume, 0.8) and is_equal_approx(migrated.music_volume, 0.55) and is_equal_approx(migrated.effects_volume, 1.0), "Schema-two profiles should receive balanced default audio levels.")
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


func _test_schema_four_history_migration() -> void:
	var legacy_path := _test_path + ".legacy4"
	var legacy_file := FileAccess.open(ProjectSettings.globalize_path(legacy_path), FileAccess.WRITE)
	legacy_file.store_string(JSON.stringify({
		"schema_version": 4,
		"momentum": 800,
		"completed_runs": 8,
		"victories": 4,
		"selected_protocol": "elite_hunt",
	}))
	legacy_file.close()
	var migrated := ProgressProfileModel.new()
	_expect(migrated.load(legacy_path), "A schema-four profile should migrate when run history and mastery are introduced.")
	_expect(migrated.run_history.is_empty() and migrated.get_mastery_count() == 0, "Older profiles should receive safe empty mastery evidence without inventing clears.")
	for suffix in ["", ".tmp", ".bak"]:
		var target: String = ProjectSettings.globalize_path(legacy_path) + suffix
		if FileAccess.file_exists(target):
			DirAccess.remove_absolute(target)


func _test_schema_five_cadence_migration() -> void:
	var legacy_path := _test_path + ".legacy5"
	var legacy_file := FileAccess.open(ProjectSettings.globalize_path(legacy_path), FileAccess.WRITE)
	legacy_file.store_string(JSON.stringify({
		"schema_version": 5,
		"momentum": 900,
		"completed_runs": 10,
		"victories": 5,
		"last_run_summary": {"build_name": "STORMTRAIL • TWIN CURRENT"},
	}))
	legacy_file.close()
	var migrated := ProgressProfileModel.new()
	_expect(migrated.load(legacy_path), "A schema-five profile should migrate when cadence telemetry is introduced.")
	_expect((migrated.last_run_summary.upgrade_events as Array).is_empty(), "Older profiles should receive safe empty cadence evidence without inventing milestone times.")
	for suffix in ["", ".tmp", ".bak"]:
		var target: String = ProjectSettings.globalize_path(legacy_path) + suffix
		if FileAccess.file_exists(target):
			DirAccess.remove_absolute(target)


func _test_schema_six_feedback_migration() -> void:
	var legacy_path := _test_path + ".legacy6"
	var legacy_file := FileAccess.open(ProjectSettings.globalize_path(legacy_path), FileAccess.WRITE)
	legacy_file.store_string(JSON.stringify({
		"schema_version": 6,
		"momentum": 1000,
		"completed_runs": 12,
		"victories": 6,
		"last_run_summary": {"build_name": "ARCSTORM • ARC ORBIT"},
		"run_history": [{"victory": true, "build_name": "ARCSTORM • ARC ORBIT"}],
	}))
	legacy_file.close()
	var migrated := ProgressProfileModel.new()
	_expect(migrated.load(legacy_path), "A schema-six profile should migrate when optional replay feedback is introduced.")
	_expect(str(migrated.last_run_summary.replay_intent).is_empty() and migrated.get_recent_replay_feedback_count() == 0, "Older profiles should not invent subjective playtest responses.")
	for suffix in ["", ".tmp", ".bak"]:
		var target: String = ProjectSettings.globalize_path(legacy_path) + suffix
		if FileAccess.file_exists(target):
			DirAccess.remove_absolute(target)


func _test_schema_seven_incoming_damage_migration() -> void:
	var legacy_path := _test_path + ".legacy7"
	var legacy_file := FileAccess.open(ProjectSettings.globalize_path(legacy_path), FileAccess.WRITE)
	legacy_file.store_string(JSON.stringify({
		"schema_version": 7,
		"momentum": 1250,
		"completed_runs": 14,
		"victories": 7,
		"last_run_summary": {"build_name": "STORMTRAIL • TEMPEST ANCHOR", "damage_taken": 88.0},
		"run_history": [{"victory": false, "build_name": "STORMTRAIL • TEMPEST ANCHOR"}],
	}))
	legacy_file.close()
	var migrated := ProgressProfileModel.new()
	_expect(migrated.load(legacy_path), "A schema-seven profile should migrate when incoming threat attribution is introduced.")
	_expect((migrated.last_run_summary.damage_taken_by_source as Dictionary).is_empty(), "Older profiles should preserve total damage taken without inventing attack sources.")
	for suffix in ["", ".tmp", ".bak"]:
		var target: String = ProjectSettings.globalize_path(legacy_path) + suffix
		if FileAccess.file_exists(target):
			DirAccess.remove_absolute(target)


func _test_schema_eight_recovery_migration() -> void:
	var legacy_path := _test_path + ".legacy8"
	var legacy_file := FileAccess.open(ProjectSettings.globalize_path(legacy_path), FileAccess.WRITE)
	legacy_file.store_string(JSON.stringify({
		"schema_version": 8,
		"momentum": 1450,
		"completed_runs": 16,
		"victories": 8,
		"last_run_summary": {"build_name": "DASHBREAKER • RAMJET", "damage_taken": 62.0},
		"run_history": [{"victory": true, "build_name": "DASHBREAKER • RAMJET"}],
	}))
	legacy_file.close()
	var migrated := ProgressProfileModel.new()
	_expect(migrated.load(legacy_path), "A schema-eight profile should migrate when integrity recovery telemetry is introduced.")
	_expect(is_zero_approx(float(migrated.last_run_summary.integrity_recovered)) and int(migrated.last_run_summary.recovery_pickups) == 0, "Older profiles should preserve run history without inventing recovery use.")
	for suffix in ["", ".tmp", ".bak"]:
		var target: String = ProjectSettings.globalize_path(legacy_path) + suffix
		if FileAccess.file_exists(target):
			DirAccess.remove_absolute(target)


func _test_schema_nine_effects_migration() -> void:
	var legacy_path := _test_path + ".legacy9"
	var legacy_file := FileAccess.open(ProjectSettings.globalize_path(legacy_path), FileAccess.WRITE)
	legacy_file.store_string(JSON.stringify({
		"schema_version": 9,
		"momentum": 1650,
		"completed_runs": 18,
		"victories": 9,
		"master_volume": 0.6,
		"music_volume": 0.35,
	}))
	legacy_file.close()
	var migrated := ProgressProfileModel.new()
	_expect(migrated.load(legacy_path), "A schema-nine profile should migrate when independent effects volume is introduced.")
	_expect(is_equal_approx(migrated.master_volume, 0.6) and is_equal_approx(migrated.music_volume, 0.35), "Effects migration should preserve the existing audio mix.")
	_expect(is_equal_approx(migrated.effects_volume, 1.0), "Existing players should retain the prior full-strength effects mix by default.")
	for suffix in ["", ".tmp", ".bak"]:
		var target: String = ProjectSettings.globalize_path(legacy_path) + suffix
		if FileAccess.file_exists(target):
			DirAccess.remove_absolute(target)


func _test_schema_ten_playtest_tag_migration() -> void:
	var legacy_path := _test_path + ".legacy10"
	var legacy_file := FileAccess.open(ProjectSettings.globalize_path(legacy_path), FileAccess.WRITE)
	legacy_file.store_string(JSON.stringify({
		"schema_version": 10,
		"momentum": 1850,
		"completed_runs": 20,
		"victories": 10,
		"last_run_summary": {"build_name": "ARCSTORM • STORM LANCE", "replay_intent": "yes"},
		"run_history": [{"victory": true, "build_name": "ARCSTORM • STORM LANCE", "replay_intent": "yes"}],
	}))
	legacy_file.close()
	var migrated := ProgressProfileModel.new()
	_expect(migrated.load(legacy_path), "A schema-ten profile should migrate when actionable playtest tags are introduced.")
	_expect(str(migrated.last_run_summary.playtest_tag).is_empty() and migrated.get_recent_playtest_tag_count() == 0, "Existing replay responses should migrate without inventing a reason tag.")
	for suffix in ["", ".tmp", ".bak"]:
		var target: String = ProjectSettings.globalize_path(legacy_path) + suffix
		if FileAccess.file_exists(target):
			DirAccess.remove_absolute(target)


func _test_schema_eleven_flow_migration() -> void:
	var legacy_path := _test_path + ".legacy11"
	var legacy_file := FileAccess.open(ProjectSettings.globalize_path(legacy_path), FileAccess.WRITE)
	legacy_file.store_string(JSON.stringify({
		"schema_version": 11,
		"momentum": 2050,
		"completed_runs": 22,
		"victories": 11,
		"last_run_summary": {"build_name": "DASHBREAKER • GRAVITY KNOT"},
		"run_history": [{"victory": true, "build_name": "DASHBREAKER • GRAVITY KNOT"}],
	}))
	legacy_file.close()
	var migrated := ProgressProfileModel.new()
	_expect(migrated.load(legacy_path), "A schema-eleven profile should migrate when movement-skill records are introduced.")
	_expect(migrated.best_velocity_chain == 0 and int(migrated.last_run_summary.best_velocity_chain) == 0, "Existing histories should not invent Flow performance that was never measured.")
	for suffix in ["", ".tmp", ".bak"]:
		var target: String = ProjectSettings.globalize_path(legacy_path) + suffix
		if FileAccess.file_exists(target):
			DirAccess.remove_absolute(target)


func _test_bounded_history_and_mastery() -> void:
	var profile := ProgressProfileModel.new()
	for index in range(ProgressProfileModel.RUN_HISTORY_LIMIT + 5):
		profile.record_run(60.0 + index, index, index % 4 == 0, {
			"evolution_id": "ramjet",
			"arsenal_id": "hunter_array",
			"catalyst_id": "pulse_core",
			"build_name": "DASHBREAKER • RAMJET",
		})
	_expect(profile.run_history.size() == ProgressProfileModel.RUN_HISTORY_LIMIT, "Run history should retain a useful balance window without growing save files forever.")
	_expect(profile.get_recent_run_count() == 5 and profile.get_recent_win_count() == 2, "Recent form should use the latest five sanitized outcomes.")
	_expect(profile.get_mastery_count() == 3, "Repeated clears with one loadout should not inflate mastery progress.")


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
