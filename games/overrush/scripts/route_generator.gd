class_name RouteGenerator
extends RefCounted

const BROAD_VALLEY := "broad_valley"
const BANKED_TURN := "banked_turn"
const CRUISE := "cruise"
const LAUNCH := "launch"
const LANDING := "landing"
const NARROW_PASS := "narrow_pass"
const ALTERNATE := "alternate"

const SAMPLE_SPACING := 18.0
const SECTION_LENGTH_VARIATION := Vector2(0.94, 1.06)
const ROUTE_LATERAL_DRIFT := 34.0
const BANKED_TURN_LATERAL_RANGE := Vector2(135.0, 195.0)
const ROUTE_LATERAL_LIMIT := 455.0
const LAUNCH_RISE_RANGE := Vector2(21.0, 27.0)
const LANDING_DROP_RANGE := Vector2(30.0, 38.0)
const ROUTE_HEIGHT_DRIFT := 18.0
const ROUTE_HEIGHT_BLEND := 0.44
const BANKED_TURN_BULGE := 28.0
const BANKED_TURN_RISE := 4.0
const BANKED_TURN_STRENGTH := 0.125
const ROUTE_DETAIL_HEIGHT := 3.5
const ALTERNATE_CHANCE := 0.56
const ALTERNATE_START_RANGE := Vector2(0.31, 0.39)
const ALTERNATE_END_RANGE := Vector2(0.59, 0.68)
const ALTERNATE_LATERAL_RANGE := Vector2(205.0, 245.0)
const ALTERNATE_HEIGHT_RANGE := Vector2(-12.0, 14.0)
const ALTERNATE_BANK_STRENGTH := 0.09
const PROPERTY_SMOOTH_RADIUS := 8
const MINIMUM_BLEND_WIDTH := 180.0

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

var route_length := 0.0
var sections: Array[Dictionary] = []
var primary_samples: Array[Dictionary] = []
var alternate_samples: Array[Dictionary] = []
var has_alternate_route := false

var _rng: RandomNumberGenerator
var _route_noise: FastNoiseLite


func generate(rng: RandomNumberGenerator, route_noise: FastNoiseLite) -> void:
	_rng = rng
	_route_noise = route_noise
	sections.clear()
	primary_samples.clear()
	alternate_samples.clear()
	var template: Array = ROUTE_TEMPLATES[_rng.randi_range(0, ROUTE_TEMPLATES.size() - 1)]
	var current := Vector3.ZERO
	var turn_direction := -1.0 if _rng.randf() < 0.5 else 1.0

	for section_index in range(template.size()):
		var feature: String = template[section_index]
		var length: float = FEATURE_LENGTHS[feature] * _rng.randf_range(
			SECTION_LENGTH_VARIATION.x,
			SECTION_LENGTH_VARIATION.y
		)
		var end := current
		end.z -= length
		var lateral_change := _rng.randf_range(-ROUTE_LATERAL_DRIFT, ROUTE_LATERAL_DRIFT)
		if feature == BANKED_TURN:
			lateral_change = turn_direction * _rng.randf_range(
				BANKED_TURN_LATERAL_RANGE.x,
				BANKED_TURN_LATERAL_RANGE.y
			)
			turn_direction *= -1.0
		end.x = clampf(current.x + lateral_change, -ROUTE_LATERAL_LIMIT, ROUTE_LATERAL_LIMIT)
		if feature == LAUNCH:
			end.y = current.y + _rng.randf_range(LAUNCH_RISE_RANGE.x, LAUNCH_RISE_RANGE.y)
		elif feature == LANDING:
			end.y = current.y - _rng.randf_range(LANDING_DROP_RANGE.x, LANDING_DROP_RANGE.y)
		else:
			var authored_drift := _route_noise.get_noise_1d(end.z) * ROUTE_HEIGHT_DRIFT
			end.y = lerpf(current.y, authored_drift, ROUTE_HEIGHT_BLEND)
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
	_smooth_route_properties(primary_samples)
	has_alternate_route = _rng.randf() < ALTERNATE_CHANCE
	if has_alternate_route:
		_generate_alternate_edge()


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
			position.x += sin(t * PI) * section.turn_direction * BANKED_TURN_BULGE
			position.y += sin(t * PI) * BANKED_TURN_RISE
		elif feature == LAUNCH or feature == LANDING:
			position.y = lerpf(start.y, end.y, eased)
		else:
			position.y += _route_noise.get_noise_1d(position.z) * ROUTE_DETAIL_HEIGHT
		var bank := 0.0
		if feature == BANKED_TURN:
			bank = section.turn_direction * sin(t * PI) * BANKED_TURN_STRENGTH
		primary_samples.append(_make_sample(position, section.width, bank, feature, section.index))
	primary_samples.append(_make_sample(end, section.width, 0.0, feature, section.index))


