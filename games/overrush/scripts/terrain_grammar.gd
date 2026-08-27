extends RefCounted

const BROAD_VALLEY := "broad_valley"
const BANKED_TURN := "banked_turn"
const CRUISE := "cruise"
const LAUNCH := "launch"
const LANDING := "landing"
const NARROW_PASS := "narrow_pass"
const ALTERNATE := "alternate"

const REQUIRED_FEATURES := [BROAD_VALLEY, BANKED_TURN, LAUNCH, LANDING, NARROW_PASS]
const SAMPLE_SPACING := 18.0
const ROUTE_TEMPLATES := [
	[BROAD_VALLEY, BANKED_TURN, CRUISE, LAUNCH, LANDING, NARROW_PASS, BANKED_TURN],
	[BROAD_VALLEY, NARROW_PASS, BANKED_TURN, LAUNCH, LANDING, CRUISE, BANKED_TURN],
	[BROAD_VALLEY, BANKED_TURN, NARROW_PASS, CRUISE, LAUNCH, LANDING, BANKED_TURN],
]
const FEATURE_LENGTHS := {
	BROAD_VALLEY: 245.0,
	BANKED_TURN: 215.0,
	CRUISE: 175.0,
	LAUNCH: 150.0,
	LANDING: 220.0,
	NARROW_PASS: 185.0,
}
const FEATURE_WIDTHS := {
	BROAD_VALLEY: 270.0,
	BANKED_TURN: 180.0,
	CRUISE: 215.0,
	LAUNCH: 155.0,
	LANDING: 240.0,
	NARROW_PASS: 82.0,
	ALTERNATE: 125.0,
}

var seed: int
var map_size: float
var route_length: float
var region_breaks := Vector2(0.32, 0.66)
var palette_phase: float
var sections: Array[Dictionary] = []
var primary_samples: Array[Dictionary] = []
var alternate_samples: Array[Dictionary] = []
var has_alternate_route := false

var _rng := RandomNumberGenerator.new()
var _broad_noise := FastNoiseLite.new()
var _ridge_noise := FastNoiseLite.new()
var _detail_noise := FastNoiseLite.new()
var _route_noise := FastNoiseLite.new()


func configure(seed_value: int, size: float) -> void:
	seed = seed_value
	map_size = size
	_rng.seed = seed
	_configure_noise()
	region_breaks = Vector2(_rng.randf_range(0.28, 0.34), _rng.randf_range(0.63, 0.70))
	palette_phase = _rng.randf_range(-50.0, 50.0)
	_generate_route_graph()


func sample_height(x: float, z: float) -> float:
	var terrain_height := _sample_base_height(x, z)
	var closest := get_closest_route_info(x, z)
	if closest.is_empty():
		return terrain_height

	var sample: Dictionary = closest.sample
	var distance: float = closest.distance
	var signed_distance: float = closest.signed_distance
	var width: float = sample.width
	var normalized_distance := distance / maxf(width, 1.0)
	var influence := 1.0 - smoothstep(0.48, 1.28, normalized_distance)
	var route_height: float = sample.position.y + signed_distance * sample.bank
	var bowl_depth := _feature_bowl_depth(sample.feature)
	route_height += minf(normalized_distance * normalized_distance * bowl_depth, bowl_depth * 1.8)
	terrain_height = lerpf(terrain_height, route_height, influence)

	if sample.feature == NARROW_PASS:
		var wall_band := smoothstep(0.46, 0.92, normalized_distance)
		wall_band *= 1.0 - smoothstep(0.92, 1.75, normalized_distance)
		terrain_height += wall_band * 58.0

	var start_blend := smoothstep(10.0, 58.0, Vector2(x, z).length())
	return lerpf(0.0, terrain_height, start_blend)


func get_spawn_position() -> Vector3:
	return Vector3(0.0, sample_height(0.0, 0.0) + 3.5, 0.0)


func get_closest_route_info(x: float, z: float) -> Dictionary:
	var best_sample: Dictionary = {}
	var best_distance_squared := INF
	for sample in primary_samples:
		var position: Vector3 = sample.position
		var distance_squared := Vector2(x - position.x, z - position.z).length_squared()
		if distance_squared < best_distance_squared:
			best_distance_squared = distance_squared
			best_sample = sample
	for sample in alternate_samples:
		var position: Vector3 = sample.position
		var distance_squared := Vector2(x - position.x, z - position.z).length_squared()
		if distance_squared < best_distance_squared:
			best_distance_squared = distance_squared
			best_sample = sample
	if best_sample.is_empty():
		return {}

	var position: Vector3 = best_sample.position
	var tangent: Vector3 = best_sample.tangent
	var lateral := Vector2(-tangent.z, tangent.x).normalized()
	var offset := Vector2(x - position.x, z - position.z)
	return {
		"sample": best_sample,
		"distance": sqrt(best_distance_squared),
		"signed_distance": offset.dot(lateral),
	}


