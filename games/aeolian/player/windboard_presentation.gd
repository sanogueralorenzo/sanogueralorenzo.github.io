extends Node3D

@export_range(1.0, 40.0, 0.5, "suffix:1/s") var alignment_rate := 18.0
@export_range(0.0, 30.0, 0.5, "suffix:°") var maximum_carve_lean_degrees := 14.0
@export_range(0.0, 20.0, 0.5, "suffix:°") var maximum_instability_wobble_degrees := 7.0

@onready var controller := get_parent() as WindboardController

var _visual_time := 0.0


func _process(delta: float) -> void:
	if controller == null:
		return
	_visual_time += delta
	var up := controller.filtered_ground_normal.normalized()
	if controller.motion_state == WindboardController.MotionState.AIRBORNE:
		up = Vector3.UP
	var forward := controller.motion_model.heading.slide(up).normalized()
	if forward.is_zero_approx():
		forward = Vector3.FORWARD
	var right := forward.cross(up).normalized()
	var target := Basis(right, up, -forward).orthonormalized()
	var carve_lean := -controller.filtered_intent.steer * maximum_carve_lean_degrees
	var instability := 1.0 - controller.motion_model.stability
	var wobble := sin(_visual_time * 15.0) * instability * maximum_instability_wobble_degrees
	var crash_roll := 68.0 if controller.motion_state == WindboardController.MotionState.CRASHED else 0.0
	target = Basis(forward, deg_to_rad(carve_lean + wobble + crash_roll)) * target
	var blend := 1.0 - exp(-alignment_rate * delta)
	global_basis = Basis(global_basis.get_rotation_quaternion().slerp(
		target.get_rotation_quaternion(), blend
	))
