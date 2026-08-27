extends Camera3D

@export var target_path: NodePath
@export var follow_distance: float = 17.0
@export var follow_height: float = 8.0
@export var position_smoothing: float = 7.5
@export var look_ahead: float = 16.0
@export var normal_fov: float = 82.0
@export var dash_fov: float = 96.0
@export var fov_smoothing: float = 12.0

var _target: CharacterBody3D
var _last_direction := Vector3.FORWARD
var _dash_active := false
var _reduced_motion := false


func _ready() -> void:
	_target = get_node(target_path)


func _physics_process(delta: float) -> void:
	if not is_instance_valid(_target):
		return
	var horizontal_velocity := Vector3(_target.velocity.x, 0.0, _target.velocity.z)
	if horizontal_velocity.length_squared() > 4.0:
		_last_direction = horizontal_velocity.normalized()
	var desired_position := _target.global_position - _last_direction * follow_distance + Vector3.UP * follow_height
	var blend := 1.0 - exp(-position_smoothing * delta)
	global_position = global_position.lerp(desired_position, blend)
	look_at(_target.global_position + _last_direction * look_ahead + Vector3.UP * 1.5, Vector3.UP)
	var target_fov := normal_fov if _reduced_motion else (dash_fov if _dash_active else normal_fov)
	fov = lerpf(fov, target_fov, 1.0 - exp(-fov_smoothing * delta))


func set_dash_active(active: bool) -> void:
	_dash_active = active


func set_reduced_motion(enabled: bool) -> void:
	_reduced_motion = enabled
	if enabled:
		fov = normal_fov


func snap_to_target() -> void:
	if not is_instance_valid(_target):
		_target = get_node(target_path)
	var horizontal_velocity := Vector3(_target.velocity.x, 0.0, _target.velocity.z)
	if horizontal_velocity.length_squared() > 0.01:
		_last_direction = horizontal_velocity.normalized()
	global_position = _target.global_position - _last_direction * follow_distance + Vector3.UP * follow_height
	look_at(_target.global_position + _last_direction * look_ahead + Vector3.UP * 1.5, Vector3.UP)
