extends SceneTree

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene: Node = load("res://freeride.tscn").instantiate()
	scene.set_meta(&"overrush_manual_start", true)
	scene.get_node("Desert").seed = 41777
	root.add_child(scene)
	await process_frame
	var rider: Sandboarder = scene.get_node("Sandboarder")
	var camera: Camera3D = scene.get_node("FollowCamera")

	_expect(paused and not scene.run_active, "The launch screen should hold the world still before a run.")
	for control_path in [
		"HUD/StartOverlay/LaunchPanel/Content/ReducedMotion",
		"HUD/StartOverlay/LaunchPanel/Content/LookSensitivity/Slider",
		"HUD/StartOverlay/LaunchPanel/Content/MasterVolume/Slider",
		"HUD/PauseOverlay/PausePanel/Content/ReducedMotion",
		"HUD/PauseOverlay/PausePanel/Content/LookSensitivity/Slider",
		"HUD/PauseOverlay/PausePanel/Content/MasterVolume/Slider",
	]:
		_expect(scene.get_node_or_null(control_path) is Control, "A core accessibility control is missing: %s." % control_path)
	var settings_test_path := "user://overrush_settings_test.cfg"
	_expect(scene.save_settings(settings_test_path) == OK, "Accessibility preferences should save reliably.")
	scene.set_accessibility_settings(true, 1.4, 0.35, false)
	_expect(scene.save_settings(settings_test_path) == OK, "Changed accessibility preferences should save reliably.")
	scene.set_accessibility_settings(false, 0.7, 0.9, false)
	_expect(scene.load_settings(settings_test_path), "Saved accessibility preferences should load reliably.")
	_expect(camera._reduced_motion, "Reduced motion must immediately disable camera speed displacement.")
	_expect(is_equal_approx(camera.get_look_sensitivity_multiplier(), 1.4), "Look sensitivity must apply to mouse and gamepad camera input.")
	_expect(is_equal_approx(scene.audio_director.master_level, 0.35), "Master volume must apply to all movement audio.")
	_expect(
		scene.start_reduced_motion.button_pressed == scene.pause_reduced_motion.button_pressed
			and is_equal_approx(scene.start_look_sensitivity.value, scene.pause_look_sensitivity.value)
			and is_equal_approx(scene.start_master_volume.value, scene.pause_master_volume.value),
		"Launch and pause accessibility controls must remain synchronized.",
	)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(settings_test_path))
	scene.begin_run()
	_expect(not paused and scene.run_active and camera._controls_enabled, "Starting should resume physics and camera control.")
	scene.pause_run()
	_expect(paused and scene.get_node("HUD/PauseOverlay").visible, "Pause should stop the run and show its focused overlay.")
	_expect(not camera._controls_enabled, "Pause should release camera control.")
	scene.resume_run()
	_expect(not paused and camera._controls_enabled, "Resume should restore the same run and camera control.")

	scene.elapsed_time = 42.0
	rider.distance_traveled = 900.0
	rider.velocity = Vector3(30.0, 5.0, -18.0)
	rider.global_position += Vector3(90.0, 25.0, -120.0)
	rider.air_boost_state.leave_surface()
	rider.air_boost_state.try_use()
	scene.restart_run()
	_expect(is_zero_approx(scene.elapsed_time), "Restart should reset elapsed time.")
	_expect(is_zero_approx(rider.distance_traveled) and rider.velocity.is_zero_approx(), "Restart should reset distance and momentum.")
	_expect(rider.global_position.is_equal_approx(scene.desert.get_spawn_position()), "Restart should return to the current summit spawn.")
	_expect(rider.air_boost_state.available and not rider.air_boost_state.airborne, "Restart should restore one grounded air boost.")
	_expect(not paused and not scene.get_node("HUD/PauseOverlay").visible, "Restart should return directly to an active run.")

	paused = false
	scene.queue_free()
	await process_frame
	if _failures.is_empty():
		print("Freeride pause/restart passed — persistent accessibility, launch, pause, resume, and summit reset remain coherent.")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
