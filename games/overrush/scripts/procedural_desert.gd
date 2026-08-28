class_name ProceduralDesert
extends StaticBody3D

const TREE_FOLIAGE_CARD_PLANES := 3
const TREE_VISIBLE_TRUNK_HEIGHT_SCALE := 0.24
const TREE_FOLIAGE_SHELL_RADIUS_SCALE := 1.08
const ROCK_RADIAL_SEGMENTS := 12
const TREE_COLLISION_RADIUS_FACTOR := 0.96
const ROCK_COLLISION_RADIUS_FACTOR := 0.68
const RUIN_VISUAL_SEGMENTS := 52
const RUIN_COLLISION_VOLUMES := 9
const SUMMIT_MOUNTAIN_BLEND_START := 180.0
const SUMMIT_MOUNTAIN_BLEND_END := 960.0
const SUMMIT_RELIEF_BLEND_START := 260.0
const SUMMIT_RELIEF_BLEND_END := 620.0
const MOUNTAIN_RELIEF_AMPLITUDE := 108.0
const MOUNTAIN_FOLD_PRIMARY_AMPLITUDE := 74.0
const MOUNTAIN_FOLD_SECONDARY_AMPLITUDE := 58.0
const BROAD_RELIEF_AMPLITUDE := 54.0
const RIDGE_RELIEF_AMPLITUDE := 38.0
const STONE_TRIPLANAR_SCALE := 0.25
const HORIZON_RADIUS := 4
const HORIZON_CHUNK_RESOLUTION := 17

@export var tracked_body_path: NodePath
@export var tracked_camera_path: NodePath
@export_range(192.0, 768.0, 32.0) var chunk_size := 384.0
@export_range(25, 97, 8) var chunk_resolution := 65
@export_range(1, 4, 1) var active_radius := 2
@export_range(1, 4, 1) var chunks_per_frame := 2
@export var rebase_distance := 1536.0
@export var seed := 0
@export var summit_height := 520.0
@export var radial_grade := 0.565
@export var summit_softening_radius := 36.0

var generated_seed := 0
var world_origin := Vector3.ZERO
var loaded_chunks: Dictionary = {}
var horizon_chunks: Dictionary = {}

var _tracked_body: Node3D
var _tracked_camera: Node3D
var _stream_center := Vector2i(2147483647, 2147483647)
var _desired_chunks: Dictionary = {}
var _pending_chunks: Array[Vector2i] = []
var _terrain_material: ShaderMaterial
var _rock_material: StandardMaterial3D
var _tree_trunk_material: StandardMaterial3D
var _tree_foliage_material: StandardMaterial3D
var _ruin_material: StandardMaterial3D
var _ruin_recess_material: StandardMaterial3D
var _rock_mesh: ArrayMesh
var _tree_trunk_mesh: CylinderMesh
var _tree_foliage_mesh: ArrayMesh
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
	var softened_radius := (
		sqrt(radius * radius + summit_softening_radius * summit_softening_radius)
		- summit_softening_radius
	)
	var descent := softened_radius * radial_grade
	var mountain_fade := smoothstep(SUMMIT_MOUNTAIN_BLEND_START, SUMMIT_MOUNTAIN_BLEND_END, radius)
	var feature_fade := smoothstep(SUMMIT_RELIEF_BLEND_START, SUMMIT_RELIEF_BLEND_END, radius)
	var mountain_relief := _mountain_noise.get_noise_2d(x, z) * MOUNTAIN_RELIEF_AMPLITUDE
	var mountain_folds := (
		sin(x * 0.0014 + z * 0.0005 + _mountain_fold_phase.x) * MOUNTAIN_FOLD_PRIMARY_AMPLITUDE
		+ sin(x * -0.00055 + z * 0.0011 + _mountain_fold_phase.y) * MOUNTAIN_FOLD_SECONDARY_AMPLITUDE
	)
	var broad := _broad_noise.get_noise_2d(x, z) * BROAD_RELIEF_AMPLITUDE
	var ridges := _ridge_noise.get_noise_2d(x, z)
	var folded_ridges := signf(ridges) * ridges * ridges * RIDGE_RELIEF_AMPLITUDE
	var dunes := _dune_noise.get_noise_2d(x, z) * 10.5
	var authored_feature := _feature_grammar.sample_height_offset(x, z)
	return (
		summit_height
		- descent
		+ mountain_fade * (mountain_relief + mountain_folds + broad + folded_ridges)
		+ feature_fade * (dunes + authored_feature)
	)


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
	var focus_changed := next_center != _stream_center
	if focus_changed:
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
	if focus_changed:
		_rebuild_horizon_chunks()


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


