class_name Sandboarder
extends CharacterBody3D

signal air_boost_state_changed(available: bool, airborne: bool)
signal air_boost_used
signal landed(impact_speed: float)
signal landing_scored(rating: StringName, score: float, impact_speed: float)
signal jumped
signal crashed(obstacle_kind: StringName, impact_speed: float)

@export var world_path: NodePath
@export var camera_path: NodePath
@export var carve_track_path: NodePath
@export var gravity_strength := 30.0
@export var slope_acceleration := 44.0
@export var starting_push := 18.0
@export var summit_push_speed := 14.0
@export var ground_drag := 0.065
@export var low_speed_turn_rate := 2.8
@export var high_speed_turn_rate := 1.05
@export var air_control := 5.0
@export var jump_velocity := 13.5
@export var jump_buffer_duration := 0.13
@export var coyote_duration := 0.1
@export var air_boost_impulse := 19.0
@export var air_boost_lift := 4.5
@export var maximum_speed := 78.0
@export var valid_landing_normal_y := 0.55
@export var minimum_landing_airtime := 0.08
@export var fatal_obstacle_impact_speed := 10.0
@export var terrain_follow_snap := 1.6
@export var rider_pose_response := 9.0
@export var rider_carve_lean_degrees := 16.0
@export var rider_speed_crouch := 0.22
@export var rider_air_tuck := 0.14
@export var carve_track_sample_distance := 1.5
@export var carve_track_width := 0.68
@export var carve_track_surface_offset := 0.035
@export_range(80, 320, 1) var carve_track_max_points := 200

@onready var board_visual: Node3D = $BoardVisual
@onready var torso_visual: MeshInstance3D = $BoardVisual/Rider
@onready var head_visual: MeshInstance3D = $BoardVisual/Head
@onready var left_arm_visual: MeshInstance3D = $BoardVisual/LeftArm
@onready var right_arm_visual: MeshInstance3D = $BoardVisual/RightArm
@onready var left_leg_visual: MeshInstance3D = $BoardVisual/LeftLeg
@onready var right_leg_visual: MeshInstance3D = $BoardVisual/RightLeg
@onready var boost_trail: GPUParticles3D = $BoostTrail
@onready var boost_light: OmniLight3D = $BoostLight
@onready var surface_trail: GPUParticles3D = $SurfaceTrail
@onready var landing_burst: GPUParticles3D = $LandingBurst
@onready var carve_track: MeshInstance3D = get_node(carve_track_path)

var air_boost_state := AirBoostState.new()
var jump_assist_state := JumpAssistState.new()
var distance_traveled := 0.0
var _world: ProceduralDesert
var _camera: Camera3D
var _last_position := Vector3.ZERO
var _airtime := 0.0
var _heading := Vector3.FORWARD
var _boost_feedback_time := 0.0
var _last_floor_normal := Vector3.UP
var _carve_intensity := 0.0
var _carve_sign := 0.0
var _landing_compression := 0.0
var _has_departed_rideable_ground := false
var _surface_grass_weight := 0.0
var _crashed := false
var _air_pose := 0.0
var _rider_parts: Array[Node3D] = []
var _rider_base_positions: Array[Vector3] = []
var _rider_base_rotations: Array[Vector3] = []
var _carve_track_points: Array[Dictionary] = []
var _carve_track_segment := 0
var _carve_track_was_grounded := false

const SAND_TRAIL_COLOR := Color(1.0, 0.78, 0.38, 0.7)
const GRASS_TRAIL_COLOR := Color(0.64, 0.82, 0.34, 0.72)
const SAND_LANDING_COLOR := Color(1.0, 0.82, 0.42, 0.84)
const GRASS_LANDING_COLOR := Color(0.72, 0.88, 0.4, 0.84)
const SAND_TRACK_COLOR := Color(0.22, 0.085, 0.024, 0.46)
const GRASS_TRACK_COLOR := Color(0.034, 0.12, 0.04, 0.44)