func get_route_clearance(x: float, z: float) -> float:
	var closest := get_closest_route_info(x, z)
	if closest.is_empty():
		return INF
	var sample: Dictionary = closest.sample
	return closest.distance / maxf(sample.width, 1.0)


func get_primary_sample_at(progress: float) -> Dictionary:
	if primary_samples.is_empty():
		return {}
	var index := clampi(roundi(progress * (primary_samples.size() - 1)), 0, primary_samples.size() - 1)
	return primary_samples[index]


func get_region_name(z: float) -> String:
	var progress := clampf(-z / maxf(route_length, 1.0), 0.0, 1.0)
	if progress < region_breaks.x:
		return "VERDANT REACH"
	if progress < region_breaks.y:
		return "EMBER BASIN"
	return "PRISM HIGHLANDS"


func get_layout_fingerprint() -> String:
	var feature_order: Array[String] = []
	var lateral_signature: Array[String] = []
	for section in sections:
		feature_order.append(section.feature)
		lateral_signature.append(str(roundi(section.end.x / 25.0)))
	return "%s|%s|alt:%s" % [
		",".join(feature_order),
		",".join(lateral_signature),
		str(has_alternate_route),
	]


func validate_layout() -> PackedStringArray:
	var errors := PackedStringArray()
	if primary_samples.size() < 60:
		errors.append("primary route has fewer than 60 samples")
	for feature in REQUIRED_FEATURES:
		if not _has_feature(feature):
			errors.append("missing required feature: %s" % feature)
	_validate_feature_shapes(errors)
	if region_breaks.x >= region_breaks.y - 0.2:
		errors.append("terrain regions do not have enough separation")

	var max_route_slope := 0.0
	var max_turn := 0.0
	var min_width := INF
	for index in range(primary_samples.size()):
		var sample: Dictionary = primary_samples[index]
		var position: Vector3 = sample.position
		min_width = minf(min_width, sample.width)
		var height := sample_height(position.x, position.z)
		if is_nan(height) or is_inf(height):
			errors.append("non-finite height on primary route at sample %d" % index)
			break
		if absf(height - position.y) > 3.0:
			errors.append("route center deviates from authored height at sample %d" % index)
			break
		if index > 0:
			var previous: Vector3 = primary_samples[index - 1].position
			if position.z > previous.z + 0.01:
				errors.append("primary route reverses direction at sample %d" % index)
				break
			var horizontal_distance := Vector2(position.x - previous.x, position.z - previous.z).length()
			if horizontal_distance > 0.01:
				max_route_slope = maxf(max_route_slope, absf(position.y - previous.y) / horizontal_distance)
		if index + 16 < primary_samples.size():
			var future: Dictionary = primary_samples[index + 16]
			max_turn = maxf(max_turn, sample.tangent.angle_to(future.tangent))
	if max_route_slope > 0.48:
		errors.append("primary route exceeds safe slope: %.3f" % max_route_slope)
	if rad_to_deg(max_turn) > 65.0:
		errors.append("route turns more than 65 degrees inside a 200–400 m sightline")
	if min_width < 78.0:
		errors.append("route clearance is narrower than 78 m")

	var half_size := map_size * 0.5
	for z_index in range(25):
		var z := lerpf(-half_size, half_size, z_index / 24.0)
		for x_index in range(25):
			var x := lerpf(-half_size, half_size, x_index / 24.0)
			var height := sample_height(x, z)
			if is_nan(height) or is_inf(height) or absf(height) > 800.0:
				errors.append("invalid terrain height at grid sample (%d, %d)" % [x_index, z_index])
				return errors
	return errors


func _validate_feature_shapes(errors: PackedStringArray) -> void:
	var broad_samples := _samples_for_feature(BROAD_VALLEY)
	var bank_samples := _samples_for_feature(BANKED_TURN)
	var launch_samples := _samples_for_feature(LAUNCH)
	var landing_samples := _samples_for_feature(LANDING)
	var narrow_samples := _samples_for_feature(NARROW_PASS)
	if broad_samples.is_empty() or broad_samples[0].width < 240.0:
		errors.append("broad valley is not at least 240 m wide")
	var maximum_bank := 0.0
	for sample in bank_samples:
		maximum_bank = maxf(maximum_bank, absf(sample.bank))
	if maximum_bank < 0.12:
		errors.append("banked turn does not reach a 0.12 cross-slope")
	if launch_samples.size() < 2:
		errors.append("launch hill has insufficient samples")
	else:
		var launch_rise: float = launch_samples[-1].position.y - launch_samples[0].position.y
		if launch_rise < 18.0:
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
	if has_alternate_route:
		if alternate_samples.size() < 8:
			errors.append("alternate route has insufficient samples")
		else:
			var first_branch: Vector3 = alternate_samples[0].position
			var last_branch: Vector3 = alternate_samples[-1].position
			if _distance_to_primary(first_branch) > 1.0 or _distance_to_primary(last_branch) > 1.0:
				errors.append("alternate route does not merge back into the primary graph")


