extends SceneTree

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var scene: Node = load("res://main.tscn").instantiate()
	scene.set_meta("overrush_manual_start", true)
	scene.set_meta("overrush_disable_persistence", true)
	scene.get_node("World").seed = 199381
	root.add_child(scene)
	await process_frame
	scene.begin_run()
	await process_frame

	var director: CombatDirector = scene.combat
	var runner: CharacterBody3D = scene.ball
	var audio: OverrushAudioDirector = scene.audio
	_expect(not scene.velocity_panel.visible and director.velocity_chain.best_count == 0, "Flow should stay absent until the player earns movement-skill evidence.")

	runner.velocity = Vector3.FORWARD * 40.0
	_defeat_rewarding_enemy(director)
	_expect(director.velocity_chain.current_count == 0 and director.run_stats.best_velocity_chain == 0, "A defeat below qualifying traversal speed should not start or record Flow.")
	runner.velocity = Vector3.FORWARD * 72.0
	var empty_reward: EnemyAgent = director._spawn_enemy(&"pursuer")
	empty_reward.experience_value = 0
	empty_reward.take_damage(empty_reward.health + 1.0)
	_expect(director.velocity_chain.current_count == 0, "Zero-reward summons should never inflate Flow or its Momentum reward.")

	var tier_cues_before := audio._velocity_tier_sequence
	for _index in range(3):
		_defeat_rewarding_enemy(director)
	_expect(director.velocity_chain.current_count == 3 and director.velocity_chain.get_tier_name() == "LOCKED", "Three close high-speed defeats should establish the first earned Flow tier.")
	_expect(audio._velocity_tier_sequence == tier_cues_before + 1, "Crossing LOCKED should trigger one rising audio cue instead of one cue per defeat.")
	scene._refresh_velocity_chain_hud()
	_expect(scene.velocity_panel.visible and "FLOW ×03  •  LOCKED" in scene.velocity_label.text, "The live HUD should expose current Flow and its named tier without opening a menu.")
	_expect(scene.velocity_timer.value > 0.0 and scene.velocity_timer.value <= scene.velocity_timer.max_value, "A compact timer should communicate the remaining chain window.")
	var velocity_rect: Rect2 = scene.velocity_panel.get_global_rect()
	var integrity_rect: Rect2 = scene.integrity_bar.get_global_rect()
	_expect(not velocity_rect.intersects(integrity_rect), "The Flow card should not cover the critical integrity HUD at 720p (Flow %s, integrity %s)." % [str(velocity_rect), str(integrity_rect)])

	director.velocity_chain.update(2.1, 72.0)
	var timer_before_dash: float = director.velocity_chain.timer
	director._on_dash_state_changed(true)
	_expect(director.velocity_chain.timer > timer_before_dash and director.velocity_chain.current_count == 3, "A dash should extend the active decision window without granting a free chain count.")
	director.velocity_chain.update(2.0, 20.0)
	scene._refresh_velocity_chain_hud()
	_expect(director.velocity_chain.current_count == 0 and "FLOW LOST" in scene.velocity_label.text and "BEST ×03" in scene.velocity_label.text, "Slow play should break Flow while leaving the earned personal target readable.")

	var elite: EnemyAgent = director._spawn_enemy(&"rift_weaver", &"elite")
	runner.velocity = Vector3.FORWARD * 72.0
	elite.take_damage(elite.health + 1.0)
	_expect(director.velocity_chain.current_count == 3 and director.run_stats.best_velocity_chain == 3, "A high-speed elite should carry triple weight but obey the same bounded chain rules.")
	_expect(director.run_stats.velocity_chain_defeats == 4, "Telemetry should count qualifying enemies rather than inflated elite weight.")
	var snapshot := director.run_stats.snapshot(director.elapsed_time, director.enemies_defeated, director.build)
	_expect(int(snapshot.best_velocity_chain) == 3 and int(snapshot.velocity_chain_defeats) == 4, "The production run snapshot should preserve Flow evidence for recaps and playtests.")

	director.stop_run()
	paused = false
	scene.queue_free()
	await process_frame
	if _failures.is_empty():
		print("Velocity chain runtime validation passed — rewarding speed, dash grace, HUD, audio, elite weight, and telemetry agree.")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _defeat_rewarding_enemy(director: CombatDirector) -> void:
	var enemy: EnemyAgent = director._spawn_enemy(&"pursuer")
	enemy.take_damage(enemy.health + 1.0)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
