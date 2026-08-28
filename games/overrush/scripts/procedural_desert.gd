class_name ProceduralDesert
extends StaticBody3D

const TREE_CROWN_LAYERS := 3

@export var tracked_body_path: NodePath
@export var tracked_camera_path: NodePath
@export_range(192.0, 768.0, 32.0) var chunk_size := 384.0
@export_range(25, 97, 8) var chunk_resolution := 65
@export_range(1, 4, 1) var active_radius := 2
@export_range(1, 4, 1) var chunks_per_frame := 2
@export var rebase_distance := 1536.0
@export var seed := 0
@export var summit_height := 520.0
@export var radial_grade := 0.34

var generated_seed := 0
var world_origin := Vector3.ZERO
var loaded_chunks: Dictionary = {}

var _tracked_body: Node3D
var _tracked_camera: Node3D
var _stream_center := Vector2i(2147483647, 2147483647)
var _desired_chunks: Dictionary = {}
var _pending_chunks: Array[Vector2i] = []
var _terrain_material: ShaderMaterial
var _rock_material: StandardMaterial3D
var _tree_trunk_material: StandardMaterial3D
var _tree_canopy_material: StandardMaterial3D
var _ruin_material: StandardMaterial3D
var _rock_mesh: SphereMesh
var _tree_trunk_mesh: CylinderMesh
var _tree_canopy_mesh: SphereMesh
var _ruin_block_mesh: BoxMesh
var _broad_noise := FastNoiseLite.new()
var _mountain_noise := FastNoiseLite.new()
var _ridge_noise := FastNoiseLite.new()
var _dune_noise := FastNoiseLite.new()
var _feature_grammar := DesertFeatureGrammar.new()
var _landscape_layout := LandscapeLayout.new()
var _mountain_fold_phase := Vector2.ZERO


func _ready() -> void:
	_tracked_body = get_node_or_null(tracked_body_path)
	_tracked_camera = get_node_or_null(tracked_camera_path)
	generate()


func _physics_process(_delta: float) -> void:
	maintain_streaming(false)


func generate() -> void:
	_clear_chunks()
	world_origin = Vector3.ZERO
	generated_seed = seed
	if generated_seed == 0:
		var random_seed := RandomNumberGenerator.new()
		random_seed.randomize()
		generated_seed = random_seed.randi()
	_configure_noise()
	_feature_grammar.configure(generated_seed)
	_landscape_layout.configure(generated_seed)
	_create_materials()
	_stream_center = Vector2i(2147483647, 2147483647)
	_set_stream_focus(Vector2.ZERO, true)
	print(
		"Overrush terrain — seed %s, %d seamless chunks around an unbounded radial field"
		% [str(generated_seed), loaded_chunks.size()]
	)


func begin_new_run() -> void:
	generate()


func maintain_streaming(immediate: bool = false) -> void:
	if not is_instance_valid(_tracked_body):
		return
	var logical_position := get_world_position(_tracked_body.global_position)
	if Vector2(_tracked_body.global_position.x, _tracked_body.global_position.z).length() >= rebase_distance:
		_perform_origin_rebase(_tracked_body.global_position)
	_set_stream_focus(Vector2(logical_position.x, logical_position.z), immediate)


func get_spawn_position() -> Vector3:
	return world_to_local_position(Vector3(0.0, get_surface_height(0.0, 0.0) + 0.45, 0.0))


func get_world_position(local_position: Vector3) -> Vector3:
	return local_position + world_origin


func world_to_local_position(logical_position: Vector3) -> Vector3:
	return logical_position - world_origin


func get_surface_height(x: float, z: float) -> float:
	var radius := Vector2(x, z).length()
	var softened_radius := sqrt(radius * radius + 90.0 * 90.0) - 90.0
	var descent := softened_radius * radial_grade
	var feature_fade := smoothstep(55.0, 230.0, radius)
	var mountain_relief := _mountain_noise.get_noise_2d(x, z) * 92.0
	var mountain_folds := (
		sin(x * 0.0014 + z * 0.0005 + _mountain_fold_phase.x) * 62.0
		+ sin(x * -0.00055 + z * 0.0011 + _mountain_fold_phase.y) * 48.0
	)
	var broad := _broad_noise.get_noise_2d(x, z) * 48.0
	var ridges := _ridge_noise.get_noise_2d(x, z)
	var folded_ridges := signf(ridges) * ridges * ridges * 34.0
	var dunes := _dune_noise.get_noise_2d(x, z) * 10.5
	var authored_feature := _feature_grammar.sample_height_offset(x, z)
	return summit_height - descent + feature_fade * (mountain_relief + mountain_folds + broad + folded_ridges + dunes + authored_feature)


