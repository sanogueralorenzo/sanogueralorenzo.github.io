extends SceneTree

const RunBuildScript = preload("res://scripts/run_build.gd")

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await _validate_dashbreaker()
	await _validate_stormtrail()
	await _validate_arcstorm()
	await _validate_dashbreaker_evolutions()
	await _validate_stormtrail_evolutions()
	await _validate_arcstorm_evolutions()
	if _failures.is_empty():
		print("Build path validation passed — all three engines and six exclusive evolution geometries defeat threats.")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _create_test_scene(seed: int) -> Node:
	var scene: Node = load("res://main.tscn").instantiate()
	scene.get_node("World").seed = seed
	root.add_child(scene)
	await process_frame
	var director: CombatDirector = scene.get_node("CombatDirector")
	director.stop_run()
	return scene


func _dispose_scene(scene: Node) -> void:
	paused = false
	scene.queue_free()
	await process_frame


func _validate_dashbreaker() -> void:
	var scene := await _create_test_scene(41001)
	var director: CombatDirector = scene.get_node("CombatDirector")
	var runner: CharacterBody3D = scene.get_node("RunnerBall")
	director.build = RunBuildScript.new()
	director.build.apply_upgrade(&"dash_nova")
	director.build.apply_upgrade(&"dash_echo")
	director.build.apply_upgrade(&"phase_shell")
	director._run_active = true

	var entry_target: EnemyAgent = director._spawn_enemy(&"pursuer")
	entry_target.health = 10.0
	entry_target.global_position = runner.global_position + Vector3.RIGHT * 7.0
	entry_target.global_position.y = runner.global_position.y
	var before_entry := director.enemies_defeated
	director._on_dash_state_changed(true)
	await process_frame
	_expect(director.enemies_defeated > before_entry, "Dashbreaker entry should defeat a nearby threat.")
	var recharge_target: EnemyAgent = director._spawn_enemy(&"pursuer")
	recharge_target.health = 10.0
	recharge_target.global_position = runner.global_position + Vector3.RIGHT * 8.0
	recharge_target.global_position.y = runner.global_position.y
	var before_recharge := director.enemies_defeated
	director._on_dash_state_changed(true)
	await process_frame
	_expect(
		director.enemies_defeated == before_recharge and is_instance_valid(recharge_target),
		"Dashbreaker should not detonate a full entry nova on every rapid dash."
	)
	director._dash_nova_recharge = 0.0
	director._on_dash_state_changed(true)
	await process_frame
	_expect(director.enemies_defeated > before_recharge, "Dashbreaker's entry nova should fire again once recharged.")
	var integrity_before: float = runner.integrity
	runner.take_damage(20.0)
	_expect(is_equal_approx(runner.integrity, integrity_before), "Phase Shell should prevent damage during the dash window.")

	var exit_target: EnemyAgent = director._spawn_enemy(&"pursuer")
	exit_target.health = 10.0
	exit_target.global_position = runner.global_position + Vector3.LEFT * 7.0
	exit_target.global_position.y = runner.global_position.y
	var before_exit := director.enemies_defeated
	director._on_dash_state_changed(false)
	await process_frame
	_expect(director.enemies_defeated > before_exit, "Exit Wound should defeat a threat at the dash endpoint.")
	director.stop_run()
	await _dispose_scene(scene)


func _validate_stormtrail() -> void:
	var scene := await _create_test_scene(48920)
	var director: CombatDirector = scene.get_node("CombatDirector")
	var runner: CharacterBody3D = scene.get_node("RunnerBall")
	director.build = RunBuildScript.new()
	director.build.apply_upgrade(&"slipstream")
	director.build.apply_upgrade(&"wake_duration")
	director.build.apply_upgrade(&"wake_width")

	var wake_position: Vector3 = runner.global_position - runner.heading.normalized() * 10.0
	var wake_target: EnemyAgent = director._spawn_enemy(&"pursuer")
	wake_target.health = 5.0
	wake_target.movement_speed = 0.0
	wake_target.global_position = wake_position
	director._update_slipstream(1.0)
	await create_timer(0.2).timeout
	_expect(director.enemies_defeated > 0, "A persistent Stormtrail wake should damage a threat crossing the route behind the runner.")
	_expect(not director.build.is_arc_weapon_enabled(), "Stormtrail should win through route control rather than the default auto-arc.")
	await _dispose_scene(scene)


