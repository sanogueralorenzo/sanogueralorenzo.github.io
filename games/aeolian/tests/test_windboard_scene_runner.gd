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
	await _test_pause_resume(suite, game_app, course, player)
	_test_terrain_stress_feedback_rate(suite, course, player)
	await _test_recovery_mound(suite, course, player)
	await _test_spawn_to_finish_viability(suite, course, player)
	await _test_finish_and_missed_finish(suite, course, player)
	await _test_coyote_hard_recontact(suite, course, player)
	await _test_fatal_wall(suite, course, player)
	await _test_repeated_restart(suite, game_app, player)

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


func _test_repeated_restart(
		suite: RefCounted,
		game_app: Node,
		player: WindboardController
	) -> void:
	var before_count := player.respawn_count
	var player_id := player.get_instance_id()
	var session_count := game_app.get_node("SessionRoot").get_child_count()
	for attempt in 20:
		_pending_restart = true
		await get_tree().physics_frame
	suite.run_test("twenty input restarts preserve one clean controllable session", func() -> void:
		suite.assert_equal(player.respawn_count, before_count + 20)
		suite.assert_true(player.global_position.distance_to(Vector3(0.0, 45.86, -4.0)) < 0.1)
		suite.assert_equal(player.motion_state, WindboardController.MotionState.GROUNDED)
		suite.assert_near(player.motion_model.stability, 1.0, 0.001)
		suite.assert_equal(player.crash_cause, &"")
		suite.assert_equal(player.get_instance_id(), player_id)
		suite.assert_equal(game_app.get_node("SessionRoot").get_child_count(), session_count)
		suite.assert_true(player.event_history.size() <= WindboardController.EVENT_HISTORY_LIMIT)
		suite.assert_false(game_app.get_node("SessionRoot").get_child(0) \
			.get_node("CourseHud/HudRoot/CrashCenter").visible)
		suite.assert_false(game_app.get_node("SessionRoot").get_child(0) \
			.get_node("CourseHud/HudRoot/CompletionCenter").visible)
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
	player.event_history.clear()
	var rough_air_ticks := 0
	var rough_previous_normal := player.raw_ground_normal
	var rough_maximum_normal_delta := 0.0
	for frame in 150:
		await get_tree().physics_frame
		rough_maximum_normal_delta = maxf(
			rough_maximum_normal_delta,
			rad_to_deg(rough_previous_normal.angle_to(player.raw_ground_normal))
		)
		rough_previous_normal = player.raw_ground_normal
		if player.motion_state == WindboardController.MotionState.AIRBORNE:
			rough_air_ticks += 1
	suite.run_test("controlled roughness does not invent a jump", func() -> void:
		var terrain_stress_count := 0
		for event: Dictionary in player.event_history:
			if event.kind == &"terrain_stress":
				terrain_stress_count += 1
		suite.assert_not_equal(player.motion_state, WindboardController.MotionState.CRASHED)
		suite.assert_true(rough_air_ticks <= 5)
		suite.assert_true(player.global_position.is_finite())
		suite.assert_equal(terrain_stress_count, 0)
		suite.assert_equal(player.last_terrain_stress_damage, 0.0)
		suite.assert_true(
			rough_maximum_normal_delta * 60.0 \
				< player.tuning.terrain_normal_stress_start_deg_per_second
		)
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


func _test_pause_resume(
		suite: RefCounted,
		game_app: Node,
		course: Node,
		player: WindboardController
	) -> void:
	var geometry := course.get_node("CourseGeometry") as MovementCourseGeometry
	_place_at(player, geometry, 0.0, 18.0, 10.0)
	for frame in 12:
		await get_tree().physics_frame
	var paused_position := player.global_position
	var paused_velocity := player.motion_model.velocity
	var paused_tick := player.physics_tick
	game_app.pause_game()
	for frame in 12:
		await get_tree().physics_frame
	var position_while_paused := player.global_position
	var velocity_while_paused := player.motion_model.velocity
	var tick_while_paused := player.physics_tick
	game_app.resume_game()
	await get_tree().physics_frame
	suite.run_test("pause freezes movement and resume adds no impulse", func() -> void:
		suite.assert_equal(position_while_paused, paused_position)
		suite.assert_equal(velocity_while_paused, paused_velocity)
		suite.assert_equal(tick_while_paused, paused_tick)
		suite.assert_equal(player.physics_tick, paused_tick + 1)
		suite.assert_true(player.motion_model.velocity.distance_to(paused_velocity) < 1.0)
		suite.assert_false(get_tree().paused)
	)


func _test_terrain_stress_feedback_rate(
		suite: RefCounted,
		course: Node,
		player: WindboardController
	) -> void:
	var geometry := course.get_node("CourseGeometry") as MovementCourseGeometry
	_place_at(player, geometry, 0.0, 454.0, 0.0)
	player.event_history.clear()
	var normal_a := Vector3.UP
	var normal_b := Vector3.UP.rotated(Vector3.RIGHT, deg_to_rad(12.0))
	player._stress_reference_normal = normal_a
	player._normal_stress_tick = player.physics_tick
	for sample in 12:
		player.physics_tick += 1
		player.raw_ground_normal = normal_b if sample % 2 == 0 else normal_a
		player._filter_ground_normal(1.0 / 60.0)
	var terrain_stress_count := 0
	for event: Dictionary in player.event_history:
		if event.kind == &"terrain_stress":
			terrain_stress_count += 1
	suite.run_test("sustained terrain stress rate-limits transient feedback", func() -> void:
		suite.assert_true(player.motion_model.stability < 0.5)
		suite.assert_equal(terrain_stress_count, 1)
	)


func _test_recovery_mound(
		suite: RefCounted,
		course: Node,
		player: WindboardController
	) -> void:
	var geometry := course.get_node("CourseGeometry") as MovementCourseGeometry
	_place_at(player, geometry, 0.0, 454.0, 22.0)
	player.event_history.clear()
	var minimum_stability := player.motion_model.stability
	var airborne_ticks := 0
	var saw_recovery_prompt := false
	var previous_normal := player.raw_ground_normal
	var maximum_normal_delta_deg := 0.0
	for frame in 60:
		_scripted_recover_held = frame >= 24
		await get_tree().physics_frame
		minimum_stability = minf(minimum_stability, player.motion_model.stability)
		maximum_normal_delta_deg = maxf(
			maximum_normal_delta_deg,
			rad_to_deg(previous_normal.angle_to(player.raw_ground_normal))
		)
		previous_normal = player.raw_ground_normal
		if player.motion_state == WindboardController.MotionState.AIRBORNE:
			airborne_ticks += 1
		saw_recovery_prompt = saw_recovery_prompt \
			or course.get_node("CourseHud/HudRoot/RecoveryPrompt").visible
	_scripted_recover_held = false
	var landing_count := 0
	var landing_impact := 0.0
	var terrain_stress_count := 0
	var landing_ticks: Dictionary = {}
	var stress_ticks: Dictionary = {}
	for event: Dictionary in player.event_history:
		if event.kind == &"landing":
			landing_count += 1
			landing_impact = maxf(landing_impact, float(event.data.impact_speed_mps))
			landing_ticks[int(event.tick)] = true
		elif event.kind == &"terrain_stress":
			terrain_stress_count += 1
			stress_ticks[int(event.tick)] = true
	suite.run_test("recovery mound causes readable nonterminal instability", func() -> void:
		suite.assert_not_equal(player.motion_state, WindboardController.MotionState.CRASHED)
		suite.assert_true(-player.global_position.z > 466.0)
		suite.assert_true(
			minimum_stability < 0.99,
			"Expected mound stability loss; min=%.3f air=%d landings=%d impact=%.3f normal=%.2f" % [
				minimum_stability,
				airborne_ticks,
				landing_count,
				landing_impact,
				maximum_normal_delta_deg,
			]
		)
		suite.assert_true(player.motion_model.stability > minimum_stability)
		suite.assert_true(airborne_ticks > 0 or landing_count > 0)
		suite.assert_true(terrain_stress_count > 0)
		suite.assert_true(saw_recovery_prompt)
		for tick: int in landing_ticks:
			suite.assert_false(stress_ticks.has(tick))
	)


func _test_spawn_to_finish_viability(
		suite: RefCounted,
		course: Node,
		player: WindboardController
	) -> void:
	var analog_result := await _run_spawn_to_finish_policy(course, player, true)
	_assert_spawn_to_finish_result(suite, analog_result, "analog")
	var keyboard_result := await _run_spawn_to_finish_policy(course, player, false)
	_assert_spawn_to_finish_result(suite, keyboard_result, "keyboard")
	player.set_input_provider(_scripted_intent, true)


func _run_spawn_to_finish_policy(
		course: Node,
		player: WindboardController,
		use_analog_filter: bool
	) -> Dictionary:
	await _restart_and_wait(player)
	var start_tick := player.physics_tick
	var maximum_speed_mps := 0.0
	var maximum_lateral_position_m := 0.0
	var saw_authored_gap_airborne := false
	for frame in 3600:
		var downhill_distance := -player.global_position.z
		var target_x := 8.0 if downhill_distance >= 410.0 else 0.0
		if not use_analog_filter:
			target_x = 8.0 * clampf(inverse_lerp(370.0, 450.0, downhill_distance), 0.0, 1.0)
		var target_error := target_x - player.global_position.x
		if use_analog_filter:
			_scripted_steer = clampf(target_error * 0.12, -0.65, 0.65)
		else:
			var digital_correction := target_error * 0.35 \
				- player.motion_model.velocity.x * 0.8
			_scripted_steer = signf(digital_correction) \
				if absf(digital_correction) > 0.25 else 0.0
		await get_tree().physics_frame
		maximum_speed_mps = maxf(maximum_speed_mps, player.motion_model.velocity.length())
		maximum_lateral_position_m = maxf(
			maximum_lateral_position_m, absf(player.global_position.x)
		)
		var current_distance := -player.global_position.z
		if current_distance >= MovementCourseGeometry.GAP_START_D - 1.0 \
				and current_distance <= MovementCourseGeometry.GAP_END_D + 8.0 \
				and player.motion_state == WindboardController.MotionState.AIRBORNE:
			saw_authored_gap_airborne = true
		if player.motion_state == WindboardController.MotionState.FINISHED \
				or player.motion_state == WindboardController.MotionState.CRASHED:
			break
	_scripted_steer = 0.0
	return {
		"motion_state": player.motion_state,
		"crash_cause": player.crash_cause,
		"saw_authored_gap_airborne": saw_authored_gap_airborne,
		"maximum_speed_mps": maximum_speed_mps,
		"maximum_lateral_position_m": maximum_lateral_position_m,
		"elapsed_ticks": player.physics_tick - start_tick,
		"lane_x": float(player.last_completion.get("lane_x", NAN)),
		"maximum_air_speed_mps": player.tuning.max_air_speed_mps,
	}


func _assert_spawn_to_finish_result(
		suite: RefCounted,
		result: Dictionary,
		input_label: String
	) -> void:
	suite.run_test(
		"%s input traverses continuously from spawn to finish" % input_label,
		func() -> void:
			suite.assert_equal(
				int(result.motion_state), WindboardController.MotionState.FINISHED
			)
			suite.assert_equal(StringName(result.crash_cause), &"")
			suite.assert_true(bool(result.saw_authored_gap_airborne))
			suite.assert_true(float(result.maximum_speed_mps) > 20.0)
			suite.assert_true(
				float(result.maximum_speed_mps) \
					<= float(result.maximum_air_speed_mps) + 0.01
			)
			suite.assert_true(float(result.maximum_lateral_position_m) < 14.5)
			suite.assert_true(int(result.elapsed_ticks) < 3600)
			suite.assert_true(
				float(result.lane_x) >= MovementCourseGeometry.FINISH_MIN_X
			)
			suite.assert_true(
				float(result.lane_x) <= MovementCourseGeometry.FINISH_MAX_X
			)
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
			suite.assert_true(course.get_node("CourseHud/HudRoot/CrashCenter").visible)
			suite.assert_equal(
				course.get_node("CourseHud/HudRoot/CrashCenter/Panel/Content/CrashReason").text,
				"IMPACT TOO HARD"
			)
		)


func _test_finish_and_missed_finish(
		suite: RefCounted,
		course: Node,
		player: WindboardController
	) -> void:
	var geometry := course.get_node("CourseGeometry") as MovementCourseGeometry
	await _restart_and_wait(player)
	var run_start_tick: int = course._run_start_tick
	var state_transitions: Array[Vector2i] = []
	var record_transition := func(previous: WindboardController.MotionState, current: WindboardController.MotionState) -> void:
		state_transitions.append(Vector2i(previous, current))
	player.motion_state_changed.connect(record_transition)
	_place_at(player, geometry, 6.0, 478.0, 12.0)
	player.event_history.clear()
	for frame in 90:
		await get_tree().physics_frame
		if player.motion_state == WindboardController.MotionState.FINISHED:
			break
	var finish_events := 0
	var finish_tick := -1
	for event: Dictionary in player.event_history:
		if event.kind == &"finish":
			finish_events += 1
			finish_tick = int(event.tick)
	suite.run_test("authored finish lane ends the course exactly once", func() -> void:
		suite.assert_equal(player.motion_state, WindboardController.MotionState.FINISHED)
		suite.assert_equal(player.get_telemetry().state, &"finished")
		suite.assert_near(player.motion_model.velocity.length(), 0.0, 0.001)
		suite.assert_equal(finish_events, 1)
		var expected_elapsed := float(finish_tick - run_start_tick) \
			/ float(Engine.physics_ticks_per_second)
		suite.assert_near(
			float(player.last_completion.elapsed_seconds), expected_elapsed, 0.000001
		)
		suite.assert_true(course.get_node("CourseHud/HudRoot/CompletionCenter").visible)
		suite.assert_false(course.get_node("CourseHud/HudRoot/CrashCenter").visible)
	)
	await _restart_and_wait(player)
	suite.run_test("finish restart returns to a clean controllable descent", func() -> void:
		suite.assert_equal(player.motion_state, WindboardController.MotionState.GROUNDED)
		suite.assert_true(player.last_completion.is_empty())
		suite.assert_false(course.get_node("CourseHud/HudRoot/CompletionCenter").visible)
		suite.assert_equal(
			state_transitions.count(Vector2i(
				WindboardController.MotionState.FINISHED,
				WindboardController.MotionState.GROUNDED
			)),
			1
		)
	)

	_place_at(player, geometry, 0.0, 482.0, 12.0)
	for frame in 45:
		await get_tree().physics_frame
		if -player.global_position.z > MovementCourseGeometry.FINISH_TRIGGER_D + 0.2:
			break
	_place_at(player, geometry, 6.0, 484.0, 12.0)
	await get_tree().physics_frame
	suite.run_test("entering the lane after crossing the gate cannot finish", func() -> void:
		suite.assert_not_equal(player.motion_state, WindboardController.MotionState.FINISHED)
	)
	for frame in 90:
		await get_tree().physics_frame
		if player.motion_state == WindboardController.MotionState.CRASHED:
			break
	suite.run_test("missing the authored gate ends instead of falling forever", func() -> void:
		suite.assert_equal(player.motion_state, WindboardController.MotionState.CRASHED)
		suite.assert_equal(player.crash_cause, &"missed_finish")
		suite.assert_equal(
			course.get_node("CourseHud/HudRoot/CrashCenter/Panel/Content/CrashReason").text,
			"MISSED FINISH GATE"
		)
		suite.assert_true(course.get_node("CourseHud/HudRoot/CrashCenter").visible)
	)
	await _restart_and_wait(player)
	suite.run_test("crash restart publishes the terminal state exit", func() -> void:
		suite.assert_equal(
			state_transitions.count(Vector2i(
				WindboardController.MotionState.CRASHED,
				WindboardController.MotionState.GROUNDED
			)),
			1
		)
	)
	player.motion_state_changed.disconnect(record_transition)


func _test_coyote_hard_recontact(
		suite: RefCounted,
		course: Node,
		player: WindboardController
	) -> void:
	_pending_restart = false
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
	player.event_history.clear()
	for frame in 12:
		await get_tree().physics_frame
		if player.motion_state == WindboardController.MotionState.CRASHED:
			break
	suite.run_test("hard coyote-window recontact is still classified", func() -> void:
		var terrain_stress_count := 0
		for event: Dictionary in player.event_history:
			if event.kind == &"terrain_stress":
				terrain_stress_count += 1
		suite.assert_equal(player.motion_state, WindboardController.MotionState.CRASHED)
		suite.assert_equal(player.crash_cause, &"terminal_landing")
		suite.assert_true(float(player.last_landing.get("impact_speed_mps", 0.0)) >= 16.0)
		suite.assert_equal(terrain_stress_count, 0)
	)

	await _restart_and_wait(player)
	var lateral := normal.cross(heading).normalized()
	player.place_for_test(Transform3D(Basis.IDENTITY, origin), heading, 0.0, normal)
	player.motion_model.velocity = lateral * 10.0 - normal * 7.0
	player.velocity = player.motion_model.velocity
	player.motion_state = WindboardController.MotionState.COYOTE
	player._coyote_timer = player.tuning.coyote_time_seconds
	for frame in 12:
		await get_tree().physics_frame
		if player.motion_state == WindboardController.MotionState.CRASHED:
			break
	suite.run_test("misaligned low-closure coyote recontact cannot bypass landing", func() -> void:
		suite.assert_equal(player.motion_state, WindboardController.MotionState.CRASHED)
		suite.assert_equal(player.crash_cause, &"terminal_landing")
		suite.assert_true(float(player.last_landing.get("impact_speed_mps", 0.0)) < 8.0)
		suite.assert_true(
			float(player.last_landing.get("alignment", 1.0)) \
				<= player.tuning.crash_landing_alignment
		)
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


func _restart_and_wait(player: WindboardController) -> void:
	var previous_count := player.respawn_count
	_pending_restart = true
	for frame in 4:
		await get_tree().physics_frame
		if player.respawn_count > previous_count:
			_pending_restart = false
			return
	_pending_restart = false


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
