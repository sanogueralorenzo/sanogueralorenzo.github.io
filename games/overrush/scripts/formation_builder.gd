extends RefCounted

const SPIRE := "spire"
const BOULDER := "boulder"
const RIDGE := "ridge"

var placements: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()
var _grammar
var _map_size: float


func plan_layout(seed: int, grammar, map_size: float) -> void:
	placements.clear()
	_grammar = grammar
	_map_size = map_size
	_rng.seed = seed ^ 0x5F3759DF
	_plan_spires(62)
	_plan_boulder_clusters(38)
	_plan_distant_ridges(26)


func build(host: StaticBody3D, visual_root: Node3D) -> void:
	for child in visual_root.get_children():
		child.queue_free()
	for child in host.get_children():
		if child.has_meta("overrush_formation_collider"):
			child.queue_free()

	var material := ShaderMaterial.new()
	material.shader = load("res://shaders/landmark.gdshader")
	material.set_shader_parameter("route_length", _grammar.route_length)
	material.set_shader_parameter("region_breaks", _grammar.region_breaks)
	var rock_mesh := _build_irregular_rock_mesh()
	rock_mesh.surface_set_material(0, material)
	var rock_shape := rock_mesh.create_convex_shape(true, false)
	_build_rock_multimesh(host, visual_root, SPIRE, "RockSpires", rock_mesh, rock_shape, true)
	_build_rock_multimesh(host, visual_root, BOULDER, "BoulderFields", rock_mesh, rock_shape, true)
	_build_rock_multimesh(host, visual_root, RIDGE, "DistantRidges", rock_mesh, rock_shape, false)


func validate_layout(grammar) -> PackedStringArray:
	var errors := PackedStringArray()
	var counts := {SPIRE: 0, BOULDER: 0, RIDGE: 0}
	for placement in placements:
		counts[placement.type] += 1
		if placement.blocks_route:
			var position: Vector3 = placement.position
			if grammar.get_route_clearance(position.x, position.z) < 1.12:
				errors.append("%s blocks the authored route corridor" % placement.type)
	for type in counts:
		if counts[type] == 0:
			errors.append("formation grammar produced no %s placements" % type)
	return errors


func _plan_spires(count: int) -> void:
	var half_size := _map_size * 0.5 - 80.0
	var placed := 0
	var attempts := 0
	while placed < count and attempts < count * 40:
		attempts += 1
		var x := _rng.randf_range(-half_size, half_size)
		var z := _rng.randf_range(-half_size, half_size)
		if Vector2(x, z).length() < 190.0 or _grammar.get_route_clearance(x, z) < 1.32:
			continue
		var radius := _rng.randf_range(7.0, 20.0)
		var height := _rng.randf_range(34.0, 125.0)
		if _rng.randf() < 0.18:
			height *= _rng.randf_range(1.35, 1.75)
			radius *= 0.72
		var position := Vector3(x, _grammar.sample_height(x, z), z)
		var scale := Vector3(radius, height * 0.5, radius * _rng.randf_range(0.72, 1.28))
		placements.append(_rock_placement(SPIRE, position, scale, true))
		placed += 1


func _plan_boulder_clusters(cluster_count: int) -> void:
	var half_size := _map_size * 0.5 - 70.0
	var planned_clusters := 0
	var attempts := 0
	while planned_clusters < cluster_count and attempts < cluster_count * 40:
		attempts += 1
		var anchor := Vector2(
			_rng.randf_range(-half_size, half_size),
			_rng.randf_range(-half_size, half_size)
		)
		if anchor.length() < 170.0 or _grammar.get_route_clearance(anchor.x, anchor.y) < 1.42:
			continue
		for piece_index in range(3):
			var offset := Vector2.from_angle(_rng.randf_range(-PI, PI)) * _rng.randf_range(0.0, 24.0)
			var x := anchor.x + offset.x
			var z := anchor.y + offset.y
			if _grammar.get_route_clearance(x, z) < 1.18:
				offset *= -1.0
				x = anchor.x + offset.x
				z = anchor.y + offset.y
			if _grammar.get_route_clearance(x, z) < 1.18:
				x = anchor.x
				z = anchor.y
			var radius := _rng.randf_range(5.0, 14.0) * (1.2 if piece_index == 0 else 0.8)
			var position := Vector3(x, _grammar.sample_height(x, z), z)
			var scale := Vector3(
				radius * _rng.randf_range(0.8, 1.4),
				radius * _rng.randf_range(0.48, 0.82),
				radius * _rng.randf_range(0.8, 1.35)
			)
			placements.append(_rock_placement(BOULDER, position, scale, true))
		planned_clusters += 1


