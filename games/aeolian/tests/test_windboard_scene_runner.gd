extends Node

const TEST_CASE := preload("res://tests/test_case.gd")
var _pending_jump := false
var _pending_restart := false
var _scripted_steer := 0.0
var _scripted_tuck := 0.0
var _scripted_brake := 0.0
var _scripted_recover_held := false


func run(game_app: Node) -> void:
	print("AEOLIAN windboard scene tests")
	var suite: RefCounted = TEST_CASE.new()
	game_app.start_foundation_course()
	await get_tree().physics_frame
	var course := game_app.get_node("SessionRoot").get_child(0)
	var player := course.get_node("Windboard") as WindboardController
	player.set_input_provider(_scripted_intent, true)
	await get_tree().physics_frame

	await _test_passive_descent(suite, player)
	await _test_gentle_acceleration(suite, course, player)
	await _test_input_tradeoffs(suite, course, player)
	await _test_contextual_recovery(suite, course, player)
	await _test_jump_and_landing(suite, player)
	await _test_crest_and_compression(suite, course, player)
	await _test_bank_and_rough_contact(suite, course, player)
	await _test_authored_gap(suite, course, player)
	await _test_high_speed_runway(suite, course, player)
	await _test_coyote_hard_recontact(suite, course, player)
	await _test_fatal_wall(suite, course, player)
	await _test_restart(suite, player)

	game_app.return_to_title()
	await get_tree().process_frame
	await get_tree().process_frame
	print("Assertions: %d · Failures: %d" % [suite.assertions, suite.failures])
	get_tree().quit(0 if suite.failures == 0 else mini(suite.failures, 125))


func _test_passive_descent(suite: RefCounted, player: WindboardController) -> void:
	var start := player.global_position
	var start_speed := player.motion_model.velocity.length()
	for frame in 120:
		await get_tree().physics_frame
	var telemetry := player.get_telemetry()
	suite.run_test("real controller traverses the flat start deck", func() -> void:
		suite.assert_true(player.global_position.z < start.z - 4.0)
		suite.assert_true(float(telemetry.speed_mps) > start_speed - 1.0)
		suite.assert_true(player.global_position.is_finite())
		suite.assert_true(player.motion_model.velocity.is_finite())
		suite.assert_not_equal(player.motion_state, WindboardController.MotionState.CRASHED)
	)


func _test_gentle_acceleration(
		suite: RefCounted,
		course: Node,
		player: WindboardController
	) -> void:
	var geometry := course.get_node("CourseGeometry") as MovementCourseGeometry
	var d := 18.0
	var normal := geometry.surface_normal(0.0, d)
	var heading := Vector3.FORWARD.slide(normal).normalized()
	var origin := Vector3(0.0, geometry.surface_height(0.0, d), -d) + Vector3.UP * 0.86
	player.place_for_test(Transform3D(Basis.IDENTITY, origin), heading, 5.0, normal)
	for frame in 120:
		await get_tree().physics_frame
	var telemetry := player.get_telemetry()
	suite.run_test("gravity accelerates the real controller on the gentle slope", func() -> void:
		suite.assert_true(player.global_position.z < -28.0)
		suite.assert_true(float(telemetry.tangent_speed_mps) > 6.0)
		suite.assert_not_equal(player.motion_state, WindboardController.MotionState.CRASHED)
		suite.assert_true(player.global_position.is_finite())
	)


func _test_jump_and_landing(suite: RefCounted, player: WindboardController) -> void:
	player.respawn()
	await get_tree().physics_frame
	var event_start := player.event_history.size()
	_pending_jump = true
	var saw_airborne := false
	var saw_landing := false
	for frame in 240:
		await get_tree().physics_frame
		saw_airborne = saw_airborne or player.motion_state == WindboardController.MotionState.AIRBORNE
		for event: Dictionary in player.event_history.slice(event_start):
			if event.kind == &"landing":
				saw_landing = true
		if saw_airborne and saw_landing:
			break
	suite.run_test("jump creates one airborne interval and a classified landing", func() -> void:
		suite.assert_true(saw_airborne)
		suite.assert_true(saw_landing)
		var landing_count := 0
		for event: Dictionary in player.event_history:
			if event.kind == &"landing":
				landing_count += 1
		suite.assert_equal(landing_count, 1)
		suite.assert_not_equal(player.motion_state, WindboardController.MotionState.CRASHED)
	)