func _generate_alternate_edge() -> void:
	var start_sample := _get_primary_sample_at(_rng.randf_range(ALTERNATE_START_RANGE.x, ALTERNATE_START_RANGE.y))
	var end_sample := _get_primary_sample_at(_rng.randf_range(ALTERNATE_END_RANGE.x, ALTERNATE_END_RANGE.y))
	var start: Vector3 = start_sample.position
	var end: Vector3 = end_sample.position
	var side := -1.0 if _rng.randf() < 0.5 else 1.0
	if absf((start.x + end.x) * 0.5 + side * 230.0) > 500.0:
		side *= -1.0
	var branch_length := Vector2(end.x - start.x, end.z - start.z).length()
	var count := maxi(8, ceili(branch_length / SAMPLE_SPACING))
	var height_offset := _rng.randf_range(ALTERNATE_HEIGHT_RANGE.x, ALTERNATE_HEIGHT_RANGE.y)
	var lateral_offset := _rng.randf_range(ALTERNATE_LATERAL_RANGE.x, ALTERNATE_LATERAL_RANGE.y)
	for index in range(count + 1):
		var t := index / float(count)
		var eased := t * t * (3.0 - 2.0 * t)
		var position := start.lerp(end, eased)
		position.x += side * sin(eased * PI) * lateral_offset
		position.y += sin(eased * PI) * height_offset
		var sample := _make_sample(
			position,
			FEATURE_WIDTHS[ALTERNATE],
			side * sin(eased * PI) * ALTERNATE_BANK_STRENGTH,
			ALTERNATE,
			-1
		)
		sample.progress = lerpf(start_sample.progress, end_sample.progress, t)
		alternate_samples.append(sample)
	_finalize_route_samples(alternate_samples)
	_smooth_route_properties(alternate_samples)


func _make_sample(
	position: Vector3,
	width: float,
	bank: float,
	feature: String,
	section_index: int
) -> Dictionary:
	return {
		"position": position,
		"width": width,
		"bank": bank,
		"feature": feature,
		"section_index": section_index,
		"tangent": Vector3.FORWARD,
		"progress": 0.0,
	}


func _get_primary_sample_at(progress: float) -> Dictionary:
	var index := clampi(roundi(progress * (primary_samples.size() - 1)), 0, primary_samples.size() - 1)
	return primary_samples[index]


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


func _smooth_route_properties(samples: Array[Dictionary]) -> void:
	var blend_widths := PackedFloat32Array()
	var bowl_depths := PackedFloat32Array()
	var narrow_weights := PackedFloat32Array()
	blend_widths.resize(samples.size())
	bowl_depths.resize(samples.size())
	narrow_weights.resize(samples.size())
	var kernel_size := PROPERTY_SMOOTH_RADIUS + 1
	for index in range(samples.size()):
		var width_sum := 0.0
		var bowl_sum := 0.0
		var narrow_sum := 0.0
		var weight_sum := 0.0
		for neighbor_index in range(
			maxi(0, index - PROPERTY_SMOOTH_RADIUS),
			mini(samples.size(), index + PROPERTY_SMOOTH_RADIUS + 1)
		):
			var distance := absi(neighbor_index - index)
			var weight := float(kernel_size - distance)
			var neighbor: Dictionary = samples[neighbor_index]
			width_sum += neighbor.width * weight
			bowl_sum += _feature_bowl_depth(neighbor.feature) * weight
			narrow_sum += (1.0 if neighbor.feature == NARROW_PASS else 0.0) * weight
			weight_sum += weight
		blend_widths[index] = maxf(width_sum / weight_sum, MINIMUM_BLEND_WIDTH)
		bowl_depths[index] = bowl_sum / weight_sum
		narrow_weights[index] = narrow_sum / weight_sum
	for index in range(samples.size()):
		samples[index].blend_width = blend_widths[index]
		samples[index].bowl_depth = bowl_depths[index]
		samples[index].narrow_pass_weight = narrow_weights[index]


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
