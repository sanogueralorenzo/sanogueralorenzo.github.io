class_name LandscapeLayout
extends RefCounted

const TREE_CELL_SIZE := 20.0
const ROCK_CELL_SIZE := 64.0
const TREE_SUMMIT_CLEAR_RADIUS := 280.0
const ROCK_SUMMIT_CLEAR_RADIUS := 320.0
const RUIN_MINIMUM_RADIUS := 620.0
const SUMMIT_BIOME_BLEND_START := 80.0
const SUMMIT_BIOME_FULL_RADIUS := 800.0
const SUMMIT_BIOME_FADE_START := 1200.0
const SUMMIT_BIOME_FADE_END := 2800.0

var _seed := 1
var _phase := 0.0
var _biome_noise := FastNoiseLite.new()
var _glade_noise := FastNoiseLite.new()


func configure(world_seed: int) -> void:
	_seed = world_seed
	_phase = get_cell_random(Vector2i.ZERO, 91) * TAU
	_biome_noise.seed = world_seed ^ 0x38A71C
	_biome_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_biome_noise.frequency = 0.00072
	_biome_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_biome_noise.fractal_octaves = 3
	_biome_noise.fractal_gain = 0.42
	_glade_noise.seed = world_seed ^ 0x71C38A
	_glade_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_glade_noise.frequency = 0.0018
	_glade_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_glade_noise.fractal_octaves = 2
	_glade_noise.fractal_gain = 0.38


func get_grass_weight(logical_position: Vector2) -> float:
	var radius := logical_position.length()
	var broad_variation := _biome_noise.get_noise_2dv(logical_position)
	var warped_radius := radius + broad_variation * 420.0
	var traveling_band := sin(warped_radius * 0.00135 + _phase)
	var cross_variation := sin((logical_position.x - logical_position.y) * 0.00031 + _phase * 0.63)
	var field := traveling_band * 0.78 + broad_variation * 0.16 + cross_variation * 0.06
	var summit_influence := (
		smoothstep(SUMMIT_BIOME_BLEND_START, SUMMIT_BIOME_FULL_RADIUS, radius)
		* (1.0 - smoothstep(SUMMIT_BIOME_FADE_START, SUMMIT_BIOME_FADE_END, radius))
	)
	if summit_influence > 0.0:
		var angle := atan2(logical_position.y, logical_position.x)
		var summit_lobes := (
			sin(angle * 2.0 + _phase * 0.37 + warped_radius * 0.00055) * 0.72
			+ 0.04
		)
		field = lerpf(field, summit_lobes, summit_influence * 0.84)
	return smoothstep(-0.3, 0.3, field)


func get_tree_cell_coordinate(logical_position: Vector2) -> Vector2i:
	return Vector2i(floori(logical_position.x / TREE_CELL_SIZE), floori(logical_position.y / TREE_CELL_SIZE))


func get_tree_position(cell: Vector2i) -> Vector2:
	var center := (Vector2(cell) + Vector2(0.5, 0.5)) * TREE_CELL_SIZE
	var jitter := Vector2(
		lerpf(-0.24, 0.24, get_cell_random(cell, 11)),
		lerpf(-0.24, 0.24, get_cell_random(cell, 12)),
	) * TREE_CELL_SIZE
	return center + jitter


func get_tree_density(logical_position: Vector2) -> float:
	var summit_fade := smoothstep(TREE_SUMMIT_CLEAR_RADIUS, TREE_SUMMIT_CLEAR_RADIUS + 180.0, logical_position.length())
	var grass_density := smoothstep(0.58, 0.88, get_grass_weight(logical_position))
	var glade_distance := absf(_glade_noise.get_noise_2dv(logical_position))
	var glade_clearance := smoothstep(0.07, 0.24, glade_distance)
	return 0.6 * summit_fade * grass_density * glade_clearance


func has_tree(cell: Vector2i) -> bool:
	var position := get_tree_position(cell)
	return get_cell_random(cell, 13) < get_tree_density(position)


func get_tree_height(cell: Vector2i) -> float:
	return lerpf(7.5, 14.0, get_cell_random(cell, 14))


func get_tree_radius(cell: Vector2i) -> float:
	return lerpf(0.48, 0.82, get_cell_random(cell, 15))


func get_rock_cell_coordinate(logical_position: Vector2) -> Vector2i:
	return Vector2i(floori(logical_position.x / ROCK_CELL_SIZE), floori(logical_position.y / ROCK_CELL_SIZE))


func get_rock_position(cell: Vector2i) -> Vector2:
	var center := (Vector2(cell) + Vector2(0.5, 0.5)) * ROCK_CELL_SIZE
	var jitter := Vector2(
		lerpf(-0.3, 0.3, get_cell_random(cell, 51)),
		lerpf(-0.3, 0.3, get_cell_random(cell, 52)),
	) * ROCK_CELL_SIZE
	return center + jitter


func get_rock_density(logical_position: Vector2) -> float:
	var summit_fade := smoothstep(ROCK_SUMMIT_CLEAR_RADIUS, ROCK_SUMMIT_CLEAR_RADIUS + 180.0, logical_position.length())
	var cluster := smoothstep(-0.08, 0.42, _glade_noise.get_noise_2dv(logical_position))
	var biome_density := lerpf(0.34, 0.48, get_grass_weight(logical_position))
	return biome_density * summit_fade * cluster


func has_rock(cell: Vector2i) -> bool:
	var position := get_rock_position(cell)
	return get_cell_random(cell, 53) < get_rock_density(position)


func get_rock_radius(cell: Vector2i) -> float:
	return lerpf(1.2, 4.2, pow(get_cell_random(cell, 54), 1.65))


func has_ruin(chunk_coord: Vector2i, chunk_size: float) -> bool:
	if Vector2(chunk_coord).length() * chunk_size < RUIN_MINIMUM_RADIUS:
		return false
	var score := get_cell_random(chunk_coord, 71)
	if score > 0.52:
		return false
	for y_offset in range(-1, 2):
		for x_offset in range(-1, 2):
			if x_offset == 0 and y_offset == 0:
				continue
			if get_cell_random(chunk_coord + Vector2i(x_offset, y_offset), 71) < score:
				return false
	return true


func get_ruin_center(chunk_coord: Vector2i, chunk_size: float) -> Vector2:
	var chunk_center := Vector2(chunk_coord) * chunk_size
	var jitter_limit := chunk_size * 0.18
	return chunk_center + Vector2(
		lerpf(-jitter_limit, jitter_limit, get_cell_random(chunk_coord, 72)),
		lerpf(-jitter_limit, jitter_limit, get_cell_random(chunk_coord, 73)),
	)


func get_ruin_forward(chunk_coord: Vector2i, chunk_size: float) -> Vector2:
	var center := get_ruin_center(chunk_coord, chunk_size)
	var outward := center.normalized()
	if outward.length_squared() < 0.5:
		outward = Vector2(0.0, -1.0)
	var angle_offset := deg_to_rad(lerpf(-18.0, 18.0, get_cell_random(chunk_coord, 74)))
	return outward.rotated(angle_offset).normalized()


func get_cell_random(coord: Vector2i, salt: int) -> float:
	var mixed := Vector3i(
		coord.x * 92821 + salt * 71,
		coord.y * 68917 - salt * 43,
		_seed * 313 + salt * 997,
	)
	return float(hash(mixed) & 0x7fffffff) / 2147483647.0
