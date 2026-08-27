class_name DesertFeatureGrammar
extends RefCounted

const CELL_SIZE := 512.0
const CACHE_LIMIT := 512
const BOWL := &"bowl"
const RIDGE := &"ridge"
const KICKER := &"kicker"
const SPLIT_LINE := &"split_line"
const OPEN_SAND := &"open_sand"

var _seed := 1
var _descriptor_cache: Dictionary = {}
var _cache_order: Array[Vector2i] = []


func configure(world_seed: int) -> void:
	_seed = world_seed
	_descriptor_cache.clear()
	_cache_order.clear()


func sample_height_offset(x: float, z: float) -> float:
	var coord := get_cell_coordinate(Vector2(x, z))
	var descriptor := _get_descriptor(coord)
	var kind: StringName = descriptor.kind
	if kind == OPEN_SAND:
		return 0.0
	var center: Vector2 = descriptor.center
	var local := Vector2(x, z) - center
	var axis := Vector2(cos(descriptor.angle), sin(descriptor.angle))
	var side := Vector2(-axis.y, axis.x)
	var along := local.dot(axis)
	var across := local.dot(side)
	var amplitude: float = descriptor.amplitude

	match kind:
		BOWL:
			var radius_ratio := local.length() / 150.0
			var bowl_falloff := 1.0 - smoothstep(0.42, 1.0, radius_ratio)
			return -amplitude * bowl_falloff * bowl_falloff
		RIDGE:
			var ridge_length := 1.0 - smoothstep(0.62, 1.0, absf(along) / 158.0)
			var ridge_width := 1.0 - smoothstep(0.12, 1.0, absf(across) / 68.0)
			return amplitude * ridge_length * ridge_width
		KICKER:
			if absf(along) >= 108.0:
				return 0.0
			var ramp_t := (along + 108.0) / 216.0
			var ramp_profile := pow(sin(PI * ramp_t), 2.0)
			var ramp_width := 1.0 - smoothstep(0.45, 1.0, absf(across) / 74.0)
			return amplitude * ramp_profile * ramp_width
		SPLIT_LINE:
			var split_length := 1.0 - smoothstep(0.58, 1.0, absf(along) / 154.0)
			var first_lobe := 1.0 - smoothstep(0.18, 1.0, absf(across - 43.0) / 42.0)
			var second_lobe := 1.0 - smoothstep(0.18, 1.0, absf(across + 43.0) / 42.0)
			return amplitude * split_length * maxf(first_lobe, second_lobe)
		_:
			return 0.0


func get_feature_kind_at(logical_position: Vector2) -> StringName:
	return _get_descriptor(get_cell_coordinate(logical_position)).kind


func get_feature_kind_for_cell(coord: Vector2i) -> StringName:
	return _get_descriptor(coord).kind


func get_cell_coordinate(logical_position: Vector2) -> Vector2i:
	var half_cell := CELL_SIZE * 0.5
	return Vector2i(
		floori((logical_position.x + half_cell) / CELL_SIZE),
		floori((logical_position.y + half_cell) / CELL_SIZE),
	)


func get_cell_random(coord: Vector2i, salt: int) -> float:
	var mixed := Vector3i(
		coord.x * 92821 + salt * 71,
		coord.y * 68917 - salt * 43,
		_seed * 313 + salt * 997,
	)
	return float(hash(mixed) & 0x7fffffff) / 2147483647.0


func get_cached_descriptor_count() -> int:
	return _descriptor_cache.size()


func _get_descriptor(coord: Vector2i) -> Dictionary:
	if _descriptor_cache.has(coord):
		return _descriptor_cache[coord]
	var selector := get_cell_random(coord, 1)
	var kind := OPEN_SAND
	if selector < 0.24:
		kind = BOWL
	elif selector < 0.46:
		kind = RIDGE
	elif selector < 0.70:
		kind = KICKER
	elif selector < 0.90:
		kind = SPLIT_LINE
	var center := Vector2(coord) * CELL_SIZE + Vector2(
		lerpf(-32.0, 32.0, get_cell_random(coord, 2)),
		lerpf(-32.0, 32.0, get_cell_random(coord, 3)),
	)
	var descriptor := {
		"kind": kind,
		"center": center,
		"angle": get_cell_random(coord, 4) * TAU,
		"amplitude": lerpf(7.5, 10.0, get_cell_random(coord, 5)),
	}
	_descriptor_cache[coord] = descriptor
	_cache_order.append(coord)
	if _cache_order.size() > CACHE_LIMIT:
		_descriptor_cache.erase(_cache_order.pop_front())
	return descriptor
