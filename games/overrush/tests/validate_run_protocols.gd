extends SceneTree

const RunProtocolCatalog = preload("res://scripts/run_protocols.gd")
const ProgressProfileModel = preload("res://scripts/progress_profile.gd")

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_validate_catalog_tradeoffs()
	await _validate_launch_and_glass_velocity()
	if _failures.is_empty():
		print("Run protocol validation passed — launch gating, unlock order, and gameplay tradeoffs are active.")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _validate_catalog_tradeoffs() -> void:
	_expect(RunProtocolCatalog.get_unlocked(0) == [RunProtocolCatalog.STANDARD], "A new profile should start with only the baseline protocol.")
	_expect(RunProtocolCatalog.REDLINE in RunProtocolCatalog.get_unlocked(120), "Redline should unlock at its displayed Momentum threshold.")
	_expect(RunProtocolCatalog.GLASS_VELOCITY in RunProtocolCatalog.get_unlocked(300), "Glass Velocity should unlock at its displayed Momentum threshold.")
	_expect(RunProtocolCatalog.ELITE_HUNT in RunProtocolCatalog.get_unlocked(550), "Elite Hunt should unlock at its displayed Momentum threshold.")

	var redline := RunProtocolCatalog.get_definition(RunProtocolCatalog.REDLINE)
	var glass_velocity := RunProtocolCatalog.get_definition(RunProtocolCatalog.GLASS_VELOCITY)
	var elite_hunt := RunProtocolCatalog.get_definition(RunProtocolCatalog.ELITE_HUNT)
	_expect(float(redline.spawn_interval_multiplier) < 1.0 and float(redline.reward_multiplier) > 1.0, "Redline should exchange denser spawns for better rewards.")
	_expect(float(glass_velocity.outgoing_damage_multiplier) > 1.0 and float(glass_velocity.integrity_multiplier) < 1.0, "Glass Velocity should be a power-and-risk tradeoff rather than a universal upgrade.")
	_expect(float(elite_hunt.enemy_health_multiplier) > 1.0 and float(elite_hunt.extra_elite_interval) > 0.0, "Elite Hunt should add durable threats and scheduled elite pressure.")


func _validate_launch_and_glass_velocity() -> void:
	var scene: Node = load("res://main.tscn").instantiate()
	scene.set_meta("overrush_manual_start", true)
	scene.get_node("World").seed = 72114
	root.add_child(scene)
	await process_frame

	var overlay: Control = scene.get_node("HUD/StartOverlay")
	var director: CombatDirector = scene.get_node("CombatDirector")
	var runner: CharacterBody3D = scene.get_node("RunnerBall")
	_expect(paused, "The world should wait at the launch screen before a run begins.")
	_expect(overlay.visible, "The launch screen should be visible before a run begins.")
	_expect(not director._run_active, "Combat should remain inactive behind the launch screen.")
	_expect("BUILD MASTERY  •  0 / 12" in scene.mastery_summary.text, "A new profile should expose finite non-power mastery goals without claiming progress.")
	scene.mastery_summary.pressed.emit()
	_expect(scene.mastery_overlay.visible and scene.get_viewport().gui_get_focus_owner() == scene.mastery_back_button, "The launch screen should open a controller-safe mastery record without starting a run.")
	_expect("0 / 6" in scene.mastery_evolutions.text and "○  RAMJET" in scene.mastery_evolutions.text, "A new profile should see every unmastered evolution instead of only one recommendation.")
	_expect("0 / 3" in scene.mastery_arsenals.text and "0 / 3" in scene.mastery_drives.text, "The mastery record should expose the independent arsenal and Drive experimentation spaces.")
	_expect("no combat power" in scene.get_node("HUD/MasteryOverlay/MasteryPanel/Content/Introduction").text.to_lower(), "The mastery record should explicitly preserve skill and draft decisions over permanent power.")
	var mastery_panel: Control = scene.get_node("HUD/MasteryOverlay/MasteryPanel")
	var mastery_content: Control = scene.get_node("HUD/MasteryOverlay/MasteryPanel/Content")
	_expect(mastery_content.get_global_rect().end.y <= mastery_panel.get_global_rect().end.y - 32.0, "The complete mastery record should fit inside its 720p panel without clipping.")
	scene.mastery_back_button.pressed.emit()
	_expect(not scene.mastery_overlay.visible and scene.get_viewport().gui_get_focus_owner() == scene.mastery_summary, "Closing mastery should return focus to the launch record button.")

	scene._profile.momentum = 1000
	scene._profile.record_run(1200.0, 100, true, {
		"evolution_id": "ramjet",
		"arsenal_id": "hunter_array",
		"catalyst_id": "redline_core",
	})
	scene._available_protocols = scene._profile.get_unlocked_protocols()
	scene._protocol_index = scene._available_protocols.find(RunProtocolCatalog.GLASS_VELOCITY)
	scene._refresh_launch_screen()
	_expect("3 / 12" in scene.mastery_summary.text and "1 / 1 WINS" in scene.mastery_summary.text, "Launch should summarize durable mastery and recent playtest outcomes.")
	_expect("GRAVITY KNOT" in scene.mastery_summary.text, "Launch should recommend an unmastered build instead of permanent power.")
	scene.mastery_summary.pressed.emit()
	_expect("1 / 6" in scene.mastery_evolutions.text and "✓  RAMJET" in scene.mastery_evolutions.text, "A mastered evolution should become visibly complete in the record.")
	_expect("1 / 3" in scene.mastery_arsenals.text and "✓  HUNTER ARRAY" in scene.mastery_arsenals.text, "A mastered arsenal should become visibly complete in its category.")
	_expect("1 / 3" in scene.mastery_drives.text and "✓  REDLINE CORE" in scene.mastery_drives.text, "A mastered Drive should become visibly complete in its category.")
	scene.mastery_back_button.pressed.emit()
	var complete_masteries: Array[StringName] = ProgressProfileModel.MASTERY_IDS.duplicate()
	scene._profile.mastered_build_ids = complete_masteries
	scene._refresh_launch_screen()
	scene.mastery_summary.pressed.emit()
	_expect("12 / 12 MASTERED" in scene.mastery_progress.text and "6 / 6" in scene.mastery_evolutions.text, "A complete record should resolve every category instead of continuing to suggest unfinished work.")
	_expect("ALL BUILD MASTERIES COMPLETE" in scene.mastery_next_goal.text, "Completing all mastery targets should receive an explicit terminal acknowledgment.")
	scene.mastery_back_button.pressed.emit()
	scene.get_node("HUD/StartOverlay/LaunchPanel/Content/Launch").pressed.emit()
	await process_frame

	_expect(not paused and not overlay.visible, "Launching should dismiss the menu and resume the world.")
	_expect(director.selected_protocol == RunProtocolCatalog.GLASS_VELOCITY, "The selected protocol should reach the combat director.")
	_expect(is_equal_approx(runner.maximum_integrity, 65.0), "Glass Velocity should apply its 35% maximum-integrity reduction.")
	_expect(is_equal_approx(director._outgoing_damage_multiplier, 1.4), "Glass Velocity should apply its outgoing-damage modifier.")

	director.stop_run()
	paused = false
	scene.queue_free()
	await process_frame


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