func _ready() -> void:
	OverrushInputBindings.ensure_actions()
	_world = get_node(world_path)
	_camera = get_node(camera_path)
	floor_snap_length = terrain_follow_snap
	floor_max_angle = deg_to_rad(58.0)
	floor_stop_on_slope = false
	_last_position = global_position
	jump_assist_state.configure(jump_buffer_duration, coyote_duration)
	air_boost_state.reset_on_rideable_ground()
	_cache_rider_pose()
	_clear_carve_track()
	air_boost_state_changed.emit(true, false)


func _physics_process(delta: float) -> void:
	if _crashed:
		return
	var started_on_floor := is_on_floor()
	var input_direction := get_camera_relative_direction()
	jump_assist_state.tick(delta, started_on_floor)
	if Input.is_action_just_pressed(OverrushInputBindings.HOP):
		jump_assist_state.queue_jump()
	if started_on_floor:
		_last_floor_normal = get_floor_normal()
		_apply_ground_motion(input_direction, delta)
	else:
		_apply_air_motion(input_direction, delta)
		_airtime += delta
		if not air_boost_state.airborne:
			air_boost_state.leave_surface()
			air_boost_state_changed.emit(air_boost_state.available, true)
	var jumped_this_frame := _try_buffered_jump(started_on_floor)

	if Input.is_action_just_pressed(OverrushInputBindings.AIR_BOOST):
		try_air_boost(input_direction)

	var before_move := velocity
	move_and_slide()
	if _detect_fatal_obstacle_impact(before_move):
		return
	_update_surface_effect_palette()
	_update_surface_state(started_on_floor, before_move, jumped_this_frame)
	_update_carve_track()
	_update_visuals(delta)
	distance_traveled += Vector2(
		global_position.x - _last_position.x,
		global_position.z - _last_position.z
	).length()
	_last_position = global_position


func respawn() -> void:
	global_position = _world.get_spawn_position()
	velocity = Vector3.ZERO
	_heading = Vector3(_camera.call("get_planar_forward")) if _camera.has_method("get_planar_forward") else Vector3.FORWARD
	distance_traveled = 0.0
	_airtime = 0.0
	_has_departed_rideable_ground = false
	_crashed = false
	jump_assist_state.reset()
	air_boost_state.reset_on_rideable_ground()
	_reset_rider_pose()
	_clear_carve_track()
	_last_position = global_position
	air_boost_state_changed.emit(true, false)


func apply_world_rebase(shift: Vector3) -> void:
	global_position -= shift
	_last_position = global_position
	for point_index in range(_carve_track_points.size()):
		var point := _carve_track_points[point_index]
		point.position = Vector3(point.position) - shift
		_carve_track_points[point_index] = point
	_rebuild_carve_track_mesh()


func try_air_boost(requested_direction: Vector3) -> bool:
	if not air_boost_state.try_use():
		return false
	var direction := requested_direction
	if direction.length_squared() < 0.01:
		direction = Vector3(velocity.x, 0.0, velocity.z)
	if direction.length_squared() < 0.01:
		direction = _heading
	direction.y = 0.0
	direction = direction.normalized()
	velocity += direction * air_boost_impulse
	velocity.y += air_boost_lift
	_limit_horizontal_speed(maximum_speed * 1.18)
	_boost_feedback_time = 0.2
	boost_trail.restart()
	boost_trail.emitting = true
	boost_light.visible = true
	air_boost_used.emit()
	air_boost_state_changed.emit(false, true)
	return true


func get_camera_relative_direction() -> Vector3:
	var input := Input.get_vector(
		OverrushInputBindings.MOVE_LEFT,
		OverrushInputBindings.MOVE_RIGHT,
		OverrushInputBindings.MOVE_FORWARD,
		OverrushInputBindings.MOVE_BACKWARD
	)
	if input.length_squared() < 0.0025:
		return Vector3.ZERO
	var forward: Vector3 = Vector3(_camera.call("get_planar_forward")) if _camera.has_method("get_planar_forward") else Vector3.FORWARD
	var right: Vector3 = Vector3(_camera.call("get_planar_right")) if _camera.has_method("get_planar_right") else Vector3.RIGHT
	return (right * input.x + forward * -input.y).normalized()


