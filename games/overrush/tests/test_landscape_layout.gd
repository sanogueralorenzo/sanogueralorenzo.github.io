extends SceneTree

const TEST_SEED := 73013
const SAMPLE_RADIUS := 12000.0
const OPENING_RADIUS := 1200.0
const OPENING_SEEDS := [94631, 41777, 73013, 89173, 1001, 2002, 3003, 4004]

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
	for opening_seed in OPENING_SEEDS:
		var opening_layout := LandscapeLayout.new()
		opening_layout.configure(opening_seed)
		var opening_tree_count := 0
		var opening_rock_count := 0
		for y in range(-60, 61):
			for x in range(-60, 61):
				var tree_cell := Vector2i(x, y)
				if (
					opening_layout.get_tree_position(tree_cell).length() <= OPENING_RADIUS
					and opening_layout.has_tree(tree_cell)
				):
					opening_tree_count += 1
		for y in range(-19, 20):
			for x in range(-19, 20):
				var rock_cell := Vector2i(x, y)
				if (
					opening_layout.get_rock_position(rock_cell).length() <= OPENING_RADIUS
					and opening_layout.has_rock(rock_cell)
				):
					opening_rock_count += 1
		var forest_headings := 0
		var dune_headings := 0
		for heading_index in range(16):
			var heading := Vector2.from_angle(TAU * float(heading_index) / 16.0)
			var forest_samples := 0
			var dune_samples := 0
			for distance in [500.0, 700.0, 900.0, 1100.0]:
				var grass := opening_layout.get_grass_weight(heading * distance)
				if grass >= 0.9:
					forest_samples += 1
				if grass <= 0.1:
					dune_samples += 1
			if forest_samples >= 3:
				forest_headings += 1
			if dune_samples >= 3:
				dune_headings += 1
		_expect(
			opening_tree_count >= 1000 and opening_tree_count <= 2800,
			"Seed %d should offer consequential but bounded opening forests: %d trees."
			% [opening_seed, opening_tree_count],
		)
		_expect(
			opening_rock_count >= 90,
			"Seed %d has too few opening rock decisions: %d."
			% [opening_seed, opening_rock_count],
		)
		_expect(
			forest_headings >= 4 and dune_headings >= 3,
			"Seed %d must offer both wooded and open opening choices: %d forest, %d dune headings."
			% [opening_seed, forest_headings, dune_headings],
		)

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
	_expect(tree_count >= 5500 and tree_count <= 10500, "Forest density should create consequential slalom sections without becoming continuous walls: %d trees." % tree_count)

	var rock_count := 0
	var smallest_rock := INF
	var largest_rock := 0.0
	for y in range(-50, 51):
		for x in range(-50, 51):
			var cell := Vector2i(x, y)
			if not layout.has_rock(cell):
				continue
			rock_count += 1
			var position := layout.get_rock_position(cell)
			var radius := layout.get_rock_radius(cell)
			_expect(position.length() >= LandscapeLayout.ROCK_SUMMIT_CLEAR_RADIUS, "Rock fields must leave the summit drop-in open.")
			smallest_rock = minf(smallest_rock, radius)
			largest_rock = maxf(largest_rock, radius)
	_expect(rock_count >= 300 and rock_count <= 2200, "Rock fields should be frequent hazards with open clusters between them: %d rocks." % rock_count)
	_expect(smallest_rock <= 1.5 and largest_rock >= 3.7, "Rock silhouettes need meaningful scale variation.")

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
		print("Landscape layout passed — every heading crosses dunes and forest, %.3f max blend step, %d trees, %d rocks, %d separated ruins." % [maximum_step, tree_count, rock_count, ruin_coords.size()])
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
