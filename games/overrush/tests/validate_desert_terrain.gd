extends SceneTree

const DIRECTION_COUNT := 16
const SAMPLE_STEP := 50.0
const SAMPLE_RADIUS := 12000.0
const MINIMUM_NET_DESCENT := 5600.0
const MINIMUM_FIRST_250M_DESCENT := 120.0
const MINIMUM_FIRST_KM_DESCENT := 355.0
const MAXIMUM_LOCAL_RISE := 36.0
const MINIMUM_CROSS_SLOPE_RELIEF := 55.0
const LOCAL_RELIEF_WINDOW_LENGTH := 160
const LOCAL_RELIEF_SAMPLE_STEP := 10
const MINIMUM_LOCAL_RELIEF_P10 := 6.25

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene: Node = load("res://freeride.tscn").instantiate()
	scene.set_meta(&"overrush_manual_start", true)
	scene.get_node("Desert").seed = 89173
	root.add_child(scene)
	await process_frame
	var desert: ProceduralDesert = scene.get_node("Desert")
	var center_height := desert.get_surface_height(0.0, 0.0)
	var endpoint_heights: Array[float] = []
	var greatest_local_rise := 0.0
	var shallowest_descent := INF
	var shallowest_first_250m_descent := INF
	var shallowest_first_km_descent := INF
	var local_relief_samples: Array[float] = []

	for direction_index in range(DIRECTION_COUNT):
		var angle := TAU * float(direction_index) / DIRECTION_COUNT
		var direction := Vector2(cos(angle), sin(angle))
		var previous_height := center_height
		var first_250m_height := center_height
		var first_km_height := center_height
		for distance in range(int(SAMPLE_STEP), int(SAMPLE_RADIUS) + 1, int(SAMPLE_STEP)):
			var point := direction * distance
			var height := desert.get_surface_height(point.x, point.y)
			_expect(is_finite(height), "Terrain samples must always be finite.")
			greatest_local_rise = maxf(greatest_local_rise, height - previous_height)
			previous_height = height
			if distance == 250:
				first_250m_height = height
			if distance == 1000:
				first_km_height = height
		endpoint_heights.append(previous_height)
		var net_descent := center_height - previous_height
		var first_250m_descent := center_height - first_250m_height
		var first_km_descent := center_height - first_km_height
		shallowest_descent = minf(shallowest_descent, net_descent)
		shallowest_first_250m_descent = minf(shallowest_first_250m_descent, first_250m_descent)
		shallowest_first_km_descent = minf(shallowest_first_km_descent, first_km_descent)
		_expect(
			net_descent >= MINIMUM_NET_DESCENT,
			"Direction %d only descends %.1f m over %.0f m." % [direction_index, net_descent, SAMPLE_RADIUS],
		)
		_expect(
			first_250m_descent >= MINIMUM_FIRST_250M_DESCENT,
			"Direction %d lacks an immediate summit drop: %.1f m descent in the first 250 m."
			% [direction_index, first_250m_descent],
		)
		_expect(
			first_km_descent >= MINIMUM_FIRST_KM_DESCENT,
			"Direction %d feels too flat near the summit: %.1f m descent in the first kilometer."
			% [direction_index, first_km_descent],
		)
		var lateral := Vector2(-direction.y, direction.x)
		var cross_slope_relief := 0.0
		for relief_distance_value in [800.0, 1600.0, 2400.0, 3200.0]:
			var relief_distance: float = relief_distance_value
			var cross_slope_heights: Array[float] = []
			for lateral_offset in [-384.0, -288.0, -192.0, -96.0, 0.0, 96.0, 192.0, 288.0, 384.0]:
				var relief_point: Vector2 = direction * relief_distance + lateral * float(lateral_offset)
				cross_slope_heights.append(desert.get_surface_height(relief_point.x, relief_point.y))
			cross_slope_relief = maxf(cross_slope_relief, cross_slope_heights.max() - cross_slope_heights.min())
		_expect(
			cross_slope_relief >= MINIMUM_CROSS_SLOPE_RELIEF,
			"Direction %d lacks mountain-scale cross-slope relief: %.1f m." % [direction_index, cross_slope_relief],
		)
		for window_start in range(640, 2561, LOCAL_RELIEF_WINDOW_LENGTH):
			var window_heights: Array[float] = []
			for sample_offset in range(0, LOCAL_RELIEF_WINDOW_LENGTH + 1, LOCAL_RELIEF_SAMPLE_STEP):
				var relief_point := direction * float(window_start + sample_offset)
				window_heights.append(desert.get_surface_height(relief_point.x, relief_point.y))
			var first_window_height: float = window_heights.front()
			var last_window_height: float = window_heights.back()
			var minimum_residual := INF
			var maximum_residual := -INF
			for sample_index in range(window_heights.size()):
				var progress := float(sample_index) / float(window_heights.size() - 1)
				var residual := window_heights[sample_index] - lerpf(first_window_height, last_window_height, progress)
				minimum_residual = minf(minimum_residual, residual)
				maximum_residual = maxf(maximum_residual, residual)
			local_relief_samples.append(maximum_residual - minimum_residual)
		var encountered_features := {}
		var encountered_rock_chunks := {}
		var rock_passage_count := 0
		for feature_distance in range(512, int(SAMPLE_RADIUS) + 1, 64):
			for lateral_offset in [-256.0, -192.0, -128.0, -64.0, 0.0, 64.0, 128.0, 192.0, 256.0]:
				var feature_point: Vector2 = direction * feature_distance + lateral * float(lateral_offset)
				if absf(desert.get_feature_height_offset(feature_point)) >= 0.75:
					encountered_features[desert.get_feature_kind_at(feature_point)] = true
			var rock_point: Vector2 = direction * feature_distance
			var rock_coord := desert.get_chunk_coordinate(rock_point)
			if not encountered_rock_chunks.has(rock_coord):
				encountered_rock_chunks[rock_coord] = true
				if desert.chunk_has_rock_passage(rock_coord):
					rock_passage_count += 1
		for required_kind in [
			DesertFeatureGrammar.BOWL,
			DesertFeatureGrammar.RIDGE,
			DesertFeatureGrammar.KICKER,
			DesertFeatureGrammar.SPLIT_LINE,
		]:
			_expect(
				encountered_features.has(required_kind),
				"Direction %d never encounters a %s feature over %.0f m." % [direction_index, required_kind, SAMPLE_RADIUS],
			)
		_expect(rock_passage_count >= 2, "Direction %d contains too few readable rock passages: %d." % [direction_index, rock_passage_count])

	_expect(greatest_local_rise <= MAXIMUM_LOCAL_RISE, "A 50 m terrain segment rises too abruptly: %.1f m." % greatest_local_rise)
	local_relief_samples.sort()
	var local_relief_p10 := local_relief_samples[int(local_relief_samples.size() * 0.1)]
	_expect(
		local_relief_p10 >= MINIMUM_LOCAL_RELIEF_P10,
		"Too many 160 m downhill windows read as planar ground: p10 relief %.2f m." % local_relief_p10,
	)
	var endpoint_range: float = endpoint_heights.max() - endpoint_heights.min()
	_expect(endpoint_range >= 18.0, "Radial lines need meaningful seeded variation instead of identical cones.")
	_expect(desert.loaded_chunks.size() == 25, "The initial stream should contain a bounded 5 by 5 chunk neighborhood.")
	var center_chunk := desert.get_chunk(Vector2i.ZERO)
	_expect(center_chunk != null, "The central summit chunk should be resident.")
	if center_chunk != null:
		var terrain: MeshInstance3D = center_chunk.get_node("Terrain")
		var collision: CollisionShape3D = center_chunk.get_node("TerrainCollision")
		_expect(terrain.mesh.get_surface_count() == 1, "Each desert chunk should use one continuous terrain surface.")
		_expect(collision.shape is HeightMapShape3D, "Every visual chunk should carry matching heightmap collision.")

	if _failures.is_empty():
		print(
			"Desert terrain passed — 16 outward line fans contain every feature family and rock gates; shallowest descent %.1f m (%.1f m at 250 m, %.1f m at 1 km), p10 local relief %.2f m, max 50 m rise %.1f m, endpoint range %.1f m."
			% [shallowest_descent, shallowest_first_250m_descent, shallowest_first_km_descent, local_relief_p10, greatest_local_rise, endpoint_range]
		)
		scene.queue_free()
		await process_frame
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		scene.queue_free()
		await process_frame
		quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
