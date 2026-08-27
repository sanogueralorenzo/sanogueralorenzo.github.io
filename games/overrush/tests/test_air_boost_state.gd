extends SceneTree

const AirBoostStateModel = preload("res://scripts/air_boost_state.gd")

var _failures: Array[String] = []


func _init() -> void:
	var boost := AirBoostStateModel.new()
	_expect(not boost.try_use(), "The air boost must not activate while grounded.")
	boost.leave_surface()
	_expect(boost.try_use(), "Leaving valid rideable ground should expose exactly one air boost.")
	_expect(not boost.try_use(), "A second boost in the same airtime must be rejected.")
	_expect(not boost.land(false) and not boost.available, "Rock or wall contact must not refresh the spent boost.")
	boost.leave_surface()
	_expect(not boost.try_use(), "Leaving obstacle contact must not create a new charge.")
	_expect(boost.land(true) and boost.available, "A valid rideable landing should refresh the spent boost.")
	boost.leave_surface()
	_expect(boost.try_use() and not boost.try_use(), "Every later airtime should still contain exactly one charge.")

	if _failures.is_empty():
		print("Air boost state validation passed — one charge, rideable-ground refresh, and obstacle rejection agree.")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
