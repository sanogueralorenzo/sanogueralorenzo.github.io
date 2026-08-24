extends RefCounted

const GROUND_NORMAL := Vector3.UP
const DOWNHILL_NORMAL := Vector3(0.0, 0.8660254, -0.5)


static func run(suite: RefCounted) -> void:
	print("WindboardMotionModel")
	suite.run_test("flat hardpack removes speed without reversing", func() -> void:
		var model := _model_at_speed(12.0)
		_step_ground_for(model, 1.0, 60, _intent(), GROUND_NORMAL)
		var tangent_speed := model.velocity.slide(GROUND_NORMAL).length()
		suite.assert_true(tangent_speed < 12.0)
		suite.assert_true(tangent_speed > 0.0)
	)
	suite.run_test("projected gravity accelerates down a slope", func() -> void:
		var model := _model_at_speed(2.0)
		_step_ground_for(model, 2.0, 120, _intent(), DOWNHILL_NORMAL)
		suite.assert_true(
			model.velocity.slide(DOWNHILL_NORMAL).length() > 9.0,
			"A 30 degree slope should produce substantial gravity-driven acceleration"
		)
	)
	suite.run_test("tuck preserves more speed and brake removes more", func() -> void:
		var neutral := _model_at_speed(20.0)
		var tucked := _model_at_speed(20.0)
		var braking := _model_at_speed(20.0)
		_step_ground_for(neutral, 1.0, 60, _intent(), GROUND_NORMAL)
		_step_ground_for(tucked, 1.0, 60, _intent(0.0, 1.0), GROUND_NORMAL)
		_step_ground_for(braking, 1.0, 60, _intent(0.0, 0.0, 1.0), GROUND_NORMAL)
		var neutral_speed := neutral.velocity.slide(GROUND_NORMAL).length()
		suite.assert_true(tucked.velocity.slide(GROUND_NORMAL).length() > neutral_speed)
		suite.assert_true(braking.velocity.slide(GROUND_NORMAL).length() < neutral_speed)
	)
	suite.run_test("steering rotates heading while bounded grip redirects momentum", func() -> void:
		var model := _model_at_speed(18.0)
		_step_ground_for(model, 0.5, 30, _intent(1.0), GROUND_NORMAL)
		suite.assert_true(absf(model.heading.x) > 0.1)
		var travel := model.velocity.slide(GROUND_NORMAL).normalized()
		suite.assert_true(travel.dot(Vector3.FORWARD) < 0.999)
		suite.assert_true(model.velocity.slide(GROUND_NORMAL).length() < 18.0)
	)
	suite.run_test("air control redirects without adding horizontal energy", func() -> void:
		var model := _model_at_speed(16.0)
		var initial_horizontal_speed := model.velocity.slide(Vector3.UP).length()
		var intent := _intent(1.0)
		for frame in 60:
			model.step_air(1.0 / 60.0, intent, _tuning())
		var final_horizontal_speed := model.velocity.slide(Vector3.UP).length()
		suite.assert_true(final_horizontal_speed <= initial_horizontal_speed + 0.001)
		suite.assert_true(final_horizontal_speed > initial_horizontal_speed - 0.3)
		suite.assert_true(absf(model.velocity.x) > 0.1)
		suite.assert_true(model.velocity.y < -10.0)
	)
	suite.run_test("jump removes inward speed and adds surface-normal impulse", func() -> void:
		var model := _model_at_speed(10.0)
		model.velocity.y = -3.0
		model.jump(Vector3.UP, _tuning(), _surface())
		suite.assert_near(model.velocity.y, 7.0, 0.001)
		suite.assert_near(model.velocity.z, -10.0, 0.001)
	)
	suite.run_test("landing classification separates clean recoverable and terminal", func() -> void:
		var tuning := _tuning()
		var surface := _surface()
		var clean := WindboardMotionModel.classify_landing(
			Vector3(0.0, -5.0, -12.0), Vector3.UP, Vector3.FORWARD, tuning, surface
		)
		var recoverable := WindboardMotionModel.classify_landing(
			Vector3(0.0, -10.0, -12.0), Vector3.UP, Vector3.FORWARD, tuning, surface
		)
		var terminal := WindboardMotionModel.classify_landing(
			Vector3(0.0, -17.0, -12.0), Vector3.UP, Vector3.FORWARD, tuning, surface
		)
		suite.assert_equal(clean.severity, WindboardMotionModel.LandingSeverity.CLEAN)
		suite.assert_equal(
			recoverable.severity, WindboardMotionModel.LandingSeverity.RECOVERABLE
		)
		suite.assert_equal(terminal.severity, WindboardMotionModel.LandingSeverity.CRASH)
		suite.assert_true(float(recoverable.stability_damage) > 0.0)
	)
	suite.run_test("misaligned landing only crashes above the impact floor", func() -> void:
		var tuning := _tuning()
		var surface := _surface()
		var low_impact := WindboardMotionModel.classify_landing(
			Vector3(10.0, -3.0, 0.0), Vector3.UP, Vector3.FORWARD, tuning, surface
		)
		var high_impact := WindboardMotionModel.classify_landing(
			Vector3(10.0, -7.0, 0.0), Vector3.UP, Vector3.FORWARD, tuning, surface
		)
		suite.assert_equal(
			low_impact.severity, WindboardMotionModel.LandingSeverity.RECOVERABLE
		)
		suite.assert_equal(high_impact.severity, WindboardMotionModel.LandingSeverity.CRASH)
	)
	suite.run_test("backward landing is not treated as forward alignment", func() -> void:
		var result := WindboardMotionModel.classify_landing(
			Vector3(0.0, -7.0, 10.0),
			Vector3.UP,
			Vector3.FORWARD,
			_tuning(),
			_surface()
		)
		suite.assert_true(float(result.alignment) < 0.0)
		suite.assert_equal(result.severity, WindboardMotionModel.LandingSeverity.CRASH)
	)
	suite.run_test("wall impact uses incoming normal speed", func() -> void:
		suite.assert_near(
			WindboardMotionModel.wall_impact_speed(Vector3(12.0, 0.0, -4.0), Vector3.LEFT),
			12.0,
			0.001
		)
		suite.assert_near(
			WindboardMotionModel.wall_impact_speed(Vector3(1.0, 0.0, -12.0), Vector3.LEFT),
			1.0,
			0.001
		)
	)
	suite.run_test("slip drains stability and composed travel recovers it", func() -> void:
		var model := WindboardMotionModel.new()
		model.reset(Vector3.FORWARD, Vector3(14.0, 0.0, -2.0))
		_step_ground_for(model, 0.25, 15, _intent(), GROUND_NORMAL)
		var drained := model.stability
		suite.assert_true(drained < 1.0)
		model.velocity = Vector3.FORWARD * 12.0
		_step_ground_for(model, 1.0, 60, _intent(), GROUND_NORMAL)
		suite.assert_true(model.stability > drained)
	)
	suite.run_test("backward travel drains stability instead of appearing composed", func() -> void:
		var model := WindboardMotionModel.new()
		model.reset(Vector3.FORWARD, Vector3.BACK * 12.0)
		model.step_ground(1.0 / 60.0, GROUND_NORMAL, _intent(), _tuning(), _surface())
		suite.assert_true(model.stability < 1.0)
	)
	suite.run_test("held recover accelerates stability return without adding speed", func() -> void:
		var normal_recovery := _model_at_speed(12.0)
		var held_recovery := _model_at_speed(12.0)
		normal_recovery.stability = 0.4
		held_recovery.stability = 0.4
		var held := _intent()
		held.jump_held = true
		_step_ground_for(normal_recovery, 0.5, 30, _intent(), GROUND_NORMAL)
		_step_ground_for(held_recovery, 0.5, 30, held, GROUND_NORMAL)
		suite.assert_true(held_recovery.stability > normal_recovery.stability)
		suite.assert_near(
			held_recovery.velocity.length(), normal_recovery.velocity.length(), 0.001
		)
	)
	suite.run_test("rapid terrain-normal change causes bounded stability stress", func() -> void:
		var model := _model_at_speed(12.0)
		var tuning := _tuning()
		var surface := _surface()
		var below_threshold := model.apply_terrain_normal_stress(
			4.0, 1.0 / 60.0, tuning, surface
		)
		var abrupt_change := model.apply_terrain_normal_stress(
			12.0, 1.0 / 60.0, tuning, surface
		)
		suite.assert_near(below_threshold, 0.0, 0.0001)
		suite.assert_near(abrupt_change, 0.175, 0.001)
		suite.assert_near(model.stability, 0.825, 0.001)
		suite.assert_near(
			model.apply_terrain_normal_stress(NAN, 1.0 / 60.0, tuning, surface),
			0.0,
			0.0001
		)
	)
	suite.run_test("held air recovery aligns heading toward actual travel", func() -> void:
		var neutral := WindboardMotionModel.new()
		var recovering := WindboardMotionModel.new()
		neutral.reset(Vector3.FORWARD, Vector3.RIGHT * 12.0)
		recovering.reset(Vector3.FORWARD, Vector3.RIGHT * 12.0)
		var held := _intent()
		held.jump_held = true
		for frame in 30:
			neutral.step_air(1.0 / 60.0, _intent(), _tuning())
			recovering.step_air(1.0 / 60.0, held, _tuning())
		var travel := recovering.velocity.slide(Vector3.UP).normalized()
		suite.assert_true(recovering.heading.dot(travel) > neutral.heading.dot(travel))
	)
	suite.run_test("speed safety rails bound ground and air velocity", func() -> void:
		var ground := _model_at_speed(100.0)
		ground.step_ground(1.0 / 60.0, GROUND_NORMAL, _intent(), _tuning(), _surface())
		suite.assert_true(ground.velocity.slide(GROUND_NORMAL).length() <= 42.001)
		var air := _model_at_speed(100.0)
		air.step_air(1.0 / 60.0, _intent(), _tuning())
		suite.assert_true(air.velocity.length() <= 48.001)
	)
	suite.run_test("non-finite analog input is ignored", func() -> void:
		var model := _model_at_speed(10.0)
		var intent := _intent(NAN, INF, -INF)
		model.step_ground(1.0 / 60.0, GROUND_NORMAL, intent, _tuning(), _surface())
		suite.assert_true(model.heading.is_finite())
		suite.assert_true(model.velocity.is_finite())
		suite.assert_true(is_finite(model.stability))
	)
	suite.run_test("equal-time integration converges at 30 60 and 120 hertz", func() -> void:
		var at_30 := _simulate_ground(30)
		var at_60 := _simulate_ground(60)
		var at_120 := _simulate_ground(120)
		var speed_30 := at_30.velocity.slide(DOWNHILL_NORMAL).length()
		var speed_60 := at_60.velocity.slide(DOWNHILL_NORMAL).length()
		var speed_120 := at_120.velocity.slide(DOWNHILL_NORMAL).length()
		suite.assert_near(speed_30, speed_60, 0.2)
		suite.assert_near(speed_60, speed_120, 0.1)
		suite.assert_true(at_30.heading.dot(at_60.heading) > 0.999)
		suite.assert_true(at_60.heading.dot(at_120.heading) > 0.999)
	)


static func _model_at_speed(speed: float) -> WindboardMotionModel:
	var model := WindboardMotionModel.new()
	model.reset(Vector3.FORWARD, Vector3.FORWARD * speed)
	return model


static func _intent(steer := 0.0, tuck := 0.0, brake := 0.0) -> InputIntent:
	var intent := InputIntent.new()
	intent.steer = steer
	intent.tuck = tuck
	intent.brake = brake
	return intent


static func _tuning() -> WindboardTuning:
	return WindboardTuning.new()


static func _surface() -> SurfaceProfile:
	return SurfaceProfile.new()


static func _step_ground_for(
		model: WindboardMotionModel,
		duration: float,
		steps: int,
		intent: InputIntent,
		normal: Vector3
	) -> void:
	var delta := duration / float(steps)
	for frame in steps:
		model.step_ground(delta, normal, intent, _tuning(), _surface())


static func _simulate_ground(physics_hz: int) -> WindboardMotionModel:
	var model := _model_at_speed(8.0)
	_step_ground_for(model, 2.0, physics_hz * 2, _intent(0.55, 0.25), DOWNHILL_NORMAL)
	return model
