extends SceneTree

const ProgressProfileModel = preload("res://scripts/progress_profile.gd")
const RunProtocolCatalog = preload("res://scripts/run_protocols.gd")
const InputBindings = preload("res://scripts/input_bindings.gd")
const TEST_PROFILE_PATH := "user://overrush_archive_validation.json"

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_cleanup_test_profile()
	var scene: Node = load("res://main.tscn").instantiate()
	scene.set_meta("overrush_manual_start", true)
	scene.set_meta("overrush_disable_persistence", true)
	scene.get_node("World").seed = 73124
	root.add_child(scene)
	await process_frame

	_validate_empty_archive(scene)
	_populate_archive(scene._profile)
	scene._refresh_launch_screen()
	_validate_populated_archive(scene)
	_validate_restored_archive(scene)

	paused = false
	scene.queue_free()
	await process_frame
	_cleanup_test_profile()
	if _failures.is_empty():
		print("Run archive validation passed — empty, comparative, paged, restored, and controller-safe history states are active.")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _validate_empty_archive(scene: Node) -> void:
	_expect(scene.profile_summary is Button and "RUN ARCHIVE  •  OPEN" in scene.profile_summary.text, "Run history should be a clear launch-screen action rather than hidden profile data.")
	scene.profile_summary.pressed.emit()
	_expect(scene.archive_overlay.visible and scene.get_viewport().gui_get_focus_owner() == scene.archive_back_button, "Opening an empty archive should keep Back as the safe controller default.")
	_expect(scene.archive_empty.visible and "Launch your first run" in scene.archive_empty.text, "A new profile should receive a useful empty-state invitation.")
	_expect(scene.archive_newer_button.disabled and scene.archive_older_button.disabled, "An empty archive should not expose invalid page navigation.")
	var archive_panel: Control = scene.get_node("HUD/ArchiveOverlay/ArchivePanel")
	var archive_content: Control = scene.get_node("HUD/ArchiveOverlay/ArchivePanel/Content")
	_expect(archive_content.get_global_rect().end.y <= archive_panel.get_global_rect().end.y - 24.0, "The archive should fit inside its 720p panel without clipping.")
	var protocol_index_before: int = scene._protocol_index
	var menu_right := InputEventAction.new()
	menu_right.action = InputBindings.MENU_RIGHT
	menu_right.pressed = true
	scene._input(menu_right)
	_expect(scene._protocol_index == protocol_index_before, "Archive navigation should not cycle the hidden run protocol.")
	scene.begin_run()
	_expect(not scene._run_started and scene.start_overlay.visible, "Confirm input should never launch a run behind the archive.")
	scene.archive_back_button.pressed.emit()
	_expect(not scene.archive_overlay.visible and scene.get_viewport().gui_get_focus_owner() == scene.profile_summary, "Closing the archive should return focus to its launch-screen entry point.")


func _populate_archive(profile: ProgressProfile) -> void:
	profile.momentum = 1000
	var evolutions: Array[String] = ["ramjet", "gravity_knot", "twin_current", "tempest_anchor", "storm_lance", "arc_orbit", "ramjet"]
	var builds: Array[String] = ["DASHBREAKER / RAMJET", "DASHBREAKER / GRAVITY KNOT", "STORMTRAIL / TWIN CURRENT", "STORMTRAIL / TEMPEST ANCHOR", "ARCSTORM / STORM LANCE", "ARCSTORM / ARC ORBIT", "DASHBREAKER / RAMJET"]
	var arsenals: Array[String] = ["hunter_array", "drift_blades", "backdraft_mine", "hunter_array", "drift_blades", "backdraft_mine", "hunter_array"]
	var drives: Array[String] = ["redline_core", "airframe_core", "pulse_core", "airframe_core", "pulse_core", "redline_core", "redline_core"]
	var protocols: Array[StringName] = [RunProtocolCatalog.STANDARD, RunProtocolCatalog.REDLINE, RunProtocolCatalog.GLASS_VELOCITY, RunProtocolCatalog.ELITE_HUNT, RunProtocolCatalog.STANDARD, RunProtocolCatalog.REDLINE, RunProtocolCatalog.ELITE_HUNT]
	for index in range(7):
		profile.select_protocol(protocols[index])
		var victory := index % 3 == 0
		profile.record_run(780.0 + index * 70.0, 180 + index * 31, victory, {
			"elite_defeats": index + 1,
			"phase_reached": "apex" if index >= 4 else "overrun",
			"build_name": builds[index],
			"evolution_id": evolutions[index],
			"arsenal_id": arsenals[index],
			"catalyst_id": drives[index],
			"level": 12 + index,
			"replay_intent": "yes" if victory else "maybe",
			"playtest_tag": "build_highlight" if victory else "difficulty_issue",
		})


