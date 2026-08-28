class_name ProceduralDesert
extends StaticBody3D

const TREE_BOUGH_TIERS := 4
const TREE_RADIAL_SEGMENTS := 9
const ROCK_RADIAL_SEGMENTS := 9
const TREE_COLLISION_RADIUS_FACTOR := 0.96
const ROCK_COLLISION_RADIUS_FACTOR := 0.68
const RUIN_VISUAL_SEGMENTS := 19

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
var _rock_mesh: ArrayMesh
var _tree_trunk_mesh: CylinderMesh
var _tree_canopy_mesh: ArrayMesh
var _ruin_block_mesh: ArrayMesh
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
	_rock_mesh = _build_faceted_rock_mesh()
	_tree_trunk_mesh = CylinderMesh.new()
	_tree_trunk_mesh.top_radius = 0.72
	_tree_trunk_mesh.bottom_radius = 1.0
	_tree_trunk_mesh.height = 1.0
	_tree_trunk_mesh.radial_segments = 9
	_tree_trunk_mesh.rings = 1
	_tree_canopy_mesh = _build_conifer_canopy_mesh()
	_ruin_block_mesh = _build_weathered_block_mesh()
	if DisplayServer.get_name() != "headless":
		_terrain_material = ShaderMaterial.new()
		_terrain_material.shader = load("res://shaders/desert.gdshader")
		_terrain_material.set_shader_parameter("seed_offset", Vector2(generated_seed % 997, generated_seed % 619))
		_terrain_material.set_shader_parameter("world_origin", Vector2.ZERO)
		_terrain_material.set_shader_parameter("sand_albedo", load("res://assets/terrain/wind_sand_albedo.png"))
		_terrain_material.set_shader_parameter("grass_albedo", load("res://assets/terrain/alpine_grass_albedo.png"))
		_rock_material = StandardMaterial3D.new()
		_rock_material.albedo_color = Color("#625f64")
		_rock_material.roughness = 0.9
		_rock_material.vertex_color_use_as_albedo = true
		_rock_material.cull_mode = BaseMaterial3D.CULL_DISABLED
		_tree_trunk_material = StandardMaterial3D.new()
		_tree_trunk_material.albedo_color = Color("#62432f")
		_tree_trunk_material.roughness = 0.93
		_tree_trunk_material.vertex_color_use_as_albedo = true
		_tree_canopy_material = StandardMaterial3D.new()
		_tree_canopy_material.albedo_color = Color("#3d7044")
		_tree_canopy_material.roughness = 0.88
		_tree_canopy_material.vertex_color_use_as_albedo = true
		_tree_canopy_material.cull_mode = BaseMaterial3D.CULL_DISABLED
		_ruin_material = StandardMaterial3D.new()
		_ruin_material.albedo_color = Color("#ad9b79")
		_ruin_material.roughness = 0.94
		_ruin_material.vertex_color_use_as_albedo = true
		_ruin_material.cull_mode = BaseMaterial3D.CULL_DISABLED


func _build_conifer_canopy_mesh() -> ArrayMesh:
	var builder := SurfaceTool.new()
	builder.begin(Mesh.PRIMITIVE_TRIANGLES)
	for tier_index in range(TREE_BOUGH_TIERS):
		var tier_progress := float(tier_index) / float(TREE_BOUGH_TIERS - 1)
		var base_y := tier_progress * 0.58
		var top_y := minf(1.0, base_y + lerpf(0.5, 0.36, tier_progress))
		var tier_radius := lerpf(1.0, 0.38, tier_progress)
		var top := Vector3(0.0, top_y, 0.0)
		var underside_center := Vector3(0.0, base_y + 0.035, 0.0)
		var tier_color := Color(lerpf(0.68, 0.9, tier_progress), lerpf(0.78, 1.0, tier_progress), lerpf(0.7, 0.84, tier_progress), 1.0)
		for segment_index in range(TREE_RADIAL_SEGMENTS):
			var angle_a := TAU * float(segment_index) / float(TREE_RADIAL_SEGMENTS)
			var angle_b := TAU * float(segment_index + 1) / float(TREE_RADIAL_SEGMENTS)
			var irregular_a := 0.91 + 0.09 * sin(float(segment_index * 5 + tier_index * 7))
			var irregular_b := 0.91 + 0.09 * sin(float((segment_index + 1) * 5 + tier_index * 7))
			var ring_a := Vector3(cos(angle_a) * tier_radius * irregular_a, base_y, sin(angle_a) * tier_radius * irregular_a)
			var ring_b := Vector3(cos(angle_b) * tier_radius * irregular_b, base_y, sin(angle_b) * tier_radius * irregular_b)
			_add_mesh_triangle(builder, top, ring_a, ring_b, tier_color, Vector3(0.0, 0.45, 0.0))
			_add_mesh_triangle(builder, underside_center, ring_b, ring_a, tier_color.darkened(0.24), Vector3(0.0, 0.45, 0.0))
	return builder.commit() as ArrayMesh