func _validate_arcstorm() -> void:
	var scene := await _create_test_scene(56839)
	var director: CombatDirector = scene.get_node("CombatDirector")
	var runner: CharacterBody3D = scene.get_node("RunnerBall")
	director.build = RunBuildScript.new()
	director.build.apply_upgrade(&"velocity_coil")
	director.build.apply_upgrade(&"arc_chain")
	var first_target: EnemyAgent = director._spawn_enemy(&"pursuer")
	var second_target: EnemyAgent = director._spawn_enemy(&"pursuer")
	first_target.health = 8.0
	second_target.health = 8.0
	first_target.movement_speed = 0.0
	second_target.movement_speed = 0.0
	first_target.global_position = runner.global_position + runner.heading.normalized() * 14.0
	second_target.global_position = first_target.global_position + Vector3.RIGHT * 9.0
	director._update_arc_weapon(1.0)
	await create_timer(0.7).timeout
	_expect(director.enemies_defeated >= 2, "One Arcstorm bolt should chain between two nearby threats.")
	_expect(director.build.is_arc_weapon_enabled(), "Arcstorm should retain ranged automatic targeting.")
	await _dispose_scene(scene)


func _validate_dashbreaker_evolutions() -> void:
	var scene := await _create_test_scene(64758)
	var director: CombatDirector = scene.get_node("CombatDirector")
	var runner: CharacterBody3D = scene.get_node("RunnerBall")
	director._run_active = true
	director.build = _evolved_build(&"dash_nova", &"ramjet", &"ramjet_mass")
	var ram_target: EnemyAgent = director._spawn_enemy(&"pursuer")
	ram_target.health = 18.0
	ram_target.movement_speed = 0.0
	ram_target.global_position = runner.global_position + Vector3.RIGHT * 2.0
	ram_target.global_position.y = runner.global_position.y
	runner._dash_state.is_active = true
	director._dash_hit_ids.clear()
	var defeats_before_ram := director.enemies_defeated
	director._update_ramjet()
	await process_frame
	_expect(director.enemies_defeated > defeats_before_ram, "Ramjet should turn the moving dash body into a once-per-target collision weapon.")
	runner._dash_state.is_active = false
	await _clear_director_children(director)

	director.build = _evolved_build(&"dash_nova", &"gravity_knot", &"event_horizon")
	var knot_target: EnemyAgent = director._spawn_enemy(&"bulwark")
	knot_target.health = 24.0
	knot_target.movement_speed = 0.0
	knot_target.global_position = runner.global_position + Vector3.RIGHT * 24.0
	knot_target.global_position.y = runner.global_position.y
	var distance_before := knot_target.global_position.distance_to(runner.global_position)
	var defeats_before_knot := director.enemies_defeated
	director._on_dash_state_changed(false)
	var distance_after_pull := knot_target.global_position.distance_to(runner.global_position)
	_expect(distance_after_pull < distance_before * 0.7, "Gravity Knot should pull nearby threats toward the dash endpoint before damage resolves.")
	await create_timer(0.45).timeout
	_expect(director.enemies_defeated > defeats_before_knot, "Gravity Knot's delayed collapse should damage the clustered threat.")
	await _dispose_scene(scene)


func _validate_stormtrail_evolutions() -> void:
	var scene := await _create_test_scene(72677)
	var director: CombatDirector = scene.get_node("CombatDirector")
	var runner: CharacterBody3D = scene.get_node("RunnerBall")
	director.build = _evolved_build(&"slipstream", &"twin_current", &"parallel_flow")
	director._update_slipstream(1.0)
	var twin_wakes: Array[SlipstreamWake] = []
	for child in director.get_children():
		if child is SlipstreamWake:
			twin_wakes.append(child)
	_expect(twin_wakes.size() == 2, "Twin Current should replace the center wake with two separated traversal lanes.")
	if twin_wakes.size() == 2:
		_expect(twin_wakes[0].global_position.distance_to(twin_wakes[1].global_position) > 16.0, "Twin Current lanes should be spatially distinct enough to reward weaving.")
	await _clear_director_children(director)

	director.build = _evolved_build(&"slipstream", &"tempest_anchor", &"storm_charge")
	director._wake_drop_count = director.build.get_anchor_stride() - 1
	director._wake_timer = 0.0
	director._update_slipstream(1.0)
	var anchor: SlipstreamWake
	for child in director.get_children():
		if child is SlipstreamWake:
			anchor = child
			break
	_expect(anchor != null and anchor.repeat_interval > 0.0, "Tempest Anchor should periodically create a persistent, repeating damage zone.")
	if anchor != null:
		var anchor_target: EnemyAgent = director._spawn_enemy(&"pursuer")
		anchor_target.health = anchor.damage * 1.5
		anchor_target.movement_speed = 0.0
		anchor_target.global_position = anchor.global_position
		await create_timer(anchor.repeat_interval * 2.4).timeout
		_expect(not is_instance_valid(anchor_target) or anchor_target.is_queued_for_deletion(), "A Tempest Anchor should be able to strike the same stationary threat more than once.")
	await _dispose_scene(scene)