func get_local_surface_height(x: float, z: float) -> float:
	var logical := get_world_position(Vector3(x, 0.0, z))
	return get_surface_height(logical.x, logical.z) - world_origin.y


func get_surface_normal(x: float, z: float, sample_distance := 3.0) -> Vector3:
	var left := get_surface_height(x - sample_distance, z)
	var right := get_surface_height(x + sample_distance, z)
	var back := get_surface_height(x, z - sample_distance)
	var forward := get_surface_height(x, z + sample_distance)
	return Vector3(left - right, sample_distance * 2.0, back - forward).normalized()


func is_rideable_collider(collider: Object) -> bool:
	return collider is StaticBody3D and collider.get_meta(&"overrush_rideable", false)


func is_obstacle_collider(collider: Object) -> bool:
	return collider is StaticBody3D and collider.get_meta(&"overrush_obstacle", false)


func get_obstacle_kind(collider: Object) -> StringName:
	if not is_obstacle_collider(collider):
		return &"terrain"
	if collider.get_meta(&"overrush_forest", false):
		return &"tree"
	if collider.get_meta(&"overrush_rock", false):
		return &"rock"
	if collider.get_meta(&"overrush_ruin", false):
		return &"ruin"
	return &"obstacle"


func get_feature_kind_at(logical_position: Vector2) -> StringName:
	return _feature_grammar.get_feature_kind_at(logical_position)


func get_feature_height_offset(logical_position: Vector2) -> float:
	return _feature_grammar.sample_height_offset(logical_position.x, logical_position.y)


func get_grass_weight(logical_position: Vector2) -> float:
	return _landscape_layout.get_grass_weight(logical_position)


func chunk_has_ruin(coord: Vector2i) -> bool:
	return _landscape_layout.has_ruin(coord, chunk_size)


func chunk_has_rock_passage(coord: Vector2i) -> bool:
	return (
		not chunk_has_ruin(coord)
		and Vector2(coord).length() * chunk_size >= 420.0
		and _feature_grammar.get_cell_random(coord, 31) <= 0.38
	)


func get_loaded_rock_bodies() -> Array[StaticBody3D]:
	var rocks: Array[StaticBody3D] = []
	for chunk_value in loaded_chunks.values():
		var chunk: StaticBody3D = chunk_value
		for child in chunk.get_children():
			if child is StaticBody3D and child.get_meta(&"overrush_rock", false):
				rocks.append(child)
	return rocks


func get_loaded_rock_gate_bodies() -> Array[StaticBody3D]:
	var gates: Array[StaticBody3D] = []
	for rock in get_loaded_rock_bodies():
		if rock.get_meta(&"overrush_rock_gate", false):
			gates.append(rock)
	return gates


func get_loaded_rock_count() -> int:
	var total := 0
	for chunk_value in loaded_chunks.values():
		var chunk := chunk_value as StaticBody3D
		total += int(chunk.get_meta(&"rock_count", 0))
		for child in chunk.get_children():
			if child is StaticBody3D and child.get_meta(&"overrush_rock_gate", false):
				total += 1
	return total


func get_loaded_tree_count() -> int:
	var total := 0
	for chunk_value in loaded_chunks.values():
		total += int((chunk_value as StaticBody3D).get_meta(&"tree_count", 0))
	return total


func get_loaded_ruin_bodies() -> Array[StaticBody3D]:
	var ruins: Array[StaticBody3D] = []
	for chunk_value in loaded_chunks.values():
		var chunk: StaticBody3D = chunk_value
		for child in chunk.get_children():
			if child is StaticBody3D and child.get_meta(&"overrush_ruin", false):
				ruins.append(child)
	return ruins


func get_chunk_coordinate(logical_position: Vector2) -> Vector2i:
	return Vector2i(
		roundi(logical_position.x / chunk_size),
		roundi(logical_position.y / chunk_size),
	)


func get_chunk(coord: Vector2i) -> StaticBody3D:
	return loaded_chunks.get(coord) as StaticBody3D


func flush_streaming() -> void:
	while not _pending_chunks.is_empty():
		_load_chunk(_pending_chunks.pop_front())


func _set_stream_focus(logical_position: Vector2, immediate: bool) -> void:
	var next_center := get_chunk_coordinate(logical_position)
	if next_center != _stream_center:
		_stream_center = next_center
		_rebuild_stream_request()
		_ensure_safety_chunks()
		_retire_distant_chunks()
	if immediate:
		flush_streaming()
	else:
		for _index in range(chunks_per_frame):
			if _pending_chunks.is_empty():
				break
			_load_chunk(_pending_chunks.pop_front())


