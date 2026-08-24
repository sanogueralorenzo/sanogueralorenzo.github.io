class_name WindboardController
extends CharacterBody3D

signal motion_state_changed(previous: MotionState, current: MotionState)
signal landed(result: Dictionary)
signal crashed(cause: StringName, details: Dictionary)
signal respawned(count: int)
signal destabilized(amount: float, cause: StringName)

enum MotionState {
	GROUNDED,
	COYOTE,
	AIRBORNE,
	CRASHED,
}

const EVENT_HISTORY_LIMIT := 24

@export var tuning: WindboardTuning = preload("res://player/default_windboard_tuning.tres")
@export var surface: SurfaceProfile = preload("res://biomes/frost/surfaces/hardpack.tres")
@export_range(0.0, 20.0, 0.1, "suffix:m/s") var initial_speed_mps := 4.0

@onready var support_now: ShapeCast3D = %SupportNow
@onready var support_ahead: ShapeCast3D = %SupportAhead

var motion_model := WindboardMotionModel.new()
var input_filter := WindboardInputFilter.new()
var motion_state := MotionState.GROUNDED
var respawn_count := 0
var physics_tick := 0

var raw_ground_normal := Vector3.UP
var filtered_ground_normal := Vector3.UP
var last_landing: Dictionary = {}
var last_wall_impact_mps := 0.0
var last_terrain_stress_damage := 0.0
var last_requested_velocity := Vector3.ZERO
var raw_intent := InputIntent.new()
var filtered_intent := InputIntent.new()
var crash_cause: StringName = &""
var event_history: Array[Dictionary] = []

var _spawn_transform := Transform3D.IDENTITY
var _coyote_timer := 0.0
var _recontact_timer := 0.0
var _airborne_seconds := 0.0
var _zero_stability_seconds := 0.0
var _intent_provider := Callable()
var _input_provider_is_gamepad := false
var _ignore_cached_floor := true
var _stress_reference_normal := Vector3.UP
var _normal_stress_tick := -1
var _terrain_stress_feedback_cooldown := 0.0


func _ready() -> void:
	_spawn_transform = global_transform
	up_direction = Vector3.UP
	motion_mode = CharacterBody3D.MOTION_MODE_GROUNDED
	floor_stop_on_slope = false
	floor_constant_speed = false
	floor_block_on_wall = true
	slide_on_ceiling = false
	max_slides = 8
	platform_floor_layers = 0
	platform_on_leave = CharacterBody3D.PLATFORM_ON_LEAVE_DO_NOTHING
	floor_max_angle = deg_to_rad(tuning.maximum_floor_angle_deg)
	floor_snap_length = tuning.floor_snap_length_m
	safe_margin = tuning.collision_safe_margin_m
	support_now.target_position = Vector3.DOWN * tuning.ground_probe_length_m
	for cast: ShapeCast3D in [support_now, support_ahead]:
		var probe_sphere := cast.shape as SphereShape3D
		if probe_sphere != null:
			probe_sphere.radius = tuning.probe_shape_radius_m
	add_to_group(&"windboard_player")
	_reset_motion(false)


func _physics_process(delta: float) -> void:
	physics_tick += 1
	var intent := _sample_intent(delta)
	if intent.restart_pressed:
		respawn()
		return
	if motion_state == MotionState.CRASHED:
		return

	_coyote_timer = maxf(0.0, _coyote_timer - delta)
	_recontact_timer = maxf(0.0, _recontact_timer - delta)
	var contact := _read_ground_contact()
	var has_supported_contact := bool(contact.hit) and _recontact_timer <= 0.0
	if has_supported_contact:
		raw_ground_normal = contact.normal
		_filter_ground_normal(delta)

	match motion_state:
		MotionState.GROUNDED:
			if has_supported_contact:
				motion_model.step_ground(delta, filtered_ground_normal, intent, tuning, surface)
				if intent.jump_pressed \
						and motion_model.stability >= tuning.grounded_recover_threshold:
					_takeoff(filtered_ground_normal, &"jump")
				elif intent.jump_pressed:
					_record_event(&"recover_brace", {"stability": motion_model.stability})
			else:
				_enter_coyote()
				motion_model.step_air(delta, intent, tuning)
		MotionState.COYOTE:
			if has_supported_contact:
				_set_motion_state(MotionState.GROUNDED, &"contact_recovered")
				motion_model.step_ground(delta, filtered_ground_normal, intent, tuning, surface)
			elif intent.jump_pressed and _coyote_timer > 0.0:
				motion_model.step_air(delta, intent, tuning)
				_takeoff(filtered_ground_normal, &"coyote_jump")
			else:
				motion_model.step_air(delta, intent, tuning)
				if _coyote_timer <= 0.0:
					_set_motion_state(MotionState.AIRBORNE, &"contact_lost")
		MotionState.AIRBORNE:
			_airborne_seconds += delta
			motion_model.step_air(delta, intent, tuning)

	var incoming_velocity := motion_model.velocity
	last_requested_velocity = incoming_velocity
	velocity = incoming_velocity
	move_and_slide()
	motion_model.velocity = get_real_velocity() if is_on_floor() else velocity
	if _classify_wall_collisions(incoming_velocity):
		return

	var physical_floor := is_on_floor() and _recontact_timer <= 0.0
	if physical_floor:
		raw_ground_normal = get_floor_normal()
		_filter_ground_normal(delta)
		if motion_state == MotionState.AIRBORNE:
			_process_landing(incoming_velocity, raw_ground_normal)
		elif motion_state == MotionState.COYOTE:
			var closure_speed := maxf(0.0, -incoming_velocity.dot(raw_ground_normal))
			if closure_speed > tuning.clean_landing_impact_mps \
					or motion_model.stability < tuning.grounded_recover_threshold:
				_process_landing(incoming_velocity, raw_ground_normal)
			else:
				_set_motion_state(MotionState.GROUNDED, &"contact_recovered")
	elif motion_state == MotionState.GROUNDED and not has_supported_contact:
		_enter_coyote()

	if motion_model.stability <= 0.0:
		_zero_stability_seconds += delta
	else:
		_zero_stability_seconds = 0.0
	if _zero_stability_seconds >= tuning.zero_stability_crash_delay_seconds:
		_crash(&"stability_exhausted", {"stability": motion_model.stability})


