extends SceneTree

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene: Node = load("res://main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await create_timer(2.1).timeout

	var director: CombatDirector = scene.get_node("CombatDirector")
	var runner: CharacterBody3D = scene.get_node("RunnerBall")
	_expect(director.get_enemy_count() > 0, "The combat director should populate the terrain with threats.")

	if director.get_enemy_count() > 0:
		var enemy: EnemyAgent = director._enemies[0]
		enemy.health = 1.0
		var runner_heading: Vector3 = runner.heading.normalized()
		enemy.global_position = runner.global_position + runner_heading * 11.0
		enemy.global_position.y = runner.global_position.y
		await create_timer(1.0).timeout
		_expect(director.enemies_defeated > 0, "The automatic arc weapon should acquire and defeat a nearby threat.")

	director._on_experience_collected(12)
	await process_frame
	_expect(paused, "Level-up decisions should pause combat.")
	_expect(scene.get_node("HUD/LevelUpOverlay").visible, "A level-up should present three readable choices.")
	director.choose_upgrade(0)
	await process_frame
	_expect(not paused, "Choosing an upgrade should resume the run.")
	_expect(director.build.dash_nova_level == 1, "The selected first upgrade should alter the active build.")

	director._spawn_enemy()
	var dash_target: EnemyAgent = director._enemies.back()
	dash_target.health = 10.0
	dash_target.global_position = runner.global_position + Vector3.RIGHT * 5.0
	var defeats_before_nova := director.enemies_defeated
	director._on_dash_state_changed(true)
	await process_frame
	_expect(director.enemies_defeated > defeats_before_nova, "Dash Nova should convert a movement action into immediate area damage.")

	director.stop_run()
	paused = false
	scene.queue_free()
	if _failures.is_empty():
		print("Combat slice integration validation passed.")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
