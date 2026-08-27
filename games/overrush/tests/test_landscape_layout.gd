extends SceneTree

const TEST_SEED := 73013
const SAMPLE_RADIUS := 12000.0

var _failures: Array[String] = []


func _init() -> void:
	var layout := LandscapeLayout.new()
	var duplicate := LandscapeLayout.new()
	var alternate := LandscapeLayout.new()
	layout.configure(TEST_SEED)
	duplicate.configure(TEST_SEED)
	alternate.configure(TEST_SEED + 1)

	var seed_difference := 0.0
	var maximum_step := 0.0
	for direction_index in range(16):
		var angle := TAU * float(direction_index) / 16.0
		var direction := Vector2(cos(angle), sin(angle))
		var minimum_grass := 1.0
		var maximum_grass := 0.0
		var previous := layout.get_grass_weight(Vector2.ZERO)
		for distance in range(50, int(SAMPLE_RADIUS) + 1, 50):
			var position := direction * distance
			var grass := layout.get_grass_weight(position)
			minimum_grass = minf(minimum_grass, grass)
			maximum_grass = maxf(maximum_grass, grass)
			maximum_step = maxf(maximum_step, absf(grass - previous))
			seed_difference += absf(grass - alternate.get_grass_weight(position))
			_expect(is_equal_approx(grass, duplicate.get_grass_weight(position)), "Equal seeds must produce equal biome weights.")
			previous = grass
		_expect(minimum_grass <= 0.05, "Direction %d never reaches a clear dune region." % direction_index)
		_expect(maximum_grass >= 0.95, "Direction %d never reaches a clear grass/forest region." % direction_index)
	_expect(maximum_step <= 0.34, "Biome blending changes too abruptly over 50 m: %.3f." % maximum_step)
	_expect(seed_difference > 100.0, "Different seeds should materially change biome placement.")

	var tree_count := 0
	for y in range(-80, 81):
		for x in range(-80, 81):
			var cell := Vector2i(x, y)
			if not layout.has_tree(cell):
				continue
			tree_count += 1
			var position := layout.get_tree_position(cell)
			_expect(position.length() >= LandscapeLayout.TREE_SUMMIT_CLEAR_RADIUS, "Trees must leave the summit drop-in open.")
			_expect(layout.get_grass_weight(position) >= 0.58, "Trees must never appear in clear dune terrain.")
	_expect(tree_count >= 1200 and tree_count <= 3800, "Forest density should be substantial but line-readable: %d trees." % tree_count)

	var ruin_coords: Array[Vector2i] = []
	for y in range(-14, 15):
		for x in range(-14, 15):
			var coord := Vector2i(x, y)
			if not layout.has_ruin(coord, 384.0):
				continue
			ruin_coords.append(coord)
			_expect(Vector2(coord).length() * 384.0 >= LandscapeLayout.RUIN_MINIMUM_RADIUS, "Ruins must leave the summit open.")
			var center_offset := layout.get_ruin_center(coord, 384.0) - Vector2(coord) * 384.0
			_expect(maxf(absf(center_offset.x), absf(center_offset.y)) <= 70.0, "Ruins should remain safely inset from chunk seams.")
	for first in ruin_coords:
		for second in ruin_coords:
			if first == second:
				continue
			_expect(maxi(absi(first.x - second.x), absi(first.y - second.y)) > 1, "Ruin sites must not occupy neighboring chunks.")
	_expect(ruin_coords.size() >= 40 and ruin_coords.size() <= 120, "Ruins should remain sparse and memorable: %d sites." % ruin_coords.size())

	if _failures.is_empty():
		print("Landscape layout passed — every heading crosses dunes and forest, %.3f max blend step, %d trees, %d separated ruins." % [maximum_step, tree_count, ruin_coords.size()])
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
