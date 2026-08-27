extends SceneTree

const DashStateMachine = preload("res://scripts/dash_state.gd")

var _failures: Array[String] = []


func _init() -> void:
	_test_ground_dash_can_repeat()
	_test_air_dash_resets_only_on_landing()
	_test_hold_controls_dash_length()
	if _failures.is_empty():
		print("Dash state validation passed.")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _test_ground_dash_can_repeat() -> void:
	var dash := DashStateMachine.new(0.08, 0.24, 0.14)
	_expect(dash.step(0.0, true, true, true) == DashStateMachine.Event.STARTED, "Ground dash should start immediately.")
	_expect(dash.step(0.04, false, false, true) == DashStateMachine.Event.NONE, "A tap should honor the minimum dash duration.")
	_expect(dash.step(0.04, false, false, true) == DashStateMachine.Event.ENDED, "A released ground dash should end at its minimum duration.")
	dash.step(0.14, false, false, true)
	_expect(dash.step(0.0, true, true, true) == DashStateMachine.Event.STARTED, "Ground dash should repeat after recovery.")


func _test_air_dash_resets_only_on_landing() -> void:
	var dash := DashStateMachine.new(0.08, 0.24, 0.0)
	_expect(dash.step(0.0, true, true, false) == DashStateMachine.Event.STARTED, "Air dash should be available once.")
	dash.step(0.24, true, false, false)
	dash.step(0.0, false, false, false)
	_expect(dash.step(0.0, true, true, false) == DashStateMachine.Event.NONE, "A second dash in the same airtime should be denied.")
	dash.step(0.0, false, false, true)
	_expect(dash.air_dash_available, "Landing should restore the air dash.")
	dash.step(0.0, false, false, false)
	_expect(dash.step(0.0, true, true, false) == DashStateMachine.Event.STARTED, "Air dash should work after landing.")


func _test_hold_controls_dash_length() -> void:
	var tap := DashStateMachine.new(0.08, 0.24, 0.0)
	tap.step(0.0, true, true, true)
	tap.step(0.04, false, false, true)
	tap.step(0.04, false, false, true)
	var tap_duration := tap.elapsed

	var hold := DashStateMachine.new(0.08, 0.24, 0.0)
	hold.step(0.0, true, true, true)
	for index in range(6):
		hold.step(0.04, true, false, true)
	_expect(not hold.is_active, "A held dash should stop at the maximum duration.")
	_expect(hold.elapsed > tap_duration, "Holding should produce a longer dash than tapping.")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
