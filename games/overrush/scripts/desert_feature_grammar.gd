class_name DesertFeatureGrammar
extends RefCounted

const CELL_SIZE := 512.0
const CACHE_LIMIT := 512
const BOWL := &"bowl"
const RIDGE := &"ridge"
const KICKER := &"kicker"
const SPLIT_LINE := &"split_line"
const OPEN_SAND := &"open_sand"
const MAXIMUM_AXIS_JITTER_DEGREES := 20.0
const KICKER_APPROACH_START := -140.0
const KICKER_LIP_ALONG := 12.0
const KICKER_RUNOUT_END := 190.0
const KICKER_CATCH_CURVE := 1.25
const PROTECTED_ROUTE_NEIGHBOR_RANGE := 1
const KICKER_ROUTE_HALF_WIDTH := 16.0
const BOWL_EXIT_START := -12.0
const BOWL_EXIT_END := 190.0
const BOWL_EXIT_HALF_WIDTH := 18.0
const RIDGE_ROUTE_OFFSET := 86.0
const RIDGE_ROUTE_START := -148.0
const RIDGE_ROUTE_END := 190.0
const RIDGE_ROUTE_HALF_WIDTH := 14.0
const SPLIT_ROUTE_START := -150.0
const SPLIT_ROUTE_END := 190.0
const SPLIT_ROUTE_HALF_WIDTH := 15.0
const OPEN_SAND_RADIUS := 55.0

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
			var along_extent := 156.0 if along < 0.0 else 204.0
			var radius_ratio := Vector2(along / along_extent, across / 118.0).length()
			var bowl_falloff := 1.0 - smoothstep(0.42, 1.0, radius_ratio)
			return -amplitude * bowl_falloff * bowl_falloff
		RIDGE:
			var along_extent := 165.0 if along < 0.0 else 204.0
			var ridge_length := 1.0 - smoothstep(0.6, 1.0, absf(along) / along_extent)
			var ridge_width := 1.0 - smoothstep(0.1, 1.0, absf(across) / 66.0)
			return amplitude * ridge_length * ridge_width
		KICKER:
			if along <= KICKER_APPROACH_START or along >= KICKER_RUNOUT_END:
				return 0.0
			var approach := smoothstep(KICKER_APPROACH_START, KICKER_LIP_ALONG, along)
			var landing_transition := pow(
				1.0 - smoothstep(KICKER_LIP_ALONG, KICKER_RUNOUT_END, along),
				KICKER_CATCH_CURVE,
			)
			var ramp_profile := approach * landing_transition
			var ramp_width := 1.0 - smoothstep(0.28, 1.0, absf(across) / 82.0)
			return amplitude * ramp_profile * ramp_width
		SPLIT_LINE:
			var along_extent := 160.0 if along < 0.0 else 195.0
			var split_length := 1.0 - smoothstep(0.56, 1.0, absf(along) / along_extent)
			var first_lobe := 1.0 - smoothstep(0.16, 1.0, absf(across - 46.0) / 52.0)
			var second_lobe := 1.0 - smoothstep(0.16, 1.0, absf(across + 46.0) / 52.0)
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


## Returns true when an obstacle circle would overlap an authored traversal lane.
## Positions use the same stable logical/world XZ coordinates as sample_height_offset.
## The radius expands the lane by the obstacle's collision footprint; it does not add
## a separate gameplay safety margin. Nearby cells are included so the result remains
## stable when an obstacle center lies on a cell seam.
func intersects_protected_route(logical_position: Vector2, collision_radius: float = 0.0) -> bool:
	var center_coord := get_cell_coordinate(logical_position)
	var safe_radius := maxf(collision_radius, 0.0)
	for z_offset in range(-PROTECTED_ROUTE_NEIGHBOR_RANGE, PROTECTED_ROUTE_NEIGHBOR_RANGE + 1):
		for x_offset in range(-PROTECTED_ROUTE_NEIGHBOR_RANGE, PROTECTED_ROUTE_NEIGHBOR_RANGE + 1):
			var coord := center_coord + Vector2i(x_offset, z_offset)
			if _descriptor_route_intersects(_get_descriptor(coord), logical_position, safe_radius):
				return true
	return false


func _descriptor_route_intersects(
	descriptor: Dictionary,
	logical_position: Vector2,
	collision_radius: float,
) -> bool:
	var axis := Vector2.from_angle(float(descriptor.angle))
	var side := Vector2(-axis.y, axis.x)
	var local: Vector2 = logical_position - Vector2(descriptor.center)
	var along := local.dot(axis)
	var across := local.dot(side)
	var kind: StringName = descriptor.kind
	match kind:
		KICKER:
			return _circle_intersects_lane(
				along,
				across,
				collision_radius,
				KICKER_APPROACH_START,
				KICKER_RUNOUT_END,
				0.0,
				KICKER_ROUTE_HALF_WIDTH,
			)
		BOWL:
			return _circle_intersects_lane(
				along,
				across,
				collision_radius,
				BOWL_EXIT_START,
				BOWL_EXIT_END,
				0.0,
				BOWL_EXIT_HALF_WIDTH,
			)
		RIDGE:
			return (
				_circle_intersects_lane(
					along,
					across,
					collision_radius,
					RIDGE_ROUTE_START,
					RIDGE_ROUTE_END,
					-RIDGE_ROUTE_OFFSET,
					RIDGE_ROUTE_HALF_WIDTH,
				)
				or _circle_intersects_lane(
					along,
					across,
					collision_radius,
					RIDGE_ROUTE_START,
					RIDGE_ROUTE_END,
					RIDGE_ROUTE_OFFSET,
					RIDGE_ROUTE_HALF_WIDTH,
				)
			)
		SPLIT_LINE:
			return _circle_intersects_lane(
				along,
				across,
				collision_radius,
				SPLIT_ROUTE_START,
				SPLIT_ROUTE_END,
				0.0,
				SPLIT_ROUTE_HALF_WIDTH,
			)
		OPEN_SAND:
			return local.length() <= OPEN_SAND_RADIUS + collision_radius
	return false


func _circle_intersects_lane(
	along: float,
	across: float,
	collision_radius: float,
	start: float,
	end: float,
	lane_offset: float,
	half_width: float,
) -> bool:
	var closest_along := clampf(along, start, end)
	var delta := Vector2(along - closest_along, across - lane_offset)
	var expanded_width := half_width + collision_radius
	return delta.length_squared() <= expanded_width * expanded_width


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
	var outward := center.normalized()
	if outward.length_squared() <= 0.001:
		outward = Vector2.from_angle(get_cell_random(coord, 6) * TAU)
	var axis_jitter := deg_to_rad(lerpf(
		-MAXIMUM_AXIS_JITTER_DEGREES,
		MAXIMUM_AXIS_JITTER_DEGREES,
		get_cell_random(coord, 4),
	))
	var descriptor := {
		"kind": kind,
		"center": center,
		"angle": outward.angle() + axis_jitter,
		"amplitude": lerpf(7.5, 10.0, get_cell_random(coord, 5)),
	}
	_descriptor_cache[coord] = descriptor
	_cache_order.append(coord)
	if _cache_order.size() > CACHE_LIMIT:
		_descriptor_cache.erase(_cache_order.pop_front())
	return descriptor
