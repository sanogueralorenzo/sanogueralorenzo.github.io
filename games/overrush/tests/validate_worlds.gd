extends SceneTree

const TerrainGrammar = preload("res://scripts/terrain_grammar.gd")
const FormationBuilder = preload("res://scripts/formation_builder.gd")
const SEED_COUNT := 20
const MAP_SIZE := 3200.0


func _init() -> void:
	call_deferred("_run_validation")


func _run_validation() -> void:
	var failures := PackedStringArray()
	var fingerprints := {}
	var alternate_count := 0
	var max_route_slope := 0.0
	var max_traversable_gradient := 0.0
	var max_sightline_turn := 0.0

	for index in range(SEED_COUNT):
		var seed := 41001 + index * 7919
		var grammar = TerrainGrammar.new()
		grammar.configure(seed, MAP_SIZE)
		var formation_builder = FormationBuilder.new()
		formation_builder.plan_layout(seed, grammar, MAP_SIZE)

		var seed_errors := grammar.validate_layout()
		seed_errors.append_array(formation_builder.validate_layout(grammar))
		var region_names := {
			grammar.get_region_name(-grammar.route_length * 0.12): true,
			grammar.get_region_name(-grammar.route_length * 0.50): true,
			grammar.get_region_name(-grammar.route_length * 0.88): true,
		}
		if region_names.size() != 3:
			seed_errors.append("seed does not expose all three terrain regions")

		var fingerprint := grammar.get_layout_fingerprint()
		if fingerprints.has(fingerprint):
			seed_errors.append("layout fingerprint repeats seed %d" % fingerprints[fingerprint])
		else:
			fingerprints[fingerprint] = seed
		if grammar.has_alternate_route:
			alternate_count += 1
		var metrics := grammar.get_validation_metrics()
		max_route_slope = maxf(max_route_slope, metrics.max_route_slope)
		max_traversable_gradient = maxf(max_traversable_gradient, metrics.max_traversable_gradient)
		max_sightline_turn = maxf(max_sightline_turn, metrics.max_sightline_turn_degrees)

		if seed_errors.is_empty():
			print(
				"PASS seed %d — samples %d, alternate %s, slope %.3f, corridor gradient %.3f, sightline turn %.1f°"
				% [
					seed,
					metrics.sample_count,
					str(metrics.has_alternate),
					metrics.max_route_slope,
					metrics.max_traversable_gradient,
					metrics.max_sightline_turn_degrees,
				]
			)
		else:
			for error in seed_errors:
				failures.append("seed %d: %s" % [seed, error])

	if alternate_count < 4 or alternate_count > 16:
		failures.append(
			"alternate routes are not occasional: %d of %d seeds generated one"
			% [alternate_count, SEED_COUNT]
		)
	if fingerprints.size() != SEED_COUNT:
		failures.append("only %d of %d layouts are structurally unique" % [fingerprints.size(), SEED_COUNT])

	if failures.is_empty():
		print(
			"VALIDATED %d SEEDS — %d unique layouts, %d alternates, max slope %.3f, max corridor gradient %.3f, max 200–400 m turn %.1f°"
			% [SEED_COUNT, fingerprints.size(), alternate_count, max_route_slope, max_traversable_gradient, max_sightline_turn]
		)
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		push_error("VALIDATION FAILED — %d issues across %d seeds" % [failures.size(), SEED_COUNT])
		quit(1)
