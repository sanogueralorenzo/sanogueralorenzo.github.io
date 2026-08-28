extends SceneTree

const REPRESENTATIVE_SEEDS := [73013, 89173, 41777, 94631, 61813, 55217, 28411, 77543]
const FEATURE_SEARCH_RADIUS := 7
const LANDMARK_SEARCH_RADIUS := 7

var _failures: Array[String] = []
var _checked_resolved_obstacles := 0
var _protected_raw_candidates := 0
var _retained_resolved_obstacles := 0
var _audited_feature_lines := 0
var _audited_landmark_lines := 0
var _seen_raw_candidates := {}
var _seen_resolved_obstacles := {}


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	for world_seed in REPRESENTATIVE_SEEDS:
		var world := ProceduralDesert.new()
		world.seed = world_seed
		world.active_radius = 1
		root.add_child(world)
		await process_frame
		for kind in [DesertFeatureGrammar.KICKER, DesertFeatureGrammar.SPLIT_LINE]:
			var descriptor := _find_feature_descriptor(world._feature_grammar, kind)
			_expect(not descriptor.is_empty(), "Seed %d did not expose a nearby %s line." % [world_seed, kind])
			if descriptor.is_empty():
				continue
			_focus_without_horizon_rebuild(world, Vector2(descriptor.center))
			_audit_loaded_obstacles(world, "seed %d %s" % [world_seed, kind])
			_audited_feature_lines += 1

		var ruin_coord := _find_landmark_coord(world, true)
		_expect(ruin_coord != Vector2i(2147483647, 2147483647), "Seed %d did not expose a nearby ruin." % world_seed)
		if ruin_coord != Vector2i(2147483647, 2147483647):
			var ruin_center := world._landscape_layout.get_ruin_center(ruin_coord, world.chunk_size)
			var ruin_forward := world._landscape_layout.get_ruin_forward(ruin_coord, world.chunk_size)
			_expect(
				world._is_landmark_route_protected(ruin_center - ruin_forward * 135.0, 1.0)
					and world._is_landmark_route_protected(ruin_center + ruin_forward * 95.0, 1.0),
				"Seed %d ruin lacks a continuous approach and exit capsule." % world_seed,
			)
			_focus_without_horizon_rebuild(world, ruin_center)
			_audit_loaded_obstacles(world, "seed %d ruin" % world_seed)
			_audited_landmark_lines += 1

		var gate_coord := _find_landmark_coord(world, false)
		_expect(gate_coord != Vector2i(2147483647, 2147483647), "Seed %d did not expose a nearby rock passage." % world_seed)
		if gate_coord != Vector2i(2147483647, 2147483647):
			var gate_center := world._get_rock_passage_center(gate_coord)
			var gate_forward := world._get_rock_passage_forward(gate_coord)
			_expect(
				world._is_landmark_route_protected(gate_center - gate_forward * 95.0, 1.0)
					and world._is_landmark_route_protected(gate_center + gate_forward * 95.0, 1.0),
				"Seed %d rock passage lacks a continuous approach and exit capsule." % world_seed,
			)
			_focus_without_horizon_rebuild(world, gate_center)
			_audit_loaded_obstacles(world, "seed %d rock passage" % world_seed)
			_audited_landmark_lines += 1
		_expect(
			world._route_protection_cache.is_empty() and world._route_landmarks.is_empty(),
			"Seed %d retained ephemeral route-resolution state after chunk construction." % world_seed,
		)

		world.queue_free()
		await process_frame

	_expect(_audited_feature_lines == REPRESENTATIVE_SEEDS.size() * 2, "Every seed needs both authored line audits.")
	_expect(_audited_landmark_lines == REPRESENTATIVE_SEEDS.size() * 2, "Every seed needs both landmark line audits.")
	_expect(_protected_raw_candidates >= 120, "The audit should exercise meaningful route filtering, measured %d raw candidates." % _protected_raw_candidates)
	_expect(_checked_resolved_obstacles >= 500, "The resolved audit sampled too few obstacles: %d." % _checked_resolved_obstacles)
	_expect(_retained_resolved_obstacles >= 500, "Protected lines must retain substantial flank pressure: %d resolved obstacles." % _retained_resolved_obstacles)

	if _failures.is_empty():
		print(
			"Downhill line composition passed — %d authored and %d landmark lines across 8 seeds reject %d route candidates while retaining %d resolved flank obstacles."
			% [_audited_feature_lines, _audited_landmark_lines, _protected_raw_candidates, _retained_resolved_obstacles]
		)
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _find_feature_descriptor(grammar: DesertFeatureGrammar, kind: StringName) -> Dictionary:
	for radius in range(1, FEATURE_SEARCH_RADIUS + 1):
		for z_coord in range(-radius, radius + 1):
			for x_coord in range(-radius, radius + 1):
				if maxi(absi(x_coord), absi(z_coord)) != radius:
					continue
				var descriptor: Dictionary = grammar._get_descriptor(Vector2i(x_coord, z_coord))
				if descriptor.kind == kind and Vector2(descriptor.center).length() >= 620.0:
					return descriptor
	return {}


func _find_landmark_coord(world: ProceduralDesert, ruin: bool) -> Vector2i:
	for radius in range(2, LANDMARK_SEARCH_RADIUS + 1):
		for z_coord in range(-radius, radius + 1):
			for x_coord in range(-radius, radius + 1):
				if maxi(absi(x_coord), absi(z_coord)) != radius:
					continue
				var coord := Vector2i(x_coord, z_coord)
				if (ruin and world.chunk_has_ruin(coord)) or (not ruin and world.chunk_has_rock_passage(coord)):
					return coord
	return Vector2i(2147483647, 2147483647)


