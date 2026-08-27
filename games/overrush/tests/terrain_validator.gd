class_name TerrainValidator
extends RefCounted

const RouteGenerator = preload("res://scripts/route_generator.gd")
const REQUIRED_FEATURES := [
	RouteGenerator.BROAD_VALLEY,
	RouteGenerator.BANKED_TURN,
	RouteGenerator.LAUNCH,
	RouteGenerator.LANDING,
	RouteGenerator.NARROW_PASS,
]
const MAX_ROUTE_SLOPE := 0.34
const MAX_TRAVERSABLE_GRADIENT := 0.65
const GRID_CHECK_RESOLUTION := 25
const GRADIENT_STEP := 10.0
const GRADIENT_LATERAL_FACTORS := [-1.05, -0.78, -0.52, -0.26, 0.0, 0.26, 0.52, 0.78, 1.05]


func validate(grammar) -> Dictionary:
	var errors := PackedStringArray()
	if grammar.primary_samples.size() < 60:
		errors.append("primary route has fewer than 60 samples")
	for feature in REQUIRED_FEATURES:
		if not _has_feature(grammar, feature):
			errors.append("missing required feature: %s" % feature)
	_validate_feature_shapes(grammar, errors)
	if grammar.region_breaks.x >= grammar.region_breaks.y - 0.2:
		errors.append("terrain regions do not have enough separation")

	var max_route_slope := 0.0
	var max_turn := 0.0
	var min_width := INF
	for index in range(grammar.primary_samples.size()):
		var sample: Dictionary = grammar.primary_samples[index]
		var position: Vector3 = sample.position
		min_width = minf(min_width, sample.width)
		var height: float = grammar.sample_height(position.x, position.z)
		if is_nan(height) or is_inf(height):
			errors.append("non-finite height on primary route at sample %d" % index)
			break
		if absf(height - position.y) > 3.0:
			errors.append("route center deviates from authored height at sample %d" % index)
			break
		if index > 0:
			var previous: Vector3 = grammar.primary_samples[index - 1].position
			if position.z > previous.z + 0.01:
				errors.append("primary route reverses direction at sample %d" % index)
				break
			var horizontal_distance := Vector2(position.x - previous.x, position.z - previous.z).length()
			if horizontal_distance > 0.01:
				max_route_slope = maxf(max_route_slope, absf(position.y - previous.y) / horizontal_distance)
		if index + 16 < grammar.primary_samples.size():
			var future: Dictionary = grammar.primary_samples[index + 16]
			max_turn = maxf(max_turn, sample.tangent.angle_to(future.tangent))

	var max_traversable_gradient := _get_max_traversable_gradient(grammar)
	if max_route_slope > MAX_ROUTE_SLOPE:
		errors.append("primary route exceeds safe slope: %.3f" % max_route_slope)
	if max_traversable_gradient > MAX_TRAVERSABLE_GRADIENT:
		errors.append("route corridor has an abrupt terrain gradient: %.3f" % max_traversable_gradient)
	if rad_to_deg(max_turn) > 65.0:
		errors.append("route turns more than 65 degrees inside a 200–400 m sightline")
	if min_width < 78.0:
		errors.append("route clearance is narrower than 78 m")
	_validate_height_grid(grammar, errors)

	return {
		"errors": errors,
		"metrics": {
			"max_route_slope": max_route_slope,
			"max_traversable_gradient": max_traversable_gradient,
			"max_sightline_turn_degrees": rad_to_deg(max_turn),
			"sample_count": grammar.primary_samples.size(),
			"has_alternate": grammar.has_alternate_route,
		},
	}


