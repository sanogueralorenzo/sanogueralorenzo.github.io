extends SceneTree

const RunBuildScript = preload("res://scripts/run_build.gd")
const RunProtocolCatalog = preload("res://scripts/run_protocols.gd")

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene: Node = load("res://main.tscn").instantiate()
	scene.set_meta("overrush_disable_persistence", true)
	scene.get_node("World").seed = 120191
	root.add_child(scene)
	await process_frame
	await process_frame
	var director: CombatDirector = scene.get_node("CombatDirector")
	var runner: CharacterBody3D = scene.get_node("RunnerBall")
	director.stop_run()
	for enemy in director._enemies:
		if is_instance_valid(enemy):
			enemy.queue_free()
	director._enemies.clear()
	director._run_active = true
	director.run_stats.reset(runner.global_position)

	var hunter_target := _place_target(director, runner.global_position + runner.heading * 18.0)
	director.build = _arsenal_build(RunBuild.HUNTER_ARRAY, &"hunter_guidance")
	director._arsenal_timer = 0.0
	director._update_arsenal(0.1)
	for _frame in range(20):
		await process_frame
	_expect(float(director.run_stats.damage_by_source.get(&"hunter_array", 0.0)) > 0.0, "Hunter Array missiles should home into distant threats and retain their own telemetry source.")
	if is_instance_valid(hunter_target):
		hunter_target.queue_free()
	await process_frame

	var drift_target := _place_target(director, runner.global_position + Vector3(4.0, 0.0, 0.0))
	director.build = _arsenal_build(RunBuild.DRIFT_BLADES, &"drift_edge")
	director._arsenal_timer = 0.0
	director._update_arsenal(0.1)
	_expect(float(director.run_stats.damage_by_source.get(&"drift_blades", 0.0)) > 0.0, "Drift Blades should reward close pack threading with an immediate cutting field.")
	if is_instance_valid(drift_target):
		drift_target.queue_free()
	await process_frame

	var mine_target := _place_target(director, runner.global_position + Vector3(5.0, 0.0, 0.0))
	director.build = _arsenal_build(RunBuild.BACKDRAFT_MINE, &"backdraft_charge")
	director._drop_backdraft_mine(runner.global_position)
	await create_timer(0.5).timeout
	_expect(float(director.run_stats.damage_by_source.get(&"backdraft_mine", 0.0)) > 0.0, "Backdraft Mine should preserve its delayed dash-exit detonation and telemetry source.")
	if is_instance_valid(mine_target):
		mine_target.queue_free()

	director.stop_run()
	paused = false
	scene.queue_free()
	await process_frame
	if _failures.is_empty():
		print("Arsenal validation passed — ranged pursuit, close threading, delayed dash traps, supports, and telemetry are distinct.")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _arsenal_build(arsenal_id: StringName, support_id: StringName) -> RunBuild:
	var build: RunBuild = RunBuildScript.new()
	build.arsenal_id = arsenal_id
	match support_id:
		&"hunter_guidance":
			build.hunter_guidance_level = 1
		&"drift_edge":
			build.drift_edge_level = 1
		&"backdraft_charge":
			build.backdraft_charge_level = 1
	return build


func _place_target(director: CombatDirector, position: Vector3) -> EnemyAgent:
	var enemy := director._spawn_enemy(&"pursuer")
	enemy.global_position = position
	enemy.global_position.y = director._world.get_surface_height(position.x, position.z) + enemy.body_radius
	return enemy


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
