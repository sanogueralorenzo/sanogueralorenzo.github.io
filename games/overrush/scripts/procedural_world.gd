extends StaticBody3D

@export_range(800.0, 6400.0, 100.0) var map_size: float = 3200.0
@export_range(65, 513, 2) var grid_resolution: int = 257
@export var seed: int = 0
@export_range(0, 300, 1) var landmark_count: int = 150

@onready var terrain: MeshInstance3D = $Terrain
@onready var terrain_collision: CollisionShape3D = $TerrainCollision
@onready var landmarks: MultiMeshInstance3D = $Landmarks

var generated_seed: int
var _rng := RandomNumberGenerator.new()
var _broad_noise := FastNoiseLite.new()
var _ridge_noise := FastNoiseLite.new()
var _detail_noise := FastNoiseLite.new()
var _route_noise := FastNoiseLite.new()
var _route_phase: float
var _route_offset: float


func _ready() -> void:
	generate()


func generate() -> void:
	generated_seed = seed
	if generated_seed == 0:
		_rng.randomize()
		generated_seed = _rng.randi()
	_rng.seed = generated_seed
	_configure_noise()

	var terrain_mesh := _build_terrain_mesh()
	var terrain_material := ShaderMaterial.new()
	terrain_material.shader = load("res://shaders/terrain.gdshader")
	terrain.mesh = terrain_mesh
	terrain.material_override = terrain_material
	terrain_collision.shape = terrain_mesh.create_trimesh_shape()
	_generate_landmarks()
	print("Overrush world generated — seed %s, %.1f km square" % [str(generated_seed), map_size / 1000.0])


func get_spawn_position() -> Vector3:
	return Vector3(0.0, _sample_height(0.0, 0.0) + 3.5, 0.0)


func _configure_noise() -> void:
	_broad_noise.seed = _rng.randi()
	_broad_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_broad_noise.frequency = 0.00115
	_broad_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_broad_noise.fractal_octaves = 5
	_broad_noise.fractal_lacunarity = 2.05
	_broad_noise.fractal_gain = 0.48

	_ridge_noise.seed = _rng.randi()
	_ridge_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_ridge_noise.frequency = 0.00185
	_ridge_noise.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_ridge_noise.fractal_octaves = 4
	_ridge_noise.fractal_lacunarity = 2.2
	_ridge_noise.fractal_gain = 0.52

	_detail_noise.seed = _rng.randi()
	_detail_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_detail_noise.frequency = 0.0075
	_detail_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_detail_noise.fractal_octaves = 3
	_detail_noise.fractal_gain = 0.42

	_route_noise.seed = _rng.randi()
	_route_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_route_noise.frequency = 0.0022
	_route_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_route_noise.fractal_octaves = 3
	_route_phase = _rng.randf_range(-PI, PI)
	_route_offset = _raw_route_center(0.0)


func _build_terrain_mesh() -> ArrayMesh:
	var resolution := grid_resolution
	var vertex_count := resolution * resolution
	var spacing := map_size / float(resolution - 1)
	var half_size := map_size * 0.5
	var heights := PackedFloat32Array()
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	heights.resize(vertex_count)
	vertices.resize(vertex_count)
	normals.resize(vertex_count)
	uvs.resize(vertex_count)

	for z_index in range(resolution):
		var z := -half_size + z_index * spacing
		for x_index in range(resolution):
			var x := -half_size + x_index * spacing
			var index := z_index * resolution + x_index
			var height := _sample_height(x, z)
			heights[index] = height
			vertices[index] = Vector3(x, height, z)
			uvs[index] = Vector2(x_index, z_index) / float(resolution - 1)

	for z_index in range(resolution):
		for x_index in range(resolution):
			var index := z_index * resolution + x_index
			var left := heights[z_index * resolution + maxi(x_index - 1, 0)]
			var right := heights[z_index * resolution + mini(x_index + 1, resolution - 1)]
			var back := heights[maxi(z_index - 1, 0) * resolution + x_index]
			var forward := heights[mini(z_index + 1, resolution - 1) * resolution + x_index]
			normals[index] = Vector3(left - right, spacing * 2.0, back - forward).normalized()

	var quad_count := (resolution - 1) * (resolution - 1)
	var indices := PackedInt32Array()
	indices.resize(quad_count * 6)
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
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _sample_height(x: float, z: float) -> float:
	var broad := _broad_noise.get_noise_2d(x, z) * 112.0
	var ridge_value := maxf(_ridge_noise.get_noise_2d(x, z), -0.15)
	var ridges := ridge_value * absf(ridge_value) * 118.0
	var detail := _detail_noise.get_noise_2d(x, z) * 17.0
	var terrain_height := broad + ridges + detail

	var route_center := _raw_route_center(z) - _route_offset
	var route_distance := absf(x - route_center)
	var route_influence := 1.0 - smoothstep(72.0, 285.0, route_distance)
	var route_height := sin(z * 0.0062 + _route_phase) * 18.0
	route_height += _route_noise.get_noise_1d(z) * 25.0
	terrain_height = lerpf(terrain_height, route_height, route_influence * 0.82)

	var start_blend := smoothstep(12.0, 82.0, Vector2(x, z).length())
	return lerpf(0.0, terrain_height, start_blend)


func _raw_route_center(z: float) -> float:
	return sin(z * 0.00185 + _route_phase) * 245.0 + sin(z * 0.0047 - _route_phase * 0.35) * 82.0


func _generate_landmarks() -> void:
	var landmark_mesh := SphereMesh.new()
	landmark_mesh.radius = 1.0
	landmark_mesh.height = 2.0
	landmark_mesh.radial_segments = 14
	landmark_mesh.rings = 7
	var landmark_material := ShaderMaterial.new()
	landmark_material.shader = load("res://shaders/landmark.gdshader")
	landmark_mesh.material = landmark_material

	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = landmark_mesh
	multimesh.instance_count = landmark_count
	var half_size := map_size * 0.5 - 90.0
	var placed := 0
	var attempts := 0
	while placed < landmark_count and attempts < landmark_count * 24:
		attempts += 1
		var x := _rng.randf_range(-half_size, half_size)
		var z := _rng.randf_range(-half_size, half_size)
		var distance_from_spawn := Vector2(x, z).length()
		var route_distance := absf(x - (_raw_route_center(z) - _route_offset))
		if distance_from_spawn < 190.0 or route_distance < 118.0:
			continue

		var radius := _rng.randf_range(7.0, 22.0)
		var height := _rng.randf_range(38.0, 138.0)
		if _rng.randf() < 0.16:
			height *= _rng.randf_range(1.35, 1.9)
			radius *= _rng.randf_range(0.65, 0.9)
		var ground_height := _sample_height(x, z)
		var basis := Basis.from_euler(Vector3(0.0, _rng.randf_range(-PI, PI), 0.0))
		basis = basis.scaled(Vector3(radius, height * 0.5, radius))
		var landmark_position := Vector3(x, ground_height + height * 0.48, z)
		multimesh.set_instance_transform(placed, Transform3D(basis, landmark_position))

		var shape := CapsuleShape3D.new()
		shape.radius = radius * 0.78
		shape.height = maxf(height * 0.9, shape.radius * 2.0)
		var collider := CollisionShape3D.new()
		collider.name = "LandmarkCollision%03d" % placed
		collider.shape = shape
		collider.position = landmark_position
		add_child(collider)
		placed += 1

	landmarks.multimesh = multimesh
