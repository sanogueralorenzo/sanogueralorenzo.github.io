class_name WindboardMotionModel
extends RefCounted

enum LandingSeverity {
	CLEAN,
	RECOVERABLE,
	CRASH,
}

var velocity := Vector3.ZERO
var heading := Vector3.FORWARD
var stability := 1.0


func reset(initial_heading := Vector3.FORWARD, initial_velocity := Vector3.ZERO) -> void:
	heading = initial_heading.normalized() if not initial_heading.is_zero_approx() else Vector3.FORWARD
	velocity = initial_velocity
	stability = 1.0


func step_ground(
		delta: float,
		ground_normal: Vector3,
		intent: InputIntent,
		tuning: WindboardTuning,
		surface: SurfaceProfile
	) -> void:
	var normal := _safe_normal(ground_normal)
	heading = _project_direction(heading, normal, Vector3.FORWARD)
	var tangent_velocity := velocity.slide(normal)
	var speed := tangent_velocity.length()
	var speed_ratio := clampf(speed / tuning.turn_rate_reference_speed_mps, 0.0, 1.0)
	var turn_rate_deg := lerpf(
		tuning.low_speed_turn_rate_deg,
		tuning.high_speed_turn_rate_deg,
		speed_ratio
	)
	turn_rate_deg *= lerpf(1.0, tuning.tuck_turn_multiplier, _unit_input(intent.tuck))
	heading = heading.rotated(
		normal,
		-_signed_input(intent.steer) * deg_to_rad(turn_rate_deg) * delta
	).normalized()

	var gravity := Vector3.DOWN * tuning.gravity_mps2 * tuning.gravity_scale \
		* surface.downhill_acceleration_multiplier
	tangent_velocity += gravity.slide(normal) * delta

	var longitudinal_speed := tangent_velocity.dot(heading)
	var lateral_velocity := tangent_velocity - heading * longitudinal_speed
	var grip := tuning.lateral_grip_acceleration_mps2 * surface.lateral_grip_multiplier
	grip *= lerpf(1.0, tuning.brake_grip_multiplier, _unit_input(intent.brake))
	lateral_velocity = lateral_velocity.move_toward(Vector3.ZERO, grip * delta)
	tangent_velocity = heading * longitudinal_speed + lateral_velocity

	var drag := tuning.rolling_drag_mps2 * surface.drag_multiplier
	drag *= lerpf(1.0, tuning.tuck_drag_multiplier, _unit_input(intent.tuck))
	drag += tuning.carve_drag_mps2 * pow(absf(_signed_input(intent.steer)), 1.5)
	drag += tuning.brake_drag_mps2 * _unit_input(intent.brake)
	tangent_velocity = tangent_velocity.move_toward(Vector3.ZERO, drag * delta)
	if tangent_velocity.length() > tuning.max_ground_speed_mps:
		tangent_velocity = tangent_velocity.normalized() * tuning.max_ground_speed_mps

	var evaluated_speed := maxf(tangent_velocity.length(), 0.001)
	var lateral_slip_ratio := lateral_velocity.length() / evaluated_speed
	var reverse_slip_ratio := maxf(0.0, -longitudinal_speed) / evaluated_speed
	var slip_ratio := maxf(lateral_slip_ratio, reverse_slip_ratio)
	var instability := maxf(0.0, slip_ratio - tuning.stable_slip_ratio) \
		* tuning.slip_stability_drain_per_second \
		/ surface.stability_multiplier
	if instability > 0.0:
		stability = maxf(0.0, stability - instability * delta)
	else:
		var recover_multiplier := tuning.held_recover_stability_multiplier \
			if intent.jump_held else 1.0
		stability = minf(
			1.0,
			stability + tuning.stability_recovery_per_second * recover_multiplier * delta
		)

	velocity = tangent_velocity