func respawn() -> void:
	respawn_count += 1
	global_transform = _spawn_transform
	reset_physics_interpolation()
	_reset_motion(true)
	respawned.emit(respawn_count)


func set_spawn_transform(value: Transform3D) -> void:
	_spawn_transform = value


func set_input_provider(provider: Callable, is_gamepad := false) -> void:
	_intent_provider = provider
	_input_provider_is_gamepad = is_gamepad


func clear_input_provider() -> void:
	_intent_provider = Callable()
	_input_provider_is_gamepad = false


func place_for_test(
		target: Transform3D,
		travel_heading: Vector3,
		speed_mps: float,
		ground_normal := Vector3.UP
	) -> void:
	global_transform = target
	reset_physics_interpolation()
	motion_model.reset(travel_heading, travel_heading.normalized() * speed_mps)
	input_filter.reset()
	velocity = motion_model.velocity
	motion_state = MotionState.GROUNDED
	raw_ground_normal = ground_normal.normalized()
	filtered_ground_normal = raw_ground_normal
	last_landing.clear()
	last_wall_impact_mps = 0.0
	last_terrain_stress_damage = 0.0
	_stress_reference_normal = raw_ground_normal
	_normal_stress_tick = physics_tick
	_terrain_stress_feedback_cooldown = 0.0
	_coyote_timer = 0.0
	_recontact_timer = 0.0
	_airborne_seconds = 0.0
	_zero_stability_seconds = 0.0
	crash_cause = &""
	_ignore_cached_floor = true
	support_now.force_shapecast_update()


func get_telemetry() -> Dictionary:
	var normal := filtered_ground_normal.normalized()
	var tangent_velocity := motion_model.velocity.slide(normal)
	var longitudinal_speed := tangent_velocity.dot(motion_model.heading)
	var lateral_speed := (tangent_velocity - motion_model.heading * longitudinal_speed).length()
	return {
		"physics_tick": physics_tick,
		"state": state_label(motion_state),
		"speed_mps": motion_model.velocity.length(),
		"requested_speed_mps": last_requested_velocity.length(),
		"tangent_speed_mps": tangent_velocity.length(),
		"lateral_speed_mps": lateral_speed,
		"slip_ratio": lateral_speed / maxf(tangent_velocity.length(), 0.001),
		"stability": motion_model.stability,
		"is_on_floor": is_on_floor(),
		"support_now": support_now.is_colliding(),
		"support_ahead": support_ahead.is_colliding(),
		"raw_normal": raw_ground_normal,
		"filtered_normal": filtered_ground_normal,
		"slope_degrees": rad_to_deg(normal.angle_to(Vector3.UP)),
		"heading": motion_model.heading,
		"surface": surface.id,
		"coyote_seconds": _coyote_timer,
		"recontact_seconds": _recontact_timer,
		"airborne_seconds": _airborne_seconds,
		"zero_stability_seconds": _zero_stability_seconds,
		"last_landing": last_landing.duplicate(true),
		"last_wall_impact_mps": last_wall_impact_mps,
		"last_terrain_stress_damage": last_terrain_stress_damage,
		"crash_cause": crash_cause,
		"respawn_count": respawn_count,
		"raw_steer": raw_intent.steer,
		"filtered_steer": filtered_intent.steer,
	}


