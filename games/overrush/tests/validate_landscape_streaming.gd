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
	await process_frame
	await physics_frame
	var world: ProceduralDesert = scene.get_node("Desert")
	var rider: Sandboarder = scene.get_node("Sandboarder")

	var initial_tree_count := world.get_loaded_tree_count()
	var initial_rock_count := world.get_loaded_rock_count()
	_expect(initial_tree_count >= 1500 and initial_tree_count <= 4200, "The opening stream should contain consequential forests with preserved glades: %d trees." % initial_tree_count)
	_expect(initial_rock_count >= 60 and initial_rock_count <= 500, "The opening stream should contain frequent but avoidable rock hazards: %d rocks." % initial_rock_count)
	_validate_loaded_trees(world)
	_validate_loaded_rocks(world)
	_validate_surface_feedback(world, rider)

	var ruin_coord := _find_nearest_ruin(world)
	_expect(ruin_coord != Vector2i(2147483647, 2147483647), "A sparse ruin site should exist within the first eight chunk rings.")
	if ruin_coord != Vector2i(2147483647, 2147483647):
		var ruin_focus := Vector2(ruin_coord) * world.chunk_size
		var logical_target := Vector3(ruin_focus.x, world.get_surface_height(ruin_focus.x, ruin_focus.y) + 0.45, ruin_focus.y)
		rider.global_position = world.world_to_local_position(logical_target)
		world.maintain_streaming(true)
		var ruins := world.get_loaded_ruin_bodies()
		var target_ruin: StaticBody3D
		for ruin in ruins:
			if ruin.name == "Ruin_%d_%d" % [ruin_coord.x, ruin_coord.y]:
				target_ruin = ruin
				break
		_expect(target_ruin != null, "The selected ruin should stream with its terrain chunk.")
		if target_ruin != null:
			_expect(world.is_obstacle_collider(target_ruin) and not world.is_rideable_collider(target_ruin), "Ruins must never refresh the air boost.")
			_expect(float(target_ruin.get_meta(&"passage_clearance", 0.0)) >= 13.0, "Ruin arches need a maximum-speed passage wider than 13 m.")
			_expect(int(target_ruin.get_meta(&"visual_segment_count", 0)) >= 34, "The ruin should render as a complete weathered arch-and-crest landmark, not five monolithic blocks.")
			var collision_count := 0
			for child in target_ruin.get_children():
				if child is CollisionShape3D:
					collision_count += 1
			_expect(collision_count == 5, "The landmark should remain one readable arch-and-terrace grammar, not a dense obstacle pile.")
		_validate_loaded_trees(world)

	paused = false
	scene.queue_free()
	await process_frame
	if _failures.is_empty():
		print("Landscape streaming passed — %d trees, %d rocks, fair obstacle spacing, biome feedback, and a sparse 13 m ruin passage." % [initial_tree_count, initial_rock_count])
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _validate_loaded_trees(world: ProceduralDesert) -> void:
	var positions: Array[Vector2] = []
	for chunk_value in world.loaded_chunks.values():
		var chunk: StaticBody3D = chunk_value
		var forest := chunk.get_node_or_null("ForestObstacles") as StaticBody3D
		if forest == null:
			continue
		_expect(world.is_obstacle_collider(forest) and not world.is_rideable_collider(forest), "Tree trunks must remain obstacle-only contact.")
		var forest_collision := forest.get_node_or_null("TreeCollision") as CollisionShape3D
		_expect(forest_collision != null and forest_collision.shape is ConcavePolygonShape3D, "Each forest chunk should consolidate its trunks into one static collision mesh.")
		_expect(
			forest_collision != null
				and forest_collision.shape is ConcavePolygonShape3D
				and (forest_collision.shape as ConcavePolygonShape3D).backface_collision,
			"Forest collision should answer rider and camera queries from either trunk face.",
		)
		_expect(forest.get_child_count() == 1, "Forest collision should not create one scene node per tree.")
		var tree_positions: PackedVector3Array = forest.get_meta(&"tree_positions", PackedVector3Array())
		_expect(tree_positions.size() == int(chunk.get_meta(&"tree_count", 0)), "Batched forest collision metadata must retain every deterministic tree center.")
		for tree_position in tree_positions:
			var local_position: Vector3 = chunk.position + forest.position + tree_position
			var logical_position3 := world.get_world_position(local_position)
			var logical_position := Vector2(logical_position3.x, logical_position3.z)
			positions.append(logical_position)
			_expect(world.get_grass_weight(logical_position) >= 0.58, "Trees must remain inside grass/forest terrain.")
			_expect(logical_position.length() >= LandscapeLayout.TREE_SUMMIT_CLEAR_RADIUS, "Trees must preserve the summit drop-in clearing.")
	var minimum_spacing := INF
	for first_index in range(positions.size()):
		for second_index in range(first_index + 1, positions.size()):
			minimum_spacing = minf(minimum_spacing, positions[first_index].distance_to(positions[second_index]))
	if positions.size() >= 2:
		_expect(minimum_spacing >= 9.0, "Tree placement leaves less than 9 m between trunk centers: %.2f m." % minimum_spacing)