func get_horizontal_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()


func get_surface_grass_weight() -> float:
	return _surface_grass_weight


func _apply_ground_motion(input_direction: Vector3, delta: float) -> void:
	var normal := get_floor_normal()
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var speed := horizontal.length()
	var downhill := Vector3.DOWN.slide(normal)
	if input_direction.length_squared() > 0.01:
		var tangent_input := input_direction.slide(normal).normalized()
		if speed < summit_push_speed:
			velocity += tangent_input * starting_push * delta
			_heading = Vector3(tangent_input.x, 0.0, tangent_input.z).normalized()
		if speed >= summit_push_speed:
			var carve := SandboardMotion.calculate_carve(
				horizontal,
				tangent_input,
				delta,
				maximum_speed,
				low_speed_turn_rate,
				high_speed_turn_rate,
			)
			var carved_velocity: Vector3 = carve.velocity
			velocity.x = carved_velocity.x
			velocity.z = carved_velocity.z
			_heading = carve.direction
			_carve_intensity = float(carve.carve_intensity)
			_carve_sign = signf(float(carve.steering_angle))
	else:
		_carve_intensity = move_toward(_carve_intensity, 0.0, delta * 3.0)
		_carve_sign = move_toward(_carve_sign, 0.0, delta * 5.0)
	if downhill.length_squared() > 0.0001:
		velocity += downhill.normalized() * slope_acceleration * downhill.length() * delta
	velocity += Vector3.DOWN * gravity_strength * delta
	var drag_factor := maxf(0.0, 1.0 - ground_drag * delta)
	velocity.x *= drag_factor
	velocity.z *= drag_factor
	_limit_horizontal_speed(maximum_speed)


func _apply_air_motion(input_direction: Vector3, delta: float) -> void:
	velocity.y -= gravity_strength * delta
	if input_direction.length_squared() > 0.01:
		velocity += input_direction * air_control * delta
		_heading = input_direction
	_carve_intensity = move_toward(_carve_intensity, 0.0, delta * 2.0)
	_limit_horizontal_speed(maximum_speed * 1.18)


func _try_buffered_jump(started_on_floor: bool) -> bool:
	if not jump_assist_state.try_consume(started_on_floor):
		return false
	var launch_normal := get_floor_normal() if started_on_floor else _last_floor_normal
	launch_normal = launch_normal.normalized()
	var normal_speed := velocity.dot(launch_normal)
	if normal_speed < 0.0:
		velocity -= launch_normal * normal_speed
	velocity += launch_normal * jump_velocity
	_airtime = 0.0
	_has_departed_rideable_ground = true
	air_boost_state.leave_surface()
	air_boost_state_changed.emit(air_boost_state.available, true)
	jumped.emit()
	return true


func _update_surface_state(started_on_floor: bool, impact_velocity: Vector3, jumped_this_frame: bool) -> void:
	var ended_on_floor := is_on_floor()
	if ended_on_floor and not started_on_floor:
		var valid_rideable_ground := _airtime >= minimum_landing_airtime and _has_valid_rideable_floor_contact()
		air_boost_state.land(valid_rideable_ground)
		if valid_rideable_ground and _has_departed_rideable_ground:
			var assessment := SandboardMotion.evaluate_landing(impact_velocity, get_floor_normal(), _heading)
			var retention: float = assessment.momentum_retention
			velocity.x *= retention
			velocity.z *= retention
			_landing_compression = minf(float(assessment.impact_speed) / 30.0 * 0.22, 0.22)
			landing_burst.restart()
			landing_burst.emitting = true
			landed.emit(float(assessment.impact_speed))
			landing_scored.emit(assessment.rating, float(assessment.score), float(assessment.impact_speed))
		air_boost_state_changed.emit(air_boost_state.available, false)
		_airtime = 0.0
		_has_departed_rideable_ground = false
	elif not ended_on_floor and started_on_floor and not jumped_this_frame:
		air_boost_state.leave_surface()
		_airtime = 0.0
		_has_departed_rideable_ground = true
		air_boost_state_changed.emit(air_boost_state.available, true)