func _rebuild_stream_request() -> void:
	_desired_chunks.clear()
	_pending_chunks.clear()
	for z_offset in range(-active_radius, active_radius + 1):
		for x_offset in range(-active_radius, active_radius + 1):
			var coord := _stream_center + Vector2i(x_offset, z_offset)
			_desired_chunks[coord] = true
			if not loaded_chunks.has(coord):
				_pending_chunks.append(coord)
	_pending_chunks.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return _chunk_distance_squared(a) < _chunk_distance_squared(b)
	)


func _ensure_safety_chunks() -> void:
	for z_offset in range(-1, 2):
		for x_offset in range(-1, 2):
			var coord := _stream_center + Vector2i(x_offset, z_offset)
			if not loaded_chunks.has(coord):
				_load_chunk(coord)
			_pending_chunks.erase(coord)


func _retire_distant_chunks() -> void:
	var retention_radius := active_radius + 1
	for key in loaded_chunks.keys():
		var coord: Vector2i = key
		if absi(coord.x - _stream_center.x) <= retention_radius and absi(coord.y - _stream_center.y) <= retention_radius:
			continue
		var chunk: StaticBody3D = loaded_chunks[coord]
		loaded_chunks.erase(coord)
		chunk.queue_free()


func _load_chunk(coord: Vector2i) -> void:
	if loaded_chunks.has(coord) or not _desired_chunks.has(coord):
		return
	var chunk := StaticBody3D.new()
	chunk.name = "Terrain_%d_%d" % [coord.x, coord.y]
	chunk.set_meta(&"overrush_rideable", true)
	var center_x := float(coord.x) * chunk_size
	var center_z := float(coord.y) * chunk_size
	var reference_height := get_surface_height(center_x, center_z)
	chunk.position = Vector3(
		center_x - world_origin.x,
		reference_height - world_origin.y,
		center_z - world_origin.z,
	)
	var chunk_data := _build_chunk_mesh(coord, reference_height)
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Terrain"
	mesh_instance.mesh = chunk_data.mesh
	mesh_instance.material_override = _terrain_material
	chunk.add_child(mesh_instance)
	var collision := CollisionShape3D.new()
	collision.name = "TerrainCollision"
	collision.shape = _build_chunk_collision(chunk_data.heights)
	var spacing := chunk_size / float(chunk_resolution - 1)
	collision.scale = Vector3(spacing, 1.0, spacing)
	chunk.add_child(collision)
	_add_forest(chunk, coord, reference_height)
	_add_ruin(chunk, coord, reference_height)
	_add_rock_field(chunk, coord, reference_height)
	_add_rock_passage(chunk, coord, reference_height)
	add_child(chunk)
	loaded_chunks[coord] = chunk


func _build_chunk_mesh(coord: Vector2i, reference_height: float) -> Dictionary:
	var vertex_count := chunk_resolution * chunk_resolution
	var spacing := chunk_size / float(chunk_resolution - 1)
	var half_size := chunk_size * 0.5
	var center_x := float(coord.x) * chunk_size
	var center_z := float(coord.y) * chunk_size
	var heights := PackedFloat32Array()
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	heights.resize(vertex_count)
	vertices.resize(vertex_count)
	normals.resize(vertex_count)
	uvs.resize(vertex_count)
	colors.resize(vertex_count)

	for z_index in range(chunk_resolution):
		var local_z := -half_size + z_index * spacing
		var logical_z := center_z + local_z
		for x_index in range(chunk_resolution):
			var local_x := -half_size + x_index * spacing
			var logical_x := center_x + local_x
			var index := z_index * chunk_resolution + x_index
			var local_height := get_surface_height(logical_x, logical_z) - reference_height
			heights[index] = local_height
			vertices[index] = Vector3(local_x, local_height, local_z)
			normals[index] = get_surface_normal(logical_x, logical_z, spacing)
			uvs[index] = Vector2(logical_x, logical_z) * 0.002
			colors[index] = Color(_landscape_layout.get_grass_weight(Vector2(logical_x, logical_z)), 0.0, 0.0, 1.0)

	var indices := PackedInt32Array()
	indices.resize((chunk_resolution - 1) * (chunk_resolution - 1) * 6)
	var write_index := 0
	for z_index in range(chunk_resolution - 1):
		for x_index in range(chunk_resolution - 1):
			var top_left := z_index * chunk_resolution + x_index
			var top_right := top_left + 1
			var bottom_left := top_left + chunk_resolution
			var bottom_right := bottom_left + 1
			indices[write_index] = top_left
			indices[write_index + 1] = top_right
			indices[write_index + 2] = bottom_left
			indices[write_index + 3] = top_right
			indices[write_index + 4] = bottom_right
			indices[write_index + 5] = bottom_left
			write_index += 6

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return {"mesh": mesh, "heights": heights}


