extends RefCounted
## Harbor's static geometry is batched by material and spatial cell.
var root: Node3D
var groups = {}
var materials = {}
var primitives = {}
var collision: PhysicsBody3D
var ground_height: Callable
var plant_clearance: Callable
var leaf_texture: Texture2D


func _init(parent: Node3D, moving: bool = false) -> void:
	root = parent
	collision = AnimatableBody3D.new() if moving else StaticBody3D.new()
	collision.name = "District collision"
	root.add_child(collision)


func material(color: String, kind: String = "plaster") -> Material:
	var key = color + kind
	if materials.has(key):
		return materials[key]
	var m = ShaderMaterial.new()
	if kind == "foliage":
		m.shader = load("res://maps/harbor_hills/leaves.gdshader")
		m.set_shader_parameter("leaf_cards", true)
		if leaf_texture == null:
			leaf_texture = preload("res://maps/harbor_hills/textures.gd").leaf_spray()
		m.set_shader_parameter("leaf_texture", leaf_texture)
		m.set_shader_parameter("base_color", Color(color))
		materials[key] = m
		return m
	m.shader = load("res://maps/harbor_hills/surface.gdshader")
	m.set_shader_parameter("base_color", Color(color))
	m.set_shader_parameter("grain", .045 if kind == "metal" else .12)
	m.set_shader_parameter(
		"pattern",
		(
			1
			if kind == "siding"
			else (
				2
				if kind == "brick"
				else (3 if kind == "roof" else 4 if kind == "asphalt" else 5 if kind == "paving" else 0)
			)
		)
	)
	materials[key] = m
	return m


func shape(kind: String) -> Mesh:
	if primitives.has(kind):
		return primitives[kind]
	var mesh: Mesh
	if kind == "box":
		mesh = CozyPrimitives.box_mesh()
	elif kind == "sphere":
		mesh = CozyPrimitives.sphere_mesh()
	elif kind == "leaf":
		var st = SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var random = RandomNumberGenerator.new()
		random.seed = 491
		for i in range(28):
			var center = Vector3(
				random.randf_range(-.48, .48), random.randf_range(-.35, .35), random.randf_range(-.48, .48)
			)
			var normal = (
				Vector3(random.randf_range(-1, 1), random.randf_range(.15, 1), random.randf_range(-1, 1)).normalized()
			)
			var basis = Basis(Quaternion(Vector3.FORWARD, normal))
			var radius = random.randf_range(.22, .35)
			var shade = random.randf_range(.72, 1.22)
			st.set_color(Color(shade, shade, shade))
			var corners = [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]
			for j in [0, 1, 2, 0, 2, 3]:
				st.set_uv(corners[j] * .5 + Vector2.ONE * .5)
				st.set_normal((center * Vector3(1, 2, 1) + normal * .18 + Vector3.UP * .2).normalized())
				st.add_vertex(center + basis * Vector3(corners[j].x * radius, corners[j].y * radius, 0))
		mesh = st.commit()
	else:
		mesh = CozyPrimitives.cylinder_mesh(.5, .5, 1)
	primitives[kind] = mesh
	return mesh


func add(
	kind: String,
	pos: Vector3,
	size: Vector3,
	color: String,
	rotation: Vector3 = Vector3.ZERO,
	solid: bool = false,
	finish: String = "plaster"
) -> void:
	if kind == "leaf":
		if plant_clearance.is_valid() and plant_clearance.call(pos.x, pos.z, .4):
			return
		finish = "foliage"
	var transform = Transform3D(Basis.from_euler(rotation) * Basis.from_scale(size), pos)
	var cell = Vector2i(floori(pos.x / 40), floori(pos.z / 40))
	var key = kind + color + finish + str(cell)
	if not groups.has(key):
		groups[key] = {"kind": kind, "material": material(color, finish), "transforms": [], "cell": cell}
	groups[key].transforms.append(transform)
	if solid:
		box_collision(pos, size, rotation)


func box(
	pos: Vector3, size: Vector3, color: String, solid: bool = false, yaw: float = 0, finish: String = "plaster"
) -> void:
	add("box", pos, size, color, Vector3(0, yaw, 0), solid, finish)


func box_collision(pos: Vector3, size: Vector3, rotation: Vector3 = Vector3.ZERO) -> void:
	CozyCollision.box(collision, pos, size, rotation)