func _build_faceted_rock_mesh() -> ArrayMesh:
	var builder := SurfaceTool.new()
	builder.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings: Array[PackedVector3Array] = []
	var ring_heights := [0.52, 0.02, -0.5]
	var ring_radii := [0.72, 1.0, 0.76]
	for ring_index in range(ring_heights.size()):
		var ring := PackedVector3Array()
		for segment_index in range(ROCK_RADIAL_SEGMENTS):
			var angle := TAU * float(segment_index) / float(ROCK_RADIAL_SEGMENTS)
			var irregularity := 0.84 + 0.16 * sin(float(segment_index * 11 + ring_index * 17))
			ring.append(Vector3(
				cos(angle) * ring_radii[ring_index] * irregularity,
				ring_heights[ring_index] + 0.07 * sin(float(segment_index * 7 + ring_index * 3)),
				sin(angle) * ring_radii[ring_index] * irregularity,
			))
		rings.append(ring)
	var top := Vector3(0.08, 0.8, -0.04)
	var bottom := Vector3(-0.06, -0.64, 0.05)
	for segment_index in range(ROCK_RADIAL_SEGMENTS):
		var next_index := (segment_index + 1) % ROCK_RADIAL_SEGMENTS
		_add_mesh_triangle(builder, top, rings[0][segment_index], rings[0][next_index], Color(1.02, 1.0, 0.96, 1.0))
		for ring_index in range(rings.size() - 1):
			var upper_a := rings[ring_index][segment_index]
			var upper_b := rings[ring_index][next_index]
			var lower_a := rings[ring_index + 1][segment_index]
			var lower_b := rings[ring_index + 1][next_index]
			var side_color := Color(lerpf(0.96, 0.74, float(ring_index) / 2.0), lerpf(0.94, 0.76, float(ring_index) / 2.0), lerpf(0.98, 0.82, float(ring_index) / 2.0), 1.0)
			_add_mesh_triangle(builder, upper_a, lower_a, lower_b, side_color)
			_add_mesh_triangle(builder, upper_a, lower_b, upper_b, side_color)
		_add_mesh_triangle(builder, bottom, rings[2][next_index], rings[2][segment_index], Color(0.62, 0.64, 0.68, 1.0))
	return builder.commit() as ArrayMesh


