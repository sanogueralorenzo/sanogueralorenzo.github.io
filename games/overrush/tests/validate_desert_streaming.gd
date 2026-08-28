extends SceneTree

const TEST_SEED := 61813
const FAR_POSITION := Vector2(10500.0, -7600.0)
const BORDER_TOLERANCE := 0.001
const COLLISION_TOLERANCE := 0.35

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene: Node = load("res://freeride.tscn").instantiate()
	scene.set_meta(&"overrush_manual_start", true)
	scene.get_node("Desert").seed = TEST_SEED
	root.add_child(scene)
	await process_frame
	await physics_frame
	var desert: ProceduralDesert = scene.get_node("Desert")
	var rider: Sandboarder = scene.get_node("Sandboarder")
	var camera: Camera3D = scene.get_node("FollowCamera")
	var initial_rocks := desert.get_loaded_rock_gate_bodies()
	_expect(initial_rocks.size() >= 8, "The opening stream should contain several readable rock passages beyond the summit.")
	_expect(initial_rocks.size() <= 32, "Rock passages should remain sparse enough for alternate lines.")
	for rock in initial_rocks:
		_expect(desert.is_obstacle_collider(rock), "Rock bodies need an explicit obstacle collision identity.")
		_expect(not desert.is_rideable_collider(rock), "Rock collision must never qualify as a boost-refreshing rideable landing.")
		_expect(float(rock.get_meta(&"passage_clearance", 0.0)) >= 12.0, "Rock gates must retain at least 12 m of clear passage.")
		var rock_shape: CollisionShape3D = rock.get_node("CollisionShape3D")
		_expect(rock_shape.shape is SphereShape3D, "Every procedural rock needs dedicated solid collision.")
		var logical_rock_position := desert.get_world_position(rock.global_position)
		_expect(Vector2(logical_rock_position.x, logical_rock_position.z).length() >= 300.0, "Rocks must leave the central drop-in region unobstructed.")

	_validate_shared_border(desert, Vector2i.ZERO, Vector2i.RIGHT)
	_validate_horizon_border(desert, Vector2i(2, 0), Vector2i(3, 0))
	await _validate_collision_seam(desert, rider)

	var far_height := desert.get_surface_height(FAR_POSITION.x, FAR_POSITION.y)
	var logical_target := Vector3(FAR_POSITION.x, far_height + 0.45, FAR_POSITION.y)
	rider.distance_traveled = 7321.0
	rider.global_position = desert.world_to_local_position(logical_target)
	camera.global_position = rider.global_position + Vector3(9.0, 7.0, 13.0)
	var camera_offset := camera.global_position - rider.global_position
	desert.maintain_streaming(true)
	var recovered_logical_position := desert.get_world_position(rider.global_position)

	_expect(
		recovered_logical_position.is_equal_approx(logical_target),
		"Origin rebasing must preserve the rider's logical world position.",
	)
	_expect(
		(camera.global_position - rider.global_position).is_equal_approx(camera_offset),
		"Origin rebasing must preserve the camera-to-rider offset.",
	)
	_expect(is_equal_approx(rider.distance_traveled, 7321.0), "Origin rebasing must not add false run distance.")
	_expect(
		Vector2(rider.global_position.x, rider.global_position.z).length() < desert.chunk_size,
		"The rider should return close to the floating origin after distant travel.",
	)
	_expect(absf(rider.global_position.y) < 1.0, "Vertical rebasing should keep the rider close to local zero.")
	_expect(desert.loaded_chunks.size() == 25, "Chunk residency should remain bounded after distant travel.")
	_expect(desert.horizon_chunks.size() <= 56, "The collision-free horizon ring should remain bounded after distant travel.")
	_expect(
		is_equal_approx(desert.get_surface_height(FAR_POSITION.x, FAR_POSITION.y), far_height),
		"Streaming and rebasing must not change deterministic terrain heights.",
	)
	var far_coord := desert.get_chunk_coordinate(FAR_POSITION)
	_expect(desert.get_chunk(far_coord) != null, "The distant focus chunk should be loaded synchronously for safety.")
	for chunk_value in desert.loaded_chunks.values():
		var chunk: StaticBody3D = chunk_value
		_expect(
			Vector2(chunk.position.x, chunk.position.z).length() <= desert.chunk_size * 3.0,
			"Resident chunk transforms should stay near the floating origin.",
		)

	var travel_direction := Vector2(0.8, -0.6)
	for travel_step in range(1, 31):
		var logical_xz := FAR_POSITION + travel_direction * travel_step * 300.0
		var logical_position := Vector3(
			logical_xz.x,
			desert.get_surface_height(logical_xz.x, logical_xz.y) + 0.45,
			logical_xz.y,
		)
		rider.global_position = desert.world_to_local_position(logical_position)
		camera.global_position = rider.global_position + camera_offset
		desert.maintain_streaming(false)
		_expect(
			desert.get_world_position(rider.global_position).is_equal_approx(logical_position),
			"Repeated origin rebases must preserve logical position at travel step %d." % travel_step,
		)
		var focus_coord := desert.get_chunk_coordinate(logical_xz)
		for z_offset in range(-1, 2):
			for x_offset in range(-1, 2):
				_expect(
					desert.get_chunk(focus_coord + Vector2i(x_offset, z_offset)) != null,
					"The collision safety neighborhood is incomplete at travel step %d." % travel_step,
				)
		_expect(desert.loaded_chunks.size() <= 49, "Resident chunks exceeded the bounded 7 by 7 retention area.")
	desert.flush_streaming()
	_expect(desert.loaded_chunks.size() <= 49, "Flushing streamed terrain must preserve bounded residency.")

	if _failures.is_empty():
		print(
			"Desert streaming passed — exact shared borders, collision continuity, 22 km of rebased travel, and %d bounded chunks."
			% desert.loaded_chunks.size()
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


func _validate_shared_border(desert: ProceduralDesert, left_coord: Vector2i, right_coord: Vector2i) -> void:
	var left_chunk := desert.get_chunk(left_coord)
	var right_chunk := desert.get_chunk(right_coord)
	_expect(left_chunk != null and right_chunk != null, "Both neighboring chunks must be resident for seam validation.")
	if left_chunk == null or right_chunk == null:
		return
	var left_mesh: ArrayMesh = left_chunk.get_node("Terrain").mesh
	var right_mesh: ArrayMesh = right_chunk.get_node("Terrain").mesh
	var left_arrays := left_mesh.surface_get_arrays(0)
	var right_arrays := right_mesh.surface_get_arrays(0)
	var left_vertices: PackedVector3Array = left_arrays[Mesh.ARRAY_VERTEX]
	var right_vertices: PackedVector3Array = right_arrays[Mesh.ARRAY_VERTEX]
	var left_normals: PackedVector3Array = left_arrays[Mesh.ARRAY_NORMAL]
	var right_normals: PackedVector3Array = right_arrays[Mesh.ARRAY_NORMAL]
	var left_colors: PackedColorArray = left_arrays[Mesh.ARRAY_COLOR]
	var right_colors: PackedColorArray = right_arrays[Mesh.ARRAY_COLOR]
	var max_height_error := 0.0
	var max_normal_error := 0.0
	var max_biome_error := 0.0
	for row in range(desert.chunk_resolution):
		var left_index := row * desert.chunk_resolution + desert.chunk_resolution - 1
		var right_index := row * desert.chunk_resolution
		var left_height: float = left_chunk.position.y + left_vertices[left_index].y
		var right_height: float = right_chunk.position.y + right_vertices[right_index].y
		max_height_error = maxf(max_height_error, absf(left_height - right_height))
		max_normal_error = maxf(max_normal_error, left_normals[left_index].distance_to(right_normals[right_index]))
		max_biome_error = maxf(max_biome_error, absf(left_colors[left_index].r - right_colors[right_index].r))
	_expect(max_height_error <= BORDER_TOLERANCE, "Adjacent mesh borders differ vertically by %.6f m." % max_height_error)
	_expect(max_normal_error <= BORDER_TOLERANCE, "Adjacent mesh-border normals differ by %.6f." % max_normal_error)
	_expect(max_biome_error <= BORDER_TOLERANCE, "Adjacent mesh-border biome weights differ by %.6f." % max_biome_error)


func _validate_collision_seam(desert: ProceduralDesert, rider: Sandboarder) -> void:
	var seam_x := desert.chunk_size * 0.5
	var space := root.world_3d.direct_space_state
	for x_offset in [-0.05, 0.05]:
		var logical_x: float = seam_x + x_offset
		var expected_height := desert.get_surface_height(logical_x, 0.0)
		var query := PhysicsRayQueryParameters3D.create(
			Vector3(logical_x, expected_height + 50.0, 0.0),
			Vector3(logical_x, expected_height - 50.0, 0.0),
		)
		query.exclude = [rider.get_rid()]
		var hit := space.intersect_ray(query)
		_expect(not hit.is_empty(), "Collision ray missed one side of a streamed chunk seam.")
		if not hit.is_empty():
			_expect(desert.is_rideable_collider(hit.collider), "Seam collision should resolve to valid rideable terrain.")
			_expect(
				absf(hit.position.y - expected_height) <= COLLISION_TOLERANCE,
				"Collision differs from procedural height by %.3f m at the seam." % absf(hit.position.y - expected_height),
			)


func _validate_horizon_border(desert: ProceduralDesert, near_coord: Vector2i, far_coord: Vector2i) -> void:
	var near_chunk := desert.get_chunk(near_coord)
	var far_terrain := desert.horizon_chunks.get(far_coord) as MeshInstance3D
	_expect(near_chunk != null and far_terrain != null, "The visual horizon needs a resident border sample beyond collision terrain.")
	if near_chunk == null or far_terrain == null:
		return
	var near_mesh: ArrayMesh = near_chunk.get_node("Terrain").mesh
	var far_mesh := far_terrain.mesh as ArrayMesh
	var near_arrays := near_mesh.surface_get_arrays(0)
	var far_arrays := far_mesh.surface_get_arrays(0)
	var near_vertices: PackedVector3Array = near_arrays[Mesh.ARRAY_VERTEX]
	var far_vertices: PackedVector3Array = far_arrays[Mesh.ARRAY_VERTEX]
	var near_colors: PackedColorArray = near_arrays[Mesh.ARRAY_COLOR]
	var far_colors: PackedColorArray = far_arrays[Mesh.ARRAY_COLOR]
	var sample_ratio := roundi(
		float(desert.chunk_resolution - 1)
		/ float(ProceduralDesert.HORIZON_CHUNK_RESOLUTION - 1)
	)
	var maximum_height_error := 0.0
	var maximum_biome_error := 0.0
	for far_row in range(ProceduralDesert.HORIZON_CHUNK_RESOLUTION):
		var near_row := far_row * sample_ratio
		var near_index := near_row * desert.chunk_resolution + desert.chunk_resolution - 1
		var far_index := far_row * ProceduralDesert.HORIZON_CHUNK_RESOLUTION
		var near_height: float = near_chunk.position.y + near_vertices[near_index].y
		var far_height: float = far_terrain.position.y + far_vertices[far_index].y
		maximum_height_error = maxf(maximum_height_error, absf(near_height - far_height))
		maximum_biome_error = maxf(maximum_biome_error, absf(near_colors[near_index].r - far_colors[far_index].r))
	_expect(maximum_height_error <= BORDER_TOLERANCE, "Horizon terrain opens a %.6f m border crack." % maximum_height_error)
	_expect(maximum_biome_error <= BORDER_TOLERANCE, "Horizon terrain changes biome weight by %.6f at its inner border." % maximum_biome_error)
	_expect(
		far_terrain.get_child_count() == 0 and far_terrain.get_meta(&"overrush_horizon_terrain", false),
		"Horizon terrain must remain visual-only and never add collision or obstacles.",
	)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