static func state_label(value: MotionState) -> StringName:
	match value:
		MotionState.GROUNDED:
			return &"grounded"
		MotionState.COYOTE:
			return &"coyote"
		MotionState.AIRBORNE:
			return &"airborne"
		MotionState.CRASHED:
			return &"crashed"
	return &"unknown"


func _sample_intent(delta: float) -> InputIntent:
	if _intent_provider.is_valid():
		var supplied: Variant = _intent_provider.call(physics_tick)
		if supplied is InputIntent:
			raw_intent = supplied
		else:
			raw_intent = InputIntent.new()
	else:
		raw_intent = InputService.sample_intent()
	var sensitivity := float(SettingsStore.get_setting(&"controls", &"steer_sensitivity"))
	filtered_intent = input_filter.step(
		raw_intent,
		delta,
		_input_provider_is_gamepad if _intent_provider.is_valid() \
			else InputService.active_device_kind == InputService.DeviceKind.GAMEPAD,
		sensitivity,
		tuning
	)
	return filtered_intent


func _read_ground_contact() -> Dictionary:
	_update_support_ahead()
	if not _ignore_cached_floor and is_on_floor():
		return {"hit": true, "normal": get_floor_normal(), "source": &"slide"}
	_ignore_cached_floor = false
	support_now.force_shapecast_update()
	var best_separation := INF
	var best_normal := Vector3.UP
	for collision_index in support_now.get_collision_count():
		var candidate_normal := support_now.get_collision_normal(collision_index)
		if rad_to_deg(candidate_normal.angle_to(Vector3.UP)) > tuning.maximum_floor_angle_deg:
			continue
		var cast_origin := support_now.global_position
		var point := support_now.get_collision_point(collision_index)
		var separation := cast_origin.distance_to(point) - tuning.probe_shape_radius_m
		if separation < best_separation:
			best_separation = separation
			best_normal = candidate_normal
	var supported := best_separation <= tuning.floor_snap_length_m
	return {
		"hit": supported,
		"normal": best_normal,
		"source": &"probe" if supported else &"none",
		"separation_m": best_separation,
	}


func _update_support_ahead() -> void:
	var horizontal_motion := motion_model.velocity.slide(Vector3.UP) \
		* get_physics_process_delta_time() * tuning.look_ahead_time_multiplier
	if horizontal_motion.length() < tuning.minimum_look_ahead_distance_m:
		horizontal_motion = motion_model.heading.slide(Vector3.UP).normalized() \
			* tuning.minimum_look_ahead_distance_m
	support_ahead.target_position = support_ahead.to_local(
		support_ahead.global_position + horizontal_motion \
		+ Vector3.DOWN * tuning.look_ahead_down_distance_m
	)
	support_ahead.force_shapecast_update()


func _filter_ground_normal(delta: float) -> void:
	if _stress_reference_normal.is_zero_approx():
		_stress_reference_normal = raw_ground_normal
		_normal_stress_tick = physics_tick
	elif _normal_stress_tick != physics_tick:
		_terrain_stress_feedback_cooldown = maxf(
			0.0, _terrain_stress_feedback_cooldown - delta
		)
		var normal_change_degrees := rad_to_deg(
			_stress_reference_normal.angle_to(raw_ground_normal)
		)
		_stress_reference_normal = raw_ground_normal
		_normal_stress_tick = physics_tick
		# Airborne/coyote recontacts are owned by landing classification; applying
		# terrain stress there would double-charge the same impact.
		if motion_state == MotionState.GROUNDED:
			var damage := motion_model.apply_terrain_normal_stress(
				normal_change_degrees, delta, tuning, surface
			)
			if damage > 0.001:
				last_terrain_stress_damage = damage
				if _terrain_stress_feedback_cooldown <= 0.0:
					_record_event(&"terrain_stress", {
						"damage": damage,
						"normal_change_degrees": normal_change_degrees,
					})
					InputService.vibrate_impact(clampf(damage * 2.5, 0.0, 0.65), 0.12)
					destabilized.emit(damage, &"terrain_normal_change")
					_terrain_stress_feedback_cooldown = \
						tuning.terrain_stress_feedback_cooldown_seconds
	var blend := 1.0 - exp(-tuning.normal_smoothing_rate * delta)
	filtered_ground_normal = filtered_ground_normal.lerp(raw_ground_normal, blend).normalized()