func _build_chunk_collision(heights: PackedFloat32Array) -> HeightMapShape3D:
	var heightmap := HeightMapShape3D.new()
	heightmap.map_width = chunk_resolution
	heightmap.map_depth = chunk_resolution
	heightmap.map_data = heights
	return heightmap


func _perform_origin_rebase(local_focus: Vector3) -> void:
	var shift := Vector3(
		roundf(local_focus.x / chunk_size) * chunk_size,
		local_focus.y,
		roundf(local_focus.z / chunk_size) * chunk_size,
	)
	if shift.length_squared() < 0.001:
		return
	world_origin += shift
	for chunk in loaded_chunks.values():
		(chunk as StaticBody3D).position -= shift
	if _tracked_body.has_method("apply_world_rebase"):
		_tracked_body.call("apply_world_rebase", shift)
	else:
		_tracked_body.global_position -= shift
	if is_instance_valid(_tracked_camera):
		if _tracked_camera.has_method("apply_world_rebase"):
			_tracked_camera.call("apply_world_rebase", shift)
		else:
			_tracked_camera.global_position -= shift
	if is_instance_valid(_terrain_material):
		_terrain_material.set_shader_parameter("world_origin", Vector2(world_origin.x, world_origin.z))


func _chunk_distance_squared(coord: Vector2i) -> int:
	var delta := coord - _stream_center
	return delta.x * delta.x + delta.y * delta.y


func _configure_noise() -> void:
	_mountain_fold_phase = Vector2(
		float(posmod(generated_seed, 997)) / 997.0 * TAU,
		float(posmod(generated_seed, 619)) / 619.0 * TAU,
	)
	_mountain_noise.seed = generated_seed ^ 0x6A1B9D
	_mountain_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_mountain_noise.frequency = 0.00043
	_mountain_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_mountain_noise.fractal_octaves = 3
	_mountain_noise.fractal_gain = 0.46

	_broad_noise.seed = generated_seed ^ 0x13579B
	_broad_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_broad_noise.frequency = 0.00105
	_broad_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_broad_noise.fractal_octaves = 4
	_broad_noise.fractal_gain = 0.43

	_ridge_noise.seed = generated_seed ^ 0x2468AC
	_ridge_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_ridge_noise.frequency = 0.00175
	_ridge_noise.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_ridge_noise.fractal_octaves = 3
	_ridge_noise.fractal_gain = 0.38

	_dune_noise.seed = generated_seed ^ 0x55AA31
	_dune_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_dune_noise.frequency = 0.0042
	_dune_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_dune_noise.fractal_octaves = 2
	_dune_noise.fractal_gain = 0.34


func _create_materials() -> void:
	_terrain_material = null
	_rock_material = null
	_tree_trunk_material = null
	_tree_canopy_material = null
	_ruin_material = null
	_rock_mesh = SphereMesh.new()
	_rock_mesh.radius = 1.0
	_rock_mesh.height = 2.0
	_rock_mesh.radial_segments = 12
	_rock_mesh.rings = 6
	_tree_trunk_mesh = CylinderMesh.new()
	_tree_trunk_mesh.top_radius = 0.72
	_tree_trunk_mesh.bottom_radius = 1.0
	_tree_trunk_mesh.height = 1.0
	_tree_trunk_mesh.radial_segments = 9
	_tree_trunk_mesh.rings = 1
	_tree_canopy_mesh = SphereMesh.new()
	_tree_canopy_mesh.radius = 1.0
	_tree_canopy_mesh.height = 2.0
	_tree_canopy_mesh.radial_segments = 10
	_tree_canopy_mesh.rings = 5
	_ruin_block_mesh = BoxMesh.new()
	_ruin_block_mesh.size = Vector3.ONE
	if DisplayServer.get_name() != "headless":
		_terrain_material = ShaderMaterial.new()
		_terrain_material.shader = load("res://shaders/desert.gdshader")
		_terrain_material.set_shader_parameter("seed_offset", Vector2(generated_seed % 997, generated_seed % 619))
		_terrain_material.set_shader_parameter("world_origin", Vector2.ZERO)
		_terrain_material.set_shader_parameter("sand_albedo", load("res://assets/terrain/wind_sand_albedo.png"))
		_terrain_material.set_shader_parameter("grass_albedo", load("res://assets/terrain/alpine_grass_albedo.png"))
		_rock_material = StandardMaterial3D.new()
		_rock_material.albedo_color = Color("#51495d")
		_rock_material.roughness = 0.94
		_rock_material.vertex_color_use_as_albedo = true
		_rock_material.emission_enabled = true
		_rock_material.emission = Color("#15121b")
		_rock_material.emission_energy_multiplier = 0.32
		_tree_trunk_material = StandardMaterial3D.new()
		_tree_trunk_material.albedo_color = Color("#70452d")
		_tree_trunk_material.roughness = 0.96
		_tree_trunk_material.vertex_color_use_as_albedo = true
		_tree_canopy_material = StandardMaterial3D.new()
		_tree_canopy_material.albedo_color = Color("#4f8848")
		_tree_canopy_material.roughness = 0.92
		_tree_canopy_material.vertex_color_use_as_albedo = true
		_ruin_material = StandardMaterial3D.new()
		_ruin_material.albedo_color = Color("#c1b27f")
		_ruin_material.roughness = 0.92
		_ruin_material.emission_enabled = true
		_ruin_material.emission = Color("#443b29")
		_ruin_material.emission_energy_multiplier = 0.8


