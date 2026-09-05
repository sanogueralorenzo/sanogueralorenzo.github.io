extends RefCounted
## Spreading evergreen crowns, banyan roots and layered pond habitat, all seeded locally.
var map
var g
var rng = RandomNumberGenerator.new()
var leaf_groups: Array = [[], [], [], []]
var tree_positions: Array = []
var leaf_mesh: Mesh
var leaf_materials: Array = []


func build(world, geometry) -> void:
	map = world
	g = geometry
	rng.seed = 92176
	leaf_mesh = _spray_mesh()
	var texture = _leaf_texture()
	for color in ["587846", "6c864d", "466c4b", "82945b"]:
		var m = ShaderMaterial.new()
		m.shader = preload("res://shaders/foliage.gdshader")
		m.set_shader_parameter("leaf_texture", texture)
		m.set_shader_parameter("tint", Color(color))
		m.set_shader_parameter("wind_amplitude", .09)
		m.set_shader_parameter("band_lift", .12)
		leaf_materials.append(m)
	_tree(map.point(5, 42), 12.4, true)
	_tree(map.point(-39, -19), 9.4, true)
	_tree(map.point(-33, -20), 6.9, false)
	for p in [
		Vector2(-70, 5),
		Vector2(-9, -55),
		Vector2(5, -8),
		Vector2(-55, 26),
		Vector2(53, -70),
		Vector2(-65, 71),
		Vector2(50, 50)
	]:
		_tree(map.point(p.x, p.y), rng.randf_range(8.8, 12.5), true)
	# Trunks clear paths, while their broad crowns overlap the walking routes.
	for i in range(1100):
		var p = Vector2(rng.randf_range(-117, 69), rng.randf_range(-108, 108))
		var lawn = ((p - Vector2(30, 4)) / Vector2(23, 28)).length()
		if lawn < 1 or not map.planted_clear(p.x, p.y, 1.4):
			continue
		var clear = true
		for previous in tree_positions:
			if p.distance_to(previous) < 7.0:
				clear = false
				break
		if clear:
			_tree(map.point(p.x, p.y), rng.randf_range(5.8, 13.2), i % 5 == 0)
	# Perimeter crowns continue beyond the paths; no bare rectangular world edge.
	for z in range(-118, 119, 12):
		for x in [-125., -112.]:
			_tree(map.point(x + rng.randf_range(-2, 2), z), rng.randf_range(10, 16), false)
	for x in range(-105, 77, 12):
		for z in [-112., 111.]:
			_tree(map.point(x, z + rng.randf_range(-2, 2)), rng.randf_range(11, 16), false)
	for z in range(-87, 100, 18):
		if absf(z + 60) < 7 or absf(z - 30) < 7:
			continue
		_tree(map.point(72, z), 8.5, false)
		g.box(map.point(72, z, -.03), Vector3(2.4, .12, 2.4), "878a69")
	_understory()
	_bamboo()
	_pond_plants()
	for i in range(4):
		CozyMeshBatches.spatial(g.root, leaf_mesh, leaf_materials[i], leaf_groups[i], "Subtropical leaf sprays", 32)
	map.load_progress.emit("Combing the grass and pond reeds…", .78)
	await map.get_tree().process_frame
	_grass()
	print("Daan Gardens trees: ", tree_positions.size())