func _validate_loaded_rocks(world: ProceduralDesert) -> void:
	var field_body_count := 0
	var collision_count := 0
	for rock_body in world.get_loaded_rock_bodies():
		_expect(world.is_obstacle_collider(rock_body) and not world.is_rideable_collider(rock_body), "Every tree/rock hazard must be obstacle-only contact.")
		if not rock_body.get_meta(&"overrush_rock_field", false):
			continue
		field_body_count += 1
		for child in rock_body.get_children():
			if child is CollisionShape3D:
				collision_count += 1
	_expect(field_body_count >= 4, "Several streamed chunks should contain batched rock fields.")
	_expect(collision_count >= 40, "Rock-field collision should match the visible hazard density: %d shapes." % collision_count)


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


func _validate_surface_feedback(world: ProceduralDesert, rider: Sandboarder) -> void:
	var dune_point := _find_biome_point(world, false)
	var grass_point := _find_biome_point(world, true)
	_expect(dune_point != Vector2(INF, INF), "A nearby clear dune region is required to verify surface feedback.")
	_expect(grass_point != Vector2(INF, INF), "A nearby clear grass region is required to verify surface feedback.")
	if dune_point == Vector2(INF, INF) or grass_point == Vector2(INF, INF):
		return
	_place_rider_for_feedback(world, rider, dune_point)
	var dune_weight := rider._surface_grass_weight
	var dune_color := (rider.surface_trail.process_material as ParticleProcessMaterial).color
	_place_rider_for_feedback(world, rider, grass_point)
	var grass_weight := rider._surface_grass_weight
	var grass_color := (rider.surface_trail.process_material as ParticleProcessMaterial).color
	_expect(dune_weight <= 0.05 and grass_weight >= 0.95, "The movement wake must follow the actual contacted biome.")
	var color_difference := (
		absf(dune_color.r - grass_color.r)
		+ absf(dune_color.g - grass_color.g)
		+ absf(dune_color.b - grass_color.b)
	)
	_expect(color_difference >= 0.35, "Dune and grass movement wakes must remain visibly distinct.")


func _find_biome_point(world: ProceduralDesert, find_grass: bool) -> Vector2:
	for distance in range(300, 5001, 40):
		for direction_index in range(8):
			var angle := TAU * float(direction_index) / 8.0
			var point := Vector2(cos(angle), sin(angle)) * float(distance)
			var grass_weight := world.get_grass_weight(point)
			if (find_grass and grass_weight >= 0.98) or (not find_grass and grass_weight <= 0.02):
				return point
	return Vector2(INF, INF)


func _place_rider_for_feedback(world: ProceduralDesert, rider: Sandboarder, logical_xz: Vector2) -> void:
	var logical_position := Vector3(
		logical_xz.x,
		world.get_surface_height(logical_xz.x, logical_xz.y) + 0.45,
		logical_xz.y,
	)
	rider.global_position = world.world_to_local_position(logical_position)
	rider._update_surface_effect_palette()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
