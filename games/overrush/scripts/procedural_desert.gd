class_name ProceduralDesert
extends StaticBody3D

@export_range(2400.0, 9600.0, 100.0) var map_size := 4800.0
@export_range(129, 513, 2) var grid_resolution := 385
@export var seed := 0
@export var summit_height := 280.0
@export var radial_grade := 0.145

@onready var terrain: MeshInstance3D = $Terrain
@onready var terrain_collision: CollisionShape3D = $TerrainCollision

var generated_seed := 0
var _broad_noise := FastNoiseLite.new()
var _ridge_noise := FastNoiseLite.new()
var _dune_noise := FastNoiseLite.new()


func _ready() -> void:
	generate()


func generate() -> void:
	generated_seed = seed
	if generated_seed == 0:
		var random_seed := RandomNumberGenerator.new()
		random_seed.randomize()
		generated_seed = random_seed.randi()
	_configure_noise()
	var terrain_data := _build_terrain()
	terrain.mesh = terrain_data.mesh
	if DisplayServer.get_name() != "headless":
		var material := ShaderMaterial.new()
		material.shader = load("res://shaders/desert.gdshader")
		material.set_shader_parameter("seed_offset", Vector2(generated_seed % 997, generated_seed % 619))
		terrain.material_override = material
	terrain_collision.shape = _build_collision(terrain_data.heights)
	var spacing := map_size / float(grid_resolution - 1)
	terrain_collision.scale = Vector3(spacing, 1.0, spacing)
	print("Dune Drifter desert — seed %s, %.1f km radial freeride field" % [str(generated_seed), map_size / 1000.0])


func get_spawn_position() -> Vector3:
	return Vector3(0.0, get_surface_height(0.0, 0.0) + 0.45, 0.0)


func get_surface_height(x: float, z: float) -> float:
	var radius := Vector2(x, z).length()
	var softened_radius := sqrt(radius * radius + 70.0 * 70.0) - 70.0
	var descent := softened_radius * radial_grade
	var feature_fade := smoothstep(55.0, 230.0, radius)
	var broad := _broad_noise.get_noise_2d(x, z) * 31.0
	var ridges := _ridge_noise.get_noise_2d(x, z)
	var folded_ridges := signf(ridges) * ridges * ridges * 22.0
	var dunes := _dune_noise.get_noise_2d(x, z) * 7.5
	return summit_height - descent + feature_fade * (broad + folded_ridges + dunes)


func get_surface_normal(x: float, z: float, sample_distance := 3.0) -> Vector3:
	var left := get_surface_height(x - sample_distance, z)
	var right := get_surface_height(x + sample_distance, z)
	var back := get_surface_height(x, z - sample_distance)
	var forward := get_surface_height(x, z + sample_distance)
	return Vector3(left - right, sample_distance * 2.0, back - forward).normalized()


func is_sand_shape(shape: Shape3D) -> bool:
	return shape == terrain_collision.shape


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


func _build_terrain() -> Dictionary:
	var vertex_count := grid_resolution * grid_resolution
	var spacing := map_size / float(grid_resolution - 1)
	var half_size := map_size * 0.5
	var heights := PackedFloat32Array()
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	heights.resize(vertex_count)
	vertices.resize(vertex_count)
	normals.resize(vertex_count)
	uvs.resize(vertex_count)

	for z_index in range(grid_resolution):
		var z := -half_size + z_index * spacing
		for x_index in range(grid_resolution):
			var x := -half_size + x_index * spacing
			var index := z_index * grid_resolution + x_index
			var height := get_surface_height(x, z)
			heights[index] = height
			vertices[index] = Vector3(x, height, z)
			uvs[index] = Vector2(x_index, z_index) / float(grid_resolution - 1)

	for z_index in range(grid_resolution):
		for x_index in range(grid_resolution):
			var index := z_index * grid_resolution + x_index
			var left := heights[z_index * grid_resolution + maxi(x_index - 1, 0)]
			var right := heights[z_index * grid_resolution + mini(x_index + 1, grid_resolution - 1)]
			var back := heights[maxi(z_index - 1, 0) * grid_resolution + x_index]
			var forward := heights[mini(z_index + 1, grid_resolution - 1) * grid_resolution + x_index]
			normals[index] = Vector3(left - right, spacing * 2.0, back - forward).normalized()

	var indices := PackedInt32Array()
	indices.resize((grid_resolution - 1) * (grid_resolution - 1) * 6)
	var write_index := 0
	for z_index in range(grid_resolution - 1):
		for x_index in range(grid_resolution - 1):
			var top_left := z_index * grid_resolution + x_index
			var top_right := top_left + 1
			var bottom_left := top_left + grid_resolution
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


func _build_collision(heights: PackedFloat32Array) -> HeightMapShape3D:
	var heightmap := HeightMapShape3D.new()
	heightmap.map_width = grid_resolution
	heightmap.map_depth = grid_resolution
	heightmap.map_data = heights
	return heightmap