func _leaf_texture() -> Texture2D:
	var img = Image.create(256, 256, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var brush = RandomNumberGenerator.new()
	brush.seed = 6238
	for layer in range(2):
		for i in range(74):
			var angle = brush.randf() * TAU
			var r = sqrt(brush.randf()) * 86
			var at = Vector2(128, 128) + Vector2(cos(angle), sin(angle) * .84) * r
			var length = brush.randf_range(10, 22)
			CozyLeafPainter.paint(
				img,
				at,
				length,
				length * brush.randf_range(.35, .55),
				angle + brush.randf_range(-.8, .8),
				brush.randf_range(.5, .78) if layer == 0 else brush.randf_range(.75, 1),
				CozyLeafPainter.Profile.POINTED
			)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _spray_mesh() -> Mesh:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(24):
		var at = Vector3(rng.randf_range(-.48, .48), rng.randf_range(-.27, .27), rng.randf_range(-.48, .48))
		var normal = Vector3(rng.randf_range(-1, 1), rng.randf_range(.2, 1), rng.randf_range(-1, 1)).normalized()
		var basis = Basis(Quaternion(Vector3.BACK, normal))
		var size = rng.randf_range(.25, .42)
		var shade = rng.randf_range(.85, 1.15)
		st.set_color(Color(shade, shade, shade, .7))
		var corners = [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]
		for j in [0, 1, 2, 0, 2, 3]:
			st.set_uv(corners[j] * .5 + Vector2(.5, .5))
			st.set_normal((at * Vector3(1, 2, 1) + Vector3.UP * .6).normalized())
			st.add_vertex(at + basis * Vector3(corners[j].x * size, corners[j].y * size, 0))
	return st.commit()


func _leaves(at: Vector3, size: Vector3, index: int) -> void:
	leaf_groups[posmod(index, 4)].append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU) * Basis.from_scale(size), at))


func _limb(a: Vector3, b: Vector3, radius: float) -> void:
	g.add(
		"branch",
		(a + b) * .5,
		Vector3(radius * 2, a.distance_to(b), radius * 2),
		"8d8970",
		Quaternion(Vector3.UP, (b - a).normalized()).get_euler(),
		false,
		4
	)

	if radius >= .085:
		var collision = CollisionShape3D.new()
		var shape = CapsuleShape3D.new()
		shape.radius = radius * .72
		shape.height = maxf(shape.radius * 2, a.distance_to(b))
		collision.shape = shape
		collision.position = (a + b) * .5
		collision.rotation = Quaternion(Vector3.UP, (b - a).normalized()).get_euler()
		g.body.add_child(collision)


func _tree(p: Vector3, h: float, banyan: bool) -> void:
	tree_positions.append(Vector2(p.x, p.z))
	var trunk = h * (.040 if banyan else .022)
	var lean = Vector3(rng.randf_range(-.7, .7), 0, rng.randf_range(-.7, .7))
	var fork = p + lean + Vector3(0, h * rng.randf_range(.29, .45), 0)
	_limb(p, fork, trunk)
	_limb(fork, p + lean * 1.7 + Vector3(0, h * .79, 0), trunk * .67)
	if banyan:
		for i in range(6):
			var angle = i * TAU / 6 + rng.randf() * .2
			_limb(
				p + Vector3(cos(angle) * 1.6, .08, sin(angle) * 1.6),
				p + Vector3(cos(angle) * .13, 1.3, sin(angle) * .13),
				.14
			)
	var count = rng.randi_range(5, 8)
	for branch in range(count):
		var angle = branch * 2.399 + rng.randf() * .6
		var spread = h * rng.randf_range(.33, .49) if banyan else h * rng.randf_range(.23, .40)
		var tip = p + lean + Vector3(cos(angle) * spread, h * rng.randf_range(.64, .96), sin(angle) * spread)
		var elbow = fork.lerp(tip, .5) + Vector3(0, rng.randf_range(.2, 1), 0)
		_limb(fork + Vector3(0, branch * .12, 0), elbow, trunk * .55)
		_limb(elbow, tip, trunk * .31)
		for j in range(8):
			var a = rng.randf() * TAU
			var r = sqrt(rng.randf()) * h * .19
			var at = tip + Vector3(cos(a) * r, rng.randf_range(-.08, .09) * h, sin(a) * r)
			var size = h * rng.randf_range(.23, .33)
			_leaves(at, Vector3(size * 1.25, size * .83, size), branch + j)
		if banyan and branch % 2 == 0:
			for j in range(4):
				var hanging = tip + Vector3(rng.randf_range(-.7, .7), -.3, rng.randf_range(-.7, .7))
				g.beam(hanging, hanging - Vector3(0, rng.randf_range(1.6, 3), 0), .022, "93886d")