func _has_valid_rideable_floor_contact() -> bool:
	for index in range(get_slide_collision_count()):
		var collision := get_slide_collision(index)
		if _world.is_rideable_collider(collision.get_collider()) and collision.get_normal().y >= valid_landing_normal_y:
			return true
	return false


func _detect_fatal_obstacle_impact(incoming_velocity: Vector3) -> bool:
	for index in range(get_slide_collision_count()):
		var collision := get_slide_collision(index)
		var collider := collision.get_collider()
		if not _world.is_obstacle_collider(collider):
			continue
		if not SandboardMotion.is_fatal_obstacle_impact(
			incoming_velocity,
			collision.get_normal(),
			fatal_obstacle_impact_speed,
		):
			continue
		var impact_speed := maxf(0.0, -incoming_velocity.dot(collision.get_normal().normalized()))
		_crashed = true
		velocity = Vector3.ZERO
		surface_trail.emitting = false
		boost_trail.emitting = false
		boost_light.visible = false
		crashed.emit(_world.get_obstacle_kind(collider), impact_speed)
		return true
	return false


func _limit_horizontal_speed(limit: float) -> void:
	var horizontal := Vector2(velocity.x, velocity.z)
	if horizontal.length() <= limit:
		return
	horizontal = horizontal.normalized() * limit
	velocity.x = horizontal.x
	velocity.z = horizontal.y


func _update_visuals(delta: float) -> void:
	var flat_heading := Vector3(velocity.x, 0.0, velocity.z)
	if flat_heading.length_squared() > 0.25:
		_heading = flat_heading.normalized()
	var visual_forward := _heading
	var visual_up := Vector3.UP
	if is_on_floor():
		visual_up = get_floor_normal().normalized()
		visual_forward = _heading.slide(visual_up).normalized()
	elif velocity.length_squared() > 4.0:
		visual_forward = velocity.normalized()
	var visual_right := visual_forward.cross(visual_up).normalized()
	if visual_right.length_squared() < 0.01:
		visual_right = Vector3.RIGHT
	visual_up = visual_right.cross(visual_forward).normalized()
	var target_basis := Basis(visual_right, visual_up, -visual_forward).orthonormalized()
	if is_on_floor():
		target_basis = target_basis.rotated(visual_forward, -_carve_sign * _carve_intensity * deg_to_rad(13.0))
	board_visual.basis = board_visual.basis.slerp(target_basis, 1.0 - exp(-10.0 * delta)).orthonormalized()
	_landing_compression = move_toward(_landing_compression, 0.0, delta * 1.8)
	board_visual.position.y = -_landing_compression
	var speed_ratio := clampf(get_horizontal_speed() / maximum_speed, 0.0, 1.0)
	_update_rider_pose(delta, is_on_floor(), speed_ratio)
	surface_trail.emitting = is_on_floor() and get_horizontal_speed() >= 8.0
	surface_trail.amount_ratio = clampf((speed_ratio - 0.08) / 0.92, 0.15, 1.0)
	surface_trail.rotation.y = atan2(-_heading.x, -_heading.z)
	_boost_feedback_time = maxf(0.0, _boost_feedback_time - delta)
	if _boost_feedback_time <= 0.0:
		boost_trail.emitting = false
		boost_light.visible = false


func _cache_rider_pose() -> void:
	_rider_parts.assign([
		torso_visual,
		head_visual,
		left_arm_visual,
		right_arm_visual,
		left_leg_visual,
		right_leg_visual,
	])
	_rider_base_positions.clear()
	_rider_base_rotations.clear()
	for part in _rider_parts:
		_rider_base_positions.append(part.position)
		_rider_base_rotations.append(part.rotation)


