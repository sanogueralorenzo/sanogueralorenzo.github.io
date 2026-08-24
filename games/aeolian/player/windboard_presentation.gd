extends Node3D

@export_range(1.0, 40.0, 0.5, "suffix:1/s") var alignment_rate := 18.0

@onready var controller := get_parent() as WindboardController


func _process(delta: float) -> void:
	if controller == null:
		return
	var up := controller.filtered_ground_normal.normalized()
	if controller.motion_state == WindboardController.MotionState.AIRBORNE:
		up = Vector3.UP
	var forward := controller.motion_model.heading.slide(up).normalized()
	if forward.is_zero_approx():
		forward = Vector3.FORWARD
	var right := forward.cross(up).normalized()
	var target := Basis(right, up, -forward).orthonormalized()
	var blend := 1.0 - exp(-alignment_rate * delta)
	global_basis = Basis(global_basis.get_rotation_quaternion().slerp(
		target.get_rotation_quaternion(), blend
	))