func _test_input_tradeoffs(
		suite: RefCounted,
		course: Node,
		player: WindboardController
	) -> void:
	var geometry := course.get_node("CourseGeometry") as MovementCourseGeometry
	_place_at(player, geometry, 0.0, 18.0, 10.0)
	for frame in 180:
		await get_tree().physics_frame
	var neutral_speed := player.motion_model.velocity.length()

	_place_at(player, geometry, 0.0, 18.0, 10.0)
	_scripted_tuck = 1.0
	for frame in 180:
		await get_tree().physics_frame
	_scripted_tuck = 0.0
	var tuck_speed := player.motion_model.velocity.length()

	_place_at(player, geometry, 0.0, 18.0, 10.0)
	_scripted_brake = 1.0
	for frame in 120:
		await get_tree().physics_frame
	_scripted_brake = 0.0
	var brake_speed := player.motion_model.velocity.length()
	suite.run_test("tuck preserves speed while brake sheds it", func() -> void:
		suite.assert_true(tuck_speed > neutral_speed)
		suite.assert_true(brake_speed < neutral_speed - 3.0)
		suite.assert_true(brake_speed >= 0.0)
	)


func _test_contextual_recovery(
		suite: RefCounted,
		course: Node,
		player: WindboardController
	) -> void:
	var geometry := course.get_node("CourseGeometry") as MovementCourseGeometry
	_place_at(player, geometry, 0.0, 4.0, 4.0)
	player.motion_model.stability = 0.4
	_scripted_recover_held = true
	_pending_jump = true
	for frame in 30:
		await get_tree().physics_frame
	_scripted_recover_held = false
	suite.run_test("low-stability jump input braces instead of launching", func() -> void:
		suite.assert_equal(player.motion_state, WindboardController.MotionState.GROUNDED)
		suite.assert_true(player.motion_model.stability > 0.4)
		var brace_events := 0
		for event: Dictionary in player.event_history:
			if event.kind == &"recover_brace":
				brace_events += 1
		suite.assert_equal(brace_events, 1)
	)

	_place_at(player, geometry, 0.0, 18.0, 10.0)
	_scripted_steer = 0.25
	for frame in 60:
		await get_tree().physics_frame
	_scripted_steer = 0.0
	var low_displacement := absf(player.global_position.x)

	_place_at(player, geometry, 0.0, 18.0, 10.0)
	_scripted_steer = 1.0
	for frame in 60:
		await get_tree().physics_frame
	_scripted_steer = 0.0
	var full_displacement := absf(player.global_position.x)
	suite.run_test("low and full analog steering remain meaningfully distinct", func() -> void:
		suite.assert_true(low_displacement > 0.1)
		suite.assert_true(full_displacement > low_displacement * 2.0)
		suite.assert_true(full_displacement < geometry.half_width(-player.global_position.z))
	)


func _test_restart(suite: RefCounted, player: WindboardController) -> void:
	var before_count := player.respawn_count
	_pending_restart = true
	await get_tree().physics_frame
	suite.run_test("restart input restores a clean controllable state", func() -> void:
		suite.assert_equal(player.respawn_count, before_count + 1)
		suite.assert_true(player.global_position.distance_to(Vector3(0.0, 45.86, -4.0)) < 0.1)
		suite.assert_equal(player.motion_state, WindboardController.MotionState.GROUNDED)
		suite.assert_near(player.motion_model.stability, 1.0, 0.001)
		suite.assert_equal(player.crash_cause, &"")
	)