func _add_forest(chunk: StaticBody3D, coord: Vector2i, reference_height: float) -> void:
	var chunk_center := Vector2(coord) * chunk_size
	var half_size := chunk_size * 0.5
	var cell_size := LandscapeLayout.TREE_CELL_SIZE
	var minimum_cell := Vector2i(
		floori((chunk_center.x - half_size) / cell_size) - 1,
		floori((chunk_center.y - half_size) / cell_size) - 1,
	)
	var maximum_cell := Vector2i(
		floori((chunk_center.x + half_size) / cell_size) + 1,
		floori((chunk_center.y + half_size) / cell_size) + 1,
	)
	var ruin_center := _landscape_layout.get_ruin_center(coord, chunk_size) if chunk_has_ruin(coord) else Vector2(INF, INF)
	var rock_center := _get_rock_passage_center(coord) if chunk_has_rock_passage(coord) else Vector2(INF, INF)
	var trees: Array[Dictionary] = []
	for cell_y in range(minimum_cell.y, maximum_cell.y + 1):
		for cell_x in range(minimum_cell.x, maximum_cell.x + 1):
			var cell := Vector2i(cell_x, cell_y)
			if not _landscape_layout.has_tree(cell):
				continue
			var logical_position := _landscape_layout.get_tree_position(cell)
			if get_chunk_coordinate(logical_position) != coord:
				continue
			if logical_position.distance_to(ruin_center) < 36.0 or logical_position.distance_to(rock_center) < 28.0:
				continue
			if _has_scattered_rock_near(logical_position, 9.0):
				continue
			trees.append({
				"cell": cell,
				"position": logical_position,
				"height": _landscape_layout.get_tree_height(cell),
				"radius": _landscape_layout.get_tree_radius(cell),
			})
	chunk.set_meta(&"tree_count", trees.size())
	if trees.is_empty():
		return

	var obstacles := StaticBody3D.new()
	obstacles.name = "ForestObstacles"
	obstacles.set_meta(&"overrush_obstacle", true)
	obstacles.set_meta(&"overrush_forest", true)
	for tree_index in range(trees.size()):
		var tree := trees[tree_index]
		var logical_position: Vector2 = tree.position
		var height: float = tree.height
		var radius: float = tree.radius
		var local_height := get_surface_height(logical_position.x, logical_position.y) - reference_height
		var collision := CollisionShape3D.new()
		collision.name = "Tree_%d" % tree_index
		var shape := CylinderShape3D.new()
		shape.radius = radius * 1.12
		shape.height = maxf(4.8, height * 0.7)
		collision.shape = shape
		collision.position = Vector3(
			logical_position.x - chunk_center.x,
			local_height + shape.height * 0.5,
			logical_position.y - chunk_center.y,
		)
		obstacles.add_child(collision)
	chunk.add_child(obstacles)

	if DisplayServer.get_name() == "headless":
		return
	var trunk_multimesh := MultiMesh.new()
	trunk_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	trunk_multimesh.use_colors = true
	trunk_multimesh.mesh = _tree_trunk_mesh
	trunk_multimesh.instance_count = trees.size()
	var canopy_multimesh := MultiMesh.new()
	canopy_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	canopy_multimesh.use_colors = true
	canopy_multimesh.mesh = _tree_canopy_mesh
	canopy_multimesh.instance_count = trees.size() * TREE_CROWN_LAYERS
	for tree_index in range(trees.size()):
		var tree := trees[tree_index]
		var cell: Vector2i = tree.cell
		var logical_position: Vector2 = tree.position
		var height: float = tree.height
		var radius: float = tree.radius
		var local_height := get_surface_height(logical_position.x, logical_position.y) - reference_height
		var local_xz := logical_position - chunk_center
		var trunk_transform := Transform3D(
			Basis.IDENTITY.scaled(Vector3(radius, height, radius)),
			Vector3(local_xz.x, local_height + height * 0.5, local_xz.y),
		)
		var canopy_radius := height * lerpf(0.21, 0.28, _landscape_layout.get_cell_random(cell, 16))
		var crown_angle := _landscape_layout.get_cell_random(cell, 17) * TAU
		var crown_offset := Vector2(cos(crown_angle), sin(crown_angle)) * canopy_radius * 0.18
		var crown_basis := Basis(Vector3.UP, crown_angle)
		var lower_canopy := Transform3D(
			crown_basis.scaled(Vector3(canopy_radius, height * 0.2, canopy_radius * 0.86)),
			Vector3(local_xz.x - crown_offset.x, local_height + height * 0.58, local_xz.y - crown_offset.y),
		)
		var middle_canopy := Transform3D(
			crown_basis.scaled(Vector3(canopy_radius * 0.84, height * 0.17, canopy_radius * 0.76)),
			Vector3(local_xz.x + crown_offset.x, local_height + height * 0.76, local_xz.y + crown_offset.y),
		)
		var upper_canopy := Transform3D(
			crown_basis.scaled(Vector3(canopy_radius * 0.58, height * 0.13, canopy_radius * 0.55)),
			Vector3(local_xz.x, local_height + height * 0.91, local_xz.y),
		)
		trunk_multimesh.set_instance_transform(tree_index, trunk_transform)
		trunk_multimesh.set_instance_color(tree_index, Color(0.82, 0.74, 0.67, 1.0))
		var tint := lerpf(0.78, 1.08, _landscape_layout.get_cell_random(cell, 18))
		var canopy_color := Color(tint * 0.78, tint, tint * 0.72, 1.0)
		canopy_multimesh.set_instance_transform(tree_index * 3, lower_canopy)
		canopy_multimesh.set_instance_color(tree_index * 3, canopy_color.darkened(0.04))
		canopy_multimesh.set_instance_transform(tree_index * 3 + 1, middle_canopy)
		canopy_multimesh.set_instance_color(tree_index * 3 + 1, canopy_color)
		canopy_multimesh.set_instance_transform(tree_index * 3 + 2, upper_canopy)
		canopy_multimesh.set_instance_color(tree_index * 3 + 2, canopy_color.lightened(0.08))
	var trunks := MultiMeshInstance3D.new()
	trunks.name = "TreeTrunks"
	trunks.multimesh = trunk_multimesh
	trunks.material_override = _tree_trunk_material
	chunk.add_child(trunks)
	var canopies := MultiMeshInstance3D.new()
	canopies.name = "TreeCanopies"
	canopies.multimesh = canopy_multimesh
	canopies.material_override = _tree_canopy_material
	chunk.add_child(canopies)