func _focus_without_horizon_rebuild(world: ProceduralDesert, logical_position: Vector2) -> void:
	world._stream_center = world.get_chunk_coordinate(logical_position)
	world._rebuild_stream_request()
	world._ensure_safety_chunks()
	world.flush_streaming()
	world._retire_distant_chunks()
	_count_protected_raw_candidates(world)


func _count_protected_raw_candidates(world: ProceduralDesert) -> void:
	for coord_value in world.loaded_chunks.keys():
		var coord := Vector2i(coord_value)
		var chunk_center := Vector2(coord) * world.chunk_size
		var half_size := world.chunk_size * 0.5
		var minimum_tree_cell := Vector2i(
			floori((chunk_center.x - half_size) / LandscapeLayout.TREE_CELL_SIZE) - 1,
			floori((chunk_center.y - half_size) / LandscapeLayout.TREE_CELL_SIZE) - 1,
		)
		var maximum_tree_cell := Vector2i(
			floori((chunk_center.x + half_size) / LandscapeLayout.TREE_CELL_SIZE) + 1,
			floori((chunk_center.y + half_size) / LandscapeLayout.TREE_CELL_SIZE) + 1,
		)
		for tree_y in range(minimum_tree_cell.y, maximum_tree_cell.y + 1):
			for tree_x in range(minimum_tree_cell.x, maximum_tree_cell.x + 1):
				var tree_cell := Vector2i(tree_x, tree_y)
				if not world._landscape_layout.has_tree(tree_cell):
					continue
				var tree_position := world._landscape_layout.get_tree_position(tree_cell)
				if world.get_chunk_coordinate(tree_position) != coord:
					continue
				var tree_radius := world._landscape_layout.get_tree_radius(tree_cell) * ProceduralDesert.TREE_COLLISION_RADIUS_FACTOR
				var tree_key := "%d:tree:%d:%d" % [world.generated_seed, tree_cell.x, tree_cell.y]
				if not _seen_raw_candidates.has(tree_key) and world.is_obstacle_route_protected(tree_position, tree_radius):
					_seen_raw_candidates[tree_key] = true
					_protected_raw_candidates += 1

		var minimum_rock_cell := Vector2i(
			floori((chunk_center.x - half_size) / LandscapeLayout.ROCK_CELL_SIZE) - 1,
			floori((chunk_center.y - half_size) / LandscapeLayout.ROCK_CELL_SIZE) - 1,
		)
		var maximum_rock_cell := Vector2i(
			floori((chunk_center.x + half_size) / LandscapeLayout.ROCK_CELL_SIZE) + 1,
			floori((chunk_center.y + half_size) / LandscapeLayout.ROCK_CELL_SIZE) + 1,
		)
		for rock_y in range(minimum_rock_cell.y, maximum_rock_cell.y + 1):
			for rock_x in range(minimum_rock_cell.x, maximum_rock_cell.x + 1):
				var rock_cell := Vector2i(rock_x, rock_y)
				if not world._landscape_layout.has_rock(rock_cell):
					continue
				var rock_position := world._landscape_layout.get_rock_position(rock_cell)
				if world.get_chunk_coordinate(rock_position) != coord:
					continue
				var rock_radius := world._landscape_layout.get_rock_radius(rock_cell) * ProceduralDesert.ROCK_COLLISION_RADIUS_FACTOR
				var rock_key := "%d:rock:%d:%d" % [world.generated_seed, rock_cell.x, rock_cell.y]
				if not _seen_raw_candidates.has(rock_key) and world.is_obstacle_route_protected(rock_position, rock_radius):
					_seen_raw_candidates[rock_key] = true
					_protected_raw_candidates += 1


func _audit_loaded_obstacles(world: ProceduralDesert, context: String) -> void:
	for chunk_value in world.loaded_chunks.values():
		var chunk := chunk_value as StaticBody3D
		for child in chunk.get_children():
			if child is StaticBody3D and child.get_meta(&"overrush_forest", false):
				var tree_positions: PackedVector3Array = child.get_meta(&"tree_positions", PackedVector3Array())
				var tree_radii: PackedFloat32Array = child.get_meta(&"tree_collision_radii", PackedFloat32Array())
				_expect(tree_positions.size() == tree_radii.size(), "%s has incomplete tree collision metadata." % context)
				for tree_index in range(mini(tree_positions.size(), tree_radii.size())):
					var logical_tree := world.get_world_position(chunk.global_position + tree_positions[tree_index])
					_audit_resolved_circle(world, Vector2(logical_tree.x, logical_tree.z), tree_radii[tree_index], context)
			elif child is StaticBody3D and child.get_meta(&"overrush_rock_field", false):
				for collision in child.get_children():
					if not collision is CollisionShape3D or not collision.shape is SphereShape3D:
						continue
					var logical_rock := world.get_world_position(collision.global_position)
					_audit_resolved_circle(world, Vector2(logical_rock.x, logical_rock.z), collision.shape.radius, context)


func _audit_resolved_circle(
	world: ProceduralDesert,
	logical_position: Vector2,
	collision_radius: float,
	context: String,
) -> void:
	var obstacle_key := "%d:%d:%d:%d" % [
		world.generated_seed,
		roundi(logical_position.x * 10.0),
		roundi(logical_position.y * 10.0),
		roundi(collision_radius * 100.0),
	]
	if _seen_resolved_obstacles.has(obstacle_key):
		return
	_seen_resolved_obstacles[obstacle_key] = true
	_checked_resolved_obstacles += 1
	_retained_resolved_obstacles += 1
	_expect(
		not world.is_obstacle_route_protected(logical_position, collision_radius),
		"%s retained a fatal obstacle at %s inside a protected downhill line." % [context, str(logical_position)],
	)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
