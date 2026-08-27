extends SceneTree

const InputBindings = preload("res://scripts/input_bindings.gd")

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	InputBindings.ensure_actions()
	_release_movement_actions()

	var scene: Node = load("res://main.tscn").instantiate()
	scene.set_meta("overrush_manual_start", true)
	scene.get_node("World").seed = 31904
	root.add_child(scene)
	await process_frame

	var runner: CharacterBody3D = scene.get_node("RunnerBall")
	var camera: Camera3D = scene.get_node("Camera3D")
	scene.get_node("CombatDirector").stop_run()
	_expect(is_zero_approx(runner.get_movement_target_speed(0.0)), "Neutral input should have no hidden cruise speed.")
	_expect(is_equal_approx(runner.get_movement_target_speed(1.0), runner.boost_speed), "Full directional input should still reach boost speed.")

	camera.set_orbit_angles(-PI * 0.5, deg_to_rad(25.0))
	var camera_forward: Vector3 = camera.get_planar_forward()
	var camera_right: Vector3 = camera.get_planar_right()
	_expect(runner.get_camera_relative_direction(Vector2.UP).dot(camera_forward) > 0.999, "Forward movement should follow the rotated camera, not a fixed world axis.")
	_expect(runner.get_camera_relative_direction(Vector2.RIGHT).dot(camera_right) > 0.999, "Right movement should follow the rotated camera's right axis.")
	_expect(runner.get_camera_relative_direction(Vector2.DOWN).dot(-camera_forward) > 0.999, "Backward movement should travel opposite the camera.")
	_expect(runner.get_camera_relative_direction(Vector2.LEFT).dot(-camera_right) > 0.999, "Left movement should support direct lateral travel.")

	runner.velocity = Vector3.RIGHT * runner.cruise_speed
	runner._physics_process(0.016)
	_expect(runner.get_horizontal_speed() < 0.01, "Releasing forward should stop horizontal movement on the next physics frame.")

	Input.action_press(InputBindings.MOVE_FORWARD)
	runner._physics_process(0.1)
	_expect(runner.get_horizontal_speed() > 1.0 and runner.heading.dot(camera_forward) > 0.999, "W or left-stick forward should move along the camera's facing direction.")
	Input.action_release(InputBindings.MOVE_FORWARD)
	Input.action_press(InputBindings.MOVE_BACKWARD)
	runner._physics_process(0.1)
	_expect(runner.heading.dot(-camera_forward) > 0.999, "S or left-stick back should move backward instead of acting as a brake.")
	Input.action_release(InputBindings.MOVE_BACKWARD)
	Input.action_press(InputBindings.MOVE_LEFT)
	runner._physics_process(0.1)
	_expect(runner.heading.dot(-camera_right) > 0.999, "A or left-stick left should strafe directly left.")
	Input.action_release(InputBindings.MOVE_LEFT)
	Input.action_press(InputBindings.MOVE_RIGHT)
	runner._physics_process(0.1)
	_expect(runner.heading.dot(camera_right) > 0.999, "D or left-stick right should strafe directly right.")
	Input.action_release(InputBindings.MOVE_RIGHT)
	runner._physics_process(0.016)
	_expect(runner.get_horizontal_speed() < 0.01, "Releasing directional input should stop immediately instead of preserving ball-like inertia.")

	var look_forward_before: Vector3 = camera.get_planar_forward()
	camera.set_controls_enabled(true)
	Input.action_press(InputBindings.LOOK_RIGHT)
	camera._physics_process(0.25)
	Input.action_release(InputBindings.LOOK_RIGHT)
	_expect(camera.get_planar_forward().distance_to(look_forward_before) > 0.2, "The right stick should rotate the camera independently of movement.")
	var stick_rotated_forward: Vector3 = camera.get_planar_forward()
	camera.apply_look_delta(Vector2(0.35, -0.1))
	_expect(camera.get_planar_forward().distance_to(stick_rotated_forward) > 0.2, "Mouse look should rotate the same independent camera orbit.")
	camera.set_controls_enabled(false)

	runner.velocity = Vector3.FORWARD * runner.cruise_speed
	runner.respawn(scene.get_node("World").get_spawn_position())
	_expect(runner.get_horizontal_speed() < 0.01, "Respawning without movement input should leave the runner stopped.")

	_release_movement_actions()
	scene.queue_free()
	await process_frame
	if _failures.is_empty():
		print("Runner movement validation passed — camera-relative movement, free look, immediate stops, and stationary respawn agree.")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _release_movement_actions() -> void:
	for action in [
		InputBindings.MOVE_LEFT,
		InputBindings.MOVE_RIGHT,
		InputBindings.MOVE_FORWARD,
		InputBindings.MOVE_BACKWARD,
		InputBindings.LOOK_LEFT,
		InputBindings.LOOK_RIGHT,
		InputBindings.LOOK_UP,
		InputBindings.LOOK_DOWN,
	]:
		Input.action_release(action)
