class_name ProceduralDesert
extends StaticBody3D

@export var tracked_body_path: NodePath
@export var tracked_camera_path: NodePath
@export_range(192.0, 768.0, 32.0) var chunk_size := 384.0
@export_range(25, 97, 8) var chunk_resolution := 49
@export_range(1, 4, 1) var active_radius := 2
@export_range(1, 4, 1) var chunks_per_frame := 2
@export var rebase_distance := 1536.0
@export var seed := 0
@export var summit_height := 280.0
@export var radial_grade := 0.145

var generated_seed := 0
var world_origin := Vector3.ZERO
var loaded_chunks: Dictionary = {}

var _tracked_body: Node3D
var _tracked_camera: Node3D
var _stream_center := Vector2i(2147483647, 2147483647)
var _desired_chunks: Dictionary = {}
var _pending_chunks: Array[Vector2i] = []
var _sand_material: ShaderMaterial
var _rock_material: StandardMaterial3D
var _rock_mesh: SphereMesh
var _broad_noise := FastNoiseLite.new()
var _ridge_noise := FastNoiseLite.new()
var _dune_noise := FastNoiseLite.new()
var _feature_grammar := DesertFeatureGrammar.new()


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
	_create_materials()
	_stream_center = Vector2i(2147483647, 2147483647)
	_set_stream_focus(Vector2.ZERO, true)
	print(
		"Dune Drifter desert — seed %s, %d seamless chunks around an unbounded radial field"
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
	var softened_radius := sqrt(radius * radius + 70.0 * 70.0) - 70.0
	var descent := softened_radius * radial_grade
	var feature_fade := smoothstep(55.0, 230.0, radius)
	var broad := _broad_noise.get_noise_2d(x, z) * 31.0
	var ridges := _ridge_noise.get_noise_2d(x, z)
	var folded_ridges := signf(ridges) * ridges * ridges * 22.0
	var dunes := _dune_noise.get_noise_2d(x, z) * 7.5
	var authored_feature := _feature_grammar.sample_height_offset(x, z)
	return summit_height - descent + feature_fade * (broad + folded_ridges + dunes + authored_feature)


func get_local_surface_height(x: float, z: float) -> float:
	var logical := get_world_position(Vector3(x, 0.0, z))
	return get_surface_height(logical.x, logical.z) - world_origin.y


func get_surface_normal(x: float, z: float, sample_distance := 3.0) -> Vector3:
	var left := get_surface_height(x - sample_distance, z)
	var right := get_surface_height(x + sample_distance, z)
	var back := get_surface_height(x, z - sample_distance)
	var forward := get_surface_height(x, z + sample_distance)
	return Vector3(left - right, sample_distance * 2.0, back - forward).normalized()


func is_sand_collider(collider: Object) -> bool:
	return collider is StaticBody3D and collider.get_meta(&"dune_drifter_sand", false)


func is_rock_collider(collider: Object) -> bool:
	return collider is StaticBody3D and collider.get_meta(&"dune_drifter_rock", false)


func get_feature_kind_at(logical_position: Vector2) -> StringName:
	return _feature_grammar.get_feature_kind_at(logical_position)


func get_feature_height_offset(logical_position: Vector2) -> float:
	return _feature_grammar.sample_height_offset(logical_position.x, logical_position.y)


func chunk_has_rock_passage(coord: Vector2i) -> bool:
	return Vector2(coord).length() * chunk_size >= 420.0 and _feature_grammar.get_cell_random(coord, 31) <= 0.38


func get_loaded_rock_bodies() -> Array[StaticBody3D]:
	var rocks: Array[StaticBody3D] = []
	for chunk_value in loaded_chunks.values():
		var chunk: StaticBody3D = chunk_value
		for child in chunk.get_children():
			if child is StaticBody3D and is_rock_collider(child):
				rocks.append(child)
	return rocks


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
	chunk.name = "Sand_%d_%d" % [coord.x, coord.y]
	chunk.set_meta(&"dune_drifter_sand", true)
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
	mesh_instance.material_override = _sand_material
	chunk.add_child(mesh_instance)
	var collision := CollisionShape3D.new()
	collision.name = "TerrainCollision"
	collision.shape = _build_chunk_collision(chunk_data.heights)
	var spacing := chunk_size / float(chunk_resolution - 1)
	collision.scale = Vector3(spacing, 1.0, spacing)
	chunk.add_child(collision)
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
	heights.resize(vertex_count)
	vertices.resize(vertex_count)
	normals.resize(vertex_count)
	uvs.resize(vertex_count)

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
	if is_instance_valid(_sand_material):
		_sand_material.set_shader_parameter("world_origin", Vector2(world_origin.x, world_origin.z))


func _chunk_distance_squared(coord: Vector2i) -> int:
	var delta := coord - _stream_center
	return delta.x * delta.x + delta.y * delta.y


func _configure_noise() -> void:
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
	_sand_material = null
	_rock_material = null
	_rock_mesh = SphereMesh.new()
	_rock_mesh.radius = 1.0
	_rock_mesh.height = 2.0
	_rock_mesh.radial_segments = 12
	_rock_mesh.rings = 6
	if DisplayServer.get_name() != "headless":
		_sand_material = ShaderMaterial.new()
		_sand_material.shader = load("res://shaders/desert.gdshader")
		_sand_material.set_shader_parameter("seed_offset", Vector2(generated_seed % 997, generated_seed % 619))
		_sand_material.set_shader_parameter("world_origin", Vector2.ZERO)
		_rock_material = StandardMaterial3D.new()
		_rock_material.albedo_color = Color("#4a2418")
		_rock_material.roughness = 0.94


func _add_rock_passage(chunk: StaticBody3D, coord: Vector2i, reference_height: float) -> void:
	var chunk_center := Vector2(coord) * chunk_size
	if not chunk_has_rock_passage(coord):
		return
	var passage_center := chunk_center + Vector2(
		lerpf(-72.0, 72.0, _feature_grammar.get_cell_random(coord, 32)),
		lerpf(-72.0, 72.0, _feature_grammar.get_cell_random(coord, 33)),
	)
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
		rock.set_meta(&"dune_drifter_rock", true)
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