func beam(a: Vector3, b: Vector3, radius: float, color: String) -> void:
	var delta = b - a
	add(
		"cylinder",
		(a + b) * .5,
		Vector3(radius * 2, delta.length(), radius * 2),
		color,
		Quaternion(Vector3.UP, delta.normalized()).get_euler(),
		false,
		"metal"
	)


func ribbon(
	points: Array, width: float, color: String, solid: bool = false, drape: bool = true, finish: String = "plaster"
) -> void:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(points.size() - 1):
		var a: Vector3 = points[i]
		var b: Vector3 = points[i + 1]
		var side = (b - a).cross(Vector3.UP).normalized() * width * .5
		var corners = [a - side, b - side, b + side, a + side]
		if drape and ground_height.is_valid():
			# Keep the authored clearance while sampling both sides of the slope.
			var clearance_a = a.y - ground_height.call(a.x, a.z)
			var clearance_b = b.y - ground_height.call(b.x, b.z)
			for j in range(4):
				var v: Vector3 = corners[j]
				v.y = ground_height.call(v.x, v.z) + (clearance_a if j in [0, 3] else clearance_b)
				corners[j] = v
		for j in [0, 1, 2, 0, 2, 3]:
			st.add_vertex(corners[j])
		if solid and not drape:
			for edge in [[0, 1], [2, 3]]:
				var left: Vector3 = corners[edge[0]]
				var right: Vector3 = corners[edge[1]]
				for vertex in [
					left, right, right - Vector3.UP * .18, left, right - Vector3.UP * .18, left - Vector3.UP * .18
				]:
					st.add_vertex(vertex)
	st.generate_normals()
	var mesh = st.commit()
	var node = MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material(color, finish)
	root.add_child(node)
	if solid:
		CozyCollision.mesh(collision, mesh)


func semicircle(
	center: Vector2,
	forward: Vector2,
	inner: float,
	outer: float,
	lift: float,
	color: String,
	solid: bool = false,
	finish: String = "plaster"
) -> void:
	# Shared polar vertices close every seam; short radial bands conform to the hill.
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var side = forward.orthogonal()
	var bands = ceili((outer - inner) / .9)
	for ring in range(bands):
		for segment in range(48):
			for corner in [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 0), Vector2(1, 1), Vector2(0, 1)]:
				var radius = lerpf(inner, outer, (ring + corner.x) / bands)
				var angle = PI * (segment + corner.y) / 48.
				var at = center + (side * cos(angle) + forward * sin(angle)) * radius
				st.add_vertex(Vector3(at.x, ground_height.call(at.x, at.y) + lift, at.y))
	st.generate_normals()
	var mesh = st.commit()
	var node = MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material(color, finish)
	root.add_child(node)
	if solid:
		CozyCollision.mesh(collision, mesh)


func label(
	text: String, pos: Vector3, width: float, color: String = "f4eedb", yaw: float = 0, font_size: int = 64
) -> void:
	var n = Label3D.new()
	n.text = text
	n.font_size = font_size
	n.pixel_size = minf(width / maxf(1, text.length() * font_size * .57), .5 / font_size)
	n.modulate = Color(color)
	n.position = pos
	n.rotation.y = yaw
	n.outline_size = 0
	n.no_depth_test = false
	n.shaded = true
	n.double_sided = false
	n.visibility_range_end = 85
	root.add_child(n)


func finish() -> void:
	for key in groups:
		var group: Dictionary = groups[key]
		var origin := Vector3(group.cell.x * 40 + 20, 0, group.cell.y * 40 + 20)
		CozyMeshBatches.instances(root, shape(group.kind), group.material, group.transforms, origin, "Crafted district")
	groups.clear()


func cloth(at: Vector3, size: Vector2, color: String, yaw: float = 0) -> void:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for y in range(6):
		for x in range(6):
			for corner in [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 0), Vector2(1, 1), Vector2(0, 1)]:
				var uv = (Vector2(x, y) + corner) / 6.
				st.set_uv(uv)
				st.set_normal(Vector3.FORWARD)
				st.add_vertex(Vector3((uv.x - .5) * size.x, -uv.y * size.y, 0))
	var node = MeshInstance3D.new()
	node.mesh = st.commit()
	node.position = at
	node.rotation.y = yaw
	var mat = ShaderMaterial.new()
	mat.shader = load("res://maps/harbor_hills/cloth.gdshader")
	mat.set_shader_parameter("tint", Color(color))
	node.material_override = mat
	root.add_child(node)