func _build_weathered_block_mesh() -> ArrayMesh:
	var builder := SurfaceTool.new()
	builder.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := 0.5
	var inset := 0.38
	var top_color := Color(1.0, 0.98, 0.88, 1.0)
	var side_color := Color(0.86, 0.82, 0.72, 1.0)
	var shadow_color := Color(0.68, 0.66, 0.62, 1.0)
	_add_mesh_quad(builder, Vector3(-inset, half, -inset), Vector3(inset, half, -inset), Vector3(inset, half, inset), Vector3(-inset, half, inset), top_color)
	_add_mesh_quad(builder, Vector3(-inset, -half, inset), Vector3(inset, -half, inset), Vector3(inset, -half, -inset), Vector3(-inset, -half, -inset), shadow_color)
	_add_mesh_quad(builder, Vector3(half, -inset, -inset), Vector3(half, -inset, inset), Vector3(half, inset, inset), Vector3(half, inset, -inset), side_color.lightened(0.05))
	_add_mesh_quad(builder, Vector3(-half, -inset, inset), Vector3(-half, -inset, -inset), Vector3(-half, inset, -inset), Vector3(-half, inset, inset), side_color.darkened(0.08))
	_add_mesh_quad(builder, Vector3(-inset, -inset, half), Vector3(inset, -inset, half), Vector3(inset, inset, half), Vector3(-inset, inset, half), side_color)
	_add_mesh_quad(builder, Vector3(inset, -inset, -half), Vector3(-inset, -inset, -half), Vector3(-inset, inset, -half), Vector3(inset, inset, -half), side_color.darkened(0.12))
	for first_sign in [-1.0, 1.0]:
		for second_sign in [-1.0, 1.0]:
			_add_mesh_quad(
				builder,
				Vector3(-inset, first_sign * half, second_sign * inset),
				Vector3(inset, first_sign * half, second_sign * inset),
				Vector3(inset, first_sign * inset, second_sign * half),
				Vector3(-inset, first_sign * inset, second_sign * half),
				side_color.darkened(0.04),
			)
			_add_mesh_quad(
				builder,
				Vector3(first_sign * half, -inset, second_sign * inset),
				Vector3(first_sign * half, inset, second_sign * inset),
				Vector3(first_sign * inset, inset, second_sign * half),
				Vector3(first_sign * inset, -inset, second_sign * half),
				side_color.darkened(0.08),
			)
			_add_mesh_quad(
				builder,
				Vector3(first_sign * half, second_sign * inset, -inset),
				Vector3(first_sign * half, second_sign * inset, inset),
				Vector3(first_sign * inset, second_sign * half, inset),
				Vector3(first_sign * inset, second_sign * half, -inset),
				side_color,
			)
	for x_sign in [-1.0, 1.0]:
		for y_sign in [-1.0, 1.0]:
			for z_sign in [-1.0, 1.0]:
				_add_mesh_triangle(
					builder,
					Vector3(x_sign * half, y_sign * inset, z_sign * inset),
					Vector3(x_sign * inset, y_sign * half, z_sign * inset),
					Vector3(x_sign * inset, y_sign * inset, z_sign * half),
					side_color.lightened(0.03) if y_sign > 0.0 else shadow_color,
				)
	return builder.commit() as ArrayMesh


func _add_mesh_triangle(
	builder: SurfaceTool,
	first: Vector3,
	second: Vector3,
	third: Vector3,
	color: Color,
	normal_origin := Vector3.ZERO,
) -> void:
	var normal := (second - first).cross(third - first).normalized()
	var centroid := (first + second + third) / 3.0
	if normal.dot(centroid - normal_origin) < 0.0:
		normal = -normal
	for vertex in [first, second, third]:
		builder.set_normal(normal)
		builder.set_color(color)
		builder.add_vertex(vertex)


func _add_mesh_quad(
	builder: SurfaceTool,
	first: Vector3,
	second: Vector3,
	third: Vector3,
	fourth: Vector3,
	color: Color,
) -> void:
	_add_mesh_triangle(builder, first, second, third, color)
	_add_mesh_triangle(builder, first, third, fourth, color)


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
	var tree_positions := PackedVector3Array()
	var collision_faces: Array[Vector3] = []
	for tree_index in range(trees.size()):
		var tree := trees[tree_index]
		var logical_position: Vector2 = tree.position
		var height: float = tree.height
		var radius: float = tree.radius
		var local_height := get_surface_height(logical_position.x, logical_position.y) - reference_height
		var tree_position := Vector3(
			logical_position.x - chunk_center.x,
			local_height,
			logical_position.y - chunk_center.y,
		)
		tree_positions.append(tree_position)
		_append_tree_collision_prism(
			collision_faces,
			tree_position,
			radius * TREE_COLLISION_RADIUS_FACTOR,
			maxf(4.8, height * 0.7),
		)
	var collision := CollisionShape3D.new()
	collision.name = "TreeCollision"
	var forest_shape := ConcavePolygonShape3D.new()
	forest_shape.backface_collision = true
	forest_shape.set_faces(PackedVector3Array(collision_faces))
	collision.shape = forest_shape
	obstacles.add_child(collision)
	obstacles.set_meta(&"tree_positions", tree_positions)
	obstacles.set_meta(&"tree_collision_triangle_count", collision_faces.size() / 3)
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
	canopy_multimesh.instance_count = trees.size()
	for tree_index in range(trees.size()):
		var tree := trees[tree_index]
		var cell: Vector2i = tree.cell
		var logical_position: Vector2 = tree.position
		var height: float = tree.height
		var radius: float = tree.radius
		var local_height := get_surface_height(logical_position.x, logical_position.y) - reference_height
		var local_xz := logical_position - chunk_center
		var visible_trunk_height := height * 0.7
		var trunk_transform := Transform3D(
			Basis.IDENTITY.scaled(Vector3(radius, visible_trunk_height, radius)),
			Vector3(local_xz.x, local_height + visible_trunk_height * 0.5, local_xz.y),
		)
		var canopy_radius := height * lerpf(0.21, 0.28, _landscape_layout.get_cell_random(cell, 16))
		var crown_angle := _landscape_layout.get_cell_random(cell, 17) * TAU
		var crown_basis := Basis(Vector3.UP, crown_angle)
		var canopy := Transform3D(
			crown_basis.scaled(Vector3(
				canopy_radius,
				height * 0.66,
				canopy_radius * lerpf(0.84, 1.08, _landscape_layout.get_cell_random(cell, 19)),
			)),
			Vector3(local_xz.x, local_height + height * 0.35, local_xz.y),
		)
		trunk_multimesh.set_instance_transform(tree_index, trunk_transform)
		trunk_multimesh.set_instance_color(tree_index, Color(0.82, 0.74, 0.67, 1.0))
		var tint := lerpf(0.78, 1.08, _landscape_layout.get_cell_random(cell, 18))
		var canopy_color := Color(tint * 0.78, tint, tint * 0.72, 1.0)
		canopy_multimesh.set_instance_transform(tree_index, canopy)
		canopy_multimesh.set_instance_color(tree_index, canopy_color)
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


