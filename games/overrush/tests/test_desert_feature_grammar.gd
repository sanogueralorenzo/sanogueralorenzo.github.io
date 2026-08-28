extends SceneTree

const FeatureGrammar = preload("res://scripts/desert_feature_grammar.gd")
const TEST_SEED := 73013
const GRID_RADIUS := 16
const SAMPLE_SPACING := 8.0
const MAXIMUM_FEATURE_GRADE := 0.43
const REPRESENTATIVE_SEEDS := [73013, 89173, 41777, 94631]
const PROFILE_GRID_RADIUS := 10
const MINIMUM_CHECKED_PROFILES_PER_KIND := 8
const MINIMUM_OUTWARD_ALIGNMENT := 0.92
const KICKER_NORMAL_SAMPLE_STEP := 6.0
const MAXIMUM_KICKER_NORMAL_CHANGE_DEGREES := 6.0

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

	var representative_maximum_grade := 0.0
	for representative_seed in REPRESENTATIVE_SEEDS:
		representative_maximum_grade = maxf(
			representative_maximum_grade,
			_validate_directional_profiles(representative_seed),
		)
	_expect(
		representative_maximum_grade <= MAXIMUM_FEATURE_GRADE,
		"Representative directional profiles create an abrupt %.3f local grade."
		% representative_maximum_grade,
	)

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
			"Desert feature grammar passed — all five feature families face outward across four seeds, directional profiles retain a %.3f max grade, %.1f to %.1f m relief, bounded cache."
			% [maxf(maximum_grade, representative_maximum_grade), minimum_height, maximum_height]
		)
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _validate_directional_profiles(world_seed: int) -> float:
	var grammar := FeatureGrammar.new()
	grammar.configure(world_seed)
	var checked_counts := {
		FeatureGrammar.BOWL: 0,
		FeatureGrammar.RIDGE: 0,
		FeatureGrammar.KICKER: 0,
		FeatureGrammar.SPLIT_LINE: 0,
	}
	var maximum_grade := 0.0
	for z_coord in range(-PROFILE_GRID_RADIUS, PROFILE_GRID_RADIUS + 1):
		for x_coord in range(-PROFILE_GRID_RADIUS, PROFILE_GRID_RADIUS + 1):
			var coord := Vector2i(x_coord, z_coord)
			var descriptor: Dictionary = grammar._get_descriptor(coord)
			var kind: StringName = descriptor.kind
			if kind == FeatureGrammar.OPEN_SAND:
				continue
			var center: Vector2 = descriptor.center
			var axis := Vector2.from_angle(float(descriptor.angle))
			if center.length_squared() > 1.0:
				_expect(
					axis.dot(center.normalized()) >= MINIMUM_OUTWARD_ALIGNMENT,
					"Seed %d feature %s at %s does not face its outward fall line."
					% [world_seed, kind, str(coord)],
				)
			if int(checked_counts[kind]) >= MINIMUM_CHECKED_PROFILES_PER_KIND:
				continue
			checked_counts[kind] = int(checked_counts[kind]) + 1
			_validate_profile_shape(grammar, descriptor, world_seed, coord)
			maximum_grade = maxf(maximum_grade, _measure_profile_grade(grammar, descriptor))
	for kind in checked_counts:
		_expect(
			int(checked_counts[kind]) >= MINIMUM_CHECKED_PROFILES_PER_KIND,
			"Seed %d exposes too few %s profiles for directional validation: %d."
			% [world_seed, kind, int(checked_counts[kind])],
		)
	_expect(
		grammar.get_cached_descriptor_count() <= FeatureGrammar.CACHE_LIMIT,
		"Seed %d exceeded bounded descriptor residency during profile validation." % world_seed,
	)
	return maximum_grade


