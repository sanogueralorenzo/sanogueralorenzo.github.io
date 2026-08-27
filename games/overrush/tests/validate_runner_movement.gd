extends SceneTree

const InputBindings = preload("res://scripts/input_bindings.gd")

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	InputBindings.ensure_actions()
	Input.action_release(InputBindings.BOOST)
	Input.action_release(InputBindings.BRAKE)

	var scene: Node = load("res://main.tscn").instantiate()
	scene.set_meta("overrush_manual_start", true)
	scene.get_node("World").seed = 31904
	root.add_child(scene)
	await process_frame

	var runner: CharacterBody3D = scene.get_node("RunnerBall")
	scene.get_node("CombatDirector").stop_run()
	_expect(is_zero_approx(runner.get_drive_target_speed(0.0)), "Neutral input should have no hidden cruise speed.")
	_expect(is_equal_approx(runner.get_drive_target_speed(1.0), runner.boost_speed), "Full forward input should still reach boost speed.")

	runner.velocity = Vector3.RIGHT * runner.cruise_speed
	await physics_frame
	await process_frame
	_expect(runner.get_horizontal_speed() < 0.01, "Releasing forward should stop horizontal movement on the next physics frame.")

	Input.action_press(InputBindings.BOOST)
	for _index in range(30):
		await physics_frame
	_expect(runner.get_horizontal_speed() > 4.0, "Holding forward should accelerate the runner from rest.")
	Input.action_release(InputBindings.BOOST)
	await physics_frame
	await process_frame
	_expect(runner.get_horizontal_speed() < 0.01, "Releasing forward after driving should stop immediately instead of coasting like a ball.")

	runner.velocity = Vector3.FORWARD * runner.cruise_speed
	runner.respawn(scene.get_node("World").get_spawn_position())
	_expect(runner.get_horizontal_speed() < 0.01, "Respawning without forward input should leave the runner stopped.")

	Input.action_release(InputBindings.BOOST)
	Input.action_release(InputBindings.BRAKE)
	scene.queue_free()
	await process_frame
	if _failures.is_empty():
		print("Runner movement validation passed — forward drives, neutral stops immediately, and respawn stays still.")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
