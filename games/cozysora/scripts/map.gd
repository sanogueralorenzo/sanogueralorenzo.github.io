class_name CozyMap
extends Node3D
## Minimal scene contract: build local content and describe traversable ground.
signal load_progress(message: String, fraction: float)
var scenic_views: Dictionary = {}
var ambience: Dictionary = {}
var generation_signature := ""
var supports_surface_traversal := false
var flight_bounds := AABB(Vector3(-135,-30,-95),Vector3(270,140,213))

func build() -> void:
	pass

func set_paused(_value: bool) -> void:
	pass

func height_at(_x: float, _z: float) -> float:
	return 0.0

func walkable(_x: float, _z: float) -> bool:
	return true
