extends StaticBody3D

const TerrainGrammar = preload("res://scripts/terrain_grammar.gd")
const FormationBuilder = preload("res://scripts/formation_builder.gd")

@export_range(800.0, 6400.0, 100.0) var map_size: float = 3200.0
@export_range(65, 513, 2) var grid_resolution: int = 321
@export var seed: int = 0

@onready var terrain: MeshInstance3D = $Terrain
@onready var terrain_collision: CollisionShape3D = $TerrainCollision
@onready var formations: Node3D = $Formations

var generated_seed: int
var grammar = TerrainGrammar.new()
var formation_builder = FormationBuilder.new()


func _ready() -> void:
	generate()


func generate() -> void:
	generated_seed = seed
	if generated_seed == 0:
		var random_seed := RandomNumberGenerator.new()
		random_seed.randomize()
		generated_seed = random_seed.randi()
	grammar.configure(generated_seed, map_size)

	var terrain_data := _build_terrain()
	var terrain_mesh: ArrayMesh = terrain_data.mesh
	var terrain_material := ShaderMaterial.new()
	terrain_material.shader = load("res://shaders/terrain.gdshader")
	terrain_material.set_shader_parameter("map_size", map_size)
	terrain_material.set_shader_parameter("route_length", grammar.route_length)
	terrain_material.set_shader_parameter("region_breaks", grammar.region_breaks)
	terrain_material.set_shader_parameter("palette_phase", grammar.palette_phase)
	terrain.mesh = terrain_mesh
	terrain.material_override = terrain_material
	terrain_collision.shape = _build_terrain_collision(terrain_data.heights)
	var terrain_spacing := map_size / float(grid_resolution - 1)
	terrain_collision.scale = Vector3(terrain_spacing, 1.0, terrain_spacing)

	formation_builder.plan_layout(generated_seed, grammar, map_size)
	formation_builder.build(self, formations)
	print(
		"Overrush route world — seed %s, %.1f km, %d sections, alternate: %s"
		% [str(generated_seed), map_size / 1000.0, grammar.sections.size(), str(grammar.has_alternate_route)]
	)


func get_spawn_position() -> Vector3:
	return grammar.get_spawn_position()


func get_region_name(z: float) -> String:
	return grammar.get_region_name(z)


func _build_terrain() -> Dictionary:
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
			var height: float = grammar.sample_height(x, z)
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
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return {"mesh": mesh, "heights": heights}


func _build_terrain_collision(heights: PackedFloat32Array) -> HeightMapShape3D:
	var heightmap := HeightMapShape3D.new()
	heightmap.map_width = grid_resolution
	heightmap.map_depth = grid_resolution
	heightmap.map_data = heights
	return heightmap
