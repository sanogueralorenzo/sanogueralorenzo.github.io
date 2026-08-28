extends Camera3D

@export var target_path: NodePath
@export var world_path: NodePath
@export var follow_distance: float = 6.4
@export var follow_height: float = 3.8
@export var position_smoothing: float = 7.5
@export var speed_position_smoothing: float = 0.22
@export var look_ahead: float = 18.0
@export var focus_height: float = 0.6
@export var mouse_sensitivity: float = 0.0025
@export var gamepad_look_speed: float = 2.4
@export var minimum_pitch_degrees: float = 10.0
@export var maximum_pitch_degrees: float = 55.0
@export var normal_fov: float = 66.0
@export var boost_fov: float = 82.0
@export var speed_fov_start: float = 15.0
@export var speed_fov_full: float = 72.0
@export var speed_fov_addition: float = 4.0
@export var fov_smoothing: float = 12.0
@export var terrain_clearance: float = 0.7
@export_range(3, 12, 1) var terrain_probe_samples := 7
@export var obstacle_padding := 0.7
@export var obstacle_release_speed := 18.0

var _target: CharacterBody3D
var _world: ProceduralDesert
var _speed_burst_active := false
var _reduced_motion := false
var _controls_enabled := false
var _yaw := 0.0
var _pitch := 0.0
var _smoothed_target_position := Vector3.ZERO
var _base_mouse_sensitivity := 0.0
var _base_gamepad_look_speed := 0.0
var _look_sensitivity_multiplier := 1.0
var _obstacle_distance_limit := INF


func _ready() -> void:
	_target = get_node(target_path)
	_world = get_node_or_null(world_path) as ProceduralDesert
	_pitch = atan2(follow_height, follow_distance)
	_smoothed_target_position = _target.global_position
	_base_mouse_sensitivity = mouse_sensitivity
	_base_gamepad_look_speed = gamepad_look_speed
	set_controls_enabled(false)


func _exit_tree() -> void:
	if DisplayServer.get_name() != "headless" and _controls_enabled:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _unhandled_input(event: InputEvent) -> void:
	if not _controls_enabled or not event is InputEventMouseMotion:
		return
	apply_look_delta(event.relative * mouse_sensitivity)
	get_viewport().set_input_as_handled()


func _physics_process(delta: float) -> void:
	if not is_instance_valid(_target):
		return
	if _controls_enabled:
		var look_input := Input.get_vector(
			OverrushInputBindings.LOOK_LEFT,
			OverrushInputBindings.LOOK_RIGHT,
			OverrushInputBindings.LOOK_UP,
			OverrushInputBindings.LOOK_DOWN
		)
		apply_look_delta(look_input * gamepad_look_speed * delta)
	var forward := get_planar_forward()
	var orbit_height := tan(_pitch) * follow_distance
	var blend := 1.0 - exp(-get_follow_response_rate(_get_planar_speed()) * delta)
	_smoothed_target_position = _smoothed_target_position.lerp(_target.global_position, blend)
	var focus := _get_focus(forward)
	var desired_position := _smoothed_target_position - forward * follow_distance + Vector3.UP * orbit_height
	var terrain_resolved := _resolve_terrain_clearance(desired_position, focus)
	var sightline_origin := _target.global_position + Vector3.UP * focus_height
	global_position = _resolve_obstacle_clearance(terrain_resolved, sightline_origin, delta)
	look_at(focus, Vector3.UP)
	var target_fov := _get_target_fov()
	fov = lerpf(fov, target_fov, 1.0 - exp(-fov_smoothing * delta))


func _get_target_fov() -> float:
	if _reduced_motion:
		return normal_fov
	if _speed_burst_active:
		return boost_fov
	var planar_speed := _get_planar_speed()
	var speed_ratio := smoothstep(speed_fov_start, speed_fov_full, planar_speed)
	return normal_fov + speed_fov_addition * speed_ratio


func get_follow_response_rate(planar_speed: float) -> float:
	return position_smoothing + maxf(0.0, planar_speed) * speed_position_smoothing


func _get_planar_speed() -> float:
	return Vector2(_target.velocity.x, _target.velocity.z).length()


func set_speed_burst_active(active: bool) -> void:
	_speed_burst_active = active


func set_reduced_motion(enabled: bool) -> void:
	_reduced_motion = enabled
	if enabled:
		fov = normal_fov


func set_look_sensitivity_multiplier(multiplier: float) -> void:
	_look_sensitivity_multiplier = clampf(multiplier, 0.5, 2.0)
	mouse_sensitivity = _base_mouse_sensitivity * _look_sensitivity_multiplier
	gamepad_look_speed = _base_gamepad_look_speed * _look_sensitivity_multiplier


func get_look_sensitivity_multiplier() -> float:
	return _look_sensitivity_multiplier


func set_controls_enabled(enabled: bool) -> void:
	_controls_enabled = enabled
	if DisplayServer.get_name() != "headless":
		var desired_mode := Input.MOUSE_MODE_CAPTURED if enabled else Input.MOUSE_MODE_VISIBLE
		if Input.mouse_mode != desired_mode:
			Input.mouse_mode = desired_mode


