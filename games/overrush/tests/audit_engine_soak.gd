extends SceneTree

var _director: CombatDirector
var _runner: CharacterBody3D
var _world: Node3D
var _failures: Array[String] = []
var _strategy := "dashbreaker"
var _next_dash_time := 0.0
var _audit_seed := 41001


func _init() -> void:
	var user_args := OS.get_cmdline_user_args()
	if not user_args.is_empty():
		_strategy = user_args[0]
	if user_args.size() > 1:
		_audit_seed = int(user_args[1])
	Engine.physics_ticks_per_second = 600
	Engine.time_scale = 30.0
	call_deferred("_run")


func _run() -> void:
	var scene: Node = load("res://main.tscn").instantiate()
	scene.set_meta("overrush_manual_start", true)
	scene.set_meta("overrush_disable_persistence", true)
	scene.get_node("World").seed = _audit_seed
	root.add_child(scene)
	await process_frame
	_runner = scene.get_node("RunnerBall")
	_world = scene.get_node("World")
	_runner.maximum_integrity = 100000.0
	_runner.integrity = _runner.maximum_integrity
	_director = scene.get_node("CombatDirector")
	_director.level_up_requested.connect(_choose_upgrade)
	scene.begin_run()
	while _director.elapsed_time < 420.0 and _director._run_active:
		_apply_audit_route()
		if _strategy == "dashbreaker" and _director.elapsed_time >= _next_dash_time:
			_director._on_dash_state_changed(true)
			_director._on_dash_state_changed(false)
			_next_dash_time = _director.elapsed_time + 0.75
		elif _strategy == "arcstorm":
			_update_aim_heading()
		await process_frame
	_apply_audit_route()
	print("%s SOAK elapsed=%.1f level=%d clears=%d integrity=%.0f taken=%.0f distance=%.0f peak=%.1f current=%.1f position=%s milestones=%s total_damage=%.0f damage=%s" % [
		_strategy,
		_director.elapsed_time,
		_director.build.level,
		_director.enemies_defeated,
		_runner.integrity,
		_director.run_stats.damage_taken,
		_director.run_stats.distance_traveled,
		_director.run_stats.maximum_speed,
		_runner.get_horizontal_speed(),
		str(_runner.global_position),
		str(_director.run_stats.get_build_milestone_times()),
		_director.run_stats.get_total_damage(),
		_director.run_stats.get_damage_breakdown_text(),
	])
	print("%s UPGRADES %s" % [_strategy, str(_director.run_stats.upgrade_history)])
	print("%s SOURCES %s HITS %s" % [
		_strategy,
		str(_director.run_stats.damage_by_source),
		str(_director.run_stats.hits_by_source),
	])
	_validate_result()
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	if _failures.is_empty():
		print("Engine balance soak passed — %s remains fast, staged, viable, and mechanically distinct." % _strategy)
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _validate_result() -> void:
	var expected_paths := {
		"dashbreaker": [RunBuild.DASHBREAKER, &"gravity_knot", RunBuild.BACKDRAFT_MINE],
		"stormtrail": [RunBuild.STORMTRAIL, &"twin_current", RunBuild.HUNTER_ARRAY],
		"arcstorm": [RunBuild.ARCSTORM, &"storm_lance", RunBuild.HUNTER_ARRAY],
	}
	_expect(expected_paths.has(_strategy), "Unknown engine strategy '%s'." % _strategy)
	if not expected_paths.has(_strategy):
		return
	var expected: Array = expected_paths[_strategy]
	_expect(_director.build.core_path == expected[0], "The soak should retain its intended engine commitment.")
	_expect(_director.build.evolution_id == expected[1], "The soak should reach its intended evolution fork.")
	_expect(_director.build.arsenal_id == expected[2], "The soak should reach its intended independent arsenal.")
	_expect(_director.elapsed_time >= 419.0, "The representative seven-minute sample should complete.")
	_expect(_director.run_stats.distance_traveled >= 20000.0, "The strategy must preserve high-speed traversal instead of farming while stalled.")
	_expect(_runner.get_horizontal_speed() >= 45.0, "The sample should finish at traversal speed.")
	_expect(_director.enemies_defeated >= 260 and _director.enemies_defeated <= 700, "The engine should remain inside the broad viable clear envelope.")
	for milestone_id in _director.run_stats.get_build_milestone_times():
		var window: Vector2 = RunPacing.BUILD_MILESTONE_WINDOWS[milestone_id]
		var milestone_time := float(_director.run_stats.get_build_milestone_times()[milestone_id])
		_expect(milestone_time >= window.x and milestone_time <= window.y, "%s should not bypass its authored cadence window." % milestone_id)
	if _strategy == "dashbreaker":
		_expect(_source_share(&"dash_nova") <= 0.65, "Dashbreaker's charged entry nova should not dominate its mature loadout.")
		_expect(_source_share(&"gravity_knot") + _source_share(&"backdraft_mine") >= 0.05, "Dashbreaker's evolution and arsenal should make a measurable contribution.")
	elif _strategy == "arcstorm":
		_expect(_source_share(&"storm_lance") <= 0.75, "Storm Lance should reward aim without erasing Arcstorm's residual coverage.")
		_expect(_source_share(&"arc_bolt") >= 0.15, "Missed Storm Lance lanes should preserve meaningful residual Arcstorm output.")