func _test_crest_and_compression(
		suite: RefCounted,
		course: Node,
		player: WindboardController
	) -> void:
	var geometry := course.get_node("CourseGeometry") as MovementCourseGeometry
	_place_at(player, geometry, 0.0, 66.0, 15.0)
	var crest_air_ticks := 0
	for frame in 90:
		await get_tree().physics_frame
		if player.motion_state == WindboardController.MotionState.AIRBORNE:
			crest_air_ticks += 1
	suite.run_test("smooth crest retains predictable support", func() -> void:
		suite.assert_not_equal(player.motion_state, WindboardController.MotionState.CRASHED)
		suite.assert_true(crest_air_ticks <= 5)
		suite.assert_true(player.global_position.is_finite())
	)

	_place_at(player, geometry, 0.0, 136.0, 20.0)
	var compression_air_ticks := 0
	for frame in 75:
		await get_tree().physics_frame
		if player.motion_state == WindboardController.MotionState.AIRBORNE:
			compression_air_ticks += 1
	suite.run_test("compression remains grounded and nonterminal", func() -> void:
		suite.assert_not_equal(player.motion_state, WindboardController.MotionState.CRASHED)
		suite.assert_equal(compression_air_ticks, 0)
		suite.assert_true(player.motion_model.velocity.is_finite())
	)


func _test_bank_and_rough_contact(
		suite: RefCounted,
		course: Node,
		player: WindboardController
	) -> void:
	var geometry := course.get_node("CourseGeometry") as MovementCourseGeometry
	_place_at(player, geometry, 0.0, 160.0, 15.0)
	var bank_air_ticks := 0
	for frame in 180:
		await get_tree().physics_frame
		if player.motion_state == WindboardController.MotionState.AIRBORNE:
			bank_air_ticks += 1
	suite.run_test("bank ribbon preserves contact", func() -> void:
		suite.assert_not_equal(player.motion_state, WindboardController.MotionState.CRASHED)
		suite.assert_equal(bank_air_ticks, 0)
		suite.assert_true(absf(player.global_position.x) < geometry.half_width(-player.global_position.z))
	)

	_place_at(player, geometry, 0.0, 240.0, 12.0)
	var rough_air_ticks := 0
	for frame in 150:
		await get_tree().physics_frame
		if player.motion_state == WindboardController.MotionState.AIRBORNE:
			rough_air_ticks += 1
	suite.run_test("controlled roughness does not invent a jump", func() -> void:
		suite.assert_not_equal(player.motion_state, WindboardController.MotionState.CRASHED)
		suite.assert_true(rough_air_ticks <= 5)
		suite.assert_true(player.global_position.is_finite())
	)


func _test_authored_gap(
		suite: RefCounted,
		course: Node,
		player: WindboardController
	) -> void:
	var geometry := course.get_node("CourseGeometry") as MovementCourseGeometry
	_place_at(player, geometry, 0.0, 288.0, 22.0)
	var airborne_intervals := 0
	var was_airborne := false
	var landed_after_gap := false
	for frame in 180:
		await get_tree().physics_frame
		var is_airborne := player.motion_state == WindboardController.MotionState.AIRBORNE
		if is_airborne and not was_airborne:
			airborne_intervals += 1
		if was_airborne and player.motion_state == WindboardController.MotionState.GROUNDED:
			landed_after_gap = true
		was_airborne = is_airborne
		if landed_after_gap:
			break
	suite.run_test("authored kicker gap creates one viable terrain jump", func() -> void:
		suite.assert_equal(airborne_intervals, 1)
		suite.assert_true(landed_after_gap)
		suite.assert_not_equal(player.motion_state, WindboardController.MotionState.CRASHED)
		suite.assert_true(-player.global_position.z >= 324.0)
	)