func _append_tree_collision_prism(
	faces: Array[Vector3],
	base_center: Vector3,
	radius: float,
	height: float,
) -> void:
	const SEGMENT_COUNT := 6
	var top_center := base_center + Vector3.UP * height
	for segment_index in range(SEGMENT_COUNT):
		var angle_a := TAU * float(segment_index) / float(SEGMENT_COUNT)
		var angle_b := TAU * float(segment_index + 1) / float(SEGMENT_COUNT)
		var radial_a := Vector3(cos(angle_a) * radius, 0.0, sin(angle_a) * radius)
		var radial_b := Vector3(cos(angle_b) * radius, 0.0, sin(angle_b) * radius)
		var bottom_a := base_center + radial_a
		var bottom_b := base_center + radial_b
		var top_a := top_center + radial_a
		var top_b := top_center + radial_b
		faces.append_array([bottom_a, top_a, top_b, bottom_a, top_b, bottom_b])
		faces.append_array([top_center, top_b, top_a])
		faces.append_array([base_center, bottom_a, bottom_b])


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
		shape.radius = radius * ROCK_COLLISION_RADIUS_FACTOR
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
	ruin.set_meta(&"visual_segment_count", RUIN_VISUAL_SEGMENTS)
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
	_add_ruin_block_visuals(ruin, position, size, block_name)


func _add_ruin_block_visuals(ruin: StaticBody3D, position: Vector3, size: Vector3, block_name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var segment_count := 1
	var split_axis := Vector3.ZERO
	match block_name:
		"LeftColumn", "RightColumn":
			segment_count = 3
			split_axis = Vector3.UP
		"Lintel":
			segment_count = 7
			split_axis = Vector3.RIGHT
		"LeftTerrace", "RightTerrace":
			segment_count = 3
			split_axis = Vector3.FORWARD
	var split_length := size.dot(split_axis.abs())
	var gap := 0.07
	var segment_length := (split_length - gap * float(segment_count - 1)) / float(segment_count)
	var segment_size := size
	if split_axis.x != 0.0:
		segment_size.x = segment_length
	elif split_axis.y != 0.0:
		segment_size.y = segment_length
	else:
		segment_size.z = segment_length
	for segment_index in range(segment_count):
		var along_axis := -split_length * 0.5 + segment_length * 0.5 + float(segment_index) * (segment_length + gap)
		var visual := MeshInstance3D.new()
		visual.name = "%sStone%02d" % [block_name, segment_index]
		visual.mesh = _ruin_block_mesh
		visual.material_override = _ruin_material
		visual.position = position + split_axis * along_axis
		visual.scale = segment_size * 1.012
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
		shape.radius = radius * ROCK_COLLISION_RADIUS_FACTOR
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