func apply_look_delta(look_delta: Vector2) -> void:
	_yaw = wrapf(_yaw - look_delta.x, -PI, PI)
	_pitch = clampf(
		_pitch + look_delta.y,
		deg_to_rad(minimum_pitch_degrees),
		deg_to_rad(maximum_pitch_degrees)
	)


func get_planar_forward() -> Vector3:
	return Vector3.FORWARD.rotated(Vector3.UP, _yaw).normalized()


func get_planar_right() -> Vector3:
	return get_planar_forward().cross(Vector3.UP).normalized()


func set_orbit_angles(yaw: float, pitch: float) -> void:
	_yaw = wrapf(yaw, -PI, PI)
	_pitch = clampf(pitch, deg_to_rad(minimum_pitch_degrees), deg_to_rad(maximum_pitch_degrees))


func snap_to_target() -> void:
	if not is_instance_valid(_target):
		_target = get_node(target_path)
	var forward := get_planar_forward()
	_smoothed_target_position = _target.global_position
	var focus := _get_focus(forward)
	var desired_position := _target.global_position - forward * follow_distance + Vector3.UP * tan(_pitch) * follow_distance
	var terrain_resolved := _resolve_terrain_clearance(desired_position, focus)
	var sightline_origin := _target.global_position + Vector3.UP * focus_height
	global_position = _resolve_obstacle_clearance(terrain_resolved, sightline_origin, 0.0, true)
	look_at(focus, Vector3.UP)


func get_current_minimum_terrain_clearance() -> float:
	if not is_instance_valid(_target) or not is_instance_valid(_world):
		return INF
	var focus := _get_focus(get_planar_forward())
	return _sample_minimum_terrain_clearance(focus, global_position)


func _get_focus(forward: Vector3) -> Vector3:
	var focus := _target.global_position + forward * look_ahead + Vector3.UP * focus_height
	if not is_instance_valid(_world):
		return focus
	var surface_focus_height := (
		_world.get_local_surface_height(focus.x, focus.z)
		+ focus_height
	)
	focus.y = minf(focus.y, surface_focus_height)
	return focus


func _resolve_terrain_clearance(desired_position: Vector3, focus: Vector3) -> Vector3:
	if not is_instance_valid(_world):
		return desired_position
	var required_camera_lift := 0.0
	for sample_index in range(1, terrain_probe_samples + 1):
		var progress := float(sample_index) / float(terrain_probe_samples)
		var point := focus.lerp(desired_position, progress)
		var surface_height := _world.get_local_surface_height(point.x, point.z)
		var clearance_deficit := surface_height + terrain_clearance - point.y
		if clearance_deficit > 0.0:
			required_camera_lift = maxf(required_camera_lift, clearance_deficit / progress)
	var resolved := desired_position
	resolved.y += required_camera_lift
	return resolved


func _sample_minimum_terrain_clearance(from: Vector3, to: Vector3) -> float:
	var minimum_clearance := INF
	for sample_index in range(1, terrain_probe_samples + 1):
		var progress := float(sample_index) / float(terrain_probe_samples)
		var point := from.lerp(to, progress)
		minimum_clearance = minf(minimum_clearance, point.y - _world.get_local_surface_height(point.x, point.z))
	return minimum_clearance


func _resolve_obstacle_clearance(
	desired_position: Vector3,
	sightline_origin: Vector3,
	delta: float,
	instant := false,
) -> Vector3:
	var offset := desired_position - sightline_origin
	var desired_distance := offset.length()
	if desired_distance <= 0.001 or not is_instance_valid(_world):
		return desired_position
	var allowed_distance := desired_distance
	var hit := _find_obstacle_hit(sightline_origin, desired_position)
	if not hit.is_empty():
		allowed_distance = maxf(0.25, sightline_origin.distance_to(Vector3(hit.position)) - obstacle_padding)
	if instant or not is_finite(_obstacle_distance_limit):
		_obstacle_distance_limit = allowed_distance
	elif allowed_distance < _obstacle_distance_limit:
		_obstacle_distance_limit = allowed_distance
	else:
		_obstacle_distance_limit = move_toward(
			_obstacle_distance_limit,
			allowed_distance,
			obstacle_release_speed * delta,
		)
	_obstacle_distance_limit = minf(_obstacle_distance_limit, desired_distance)
	return sightline_origin + offset / desired_distance * _obstacle_distance_limit


func _find_obstacle_hit(from: Vector3, to: Vector3) -> Dictionary:
	if from.is_equal_approx(to):
		return {}
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.hit_back_faces = true
	if is_instance_valid(_target):
		query.exclude = [_target.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty() or not _world.is_obstacle_collider(hit.collider):
		return {}
	return hit


func apply_world_rebase(shift: Vector3) -> void:
	global_position -= shift
	_smoothed_target_position -= shift
