extends SceneTree

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene: Node = load("res://main.tscn").instantiate()
	scene.get_node("World").seed = 41001
	root.add_child(scene)
	await process_frame

	var world: Node3D = scene.get_node("World")
	var runner: CharacterBody3D = scene.get_node("RunnerBall")
	var boundary: WorldBoundary = scene.get_node("WorldBoundary")
	var combat: CombatDirector = scene.get_node("CombatDirector")
	combat.stop_run()
	runner.cruise_speed = 126.0
	runner.boost_speed = 126.0
	runner.heading = Vector3.FORWARD
	runner.velocity = Vector3.FORWARD * 126.0
	runner.global_position = Vector3(0.0, world.get_surface_height(0.0, -1220.0) + 4.0, -1220.0)
	Input.action_press(&"overrush_boost")

	var maximum_axis := 0.0
	var minimum_speed := INF
	var minimum_speed_frame := -1
	var minimum_speed_position := Vector3.ZERO
	var peak_pressure := 0.0
	for index in range(8 * 60):
		await physics_frame
		maximum_axis = maxf(maximum_axis, maxf(absf(runner.global_position.x), absf(runner.global_position.z)))
		var speed: float = runner.get_horizontal_speed()
		if speed < minimum_speed:
			minimum_speed = speed
			minimum_speed_frame = index
			minimum_speed_position = runner.global_position
		peak_pressure = maxf(peak_pressure, boundary.pressure)

	_expect(peak_pressure > 0.5, "The runtime boundary current should visibly engage before the terrain edge.")
	_expect(boundary.emergency_recoveries == 0, "Normal maximum-speed guidance should not need an emergency position correction.")
	_expect(maximum_axis < world.map_size * 0.5 - 24.0, "The runner should stay within the generated terrain at maximum speed.")
	_expect(minimum_speed > 92.0, "The boundary current should preserve momentum instead of stopping the runner; minimum was %.1f m/s at frame %d near %s." % [minimum_speed, minimum_speed_frame, str(minimum_speed_position)])
	_expect(runner.heading.dot(Vector3.FORWARD) < 0.72, "The current should produce a clear flowing turn along the perimeter.")

	Input.action_release(&"overrush_boost")
	paused = false
	scene.queue_free()
	if _failures.is_empty():
		print("Boundary runtime validation passed — max axis %.1f m, minimum speed %.1f m/s." % [maximum_axis, minimum_speed])
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
