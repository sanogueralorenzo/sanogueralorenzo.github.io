extends Node

signal active_device_changed(device_kind: DeviceKind, joypad_id: int)
signal pause_requested
signal controller_disconnected(device_id: int)

enum DeviceKind {
	KEYBOARD_MOUSE,
	GAMEPAD,
}

const REMAPPABLE_ACTIONS := [
	&"steer_left",
	&"steer_right",
	&"tuck",
	&"brake",
	&"jump_recover",
	&"restart_run",
	&"pause",
]

var active_device_kind := DeviceKind.KEYBOARD_MOUSE
var active_joypad_id := -1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Input.joy_connection_changed.connect(_on_joy_connection_changed)


func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		if _event_has_meaningful_input(event):
			_set_active_device(DeviceKind.GAMEPAD, event.device)
	elif event is InputEventKey or event is InputEventMouseButton or event is InputEventMouseMotion:
		if _event_has_meaningful_input(event):
			_set_active_device(DeviceKind.KEYBOARD_MOUSE, -1)

	if event.is_action_pressed(&"pause") and not event.is_echo():
		pause_requested.emit()


func sample_intent() -> InputIntent:
	var intent := InputIntent.new()
	intent.steer = Input.get_axis(&"steer_left", &"steer_right")
	intent.tuck = Input.get_action_strength(&"tuck")
	intent.brake = Input.get_action_strength(&"brake")
	intent.jump_pressed = Input.is_action_just_pressed(&"jump_recover")
	intent.jump_held = Input.is_action_pressed(&"jump_recover")
	intent.restart_pressed = Input.is_action_just_pressed(&"restart_run")
	return intent


func vibrate_impact(strength: float, duration_seconds: float) -> void:
	if active_device_kind != DeviceKind.GAMEPAD or active_joypad_id < 0:
		return
	var configured_strength := float(SettingsStore.get_setting(&"controls", &"vibration_strength"))
	if configured_strength <= 0.0:
		return
	var magnitude := clampf(strength * configured_strength, 0.0, 1.0)
	Input.start_joy_vibration(active_joypad_id, magnitude * 0.65, magnitude, maxf(0.0, duration_seconds))


func device_label() -> String:
	if active_device_kind == DeviceKind.GAMEPAD:
		var name := Input.get_joy_name(active_joypad_id)
		return name if not name.is_empty() else "Gamepad"
	return "Keyboard & Mouse"


func _set_active_device(kind: DeviceKind, joypad_id: int) -> void:
	if active_device_kind == kind and active_joypad_id == joypad_id:
		return
	active_device_kind = kind
	active_joypad_id = joypad_id
	active_device_changed.emit(active_device_kind, active_joypad_id)


func _event_has_meaningful_input(event: InputEvent) -> bool:
	if event is InputEventJoypadMotion:
		return absf(event.axis_value) >= 0.2
	if event is InputEventMouseMotion:
		return event.relative.length_squared() >= 4.0
	if event is InputEventKey or event is InputEventMouseButton or event is InputEventJoypadButton:
		return event.pressed
	return false


func _on_joy_connection_changed(device_id: int, connected: bool) -> void:
	if not connected and active_device_kind == DeviceKind.GAMEPAD and active_joypad_id == device_id:
		Input.stop_joy_vibration(device_id)
		_set_active_device(DeviceKind.KEYBOARD_MOUSE, -1)
		controller_disconnected.emit(device_id)
