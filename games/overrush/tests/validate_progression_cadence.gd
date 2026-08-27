extends SceneTree

var _failures: Array[String] = []
var _director: CombatDirector
var _wall_start := 0


func _init() -> void:
	Engine.physics_ticks_per_second = 600
	Engine.time_scale = 30.0
	_wall_start = Time.get_ticks_msec()
	call_deferred("_run")


func _run() -> void:
	var scene: Node = load("res://main.tscn").instantiate()
	scene.set_meta("overrush_manual_start", true)
	scene.set_meta("overrush_disable_persistence", true)
	scene.get_node("World").seed = 41001
	root.add_child(scene)
	await process_frame
	var runner: CharacterBody3D = scene.get_node("RunnerBall")
	runner.maximum_integrity = 100000.0
	runner.integrity = runner.maximum_integrity
	_director = scene.get_node("CombatDirector")
	_director.level_up_requested.connect(_choose_upgrade)
	scene.begin_run()
	while _director.elapsed_time < 900.0 and _director._run_active and _director.build.catalyst_id.is_empty():
		await process_frame

	var milestones := _director.run_stats.get_build_milestone_times()
	var cadence_failures := _director.pacing.get_build_cadence_failures(milestones)
	var total_damage := maxf(_director.run_stats.get_total_damage(), 1.0)
	var lance_share := float(_director.run_stats.damage_by_source.get(&"storm_lance", 0.0)) / total_damage
	var residual_share := float(_director.run_stats.damage_by_source.get(&"arc_bolt", 0.0)) / total_damage
	print("Cadence sample — elapsed %.1f, level %d, clears %d, milestones %s, damage %s" % [
		_director.elapsed_time,
		_director.build.level,
		_director.enemies_defeated,
		str(milestones),
		_director.run_stats.get_damage_breakdown_text(),
	])
	_expect(cadence_failures.is_empty(), "The fixed-seed full-system run should reach each build fork inside its authored cadence window; failed: %s." % str(cadence_failures))
	_expect(_director.build.core_path == RunBuild.ARCSTORM, "The soak strategy should commit to Arcstorm rather than silently changing build identity.")
	_expect(_director.build.evolution_id == &"storm_lance", "The soak should reach its intended exclusive evolution.")
	_expect(_director.build.arsenal_id == RunBuild.HUNTER_ARRAY, "The soak should reach an independent arsenal fork.")
	_expect(_director.build.catalyst_id == RunBuild.REDLINE_CORE, "The soak should reach a movement-conditioned Drive fork before the Overrun phase ends.")
	_expect(_director.run_stats.upgrade_events.size() == _director.run_stats.upgrade_history.size(), "Every draft choice should retain timestamped balance evidence.")
	_expect(lance_share <= 0.75, "The aimed evolution should not erase Arcstorm's residual coverage in the full-system sample.")
	_expect(residual_share >= 0.15, "Missed Storm Lance lanes should preserve a meaningful automatic fallback contribution.")
	_expect(float(_director.run_stats.damage_by_source.get(&"hunter_array", 0.0)) > 0.0, "The independent arsenal should contribute before the Drive fork arrives.")
	_expect(float(milestones.get("engine", 0.0)) >= RunOnboarding.AUTOMATIC_ADVANCE_SECONDS, "The first engine decision should not interrupt the initial steering guidance beat.")
	_expect(Time.get_ticks_msec() - _wall_start < 60000, "The accelerated cadence gate should remain practical for routine validation.")

	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	paused = false
	scene.queue_free()
	await process_frame
	if _failures.is_empty():
		print("Progression cadence validation passed — real spawning, combat, pickups, and drafts reach all four build milestones at intentional times.")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _choose_upgrade(options: Array[StringName]) -> void:
	var preference: Array[StringName] = [
		&"storm_lance", RunBuild.HUNTER_ARRAY, RunBuild.REDLINE_CORE,
		&"velocity_coil", &"arc_payload", &"forked_current", &"arc_capacitor", &"arc_chain",
		&"lance_focus", &"hunter_guidance", &"kinetic_repair",
	]
	var choice := 0
	for upgrade_id in preference:
		var index := options.find(upgrade_id)
		if index >= 0:
			choice = index
			break
	_director.choose_upgrade(choice)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