func _understory() -> void:
	# Tall leafy pockets behind resting spots create intimate sheltered rooms.
	for center in [
		Vector2(-66, 58),
		Vector2(-54, 66),
		Vector2(0, 51),
		Vector2(-7, 39),
		Vector2(-79, 30),
		Vector2(-91, -39),
		Vector2(47, 48)
	]:
		for i in range(24):
			var x = center.x + rng.randf_range(-5, 5)
			var z = center.y + rng.randf_range(-4, 4)
			if not map.planted_clear(x, z, .65):
				continue
			var size = rng.randf_range(1.6, 3.2)
			_leaves(map.point(x, z, size * .38), Vector3(size, size * .95, size), i)
	for i in range(270):
		var x = rng.randf_range(-99, 60)
		var z = rng.randf_range(-88, 92)
		if map.planted_clear(x, z, .8) and (x < -58 or z > 34):
			_fern(map.point(x, z), rng.randf_range(.65, 1.25))
	for i in range(2600):
		var x = rng.randf_range(-110, 70)
		var z = rng.randf_range(-103, 102)
		if not map.planted_clear(x, z, .4):
			continue
		if ((Vector2(x, z) - Vector2(30, 4)) / Vector2(26, 29)).length() < 1:
			continue
		if sin(x * .17) + cos(z * .21) < -.3:
			continue
		var p = map.point(x, z)
		var s = rng.randf_range(.6, 1.7)
		_leaves(p + Vector3(0, s * .27, 0), Vector3(s, s * .7, s), i)
		if i % 7 == 0:
			for j in range(4):
				var q = p + Vector3(rng.randf_range(-.4, .4), s * .45, rng.randf_range(-.4, .4))
				g.add("sphere", q, Vector3(.12, .10, .12), ["dbc798", "c6aa91", "d9d6b7"][j % 3])


func _bamboo() -> void:
	for center in [Vector2(-91, 50), Vector2(-88, 67), Vector2(-66, 39)]:
		for i in range(37):
			var p = map.point(center.x + rng.randf_range(-4, 4), center.y + rng.randf_range(-4, 4))
			if map.path_distance(p.x, p.z) < .7:
				continue
			var h = rng.randf_range(5, 8)
			g.beam(p, p + Vector3(.35, h, .2), .065, "85966c")
			for j in range(1, 11):
				var at = p + Vector3(.35, h, .2) * j / 11.
				g.add("cylinder", at, Vector3(.15, .045, .15), "b8b78b")
				if j > 5:
					_leaves(at + Vector3(sin(j) * .8, 0, cos(j) * .8), Vector3(1.8, .45, 1.4), j)


func _pond_plants() -> void:
	for i in range(50):
		var p = map.ISLAND + Vector2(rng.randf_range(-8, 8), rng.randf_range(-6, 6))
		if map.island_radius(p.x, p.y) > 1.04:
			continue
		var size = rng.randf_range(.5, 1.4)
		_leaves(map.point(p.x, p.y, size * .3), Vector3(size, size * .8, size), i)
		if i % 4 == 0:
			g.add("sphere", map.point(p.x, p.y, -.06), Vector3(.6, .4, .7), "a4a88b")
	for i in range(550):
		var angle = rng.randf() * TAU
		var r = rng.randf_range(.96, 1.05)
		var wave = 1. + .065 * sin(angle * 3) + .035 * cos(angle * 5)
		var p = map.point(map.POND.x + cos(angle) * 30 * wave * r, map.POND.y + sin(angle) * 23 * wave * r)
		if p.x > -5 and p.x < 9 and p.z > -27 and p.z < -19:
			continue
		# Keep a wide viewing window on the south-east bank.
		if angle > 0 and angle < 1.1:
			continue
		for j in range(3):
			var q = p + Vector3(rng.randf_range(-.3, .3), 0, rng.randf_range(-.3, .3))
			var h = rng.randf_range(.45, 1.35)
			g.beam(q, q + Vector3(.07, h, .06), .018, "74834f")
			if j == 0:
				g.add("cylinder", q + Vector3(.07, h, .06), Vector3(.055, .18, .055), "887857")
		if i % 3 == 0:
			_leaves(p + Vector3(0, .25, 0), Vector3(.8, .6, .8), i)
	for i in range(110):
		var p = map.POND + Vector2(rng.randf_range(-23, 18), rng.randf_range(-15, 13))
		if map.pond_radius(p.x, p.y) > .87 or map.island_radius(p.x, p.y) < 1.25:
			continue
		if sin(p.x * .35) + cos(p.y * .3) < .2:
			continue
		g.add(
			"cylinder",
			Vector3(p.x, .535, p.y),
			Vector3(rng.randf_range(.25, .65), .025, rng.randf_range(.25, .6)),
			"82945a"
		)
		if i % 9 == 0:
			g.add("sphere", Vector3(p.x, .60, p.y), Vector3(.14, .1, .14), "e6ccb8")