func _validate_feature_shapes(grammar, errors: PackedStringArray) -> void:
	var broad_samples := _samples_for_feature(grammar, RouteGenerator.BROAD_VALLEY)
	var bank_samples := _samples_for_feature(grammar, RouteGenerator.BANKED_TURN)
	var launch_samples := _samples_for_feature(grammar, RouteGenerator.LAUNCH)
	var landing_samples := _samples_for_feature(grammar, RouteGenerator.LANDING)
	var narrow_samples := _samples_for_feature(grammar, RouteGenerator.NARROW_PASS)
	if broad_samples.is_empty() or broad_samples[0].width < 240.0:
		errors.append("broad valley is not at least 240 m wide")
	var maximum_bank := 0.0
	for sample in bank_samples:
		maximum_bank = maxf(maximum_bank, absf(sample.bank))
	if maximum_bank < 0.12:
		errors.append("banked turn does not reach a 0.12 cross-slope")
	if launch_samples.size() < 2:
		errors.append("launch hill has insufficient samples")
	elif launch_samples[-1].position.y - launch_samples[0].position.y < 18.0:
		errors.append("launch hill rises less than 18 m")
	if landing_samples.size() < 3:
		errors.append("landing zone has insufficient samples")
	else:
		var landing_drop: float = landing_samples[0].position.y - landing_samples[-1].position.y
		var last: Vector3 = landing_samples[-1].position
		var previous: Vector3 = landing_samples[-2].position
		var terminal_distance := Vector2(last.x - previous.x, last.z - previous.z).length()
		var terminal_slope := absf(last.y - previous.y) / maxf(terminal_distance, 0.01)
		if landing_drop < 24.0:
			errors.append("landing zone drops less than 24 m after its launch")
		if terminal_slope > 0.12:
			errors.append("landing zone does not flatten smoothly at its exit")
	if narrow_samples.is_empty() or narrow_samples[0].width > 90.0:
		errors.append("narrow pass is wider than 90 m")
	if grammar.has_alternate_route:
		if grammar.alternate_samples.size() < 8:
			errors.append("alternate route has insufficient samples")
		else:
			var first_branch: Vector3 = grammar.alternate_samples[0].position
			var last_branch: Vector3 = grammar.alternate_samples[-1].position
			if _distance_to_primary(grammar, first_branch) > 1.0 or _distance_to_primary(grammar, last_branch) > 1.0:
				errors.append("alternate route does not merge back into the primary graph")


func _validate_height_grid(grammar, errors: PackedStringArray) -> void:
	var half_size: float = grammar.map_size * 0.5
	for z_index in range(GRID_CHECK_RESOLUTION):
		var z := lerpf(-half_size, half_size, z_index / float(GRID_CHECK_RESOLUTION - 1))
		for x_index in range(GRID_CHECK_RESOLUTION):
			var x := lerpf(-half_size, half_size, x_index / float(GRID_CHECK_RESOLUTION - 1))
			var height: float = grammar.sample_height(x, z)
			if is_nan(height) or is_inf(height) or absf(height) > 800.0:
				errors.append("invalid terrain height at grid sample (%d, %d)" % [x_index, z_index])
				return


func _get_max_traversable_gradient(grammar) -> float:
	var max_gradient := 0.0
	for sample in grammar.primary_samples:
		var position: Vector3 = sample.position
		var tangent: Vector3 = sample.tangent
		var lateral := Vector2(-tangent.z, tangent.x).normalized()
		for lateral_factor in GRADIENT_LATERAL_FACTORS:
			var x: float = position.x + lateral.x * sample.width * lateral_factor
			var z: float = position.z + lateral.y * sample.width * lateral_factor
			var x_gradient: float = (
				grammar.sample_height(x + GRADIENT_STEP, z) - grammar.sample_height(x - GRADIENT_STEP, z)
			) / (GRADIENT_STEP * 2.0)
			var z_gradient: float = (
				grammar.sample_height(x, z + GRADIENT_STEP) - grammar.sample_height(x, z - GRADIENT_STEP)
			) / (GRADIENT_STEP * 2.0)
			max_gradient = maxf(max_gradient, Vector2(x_gradient, z_gradient).length())
	return max_gradient


func _has_feature(grammar, feature: String) -> bool:
	for section in grammar.sections:
		if section.feature == feature:
			return true
	return false


func _samples_for_feature(grammar, feature: String) -> Array[Dictionary]:
	var matching: Array[Dictionary] = []
	for sample in grammar.primary_samples:
		if sample.feature == feature:
			matching.append(sample)
	return matching


func _distance_to_primary(grammar, position: Vector3) -> float:
	var nearest := INF
	for sample in grammar.primary_samples:
		var route_position: Vector3 = sample.position
		nearest = minf(nearest, Vector2(position.x - route_position.x, position.z - route_position.z).length())
	return nearest
