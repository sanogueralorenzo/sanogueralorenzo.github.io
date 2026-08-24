class_name WindboardFeedback
extends Node

@onready var controller := get_parent() as WindboardController
@onready var contact_trail: MeshInstance3D = %ContactTrail
@onready var snow_spray: GPUParticles3D = %SnowSpray


func _process(_delta: float) -> void:
	if controller == null:
		return
	var speed := controller.motion_model.velocity.length()
	var supported := controller.motion_state == WindboardController.MotionState.GROUNDED \
		or controller.motion_state == WindboardController.MotionState.COYOTE
	var intensity := clampf(inverse_lerp(3.0, 32.0, speed), 0.0, 1.0)
	contact_trail.visible = supported and intensity > 0.02
	contact_trail.scale = Vector3(
		lerpf(0.55, 1.2, intensity),
		1.0,
		lerpf(0.35, 4.2, intensity)
	)
	contact_trail.position.z = 0.6 + contact_trail.scale.z * 0.5
	snow_spray.emitting = supported and speed > 4.0 \
		and controller.motion_state != WindboardController.MotionState.CRASHED
	snow_spray.amount_ratio = lerpf(0.12, 1.0, intensity)
