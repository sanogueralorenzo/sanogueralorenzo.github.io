extends SceneTree

const Motion = preload("res://scripts/sandboard_motion.gd")

var _failures: Array[String] = []


func _init() -> void:
	var fast_carve := Motion.calculate_carve(Vector3(0.0, 0.0, -18.0), Vector3.RIGHT, 1.0 / 60.0, 78.0, 2.8, 1.05)
	var high_speed_carve := Motion.calculate_carve(Vector3(0.0, 0.0, -70.0), Vector3.RIGHT, 1.0 / 60.0, 78.0, 2.8, 1.05)
	_expect(absf(fast_carve.turn_angle) > absf(high_speed_carve.turn_angle), "Lower-speed carving should turn more tightly than maximum-speed carving.")
	_expect(absf(high_speed_carve.turn_angle) <= 0.021, "Maximum-speed steering should remain inside the predictable carve envelope.")
	_expect(fast_carve.velocity.length() >= 17.9, "One carve frame should preserve nearly all existing momentum.")
	_expect(fast_carve.direction.x > 0.0 and fast_carve.direction.z < 0.0, "Carving should rotate toward input without snapping to it.")
	var sustained_velocity := Vector3(0.0, 0.0, -70.0)
	for _frame in range(60):
		var sustained := Motion.calculate_carve(sustained_velocity, Vector3.RIGHT, 1.0 / 60.0, 78.0, 2.8, 1.05)
		sustained_velocity = sustained.velocity
	var sustained_direction := sustained_velocity.normalized()
	_expect(sustained_direction.x > 0.7 and sustained_direction.z < -0.2, "A one-second high-speed carve should turn substantially without snapping sideways.")
	_expect(sustained_velocity.length() >= 65.0, "A sustained high-speed carve should retain at least 92% of its momentum.")
	var coasting := Motion.calculate_carve(Vector3(22.0, 0.0, -31.0), Vector3.ZERO, 1.0 / 60.0, 78.0, 2.8, 1.05)
	_expect(coasting.velocity.is_equal_approx(Vector3(22.0, 0.0, -31.0)), "Releasing carve input should not redirect momentum.")

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
