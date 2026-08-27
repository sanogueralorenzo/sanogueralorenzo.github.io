extends SceneTree

const SAMPLE_SPEED := 58.0
const ROUTE_RADIUS := 700.0
const MAX_EVASION_OFFSET := 150.0

var _director: CombatDirector
var _runner: CharacterBody3D
var _world: Node3D
var _audit_seed := 41001
var _last_control_time := 0.0
var _next_dash_time := 0.0
var _next_pressure_time := 60.0
var _evasion_offset := Vector3.ZERO
var _outcome := ""
var _failures: Array[String] = []


func _init() -> void:
	var user_args := OS.get_cmdline_user_args()
	if not user_args.is_empty():
		_audit_seed = int(user_args[0])
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
	_director = scene.get_node("CombatDirector")
	_director.level_up_requested.connect(_choose_upgrade)
	_director.run_victory.connect(func() -> void: _outcome = "victory")
	_director.run_failed.connect(func(_reason: String) -> void: _outcome = "failure")
	_place_runner(Vector3(ROUTE_RADIUS, 0.0, 0.0), Vector3.FORWARD)
	scene.begin_run()
	while _director.elapsed_time < RunPacing.RUN_DURATION and _director._run_active:
		_apply_survival_route()
		await process_frame
	_apply_survival_route()
	print("STANDARD SURVIVAL elapsed=%.1f outcome=%s level=%d clears=%d integrity=%.1f/%.1f taken=%.1f repaired=%.1f cores=%d distance=%.0f dashes=%d milestones=%s" % [
		_director.elapsed_time,
		_outcome,
		_director.build.level,
		_director.enemies_defeated,
		_runner.integrity,
		_runner.maximum_integrity,
		_director.run_stats.damage_taken,
		_director.run_stats.integrity_recovered,
		_director.run_stats.recovery_pickups,
		_director.run_stats.distance_traveled,
		_director.run_stats.dash_count,
		str(_director.run_stats.get_build_milestone_times()),
	])
	print("STANDARD THREATS %s" % _director.run_stats.get_damage_taken_breakdown_text())
	_validate_result()
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	if _failures.is_empty():
		print("Survival soak passed — a finite-integrity Arcstorm run sustains controlled mistakes, earned recovery, traversal, and a complete ending.")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _apply_survival_route() -> void:
	var elapsed := _director.elapsed_time
	var delta := clampf(elapsed - _last_control_time, 0.0, 0.1)
	_last_control_time = elapsed
	var angular_speed := SAMPLE_SPEED / ROUTE_RADIUS
	var angle := elapsed * angular_speed
	var route_position := Vector3(cos(angle) * ROUTE_RADIUS, 0.0, sin(angle) * ROUTE_RADIUS)
	var threat := _get_threat_response()
	var desired_offset: Vector3 = threat.direction * MAX_EVASION_OFFSET * threat.urgency
	_evasion_offset = _evasion_offset.lerp(desired_offset, clampf(delta * 3.2, 0.0, 1.0))
	var desired_position := route_position + _evasion_offset
	var displacement: Vector3 = desired_position - _runner.global_position
	displacement.y = 0.0
	var travel_distance := minf(displacement.length(), SAMPLE_SPEED * maxf(delta, 0.001))
	var movement_heading: Vector3 = _runner.heading
	if displacement.length_squared() > 0.01:
		movement_heading = displacement.normalized()
	var next_position := _runner.global_position + movement_heading * travel_distance
	_place_runner(next_position, movement_heading)
	if bool(threat.imminent) and elapsed >= _next_dash_time:
		_runner.grant_damage_immunity(_runner.BASE_DASH_IMMUNITY_SECONDS)
		_director._on_dash_state_changed(true)
		_director._on_dash_state_changed(false)
		_next_dash_time = elapsed + 0.8
	_update_aim_heading()
	_apply_controlled_pressure()


func _apply_controlled_pressure() -> void:
	while _director._run_active and _director.elapsed_time >= _next_pressure_time:
		var phase_index := _director.pacing.get_phase_index(_next_pressure_time)
		var damage := 10.0 + phase_index * 2.0
		_runner._damage_invulnerability_remaining = 0.0
		_runner.take_damage(damage, _runner.global_position + Vector3.RIGHT, &"audit_pressure")
		_next_pressure_time += 45.0