func _validate_arcstorm_evolutions() -> void:
	var scene := await _create_test_scene(104353)
	var director: CombatDirector = scene.get_node("CombatDirector")
	var runner: CharacterBody3D = scene.get_node("RunnerBall")
	director.build = _evolved_build(&"velocity_coil", &"storm_lance", &"lance_focus")
	var lance_defeats_before := director.enemies_defeated
	for distance in [24.0, 48.0, 72.0]:
		var target: EnemyAgent = director._spawn_enemy(&"pursuer")
		target.health = 28.0
		target.movement_speed = 0.0
		target.global_position = runner.global_position + runner.heading.normalized() * distance
		target.global_position.y = runner.global_position.y
	var behind_target: EnemyAgent = director._spawn_enemy(&"pursuer")
	behind_target.health = 28.0
	behind_target.movement_speed = 0.0
	behind_target.global_position = runner.global_position - runner.heading.normalized() * 20.0
	behind_target.global_position.y = runner.global_position.y
	director._fire_timer = 0.0
	director._update_arc_weapon(1.0)
	await process_frame
	_expect(director.enemies_defeated >= lance_defeats_before + 3, "Storm Lance should pierce a lined-up pack in the runner's heading.")
	_expect(is_instance_valid(behind_target) and behind_target.health > 0.0, "Storm Lance should reward facing instead of hitting enemies behind the runner.")
	await _clear_director_children(director)
	var residual_target: EnemyAgent = director._spawn_enemy(&"pursuer")
	residual_target.health = 12.0
	residual_target.movement_speed = 0.0
	residual_target.global_position = runner.global_position + runner.heading.normalized() * 34.0 + Vector3.RIGHT * 32.0
	residual_target.global_position.y = runner.global_position.y
	var residual_defeats_before := director.enemies_defeated
	director._fire_timer = 0.0
	director._update_arc_weapon(1.0)
	await create_timer(0.7).timeout
	_expect(director.enemies_defeated > residual_defeats_before, "A missed Storm Lance lane should preserve one residual auto-arc instead of wasting its cycle.")
	await _clear_director_children(director)

	director.build = _evolved_build(&"velocity_coil", &"arc_orbit", &"orbit_flux")
	var orbit_defeats_before := director.enemies_defeated
	for offset in [Vector3.RIGHT * 8.0, Vector3.LEFT * 12.0, runner.heading.normalized() * 16.0]:
		var target: EnemyAgent = director._spawn_enemy(&"pursuer")
		target.health = 12.0
		target.movement_speed = 0.0
		target.global_position = runner.global_position + offset
		target.global_position.y = runner.global_position.y
	var distant_target: EnemyAgent = director._spawn_enemy(&"pursuer")
	distant_target.health = 12.0
	distant_target.movement_speed = 0.0
	distant_target.global_position = runner.global_position + Vector3.RIGHT * 50.0
	distant_target.global_position.y = runner.global_position.y
	director._fire_timer = 0.0
	director._update_arc_weapon(1.0)
	await process_frame
	_expect(director.enemies_defeated >= orbit_defeats_before + 3, "Arc Orbit should clear nearby threats in every direction.")
	_expect(is_instance_valid(distant_target) and distant_target.health > 0.0, "Arc Orbit should trade ranged safety for close traversal pressure.")
	await _dispose_scene(scene)


func _evolved_build(keystone: StringName, evolution: StringName, support: StringName) -> RunBuild:
	var build: RunBuild = RunBuildScript.new()
	for _rank in range(RunBuild.EVOLUTION_UNLOCK_RANK):
		build.apply_upgrade(keystone)
	build.apply_upgrade(evolution)
	build.apply_upgrade(support)
	return build


func _clear_director_children(director: CombatDirector) -> void:
	for child in director.get_children():
		child.queue_free()
	director._enemies.clear()
	await process_frame


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