func _test_high_speed_runway(
		suite: RefCounted,
		course: Node,
		player: WindboardController
	) -> void:
	var geometry := course.get_node("CourseGeometry") as MovementCourseGeometry
	_place_at(player, geometry, 7.0, 375.0, 42.0)
	var air_ticks := 0
	for frame in 90:
		await get_tree().physics_frame
		if player.motion_state == WindboardController.MotionState.AIRBORNE:
			air_ticks += 1
	suite.run_test("high-speed runway does not tunnel or false-launch", func() -> void:
		suite.assert_not_equal(player.motion_state, WindboardController.MotionState.CRASHED)
		suite.assert_equal(air_ticks, 0)
		suite.assert_true(-player.global_position.z > 420.0)
		suite.assert_true(player.global_position.is_finite())
		suite.assert_true(player.get_node("Presentation/ContactTrail").visible)
		suite.assert_true(player.get_node("Presentation/SnowSpray").emitting)
	)


func _test_fatal_wall(
		suite: RefCounted,
		course: Node,
		player: WindboardController
	) -> void:
	var geometry := course.get_node("CourseGeometry") as MovementCourseGeometry
	for test_speed: float in [30.0, 42.0]:
		_place_at(player, geometry, -7.0, 462.0, test_speed)
		for frame in 60:
			await get_tree().physics_frame
			if player.motion_state == WindboardController.MotionState.CRASHED:
				break
		suite.run_test("fatal wall at %.0f m/s cannot be tunneled" % test_speed, func() -> void:
			suite.assert_equal(player.motion_state, WindboardController.MotionState.CRASHED)
			suite.assert_equal(player.crash_cause, &"wall_impact")
			suite.assert_true(-player.global_position.z < 478.0)
			suite.assert_true(player.last_wall_impact_mps >= player.tuning.wall_crash_impact_mps)
		)


func _test_coyote_hard_recontact(
		suite: RefCounted,
		course: Node,
		player: WindboardController
	) -> void:
	var geometry := course.get_node("CourseGeometry") as MovementCourseGeometry
	var d := 340.0
	var normal := geometry.surface_normal(0.0, d)
	var heading := Vector3.FORWARD.slide(normal).normalized()
	var origin := Vector3(0.0, geometry.surface_height(0.0, d), -d) \
		+ Vector3.UP * 1.21
	player.place_for_test(Transform3D(Basis.IDENTITY, origin), heading, 0.0, normal)
	player.motion_model.velocity = heading * 10.0 + Vector3.DOWN * 18.0
	player.velocity = player.motion_model.velocity
	player.motion_state = WindboardController.MotionState.COYOTE
	player._coyote_timer = player.tuning.coyote_time_seconds
	for frame in 12:
		await get_tree().physics_frame
		if player.motion_state == WindboardController.MotionState.CRASHED:
			break
	suite.run_test("hard coyote-window recontact is still classified", func() -> void:
		suite.assert_equal(player.motion_state, WindboardController.MotionState.CRASHED)
		suite.assert_equal(player.crash_cause, &"terminal_landing")
		suite.assert_true(float(player.last_landing.impact_speed_mps) >= 16.0)
	)


func _place_at(
		player: WindboardController,
		geometry: MovementCourseGeometry,
		x: float,
		d: float,
		speed_mps: float
	) -> void:
	var normal := geometry.surface_normal(x, d)
	var heading := Vector3.FORWARD.slide(normal).normalized()
	var origin := Vector3(x, geometry.surface_height(x, d), -d) + Vector3.UP * 0.86
	player.place_for_test(Transform3D(Basis.IDENTITY, origin), heading, speed_mps, normal)


func _scripted_intent(_physics_tick: int) -> InputIntent:
	var intent := InputIntent.new()
	intent.steer = _scripted_steer
	intent.tuck = _scripted_tuck
	intent.brake = _scripted_brake
	intent.jump_pressed = _pending_jump
	intent.jump_held = _scripted_recover_held
	intent.restart_pressed = _pending_restart
	_pending_jump = false
	_pending_restart = false
	return intent