func _add_rock_field(chunk: StaticBody3D, coord: Vector2i, reference_height: float) -> void:
	var chunk_center := Vector2(coord) * chunk_size
	var half_size := chunk_size * 0.5
	var cell_size := LandscapeLayout.ROCK_CELL_SIZE
	var minimum_cell := Vector2i(
		floori((chunk_center.x - half_size) / cell_size) - 1,
		floori((chunk_center.y - half_size) / cell_size) - 1,
	)
	var maximum_cell := Vector2i(
		floori((chunk_center.x + half_size) / cell_size) + 1,
		floori((chunk_center.y + half_size) / cell_size) + 1,
	)
	var ruin_center := _landscape_layout.get_ruin_center(coord, chunk_size) if chunk_has_ruin(coord) else Vector2(INF, INF)
	var gate_center := _get_rock_passage_center(coord) if chunk_has_rock_passage(coord) else Vector2(INF, INF)
	var rocks: Array[Dictionary] = []
	for cell_y in range(minimum_cell.y, maximum_cell.y + 1):
		for cell_x in range(minimum_cell.x, maximum_cell.x + 1):
			var cell := Vector2i(cell_x, cell_y)
			if not _landscape_layout.has_rock(cell):
				continue
			var logical_position := _landscape_layout.get_rock_position(cell)
			if get_chunk_coordinate(logical_position) != coord:
				continue
			var radius := _landscape_layout.get_rock_radius(cell)
			if logical_position.distance_to(ruin_center) < 38.0 or logical_position.distance_to(gate_center) < 32.0:
				continue
			if _has_tree_near(logical_position, radius + 4.5):
				continue
			rocks.append({"cell": cell, "position": logical_position, "radius": radius})
	chunk.set_meta(&"rock_count", rocks.size())
	if rocks.is_empty():
		return

	var obstacles := StaticBody3D.new()
	obstacles.name = "RockFieldObstacles"
	obstacles.set_meta(&"overrush_obstacle", true)
	obstacles.set_meta(&"overrush_rock", true)
	obstacles.set_meta(&"overrush_rock_field", true)
	for rock_index in range(rocks.size()):
		var rock := rocks[rock_index]
		var logical_position: Vector2 = rock.position
		var radius: float = rock.radius
		var collision := CollisionShape3D.new()
		collision.name = "Rock_%d" % rock_index
		var shape := SphereShape3D.new()
		shape.radius = radius * 0.82
		collision.shape = shape
		collision.position = Vector3(
			logical_position.x - chunk_center.x,
			get_surface_height(logical_position.x, logical_position.y) - reference_height + radius * 0.48,
			logical_position.y - chunk_center.y,
		)
		obstacles.add_child(collision)
	chunk.add_child(obstacles)

	if DisplayServer.get_name() == "headless":
		return
	var rock_multimesh := MultiMesh.new()
	rock_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	rock_multimesh.use_colors = true
	rock_multimesh.mesh = _rock_mesh
	rock_multimesh.instance_count = rocks.size()
	for rock_index in range(rocks.size()):
		var rock := rocks[rock_index]
		var cell: Vector2i = rock.cell
		var logical_position: Vector2 = rock.position
		var radius: float = rock.radius
		var local_xz := logical_position - chunk_center
		var rock_basis := Basis(Vector3.UP, _landscape_layout.get_cell_random(cell, 58) * TAU)
		rock_basis = rock_basis.scaled(Vector3(
			radius * lerpf(0.82, 1.28, _landscape_layout.get_cell_random(cell, 55)),
			radius * lerpf(0.62, 1.05, _landscape_layout.get_cell_random(cell, 56)),
			radius * lerpf(0.82, 1.2, _landscape_layout.get_cell_random(cell, 57)),
		))
		rock_multimesh.set_instance_transform(rock_index, Transform3D(
			rock_basis,
			Vector3(
				local_xz.x,
				get_surface_height(logical_position.x, logical_position.y) - reference_height + radius * 0.48,
				local_xz.y,
			),
		))
		var tint := lerpf(0.72, 1.08, _landscape_layout.get_cell_random(cell, 59))
		rock_multimesh.set_instance_color(rock_index, Color(tint * 0.9, tint * 0.86, tint, 1.0))
	var visuals := MultiMeshInstance3D.new()
	visuals.name = "RockFieldVisuals"
	visuals.multimesh = rock_multimesh
	visuals.material_override = _rock_material
	chunk.add_child(visuals)


