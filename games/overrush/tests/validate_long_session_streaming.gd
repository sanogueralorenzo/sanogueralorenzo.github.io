extends SceneTree

const TEST_SEED := 94631
const TRAVEL_STEP_COUNT := 120
const TRAVEL_STEP_DISTANCE := 440.0
const MAXIMUM_LOGICAL_ERROR := 0.01
const MAXIMUM_TRANSITION_MILLISECONDS := 900.0

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene: Node = load("res://freeride.tscn").instantiate()
	scene.set_meta(&"overrush_manual_start", true)
	scene.get_node("Desert").seed = TEST_SEED
	root.add_child(scene)
	await process_frame
	var desert: ProceduralDesert = scene.get_node("Desert")
	var rider: Sandboarder = scene.get_node("Sandboarder")
	var camera: Camera3D = scene.get_node("FollowCamera")
	var camera_offset := Vector3(8.0, 6.5, 11.0)
	var logical_xz := Vector2.ZERO
	var route_distance := 0.0
	var rebase_count := 0
	var previous_origin := desert.world_origin
	var maximum_transition_milliseconds := 0.0
	var total_transition_milliseconds := 0.0
	var stable_height_samples: Dictionary = {}
	rider.distance_traveled = 2468.0

	var headings: Array[Vector2] = [
		Vector2(0.8, -0.6),
		Vector2(1.0, 0.0),
		Vector2(0.72, 0.69).normalized(),
		Vector2(0.45, -0.89).normalized(),
	]
	for travel_step in range(1, TRAVEL_STEP_COUNT + 1):
		var heading := headings[floori(float(travel_step - 1) / 15.0) % headings.size()]
		logical_xz += heading * TRAVEL_STEP_DISTANCE
		route_distance += TRAVEL_STEP_DISTANCE
		var surface_height := desert.get_surface_height(logical_xz.x, logical_xz.y)
		_expect(is_finite(surface_height), "Long-session terrain became non-finite at step %d." % travel_step)
		var logical_position := Vector3(logical_xz.x, surface_height + 0.45, logical_xz.y)
		rider.global_position = desert.world_to_local_position(logical_position)
		camera.global_position = rider.global_position + camera_offset
		var transition_started := Time.get_ticks_usec()
		desert.maintain_streaming(false)
		var transition_milliseconds := float(Time.get_ticks_usec() - transition_started) / 1000.0
		maximum_transition_milliseconds = maxf(maximum_transition_milliseconds, transition_milliseconds)
		total_transition_milliseconds += transition_milliseconds

		var recovered_position := desert.get_world_position(rider.global_position)
		_expect(
			recovered_position.distance_to(logical_position) <= MAXIMUM_LOGICAL_ERROR,
			"Floating-origin precision drifted by %.4f m at step %d." % [recovered_position.distance_to(logical_position), travel_step],
		)
		_expect(
			(camera.global_position - rider.global_position).is_equal_approx(camera_offset),
			"The camera offset changed during rebase step %d." % travel_step,
		)
		_expect(is_equal_approx(rider.distance_traveled, 2468.0), "Streaming added false run distance at step %d." % travel_step)
		_expect(
			Vector2(rider.global_position.x, rider.global_position.z).length() <= desert.rebase_distance + desert.chunk_size,
			"The rider escaped the floating-origin precision envelope at step %d." % travel_step,
		)
		_expect(absf(rider.global_position.y) <= desert.rebase_distance, "Vertical position escaped the floating-origin precision envelope at step %d." % travel_step)
		_expect(desert.loaded_chunks.size() <= 49, "Chunk residency exceeded the bounded 7 by 7 area at step %d." % travel_step)
		_expect(desert._pending_chunks.size() <= 16, "Pending chunk work exceeded one outer ring at step %d." % travel_step)
		_validate_safety_neighborhood(desert, logical_xz, travel_step)

		if desert.world_origin != previous_origin:
			rebase_count += 1
			previous_origin = desert.world_origin
		if travel_step % 24 == 0:
			stable_height_samples[logical_xz] = surface_height
		if travel_step % 4 == 0:
			await process_frame

	desert.flush_streaming()
	_expect(desert._pending_chunks.is_empty(), "The final streamed outer ring should flush completely.")
	_expect(desert.loaded_chunks.size() <= 49, "Final chunk residency exceeded the bounded retention area.")
	_expect(route_distance >= 50000.0, "The long-session route did not exceed 50 km.")
	_expect(rebase_count >= 24, "The soak exercised too few floating-origin rebases: %d." % rebase_count)
	_expect(
		maximum_transition_milliseconds <= MAXIMUM_TRANSITION_MILLISECONDS,
		"A worst-case chunk transition took %.1f ms, above the %.0f ms soak ceiling."
		% [maximum_transition_milliseconds, MAXIMUM_TRANSITION_MILLISECONDS],
	)
	for sample_position in stable_height_samples:
		_expect(
			is_equal_approx(desert.get_surface_height(sample_position.x, sample_position.y), float(stable_height_samples[sample_position])),
			"Terrain height changed after streaming at %s." % sample_position,
		)

	var average_transition_milliseconds := total_transition_milliseconds / float(TRAVEL_STEP_COUNT)
	if _failures.is_empty():
		print(
			"Long-session streaming passed — %.1f km, %d rebases, %d resident chunks, %.1f ms average and %.1f ms worst transition."
			% [route_distance / 1000.0, rebase_count, desert.loaded_chunks.size(), average_transition_milliseconds, maximum_transition_milliseconds]
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


func _validate_safety_neighborhood(desert: ProceduralDesert, logical_xz: Vector2, travel_step: int) -> void:
	var focus_coord := desert.get_chunk_coordinate(logical_xz)
	for z_offset in range(-1, 2):
		for x_offset in range(-1, 2):
			_expect(
				desert.get_chunk(focus_coord + Vector2i(x_offset, z_offset)) != null,
				"The collision safety neighborhood is incomplete at soak step %d." % travel_step,
			)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
