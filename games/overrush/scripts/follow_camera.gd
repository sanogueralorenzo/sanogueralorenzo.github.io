extends Camera3D

@export var target_path: NodePath
@export var follow_distance: float = 17.0
@export var follow_height: float = 8.0
@export var position_smoothing: float = 7.5
@export var look_ahead: float = 4.0
@export var focus_height: float = 1.5
@export var mouse_sensitivity: float = 0.0025
@export var gamepad_look_speed: float = 2.4
@export var minimum_pitch_degrees: float = 10.0
@export var maximum_pitch_degrees: float = 55.0
@export var normal_fov: float = 82.0
@export var dash_fov: float = 96.0
@export var fov_smoothing: float = 12.0

var _target: CharacterBody3D
var _dash_active := false
var _reduced_motion := false
var _controls_enabled := false
var _yaw := 0.0
var _pitch := 0.0
var _smoothed_target_position := Vector3.ZERO


func _ready() -> void:
	_target = get_node(target_path)
	_pitch = atan2(follow_height, follow_distance)
	_smoothed_target_position = _target.global_position
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
	var blend := 1.0 - exp(-position_smoothing * delta)
	_smoothed_target_position = _smoothed_target_position.lerp(_target.global_position, blend)
	global_position = _smoothed_target_position - forward * follow_distance + Vector3.UP * orbit_height
	look_at(_target.global_position + forward * look_ahead + Vector3.UP * focus_height, Vector3.UP)
	var target_fov := normal_fov if _reduced_motion else (dash_fov if _dash_active else normal_fov)
	fov = lerpf(fov, target_fov, 1.0 - exp(-fov_smoothing * delta))


func set_dash_active(active: bool) -> void:
	_dash_active = active


func set_speed_burst_active(active: bool) -> void:
	set_dash_active(active)


func set_reduced_motion(enabled: bool) -> void:
	_reduced_motion = enabled
	if enabled:
		fov = normal_fov


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
	global_position = _target.global_position - forward * follow_distance + Vector3.UP * tan(_pitch) * follow_distance
	look_at(_target.global_position + forward * look_ahead + Vector3.UP * focus_height, Vector3.UP)