func _source_share(source_id: StringName) -> float:
	return float(_director.run_stats.damage_by_source.get(source_id, 0.0)) / maxf(_director.run_stats.get_total_damage(), 1.0)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _apply_audit_route() -> void:
	var elapsed := _director.elapsed_time
	var angular_speed := 58.0 / 720.0
	var angle := elapsed * angular_speed
	var radius := 720.0
	var radial_speed := 0.0
	if _strategy == "stormtrail":
		radius += sin(elapsed * 0.48) * 115.0
		radial_speed = cos(elapsed * 0.48) * 115.0 * 0.48
	var position := Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
	var route_heading := Vector3(
		radial_speed * cos(angle) - radius * angular_speed * sin(angle),
		0.0,
		radial_speed * sin(angle) + radius * angular_speed * cos(angle)
	).normalized()
	position.y = _world.get_surface_height(position.x, position.z) + 2.0
	_runner.global_position = position
	_runner.apply_boundary_heading(route_heading)
	_runner.velocity = route_heading * 58.0


func _update_aim_heading() -> void:
	var best_target: EnemyAgent
	var best_score := INF
	for enemy in _director._enemies:
		if not is_instance_valid(enemy):
			continue
		var candidate_direction: Vector3 = enemy.global_position - _runner.global_position
		candidate_direction.y = 0.0
		var distance: float = candidate_direction.length()
		if distance < 0.01 or distance > _director.TARGETING_RANGE:
			continue
		var candidate_angle: float = _runner.heading.signed_angle_to(candidate_direction / distance, Vector3.UP)
		if absf(candidate_angle) > PI * 0.5:
			continue
		var score: float = absf(candidate_angle) + distance / _director.TARGETING_RANGE * 0.22
		if score < best_score:
			best_score = score
			best_target = enemy
	if best_target == null:
		return
	var target_direction: Vector3 = best_target.global_position - _runner.global_position
	target_direction.y = 0.0
	if target_direction.length_squared() < 0.01:
		return
	var angle: float = _runner.heading.signed_angle_to(target_direction.normalized(), Vector3.UP)
	if absf(angle) > PI * 0.5:
		return
	_runner.apply_boundary_heading(_runner.heading.slerp(target_direction.normalized(), 0.46).normalized())


func _choose_upgrade(options: Array[StringName]) -> void:
	var preference: Array[StringName]
	if _strategy == "dashbreaker":
		preference = [
			&"gravity_knot", RunBuild.BACKDRAFT_MINE, RunBuild.PULSE_CORE,
			&"dash_nova", &"dash_echo", &"phase_shell", &"event_horizon",
			&"backdraft_charge", &"kinetic_repair",
		]
	elif _strategy == "stormtrail":
		preference = [
			&"twin_current", RunBuild.HUNTER_ARRAY, RunBuild.REDLINE_CORE,
			&"slipstream", &"wake_voltage", &"wake_width", &"wake_duration",
			&"parallel_flow", &"hunter_guidance", &"kinetic_repair",
		]
	else:
		preference = [
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
