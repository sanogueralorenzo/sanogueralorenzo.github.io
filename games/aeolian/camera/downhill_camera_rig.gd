class_name DownhillCameraRig
extends Node3D

@export var target: WindboardController
@export_range(1.0, 20.0, 0.1, "suffix:m") var follow_distance_m := 8.5
@export_range(0.5, 10.0, 0.1, "suffix:m") var follow_height_m := 3.8
@export_range(1.0, 30.0, 0.5, "suffix:1/s") var position_response := 7.0
@export_range(1.0, 30.0, 0.5, "suffix:1/s") var aim_response := 10.0

var _aim_point := Vector3.ZERO


func _ready() -> void:
	if target != null:
		target.respawned.connect(_on_target_respawned)
		_snap_to_target()


func _process(delta: float) -> void:
	if target == null:
		return
	var heading := target.motion_model.heading.slide(Vector3.UP).normalized()
	if heading.is_zero_approx():
		heading = Vector3.FORWARD
	var speed := target.motion_model.velocity.length()
	var desired_position := target.global_position - heading * follow_distance_m \
		+ Vector3.UP * follow_height_m
	var desired_aim := target.global_position + heading * (5.0 + speed * 0.22) \
		- Vector3.UP * minf(speed * 0.025, 1.0)
	var position_blend := 1.0 - exp(-position_response * delta)
	var aim_blend := 1.0 - exp(-aim_response * delta)
	global_position = global_position.lerp(desired_position, position_blend)
	_aim_point = _aim_point.lerp(desired_aim, aim_blend)
	if global_position.distance_squared_to(_aim_point) > 0.01:
		look_at(_aim_point, Vector3.UP)


func _snap_to_target() -> void:
	if target == null:
		return
	var heading := target.motion_model.heading.slide(Vector3.UP).normalized()
	if heading.is_zero_approx():
		heading = Vector3.FORWARD
	global_position = target.global_position - heading * follow_distance_m \
		+ Vector3.UP * follow_height_m
	_aim_point = target.global_position + heading * 5.0
	look_at(_aim_point, Vector3.UP)


func _on_target_respawned(_count: int) -> void:
	_snap_to_target()
