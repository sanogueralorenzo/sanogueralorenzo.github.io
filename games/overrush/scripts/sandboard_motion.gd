class_name SandboardMotion
extends RefCounted

const LANDING_CLEAN := &"clean"
const LANDING_SOLID := &"solid"
const LANDING_ROUGH := &"rough"


static func calculate_carve(
	velocity: Vector3,
	desired_direction: Vector3,
	surface_normal: Vector3,
	delta: float,
	maximum_speed: float,
	fast_turn_rate: float,
	high_speed_turn_rate: float
) -> Dictionary:
	var normal := surface_normal.normalized()
	var normal_velocity := normal * velocity.dot(normal)
	var tangent_velocity := velocity.slide(normal)
	var speed := tangent_velocity.length()
	var current_direction := tangent_velocity.normalized()
	var input_strength := clampf(desired_direction.length(), 0.0, 1.0)
	var target_direction := desired_direction.slide(normal).normalized()
	if input_strength <= 0.001 or target_direction.length_squared() <= 0.001:
		return {
			"velocity": velocity,
			"direction": current_direction,
			"turn_angle": 0.0,
			"steering_angle": 0.0,
			"carve_intensity": 0.0,
			"edge_load": 0.0,
		}
	if speed <= 0.001:
		return {
			"velocity": velocity,
			"direction": target_direction,
			"turn_angle": 0.0,
			"steering_angle": 0.0,
			"carve_intensity": 0.0,
			"edge_load": 0.0,
		}
	var speed_ratio := clampf(speed / maximum_speed, 0.0, 1.0)
	var turn_rate := lerpf(fast_turn_rate, high_speed_turn_rate, pow(speed_ratio, 0.7))
	var steering_angle := current_direction.signed_angle_to(target_direction, normal)
	var analog_turn_scale := lerpf(0.18, 1.0, input_strength)
	var maximum_turn := maxf(0.0001, turn_rate * analog_turn_scale * delta)
	var turn_angle := clampf(steering_angle, -maximum_turn, maximum_turn)
	var carved_direction := current_direction.rotated(normal, turn_angle).normalized()
	var carve_intensity := clampf(absf(steering_angle) / (PI * 0.5), 0.0, 1.0) * input_strength
	var turn_commitment := clampf(absf(turn_angle) / maximum_turn, 0.0, 1.0)
	var edge_load := carve_intensity * turn_commitment
	var carve_drag_rate := lerpf(0.015, 0.11, speed_ratio) * edge_load
	var turn_drag := exp(-carve_drag_rate * delta)
	return {
		"velocity": carved_direction * speed * turn_drag + normal_velocity,
		"direction": carved_direction,
		"turn_angle": turn_angle,
		"steering_angle": steering_angle,
		"carve_intensity": carve_intensity,
		"edge_load": edge_load,
	}


static func calculate_starting_push(
	tangent_speed: float,
	push_speed_limit: float,
	starting_push: float,
	input_strength: float,
) -> float:
	if push_speed_limit <= 0.001 or starting_push <= 0.0:
		return 0.0
	var fade := 1.0 - smoothstep(push_speed_limit * 0.45, push_speed_limit, maxf(0.0, tangent_speed))
	return starting_push * fade * clampf(input_strength, 0.0, 1.0)