func _plan_distant_ridges(count: int) -> void:
	var half_size := _map_size * 0.5
	for index in range(count):
		var side := -1.0 if index % 2 == 0 else 1.0
		var x := side * _rng.randf_range(half_size * 0.58, half_size * 0.9)
		var z := _rng.randf_range(-half_size * 0.96, half_size * 0.2)
		var position := Vector3(x, _grammar.sample_height(x, z), z)
		var scale := Vector3(
			_rng.randf_range(45.0, 105.0),
			_rng.randf_range(28.0, 82.0),
			_rng.randf_range(15.0, 34.0)
		)
		placements.append(_rock_placement(RIDGE, position, scale, false))


func _rock_placement(type: String, position: Vector3, scale: Vector3, blocks_route: bool) -> Dictionary:
	var yaw := _rng.randf_range(-PI, PI)
	var basis := Basis(Vector3.UP, yaw).scaled(scale)
	var footprint_radius := maxf(scale.x, scale.z) * 0.72
	var lowest_ground := position.y
	for sample_index in range(8):
		var angle := sample_index / 8.0 * TAU + yaw
		var sample_x := position.x + cos(angle) * footprint_radius
		var sample_z := position.z + sin(angle) * footprint_radius
		lowest_ground = minf(lowest_ground, _grammar.sample_height(sample_x, sample_z))
	var embedded_position := Vector3(position.x, lowest_ground - clampf(footprint_radius * 0.08, 0.8, 3.5), position.z)
	return {
		"type": type,
		"position": embedded_position,
		"transform": Transform3D(basis, embedded_position),
		"blocks_route": blocks_route,
	}


func _build_rock_multimesh(
	host: StaticBody3D,
	visual_root: Node3D,
	type: String,
	name: String,
	mesh: ArrayMesh,
	shape: Shape3D,
	with_collision: bool
) -> void:
	var matching: Array[Dictionary] = []
	for placement in placements:
		if placement.type == type:
			matching.append(placement)
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = matching.size()
	for index in range(matching.size()):
		multimesh.set_instance_transform(index, matching[index].transform)
		if with_collision:
			var collider := CollisionShape3D.new()
			collider.name = "%sCollision%03d" % [name, index]
			collider.shape = shape
			collider.transform = matching[index].transform
			collider.set_meta("overrush_formation_collider", true)
			host.add_child(collider)
	var instance := MultiMeshInstance3D.new()
	instance.name = name
	instance.multimesh = multimesh
	visual_root.add_child(instance)


func _build_irregular_rock_mesh() -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sides := 9
	var levels := 5
	var radii := [0.72, 1.0, 0.82, 0.48, 0.08]
	for level in range(levels - 1):
		var y0 := level / float(levels - 1) * 2.0
		var y1 := (level + 1) / float(levels - 1) * 2.0
		for side in range(sides):
			var next_side := (side + 1) % sides
			var angle0 := side / float(sides) * TAU
			var angle1 := next_side / float(sides) * TAU
			var wobble0 := 1.0 + sin(side * 4.71 + level * 1.9) * 0.12
			var wobble1 := 1.0 + sin(next_side * 4.71 + level * 1.9) * 0.12
			var wobble2 := 1.0 + sin(side * 4.71 + (level + 1) * 1.9) * 0.12
			var wobble3 := 1.0 + sin(next_side * 4.71 + (level + 1) * 1.9) * 0.12
			var p00 := Vector3(cos(angle0), y0, sin(angle0)) * Vector3(radii[level] * wobble0, 1.0, radii[level] * wobble0)
			var p01 := Vector3(cos(angle1), y0, sin(angle1)) * Vector3(radii[level] * wobble1, 1.0, radii[level] * wobble1)
			var p10 := Vector3(cos(angle0), y1, sin(angle0)) * Vector3(radii[level + 1] * wobble2, 1.0, radii[level + 1] * wobble2)
			var p11 := Vector3(cos(angle1), y1, sin(angle1)) * Vector3(radii[level + 1] * wobble3, 1.0, radii[level + 1] * wobble3)
			_add_triangle(surface, p00, p10, p01)
			_add_triangle(surface, p01, p10, p11)
	for side in range(sides):
		var next_side := (side + 1) % sides
		var p0 := Vector3(cos(side / float(sides) * TAU) * radii[0], 0.0, sin(side / float(sides) * TAU) * radii[0])
		var p1 := Vector3(cos(next_side / float(sides) * TAU) * radii[0], 0.0, sin(next_side / float(sides) * TAU) * radii[0])
		_add_triangle(surface, Vector3.ZERO, p1, p0)
	surface.generate_normals()
	return surface.commit()


func _add_triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	surface.set_uv(Vector2(a.x, a.y))
	surface.add_vertex(a)
	surface.set_uv(Vector2(b.x, b.y))
	surface.add_vertex(b)
	surface.set_uv(Vector2(c.x, c.y))
	surface.add_vertex(c)
