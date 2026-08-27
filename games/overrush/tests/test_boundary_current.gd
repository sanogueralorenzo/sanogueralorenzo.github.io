extends SceneTree

const BoundaryCurrentModel = preload("res://scripts/boundary_current.gd")

const HALF_EXTENT := 1600.0
const SIMULATION_DURATION := 20.0 * 60.0
const STEP := 1.0 / 60.0

var _failures: Array[String] = []


func _init() -> void:
	_simulate_sustained_traversal(58.0, 1.0)
	_simulate_sustained_traversal(126.0, -1.0)
	_test_no_guidance_in_safe_interior()
	if _failures.is_empty():
		print("Boundary current validation passed for 20-minute cruise and dash-speed traversal.")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _simulate_sustained_traversal(speed: float, turn_bias: float) -> void:
	var current := BoundaryCurrentModel.new()
	var sample := BoundaryCurrentModel.Sample.new()
	var position := Vector3.ZERO
	var heading := Vector3.FORWARD
	var maximum_axis := 0.0
	var guidance_frames := 0
	var steps := floori(SIMULATION_DURATION / STEP)
	for index in range(steps):
		current.sample(position, heading, speed, HALF_EXTENT, turn_bias, sample)
		if sample.pressure > 0.0:
			guidance_frames += 1
		heading = current.guide_heading(heading, sample, STEP)
		position += heading * speed * STEP
		maximum_axis = maxf(maximum_axis, maxf(absf(position.x), absf(position.z)))
	_expect(guidance_frames > 0, "Boundary guidance should engage during sustained traversal at %.0f m/s." % speed)
	_expect(maximum_axis < HALF_EXTENT - 24.0, "Guidance should keep %.0f m/s traversal inside the emergency inset; reached %.1f m." % [speed, maximum_axis])


func _test_no_guidance_in_safe_interior() -> void:
	var current := BoundaryCurrentModel.new()
	var sample := BoundaryCurrentModel.Sample.new()
	current.sample(Vector3.ZERO, Vector3.FORWARD, 126.0, HALF_EXTENT, 1.0, sample)
	_expect(sample.pressure == 0.0, "The boundary current should not steer the runner in the safe interior.")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