func _grass() -> void:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for blade in range(4):
		var angle = blade * 2.399
		var side = Vector3(cos(angle), 0, sin(angle)) * .05
		var base = Vector3(sin(angle), 0, cos(angle)) * .1
		var tip = base + Vector3(cos(angle) * .22, 1, sin(angle) * .22)
		for row in range(3):
			var t = row / 3.
			var next = (row + 1) / 3.
			var a = base.lerp(tip, t)
			var b = base.lerp(tip, next)
			for item in [
				[a - side * (1 - t), t],
				[b - side * (1 - next), next],
				[b + side * (1 - next), next],
				[a - side * (1 - t), t],
				[b + side * (1 - next), next],
				[a + side * (1 - t), t]
			]:
				st.set_normal(Vector3.UP)
				st.set_color(Color(1, 1, 1))
				st.set_uv(Vector2(0, item[1]))
				st.add_vertex(item[0])
	var instances = []
	for i in range(270000):
		var x = rng.randf_range(-130, 73)
		var z = rng.randf_range(-119, 119)
		if map.deck_footprint(x, z, .35) or map.path_distance(x, z) < .14 or map.pond_radius(x, z) < 1.095:
			continue
		var clear = true
		for plaza in [Vector3(5, 42, 11.2), Vector3(-52, 56, 9.2), Vector3(62, -60, 9.2)]:
			if Vector2(x - plaza.x, z - plaza.y).length() < plaza.z:
				clear = false
				break
		if not clear:
			continue
		var lawn = ((Vector2(x, z) - Vector2(30, 4)) / Vector2(26, 29)).length() < 1
		var s = rng.randf_range(.08, .19) if lawn else rng.randf_range(.18, .43)
		instances.append(
			Transform3D(Basis(Vector3.UP, rng.randf() * TAU) * Basis.from_scale(Vector3(.8, s, .8)), map.point(x, z))
		)
	var mat = ShaderMaterial.new()
	mat.shader = preload("res://shaders/grass.gdshader")
	mat.set_shader_parameter("grass_base", Vector3(.28, .39, .20))
	mat.set_shader_parameter("grass_mid", Vector3(.44, .51, .27))
	mat.set_shader_parameter("grass_tip", Vector3(.62, .62, .36))
	var batches = CozyMeshBatches.spatial(
		g.root, st.commit(), mat, instances, "Park grass", 24, 105, 12, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	)
	print("Daan Gardens grass: ", instances.size(), " in ", batches, " batches")


func _fern(p: Vector3, size: float) -> void:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for frond in range(8):
		var angle = frond * 2.399
		var forward = Vector3(cos(angle), 0, sin(angle))
		var side = forward.cross(Vector3.UP)
		for leaf in range(1, 8):
			var t = leaf / 8.
			var center = p + forward * t * size + Vector3.UP * sin(t * PI * .78) * size * .65
			var width = sin(t * PI) * size * .26
			for sign in [-1, 1]:
				var tip = center + side * width * sign + forward * .12 * size
				for point in [center - forward * .05, tip, center + forward * .06]:
					st.add_vertex(point)
	st.generate_normals()
	g.mesh(st.commit(), "7d9858")
