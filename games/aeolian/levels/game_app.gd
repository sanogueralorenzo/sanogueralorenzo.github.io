extends Node

const FOUNDATION_COURSE_PATH := "res://levels/foundation_course.tscn"

@onready var session_root: Node = %SessionRoot
@onready var title_screen: Control = %TitleScreen
@onready var pause_menu: Control = %PauseMenu

var _state := GameStateMachine.new()
var _active_session: Node
var _smoke_test_running := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_state.state_changed.connect(_on_state_changed)
	_state.transition_rejected.connect(_on_transition_rejected)
	title_screen.start_requested.connect(start_foundation_course)
	title_screen.quit_requested.connect(_quit_application)
	pause_menu.resume_requested.connect(resume_game)
	pause_menu.title_requested.connect(return_to_title)
	InputService.pause_requested.connect(_on_pause_requested)
	InputService.controller_disconnected.connect(_on_controller_disconnected)
	_state.transition(GameStateMachine.State.TITLE)
	AppLog.info(&"app", "Application ready", {
		"version": ProjectSettings.get_setting("application/config/version", "unknown"),
	})
	if "--movement-scene-test" in OS.get_cmdline_user_args():
		var movement_test := preload("res://tests/test_windboard_scene_runner.gd").new()
		add_child(movement_test)
		movement_test.run.call_deferred(self)
	elif "--smoke-test" in OS.get_cmdline_user_args():
		_smoke_test_running = true
		call_deferred("_run_smoke_test")
	elif OS.is_debug_build() and "--capture-smoke" in OS.get_cmdline_user_args():
		var capture_tool := preload("res://tools/visual_smoke_capture.gd").new()
		add_child(capture_tool)
		capture_tool.run.call_deferred(self)


func start_foundation_course(scene_path := FOUNDATION_COURSE_PATH) -> void:
	if not _state.transition(GameStateMachine.State.RUN_LOADING):
		return
	var packed_scene := ResourceLoader.load(
		scene_path,
		"PackedScene",
		ResourceLoader.CACHE_MODE_REUSE
	) as PackedScene
	if packed_scene == null:
		AppLog.error(&"app", "Session scene could not be loaded", {
			"code": "session_load_failed",
			"resource": scene_path,
		})
		_state.transition(GameStateMachine.State.TITLE)
		return
	var candidate := packed_scene.instantiate()
	if candidate == null:
		AppLog.error(&"app", "Session scene could not be instantiated", {
			"code": "session_instantiate_failed",
			"resource": scene_path,
		})
		_state.transition(GameStateMachine.State.TITLE)
		return
	_clear_active_session()
	_active_session = candidate
	session_root.add_child(_active_session)
	_state.transition(GameStateMachine.State.RUN_INTRO)
	_state.transition(GameStateMachine.State.DESCENT)


func pause_game() -> void:
	if _state.current != GameStateMachine.State.DESCENT:
		return
	pause_menu.show_and_focus()
	get_tree().paused = true
	_state.transition(GameStateMachine.State.PAUSED)


func resume_game() -> void:
	if _state.current != GameStateMachine.State.PAUSED:
		return
	get_tree().paused = false
	pause_menu.hide()
	_state.transition(GameStateMachine.State.DESCENT)


func return_to_title() -> void:
	get_tree().paused = false
	pause_menu.hide()
	_clear_active_session()
	if _state.current != GameStateMachine.State.TITLE:
		_state.transition(GameStateMachine.State.TITLE)


func _clear_active_session() -> void:
	if is_instance_valid(_active_session):
		_active_session.queue_free()
	_active_session = null


func _on_state_changed(previous: GameStateMachine.State, current: GameStateMachine.State) -> void:
	title_screen.visible = current == GameStateMachine.State.TITLE
	AppLog.info(&"state", "State changed", {
		"from": GameStateMachine.label(previous),
		"to": GameStateMachine.label(current),
	})


func _on_transition_rejected(previous: GameStateMachine.State, requested: GameStateMachine.State) -> void:
	AppLog.warning(&"state", "Rejected state transition", {
		"from": GameStateMachine.label(previous),
		"to": GameStateMachine.label(requested),
	})


func _on_pause_requested() -> void:
	if _state.current == GameStateMachine.State.DESCENT:
		pause_game()
	elif _state.current == GameStateMachine.State.PAUSED:
		resume_game()


func _on_controller_disconnected(_device_id: int) -> void:
	if _state.current == GameStateMachine.State.DESCENT:
		pause_game()
		pause_menu.set_notice("Controller disconnected. Keyboard controls remain available.")


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and is_node_ready() \
			and _state.current == GameStateMachine.State.DESCENT:
		pause_game()


