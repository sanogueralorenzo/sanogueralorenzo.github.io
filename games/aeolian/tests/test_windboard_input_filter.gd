extends RefCounted

const INPUT_FILTER := preload("res://input/windboard_input_filter.gd")


static func run(suite: RefCounted) -> void:
	print("WindboardInputFilter")
	suite.run_test("keyboard steering attacks and releases over multiple ticks", func() -> void:
		var filter := INPUT_FILTER.new()
		var tuning := WindboardTuning.new()
		var pressed := _intent(1.0)
		var first := filter.step(pressed, 1.0 / 60.0, false, 1.0, tuning)
		suite.assert_true(first.steer > 0.0 and first.steer < 0.2)
		for frame in 11:
			filter.step(pressed, 1.0 / 60.0, false, 1.0, tuning)
		suite.assert_true(filter.filtered_steer >= 0.9)
		var released := filter.step(_intent(0.0), 1.0 / 60.0, false, 1.0, tuning)
		suite.assert_true(released.steer > 0.0 and released.steer < 1.0)
	)
	suite.run_test("keyboard sign reversal crosses zero progressively", func() -> void:
		var filter := INPUT_FILTER.new()
		var tuning := WindboardTuning.new()
		filter.filtered_steer = 1.0
		var reversed := filter.step(_intent(-1.0), 1.0 / 60.0, false, 1.0, tuning)
		suite.assert_true(reversed.steer > 0.0)
		for frame in 12:
			filter.step(_intent(-1.0), 1.0 / 60.0, false, 1.0, tuning)
		suite.assert_true(filter.filtered_steer < -0.5)
	)
	suite.run_test("gamepad preserves low analog control with a bounded curve", func() -> void:
		var filter := INPUT_FILTER.new()
		var tuning := WindboardTuning.new()
		var low := filter.step(_intent(0.25), 1.0 / 60.0, true, 1.0, tuning).steer
		var full := filter.step(_intent(1.0), 1.0 / 60.0, true, 1.0, tuning).steer
		suite.assert_true(low > 0.15 and low < 0.25)
		suite.assert_true(full / low >= 2.0 and full / low <= 6.0)
	)
	suite.run_test("keyboard equal-time response converges across tick rates", func() -> void:
		var at_30 := _simulate_keyboard(30)
		var at_60 := _simulate_keyboard(60)
		var at_120 := _simulate_keyboard(120)
		suite.assert_near(at_30, at_60, 0.001)
		suite.assert_near(at_60, at_120, 0.001)
	)
	suite.run_test("intent edge and held flags survive filtering", func() -> void:
		var raw := _intent(0.0)
		raw.jump_pressed = true
		raw.jump_held = true
		raw.restart_pressed = true
		var output := INPUT_FILTER.new().step(
			raw, 1.0 / 60.0, false, 1.0, WindboardTuning.new()
		)
		suite.assert_true(output.jump_pressed)
		suite.assert_true(output.jump_held)
		suite.assert_true(output.restart_pressed)
	)


static func _intent(steer: float) -> InputIntent:
	var intent := InputIntent.new()
	intent.steer = steer
	return intent


static func _simulate_keyboard(rate: int) -> float:
	var filter := INPUT_FILTER.new()
	var tuning := WindboardTuning.new()
	for frame in rate:
		filter.step(_intent(1.0), 1.0 / float(rate), false, 1.0, tuning)
	return filter.filtered_steer