func step_air(delta: float, intent: InputIntent, tuning: WindboardTuning) -> void:
	velocity += Vector3.DOWN * tuning.gravity_mps2 * tuning.gravity_scale * delta
	heading = _project_direction(heading, Vector3.UP, Vector3.FORWARD)
	heading = heading.rotated(
		Vector3.UP,
		-_signed_input(intent.steer) * deg_to_rad(tuning.air_turn_rate_deg) * delta
	).normalized()
	var horizontal := velocity.slide(Vector3.UP)
	if not horizontal.is_zero_approx():
		var target_horizontal := heading * horizontal.length()
		horizontal = horizontal.move_toward(
			target_horizontal,
			tuning.air_control_acceleration_mps2 * absf(_signed_input(intent.steer)) * delta
		)
		velocity.x = horizontal.x
		velocity.z = horizontal.z
		if intent.jump_held:
			heading = _rotate_direction_toward(
				heading,
				horizontal.normalized(),
				deg_to_rad(tuning.air_recover_alignment_rate_deg) * delta
			)
	if velocity.length() > tuning.max_air_speed_mps:
		velocity = velocity.normalized() * tuning.max_air_speed_mps


func jump(normal: Vector3, tuning: WindboardTuning, surface: SurfaceProfile) -> void:
	var safe_normal := _safe_normal(normal)
	var inward_speed := velocity.dot(safe_normal)
	if inward_speed < 0.0:
		velocity -= safe_normal * inward_speed
	velocity += safe_normal * tuning.jump_speed_mps * surface.jump_multiplier


func apply_landing_damage(result: Dictionary) -> void:
	stability = maxf(0.0, stability - float(result.get("stability_damage", 0.0)))


static func classify_landing(
		incoming_velocity: Vector3,
		ground_normal: Vector3,
		travel_heading: Vector3,
		tuning: WindboardTuning,
		surface: SurfaceProfile
	) -> Dictionary:
	var normal := _safe_normal(ground_normal)
	var impact_speed := maxf(0.0, -incoming_velocity.dot(normal))
	var tangent_velocity := incoming_velocity.slide(normal)
	var alignment := 1.0
	if tangent_velocity.length_squared() > 0.01:
		var tangent_heading := _project_direction(travel_heading, normal, tangent_velocity)
		alignment = tangent_velocity.normalized().dot(tangent_heading)
	var forgiveness := surface.landing_forgiveness_multiplier
	var clean_impact := tuning.clean_landing_impact_mps * forgiveness
	var crash_impact := tuning.crash_landing_impact_mps * forgiveness
	var severity := LandingSeverity.CLEAN
	if impact_speed >= crash_impact or (
			alignment <= tuning.crash_landing_alignment
			and impact_speed >= tuning.minimum_alignment_crash_impact_mps * forgiveness
		):
		severity = LandingSeverity.CRASH
	elif impact_speed > clean_impact or alignment < tuning.clean_landing_alignment:
		severity = LandingSeverity.RECOVERABLE

	var impact_damage := inverse_lerp(clean_impact, crash_impact, impact_speed)
	var alignment_damage := inverse_lerp(
		tuning.clean_landing_alignment,
		tuning.crash_landing_alignment,
		alignment
	)
	var stability_damage := clampf(maxf(impact_damage, alignment_damage), 0.0, 1.0)
	return {
		"severity": severity,
		"impact_speed_mps": impact_speed,
		"alignment": alignment,
		"stability_damage": stability_damage,
	}


static func wall_impact_speed(incoming_velocity: Vector3, collision_normal: Vector3) -> float:
	return maxf(0.0, -incoming_velocity.dot(_safe_normal(collision_normal)))


static func _project_direction(direction: Vector3, normal: Vector3, fallback: Vector3) -> Vector3:
	var projected := direction.slide(normal)
	if projected.length_squared() <= 0.000001:
		projected = fallback.slide(normal)
	if projected.length_squared() <= 0.000001:
		projected = normal.cross(Vector3.RIGHT)
	return projected.normalized()


static func _safe_normal(value: Vector3) -> Vector3:
	return value.normalized() if not value.is_zero_approx() else Vector3.UP


static func _rotate_direction_toward(from: Vector3, to: Vector3, max_angle: float) -> Vector3:
	var safe_from := from.normalized()
	var safe_to := to.normalized()
	if safe_from.is_zero_approx() or safe_to.is_zero_approx():
		return safe_from
	var angle := safe_from.angle_to(safe_to)
	if angle <= max_angle or is_zero_approx(angle):
		return safe_to
	return safe_from.slerp(safe_to, clampf(max_angle / angle, 0.0, 1.0)).normalized()


static func _unit_input(value: float) -> float:
	return clampf(value, 0.0, 1.0) if is_finite(value) else 0.0


static func _signed_input(value: float) -> float:
	return clampf(value, -1.0, 1.0) if is_finite(value) else 0.0