func _quit_application() -> void:
	get_tree().quit(0)


func _run_smoke_test() -> void:
	if not _run_foundation_service_smoke_tests():
		get_tree().quit(4)
		return
	start_foundation_course()
	await get_tree().process_frame
	await get_tree().process_frame
	if _state.current != GameStateMachine.State.DESCENT or not is_instance_valid(_active_session):
		AppLog.error(&"smoke", "Main flow smoke test failed")
		get_tree().quit(2)
		return
	pause_game()
	await get_tree().process_frame
	resume_game()
	return_to_title()
	await get_tree().process_frame
	if _state.current != GameStateMachine.State.TITLE or get_tree().paused:
		AppLog.error(&"smoke", "State cleanup smoke test failed")
		get_tree().quit(3)
		return
	AppLog.info(&"smoke", "Main flow smoke test passed")
	get_tree().quit(0)


func _run_foundation_service_smoke_tests() -> bool:
	var settings_path := "user://aeolian-smoke-settings.cfg"
	var profile_path := "user://aeolian-smoke-profile.cfg"
	_cleanup_smoke_files(settings_path)
	_cleanup_smoke_files(profile_path)

	var original_sensitivity: Variant = SettingsStore.get_setting(&"controls", &"steer_sensitivity")
	SettingsStore.set_setting(&"controls", &"steer_sensitivity", 1.37, false)
	if SettingsStore.save_settings(settings_path) != OK:
		AppLog.error(&"smoke", "Settings smoke save failed")
		return false
	SettingsStore.set_setting(&"controls", &"steer_sensitivity", 0.25, false)
	if SettingsStore.load_settings(settings_path) != OK \
			or not is_equal_approx(
				float(SettingsStore.get_setting(&"controls", &"steer_sensitivity")), 1.37
			):
		AppLog.error(&"smoke", "Settings smoke round trip failed")
		return false
	SettingsStore.set_setting(&"controls", &"steer_sensitivity", original_sensitivity, false)

	var original_profile := SaveStore.profile.duplicate(true)
	SaveStore.profile = ProfileSchema.defaults()
	SaveStore.profile.stats.runs_started = 3
	if SaveStore.save_profile(profile_path) != OK:
		AppLog.error(&"smoke", "Profile smoke save failed")
		return false
	SaveStore.profile = ProfileSchema.defaults()
	if SaveStore.load_profile(profile_path) != OK or SaveStore.profile.stats.runs_started != 3:
		AppLog.error(&"smoke", "Profile smoke round trip failed")
		return false
	SaveStore.profile = original_profile

	Input.action_press(&"steer_right", 0.75)
	var intent := InputService.sample_intent()
	Input.action_release(&"steer_right")
	if intent.steer <= 0.5:
		AppLog.error(&"smoke", "Input intent smoke test failed", {"steer": intent.steer})
		return false
	for action: StringName in InputService.REMAPPABLE_ACTIONS:
		if not InputMap.has_action(action) or InputMap.action_get_events(action).is_empty():
			AppLog.error(&"smoke", "Required input action has no default binding", {"action": action})
			return false
		if not _has_keyboard_and_gamepad_defaults(action):
			AppLog.error(&"smoke", "Required action lacks keyboard or gamepad coverage", {"action": action})
			return false
	var arrow_defaults := {
		&"steer_left": KEY_LEFT,
		&"steer_right": KEY_RIGHT,
		&"tuck": KEY_UP,
		&"brake": KEY_DOWN,
	}
	for action: StringName in arrow_defaults:
		if not _has_key_default(action, arrow_defaults[action]):
			AppLog.error(&"smoke", "Required arrow-key default is missing", {"action": action})
			return false

	_cleanup_smoke_files(settings_path)
	_cleanup_smoke_files(profile_path)
	AppLog.info(&"smoke", "Settings, profile, and input smoke tests passed")
	return true


func _cleanup_smoke_files(base_path: String) -> void:
	for suffix: String in ["", ".tmp", ".bak"]:
		var candidate := base_path + suffix
		if FileAccess.file_exists(candidate):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(candidate))


func _has_keyboard_and_gamepad_defaults(action: StringName) -> bool:
	var has_keyboard := false
	var has_gamepad := false
	for event: InputEvent in InputMap.action_get_events(action):
		has_keyboard = has_keyboard or event is InputEventKey
		has_gamepad = has_gamepad or event is InputEventJoypadButton \
			or event is InputEventJoypadMotion
	return has_keyboard and has_gamepad


func _has_key_default(action: StringName, expected: Key) -> bool:
	for event: InputEvent in InputMap.action_get_events(action):
		if event is InputEventKey and (event.keycode == expected \
				or event.physical_keycode == expected):
			return true
	return false
