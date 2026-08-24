class_name DownhillCameraRig
extends Node3D

@export var target: WindboardController
@export_range(1.0, 20.0, 0.1, "suffix:m") var follow_distance_m := 8.5
@export_range(0.5, 10.0, 0.1, "suffix:m") var follow_height_m := 3.8
@export_range(1.0, 30.0, 0.5, "suffix:1/s") var position_response := 7.0
@export_range(1.0, 30.0, 0.5, "suffix:1/s") var aim_response := 10.0
@export_range(45.0, 100.0, 0.5, "suffix:°") var base_fov_degrees := 72.0
@export_range(45.0, 110.0, 0.5, "suffix:°") var maximum_fov_degrees := 82.0
@export_range(5.0, 60.0, 0.5, "suffix:m/s") var fov_reference_speed_mps := 36.0
@export_range(1.0, 20.0, 0.5, "suffix:1/s") var fov_response := 4.5

@onready var camera: Camera3D = %Camera

var _aim_point := Vector3.ZERO
var _shake_seconds := 0.0
var _shake_strength := 0.0
var _visual_time := 0.0


func _ready() -> void:
	if target != null:
		target.respawned.connect(_on_target_respawned)
		target.landed.connect(_on_target_landed)
		target.crashed.connect(_on_target_crashed)
		_snap_to_target()


func _process(delta: float) -> void:
	if target == null:
		return
	_visual_time += delta
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
	var fov_blend := 1.0 - exp(-fov_response * delta)
	if _shake_seconds > 0.0:
		_shake_seconds = maxf(0.0, _shake_seconds - delta)
		var comfort := float(SettingsStore.get_setting(&"accessibility", &"camera_shake_strength"))
		var envelope := minf(_shake_seconds * 8.0, 1.0)
		var shake := Vector3(
			sin(_visual_time * 47.0),
			cos(_visual_time * 61.0) * 0.65,
			0.0
		) * _shake_strength * comfort * envelope
		desired_position += shake
	global_position = global_position.lerp(desired_position, position_blend)
	_aim_point = _aim_point.lerp(desired_aim, aim_blend)
	camera.fov = lerpf(camera.fov, CameraResponse.speed_fov(
		speed, base_fov_degrees, maximum_fov_degrees, fov_reference_speed_mps
	), fov_blend)
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
	camera.fov = CameraResponse.speed_fov(
		target.motion_model.velocity.length(),
		base_fov_degrees,
		maximum_fov_degrees,
		fov_reference_speed_mps
	)


func _on_target_respawned(_count: int) -> void:
	_shake_seconds = 0.0
	_shake_strength = 0.0
	_snap_to_target()


func _on_target_landed(result: Dictionary) -> void:
	var damage := float(result.get("stability_damage", 0.0))
	if damage <= 0.0:
		return
	_shake_seconds = 0.12
	_shake_strength = 0.08 + damage * 0.12


func _on_target_crashed(_cause: StringName, _details: Dictionary) -> void:
	_shake_seconds = 0.28
	_shake_strength = 0.32
