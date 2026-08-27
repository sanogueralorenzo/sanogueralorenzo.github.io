extends RefCounted

const RouteLookupTable = preload("res://scripts/route_lookup.gd")
const RouteGeneratorBuilder = preload("res://scripts/route_generator.gd")

const ROUTE_INFLUENCE_CORE := 0.42
const ROUTE_INFLUENCE_OUTER := 3.40
const ROUTE_BLEND_DISTANCE := 70.0
const BANK_FADE_START := 0.45
const BANK_FADE_END := 1.15
const NARROW_WALL_START := 0.62
const NARROW_WALL_PEAK := 1.50
const NARROW_WALL_END := 2.50
const NARROW_WALL_HEIGHT := 22.0
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
var _primary_lookup = RouteLookupTable.new()
var _alternate_lookup = RouteLookupTable.new()
var _primary_query = RouteLookupTable.Query.new()
var _alternate_query = RouteLookupTable.Query.new()
var _route_generator = RouteGeneratorBuilder.new()


func configure(seed_value: int, size: float) -> void:
	seed = seed_value
	map_size = size
	_rng.seed = seed
	_configure_noise()
	region_breaks = Vector2(_rng.randf_range(0.28, 0.34), _rng.randf_range(0.63, 0.70))
	palette_phase = _rng.randf_range(-50.0, 50.0)
	_route_generator.generate(_rng, _route_noise)
	route_length = _route_generator.route_length
	sections = _route_generator.sections
	primary_samples = _route_generator.primary_samples
	alternate_samples = _route_generator.alternate_samples
	has_alternate_route = _route_generator.has_alternate_route
	_primary_lookup.configure(primary_samples)
	_alternate_lookup.configure(alternate_samples)


func sample_height(x: float, z: float) -> float:
	var terrain_height := _sample_base_height(x, z)
	var route_height_sum := 0.0
	var total_shaping_weight := 0.0
	var strongest_influence := 0.0
	_primary_lookup.sample(x, z, _primary_query)
	_alternate_lookup.sample(x, z, _alternate_query)
	var primary_contribution := _get_route_contribution(_primary_query)
	var alternate_contribution := _get_route_contribution(_alternate_query)
	route_height_sum = primary_contribution.x + alternate_contribution.x
	total_shaping_weight = primary_contribution.y + alternate_contribution.y
	strongest_influence = maxf(primary_contribution.z, alternate_contribution.z)
	if total_shaping_weight > 0.0:
		var blended_route_height := route_height_sum / total_shaping_weight
		terrain_height = lerpf(terrain_height, blended_route_height, strongest_influence)
	var nearest_route = _get_nearest_query()
	if nearest_route != null:
		var core_distance: float = nearest_route.distance / maxf(nearest_route.width, 1.0)
		var core_influence := 1.0 - _smootherstep(0.0, ROUTE_INFLUENCE_CORE, core_distance)
		if core_influence > 0.0:
			terrain_height = lerpf(
				terrain_height,
				_get_shaped_route_height(nearest_route),
				core_influence
			)

	var start_blend := smoothstep(10.0, 58.0, Vector2(x, z).length())
	return lerpf(0.0, terrain_height, start_blend)


func _get_route_contribution(route_info) -> Vector3:
	if not route_info.valid:
		return Vector3.ZERO
	var normalized_distance: float = route_info.distance / maxf(route_info.width, 1.0)
	var influence := 1.0 - _smootherstep(
		ROUTE_INFLUENCE_CORE,
		ROUTE_INFLUENCE_OUTER,
		normalized_distance
	)
	if influence <= 0.0:
		return Vector3.ZERO
	var shaping_weight := influence * exp(-0.5 * pow(route_info.distance / ROUTE_BLEND_DISTANCE, 2.0))
	return Vector3(_get_shaped_route_height(route_info) * shaping_weight, shaping_weight, influence)


func _get_shaped_route_height(route_info) -> float:
	var normalized_distance: float = route_info.distance / maxf(route_info.width, 1.0)
	var bank_influence := 1.0 - _smootherstep(BANK_FADE_START, BANK_FADE_END, normalized_distance)
	var route_height: float = route_info.position.y + route_info.signed_distance * route_info.bank * bank_influence
	route_height += minf(
		normalized_distance * normalized_distance * route_info.bowl_depth,
		route_info.bowl_depth * 1.8
	)
	if route_info.narrow_pass_weight > 0.001:
		var wall_band := _smootherstep(NARROW_WALL_START, NARROW_WALL_PEAK, normalized_distance)
		wall_band *= 1.0 - _smootherstep(NARROW_WALL_PEAK, NARROW_WALL_END, normalized_distance)
		route_height += wall_band * NARROW_WALL_HEIGHT * route_info.narrow_pass_weight
	return route_height


