extends SceneTree

const FeatureGrammar = preload("res://scripts/desert_feature_grammar.gd")
const TEST_SEED := 73013
const GRID_RADIUS := 16
const SAMPLE_SPACING := 8.0
const MAXIMUM_FEATURE_GRADE := 0.43

var _failures: Array[String] = []


func _init() -> void:
	var grammar := FeatureGrammar.new()
	grammar.configure(TEST_SEED)
	var repeated := FeatureGrammar.new()
	repeated.configure(TEST_SEED)
	var alternate := FeatureGrammar.new()
	alternate.configure(TEST_SEED + 1)
	var counts := {
		FeatureGrammar.BOWL: 0,
		FeatureGrammar.RIDGE: 0,
		FeatureGrammar.KICKER: 0,
		FeatureGrammar.SPLIT_LINE: 0,
		FeatureGrammar.OPEN_SAND: 0,
	}
	var seed_difference_found := false
	for z_coord in range(-GRID_RADIUS, GRID_RADIUS + 1):
		for x_coord in range(-GRID_RADIUS, GRID_RADIUS + 1):
			var coord := Vector2i(x_coord, z_coord)
			var kind: StringName = grammar.get_feature_kind_for_cell(coord)
			counts[kind] += 1
			_expect(kind == repeated.get_feature_kind_for_cell(coord), "Equal seeds must produce equal feature identities.")
			if kind != alternate.get_feature_kind_for_cell(coord):
				seed_difference_found = true
	_expect(seed_difference_found, "Different seeds should change the macro-feature layout.")
	for kind in counts:
		_expect(counts[kind] >= 45, "Feature kind %s is underrepresented: %d cells." % [kind, counts[kind]])

	var maximum_grade := 0.0
	var maximum_height := -INF
	var minimum_height := INF
	for z_index in range(-256, 257):
		var z := z_index * SAMPLE_SPACING
		var previous_height := grammar.sample_height_offset(-256.0 * SAMPLE_SPACING, z)
		for x_index in range(-255, 257):
			var x := x_index * SAMPLE_SPACING
			var height := grammar.sample_height_offset(x, z)
			maximum_grade = maxf(maximum_grade, absf(height - previous_height) / SAMPLE_SPACING)
			maximum_height = maxf(maximum_height, height)
			minimum_height = minf(minimum_height, height)
			previous_height = height
	_expect(maximum_grade <= MAXIMUM_FEATURE_GRADE, "Feature grammar creates an abrupt %.3f local grade." % maximum_grade)
	_expect(maximum_height >= 9.0, "Positive ridges and kickers should create meaningful terrain relief.")
	_expect(minimum_height <= -9.0, "Bowls should create meaningful negative terrain relief.")

	for boundary_index in range(-8, 9):
		var boundary := (float(boundary_index) + 0.5) * FeatureGrammar.CELL_SIZE
		for cross_index in range(-8, 9):
			var cross := float(cross_index) * 31.0
			var horizontal_error := absf(
				grammar.sample_height_offset(boundary - 0.01, cross)
				- grammar.sample_height_offset(boundary + 0.01, cross)
			)
			var vertical_error := absf(
				grammar.sample_height_offset(cross, boundary - 0.01)
				- grammar.sample_height_offset(cross, boundary + 0.01)
			)
			_expect(horizontal_error <= 0.001 and vertical_error <= 0.001, "Feature influence must fade to zero at cell boundaries.")
	_expect(grammar.get_cached_descriptor_count() <= FeatureGrammar.CACHE_LIMIT, "The infinite feature cache must remain bounded.")

	if _failures.is_empty():
		print(
			"Desert feature grammar passed — all five feature families, %.3f max grade, %.1f to %.1f m relief, bounded cache."
			% [maximum_grade, minimum_height, maximum_height]
		)
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
