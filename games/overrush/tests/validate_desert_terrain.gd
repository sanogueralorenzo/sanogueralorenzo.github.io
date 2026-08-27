extends SceneTree

const DIRECTION_COUNT := 16
const SAMPLE_STEP := 50.0
const SAMPLE_RADIUS := 2000.0
const MINIMUM_NET_DESCENT := 185.0
const MAXIMUM_LOCAL_RISE := 28.0

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

	for direction_index in range(DIRECTION_COUNT):
		var angle := TAU * float(direction_index) / DIRECTION_COUNT
		var direction := Vector2(cos(angle), sin(angle))
		var previous_height := center_height
		for distance in range(int(SAMPLE_STEP), int(SAMPLE_RADIUS) + 1, int(SAMPLE_STEP)):
			var point := direction * distance
			var height := desert.get_surface_height(point.x, point.y)
			_expect(is_finite(height), "Terrain samples must always be finite.")
			greatest_local_rise = maxf(greatest_local_rise, height - previous_height)
			previous_height = height
		endpoint_heights.append(previous_height)
		var net_descent := center_height - previous_height
		shallowest_descent = minf(shallowest_descent, net_descent)
		_expect(
			net_descent >= MINIMUM_NET_DESCENT,
			"Direction %d only descends %.1f m over %.0f m." % [direction_index, net_descent, SAMPLE_RADIUS],
		)

	_expect(greatest_local_rise <= MAXIMUM_LOCAL_RISE, "A 50 m terrain segment rises too abruptly: %.1f m." % greatest_local_rise)
	var endpoint_range: float = endpoint_heights.max() - endpoint_heights.min()
	_expect(endpoint_range >= 18.0, "Radial lines need meaningful seeded variation instead of identical cones.")
	_expect(desert.terrain.mesh.get_surface_count() == 1, "The desert should be one watertight terrain surface without visual seams.")
	_expect(desert.terrain_collision.shape is HeightMapShape3D, "The visible desert and collision should share heightmap generation.")

	if _failures.is_empty():
		print(
			"Desert terrain passed — 16 outward lines, shallowest descent %.1f m, max 50 m rise %.1f m, endpoint range %.1f m."
			% [shallowest_descent, greatest_local_rise, endpoint_range]
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