func _reset_rider_pose() -> void:
	_air_pose = 0.0
	_landing_compression = 0.0
	board_visual.position.y = 0.0
	for part_index in range(_rider_parts.size()):
		_rider_parts[part_index].position = _rider_base_positions[part_index]
		_rider_parts[part_index].rotation = _rider_base_rotations[part_index]


func _update_rider_pose(delta: float, grounded: bool, speed_ratio: float) -> void:
	var blend := 1.0 - exp(-rider_pose_response * delta)
	_air_pose = lerpf(_air_pose, 0.0 if grounded else 1.0, blend)
	var landing_ratio := clampf(_landing_compression / 0.22, 0.0, 1.0)
	var crouch := clampf(speed_ratio * 0.72 + landing_ratio * 0.55, 0.0, 1.0)
	var carve := _carve_sign * _carve_intensity * (1.0 - _air_pose)
	var boost_ratio := clampf(_boost_feedback_time / 0.2, 0.0, 1.0)
	var torso_position := _rider_base_positions[0] + Vector3(
		carve * 0.07,
		-rider_speed_crouch * crouch,
		-0.08 * speed_ratio - 0.08 * boost_ratio,
	)
	var torso_rotation := _rider_base_rotations[0] + Vector3(
		deg_to_rad(-11.0 * crouch - 8.0 * boost_ratio),
		0.0,
		deg_to_rad(-rider_carve_lean_degrees * carve),
	)
	var head_position := _rider_base_positions[1] + Vector3(
		carve * 0.035,
		-rider_speed_crouch * crouch * 0.72,
		-0.035 * boost_ratio,
	)
	var head_rotation := _rider_base_rotations[1] + Vector3(
		deg_to_rad(5.0 * crouch),
		0.0,
		deg_to_rad(7.0 * carve),
	)
	var left_arm_rotation := _rider_base_rotations[2] + Vector3(
		deg_to_rad(-9.0 * _air_pose),
		deg_to_rad(-10.0 * carve),
		deg_to_rad(-22.0 * _air_pose + 12.0 * carve),
	)
	var right_arm_rotation := _rider_base_rotations[3] + Vector3(
		deg_to_rad(9.0 * _air_pose),
		deg_to_rad(-10.0 * carve),
		deg_to_rad(22.0 * _air_pose + 12.0 * carve),
	)
	var leg_lift := rider_air_tuck * _air_pose - 0.04 * landing_ratio
	var left_leg_position := _rider_base_positions[4] + Vector3(0.0, leg_lift, -0.04 * crouch)
	var right_leg_position := _rider_base_positions[5] + Vector3(0.0, leg_lift, 0.04 * crouch)
	var left_leg_rotation := _rider_base_rotations[4] + Vector3(
		deg_to_rad(20.0 * crouch + 24.0 * _air_pose),
		0.0,
		deg_to_rad(-8.0 * carve - 8.0 * _air_pose),
	)
	var right_leg_rotation := _rider_base_rotations[5] + Vector3(
		deg_to_rad(-20.0 * crouch - 24.0 * _air_pose),
		0.0,
		deg_to_rad(-8.0 * carve + 8.0 * _air_pose),
	)
	_lerp_part_pose(torso_visual, torso_position, torso_rotation, blend)
	_lerp_part_pose(head_visual, head_position, head_rotation, blend)
	_lerp_part_pose(left_arm_visual, _rider_base_positions[2], left_arm_rotation, blend)
	_lerp_part_pose(right_arm_visual, _rider_base_positions[3], right_arm_rotation, blend)
	_lerp_part_pose(left_leg_visual, left_leg_position, left_leg_rotation, blend)
	_lerp_part_pose(right_leg_visual, right_leg_position, right_leg_rotation, blend)


func _lerp_part_pose(part: Node3D, target_position: Vector3, target_rotation: Vector3, blend: float) -> void:
	part.position = part.position.lerp(target_position, blend)
	part.rotation = Vector3(
		lerp_angle(part.rotation.x, target_rotation.x, blend),
		lerp_angle(part.rotation.y, target_rotation.y, blend),
		lerp_angle(part.rotation.z, target_rotation.z, blend),
	)


