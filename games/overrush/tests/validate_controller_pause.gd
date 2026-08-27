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
	_expect("LEFT STICK" in scene.controls.text and "START PAUSE" in scene.controls.text, "The contextual reminder should describe the complete gamepad movement loop.")

	scene._profile.onboarding_completed = true
	scene.begin_run(RunProtocolCatalog.STANDARD)
	await process_frame
	_expect(not paused and scene._run_started, "Launching should resume the simulation.")
	_expect(scene.controls.visible and not scene.tutorial_card.visible, "Returning players should receive one compact control refresher instead of replaying onboarding.")
	var design_integrity_left: float = 1280.0 * 0.5 + scene.integrity_bar.offset_left
	_expect(scene.controls.offset_right < design_integrity_left, "The compact refresher should not overlap the centered integrity HUD at the 1280×720 design resolution.")
	scene._update_control_reminder(scene.CONTROL_REMINDER_SECONDS)
	_expect(not scene.controls.visible, "The returning-player control refresher should retire after a bounded opening window.")
	_expect("APEX IN" in scene.run_stats.text and "SEED" not in scene.run_stats.text, "The live HUD should prioritize the win-condition countdown over developer-facing seed data.")
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
	_expect("LEFT STICK" in scene.pause_hint.text and "LB/RB DASH" in scene.pause_hint.text, "Pause should retain the complete movement reference after the live refresher retires.")
	var pause_panel: Control = scene.get_node("HUD/PauseOverlay/PausePanel")
	var pause_content: Control = scene.get_node("HUD/PauseOverlay/PausePanel/Content")
	_expect(pause_content.get_global_rect().end.y <= pause_panel.get_global_rect().end.y - 32.0, "The pause summary, controls, and safe actions should fit inside the panel without clipping.")
	_expect("OPEN CIRCUIT" not in scene.pause_summary.text, "The pause summary should describe the current run state rather than repeat launch copy.")
	_expect("APEX IN" in scene.pause_summary.text and "SEED" in scene.pause_summary.text, "Pause should preserve objective context and move the reproducible world seed out of the live HUD.")

	scene._open_settings(true)
	await process_frame
	_expect(scene.settings_overlay.visible and not scene.pause_overlay.visible, "Accessibility and audio settings should be available without abandoning a run.")
	_expect(scene.settings_back_button.text == "BACK TO PAUSE", "Mid-run settings should make their return destination explicit.")
	_expect(scene.get_viewport().gui_get_focus_owner() == scene.master_volume_slider, "Settings should begin at the first audio control for predictable controller navigation.")
	var settings_panel: Control = scene.get_node("HUD/SettingsOverlay/SettingsPanel")
	var settings_content: Control = scene.get_node("HUD/SettingsOverlay/SettingsPanel/Content")
	_expect(settings_content.get_global_rect().end.y <= settings_panel.get_global_rect().end.y - 32.0, "The complete audio and comfort control stack should fit inside the settings panel without clipping.")
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
