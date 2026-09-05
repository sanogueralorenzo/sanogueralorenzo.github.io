extends RefCounted
## Map palette and grouped construction, composing the shared mesh/collision mechanisms.
var ground_height: Callable
var root: Node3D
var body: StaticBody3D
var groups: Dictionary = {}
var materials: Dictionary = {}
var meshes: Dictionary = {}


func _init(parent: Node3D) -> void:
	root = parent
	body = StaticBody3D.new()
	body.name = "Park and neighborhood collision"
	root.add_child(body)


func material(color: String, finish: int = 0) -> Material:
	var key = color + str(finish)
	if not materials.has(key):
		var mat = ShaderMaterial.new()
		mat.shader = preload("res://maps/daan_gardens/surface.gdshader")
		mat.set_shader_parameter("tint", Color(color))
		mat.set_shader_parameter("finish", finish)
		materials[key] = mat
	return materials[key]


func shape(kind: String) -> Mesh:
	if not meshes.has(kind):
		match kind:
			"box":
				meshes[kind] = CozyPrimitives.box_mesh()
			"sphere":
				meshes[kind] = CozyPrimitives.sphere_mesh()
			"branch":
				meshes[kind] = CozyPrimitives.cylinder_mesh(.5, .25, 1, 9)
			_:
				meshes[kind] = CozyPrimitives.cylinder_mesh(.5, .5, 1, 12)
	return meshes[kind]


func add(
	kind: String,
	pos: Vector3,
	size: Vector3,
	color: String,
	rotation: Vector3 = Vector3.ZERO,
	solid: bool = false,
	finish: int = 0
) -> void:
	var key = kind + color + str(finish)
	if not groups.has(key):
		groups[key] = {"mesh": shape(kind), "material": material(color, finish), "transforms": []}
	groups[key].transforms.append(Transform3D(Basis.from_euler(rotation) * Basis.from_scale(size), pos))
	if solid:
		CozyCollision.box(body, pos, size, rotation)


func box(pos: Vector3, size: Vector3, color: String, solid: bool = false, yaw: float = 0, finish: int = 0) -> void:
	add("box", pos, size, color, Vector3(0, yaw, 0), solid, finish)


func beam(a: Vector3, b: Vector3, radius: float, color: String) -> void:
	add(
		"cylinder",
		(a + b) * .5,
		Vector3(radius * 2, a.distance_to(b), radius * 2),
		color,
		Quaternion(Vector3.UP, (b - a).normalized()).get_euler()
	)


func mesh(mesh_value: Mesh, color: String, solid: bool = false, finish: int = 0) -> MeshInstance3D:
	var node = CozyPrimitives.instance(root, mesh_value, Vector3.ZERO, material(color, finish))
	if solid:
		CozyCollision.mesh(body, mesh_value)
	return node


func ribbon(
	points: Array, width: float, color: String, finish: int = 1, solid: bool = false, drape: bool = true
) -> void:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pairs = []
	for i in range(points.size()):
		var before: Vector3 = points[maxi(0, i - 1)]
		var after: Vector3 = points[mini(points.size() - 1, i + 1)]
		if points[0].is_equal_approx(points[-1]) and i in [0, points.size() - 1]:
			before = points[-2]
			after = points[1]
		var side = (after - before).cross(Vector3.UP).normalized() * width * .5
		var a: Vector3 = points[i] - side
		var b: Vector3 = points[i] + side
		if drape and ground_height.is_valid():
			var lift = points[i].y - ground_height.call(points[i].x, points[i].z)
			a.y = ground_height.call(a.x, a.z) + lift
			b.y = ground_height.call(b.x, b.z) + lift
		pairs.append([a, b])
	for i in range(points.size() - 1):
		for at in [pairs[i][0], pairs[i + 1][0], pairs[i + 1][1], pairs[i][0], pairs[i + 1][1], pairs[i][1]]:
			st.add_vertex(at)
	st.generate_normals()
	mesh(st.commit(), color, solid, finish)


func disc(at: Vector3, radius: float, color: String, finish: int = 1) -> void:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lift = at.y - ground_height.call(at.x, at.z) if ground_height.is_valid() else 0.
	for i in range(64):
		for v in [
			at,
			at + Vector3(cos(i * TAU / 64), 0, sin(i * TAU / 64)) * radius,
			at + Vector3(cos((i + 1) * TAU / 64), 0, sin((i + 1) * TAU / 64)) * radius
		]:
			if ground_height.is_valid():
				v.y = ground_height.call(v.x, v.z) + lift
			st.add_vertex(v)
	st.generate_normals()
	mesh(st.commit(), color, false, finish)


func label(text: String, at: Vector3, width: float, color: String = "ede8cd", yaw: float = 0) -> void:
	var n = Label3D.new()
	n.text = text
	n.position = at
	n.rotation.y = yaw
	n.font_size = 64
	n.pixel_size = minf(width / maxf(1, text.length() * 36.48), .008)
	n.modulate = Color(color)
	n.outline_size = 0
	n.shaded = true
	n.double_sided = false
	n.visibility_range_end = 65
	root.add_child(n)


func finish() -> void:
	for group in groups.values():
		CozyMeshBatches.spatial(root, group.mesh, group.material, group.transforms, "Crafted park", 32)
	groups.clear()