func _has_tree_near(logical_position: Vector2, clearance: float) -> bool:
	var center_cell := _landscape_layout.get_tree_cell_coordinate(logical_position)
	for y_offset in range(-1, 2):
		for x_offset in range(-1, 2):
			var cell := center_cell + Vector2i(x_offset, y_offset)
			if _landscape_layout.has_tree(cell) and _landscape_layout.get_tree_position(cell).distance_to(logical_position) < clearance:
				return true
	return false


func _has_scattered_rock_near(logical_position: Vector2, clearance: float) -> bool:
	var center_cell := _landscape_layout.get_rock_cell_coordinate(logical_position)
	for y_offset in range(-1, 2):
		for x_offset in range(-1, 2):
			var cell := center_cell + Vector2i(x_offset, y_offset)
			if not _landscape_layout.has_rock(cell):
				continue
			var rock_position := _landscape_layout.get_rock_position(cell)
			if rock_position.distance_to(logical_position) < clearance + _landscape_layout.get_rock_radius(cell):
				return true
	return false


func _add_ruin(chunk: StaticBody3D, coord: Vector2i, reference_height: float) -> void:
	if not chunk_has_ruin(coord):
		return
	var chunk_center := Vector2(coord) * chunk_size
	var ruin_center := _landscape_layout.get_ruin_center(coord, chunk_size)
	var forward := _landscape_layout.get_ruin_forward(coord, chunk_size)
	var ruin := StaticBody3D.new()
	ruin.name = "Ruin_%d_%d" % [coord.x, coord.y]
	ruin.position = Vector3(ruin_center.x - chunk_center.x, 0.0, ruin_center.y - chunk_center.y)
	ruin.rotation.y = atan2(-forward.x, -forward.y)
	ruin.set_meta(&"overrush_obstacle", true)
	ruin.set_meta(&"overrush_ruin", true)
	ruin.set_meta(&"passage_clearance", 13.6)
	_add_ruin_block(ruin, chunk_center, reference_height, ruin_center, forward, Vector2(-8.0, 0.0), Vector3(2.4, 7.0, 2.8), 0.0, "LeftColumn")
	_add_ruin_block(ruin, chunk_center, reference_height, ruin_center, forward, Vector2(8.0, 0.0), Vector3(2.4, 7.0, 2.8), 0.0, "RightColumn")
	_add_ruin_block(ruin, chunk_center, reference_height, ruin_center, forward, Vector2.ZERO, Vector3(18.4, 1.8, 3.0), 7.0, "Lintel")
	_add_ruin_block(ruin, chunk_center, reference_height, ruin_center, forward, Vector2(-11.0, 6.0), Vector3(4.2, 1.2, 8.0), 0.0, "LeftTerrace")
	_add_ruin_block(ruin, chunk_center, reference_height, ruin_center, forward, Vector2(11.0, 6.0), Vector3(4.2, 1.2, 8.0), 0.0, "RightTerrace")
	chunk.add_child(ruin)