func _takeoff(normal: Vector3, reason: StringName) -> void:
	motion_model.jump(normal, tuning, surface)
	_recontact_timer = tuning.jump_recontact_grace_seconds
	_coyote_timer = 0.0
	_airborne_seconds = 0.0
	_zero_stability_seconds = 0.0
	floor_snap_length = 0.0
	_set_motion_state(MotionState.AIRBORNE, reason)


func _enter_coyote() -> void:
	_coyote_timer = tuning.coyote_time_seconds
	_set_motion_state(MotionState.COYOTE, &"contact_grace")


func _process_landing(incoming_velocity: Vector3, normal: Vector3) -> void:
	last_landing = WindboardMotionModel.classify_landing(
		incoming_velocity, normal, motion_model.heading, tuning, surface
	)
	last_landing["airborne_seconds"] = _airborne_seconds
	motion_model.apply_landing_damage(last_landing)
	var severity := int(last_landing.severity) as WindboardMotionModel.LandingSeverity
	if severity == WindboardMotionModel.LandingSeverity.CRASH:
		_crash(&"terminal_landing", last_landing)
		return
	if severity == WindboardMotionModel.LandingSeverity.RECOVERABLE:
		var retention := lerpf(
			1.0,
			tuning.recoverable_landing_min_speed_retention,
			float(last_landing.stability_damage)
		)
		motion_model.velocity *= retention
		velocity = motion_model.velocity
		InputService.vibrate_impact(float(last_landing.stability_damage), 0.16)
	_airborne_seconds = 0.0
	_zero_stability_seconds = 0.0
	_set_motion_state(MotionState.GROUNDED, &"landed")
	_record_event(&"landing", last_landing)
	landed.emit(last_landing.duplicate(true))


func _classify_wall_collisions(incoming_velocity: Vector3) -> bool:
	for collision_index in get_slide_collision_count():
		var collision := get_slide_collision(collision_index)
		var normal := collision.get_normal()
		if rad_to_deg(normal.angle_to(Vector3.UP)) <= tuning.maximum_floor_angle_deg:
			continue
		last_wall_impact_mps = WindboardMotionModel.wall_impact_speed(incoming_velocity, normal)
		if last_wall_impact_mps >= tuning.wall_crash_impact_mps:
			_crash(&"wall_impact", {
				"impact_speed_mps": last_wall_impact_mps,
				"normal": normal,
			})
			return true
	return false


func _crash(cause: StringName, details: Dictionary) -> void:
	if motion_state == MotionState.CRASHED:
		return
	crash_cause = cause
	motion_model.velocity = Vector3.ZERO
	velocity = Vector3.ZERO
	_set_motion_state(MotionState.CRASHED, cause)
	_record_event(&"crash", details.merged({"cause": cause}, true))
	InputService.vibrate_impact(1.0, 0.28)
	AppLog.info(&"movement", "Windboard crashed", {
		"cause": cause,
		"details": details,
		"physics_tick": physics_tick,
	})
	crashed.emit(cause, details.duplicate(true))


func _reset_motion(record_event: bool) -> void:
	var initial_heading := -global_basis.z
	initial_heading.y = 0.0
	if initial_heading.is_zero_approx():
		initial_heading = Vector3.FORWARD
	motion_model.reset(initial_heading, initial_heading.normalized() * initial_speed_mps)
	input_filter.reset()
	raw_intent = InputIntent.new()
	filtered_intent = InputIntent.new()
	velocity = motion_model.velocity
	motion_state = MotionState.GROUNDED
	raw_ground_normal = Vector3.UP
	filtered_ground_normal = Vector3.UP
	last_landing.clear()
	last_wall_impact_mps = 0.0
	last_terrain_stress_damage = 0.0
	crash_cause = &""
	_coyote_timer = 0.0
	_recontact_timer = 0.0
	_airborne_seconds = 0.0
	_zero_stability_seconds = 0.0
	_ignore_cached_floor = true
	_stress_reference_normal = Vector3.ZERO
	_normal_stress_tick = -1
	_terrain_stress_feedback_cooldown = 0.0
	floor_snap_length = tuning.floor_snap_length_m
	if record_event:
		_record_event(&"respawn", {"count": respawn_count})


func _set_motion_state(next: MotionState, reason: StringName) -> void:
	if next == motion_state:
		return
	var previous := motion_state
	motion_state = next
	if next != MotionState.AIRBORNE:
		floor_snap_length = tuning.floor_snap_length_m
	_record_event(&"state", {
		"from": state_label(previous),
		"to": state_label(next),
		"reason": reason,
	})
	motion_state_changed.emit(previous, next)


func _record_event(kind: StringName, data: Dictionary) -> void:
	event_history.append({
		"tick": physics_tick,
		"kind": kind,
		"data": data.duplicate(true),
	})
	if event_history.size() > EVENT_HISTORY_LIMIT:
		event_history.pop_front()
