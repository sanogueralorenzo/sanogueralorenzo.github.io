extends SceneTree

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene: Node = load("res://main.tscn").instantiate()
	scene.set_meta("overrush_manual_start", true)
	scene.set_meta("overrush_disable_persistence", true)
	scene.get_node("World").seed = 41001
	root.add_child(scene)
	await process_frame
	var runner: CharacterBody3D = scene.get_node("RunnerBall")
	var visual_core: SphereMesh = runner.ball_mesh.mesh
	var collision_sphere: SphereShape3D = runner.get_node("CollisionShape3D").shape
	_expect(visual_core.radius < collision_sphere.radius, "The luminous core should leave room for the gyro shell inside the honest collision silhouette.")
	_expect(is_instance_valid(runner._runner_frame), "The runner should build a dedicated directional frame independently of its collision body.")
	_expect(runner._roll_bands.size() == 2 and runner._directional_fins.size() == 2, "The runner should replace the plain-sphere silhouette with gyro bands and paired vector fins.")
	_expect(is_instance_valid(runner._runner_frame.get_node("DirectionNeedle")) and is_instance_valid(runner._dash_ring), "The runner should visibly communicate forward direction and local dash state.")
	_expect((runner._roll_bands[0].material_override as StandardMaterial3D).no_depth_test and runner._dash_ring_material.no_depth_test, "Only the thin orientation shell should remain readable through close enemy overlap.")

	runner.velocity = Vector3(80.0, 0.0, 0.0)
	runner.heading = Vector3.RIGHT
	var initial_band_rotation: Vector3 = runner._roll_bands[0].global_rotation
	runner._roll_visual(0.05)
	runner._update_runner_frame(0.25, 1.0)
	_expect(absf(angle_difference(runner._runner_frame.rotation.y, -PI * 0.5)) < 0.08, "The directional frame should point along actual travel rather than remaining camera-facing.")
	_expect(runner._runner_frame.rotation.z > 0.15, "Steering should produce a readable, velocity-preserving bank.")
	_expect(runner._roll_bands[0].global_rotation.distance_to(initial_band_rotation) > 0.05, "The gyro shell should retain visible ground-speed roll.")
	_expect(runner._directional_fins[0].scale.z > 1.0, "Vector fins should lengthen subtly with speed.")

	runner._dash_state.cooldown_remaining = runner.dash_cooldown
	runner._set_dash_visuals(false)
	_expect(runner._dash_ring.scale.x < 0.9 and runner._dash_ring_material.emission_energy_multiplier <= 0.31, "The local ring should visibly empty while dash recovery is unavailable.")
	runner._begin_dash()
	runner._update_runner_frame(0.25, 0.0)
	_expect(runner._dash_ring.scale.x > 1.15 and runner._dash_ring_material.emission_energy_multiplier > 4.0, "Dashing should expand and brighten the local charge ring without relying on HUD text.")
	runner.set_reduced_motion(true)
	var reduced_rotation: Vector3 = runner.ball_mesh.rotation
	runner._roll_visual(0.25)
	runner._update_runner_frame(0.25, 1.0)
	_expect(runner.ball_mesh.rotation.is_equal_approx(reduced_rotation), "Reduced motion should stop high-frequency gyro roll.")
	_expect(absf(runner._runner_frame.rotation.z) < 0.02, "Reduced motion should remove runner banking while retaining its directional silhouette.")
	_expect(not runner.dash_trail.emitting and runner._dash_ring.scale.x <= 1.081, "Reduced motion should replace the particle burst with a restrained ring state.")

	paused = false
	scene.queue_free()
	await process_frame
	if _failures.is_empty():
		print("Runner presentation validation passed — direction, speed, dash charge, and reduced-motion states agree.")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
