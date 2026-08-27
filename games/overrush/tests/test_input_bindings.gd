extends SceneTree

const InputBindings = preload("res://scripts/input_bindings.gd")

var _failures: Array[String] = []


func _init() -> void:
	InputBindings.ensure_actions()
	var original_event_counts := {}
	for action in InputBindings.ALL_ACTIONS:
		original_event_counts[action] = InputMap.action_get_events(action).size()
	InputBindings.ensure_actions()

	for action in InputBindings.ALL_ACTIONS:
		_expect(InputMap.has_action(action), "The %s action should be registered at runtime." % action)
		_expect(
			InputMap.action_get_events(action).size() == int(original_event_counts[action]),
			"Registering actions twice should not duplicate %s bindings." % action,
		)
	_expect(_has_key(InputBindings.MOVE_LEFT, KEY_A), "Keyboard movement should include A.")
	_expect(_has_key(InputBindings.MOVE_BACKWARD, KEY_S), "Keyboard movement should include S.")
	_expect(_has_axis(InputBindings.MOVE_LEFT, JOY_AXIS_LEFT_X, -1.0), "Analog movement should include the left stick's negative X axis.")
	_expect(_has_axis(InputBindings.MOVE_FORWARD, JOY_AXIS_LEFT_Y, -1.0), "Analog movement should include the left stick's forward axis.")
	_expect(_has_axis(InputBindings.LOOK_RIGHT, JOY_AXIS_RIGHT_X, 1.0), "Camera rotation should include the right stick's horizontal axis.")
	_expect(_has_axis(InputBindings.LOOK_UP, JOY_AXIS_RIGHT_Y, -1.0), "Camera rotation should include the right stick's vertical axis.")
	_expect(_has_button(InputBindings.HOP, JOY_BUTTON_A), "Gamepad hop should use the south face button.")
	_expect(_has_button(InputBindings.AIR_BOOST, JOY_BUTTON_LEFT_SHOULDER), "Gamepad air boost should include the left shoulder.")
	_expect(_has_button(InputBindings.PAUSE, JOY_BUTTON_START), "Gamepad pause should use Start.")
	_expect(InputBindings.ALL_ACTIONS.size() == 11, "The final game should register only movement, look, jump, air boost, and pause actions.")

	var joy_event := InputEventJoypadButton.new()
	joy_event.button_index = JOY_BUTTON_A
	joy_event.pressed = true
	_expect(InputBindings.is_gamepad_event(joy_event), "Pressed controller buttons should switch prompt mode.")
	var key_event := InputEventKey.new()
	key_event.keycode = KEY_SPACE
	key_event.pressed = true
	_expect(InputBindings.is_keyboard_or_mouse_event(key_event), "Pressed keyboard keys should switch prompt mode.")

	if _failures.is_empty():
		print("Input binding validation passed — keyboard and controller actions are complete and idempotent.")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _has_key(action: StringName, keycode: Key) -> bool:
	for event in InputMap.action_get_events(action):
		if event is InputEventKey and event.keycode == keycode:
			return true
	return false


func _has_button(action: StringName, button: JoyButton) -> bool:
	for event in InputMap.action_get_events(action):
		if event is InputEventJoypadButton and event.button_index == button:
			return true
	return false


func _has_axis(action: StringName, axis: JoyAxis, value: float) -> bool:
	for event in InputMap.action_get_events(action):
		if event is InputEventJoypadMotion and event.axis == axis and is_equal_approx(event.axis_value, value):
			return true
	return false


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
