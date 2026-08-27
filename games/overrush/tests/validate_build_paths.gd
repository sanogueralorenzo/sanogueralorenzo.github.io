extends SceneTree

const RunBuildScript = preload("res://scripts/run_build.gd")

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await _validate_dashbreaker()
	await _validate_stormtrail()
	await _validate_arcstorm()
	if _failures.is_empty():
		print("Build path validation passed — dash endpoints, persistent wakes, and chain arcs all defeat threats.")
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


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