func get_spawn_position() -> Vector3:
	return Vector3(0.0, sample_height(0.0, 0.0) + 3.5, 0.0)


func get_closest_route_info(x: float, z: float) -> Dictionary:
	_primary_lookup.sample(x, z, _primary_query)
	_alternate_lookup.sample(x, z, _alternate_query)
	var nearest_route = _get_nearest_query()
	if nearest_route == null:
		return {}
	return {
		"sample": {
			"position": nearest_route.position,
			"width": nearest_route.width,
			"bank": nearest_route.bank,
			"bowl_depth": nearest_route.bowl_depth,
			"narrow_pass_weight": nearest_route.narrow_pass_weight,
			"feature": nearest_route.feature,
			"tangent": nearest_route.tangent,
			"progress": nearest_route.progress,
		},
		"distance": nearest_route.distance,
		"signed_distance": nearest_route.signed_distance,
	}


func _get_nearest_query():
	if not _primary_query.valid:
		return _alternate_query if _alternate_query.valid else null
	if not _alternate_query.valid or _primary_query.distance <= _alternate_query.distance:
		return _primary_query
	return _alternate_query


func get_route_clearance(x: float, z: float) -> float:
	_primary_lookup.sample(x, z, _primary_query)
	_alternate_lookup.sample(x, z, _alternate_query)
	var closest = _get_nearest_query()
	if closest == null:
		return INF
	return closest.distance / maxf(closest.width, 1.0)


func get_region_name(z: float) -> String:
	var progress := clampf(-z / maxf(route_length, 1.0), 0.0, 1.0)
	if progress < region_breaks.x:
		return "VERDANT REACH"
	if progress < region_breaks.y:
		return "EMBER BASIN"
	return "PRISM HIGHLANDS"


func get_layout_fingerprint() -> String:
	return _route_generator.get_layout_fingerprint()


func _configure_noise() -> void:
	_broad_noise.seed = _rng.randi()
	_broad_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_broad_noise.frequency = 0.00082
	_broad_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_broad_noise.fractal_octaves = 4
	_broad_noise.fractal_gain = 0.42

	_ridge_noise.seed = _rng.randi()
	_ridge_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_ridge_noise.frequency = 0.00115
	_ridge_noise.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_ridge_noise.fractal_octaves = 3
	_ridge_noise.fractal_gain = 0.40

	_detail_noise.seed = _rng.randi()
	_detail_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_detail_noise.frequency = 0.0035
	_detail_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_detail_noise.fractal_octaves = 2
	_detail_noise.fractal_gain = 0.36

	_route_noise.seed = _rng.randi()
	_route_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_route_noise.frequency = 0.0018
	_route_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_route_noise.fractal_octaves = 3


func _sample_base_height(x: float, z: float) -> float:
	var progress := clampf(-z / maxf(route_length, 1.0), 0.0, 1.0)
	var weights := _region_weights(progress)
	var broad := _broad_noise.get_noise_2d(x, z)
	var ridge := _ridge_noise.get_noise_2d(x, z)
	var detail := _detail_noise.get_noise_2d(x, z)
	var ridge_curve := ridge * absf(ridge)
	var rounded_ridge := ridge * ridge
	var verdant := broad * 70.0 + ridge_curve * 34.0 + detail * 5.0
	var ember := broad * 90.0 + ridge_curve * 96.0 + detail * 8.0 + 12.0
	var prism := broad * 108.0 + rounded_ridge * 78.0 + detail * 10.0 + 24.0
	return verdant * weights.x + ember * weights.y + prism * weights.z


func _smootherstep(edge_start: float, edge_end: float, value: float) -> float:
	var t := clampf((value - edge_start) / maxf(edge_end - edge_start, 0.0001), 0.0, 1.0)
	return t * t * t * (t * (t * 6.0 - 15.0) + 10.0)


func _region_weights(progress: float) -> Vector3:
	var first := 1.0 - smoothstep(region_breaks.x - 0.075, region_breaks.x + 0.075, progress)
	var third := smoothstep(region_breaks.y - 0.075, region_breaks.y + 0.075, progress)
	var second := maxf(0.0, 1.0 - first - third)
	return Vector3(first, second, third)