func _rebuild_horizon_chunks() -> void:
	var desired_horizon := {}
	for z_offset in range(-HORIZON_RADIUS, HORIZON_RADIUS + 1):
		for x_offset in range(-HORIZON_RADIUS, HORIZON_RADIUS + 1):
			var coord := _stream_center + Vector2i(x_offset, z_offset)
			if loaded_chunks.has(coord):
				continue
			desired_horizon[coord] = true
			if not horizon_chunks.has(coord):
				_load_horizon_chunk(coord)
	for key in horizon_chunks.keys():
		var coord: Vector2i = key
		if desired_horizon.has(coord):
			continue
		_remove_horizon_chunk(coord)


func _load_horizon_chunk(coord: Vector2i) -> void:
	var center_x := float(coord.x) * chunk_size
	var center_z := float(coord.y) * chunk_size
	var reference_height := get_surface_height(center_x, center_z)
	var terrain := MeshInstance3D.new()
	terrain.name = "Horizon_%d_%d" % [coord.x, coord.y]
	terrain.position = Vector3(
		center_x - world_origin.x,
		reference_height - world_origin.y,
		center_z - world_origin.z,
	)
	terrain.mesh = _build_chunk_mesh(coord, reference_height, HORIZON_CHUNK_RESOLUTION).mesh
	terrain.material_override = _terrain_material
	terrain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	terrain.set_meta(&"overrush_horizon_terrain", true)
	add_child(terrain)
	horizon_chunks[coord] = terrain


func _remove_horizon_chunk(coord: Vector2i) -> void:
	if not horizon_chunks.has(coord):
		return
	var terrain := horizon_chunks[coord] as MeshInstance3D
	horizon_chunks.erase(coord)
	terrain.free()


func _load_chunk(coord: Vector2i) -> void:
	if loaded_chunks.has(coord) or not _desired_chunks.has(coord):
		return
	_remove_horizon_chunk(coord)
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
	var chunk_data := _build_chunk_mesh(coord, reference_height, chunk_resolution)
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


