extends SceneTree

const RunBuildScript = preload("res://scripts/run_build.gd")

var _failures: Array[String] = []
var _catalyst_announcement := ""


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene: Node = load("res://main.tscn").instantiate()
	scene.set_meta("overrush_disable_persistence", true)
	scene.set_meta("overrush_manual_start", true)
	scene.get_node("World").seed = 175624
	root.add_child(scene)
	await process_frame
	scene.begin_run()
	await process_frame
	var director: CombatDirector = scene.get_node("CombatDirector")
	var runner: CharacterBody3D = scene.get_node("RunnerBall")
	for enemy in director._enemies:
		if is_instance_valid(enemy):
			enemy.queue_free()
	director._enemies.clear()
	await process_frame

	director.build = _catalyst_ready_build()
	director.build.pending_levels = 1
	director.elapsed_time = director.pacing.BUILD_MILESTONE_WINDOWS[&"catalyst"].x
	director.event_announced.connect(func(title: String, _subtitle: String) -> void:
		if "TUNED" in title:
			_catalyst_announcement = title
	)
	director._offer_level_up()
	await process_frame
	_expect(scene.level_up_title.text == "TUNE YOUR DRIVE", "The catalyst milestone should present a dedicated strategic fork instead of looking like a routine rank-up.")
	_expect(scene._current_upgrade_options == RunBuild.CATALYST_IDS, "All three movement rhythms should appear together so the choice is informed rather than roll-dependent.")
	_expect(scene.reroll_button.disabled and scene.banish_button.disabled, "A complete catalyst fork should not waste rerolls or allow one rhythm to be banished.")
	scene._choose_upgrade(0)
	await process_frame
	_expect(director.build.catalyst_id == RunBuild.REDLINE_CORE and not paused, "Choosing a catalyst should commit the build, consume the pending level, and resume the run.")
	_expect("REDLINE CORE TUNED" in _catalyst_announcement, "Catalyst commitment should receive clear in-world confirmation.")

	runner.velocity = runner.heading.normalized() * 58.0
	scene._process(0.0)
	_expect("REDLINE CORE" in scene.info.text and "OUTPUT 78%" in scene.info.text, "The live HUD should expose Redline's low-speed penalty before it affects an unseen calculation.")
	var low_target := director._spawn_enemy(&"bulwark")
	low_target.movement_speed = 0.0
	low_target.global_position = runner.global_position
	low_target.maximum_health = 1000.0
	low_target.health = 1000.0
	var low_health := low_target.health
	director._release_nova(runner.global_position, 100.0, 10.0, Color.WHITE, &"dash_nova")
	var low_damage := low_health - low_target.health

	runner.velocity = runner.heading.normalized() * 126.0
	scene._process(0.0)
	_expect("OUTPUT 150%" in scene.info.text, "The live HUD should show when dash velocity fully activates Redline Core.")
	var high_target := director._spawn_enemy(&"bulwark")
	high_target.movement_speed = 0.0
	high_target.global_position = runner.global_position
	high_target.maximum_health = 1000.0
	high_target.health = 1000.0
	var high_health := high_target.health
	director._release_nova(runner.global_position, 100.0, 10.0, Color.WHITE, &"dash_nova")
	var high_damage := high_health - high_target.health
	_expect(is_equal_approx(low_damage, 78.0) and is_equal_approx(high_damage, 150.0), "Catalyst output should reach actual combat damage exactly once at both penalty and empowered states.")
	await _clear_combat_children(director)

	var trail_build := RunBuildScript.new()
	trail_build.apply_upgrade(&"slipstream")
	trail_build.catalyst_id = RunBuild.REDLINE_CORE
	director.build = trail_build
	runner.velocity = runner.heading.normalized() * 126.0
	director._wake_timer = 0.0
	director._update_slipstream(1.0)
	var wake: SlipstreamWake
	for child in director.get_children():
		if child is SlipstreamWake:
			wake = child
			break
	_expect(wake != null and is_equal_approx(wake.damage, trail_build.get_wake_damage(126.0) * 1.5), "Stormtrail wakes should snapshot the same catalyst output used by direct-impact damage.")
	await _clear_combat_children(director)

	var arc_build := RunBuildScript.new()
	arc_build.apply_upgrade(&"velocity_coil")
	arc_build.catalyst_id = RunBuild.PULSE_CORE
	director.build = arc_build
	runner.velocity = runner.heading.normalized() * 88.0
	director._catalyst_dash_window = RunBuild.PULSE_WINDOW_SECONDS
	var arc_target := director._spawn_enemy(&"bulwark")
	arc_target.movement_speed = 0.0
	arc_target.global_position = runner.global_position + runner.heading.normalized() * 24.0
	director._fire_timer = 0.0
	director._update_arc_weapon(1.0)
	var projectile: ArcProjectile
	for child in director.get_children():
		if child is ArcProjectile:
			projectile = child
			break
	_expect(projectile != null and is_equal_approx(projectile.damage, arc_build.get_arc_damage(88.0) * 1.35), "Arcstorm projectiles should receive the active catalyst exactly once before they begin chaining.")

	director.build.catalyst_id = RunBuild.AIRFRAME_CORE
	runner._airborne_time = runner.AIRFRAME_COMMIT_TIME - 0.01
	_expect("OUTPUT 80%" in director.get_catalyst_status(), "Airframe Core should ignore tiny terrain separations that would make the HUD and damage flicker.")
	runner._airborne_time = runner.AIRFRAME_COMMIT_TIME
	_expect("OUTPUT 140%" in director.get_catalyst_status(), "A committed hop should activate Airframe Core after the short anti-flicker threshold.")

	arc_build.catalyst_id = RunBuild.PULSE_CORE
	director.build = arc_build
	runner.velocity = runner.heading.normalized() * 88.0
	director._catalyst_dash_window = 0.0
	_expect("OUTPUT 75%" in director.get_catalyst_status(), "Pulse Core should visibly penalize attacks outside its cadence window.")
	director._on_dash_state_changed(true)
	_expect(director._catalyst_dash_window == RunBuild.PULSE_WINDOW_SECONDS and "OUTPUT 135%" in director.get_catalyst_status(), "Starting a dash should immediately open Pulse Core's short empowered window.")

	paused = false
	scene.queue_free()
	await process_frame
	if _failures.is_empty():
		print("Drive catalyst validation passed — protected drafting, tradeoffs, live state, combat output, and dash timing agree.")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _catalyst_ready_build() -> RunBuild:
	var build: RunBuild = RunBuildScript.new()
	for _rank in range(RunBuild.EVOLUTION_UNLOCK_RANK):
		build.apply_upgrade(&"dash_nova")
	build.apply_upgrade(&"ramjet")
	while build.get_specialization_rank() < RunBuild.CATALYST_UNLOCK_RANK:
		build.apply_upgrade(&"dash_nova")
	build.apply_upgrade(RunBuild.HUNTER_ARRAY)
	return build


func _clear_combat_children(director: CombatDirector) -> void:
	for child in director.get_children():
		child.queue_free()
	director._enemies.clear()
	await process_frame


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
