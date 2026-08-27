class_name BoundaryCurrent
extends RefCounted

const WARNING_DISTANCE := 390.0
const CRITICAL_DISTANCE := 72.0
const LOOK_AHEAD_SECONDS := 2.25
const MINIMUM_LOOK_AHEAD := 90.0
const MAXIMUM_LOOK_AHEAD := 300.0
const TANGENT_WEIGHT := 0.78
const INWARD_WEIGHT := 0.62
const MINIMUM_TURN_RATE := 0.48
const MAXIMUM_TURN_RATE := 3.1


class Sample:
	extends RefCounted
	var pressure := 0.0
	var edge_distance := INF
	var predicted_edge_distance := INF
	var target_direction := Vector3.ZERO
	var outward_normal := Vector3.ZERO
	var bank_label := ""


func sample(
	position: Vector3,
	heading: Vector3,
	horizontal_speed: float,
	half_extent: float,
	turn_bias: float,
	result: Sample
) -> void:
	var planar_heading := Vector3(heading.x, 0.0, heading.z).normalized()
	var look_ahead := clampf(horizontal_speed * LOOK_AHEAD_SECONDS, MINIMUM_LOOK_AHEAD, MAXIMUM_LOOK_AHEAD)
	var future_position := position + planar_heading * look_ahead
	result.edge_distance = half_extent - maxf(absf(position.x), absf(position.z))
	result.predicted_edge_distance = half_extent - maxf(absf(future_position.x), absf(future_position.z))
	result.pressure = 1.0 - smoothstep(CRITICAL_DISTANCE, WARNING_DISTANCE, result.predicted_edge_distance)
	if result.pressure <= 0.0001:
		result.pressure = 0.0
		result.target_direction = planar_heading
		result.outward_normal = Vector3.ZERO
		result.bank_label = ""
		return

	var outward := _nearest_outward_normal(future_position)
	var tangent := outward.cross(Vector3.UP).normalized()
	var tangent_alignment := planar_heading.dot(tangent)
	if tangent_alignment < -0.08:
		tangent = -tangent
	elif absf(tangent_alignment) <= 0.08:
		tangent *= signf(turn_bias) if turn_bias != 0.0 else 1.0
	var inward := -outward
	result.outward_normal = outward
	result.target_direction = (tangent * TANGENT_WEIGHT + inward * INWARD_WEIGHT).normalized()
	var turn_sign := planar_heading.cross(result.target_direction).y
	result.bank_label = "BANK LEFT" if turn_sign > 0.0 else "BANK RIGHT"


func guide_heading(heading: Vector3, sample_result: Sample, delta: float) -> Vector3:
	if sample_result.pressure <= 0.0:
		return heading
	var shaped_pressure := pow(sample_result.pressure, 0.72)
	var turn_rate := lerpf(MINIMUM_TURN_RATE, MAXIMUM_TURN_RATE, shaped_pressure)
	var blend := 1.0 - exp(-turn_rate * shaped_pressure * delta)
	return heading.slerp(sample_result.target_direction, blend).normalized()


func _nearest_outward_normal(position: Vector3) -> Vector3:
	if absf(position.x) >= absf(position.z):
		return Vector3(signf(position.x), 0.0, 0.0)
	return Vector3(0.0, 0.0, signf(position.z))