func _build_chunk_mesh(coord: Vector2i, reference_height: float, resolution: int) -> Dictionary:
	var vertex_count := resolution * resolution
	var spacing := chunk_size / float(resolution - 1)
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

	for z_index in range(resolution):
		var local_z := -half_size + z_index * spacing
		var logical_z := center_z + local_z
		for x_index in range(resolution):
			var local_x := -half_size + x_index * spacing
			var logical_x := center_x + local_x
			var index := z_index * resolution + x_index
			var local_height := get_surface_height(logical_x, logical_z) - reference_height
			heights[index] = local_height
			vertices[index] = Vector3(local_x, local_height, local_z)
			normals[index] = get_surface_normal(logical_x, logical_z, spacing)
			uvs[index] = Vector2(logical_x, logical_z) * 0.002
			colors[index] = Color(_landscape_layout.get_grass_weight(Vector2(logical_x, logical_z)), 0.0, 0.0, 1.0)

	var indices := PackedInt32Array()
	indices.resize((resolution - 1) * (resolution - 1) * 6)
	var write_index := 0
	for z_index in range(resolution - 1):
		for x_index in range(resolution - 1):
			var top_left := z_index * resolution + x_index
			var top_right := top_left + 1
			var bottom_left := top_left + resolution
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
	for terrain in horizon_chunks.values():
		(terrain as MeshInstance3D).position -= shift
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
	_offset_stone_texture_origin(_rock_material, shift)
	_offset_stone_texture_origin(_ruin_material, shift)


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
	_tree_foliage_material = null
	_ruin_material = null
	_ruin_recess_material = null
	_rock_mesh = _build_weathered_rock_mesh()
	_tree_trunk_mesh = CylinderMesh.new()
	_tree_trunk_mesh.top_radius = 0.72
	_tree_trunk_mesh.bottom_radius = 1.0
	_tree_trunk_mesh.height = 1.0
	_tree_trunk_mesh.radial_segments = 9
	_tree_trunk_mesh.rings = 1
	_tree_foliage_mesh = _build_conifer_foliage_mesh()
	_ruin_block_mesh = _build_weathered_block_mesh()
	if DisplayServer.get_name() != "headless":
		_terrain_material = ShaderMaterial.new()
		_terrain_material.shader = load("res://shaders/desert.gdshader")
		_terrain_material.set_shader_parameter("seed_offset", Vector2(generated_seed % 997, generated_seed % 619))
		_terrain_material.set_shader_parameter("world_origin", Vector2.ZERO)
		_terrain_material.set_shader_parameter("sand_albedo", load("res://assets/terrain/wind_sand_albedo.png"))
		_terrain_material.set_shader_parameter("grass_albedo", load("res://assets/terrain/alpine_grass_albedo.png"))
		var stone_texture := load("res://assets/terrain/weathered_sandstone_albedo.png") as Texture2D
		_rock_material = _create_stone_material(stone_texture, Color("#a7a19a"), 0.9)
		_tree_trunk_material = StandardMaterial3D.new()
		_tree_trunk_material.albedo_color = Color("#4b3428")
		_tree_trunk_material.roughness = 0.93
		_tree_trunk_material.vertex_color_use_as_albedo = true
		_tree_foliage_material = _create_foliage_material(
			load("res://assets/terrain/conifer_foliage_atlas.png") as Texture2D
		)
		_ruin_material = _create_stone_material(stone_texture, Color("#d7c2a0"), 0.94)
		_ruin_material.emission_enabled = true
		_ruin_material.emission = Color("#1f1308")
		_ruin_material.emission_energy_multiplier = 0.18
		_ruin_recess_material = StandardMaterial3D.new()
		_ruin_recess_material.albedo_color = Color("#382e28")
		_ruin_recess_material.roughness = 1.0
		_ruin_recess_material.vertex_color_use_as_albedo = true
		_ruin_recess_material.emission_enabled = true
		_ruin_recess_material.emission = Color("#080504")
		_ruin_recess_material.emission_energy_multiplier = 0.2


