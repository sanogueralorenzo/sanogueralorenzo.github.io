extends SceneTree

var _failures: Array[String] = []
var _telegraph_seen := false
var _victory_seen := false
var _failure_seen := false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await _validate_elite_telegraph_and_victory()
	await _validate_deadline_failure()
	await _validate_post_defeat_atomicity()
	if _failures.is_empty():
		print("Run climax validation passed — elite telegraph, Apex health, victory, and deadline failure.")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _validate_elite_telegraph_and_victory() -> void:
	var scene: Node = load("res://main.tscn").instantiate()
	scene.get_node("World").seed = 41001
	root.add_child(scene)
	await process_frame
	var director: CombatDirector = scene.get_node("CombatDirector")
	var runner: CharacterBody3D = scene.get_node("RunnerBall")
	var world: Node3D = scene.get_node("World")
	director.stop_run()

	var elite: EnemyAgent = director._spawn_enemy(&"skimmer", &"elite")
	elite.global_position = runner.global_position + Vector3.FORWARD * 42.0
	elite.global_position.y = world.get_surface_height(elite.global_position.x, elite.global_position.z) + elite.body_radius
	elite._special_cooldown = 0.0
	_telegraph_seen = false
	elite.attack_telegraphed.connect(func(_enemy: EnemyAgent, _kind: StringName) -> void: _telegraph_seen = true)
	await physics_frame
	await physics_frame
	_expect(elite.is_elite and elite.maximum_health > 45.0, "Scheduled elites should be visually and mechanically stronger than standard threats.")
	_expect(_telegraph_seen and elite.get_attack_state() == EnemyAgent.AttackState.TELEGRAPH, "Elite attacks should enter a readable telegraph state before dealing burst damage.")
	elite.queue_free()
	await process_frame

	runner.cruise_speed = 0.0
	runner.boost_speed = 0.0
	runner.velocity = Vector3.ZERO
	var bulwark: EnemyAgent = director._spawn_enemy(&"bulwark")
	bulwark.global_position = runner.global_position + Vector3.RIGHT * 18.0
	bulwark.global_position.y = world.get_surface_height(bulwark.global_position.x, bulwark.global_position.z) + bulwark.body_radius
	bulwark._special_cooldown = 0.0
	var integrity_before_warning: float = runner.integrity
	await create_timer(0.35).timeout
	_expect(is_equal_approx(runner.integrity, integrity_before_warning), "A Bulwark pulse should not deal damage during its warning window.")
	await create_timer(0.7).timeout
	_expect(runner.integrity < integrity_before_warning, "A player remaining inside the completed Bulwark telegraph should take pulse damage.")
	bulwark.queue_free()
	await process_frame

	_victory_seen = false
	director.run_victory.connect(func() -> void: _victory_seen = true)
	director._spawn_apex()
	await process_frame
	var apex: EnemyAgent = director._apex
	_expect(is_instance_valid(apex) and apex.is_apex, "The climax should spawn a distinct Apex enemy.")
	_expect(scene.get_node("HUD/ApexBar").visible, "The Apex should present a dedicated health bar.")
	_expect("RIFT MATRIARCH" in scene.get_node("HUD/ApexLabel").text, "The boss HUD should identify the seed-selected encounter instead of using a generic Apex label.")
	if is_instance_valid(apex):
		apex.take_damage(apex.maximum_health * 0.5)
		await process_frame
		var apex_bar: ProgressBar = scene.get_node("HUD/ApexBar")
		_expect(is_equal_approx(apex_bar.value, apex.maximum_health * 0.5), "Apex damage should update the boss health presentation.")
		apex.take_damage(apex.maximum_health)
		await process_frame
	_expect(_victory_seen, "Defeating the Apex should resolve the run as a victory.")
	_expect(scene.get_node("HUD/VictoryOverlay").visible and paused, "Victory should pause play and present a clear ending.")
	_expect(not scene.get_node("HUD/VictoryOverlay/FeedbackChoices/Yes").disabled, "Victory should offer optional replay-intent feedback without hiding the ending.")
	_expect(scene.get_node("HUD/VictoryOverlay/CopyReport").visible, "Victory should expose the same playtest-report handoff as defeat.")

	paused = false
	scene.queue_free()
	await process_frame


func _validate_deadline_failure() -> void:
	var scene: Node = load("res://main.tscn").instantiate()
	scene.get_node("World").seed = 48920
	root.add_child(scene)
	await process_frame
	var director: CombatDirector = scene.get_node("CombatDirector")
	_failure_seen = false
	director.run_failed.connect(func(_reason: String) -> void: _failure_seen = true)
	director._spawn_apex()
	_expect(director._apex.archetype == &"velocity_reaver", "A different world seed should deterministically select the alternate Apex encounter.")
	director.elapsed_time = director.pacing.RUN_DURATION + 0.1
	director._update_run_pacing(director.pacing.RUN_DURATION - 0.1)
	await process_frame
	_expect(_failure_seen, "An undefeated Apex at 20:00 should resolve the run as a deadline failure.")
	_expect(scene.get_node("HUD/GameOverOverlay").visible and paused, "Deadline failure should pause play and present a clear retry state.")
	_expect(not scene.get_node("HUD/GameOverOverlay/FeedbackChoices/Yes").disabled, "Deadline failure should offer the same optional playtest feedback as victory.")
	_expect(scene.get_node("HUD/GameOverOverlay/CopyReport").visible, "Deadline failure should keep the playtest-report handoff available beside retry.")
	paused = false
	scene.queue_free()
	await process_frame


func _validate_post_defeat_atomicity() -> void:
	var scene: Node = load("res://main.tscn").instantiate()
	scene.set_meta("overrush_manual_start", true)
	scene.set_meta("overrush_disable_persistence", true)
	scene.get_node("World").seed = 56839
	root.add_child(scene)
	await process_frame
	scene.begin_run()
	await process_frame
	var director: CombatDirector = scene.get_node("CombatDirector")
	var runner: CharacterBody3D = scene.get_node("RunnerBall")
	director.build.apply_upgrade(&"dash_nova")
	director.build.pending_levels = 1
	director._offer_level_up()
	await process_frame
	_expect(director.is_choosing_upgrade() and scene.get_node("HUD/LevelUpOverlay").visible, "The fixture should begin with a live draft that could race the defeat event.")
	runner.take_damage(runner.integrity + 100.0, runner.global_position + Vector3.RIGHT, &"skimmer_charge")
	await process_frame
	var level_before := director.build.level
	var experience_before := director.build.experience
	var pending_before := director.build.pending_levels
	director._on_experience_collected(9999)
	director._on_integrity_collected(30.0)
	director.build.set_meta("current_options", [&"kinetic_repair"])
	director.choose_upgrade(0)
	await process_frame
	_expect(not director._run_active and not director.is_choosing_upgrade(), "Defeat should close combat and invalidate any in-flight draft atomically.")
	_expect(not scene.get_node("HUD/LevelUpOverlay").visible and scene.get_node("HUD/GameOverOverlay").visible, "The defeat recap should replace, never overlap, an in-flight draft.")
	_expect(is_zero_approx(runner.integrity), "A post-defeat Kinetic Repair choice must not revive a run that has already ended.")
	_expect(is_zero_approx(director.run_stats.integrity_recovered), "A post-defeat integrity core must not mutate recovery telemetry or revive the runner.")
	_expect(director.build.level == level_before and director.build.experience == experience_before and director.build.pending_levels == pending_before, "Post-defeat pickups and stale choices must not mutate progression or the recorded build.")
	paused = false
	scene.queue_free()
	await process_frame


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
