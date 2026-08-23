extends RefCounted


static func run(suite: RefCounted) -> void:
	print("InputBindingCodec")
	suite.run_test("physical key round trip uses one representation", func() -> void:
		var original := InputEventKey.new()
		original.physical_keycode = KEY_A
		original.keycode = KEY_Q
		original.shift_pressed = true
		var encoded := InputBindingCodec.encode(original)
		suite.assert_equal(encoded.type, "key_physical")
		suite.assert_equal(encoded.code, KEY_A)
		var decoded := InputBindingCodec.decode(encoded) as InputEventKey
		suite.assert_true(decoded != null)
		suite.assert_equal(decoded.physical_keycode, KEY_A)
		suite.assert_equal(decoded.keycode, 0)
		suite.assert_true(decoded.shift_pressed)
		suite.assert_equal(decoded.device, -1)
	)
	suite.run_test("joy axis direction is canonical", func() -> void:
		var original := InputEventJoypadMotion.new()
		original.axis = JOY_AXIS_LEFT_X
		original.axis_value = -0.37
		var encoded := InputBindingCodec.encode(original)
		suite.assert_near(encoded.axis_value, -1.0, 0.0001)
		var decoded := InputBindingCodec.decode(encoded) as InputEventJoypadMotion
		suite.assert_equal(decoded.axis, JOY_AXIS_LEFT_X)
		suite.assert_near(decoded.axis_value, -1.0, 0.0001)
	)
	suite.run_test("opposite directions remain distinct", func() -> void:
		var left := InputBindingCodec.decode({"type": "joy_motion", "axis": 0, "axis_value": -1})
		var right := InputBindingCodec.decode({"type": "joy_motion", "axis": 0, "axis_value": 1})
		suite.assert_false(left.is_match(right, true))
	)
	suite.run_test("invalid records are rejected", func() -> void:
		suite.assert_equal(InputBindingCodec.decode({"type": "mouse_motion"}), null)
		suite.assert_equal(InputBindingCodec.decode({"type": "key_physical", "code": 0}), null)
		suite.assert_equal(InputBindingCodec.decode({"type": "joy_motion", "axis": 0, "axis_value": 0}), null)
		suite.assert_equal(InputBindingCodec.decode({"type": "joy_motion", "axis": 999, "axis_value": 1}), null)
		suite.assert_equal(InputBindingCodec.decode({"type": "joy_button", "button_index": 999}), null)
		suite.assert_equal(InputBindingCodec.decode({"type": "joy_motion", "axis": 0, "axis_value": NAN}), null)
	)