func get_validation_metrics() -> Dictionary:
	var max_route_slope := 0.0
	var max_turn := 0.0
	for index in range(1, primary_samples.size()):
		var previous: Vector3 = primary_samples[index - 1].position
		var current: Vector3 = primary_samples[index].position
		var distance := Vector2(current.x - previous.x, current.z - previous.z).length()
		if distance > 0.01:
			max_route_slope = maxf(max_route_slope, absf(current.y - previous.y) / distance)
		if index + 16 < primary_samples.size():
			max_turn = maxf(max_turn, primary_samples[index].tangent.angle_to(primary_samples[index + 16].tangent))
	return {
		"max_route_slope": max_route_slope,
		"max_sightline_turn_degrees": rad_to_deg(max_turn),
		"sample_count": primary_samples.size(),
		"has_alternate": has_alternate_route,
	}


func _configure_noise() -> void:
	_broad_noise.seed = _rng.randi()
	_broad_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_broad_noise.frequency = 0.00105
	_broad_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_broad_noise.fractal_octaves = 5
	_broad_noise.fractal_gain = 0.48

	_ridge_noise.seed = _rng.randi()
	_ridge_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_ridge_noise.frequency = 0.0018
	_ridge_noise.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_ridge_noise.fractal_octaves = 4
	_ridge_noise.fractal_gain = 0.52

	_detail_noise.seed = _rng.randi()
	_detail_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_detail_noise.frequency = 0.007
	_detail_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_detail_noise.fractal_octaves = 3
	_detail_noise.fractal_gain = 0.42

	_route_noise.seed = _rng.randi()
	_route_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_route_noise.frequency = 0.0018
	_route_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_route_noise.fractal_octaves = 3


func _generate_route_graph() -> void:
	sections.clear()
	primary_samples.clear()
	alternate_samples.clear()
	var template: Array = ROUTE_TEMPLATES[_rng.randi_range(0, ROUTE_TEMPLATES.size() - 1)]
	var current := Vector3.ZERO
	var turn_direction := -1.0 if _rng.randf() < 0.5 else 1.0

	for section_index in range(template.size()):
		var feature: String = template[section_index]
		var length: float = FEATURE_LENGTHS[feature] * _rng.randf_range(0.94, 1.06)
		var end := current
		end.z -= length
		var lateral_change := _rng.randf_range(-34.0, 34.0)
		if feature == BANKED_TURN:
			lateral_change = turn_direction * _rng.randf_range(135.0, 195.0)
			turn_direction *= -1.0
		end.x = clampf(current.x + lateral_change, -455.0, 455.0)
		if feature == LAUNCH:
			end.y = current.y + _rng.randf_range(21.0, 27.0)
		elif feature == LANDING:
			end.y = current.y - _rng.randf_range(30.0, 38.0)
		else:
			var authored_drift := _route_noise.get_noise_1d(end.z) * 18.0
			end.y = lerpf(current.y, authored_drift, 0.44)
		var section := {
			"index": section_index,
			"feature": feature,
			"start": current,
			"end": end,
			"length": length,
			"width": FEATURE_WIDTHS[feature],
			"turn_direction": signf(lateral_change),
		}
		sections.append(section)
		_sample_section(section)
		current = end

	route_length = absf(current.z)
	_finalize_route_samples(primary_samples)
	has_alternate_route = _rng.randf() < 0.56
	if has_alternate_route:
		_generate_alternate_edge()


func _sample_section(section: Dictionary) -> void:
	var length: float = section.length
	var sample_count := maxi(2, ceili(length / SAMPLE_SPACING))
	var start: Vector3 = section.start
	var end: Vector3 = section.end
	var feature: String = section.feature
	for sample_index in range(sample_count):
		if not primary_samples.is_empty() and sample_index == 0:
			continue
		var t := sample_index / float(sample_count)
		var eased := t * t * (3.0 - 2.0 * t)
		var position := start.lerp(end, eased)
		position.z = lerpf(start.z, end.z, t)
		if feature == BANKED_TURN:
			position.x += sin(t * PI) * section.turn_direction * 28.0
			position.y += sin(t * PI) * 4.0
		elif feature == LAUNCH:
			position.y = start.y + (end.y - start.y) * pow(t, 1.65)
		elif feature == LANDING:
			position.y = end.y + (start.y - end.y) * pow(1.0 - t, 2.25)
		else:
			position.y += _route_noise.get_noise_1d(position.z) * 3.5
		var bank := 0.0
		if feature == BANKED_TURN:
			bank = section.turn_direction * sin(t * PI) * 0.16
		primary_samples.append({
			"position": position,
			"width": section.width,
			"bank": bank,
			"feature": feature,
			"section_index": section.index,
			"tangent": Vector3.FORWARD,
			"progress": 0.0,
		})
	var final_bank := 0.0
	primary_samples.append({
		"position": end,
		"width": section.width,
		"bank": final_bank,
		"feature": feature,
		"section_index": section.index,
		"tangent": Vector3.FORWARD,
		"progress": 0.0,
	})