func _validate_populated_archive(scene: Node) -> void:
	scene.profile_summary.pressed.emit()
	_expect(not scene.archive_empty.visible and scene.archive_rows[0].visible and scene.archive_rows[4].visible, "A populated archive should replace the empty state with five recent run cards.")
	_expect("7 RECORDED RUNS" in scene.archive_summary.text and "3 VICTORIES" in scene.archive_summary.text and "43% CLEAR RATE" in scene.archive_summary.text, "The archive header should summarize the complete recorded sample honestly.")
	_expect("RUN 07" in scene.archive_rows[0].text and "VICTORY" in scene.archive_rows[0].text and "ELITE HUNT" in scene.archive_rows[0].text, "The newest card should identify its outcome, true run number, and protocol.")
	_expect("DASHBREAKER / RAMJET" in scene.archive_rows[0].text and "HUNTER ARRAY" in scene.archive_rows[0].text and "REDLINE CORE" in scene.archive_rows[0].text, "Each card should expose the mature build components needed for comparison.")
	_expect("REPLAY YES" in scene.archive_rows[0].text and "NOTE BUILD" in scene.archive_rows[0].text, "A player's optional replay verdict and note should stay attached to the matching run.")
	_expect("RUNS 1–5 OF 7" in scene.archive_page_label.text and scene.archive_newer_button.disabled and not scene.archive_older_button.disabled, "The first page should expose its range and only offer valid older navigation.")
	scene.archive_older_button.pressed.emit()
	_expect("RUNS 6–7 OF 7" in scene.archive_page_label.text and scene.archive_rows[1].visible and not scene.archive_rows[2].visible, "The final page should show only the two remaining older runs.")
	_expect(not scene.archive_newer_button.disabled and scene.archive_older_button.disabled and scene.get_viewport().gui_get_focus_owner() == scene.archive_newer_button, "Reaching the oldest page should move focus away from the newly disabled action.")
	_expect("RUN 02" in scene.archive_rows[0].text and "RUN 01" in scene.archive_rows[1].text, "Older pagination should preserve reverse-chronological run numbering.")
	scene.archive_back_button.pressed.emit()


func _validate_restored_archive(scene: Node) -> void:
	_expect(scene._profile.save(TEST_PROFILE_PATH), "The populated archive fixture should save through the production profile path.")
	var restored: ProgressProfile = ProgressProfileModel.new()
	_expect(restored.load(TEST_PROFILE_PATH), "A saved run archive should restore through the production recovery-safe loader.")
	_expect(restored.run_history.size() == 7 and restored.completed_runs == 7, "Restored history should preserve the visible run count and cards.")
	scene._profile = restored
	scene._refresh_launch_screen()
	scene.profile_summary.pressed.emit()
	_expect("RUN 07" in scene.archive_rows[0].text and "NOTE BUILD" in scene.archive_rows[0].text, "The launch archive should render restored outcomes and attached notes exactly as live history.")
	_expect(scene._archive_page == 0 and "RUNS 1–5 OF 7" in scene.archive_page_label.text, "Reopening restored history should always begin with the most recent runs.")
	scene.archive_back_button.pressed.emit()


func _cleanup_test_profile() -> void:
	var absolute_path := ProjectSettings.globalize_path(TEST_PROFILE_PATH)
	for suffix in ["", ".bak", ".tmp"]:
		var candidate: String = absolute_path + str(suffix)
		if FileAccess.file_exists(candidate):
			DirAccess.remove_absolute(candidate)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
