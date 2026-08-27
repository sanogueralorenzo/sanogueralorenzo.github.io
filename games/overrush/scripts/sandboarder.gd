class_name Sandboarder
extends CharacterBody3D

signal air_boost_state_changed(available: bool, airborne: bool)
signal air_boost_used
signal landed(impact_speed: float)

@export var world_path: NodePath
@export var camera_path: NodePath
@export var gravity_strength := 30.0
@export var slope_acceleration := 44.0
@export var starting_push := 18.0
@export var summit_push_speed := 14.0
@export var ground_drag := 0.18
@export var carve_response := 3.8
@export var carve_speed_loss := 0.035
@export var air_control := 5.0
@export var jump_velocity := 10.5
@export var air_boost_impulse := 19.0
@export var air_boost_lift := 4.5
@export var maximum_speed := 78.0
@export var valid_landing_normal_y := 0.55
@export var minimum_landing_airtime := 0.08

@onready var board_visual: Node3D = $BoardVisual
@onready var boost_trail: GPUParticles3D = $BoostTrail
@onready var boost_light: OmniLight3D = $BoostLight

var air_boost_state := AirBoostState.new()
var distance_traveled := 0.0
var _world: ProceduralDesert
var _camera: Camera3D
var _last_position := Vector3.ZERO
var _airtime := 0.0
var _heading := Vector3.FORWARD
var _boost_feedback_time := 0.0


func _ready() -> void:
	OverrushInputBindings.ensure_actions()
	_world = get_node(world_path)
	_camera = get_node(camera_path)
	floor_snap_length = 1.1
	floor_max_angle = deg_to_rad(58.0)
	floor_stop_on_slope = false
	_last_position = global_position
	air_boost_state.reset_on_sand()
	air_boost_state_changed.emit(true, false)


func _physics_process(delta: float) -> void:
	var started_on_floor := is_on_floor()
	var input_direction := get_camera_relative_direction()
	if started_on_floor:
		_apply_ground_motion(input_direction, delta)
		if Input.is_action_just_pressed(OverrushInputBindings.HOP):
			velocity.y = jump_velocity
			air_boost_state.leave_surface()
			_airtime = 0.0
			air_boost_state_changed.emit(air_boost_state.available, true)
	else:
		_apply_air_motion(input_direction, delta)
		_airtime += delta
		if not air_boost_state.airborne:
			air_boost_state.leave_surface()
			air_boost_state_changed.emit(air_boost_state.available, true)

	if Input.is_action_just_pressed(OverrushInputBindings.AIR_BOOST):
		try_air_boost(input_direction)

	var before_move := velocity
	move_and_slide()
	_update_surface_state(started_on_floor, before_move)
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
	air_boost_state.reset_on_sand()
	_last_position = global_position
	air_boost_state_changed.emit(true, false)


func apply_world_rebase(shift: Vector3) -> void:
	global_position -= shift
	_last_position = global_position


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


func _apply_ground_motion(input_direction: Vector3, delta: float) -> void:
	var normal := get_floor_normal()
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var speed := horizontal.length()
	var downhill := Vector3.DOWN.slide(normal)
	if downhill.length_squared() > 0.0001:
		velocity += downhill.normalized() * slope_acceleration * (1.0 - normal.y) * delta
	if input_direction.length_squared() > 0.01:
		var tangent_input := input_direction.slide(normal).normalized()
		if speed < summit_push_speed:
			velocity += tangent_input * starting_push * delta
		else:
			var current_direction := horizontal.normalized()
			var carved_direction := current_direction.slerp(tangent_input, clampf(carve_response * delta, 0.0, 1.0))
			var retained_speed := speed * (1.0 - carve_speed_loss * delta)
			velocity.x = carved_direction.x * retained_speed
			velocity.z = carved_direction.z * retained_speed
		_heading = tangent_input
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
	_limit_horizontal_speed(maximum_speed * 1.18)


func _update_surface_state(started_on_floor: bool, impact_velocity: Vector3) -> void:
	var ended_on_floor := is_on_floor()
	if ended_on_floor and not started_on_floor:
		var valid_sand := _airtime >= minimum_landing_airtime and _has_valid_sand_floor_contact()
		air_boost_state.land(valid_sand)
		if valid_sand:
			landed.emit(maxf(0.0, -impact_velocity.y))
		air_boost_state_changed.emit(air_boost_state.available, false)
		_airtime = 0.0
	elif not ended_on_floor and started_on_floor:
		air_boost_state.leave_surface()
		_airtime = 0.0
		air_boost_state_changed.emit(air_boost_state.available, true)


func _has_valid_sand_floor_contact() -> bool:
	for index in range(get_slide_collision_count()):
		var collision := get_slide_collision(index)
		if _world.is_sand_collider(collision.get_collider()) and collision.get_normal().y >= valid_landing_normal_y:
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
		board_visual.rotation.y = lerp_angle(board_visual.rotation.y, atan2(-_heading.x, -_heading.z), 1.0 - exp(-9.0 * delta))
	_boost_feedback_time = maxf(0.0, _boost_feedback_time - delta)
	if _boost_feedback_time <= 0.0:
		boost_trail.emitting = false
		boost_light.visible = false
