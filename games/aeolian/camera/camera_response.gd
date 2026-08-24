class_name CameraResponse
extends RefCounted


static func speed_fov(
		speed_mps: float,
		base_fov: float,
		maximum_fov: float,
		reference_speed: float
	) -> float:
	var ratio := clampf(speed_mps / maxf(reference_speed, 0.001), 0.0, 1.0)
	return lerpf(base_fov, maximum_fov, ratio * ratio * (3.0 - 2.0 * ratio))
