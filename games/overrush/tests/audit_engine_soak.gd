extends SceneTree

var _director: CombatDirector
var _runner: CharacterBody3D
var _world: Node3D
var _failures: Array[String] = []
var _strategy := "dashbreaker"
var _next_dash_time := 0.0
var _dash_end_time := 0.0
var _ramjet_dash_started_at := 0.0
var _ramjet_dash_start := Vector3.ZERO
var _ramjet_dash_heading := Vector3.FORWARD
var _close_route_position := Vector3.ZERO
var _close_route_heading := Vector3.FORWARD
var _close_route_initialized := false
var _last_route_elapsed := -1.0
var _audit_seed := 41001
var _sample_duration := 420.0
var _apex_only := false
var _outcome := ""
var _apex_started_at := -1.0
var _apex_identity := &""
var _apex_initial_health := 0.0
var _apex_damage_by_source: Dictionary = {}
var _apex_pass_heading := Vector3.FORWARD
var _apex_pass_end_time := 0.0


func _init() -> void:
	var user_args := OS.get_cmdline_user_args()
	if not user_args.is_empty():
		_strategy = user_args[0]
	if user_args.size() > 1:
		_audit_seed = int(user_args[1])
	if user_args.size() > 2:
		_sample_duration = maxf(420.0, float(user_args[2]))
	if user_args.size() > 3:
		_apex_only = user_args[3] == "apex_only"
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
	# This audit isolates build output. Finite-integrity pressure is covered by audit_survival_soak.gd.
	_runner.maximum_integrity = 100.0
	_runner.integrity = _runner.maximum_integrity
	_runner.grant_damage_immunity(INF)
	_director = scene.get_node("CombatDirector")
	_director.level_up_requested.connect(_choose_upgrade)
	_director.apex_health_changed.connect(_on_apex_health_audit)
	_director.run_victory.connect(func() -> void: _outcome = "victory")
	_director.run_failed.connect(func(_reason: String) -> void: _outcome = "deadline")
	scene.begin_run()
	if _apex_only:
		_configure_mature_build()
		_director.elapsed_time = RunPacing.APEX_TIME
		_director._spawn_timer = INF
		_director._spawn_apex()
	while _director.elapsed_time < _sample_duration and _director._run_active:
		_capture_apex_start()
		_apply_audit_route()
		if _strategy == "ramjet":
			_director._update_ramjet()
			_update_ramjet_dash_cycle()
		elif _strategy == "dashbreaker" and _director.elapsed_time >= _next_dash_time:
			_director._on_dash_state_changed(true)
			_director._on_dash_state_changed(false)
			_next_dash_time = _director.elapsed_time + 0.75
		elif _strategy == "arcstorm":
			_update_aim_heading()
		await process_frame
	_capture_apex_start()
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
	if _sample_duration >= RunPacing.RUN_DURATION:
		var encounter_time := _director.elapsed_time - _apex_started_at if _apex_started_at >= 0.0 else 0.0
		print("APEX_RESULT strategy=%s apex=%s outcome=%s encounter_time=%.1f damage=%.0f sources=%s" % [
			_strategy,
			str(_apex_identity),
			_outcome,
			encounter_time,
			_get_apex_damage_total(),
			str(_apex_damage_by_source),
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
		"dashbreaker": [RunBuild.DASHBREAKER, &"gravity_knot", RunBuild.BACKDRAFT_MINE, RunBuild.PULSE_CORE],
		"ramjet": [RunBuild.DASHBREAKER, &"ramjet", RunBuild.DRIFT_BLADES, RunBuild.PULSE_CORE],
		"stormtrail": [RunBuild.STORMTRAIL, &"twin_current", RunBuild.HUNTER_ARRAY, RunBuild.REDLINE_CORE],
		"tempest_anchor": [RunBuild.STORMTRAIL, &"tempest_anchor", RunBuild.DRIFT_BLADES, RunBuild.REDLINE_CORE],
		"arcstorm": [RunBuild.ARCSTORM, &"storm_lance", RunBuild.HUNTER_ARRAY, RunBuild.REDLINE_CORE],
		"arc_orbit": [RunBuild.ARCSTORM, &"arc_orbit", RunBuild.DRIFT_BLADES, RunBuild.REDLINE_CORE],
	}
	_expect(expected_paths.has(_strategy), "Unknown engine strategy '%s'." % _strategy)
	if not expected_paths.has(_strategy):
		return
	var expected: Array = expected_paths[_strategy]
	_expect(_director.build.core_path == expected[0], "The soak should retain its intended engine commitment.")
	_expect(_director.build.evolution_id == expected[1], "The soak should reach its intended evolution fork.")
	_expect(_director.build.arsenal_id == expected[2], "The soak should reach its intended independent arsenal.")
	var is_late_sample := _sample_duration >= 1000.0
	var is_climax_sample := _sample_duration >= RunPacing.RUN_DURATION
	if is_climax_sample:
		_expect(_apex_started_at >= RunPacing.APEX_TIME - 1.0, "The complete-run audit should reach and measure its Apex encounter.")
		_expect(_outcome == "victory", "The mature %s build should defeat %s before the 20-minute deadline." % [_strategy, str(_apex_identity)])
		var encounter_time := _director.elapsed_time - _apex_started_at
		_expect(encounter_time >= 12.0, "The Apex should remain a meaningful climax instead of evaporating on arrival.")
		_expect(encounter_time <= RunPacing.RUN_DURATION - RunPacing.APEX_TIME, "The Apex should fall inside its authored two-minute window.")
		_expect(_get_apex_damage_total() >= _apex_initial_health * 0.99, "Measured build damage should account for the complete Apex health pool.")
		_validate_apex_build_identity()
	else:
		_expect(_director.elapsed_time >= _sample_duration - 1.0, "The requested strategy sample should complete.")
	var required_traversal_time := _director.elapsed_time - RunPacing.APEX_TIME if _apex_only else _sample_duration
	_expect(_director.run_stats.distance_traveled >= required_traversal_time * 45.0, "The strategy must preserve high-speed traversal instead of farming while stalled.")
	_expect(_runner.get_horizontal_speed() >= 45.0, "The sample should finish at traversal speed.")
	if _apex_only:
		_expect(_director.build.catalyst_id == expected[3], "The Apex sample should use its intended mature movement catalyst.")
	elif is_late_sample:
		_expect(_director.build.catalyst_id == expected[3], "The late sample should reach its intended movement catalyst.")
		_expect(_director.enemies_defeated >= 500 and _director.enemies_defeated <= 1000, "The engine should remain inside the shared late-run clear envelope.")
		_expect(_director.pacing.get_build_cadence_failures(_director.run_stats.get_build_milestone_times()).is_empty(), "The late sample should reach every build commitment inside its authored cadence window.")
	else:
		_expect(_director.enemies_defeated >= 260 and _director.enemies_defeated <= 700, "The engine should remain inside the broad seven-minute clear envelope.")
	if not _apex_only:
		for milestone_id in _director.run_stats.get_build_milestone_times():
			var window: Vector2 = RunPacing.BUILD_MILESTONE_WINDOWS[milestone_id]
			var milestone_time := float(_director.run_stats.get_build_milestone_times()[milestone_id])
			_expect(milestone_time >= window.x and milestone_time <= window.y, "%s should not bypass its authored cadence window." % milestone_id)
	if _apex_only:
		return
	if _strategy == "dashbreaker":
		_expect(_source_share(&"dash_nova") <= 0.65, "Dashbreaker's charged entry nova should not dominate its mature loadout.")
		_expect(_source_share(&"gravity_knot") + _source_share(&"backdraft_mine") >= 0.05, "Dashbreaker's evolution and arsenal should make a measurable contribution.")
	elif _strategy == "ramjet" and is_late_sample:
		_expect(_source_share(&"ramjet") >= 0.15, "Ramjet impacts should remain a meaningful reward for threading dash lines through threats.")
		_expect(_source_share(&"dash_nova") <= 0.7, "Dash Nova should open Ramjet entries without erasing direct-impact play.")
	elif _strategy == "arcstorm":
		_expect(_source_share(&"storm_lance") <= 0.75, "Storm Lance should reward aim without erasing Arcstorm's residual coverage.")
		_expect(_source_share(&"arc_bolt") >= 0.15, "Missed Storm Lance lanes should preserve meaningful residual Arcstorm output.")
	elif _strategy == "stormtrail" and is_late_sample:
		_expect(_source_share(&"twin_current") <= 0.9, "Twin Current should reward sustained weaving without erasing its arsenal and base engine.")
		_expect(_source_share(&"hunter_array") >= 0.05, "Stormtrail's independent arsenal should remain measurable at late density.")
	elif _strategy == "tempest_anchor" and is_late_sample:
		_expect(_source_share(&"tempest_anchor") >= 0.15 and _source_share(&"tempest_anchor") <= 0.65, "Tempest Anchor should matter without replacing its continuous route-control wake.")
		_expect(_source_share(&"drift_blades") >= 0.04, "Tempest Anchor's independent close arsenal should remain measurable.")
	elif _strategy == "arc_orbit" and is_late_sample:
		_expect(_source_share(&"arc_orbit") <= 0.93, "Arc Orbit should reward threading without erasing the rest of its loadout.")
		_expect(_source_share(&"drift_blades") >= 0.04, "Arc Orbit's independent close arsenal should remain measurable.")


func _validate_apex_build_identity() -> void:
	var signature_sources := {
		"dashbreaker": &"gravity_knot",
		"ramjet": &"ramjet",
		"stormtrail": &"twin_current",
		"tempest_anchor": &"tempest_anchor",
		"arcstorm": &"storm_lance",
		"arc_orbit": &"arc_orbit",
	}
	if not signature_sources.has(_strategy):
		return
	var signature_source: StringName = signature_sources[_strategy]
	var signature_damage := float(_apex_damage_by_source.get(signature_source, 0.0))
	_expect(signature_damage / maxf(_get_apex_damage_total(), 1.0) >= 0.05, "%s should contribute meaningfully to its own Apex clear." % str(signature_source))


func _configure_mature_build() -> void:
	var mature_upgrades := {
		"dashbreaker": [
			&"dash_nova", &"dash_nova", &"dash_echo", &"dash_nova", &"gravity_knot",
			&"dash_nova", &"phase_shell", RunBuild.BACKDRAFT_MINE, &"dash_nova",
			&"dash_nova", &"dash_nova", &"event_horizon", &"dash_echo",
			RunBuild.PULSE_CORE, &"dash_nova",
		],
		"ramjet": [
			&"dash_nova", &"dash_nova", &"dash_nova", &"dash_nova", &"ramjet",
			&"dash_nova", &"dash_nova", RunBuild.DRIFT_BLADES, &"dash_nova",
			&"dash_nova", &"ramjet_mass", &"dash_nova", &"ramjet_mass",
			RunBuild.PULSE_CORE, &"dash_nova",
		],
		"stormtrail": [
			&"slipstream", &"wake_voltage", &"wake_voltage", &"slipstream", &"twin_current",
			&"wake_voltage", &"wake_duration", RunBuild.HUNTER_ARRAY, &"wake_duration",
			&"wake_width", &"slipstream", &"slipstream", RunBuild.REDLINE_CORE,
			&"slipstream", &"slipstream", &"wake_voltage", &"wake_width", &"wake_width",
			&"slipstream",
		],
		"tempest_anchor": [
			&"slipstream", &"wake_voltage", &"wake_voltage", &"slipstream", &"tempest_anchor",
			&"slipstream", &"wake_voltage", RunBuild.DRIFT_BLADES, &"slipstream",
			&"wake_width", &"slipstream", &"storm_charge", &"wake_width",
			RunBuild.REDLINE_CORE, &"slipstream", &"slipstream", &"slipstream",
		],
		"arcstorm": [
			&"velocity_coil", &"velocity_coil", &"velocity_coil", &"forked_current", &"storm_lance",
			&"velocity_coil", &"velocity_coil", RunBuild.HUNTER_ARRAY, &"velocity_coil",
			&"arc_payload", &"arc_payload", RunBuild.REDLINE_CORE, &"lance_focus",
		],
		"arc_orbit": [
			&"velocity_coil", &"velocity_coil", &"velocity_coil", &"arc_payload", &"arc_orbit",
			&"velocity_coil", &"arc_payload", RunBuild.DRIFT_BLADES, &"drift_edge",
			&"arc_payload", &"velocity_coil", &"velocity_coil", RunBuild.REDLINE_CORE,
			&"orbit_flux",
		],
	}
	if not mature_upgrades.has(_strategy):
		return
	for upgrade_id in mature_upgrades[_strategy]:
		_director.build.apply_upgrade(upgrade_id)
	_director.run_stats.reset(_runner.global_position)


func _source_share(source_id: StringName) -> float:
	return float(_director.run_stats.damage_by_source.get(source_id, 0.0)) / maxf(_director.run_stats.get_total_damage(), 1.0)


func _get_apex_damage_total() -> float:
	var total := 0.0
	for source_id in _apex_damage_by_source:
		total += float(_apex_damage_by_source[source_id])
	return total


func _capture_apex_start() -> void:
	if _apex_started_at >= 0.0 or not _director.has_active_apex():
		return
	var apex: EnemyAgent = _director._apex
	_apex_started_at = _director.elapsed_time
	_apex_identity = apex.archetype
	_apex_initial_health = apex.maximum_health
	apex.damaged.connect(_on_apex_damaged)


func _on_apex_health_audit(_current: float, _maximum: float) -> void:
	_capture_apex_start()


func _on_apex_damaged(_enemy: EnemyAgent, amount: float, source_id: StringName) -> void:
	_apex_damage_by_source[source_id] = float(_apex_damage_by_source.get(source_id, 0.0)) + amount


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _apply_audit_route() -> void:
	var elapsed := _director.elapsed_time
	var route_delta := 0.0 if _last_route_elapsed < 0.0 else minf(0.1, elapsed - _last_route_elapsed)
	_last_route_elapsed = elapsed
	if _director.has_active_apex():
		_apply_apex_route(route_delta)
		return
	var angular_speed := 58.0 / 720.0
	var angle := elapsed * angular_speed
	var radius := 720.0
	var radial_speed := 0.0
	if _strategy in ["stormtrail", "tempest_anchor"]:
		radius += sin(elapsed * 0.48) * 115.0
		radial_speed = cos(elapsed * 0.48) * 115.0 * 0.48
	elif _strategy == "ramjet":
		radius += sin(elapsed * 0.36) * 72.0
		radial_speed = cos(elapsed * 0.36) * 72.0 * 0.36
	var position := Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
	var route_heading := Vector3(
		radial_speed * cos(angle) - radius * angular_speed * sin(angle),
		0.0,
		radial_speed * sin(angle) + radius * angular_speed * cos(angle)
	).normalized()
	var orbit_threading_window := _strategy == "arc_orbit" and fmod(elapsed, 10.0) < 6.5
	var ramjet_threading_window := _strategy == "ramjet" and fmod(elapsed, 10.0) < 5.5
	if (_strategy == "arc_orbit" and not orbit_threading_window) or (_strategy == "ramjet" and not ramjet_threading_window):
		_close_route_initialized = false
	if (ramjet_threading_window or orbit_threading_window) and not _runner.is_dashing():
		if not _close_route_initialized:
			_close_route_position = position
			_close_route_heading = route_heading
			_close_route_initialized = true
		var desired_heading := route_heading
		var target := _find_close_route_target(_close_route_position)
		if target != null:
			desired_heading = target.global_position - _close_route_position
			desired_heading.y = 0.0
			desired_heading = desired_heading.normalized()
		if _close_route_position.length() > 1200.0:
			desired_heading = desired_heading.slerp(-_close_route_position.normalized(), 0.45).normalized()
		_close_route_heading = _close_route_heading.slerp(desired_heading, minf(1.0, 3.4 * route_delta)).normalized()
		_close_route_position += _close_route_heading * 58.0 * route_delta
		position = _close_route_position
		route_heading = _close_route_heading
	if _strategy == "ramjet" and _runner.is_dashing():
		var dash_progress := clampf(elapsed - _ramjet_dash_started_at, 0.0, 0.2)
		position = _ramjet_dash_start + _ramjet_dash_heading * _runner.dash_speed * dash_progress
		route_heading = _ramjet_dash_heading
		_close_route_position = position
		_close_route_heading = route_heading
	position.y = _world.get_surface_height(position.x, position.z) + 2.0
	_runner.global_position = position
	_runner.apply_boundary_heading(route_heading)
	var route_speed := 126.0 if _strategy == "ramjet" and _runner.is_dashing() else 58.0
	_runner.velocity = route_heading * route_speed


func _apply_apex_route(delta: float) -> void:
	var apex: EnemyAgent = _director._apex
	var position := _runner.global_position
	var to_apex: Vector3 = apex.global_position - position
	to_apex.y = 0.0
	var distance := to_apex.length()
	var toward: Vector3 = to_apex / distance if distance > 0.01 else _runner.heading
	var tangent: Vector3 = Vector3(-toward.z, 0.0, toward.x)
	var weave_sign := -1.0 if sin(_director.elapsed_time * 0.42) < 0.0 else 1.0
	var route_heading: Vector3 = tangent * weave_sign
	if _strategy in ["stormtrail", "tempest_anchor"]:
		if _director.elapsed_time >= _apex_pass_end_time:
			_apex_pass_heading = toward
			_apex_pass_end_time = _director.elapsed_time + clampf(distance / 58.0 + 1.0, 1.8, 3.0)
		route_heading = _apex_pass_heading
	elif _strategy == "arcstorm":
		if distance > 52.0:
			route_heading = toward
		elif distance < 28.0:
			route_heading = (-toward + tangent * weave_sign * 0.4).normalized()
		else:
			route_heading = (toward + tangent * weave_sign * 0.18).normalized()
	else:
		var desired_distance := 20.0 if _strategy in ["dashbreaker", "ramjet", "arc_orbit"] else 32.0
		if distance > desired_distance + 8.0:
			route_heading = (toward + tangent * weave_sign * 0.22).normalized()
		elif distance < desired_distance - 6.0:
			route_heading = (-toward + tangent * weave_sign * 0.62).normalized()
		else:
			route_heading = tangent * weave_sign
	if position.length() > 1220.0:
		route_heading = route_heading.slerp(-position.normalized(), 0.68).normalized()
	var route_speed := 58.0
	if _strategy == "ramjet" and _runner.is_dashing():
		route_heading = _ramjet_dash_heading
		route_speed = 126.0
	position += route_heading * route_speed * delta
	position.y = _world.get_surface_height(position.x, position.z) + 2.0
	_runner.global_position = position
	_runner.apply_boundary_heading(route_heading)
	_runner.velocity = route_heading * route_speed


func _find_close_route_target(from_position: Vector3) -> EnemyAgent:
	var best_target: EnemyAgent
	var best_distance := 135.0
	for enemy in _director._enemies:
		if not is_instance_valid(enemy):
			continue
		var offset: Vector3 = enemy.global_position - from_position
		offset.y = 0.0
		var distance := offset.length()
		if distance < best_distance:
			best_target = enemy
			best_distance = distance
	return best_target


func _update_ramjet_dash_cycle() -> void:
	var elapsed := _director.elapsed_time
	if _runner.is_dashing() and elapsed >= _dash_end_time:
		_runner._dash_state.is_active = false
		_director._on_dash_state_changed(false)
	if _runner.is_dashing() or elapsed < _next_dash_time:
		return
	if _director.has_active_apex():
		var apex_offset: Vector3 = _director._apex.global_position - _runner.global_position
		apex_offset.y = 0.0
		if apex_offset.length() > 22.0:
			return
	_runner._dash_state.is_active = true
	_runner._dash_state.elapsed = 0.0
	_ramjet_dash_started_at = elapsed
	_ramjet_dash_start = _runner.global_position
	_ramjet_dash_heading = _get_ramjet_dash_heading()
	_director._on_dash_state_changed(true)
	if _director.has_active_apex():
		var dash_destination: Vector3 = _runner.global_position + _ramjet_dash_heading * _runner.dash_speed * 0.2
		dash_destination.y = _world.get_surface_height(dash_destination.x, dash_destination.z) + 2.0
		_runner.global_position = dash_destination
		_runner.velocity = _ramjet_dash_heading * _runner.dash_speed
		_director._update_ramjet()
	_dash_end_time = elapsed + 0.2
	_next_dash_time = elapsed + 0.75


func _get_ramjet_dash_heading() -> Vector3:
	if _director.has_active_apex():
		var apex_direction: Vector3 = _director._apex.global_position - _runner.global_position
		apex_direction.y = 0.0
		if apex_direction.length_squared() > 0.01:
			return apex_direction.normalized()
	var best_target: EnemyAgent
	var best_distance := 42.0
	for enemy in _director._enemies:
		if not is_instance_valid(enemy):
			continue
		var offset: Vector3 = enemy.global_position - _runner.global_position
		offset.y = 0.0
		var distance := offset.length()
		if distance > 4.0 and distance < best_distance:
			best_target = enemy
			best_distance = distance
	if best_target == null:
		return _runner.heading.normalized()
	var direction: Vector3 = best_target.global_position - _runner.global_position
	direction.y = 0.0
	return direction.normalized()


func _update_aim_heading() -> void:
	if _director.has_active_apex():
		var apex_direction: Vector3 = _director._apex.global_position - _runner.global_position
		apex_direction.y = 0.0
		if apex_direction.length_squared() > 0.01:
			_runner.apply_boundary_heading(apex_direction.normalized())
		return
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
	elif _strategy == "ramjet":
		preference = [
			&"ramjet", RunBuild.DRIFT_BLADES, RunBuild.PULSE_CORE,
			&"dash_nova", &"ramjet_mass", &"phase_shell", &"dash_echo",
			&"drift_edge", &"kinetic_repair",
		]
	elif _strategy == "stormtrail":
		preference = [
			&"twin_current", RunBuild.HUNTER_ARRAY, RunBuild.REDLINE_CORE,
			&"slipstream", &"wake_voltage", &"wake_width", &"wake_duration",
			&"parallel_flow", &"hunter_guidance", &"kinetic_repair",
		]
	elif _strategy == "tempest_anchor":
		preference = [
			&"tempest_anchor", RunBuild.DRIFT_BLADES, RunBuild.REDLINE_CORE,
			&"slipstream", &"storm_charge", &"wake_voltage", &"wake_width",
			&"wake_duration", &"drift_edge", &"kinetic_repair",
		]
	elif _strategy == "arc_orbit":
		preference = [
			&"arc_orbit", RunBuild.DRIFT_BLADES, RunBuild.REDLINE_CORE,
			&"velocity_coil", &"orbit_flux", &"arc_payload", &"arc_capacitor",
			&"drift_edge", &"kinetic_repair",
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
