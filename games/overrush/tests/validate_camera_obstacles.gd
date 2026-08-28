extends SceneTree

const TEST_SEED := 73013

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene: Node = load("res://freeride.tscn").instantiate()
	scene.set_meta(&"overrush_manual_start", true)
	scene.get_node("Desert").seed = TEST_SEED
	root.add_child(scene)
	await physics_frame
	await physics_frame
	var world: ProceduralDesert = scene.get_node("Desert")
	var rider: Sandboarder = scene.get_node("Sandboarder")
	var camera = scene.get_node("FollowCamera")
	var targets := _find_obstacle_targets(world)
	_expect(targets.has(&"tree"), "The camera-clearance test needs a streamed tree trunk.")
	_expect(targets.has(&"rock"), "The camera-clearance test needs a streamed rock.")
	for obstacle_kind in targets:
		_validate_blocked_line(camera, world, obstacle_kind, targets[obstacle_kind], Vector3.RIGHT, 5.0, 7.0)

	var ruin_coord := _find_nearest_ruin(world)
	_expect(ruin_coord != Vector2i(2147483647, 2147483647), "The camera-clearance test needs a sparse ruin site.")
	if ruin_coord != Vector2i(2147483647, 2147483647):
		var ruin_focus := Vector2(ruin_coord) * world.chunk_size
		rider.global_position = world.world_to_local_position(Vector3(
			ruin_focus.x,
			world.get_surface_height(ruin_focus.x, ruin_focus.y) + 0.45,
			ruin_focus.y,
		))
		world.maintain_streaming(true)
		await physics_frame
		var ruin_data := _find_ruin_target(world, ruin_coord)
		_expect(not ruin_data.is_empty(), "The selected ruin lintel should stream for camera validation.")
		if not ruin_data.is_empty():
			_validate_blocked_line(
				camera,
				world,
				&"ruin",
				ruin_data.position,
				ruin_data.axis,
				14.0,
				14.0,
			)

	var tree_position: Vector3 = targets.get(&"tree", Vector3.ZERO)
	var clear_origin := tree_position - Vector3.RIGHT * 5.0
	var blocked_desired := tree_position + Vector3.RIGHT * 7.0
	camera._obstacle_distance_limit = INF
	var contracted: Vector3 = camera._resolve_obstacle_clearance(blocked_desired, clear_origin, 0.0, true)
	var clear_desired := clear_origin + Vector3.UP * 7.0
	var first_release: Vector3 = camera._resolve_obstacle_clearance(clear_desired, clear_origin, 0.1)
	_expect(
		clear_origin.distance_to(first_release) > clear_origin.distance_to(contracted)
			and clear_origin.distance_to(first_release) < clear_origin.distance_to(clear_desired),
		"Leaving obstacle cover should restore camera distance smoothly instead of popping outward.",
	)
	var released := first_release
	for _step in range(8):
		released = camera._resolve_obstacle_clearance(clear_desired, clear_origin, 0.1)
	_expect(
		clear_origin.distance_to(released) >= clear_origin.distance_to(clear_desired) - 0.02,
		"The chase camera should recover its full orbit distance after clearing the obstacle.",
	)

	if _failures.is_empty():
		print("Camera obstacle clearance passed — streamed tree, rock, and ruin sightlines contract safely and release smoothly.")
		scene.queue_free()
		await process_frame
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		scene.queue_free()
		await process_frame
		quit(1)


func _find_obstacle_targets(world: ProceduralDesert) -> Dictionary:
	var targets := {}
	var largest_rock_radius := 0.0
	for chunk_value in world.loaded_chunks.values():
		var chunk := chunk_value as StaticBody3D
		var forest := chunk.get_node_or_null("ForestObstacles") as StaticBody3D
		if forest != null and not targets.has(&"tree"):
			var tree_positions: PackedVector3Array = forest.get_meta(&"tree_positions", PackedVector3Array())
			if not tree_positions.is_empty():
				targets[&"tree"] = chunk.position + forest.position + tree_positions[0] + Vector3.UP * 2.5
		for child in chunk.get_children():
			var obstacle := child as StaticBody3D
			if obstacle == null or not obstacle.get_meta(&"overrush_rock", false):
				continue
			for obstacle_child in obstacle.get_children():
				var collision := obstacle_child as CollisionShape3D
				if collision == null or not collision.shape is SphereShape3D:
					continue
				var radius := (collision.shape as SphereShape3D).radius
				if radius > largest_rock_radius:
					largest_rock_radius = radius
					targets[&"rock"] = collision.global_position
	return targets


func _validate_blocked_line(
	camera: Camera3D,
	world: ProceduralDesert,
	obstacle_kind: StringName,
	target_position: Vector3,
	axis: Vector3,
	origin_distance: float,
	desired_distance: float,
) -> void:
	axis = axis.normalized()
	var sightline_origin := target_position - axis * origin_distance
	var desired_position := target_position + axis * desired_distance
	camera._obstacle_distance_limit = INF
	var hit: Dictionary = camera._find_obstacle_hit(sightline_origin, desired_position)
	_expect(
		not hit.is_empty() and world.get_obstacle_kind(hit.collider) == obstacle_kind,
		"The camera ray should identify the streamed %s collider." % obstacle_kind,
	)
	var resolved: Vector3 = camera._resolve_obstacle_clearance(
		desired_position,
		sightline_origin,
		0.0,
		true,
	)
	_expect(
		sightline_origin.distance_to(resolved) <= origin_distance - camera.obstacle_padding + 0.08,
		"The camera should contract in front of the %s rather than render through it."
		% obstacle_kind,
	)


func _find_nearest_ruin(world: ProceduralDesert) -> Vector2i:
	var best := Vector2i(2147483647, 2147483647)
	var best_distance := INF
	for y in range(-8, 9):
		for x in range(-8, 9):
			var coord := Vector2i(x, y)
			if not world.chunk_has_ruin(coord):
				continue
			var distance := Vector2(coord).length_squared()
			if distance < best_distance:
				best = coord
				best_distance = distance
	return best


func _find_ruin_target(world: ProceduralDesert, coord: Vector2i) -> Dictionary:
	for ruin in world.get_loaded_ruin_bodies():
		if ruin.name != "Ruin_%d_%d" % [coord.x, coord.y]:
			continue
		var lintel := ruin.get_node_or_null("LintelCollision") as CollisionShape3D
		if lintel != null:
			return {
				"position": lintel.global_position,
				"axis": ruin.global_basis.x.normalized(),
			}
	return {}


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