func _create_stone_material(texture: Texture2D, tint: Color, surface_roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = tint
	material.albedo_texture = texture
	material.roughness = surface_roughness
	material.vertex_color_use_as_albedo = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	material.uv1_scale = Vector3.ONE * STONE_TRIPLANAR_SCALE
	material.uv1_triplanar = true
	material.uv1_world_triplanar = true
	material.uv1_triplanar_sharpness = 4.0
	return material


func _create_foliage_material(texture: Texture2D) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_texture = texture
	material.albedo_color = Color.WHITE
	material.roughness = 0.92
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	material.alpha_scissor_threshold = 0.38
	material.alpha_antialiasing_mode = BaseMaterial3D.ALPHA_ANTIALIASING_ALPHA_TO_COVERAGE
	material.alpha_antialiasing_edge = 0.48
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	material.vertex_color_use_as_albedo = true
	return material


func _offset_stone_texture_origin(material: StandardMaterial3D, shift: Vector3) -> void:
	if not is_instance_valid(material):
		return
	material.uv1_offset += shift * STONE_TRIPLANAR_SCALE


func _build_conifer_foliage_mesh() -> ArrayMesh:
	var builder := SurfaceTool.new()
	builder.begin(Mesh.PRIMITIVE_TRIANGLES)
	for plane_index in range(TREE_FOLIAGE_CARD_PLANES):
		var angle := PI * float(plane_index) / float(TREE_FOLIAGE_CARD_PLANES)
		var right := Vector3(cos(angle), 0.0, sin(angle))
		var normal := Vector3(-sin(angle), 0.0, cos(angle))
		var bottom_left := -right
		var bottom_right := right
		var top_left := -right + Vector3.UP
		var top_right := right + Vector3.UP
		_add_foliage_triangle(
			builder,
			bottom_left,
			bottom_right,
			top_right,
			Vector2(0.0, 1.0),
			Vector2(1.0, 1.0),
			Vector2(1.0, 0.0),
			normal,
		)
		_add_foliage_triangle(
			builder,
			bottom_left,
			top_right,
			top_left,
			Vector2(0.0, 1.0),
			Vector2(1.0, 0.0),
			Vector2(0.0, 0.0),
			normal,
		)
	return builder.commit() as ArrayMesh


func _add_foliage_triangle(
	builder: SurfaceTool,
	first: Vector3,
	second: Vector3,
	third: Vector3,
	first_uv: Vector2,
	second_uv: Vector2,
	third_uv: Vector2,
	normal: Vector3,
) -> void:
	var vertices := [first, second, third]
	var uvs := [first_uv, second_uv, third_uv]
	for vertex_index in range(3):
		builder.set_normal(normal)
		builder.set_uv(uvs[vertex_index])
		builder.set_color(Color.WHITE)
		builder.add_vertex(vertices[vertex_index])


func _build_weathered_rock_mesh() -> ArrayMesh:
	var builder := SurfaceTool.new()
	builder.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings: Array[PackedVector3Array] = []
	var ring_heights := [0.62, 0.38, 0.04, -0.32, -0.55]
	var ring_radii := [0.44, 0.8, 1.0, 0.84, 0.5]
	var ring_offsets := [
		Vector2(0.05, -0.04),
		Vector2(-0.03, -0.02),
		Vector2(0.04, 0.03),
		Vector2(-0.05, 0.02),
		Vector2(0.02, -0.03),
	]
	for ring_index in range(ring_heights.size()):
		var ring := PackedVector3Array()
		for segment_index in range(ROCK_RADIAL_SEGMENTS):
			var angle := (
				TAU * float(segment_index) / float(ROCK_RADIAL_SEGMENTS)
				+ float(ring_index % 2) * 0.1
			)
			var irregularity := (
				0.88
				+ 0.09 * sin(float(segment_index * 11 + ring_index * 17))
				+ 0.045 * cos(float(segment_index * 5 - ring_index * 13))
			)
			ring.append(Vector3(
				cos(angle) * ring_radii[ring_index] * irregularity + ring_offsets[ring_index].x,
				ring_heights[ring_index] + 0.035 * sin(float(segment_index * 7 + ring_index * 3)),
				sin(angle) * ring_radii[ring_index] * irregularity + ring_offsets[ring_index].y,
			))
		rings.append(ring)
	var top := Vector3(0.08, 0.75, -0.05)
	var bottom := Vector3(-0.04, -0.62, 0.04)
	for segment_index in range(ROCK_RADIAL_SEGMENTS):
		var next_index := (segment_index + 1) % ROCK_RADIAL_SEGMENTS
		_add_smooth_rock_triangle(builder, top, rings[0][segment_index], rings[0][next_index], Color(1.0, 0.96, 0.86, 1.0))
		for ring_index in range(rings.size() - 1):
			var upper_a := rings[ring_index][segment_index]
			var upper_b := rings[ring_index][next_index]
			var lower_a := rings[ring_index + 1][segment_index]
			var lower_b := rings[ring_index + 1][next_index]
			var ring_progress := float(ring_index) / float(rings.size() - 2)
			var side_color := Color(
				lerpf(0.96, 0.67, ring_progress),
				lerpf(0.91, 0.62, ring_progress),
				lerpf(0.82, 0.55, ring_progress),
				1.0,
			)
			_add_smooth_rock_triangle(builder, upper_a, lower_a, lower_b, side_color)
			_add_smooth_rock_triangle(builder, upper_a, lower_b, upper_b, side_color)
		_add_smooth_rock_triangle(builder, bottom, rings[-1][next_index], rings[-1][segment_index], Color(0.55, 0.5, 0.44, 1.0))
	return builder.commit() as ArrayMesh


func _add_smooth_rock_triangle(
	builder: SurfaceTool,
	first: Vector3,
	second: Vector3,
	third: Vector3,
	color: Color,
) -> void:
	for vertex in [first, second, third]:
		builder.set_normal(Vector3(vertex.x, vertex.y * 1.25, vertex.z).normalized())
		builder.set_color(color)
		builder.add_vertex(vertex)


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
	var foliage_multimesh := MultiMesh.new()
	foliage_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	foliage_multimesh.use_colors = true
	foliage_multimesh.mesh = _tree_foliage_mesh
	foliage_multimesh.instance_count = trees.size()
	for tree_index in range(trees.size()):
		var tree := trees[tree_index]
		var cell: Vector2i = tree.cell
		var logical_position: Vector2 = tree.position
		var height: float = tree.height
		var radius: float = tree.radius
		var local_height := get_surface_height(logical_position.x, logical_position.y) - reference_height
		var local_xz := logical_position - chunk_center
		var visible_trunk_height := height * TREE_VISIBLE_TRUNK_HEIGHT_SCALE
		var trunk_transform := Transform3D(
			Basis.IDENTITY.scaled(Vector3(radius, visible_trunk_height, radius)),
			Vector3(local_xz.x, local_height + visible_trunk_height * 0.5, local_xz.y),
		)
		var canopy_radius := height * lerpf(0.21, 0.28, _landscape_layout.get_cell_random(cell, 16))
		var crown_angle := _landscape_layout.get_cell_random(cell, 17) * TAU
		var crown_basis := Basis(Vector3.UP, crown_angle)
		crown_basis = crown_basis.rotated(
			Vector3.RIGHT,
			deg_to_rad(lerpf(-2.4, 2.4, _landscape_layout.get_cell_random(cell, 20))),
		)
		crown_basis = crown_basis.rotated(
			Vector3.FORWARD,
			deg_to_rad(lerpf(-2.4, 2.4, _landscape_layout.get_cell_random(cell, 21))),
		)
		var canopy_depth_scale := lerpf(0.84, 1.08, _landscape_layout.get_cell_random(cell, 19))
		var foliage_canopy := Transform3D(
			crown_basis.scaled(Vector3(
				canopy_radius * TREE_FOLIAGE_SHELL_RADIUS_SCALE,
				height * 0.9,
				canopy_radius * canopy_depth_scale * TREE_FOLIAGE_SHELL_RADIUS_SCALE,
			)),
			Vector3(local_xz.x, local_height + height * 0.1, local_xz.y),
		)
		trunk_multimesh.set_instance_transform(tree_index, trunk_transform)
		trunk_multimesh.set_instance_color(tree_index, _get_tree_trunk_color(cell))
		foliage_multimesh.set_instance_transform(tree_index, foliage_canopy)
		foliage_multimesh.set_instance_color(tree_index, _get_tree_foliage_color(cell))
	var trunks := MultiMeshInstance3D.new()
	trunks.name = "TreeTrunks"
	trunks.multimesh = trunk_multimesh
	trunks.material_override = _tree_trunk_material
	chunk.add_child(trunks)
	var foliage := MultiMeshInstance3D.new()
	foliage.name = "TreeFoliage"
	foliage.multimesh = foliage_multimesh
	foliage.material_override = _tree_foliage_material
	chunk.add_child(foliage)


func _get_tree_trunk_color(cell: Vector2i) -> Color:
	var variation := _landscape_layout.get_cell_random(cell, 23)
	return Color(
		lerpf(0.72, 0.9, variation),
		lerpf(0.64, 0.8, variation),
		lerpf(0.56, 0.7, variation),
		1.0,
	)


func _get_tree_foliage_color(cell: Vector2i) -> Color:
	var brightness := lerpf(0.78, 0.94, _landscape_layout.get_cell_random(cell, 24))
	var warmth := _landscape_layout.get_cell_random(cell, 25)
	return Color(
		brightness * lerpf(0.96, 1.0, warmth),
		brightness * lerpf(0.99, 1.0, warmth),
		brightness * lerpf(0.99, 0.96, warmth),
		1.0,
	)


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
	ruin.set_meta(&"passage_clearance", 15.2)
	ruin.set_meta(&"visual_segment_count", RUIN_VISUAL_SEGMENTS)
	ruin.set_meta(&"collision_volume_count", RUIN_COLLISION_VOLUMES)
	_add_ruin_block(ruin, chunk_center, reference_height, ruin_center, forward, Vector2(-9.0, 0.0), Vector3(2.8, 9.0, 3.4), 0.0, "LeftColumn")
	_add_ruin_block(ruin, chunk_center, reference_height, ruin_center, forward, Vector2(9.0, 0.0), Vector3(2.8, 9.0, 3.4), 0.0, "RightColumn")
	_add_ruin_block(ruin, chunk_center, reference_height, ruin_center, forward, Vector2.ZERO, Vector3(21.0, 2.2, 3.6), 9.0, "Lintel")
	_add_ruin_block(ruin, chunk_center, reference_height, ruin_center, forward, Vector2(-12.0, 6.0), Vector3(4.8, 1.4, 10.0), 0.0, "LeftTerrace")
	_add_ruin_block(ruin, chunk_center, reference_height, ruin_center, forward, Vector2(12.0, 6.0), Vector3(4.8, 1.4, 10.0), 0.0, "RightTerrace")
	_add_ruin_pediment_collisions(ruin)
	_add_ruin_landmark_details(ruin)
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
			segment_count = 4
			split_axis = Vector3.UP
		"Lintel":
			segment_count = 9
			split_axis = Vector3.RIGHT
		"LeftTerrace", "RightTerrace":
			segment_count = 4
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
		var irregular_scale := 1.0 + 0.012 * sin(float(segment_index * 7 + segment_count * 3))
		visual.scale = segment_size * irregular_scale
		visual.rotation_degrees = Vector3(
			0.35 * sin(float(segment_index * 5 + segment_count)),
			0.45 * sin(float(segment_index * 3 + segment_count * 2)),
			0.3 * cos(float(segment_index * 4 + segment_count)),
		)
		ruin.add_child(visual)


func _add_ruin_pediment_collisions(ruin: StaticBody3D) -> void:
	var lintel := ruin.get_node("LintelCollision") as CollisionShape3D
	var lintel_size := (lintel.shape as BoxShape3D).size
	var lintel_top := lintel.position.y + lintel_size.y * 0.5
	var levels := [
		{"name": "PedimentBaseCollision", "width": 18.5, "height": 1.2, "bottom": 0.0},
		{"name": "PedimentMidCollision", "width": 13.2, "height": 0.6, "bottom": 1.2},
		{"name": "PedimentInnerCollision", "width": 7.9, "height": 0.8, "bottom": 1.8},
		{"name": "PedimentCrownCollision", "width": 2.5, "height": 1.0, "bottom": 2.6},
	]
	for level in levels:
		var collision := CollisionShape3D.new()
		collision.name = level.name
		var shape := BoxShape3D.new()
		shape.size = Vector3(level.width, level.height, 3.1)
		collision.shape = shape
		collision.position = Vector3(0.0, lintel_top + level.bottom + level.height * 0.5, 0.0)
		ruin.add_child(collision)


func _add_ruin_landmark_details(ruin: StaticBody3D) -> void:
	if DisplayServer.get_name() == "headless":
		return
	for side_name in ["Left", "Right"]:
		var column := ruin.get_node("%sColumnCollision" % side_name) as CollisionShape3D
		var column_size := (column.shape as BoxShape3D).size
		_add_ruin_detail(
			ruin,
			"%sColumnBase" % side_name,
			column.position - Vector3.UP * (column_size.y * 0.5 - 0.32),
			Vector3(3.4, 0.64, 4.0),
		)
		_add_ruin_detail(
			ruin,
			"%sColumnCap" % side_name,
			column.position + Vector3.UP * (column_size.y * 0.5 - 0.35),
			Vector3(3.5, 0.7, 4.0),
		)
		var side_sign := -1.0 if side_name == "Left" else 1.0
		_add_ruin_detail(
			ruin,
			"%sBrokenPylon" % side_name,
			column.position + Vector3.UP * (column_size.y * 0.5 + 1.25),
			Vector3(1.8, 2.5, 2.4),
			_ruin_material,
			Vector3(0.0, side_sign * 2.5, side_sign * 1.6),
		)
		for face_sign in [-1.0, 1.0]:
			_add_ruin_detail(
				ruin,
				"%sRelief%s" % [side_name, "Front" if face_sign > 0.0 else "Back"],
				column.position + Vector3(0.0, 0.15, face_sign * (column_size.z * 0.5 + 0.045)),
				Vector3(1.8, 3.4, 0.1),
				_ruin_recess_material,
			)
	var lintel := ruin.get_node("LintelCollision") as CollisionShape3D
	var lintel_size := (lintel.shape as BoxShape3D).size
	for face_sign in [-1.0, 1.0]:
		for panel_index in range(-2, 3):
			_add_ruin_detail(
				ruin,
				"LintelRelief%s%02d" % ["Front" if face_sign > 0.0 else "Back", panel_index + 2],
				lintel.position + Vector3(
					float(panel_index) * 3.35,
					0.0,
					face_sign * (lintel_size.z * 0.5 + 0.05),
				),
				Vector3(2.5, 1.15, 0.1),
				_ruin_recess_material,
			)
	var crest_heights := [1.2, 1.8, 2.6, 3.6, 2.6, 1.8, 1.2]
	for crest_index in range(crest_heights.size()):
		var crest_height: float = crest_heights[crest_index]
		var crest_x := (float(crest_index) - 3.0) * 2.65
		_add_ruin_detail(
			ruin,
			"CrestStone%02d" % crest_index,
			lintel.position + Vector3(
				crest_x,
				lintel_size.y * 0.5 + crest_height * 0.5 + 0.08,
				0.0,
			),
			Vector3(2.5, crest_height, 3.1),
		)


func _add_ruin_detail(
	ruin: StaticBody3D,
	detail_name: String,
	position: Vector3,
	size: Vector3,
	material: StandardMaterial3D = null,
	rotation_degrees := Vector3.ZERO,
) -> void:
	var visual := MeshInstance3D.new()
	visual.name = detail_name
	visual.mesh = _ruin_block_mesh
	visual.material_override = material if material != null else _ruin_material
	visual.position = position
	visual.scale = size
	visual.rotation_degrees = rotation_degrees
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
	for terrain in horizon_chunks.values():
		(terrain as MeshInstance3D).free()
	loaded_chunks.clear()
	horizon_chunks.clear()
	_desired_chunks.clear()
	_pending_chunks.clear()
