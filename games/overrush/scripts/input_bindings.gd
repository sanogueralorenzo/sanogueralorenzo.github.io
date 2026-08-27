class_name OverrushInputBindings
extends RefCounted

const MOVE_LEFT := &"overrush_move_left"
const MOVE_RIGHT := &"overrush_move_right"
const MOVE_FORWARD := &"overrush_move_forward"
const MOVE_BACKWARD := &"overrush_move_backward"
const LOOK_LEFT := &"overrush_look_left"
const LOOK_RIGHT := &"overrush_look_right"
const LOOK_UP := &"overrush_look_up"
const LOOK_DOWN := &"overrush_look_down"
const HOP := &"overrush_hop"
const AIR_BOOST := &"overrush_air_boost"
const PAUSE := &"overrush_pause"

const ALL_ACTIONS: Array[StringName] = [
	MOVE_LEFT,
	MOVE_RIGHT,
	MOVE_FORWARD,
	MOVE_BACKWARD,
	LOOK_LEFT,
	LOOK_RIGHT,
	LOOK_UP,
	LOOK_DOWN,
	HOP,
	AIR_BOOST,
	PAUSE,
]


static func ensure_actions() -> void:
	_ensure_action(MOVE_LEFT, [_key(KEY_A), _key(KEY_LEFT), _joy_axis(JOY_AXIS_LEFT_X, -1.0), _joy_button(JOY_BUTTON_DPAD_LEFT)])
	_ensure_action(MOVE_RIGHT, [_key(KEY_D), _key(KEY_RIGHT), _joy_axis(JOY_AXIS_LEFT_X, 1.0), _joy_button(JOY_BUTTON_DPAD_RIGHT)])
	_ensure_action(MOVE_FORWARD, [_key(KEY_W), _key(KEY_UP), _joy_axis(JOY_AXIS_LEFT_Y, -1.0), _joy_button(JOY_BUTTON_DPAD_UP)])
	_ensure_action(MOVE_BACKWARD, [_key(KEY_S), _key(KEY_DOWN), _joy_axis(JOY_AXIS_LEFT_Y, 1.0), _joy_button(JOY_BUTTON_DPAD_DOWN)])
	_ensure_action(LOOK_LEFT, [_joy_axis(JOY_AXIS_RIGHT_X, -1.0)])
	_ensure_action(LOOK_RIGHT, [_joy_axis(JOY_AXIS_RIGHT_X, 1.0)])
	_ensure_action(LOOK_UP, [_joy_axis(JOY_AXIS_RIGHT_Y, -1.0)])
	_ensure_action(LOOK_DOWN, [_joy_axis(JOY_AXIS_RIGHT_Y, 1.0)])
	_ensure_action(HOP, [_key(KEY_SPACE), _joy_button(JOY_BUTTON_A)])
	_ensure_action(AIR_BOOST, [_key(KEY_SHIFT), _key(KEY_ALT), _joy_button(JOY_BUTTON_LEFT_SHOULDER), _joy_button(JOY_BUTTON_RIGHT_SHOULDER)])
	_ensure_action(PAUSE, [_key(KEY_ESCAPE), _joy_button(JOY_BUTTON_START)])


static func is_gamepad_event(event: InputEvent) -> bool:
	if event is InputEventJoypadButton:
		return event.pressed
	if event is InputEventJoypadMotion:
		return absf(event.axis_value) >= 0.35
	return false


static func is_keyboard_or_mouse_event(event: InputEvent) -> bool:
	if event is InputEventKey:
		return event.pressed and not event.echo
	if event is InputEventMouseButton:
		return event.pressed
	return event is InputEventMouseMotion and event.relative.length_squared() > 16.0


static func _ensure_action(action: StringName, events: Array[InputEvent], deadzone: float = 0.22) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action, deadzone)
	for event in events:
		InputMap.action_add_event(action, event)


static func _key(keycode: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = keycode
	return event


static func _joy_button(button_index: JoyButton) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.button_index = button_index
	return event


static func _joy_axis(axis: JoyAxis, value: float) -> InputEventJoypadMotion:
	var event := InputEventJoypadMotion.new()
	event.axis = axis
	event.axis_value = value
	return event
