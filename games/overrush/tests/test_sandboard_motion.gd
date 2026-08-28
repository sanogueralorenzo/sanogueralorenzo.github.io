extends SceneTree

const Motion = preload("res://scripts/sandboard_motion.gd")

var _failures: Array[String] = []


func _init() -> void:
	var fast_carve := Motion.calculate_carve(Vector3(0.0, 0.0, -18.0), Vector3.RIGHT, Vector3.UP, 1.0 / 60.0, 78.0, 2.8, 1.05)
	var high_speed_carve := Motion.calculate_carve(Vector3(0.0, 0.0, -70.0), Vector3.RIGHT, Vector3.UP, 1.0 / 60.0, 78.0, 2.8, 1.05)
	_expect(absf(fast_carve.turn_angle) > absf(high_speed_carve.turn_angle), "Lower-speed carving should turn more tightly than maximum-speed carving.")
	_expect(absf(high_speed_carve.turn_angle) <= 0.021, "Maximum-speed steering should remain inside the predictable carve envelope.")
	_expect(fast_carve.velocity.length() >= 17.9, "One carve frame should preserve nearly all existing momentum.")
	_expect(fast_carve.direction.x > 0.0 and fast_carve.direction.z < 0.0, "Carving should rotate toward input without snapping to it.")
	var gentle_carve := Motion.calculate_carve(Vector3(0.0, 0.0, -70.0), Vector3(0.17, 0.0, -0.98), Vector3.UP, 1.0 / 60.0, 78.0, 2.8, 1.05)
	var half_strength_carve := Motion.calculate_carve(Vector3(0.0, 0.0, -70.0), Vector3.RIGHT * 0.5, Vector3.UP, 1.0 / 60.0, 78.0, 2.8, 1.05)
	_expect(
		absf(half_strength_carve.turn_angle) < absf(high_speed_carve.turn_angle)
			and float(half_strength_carve.edge_load) < float(high_speed_carve.edge_load),
		"Analog carve input should monotonically control turn authority and edge load.",
	)
	_expect(float(gentle_carve.edge_load) < float(high_speed_carve.edge_load), "A shallow carve should load the edge less than a committed direction change.")
	_expect(gentle_carve.velocity.length() > high_speed_carve.velocity.length(), "A shallow carve should preserve more speed than a hard carve.")
	var sustained_velocity := Vector3(0.0, 0.0, -70.0)
	for _frame in range(60):
		var sustained := Motion.calculate_carve(sustained_velocity, Vector3.RIGHT, Vector3.UP, 1.0 / 60.0, 78.0, 2.8, 1.05)
		sustained_velocity = sustained.velocity
	var sustained_direction := sustained_velocity.normalized()
	_expect(sustained_direction.x > 0.7 and sustained_direction.z < -0.2, "A one-second high-speed carve should turn substantially without snapping sideways.")
	_expect(sustained_velocity.length() >= 62.0, "A sustained high-speed carve should retain useful momentum while paying a readable edge-load cost.")
	var coasting := Motion.calculate_carve(Vector3(22.0, 0.0, -31.0), Vector3.ZERO, Vector3.UP, 1.0 / 60.0, 78.0, 2.8, 1.05)
	_expect(coasting.velocity.is_equal_approx(Vector3(22.0, 0.0, -31.0)), "Releasing carve input should not redirect momentum.")
	var slope_carve_normal := Vector3(0.18, 0.95, 0.25).normalized()
	var slope_velocity := Vector3(8.0, -2.0, -34.0)
	var slope_carve := Motion.calculate_carve(slope_velocity, Vector3.RIGHT, slope_carve_normal, 1.0 / 60.0, 78.0, 2.8, 1.05)
	_expect(
		is_equal_approx(slope_carve.velocity.dot(slope_carve_normal), slope_velocity.dot(slope_carve_normal))
			and absf(Vector3(slope_carve.direction).dot(slope_carve_normal)) <= 0.001,
		"Carving on steep terrain should rotate the tangent line around the surface normal without injecting vertical velocity.",
	)
	var push_below := Motion.calculate_starting_push(13.9, 14.0, 18.0, 1.0)
	var push_above := Motion.calculate_starting_push(14.1, 14.0, 18.0, 1.0)
	var push_half_input := Motion.calculate_starting_push(4.0, 14.0, 18.0, 0.5)
	_expect(
		absf(push_below - push_above) <= 0.05
			and is_equal_approx(push_above, 0.0)
			and push_half_input > 0.0
			and push_half_input < Motion.calculate_starting_push(4.0, 14.0, 18.0, 1.0),
		"Starting propulsion should fade continuously before the carve-speed envelope and respect analog input.",
	)
	var full_preparation := _simulate_landing_preparation(120, 1.0, 90.0)
	var half_preparation := _simulate_landing_preparation(120, 0.5, 90.0)
	var no_preparation := _simulate_landing_preparation(120, 0.0, 90.0)
	var opposed_preparation := _simulate_landing_preparation(120, -1.0, 90.0)
	_expect(
		float(full_preparation.closing_speed_after) >= 9.0
			and float(full_preparation.closing_speed_after) <= 13.0,
		"Aligned full input should prepare a hard descent into a still-descending clean-impact envelope.",
	)
	_expect(
		float(full_preparation.closing_speed_after) < float(half_preparation.closing_speed_after)
			and float(half_preparation.closing_speed_after) < float(no_preparation.closing_speed_after),
		"Landing preparation should improve normal impact monotonically with analog input strength.",
	)
	_expect(
		is_equal_approx(float(no_preparation.preparation_strength), 0.0)
			and Vector3(no_preparation.velocity).is_equal_approx(Vector3(no_preparation.starting_velocity))
			and is_equal_approx(float(opposed_preparation.preparation_strength), 0.0)
			and Vector3(opposed_preparation.velocity).is_equal_approx(Vector3(opposed_preparation.starting_velocity)),
		"No input and opposed input must not receive automatic landing correction.",
	)
	_expect(
		float(full_preparation.preparation_strength) > float(half_preparation.preparation_strength)
			and float(half_preparation.preparation_strength) > 0.0
			and float(full_preparation.alignment) >= 0.99,
		"Preparation feedback should expose the aligned analog intent that produced the correction.",
	)
	_expect(
		absf(Vector3(full_preparation.velocity).length() - Vector3(full_preparation.starting_velocity).length()) <= 0.01
			and float(full_preparation.tangent_speed) <= 90.001
			and Vector3(full_preparation.velocity).dot(Vector3(full_preparation.surface_normal)) < 0.0,
		"Landing preparation should preserve total speed within the tangent cap and keep approaching the surface.",
	)
	var capped_preparation := _simulate_landing_preparation(120, 1.0, 50.0)
	_expect(
		float(capped_preparation.tangent_speed) <= 50.001
			and Vector3(capped_preparation.velocity).length() <= Vector3(capped_preparation.starting_velocity).length() + 0.01,
		"The tangent cap may discard excess speed but must never inject energy.",
	)
	var outside_window := Motion.calculate_landing_preparation(
		Vector3(full_preparation.starting_velocity),
		Vector3(full_preparation.desired_direction),
		Vector3(full_preparation.surface_normal),
		24.0,
		24.0,
		1.0 / 120.0,
		8.0,
		9.5,
		90.0,
	)
	_expect(
		is_equal_approx(float(outside_window.preparation_strength), 0.0)
			and Vector3(outside_window.velocity).is_equal_approx(Vector3(full_preparation.starting_velocity)),
		"Landing preparation should remain inactive outside its near-surface clearance window.",
	)
	var ascending_velocity := Vector3(0.0, 1.0, 60.0)
	var ascending_result := Motion.calculate_landing_preparation(
		ascending_velocity,
		Vector3.BACK,
		Vector3(full_preparation.surface_normal),
		6.0,
		24.0,
		1.0 / 120.0,
		8.0,
		9.5,
		90.0,
	)
	_expect(
		is_equal_approx(float(ascending_result.preparation_strength), 0.0)
			and Vector3(ascending_result.velocity).is_equal_approx(ascending_velocity),
		"Surface-relative closing motion must not trigger preparation while the rider is ascending in world space.",
	)
	var preparation_60 := _simulate_landing_preparation(60, 1.0, 90.0)
	var preparation_300 := _simulate_landing_preparation(300, 1.0, 90.0)
	_expect(
		absf(float(preparation_60.closing_speed_after) - float(full_preparation.closing_speed_after)) <= 0.05
			and absf(float(preparation_300.closing_speed_after) - float(full_preparation.closing_speed_after)) <= 0.05
			and Vector3(preparation_60.velocity).normalized().dot(Vector3(preparation_300.velocity).normalized()) >= 0.9999,
		"Landing preparation should resolve equivalently at 60, 120, and 300 Hz.",
	)
	var result_60 := _simulate_carve(60)
	var result_120 := _simulate_carve(120)
	var result_300 := _simulate_carve(300)
	_expect(
		result_60.normalized().dot(result_120.normalized()) >= 0.999
			and result_120.normalized().dot(result_300.normalized()) >= 0.999
			and absf(result_60.length() - result_300.length()) <= 0.12,
		"Analog carving should remain nearly equivalent at 60, 120, and 300 Hz.",
	)

	var slope_normal := Vector3(0.0, 0.94, 0.342).normalized()
	var downhill := Vector3.DOWN.slide(slope_normal).normalized()
	var across_slope := downhill.cross(slope_normal).normalized()
	var downhill_drive := Motion.calculate_slope_drive(downhill, slope_normal)
	var traverse_drive := Motion.calculate_slope_drive(across_slope, slope_normal)
	var uphill_drive := Motion.calculate_slope_drive(-downhill, slope_normal)
	_expect(downhill_drive.dot(downhill) > 0.3, "Pointing downhill should receive the slope's useful acceleration.")
	_expect(traverse_drive.length() <= 0.001, "Traversing across a slope should not receive a hidden downhill shove.")
	_expect(uphill_drive.dot(downhill) > 0.3, "Gravity should oppose an uphill line rather than accelerating it uphill.")

	var clean := Motion.evaluate_landing(Vector3(0.0, -8.0, -38.0), Vector3.UP, Vector3.FORWARD)
	_expect(clean.rating == Motion.LANDING_CLEAN, "Aligned low-impact contact should produce a clean landing.")
	_expect(is_equal_approx(clean.momentum_retention, 1.0), "A clean landing should preserve all tangent momentum.")
	var solid := Motion.evaluate_landing(Vector3(8.0, -17.0, -30.0), Vector3.UP, Vector3(0.2, 0.0, -1.0))
	_expect(solid.rating == Motion.LANDING_SOLID, "A moderate aligned impact should produce a solid landing.")
	_expect(solid.momentum_retention >= 0.9, "A solid landing should retain most momentum.")
	var rough := Motion.evaluate_landing(Vector3(35.0, -29.0, 0.0), Vector3.UP, Vector3.FORWARD)
	_expect(rough.rating == Motion.LANDING_ROUGH, "A hard sideways impact should be communicated as rough.")
	_expect(rough.momentum_retention >= 0.8, "Even a rough landing must not arbitrarily erase momentum.")
	_expect(clean.score > solid.score and solid.score > rough.score, "Landing scores should order clean, solid, and rough contact predictably.")

	_expect(
		Motion.is_fatal_obstacle_impact(Vector3(0.0, 0.0, -24.0), Vector3(0.0, 0.0, 1.0), 10.0),
		"A direct high-speed obstacle strike should end the run.",
	)
	_expect(
		not Motion.is_fatal_obstacle_impact(Vector3(20.0, 0.0, -3.0), Vector3(0.0, 0.0, 1.0), 10.0),
		"A fast grazing contact should remain recoverable when closing speed is low.",
	)
	_expect(
		not Motion.is_fatal_obstacle_impact(Vector3(0.0, 0.0, -6.0), Vector3(0.0, 0.0, 1.0), 10.0),
		"A low-speed bump should not force a restart.",
	)

	if _failures.is_empty():
		print("Sandboard motion passed — carve, landing, and fair fatal-impact envelopes agree.")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _simulate_carve(ticks_per_second: int) -> Vector3:
	var simulated_velocity := Vector3(0.0, 0.0, -54.0)
	var delta := 1.0 / float(ticks_per_second)
	for _frame in range(ticks_per_second):
		var carve := Motion.calculate_carve(
			simulated_velocity,
			Vector3(0.8, 0.0, -0.2),
			Vector3.UP,
			delta,
			78.0,
			2.8,
			1.05,
		)
		simulated_velocity = carve.velocity
	return simulated_velocity


func _simulate_landing_preparation(
	ticks_per_second: int,
	input_strength: float,
	maximum_tangent_speed: float,
) -> Dictionary:
	var surface_normal := Vector3(0.0, 0.9, -0.435).normalized()
	var downhill := Vector3.DOWN.slide(surface_normal).normalized()
	var desired_direction := Vector3(downhill.x, 0.0, downhill.z).normalized() * absf(input_strength)
	if input_strength < 0.0:
		desired_direction = -desired_direction
	var starting_velocity := downhill * 42.0 - surface_normal * 55.0
	var simulated_velocity := starting_velocity
	var result := {}
	var delta := 1.0 / float(ticks_per_second)
	for _frame in range(roundi(float(ticks_per_second) * 0.45)):
		result = Motion.calculate_landing_preparation(
			simulated_velocity,
			desired_direction,
			surface_normal,
			6.0,
			24.0,
			delta,
			8.0,
			9.5,
			maximum_tangent_speed,
		)
		simulated_velocity = result.velocity
	result.starting_velocity = starting_velocity
	result.desired_direction = desired_direction
	result.surface_normal = surface_normal
	return result