func _update_surface_effect_palette() -> void:
	var logical_position := _world.get_world_position(global_position)
	_surface_grass_weight = smoothstep(
		0.08,
		0.92,
		_world.get_grass_weight(Vector2(logical_position.x, logical_position.z)),
	)
	var trail_process := surface_trail.process_material as ParticleProcessMaterial
	if trail_process != null:
		trail_process.color = SAND_TRAIL_COLOR.lerp(GRASS_TRAIL_COLOR, _surface_grass_weight)
	var landing_process := landing_burst.process_material as ParticleProcessMaterial
	if landing_process != null:
		landing_process.color = SAND_LANDING_COLOR.lerp(GRASS_LANDING_COLOR, _surface_grass_weight)


func _update_carve_track() -> void:
	var grounded := is_on_floor() and get_horizontal_speed() >= 5.0
	if not grounded:
		if _carve_track_was_grounded:
			_carve_track_segment += 1
		_carve_track_was_grounded = false
		return
	_carve_track_was_grounded = true
	var logical_position := _world.get_world_position(global_position)
	var surface_normal := _world.get_surface_normal(logical_position.x, logical_position.z, 1.5)
	var local_position := Vector3(
		global_position.x,
		_world.get_local_surface_height(global_position.x, global_position.z),
		global_position.z,
	) + surface_normal * carve_track_surface_offset
	if not _carve_track_points.is_empty():
		var last_position := Vector3(_carve_track_points.back().position)
		if Vector2(local_position.x - last_position.x, local_position.z - last_position.z).length() < carve_track_sample_distance:
			return
	var forward := Vector3(velocity.x, 0.0, velocity.z)
	if forward.length_squared() < 0.01:
		forward = _heading
	forward = forward.slide(surface_normal).normalized()
	var right := forward.cross(surface_normal).normalized()
	if right.length_squared() < 0.01:
		return
	var grass_weight := smoothstep(
		0.08,
		0.92,
		_world.get_grass_weight(Vector2(logical_position.x, logical_position.z)),
	)
	_carve_track_points.append({
		"position": local_position,
		"normal": surface_normal,
		"right": right,
		"color": SAND_TRACK_COLOR.lerp(GRASS_TRACK_COLOR, grass_weight),
		"segment": _carve_track_segment,
	})
	while _carve_track_points.size() > carve_track_max_points:
		_carve_track_points.pop_front()
	_rebuild_carve_track_mesh()


func _rebuild_carve_track_mesh() -> void:
	if not is_instance_valid(carve_track) or _carve_track_points.size() < 2:
		if is_instance_valid(carve_track):
			carve_track.mesh = null
		return
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var point_count := _carve_track_points.size()
	for point_index in range(point_count):
		var point := _carve_track_points[point_index]
		var position := Vector3(point.position)
		var normal := Vector3(point.normal)
		var right := Vector3(point.right) * carve_track_width * 0.5
		var color := Color(point.color)
		color.a *= smoothstep(0.0, 0.16, float(point_index) / float(maxi(1, point_count - 1)))
		vertices.append(position - right)
		vertices.append(position + right)
		normals.append(normal)
		normals.append(normal)
		colors.append(color)
		colors.append(color)
		if point_index == 0:
			continue
		var previous := _carve_track_points[point_index - 1]
		if int(previous.segment) != int(point.segment):
			continue
		var previous_left := (point_index - 1) * 2
		var previous_right := previous_left + 1
		var current_left := point_index * 2
		var current_right := current_left + 1
		indices.append_array(PackedInt32Array([
			previous_left,
			current_right,
			previous_right,
			previous_left,
			current_left,
			current_right,
		]))
	if indices.is_empty():
		carve_track.mesh = null
		return
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	carve_track.mesh = mesh


func _clear_carve_track() -> void:
	_carve_track_points.clear()
	_carve_track_segment = 0
	_carve_track_was_grounded = false
	if is_instance_valid(carve_track):
		carve_track.mesh = null