func _add_ruin_block(
	ruin: StaticBody3D,
	_chunk_center: Vector2,
	reference_height: float,
	ruin_center: Vector2,
	forward: Vector2,
	local_offset: Vector2,
	size: Vector3,
	vertical_offset: float,
	block_name: String,
) -> void:
	var right := Vector2(-forward.y, forward.x)
	var logical_position := ruin_center + right * local_offset.x - forward * local_offset.y
	var local_ground := get_surface_height(logical_position.x, logical_position.y) - reference_height
	var position := Vector3(local_offset.x, local_ground + size.y * 0.5 + vertical_offset, local_offset.y)
	var collision := CollisionShape3D.new()
	collision.name = "%sCollision" % block_name
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	collision.position = position
	ruin.add_child(collision)
	if DisplayServer.get_name() == "headless":
		return
	var visual := MeshInstance3D.new()
	visual.name = block_name
	visual.mesh = _ruin_block_mesh
	visual.material_override = _ruin_material
	visual.position = position
	visual.scale = size
	ruin.add_child(visual)


func _get_rock_passage_center(coord: Vector2i) -> Vector2:
	var chunk_center := Vector2(coord) * chunk_size
	return chunk_center + Vector2(
		lerpf(-72.0, 72.0, _feature_grammar.get_cell_random(coord, 32)),
		lerpf(-72.0, 72.0, _feature_grammar.get_cell_random(coord, 33)),
	)


func _add_rock_passage(chunk: StaticBody3D, coord: Vector2i, reference_height: float) -> void:
	var chunk_center := Vector2(coord) * chunk_size
	if not chunk_has_rock_passage(coord):
		return
	var passage_center := _get_rock_passage_center(coord)
	var outward := chunk_center.normalized()
	var angle_offset := deg_to_rad(lerpf(-26.0, 26.0, _feature_grammar.get_cell_random(coord, 34)))
	var gate_axis := Vector2(-outward.y, outward.x).rotated(angle_offset)
	var center_spacing := lerpf(21.0, 28.0, _feature_grammar.get_cell_random(coord, 35))
	for rock_index in range(2):
		var side := -1.0 if rock_index == 0 else 1.0
		var logical_position := passage_center + gate_axis * center_spacing * 0.5 * side
		var radius := lerpf(2.7, 4.1, _feature_grammar.get_cell_random(coord, 36 + rock_index))
		var rock := StaticBody3D.new()
		rock.name = "RockGate_%d_%d_%d" % [coord.x, coord.y, rock_index]
		rock.set_meta(&"overrush_obstacle", true)
		rock.set_meta(&"overrush_rock", true)
		rock.set_meta(&"overrush_rock_gate", true)
		rock.set_meta(&"passage_clearance", center_spacing - radius * 2.0)
		rock.position = Vector3(
			logical_position.x - chunk_center.x,
			get_surface_height(logical_position.x, logical_position.y) - reference_height + radius * 0.55,
			logical_position.y - chunk_center.y,
		)
		rock.rotation.y = _feature_grammar.get_cell_random(coord, 40 + rock_index) * TAU
		var collision := CollisionShape3D.new()
		collision.name = "CollisionShape3D"
		var shape := SphereShape3D.new()
		shape.radius = radius * 0.84
		collision.shape = shape
		rock.add_child(collision)
		if DisplayServer.get_name() != "headless":
			var visual := MeshInstance3D.new()
			visual.name = "RockVisual"
			visual.mesh = _rock_mesh
			visual.material_override = _rock_material
			visual.scale = Vector3(
				radius * lerpf(0.9, 1.25, _feature_grammar.get_cell_random(coord, 42 + rock_index)),
				radius * lerpf(0.72, 1.05, _feature_grammar.get_cell_random(coord, 44 + rock_index)),
				radius * lerpf(0.9, 1.2, _feature_grammar.get_cell_random(coord, 46 + rock_index)),
			)
			rock.add_child(visual)
		chunk.add_child(rock)


func _clear_chunks() -> void:
	for chunk in loaded_chunks.values():
		(chunk as StaticBody3D).free()
	loaded_chunks.clear()
	_desired_chunks.clear()
	_pending_chunks.clear()