static func calculate_landing_preparation(
	velocity: Vector3,
	desired_direction: Vector3,
	surface_normal: Vector3,
	clearance: float,
	clearance_window: float,
	delta: float,
	response: float,
	target_closing_speed: float,
	maximum_tangent_speed: float,
) -> Dictionary:
	var normal := surface_normal.normalized()
	var tangent_velocity := velocity.slide(normal) if normal.length_squared() > 0.001 else velocity
	var closing_speed := maxf(0.0, -velocity.dot(normal)) if normal.length_squared() > 0.001 else 0.0
	var result := {
		"velocity": velocity,
		"direction": tangent_velocity.normalized(),
		"preparation_strength": 0.0,
		"response_blend": 0.0,
		"alignment": 0.0,
		"closing_speed_before": closing_speed,
		"closing_speed_after": closing_speed,
		"tangent_speed": tangent_velocity.length(),
	}
	if (
		normal.length_squared() <= 0.001
		or velocity.y >= 0.0
		or clearance < 0.0
		or clearance_window <= 0.0
		or clearance >= clearance_window
		or delta <= 0.0
		or response <= 0.0
		or maximum_tangent_speed <= 0.0
	):
		return result
	var input_strength := clampf(desired_direction.length(), 0.0, 1.0)
	var desired_tangent := desired_direction.slide(normal).normalized()
	var current_tangent := tangent_velocity.normalized()
	if input_strength <= 0.001 or desired_tangent.length_squared() <= 0.001 or current_tangent.length_squared() <= 0.001:
		return result
	var alignment := current_tangent.dot(desired_tangent)
	result.alignment = alignment
	var closing_target := maxf(0.01, target_closing_speed)
	if alignment <= 0.0 or closing_speed <= closing_target:
		return result
	var clearance_strength := 1.0 - smoothstep(0.0, clearance_window, clearance)
	var preparation_strength := input_strength * alignment * clearance_strength
	var response_blend := 1.0 - exp(-response * preparation_strength * delta)
	var prepared_closing_speed := lerpf(closing_speed, closing_target, response_blend)
	var total_speed_squared := velocity.length_squared()
	var preserved_tangent_speed := sqrt(maxf(0.0, total_speed_squared - prepared_closing_speed * prepared_closing_speed))
	var prepared_tangent_speed := minf(preserved_tangent_speed, maximum_tangent_speed)
	var prepared_tangent_direction := current_tangent.lerp(desired_tangent, response_blend).normalized()
	var prepared_velocity := (
		prepared_tangent_direction * prepared_tangent_speed
		- normal * prepared_closing_speed
	)
	result.velocity = prepared_velocity
	result.direction = prepared_tangent_direction
	result.preparation_strength = preparation_strength
	result.response_blend = response_blend
	result.closing_speed_after = maxf(0.0, -prepared_velocity.dot(normal))
	result.tangent_speed = prepared_velocity.slide(normal).length()
	return result


static func calculate_slope_drive(board_direction: Vector3, surface_normal: Vector3) -> Vector3:
	var normal := surface_normal.normalized()
	var downhill := Vector3.DOWN.slide(normal)
	var board_tangent := board_direction.slide(normal).normalized()
	if downhill.length_squared() <= 0.0001 or board_tangent.length_squared() <= 0.0001:
		return Vector3.ZERO
	return board_tangent * downhill.dot(board_tangent)


static func evaluate_landing(incoming_velocity: Vector3, surface_normal: Vector3, board_heading: Vector3) -> Dictionary:
	var normal := surface_normal.normalized()
	var impact_speed := maxf(0.0, -incoming_velocity.dot(normal))
	var travel_direction := incoming_velocity.slide(normal).normalized()
	var landing_heading := board_heading.slide(normal).normalized()
	var alignment := 1.0
	if travel_direction.length_squared() > 0.001 and landing_heading.length_squared() > 0.001:
		alignment = clampf(travel_direction.dot(landing_heading), 0.0, 1.0)
	var impact_quality := 1.0 - smoothstep(8.0, 27.0, impact_speed)
	var score := clampf(alignment * 0.58 + impact_quality * 0.42, 0.0, 1.0)
	var rating := LANDING_ROUGH
	var momentum_retention := 0.84
	if impact_speed <= 13.0 and alignment >= 0.80:
		rating = LANDING_CLEAN
		momentum_retention = 1.0
	elif impact_speed <= 23.0 and alignment >= 0.52:
		rating = LANDING_SOLID
		momentum_retention = 0.94
	return {
		"rating": rating,
		"score": score,
		"impact_speed": impact_speed,
		"alignment": alignment,
		"momentum_retention": momentum_retention,
	}


static func is_fatal_obstacle_impact(
	incoming_velocity: Vector3,
	collision_normal: Vector3,
	minimum_closing_speed: float,
) -> bool:
	var closing_speed := maxf(0.0, -incoming_velocity.dot(collision_normal.normalized()))
	return closing_speed >= minimum_closing_speed
