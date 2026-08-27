extends SceneTree

const RunBuildScript = preload("res://scripts/run_build.gd")

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene: Node = load("res://main.tscn").instantiate()
	scene.set_meta("overrush_disable_persistence", true)
	scene.get_node("World").seed = 151867
	root.add_child(scene)
	await process_frame
	await process_frame
	var director: CombatDirector = scene.get_node("CombatDirector")
	director.stop_run()
	for enemy in director._enemies:
		if is_instance_valid(enemy):
			enemy.queue_free()
	director._enemies.clear()
	await process_frame
	director.run_stats.reset(Vector3.ZERO)

	var build: RunBuild = RunBuildScript.new()
	for _rank in range(RunBuild.EVOLUTION_UNLOCK_RANK):
		build.apply_upgrade(&"dash_nova")
		director.run_stats.record_upgrade(&"dash_nova", 12.0 if _rank == 0 else 40.0 + _rank * 25.0, _rank + 2, &"engine" if _rank == 0 else &"standard")
	build.apply_upgrade(&"ramjet")
	director.run_stats.record_upgrade(&"ramjet", 180.0, 6, &"evolution")
	build.catalyst_id = RunBuild.REDLINE_CORE
	director.run_stats.record_upgrade(RunBuild.REDLINE_CORE, 600.0, 9, &"catalyst")
	build.arsenal_id = RunBuild.HUNTER_ARRAY
	director.run_stats.record_upgrade(RunBuild.HUNTER_ARRAY, 315.0, 8, &"arsenal")
	build.level = 9
	director.build = build
	director.elapsed_time = 743.2
	director.enemies_defeated = 88
	director.run_stats.set_phase(&"overrun")
	director.run_stats.record_damage(&"dash_nova", 7200.0)
	director.run_stats.record_damage(&"ramjet", 2800.0)
	director.run_stats.record_damage(&"dash_echo", 1000.0)
	director.run_stats.record_damage_taken(47.0, &"skimmer_charge")
	director.run_stats.record_damage_taken(20.0, &"pursuer_contact")
	director.run_stats.record_integrity_recovery(12.0)
	director.run_stats.record_integrity_recovery(12.0)
	for index in range(180):
		director.run_stats.record_traversal(Vector3(0.0, 0.0, float(index + 1) * 200.0), 126.0 if index == 40 else 72.0)
	for _dash in range(74):
		director.run_stats.record_dash()
	director.run_stats.record_reroll()
	director.run_stats.record_reroll()
	director.run_stats.record_banish()
	director.run_stats.set_apex_identity(&"velocity_reaver")
	director.run_stats.record_catalyst_state(64.0, true)
	director.run_stats.record_catalyst_state(36.0, false)
	for _elite in range(4):
		director.run_stats.record_defeat(&"rift_weaver", true)

	var measured_target: EnemyAgent = director._spawn_enemy(&"pursuer")
	measured_target.health = 10.0
	var damage_before := director.run_stats.get_total_damage()
	measured_target.take_damage(50.0, &"dash_nova")
	await process_frame
	_expect(is_equal_approx(director.run_stats.get_total_damage() - damage_before, 10.0), "Run telemetry should record applied health loss instead of inflating overkill damage.")
	director.enemies_defeated = 88

	scene._on_run_failed("THE STORM CLOSED IN")
	await process_frame
	var overlay: Control = scene.get_node("HUD/GameOverOverlay")
	var message: Label = scene.get_node("HUD/GameOverOverlay/Message")
	var retry: Button = scene.get_node("HUD/GameOverOverlay/Retry")
	var feedback_prompt: Label = scene.get_node("HUD/GameOverOverlay/FeedbackPrompt")
	var feedback_yes: Button = scene.get_node("HUD/GameOverOverlay/FeedbackChoices/Yes")
	_expect(overlay.visible and paused, "A completed run should pause behind a dedicated recap overlay.")
	_expect(retry.visible and retry.text == "RUN AGAIN  •  R", "The recap should expose a focused, device-aware retry action.")
	_expect(scene.get_viewport().gui_get_focus_owner() == retry, "Retry should own focus when an outcome appears.")
	_expect(scene.has_node("HUD/GameOverOverlay/RecapPanel"), "The recap should use a framed panel rather than floating outcome text.")
	_expect("DASHBREAKER • RAMJET" in message.text and "LEVEL 9" in message.text, "The recap should identify the demonstrated build and maturity.")
	_expect("7 UPGRADES" in message.text and "2 REROLLS" in message.text and "1 BANISH" in message.text, "The recap should distinguish deliberate draft shaping from favorable rolls.")
	_expect("ENGINE 00:12" in message.text and "EVOLUTION 03:00" in message.text and "DRIVE 10:00" in message.text, "The recap should expose when the run's strategic identity came online.")
	_expect("ARSENAL  •  HUNTER ARRAY" in message.text, "The recap should preserve the independent weapon choice for replay and balance review.")
	_expect("REDLINE CORE" in message.text and "64% HOT" in message.text, "The recap should identify the movement catalyst and measured empowered uptime.")
	_expect("VELOCITY REAVER" in message.text and "BROKEN" in message.text, "The recap should identify the climax encounter and its outcome.")
	_expect("12:23" in message.text and "88 CLEARED" in message.text and "4 ELITES" in message.text, "The recap should summarize encounter progress at a glance.")
	_expect("DASH NOVA" in message.text and "RAMJET" in message.text, "The recap should expose leading damage contributions for balance review.")
	_expect("TOP THREATS" in message.text and "SKIMMER CHARGE 70%" in message.text, "The recap should teach the player and playtester which attack caused most incoming damage.")
	_expect("24 REPAIRED / 2 CORES" in message.text, "The recap should expose how much bounded recovery influenced survivability.")
	_expect("36.0 KM TRAVERSED" in message.text and "126 M/S PEAK" in message.text and "74 DASHES" in message.text, "The recap should preserve Overrush's traversal identity.")
	_expect("NEW BEST" in message.text and "+" in message.text and "MOMENTUM" in message.text, "The first measured run should connect records and progression to the retry prompt.")
	_expect(str(scene._profile.last_run_summary.build_name) == "DASHBREAKER • RAMJET", "The same bounded recap evidence should persist through the profile model.")
	_expect(is_equal_approx(float(scene._profile.last_run_summary.damage_taken_by_source.skimmer_charge), 47.0), "Incoming threat attribution should persist with the bounded run history.")
	_expect(is_equal_approx(float(scene._profile.last_run_summary.integrity_recovered), 24.0) and int(scene._profile.last_run_summary.recovery_pickups) == 2, "Recovery evidence should persist with the bounded run history.")
	_expect(feedback_prompt.text == "PLAYTEST  •  WOULD YOU RUN AGAIN?" and not feedback_yes.disabled, "Outcome feedback should remain optional and available without blocking retry.")
	feedback_yes.pressed.emit()
	_expect(str(scene._profile.last_run_summary.replay_intent) == "yes" and str(scene._profile.run_history[0].replay_intent) == "yes", "A replay response should attach to the exact measured run.")
	_expect("THANK YOU" in feedback_prompt.text and feedback_yes.disabled and feedback_yes.text.begins_with("✓"), "Submitted feedback should acknowledge the response with text as well as state.")
	scene._refresh_launch_screen()
	_expect("REPLAY YES 1 / 1" in scene.mastery_summary.text, "The launch summary should expose recent replay intent for playtest review.")
	_expect(scene.get_viewport().gui_get_focus_owner() == retry, "Optional feedback should not steal the default one-more-run focus.")

	paused = false
	scene.queue_free()
	await process_frame
	if _failures.is_empty():
		print("Run recap validation passed — applied damage, build evidence, personal records, and outcome UI agree.")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