func _generate_alternate_edge() -> void:
	var start_sample := get_primary_sample_at(_rng.randf_range(0.31, 0.39))
	var end_sample := get_primary_sample_at(_rng.randf_range(0.59, 0.68))
	var start: Vector3 = start_sample.position
	var end: Vector3 = end_sample.position
	var side := -1.0 if _rng.randf() < 0.5 else 1.0
	if absf((start.x + end.x) * 0.5 + side * 230.0) > 500.0:
		side *= -1.0
	var branch_length := Vector2(end.x - start.x, end.z - start.z).length()
	var count := maxi(8, ceili(branch_length / SAMPLE_SPACING))
	var height_offset := _rng.randf_range(-12.0, 14.0)
	for index in range(count + 1):
		var t := index / float(count)
		var eased := t * t * (3.0 - 2.0 * t)
		var position := start.lerp(end, eased)
		position.x += side * sin(t * PI) * _rng.randf_range(205.0, 245.0)
		position.y += sin(t * PI) * height_offset
		alternate_samples.append({
			"position": position,
			"width": FEATURE_WIDTHS[ALTERNATE],
			"bank": side * sin(t * PI) * 0.09,
			"feature": ALTERNATE,
			"section_index": -1,
			"tangent": Vector3.FORWARD,
			"progress": lerpf(start_sample.progress, end_sample.progress, t),
		})
	_finalize_route_samples(alternate_samples)


func _finalize_route_samples(samples: Array[Dictionary]) -> void:
	for index in range(samples.size()):
		var previous: Vector3 = samples[maxi(0, index - 1)].position
		var next: Vector3 = samples[mini(samples.size() - 1, index + 1)].position
		var tangent := (next - previous).normalized()
		if tangent.length_squared() < 0.1:
			tangent = Vector3.FORWARD
		samples[index].tangent = tangent
		if samples == primary_samples:
			samples[index].progress = clampf(-samples[index].position.z / maxf(route_length, 1.0), 0.0, 1.0)


func _sample_base_height(x: float, z: float) -> float:
	var progress := clampf(-z / maxf(route_length, 1.0), 0.0, 1.0)
	var weights := _region_weights(progress)
	var broad := _broad_noise.get_noise_2d(x, z)
	var ridge := _ridge_noise.get_noise_2d(x, z)
	var detail := _detail_noise.get_noise_2d(x, z)
	var verdant := broad * 78.0 + ridge * absf(ridge) * 42.0 + detail * 8.0
	var ember := broad * 104.0 + ridge * absf(ridge) * 138.0 + detail * 13.0 + 12.0
	var prism := broad * 128.0 + absf(ridge) * 92.0 + detail * 17.0 + 24.0
	return verdant * weights.x + ember * weights.y + prism * weights.z


func _region_weights(progress: float) -> Vector3:
	var first := 1.0 - smoothstep(region_breaks.x - 0.075, region_breaks.x + 0.075, progress)
	var third := smoothstep(region_breaks.y - 0.075, region_breaks.y + 0.075, progress)
	var second := maxf(0.0, 1.0 - first - third)
	return Vector3(first, second, third)


func _feature_bowl_depth(feature: String) -> float:
	match feature:
		BROAD_VALLEY:
			return 24.0
		BANKED_TURN:
			return 10.0
		LAUNCH:
			return 7.0
		LANDING:
			return 5.0
		NARROW_PASS:
			return 14.0
		ALTERNATE:
			return 8.0
		_:
			return 11.0


func _has_feature(feature: String) -> bool:
	for section in sections:
		if section.feature == feature:
			return true
	return false


func _samples_for_feature(feature: String) -> Array[Dictionary]:
	var matching: Array[Dictionary] = []
	for sample in primary_samples:
		if sample.feature == feature:
			matching.append(sample)
	return matching


func _distance_to_primary(position: Vector3) -> float:
	var nearest := INF
	for sample in primary_samples:
		var route_position: Vector3 = sample.position
		nearest = minf(nearest, Vector2(position.x - route_position.x, position.z - route_position.z).length())
	return nearest