func _validate_profile_shape(
	grammar: RefCounted,
	descriptor: Dictionary,
	world_seed: int,
	coord: Vector2i,
) -> void:
	var kind: StringName = descriptor.kind
	var context := "Seed %d %s at %s" % [world_seed, kind, str(coord)]
	match kind:
		FeatureGrammar.BOWL:
			var center := _sample_profile(grammar, descriptor, 0.0, 0.0)
			var uphill_transition := _sample_profile(grammar, descriptor, -125.0, 0.0)
			var downhill_transition := _sample_profile(grammar, descriptor, 125.0, 0.0)
			var shoulder := _sample_profile(grammar, descriptor, 0.0, 128.0)
			_expect(center <= -7.0, "%s lacks a meaningful catch basin." % context)
			_expect(
				downhill_transition <= uphill_transition - 0.75,
				"%s should open into a longer, smoother downhill transition." % context,
			)
			_expect(absf(shoulder) <= 0.15, "%s does not return cleanly to its side shoulder." % context)
		FeatureGrammar.RIDGE:
			var crest := _sample_profile(grammar, descriptor, 0.0, 0.0)
			var uphill_spine := _sample_profile(grammar, descriptor, -140.0, 0.0)
			var downhill_spine := _sample_profile(grammar, descriptor, 140.0, 0.0)
			var side_route := _sample_profile(grammar, descriptor, 0.0, 78.0)
			_expect(crest >= 7.0, "%s lacks a readable longitudinal crest." % context)
			_expect(
				downhill_spine >= uphill_spine + 1.0,
				"%s should carry its spine farther down the fall line." % context,
			)
			_expect(absf(side_route) <= 0.15, "%s blocks the intended alternate side route." % context)
		FeatureGrammar.KICKER:
			var entry := _sample_profile(grammar, descriptor, -104.0, 0.0)
			var approach := _sample_profile(grammar, descriptor, -52.0, 0.0)
			var lip := _sample_profile(grammar, descriptor, FeatureGrammar.KICKER_LIP_ALONG, 0.0)
			var early_catch := _sample_profile(grammar, descriptor, 60.0, 0.0)
			var late_catch := _sample_profile(grammar, descriptor, 140.0, 0.0)
			var runout := _sample_profile(grammar, descriptor, FeatureGrammar.KICKER_RUNOUT_END + 8.0, 0.0)
			var lip_grade := absf(
				_sample_profile(grammar, descriptor, FeatureGrammar.KICKER_LIP_ALONG + 3.0, 0.0)
				- _sample_profile(grammar, descriptor, FeatureGrammar.KICKER_LIP_ALONG - 3.0, 0.0)
			) / 6.0
			var runout_grade := absf(
				_sample_profile(grammar, descriptor, FeatureGrammar.KICKER_RUNOUT_END + 3.0, 0.0)
				- _sample_profile(grammar, descriptor, FeatureGrammar.KICKER_RUNOUT_END - 3.0, 0.0)
			) / 6.0
			_expect(
				entry >= -0.01 and entry < approach and approach < lip,
				"%s needs a progressive uphill approach into its lip." % context,
			)
			_expect(
				early_catch < lip
					and late_catch < early_catch
					and late_catch >= float(descriptor.amplitude) * 0.09
					and absf(runout) <= 0.15,
				"%s lacks a long, usable downhill catch and clean runout." % context,
			)
			_expect(
				lip_grade <= 0.02 and runout_grade <= 0.02,
				"%s should enter and leave its catch with a near-zero derivative (%.3f, %.3f)."
				% [context, lip_grade, runout_grade],
			)
			var maximum_normal_change := _measure_kicker_normal_change(grammar, descriptor)
			_expect(
				maximum_normal_change <= MAXIMUM_KICKER_NORMAL_CHANGE_DEGREES,
				"%s changes its board-scale normal by %.2f degrees across 6 m."
				% [context, maximum_normal_change],
			)
		FeatureGrammar.SPLIT_LINE:
			var center_route := _sample_profile(grammar, descriptor, 0.0, 0.0)
			var left_marker := _sample_profile(grammar, descriptor, 0.0, -46.0)
			var right_marker := _sample_profile(grammar, descriptor, 0.0, 46.0)
			var uphill_marker := _sample_profile(grammar, descriptor, -140.0, 46.0)
			var downhill_marker := _sample_profile(grammar, descriptor, 140.0, 46.0)
			_expect(
				minf(left_marker, right_marker) >= center_route + 4.0,
				"%s should preserve a readable center route between two markers." % context,
			)
			_expect(
				downhill_marker >= uphill_marker + 1.0,
				"%s should remain legible farther along the downhill exit." % context,
			)


func _measure_profile_grade(grammar: RefCounted, descriptor: Dictionary) -> float:
	var maximum_grade := 0.0
	var step := 8.0
	for along_index in range(-27, 28):
		var along := float(along_index) * step
		for across_index in range(-16, 17):
			var across := float(across_index) * step
			var height := _sample_profile(grammar, descriptor, along, across)
			var along_height := _sample_profile(grammar, descriptor, along + step, across)
			var across_height := _sample_profile(grammar, descriptor, along, across + step)
			var gradient := Vector2(along_height - height, across_height - height) / step
			maximum_grade = maxf(maximum_grade, gradient.length())
	return maximum_grade


func _measure_kicker_normal_change(grammar: RefCounted, descriptor: Dictionary) -> float:
	var maximum_change := 0.0
	var step := KICKER_NORMAL_SAMPLE_STEP
	for along in range(-134, 188, int(step)):
		for across in range(-72, 73, int(step)):
			var normal := _sample_profile_normal(grammar, descriptor, float(along), float(across), step)
			var next_along := _sample_profile_normal(grammar, descriptor, float(along) + step, float(across), step)
			var next_across := _sample_profile_normal(grammar, descriptor, float(along), float(across) + step, step)
			maximum_change = maxf(maximum_change, rad_to_deg(normal.angle_to(next_along)))
			maximum_change = maxf(maximum_change, rad_to_deg(normal.angle_to(next_across)))
	return maximum_change


func _sample_profile_normal(
	grammar: RefCounted,
	descriptor: Dictionary,
	along: float,
	across: float,
	step: float,
) -> Vector3:
	var half_step := step * 0.5
	var along_grade := (
		_sample_profile(grammar, descriptor, along + half_step, across)
		- _sample_profile(grammar, descriptor, along - half_step, across)
	) / step
	var across_grade := (
		_sample_profile(grammar, descriptor, along, across + half_step)
		- _sample_profile(grammar, descriptor, along, across - half_step)
	) / step
	return Vector3(-along_grade, 1.0, -across_grade).normalized()


func _sample_profile(
	grammar: RefCounted,
	descriptor: Dictionary,
	along: float,
	across: float,
) -> float:
	var axis := Vector2.from_angle(float(descriptor.angle))
	var side := Vector2(-axis.y, axis.x)
	var point: Vector2 = descriptor.center + axis * along + side * across
	return grammar.sample_height_offset(point.x, point.y)