func _get_threat_response() -> Dictionary:
	var response := Vector3.ZERO
	var urgency := 0.0
	var imminent := false
	for enemy in _director._enemies:
		if not is_instance_valid(enemy):
			continue
		var from_enemy: Vector3 = _runner.global_position - enemy.global_position
		from_enemy.y = 0.0
		var distance := from_enemy.length()
		if distance > 70.0 or distance < 0.01:
			continue
		var away := from_enemy / distance
		var proximity := clampf(1.0 - distance / 70.0, 0.0, 1.0)
		response += away * proximity * proximity
		urgency = maxf(urgency, proximity)
		if proximity >= 0.55 or distance < enemy.body_radius + 10.0:
			imminent = true
		if enemy.get_attack_state() == EnemyAgent.AttackState.CHASE:
			continue
		var from_attack: Vector3 = _runner.global_position - enemy._attack_center
		from_attack.y = 0.0
		var attack_distance := from_attack.length()
		var attack_radius: float = enemy._get_attack_radius()
		var warning_clearance: float = attack_radius + 20.0
		if attack_distance > warning_clearance or attack_distance < 0.01:
			continue
		var warning_urgency := clampf(1.0 - attack_distance / warning_clearance, 0.0, 1.0)
		response += from_attack / attack_distance * (1.5 + warning_urgency * 2.5)
		urgency = maxf(urgency, 0.55 + warning_urgency * 0.45)
		imminent = imminent or attack_distance <= attack_radius + 5.0
	return {
		"direction": response.normalized() if response.length_squared() > 0.001 else Vector3.ZERO,
		"urgency": clampf(urgency, 0.0, 1.0),
		"imminent": imminent,
	}


func _place_runner(position: Vector3, movement_heading: Vector3) -> void:
	position.y = _world.get_surface_height(position.x, position.z) + 2.0
	_runner.global_position = position
	_runner.apply_boundary_heading(movement_heading)
	_runner.velocity = movement_heading * SAMPLE_SPEED


func _update_aim_heading() -> void:
	var best_target: EnemyAgent
	var best_score := INF
	for enemy in _director._enemies:
		if not is_instance_valid(enemy):
			continue
		var target_direction: Vector3 = enemy.global_position - _runner.global_position
		target_direction.y = 0.0
		var distance := target_direction.length()
		if distance < 0.01 or distance > _director.TARGETING_RANGE:
			continue
		var angle := absf(_runner.heading.signed_angle_to(target_direction / distance, Vector3.UP))
		var score := angle + distance / _director.TARGETING_RANGE * 0.22
		if enemy.is_apex:
			score -= 4.0
		if score < best_score:
			best_score = score
			best_target = enemy
	if best_target == null:
		return
	var target_direction: Vector3 = best_target.global_position - _runner.global_position
	target_direction.y = 0.0
	if target_direction.length_squared() > 0.01:
		_runner.apply_boundary_heading(target_direction.normalized())


func _choose_upgrade(options: Array[StringName]) -> void:
	var preference: Array[StringName] = [
		&"storm_lance", RunBuild.HUNTER_ARRAY, RunBuild.REDLINE_CORE,
		&"velocity_coil", &"arc_payload", &"forked_current", &"arc_capacitor",
		&"arc_chain", &"lance_focus", &"hunter_guidance", &"kinetic_repair",
	]
	var choice := 0
	for upgrade_id in preference:
		var index := options.find(upgrade_id)
		if index >= 0:
			choice = index
			break
	_director.choose_upgrade(choice)


func _validate_result() -> void:
	_expect(_director.elapsed_time >= RunPacing.APEX_TIME, "A representative survival build should reach the Apex phase with finite integrity.")
	_expect(_runner.integrity > 0.0, "The survival sample should remain alive through its measured ending.")
	_expect(not _outcome.is_empty(), "The 20-minute sample should resolve through victory or a clear deadline ending.")
	_expect(_director.run_stats.damage_taken >= 250.0, "Controlled mistakes should create consequential pressure across the complete run.")
	_expect(_director.run_stats.integrity_recovered >= 180.0, "Earned recovery should make a measurable contribution across a full run.")
	_expect(_director.run_stats.recovery_pickups >= 12, "The full-run sample should exercise repeated recovery decisions.")
	_expect(_director.run_stats.distance_traveled >= 55000.0, "Survival should preserve Overrush's high-speed traversal identity.")
	_expect(_director.pacing.get_build_cadence_failures(_director.run_stats.get_build_milestone_times()).is_empty(), "A surviving build should reach every strategic milestone inside its authored cadence window.")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
