class_name InputBindingCodec
extends RefCounted

## Converts the supported remappable input event types to primitive dictionaries.
## Mouse motion and arbitrary objects are deliberately not persisted.


static func encode(event: InputEvent) -> Dictionary:
	if event is InputEventKey:
		var type := "key_physical" if event.physical_keycode != 0 else "key_logical"
		var code: Key = event.physical_keycode if event.physical_keycode != 0 else event.keycode
		if code == 0:
			return {}
		return {
			"type": type,
			"code": code,
			"location": event.location,
			"shift": event.shift_pressed,
			"alt": event.alt_pressed,
			"ctrl": event.ctrl_pressed,
			"meta": event.meta_pressed,
		}
	if event is InputEventJoypadButton:
		if event.button_index < 0 or event.button_index >= JOY_BUTTON_MAX:
			return {}
		return {"type": "joy_button", "button_index": event.button_index}
	if event is InputEventJoypadMotion:
		if event.axis < 0 or event.axis >= JOY_AXIS_MAX \
				or not is_finite(event.axis_value) or is_zero_approx(event.axis_value):
			return {}
		return {
			"type": "joy_motion",
			"axis": event.axis,
			"axis_value": signf(event.axis_value),
		}
	return {}


static func decode(data: Dictionary) -> InputEvent:
	var event: InputEvent
	match data.get("type", ""):
		"key_physical", "key_logical":
			var code := int(data.get("code", 0))
			if code == 0:
				return null
			var key_event := InputEventKey.new()
			if data.type == "key_physical":
				key_event.physical_keycode = code as Key
			else:
				key_event.keycode = code as Key
			key_event.location = int(data.get("location", 0)) as KeyLocation
			key_event.shift_pressed = bool(data.get("shift", false))
			key_event.alt_pressed = bool(data.get("alt", false))
			key_event.ctrl_pressed = bool(data.get("ctrl", false))
			key_event.meta_pressed = bool(data.get("meta", false))
			event = key_event
		"joy_button":
			var button_index := int(data.get("button_index", -1))
			if button_index < 0 or button_index >= JOY_BUTTON_MAX:
				return null
			var button_event := InputEventJoypadButton.new()
			button_event.button_index = button_index as JoyButton
			event = button_event
		"joy_motion":
			var axis := int(data.get("axis", -1))
			if axis < 0 or axis >= JOY_AXIS_MAX:
				return null
			var axis_value := float(data.get("axis_value", 0.0))
			if not is_finite(axis_value):
				return null
			var motion_event := InputEventJoypadMotion.new()
			motion_event.axis = axis as JoyAxis
			motion_event.axis_value = clampf(axis_value, -1.0, 1.0)
			if is_zero_approx(motion_event.axis_value):
				return null
			event = motion_event
		_:
			return null
	# Persisted mappings intentionally apply to all compatible devices.
	event.device = -1
	return event
