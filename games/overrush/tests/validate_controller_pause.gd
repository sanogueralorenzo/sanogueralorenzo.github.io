extends SceneTree

const RunProtocolCatalog = preload("res://scripts/run_protocols.gd")
const InputBindings = preload("res://scripts/input_bindings.gd")

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene: Node = load("res://main.tscn").instantiate()
	scene.set_meta("overrush_manual_start", true)
	scene.set_meta("overrush_disable_persistence", true)
	scene.get_node("World").seed = 681240
	root.add_child(scene)
	await process_frame
	await process_frame

	_expect(paused and scene.start_overlay.visible, "The launch screen should hold simulation until the player confirms a run.")
	_expect(scene.get_viewport().gui_get_focus_owner() == scene.launch_button, "The primary launch action should receive initial controller focus.")

	scene._available_protocols = RunProtocolCatalog.ORDER.duplicate()
	scene._protocol_index = 0
	scene._refresh_launch_screen()
	await _push_joy_button(JOY_BUTTON_DPAD_RIGHT)
	_expect(scene._using_gamepad, "Controller input should switch every contextual prompt to gamepad language.")
	_expect(scene._protocol_index == 1, "D-pad input should cycle run protocols even while the launch button owns focus.")
	_expect("D-PAD" in scene.select_hint.text and "A TO LAUNCH" in scene.launch_hint.text, "The launch screen should explain controller selection and confirmation.")
	_expect("LEFT STICK" in scene.controls.text and "START pause" in scene.controls.text, "The live controls legend should describe the complete gamepad movement loop.")

	scene.begin_run(RunProtocolCatalog.STANDARD)
	await process_frame
	_expect(not paused and scene._run_started, "Launching should resume the simulation.")
	var runner: CharacterBody3D = scene.get_node("RunnerBall")
	paused = true
	var heading_before: Vector3 = runner.heading
	Input.action_press(InputBindings.MOVE_LEFT, 0.5)
	runner._physics_process(0.1)
	Input.action_release(InputBindings.MOVE_LEFT)
	_expect(runner.heading.distance_to(heading_before) > 0.001, "Analog action strength should steer the live runner.")
	Input.action_press(InputBindings.DASH)
	runner._physics_process(0.016)
	Input.action_release(InputBindings.DASH)
	_expect(runner.is_dashing(), "Either controller shoulder action should reach the live dash state.")
	paused = false
	await _push_joy_button(JOY_BUTTON_START)
	_expect(paused and scene.pause_overlay.visible, "Start should suspend an active run behind a dedicated pause overlay.")
	_expect(scene.get_viewport().gui_get_focus_owner() == scene.pause_resume_button, "Resume should be the safe default pause action.")
	_expect("OPEN CIRCUIT" not in scene.pause_summary.text, "The pause summary should describe the current run state rather than repeat launch copy.")

	scene._open_settings(true)
	_expect(scene.settings_overlay.visible and not scene.pause_overlay.visible, "Accessibility and audio settings should be available without abandoning a run.")
	_expect(scene.settings_back_button.text == "BACK TO PAUSE", "Mid-run settings should make their return destination explicit.")
	scene._close_settings()
	_expect(scene.pause_overlay.visible and paused, "Leaving mid-run settings should return to the still-paused run.")

	scene._request_restart()
	_expect(scene._restart_armed and scene.pause_restart_button.text == "CONFIRM RESTART", "Restart should require a second deliberate confirmation.")
	_expect(not scene._run_recorded, "Arming restart should not log or mutate run progression.")
	scene._resume_run()
	_expect(not paused and not scene.pause_overlay.visible, "Resume should restore the active run.")
	_expect(not scene._restart_armed and scene.pause_restart_button.text == "RESTART RUN", "Leaving pause should cancel stale restart confirmation.")

	scene.get_node("CombatDirector").stop_run()
	paused = false
	scene.queue_free()
	await process_frame
	if _failures.is_empty():
		print("Controller and pause validation passed — prompts, focus, settings, resume, and safe restart agree.")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _push_joy_button(button: JoyButton) -> void:
	var pressed_event := InputEventJoypadButton.new()
	pressed_event.button_index = button
	pressed_event.pressed = true
	root.push_input(pressed_event)
	await process_frame
	var released_event := InputEventJoypadButton.new()
	released_event.button_index = button
	released_event.pressed = false
	root.push_input(released_event)
	await process_frame


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
