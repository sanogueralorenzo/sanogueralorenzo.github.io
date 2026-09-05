extends RefCounted
var map
var g
var rng = RandomNumberGenerator.new()


func build(world, geometry) -> void:
	map = world
	g = geometry
	rng.seed = 46199
	_pavilion(map.point(-52, 56))
	# Low carved entrance marker leaves the curving central path completely open.
	var p = map.point(62, -65)
	g.box(p + Vector3(0, .72, 0), Vector3(6.1, 1.44, .6), "898e78", true)
	g.box(p + Vector3(0, 1.46, 0), Vector3(6.3, .12, .75), "c2bda0")
	g.label("DAAN GARDENS", p + Vector3(0, .96, .315), 4.9, "eee4c5")
	g.label("POND  ·  BANYAN COURT  ·  TEA PAVILION", p + Vector3(0, .47, .32), 5.2, "dedbc0")
	for x in [-3.7, 3.7]:
		g.add("cylinder", p + Vector3(x, .3, 0), Vector3(.85, .6, .85), "9c8d76", Vector3.ZERO, true)
	for info in [
		Vector3(-1, -47, .6),
		Vector3(-68, 2, 1.5),
		Vector3(4, 31, 2.8),
		Vector3(-44, 67, -.6),
		Vector3(47, 56, -.9),
		Vector3(57, -34, -1.5)
	]:
		_bench(map.point(info.x, info.y), info.z)
	# A circular seat under the landmark banyan, with gaps for its exposed roots.
	for i in range(6):
		var a = i * TAU / 6
		_bench(map.point(5 + sin(a) * 4.5, 42 + cos(a) * 4.5), a)
	for path in map.paths.slice(0, 2):
		for i in range(8, path.points.size() - 3, 26):
			var a: Vector2 = path.points[i]
			var b: Vector2 = path.points[i + 1]
			var side = (b - a).normalized().orthogonal() * (path.width * .5 + .8)
			_lamp(map.point(a.x + side.x, a.y + side.y))
	for p2 in [Vector2(65, -58), Vector2(-2, -46), Vector2(7, 34), Vector2(-44, 57)]:
		_bin(map.point(p2.x, p2.y))
	_deck()
	# Staggered, partially submerged bank stones break the mathematical water edge.
	for i in range(175):
		var a = i * TAU / 175
		var wave = 1. + .065 * sin(a * 3) + .035 * cos(a * 5)
		var at = map.point(map.POND.x + cos(a) * 30 * wave * 1.015, map.POND.y + sin(a) * 23 * wave * 1.015)
		g.add(
			"sphere",
			at + Vector3(0, -.03, 0),
			Vector3(rng.randf_range(.8, 1.4), rng.randf_range(.35, .6), rng.randf_range(.6, 1.1)),
			["969a85", "898f7e", "b1ae93"][i % 3],
			Vector3(0, a, 0)
		)
	_sign(map.point(-1, -41), "THE LIVING POND", "A quiet home for egrets and water lilies", .35)
	_sign(map.point(-62, 49), "THE BAMBOO WALK", "Shade, birdsong, and the long way home", -1.0)
	# Simple park boundary rails give the forest edge a human scale.
	for z in range(-98, 100, 4):
		if absf(z + 60) < 6 or absf(z - 30) < 6:
			continue
		var at = map.point(74, z)
		g.add("cylinder", at + Vector3(0, .5, 0), Vector3(.08, 1, .08), "6b7865")
		g.beam(at + Vector3(0, .88, 0), at + Vector3(0, .88, 4), .035, "6b7865")


func _bench(p: Vector3, yaw: float) -> void:
	var turn = Basis(Vector3.UP, yaw)
	for x in [-.95, .95]:
		for z in [-.25, .25]:
			g.box(p + turn * Vector3(x, .24, z), Vector3(.09, .48, .09), "596b60", false, yaw)
	for z in [-.25, -.08, .09, .26]:
		g.box(p + turn * Vector3(0, .49, z), Vector3(2.35, .075, .13), "a18b61", false, yaw, 3)
	for y in [.73, .9]:
		g.box(p + turn * Vector3(0, y, -.31), Vector3(2.35, .13, .07), "a18b61", false, yaw, 3)
	for x in [-1, 1]:
		g.box(p + turn * Vector3(x, .68, -.31), Vector3(.06, .64, .07), "596b60", false, yaw)
	CozyCollision.box(g.body, p + Vector3(0, .28, 0), Vector3(2.35, .56, .65), Vector3(0, yaw, 0))


func _lamp(p: Vector3) -> void:
	g.add("cylinder", p + Vector3(0, 1.95, 0), Vector3(.11, 3.9, .11), "697c70", Vector3.ZERO, true)
	g.add("cylinder", p + Vector3(0, .14, 0), Vector3(.28, .28, .28), "697c70")
	g.add("cylinder", p + Vector3(0, 3.75, 0), Vector3(.48, .14, .48), "d4cfac")
	g.add("cylinder", p + Vector3(0, 3.89, 0), Vector3(.65, .08, .65), "697c70")


func _bin(p: Vector3) -> void:
	g.box(p + Vector3(0, .44, 0), Vector3(.52, .88, .52), "718271", true)
	g.box(p + Vector3(0, .82, .27), Vector3(.3, .18, .025), "384f48")
	g.box(p + Vector3(0, .91, 0), Vector3(.6, .07, .6), "a8a689")


func _sign(p: Vector3, title: String, caption: String, yaw: float) -> void:
	var turn = Basis(Vector3.UP, yaw)
	for x in [-.64, .64]:
		g.box(p + turn * Vector3(x, .65, 0), Vector3(.08, 1.3, .08), "6b7966", false, yaw)
	g.box(p + Vector3(0, 1.25, 0), Vector3(1.9, .8, .12), "6a7966", true, yaw)
	g.label(title, p + turn * Vector3(0, 1.43, .07), 1.65, "e5ddba", yaw)
	g.label(caption, p + turn * Vector3(0, 1.13, .07), 1.65, "c6cbb0", yaw)


func _pavilion(p: Vector3) -> void:
	# Ground-level access on all four sides, with six slender columns and a tiled hip roof.
	g.box(p + Vector3(0, .02, 0), Vector3(8, .04, 7), "b5ae94", false, 0, 1)
	for x in [-3.3, 0, 3.3]:
		for z in [-2.65, 2.65]:
			g.box(p + Vector3(x, 1.65, z), Vector3(.24, 3.3, .24), "8b7556", true, 0, 3)
			g.box(p + Vector3(x, .14, z), Vector3(.44, .28, .44), "a3a28a")
	for z in [-2.65, 2.65]:
		g.box(p + Vector3(0, 3.1, z), Vector3(7, .23, .25), "8b7556", false, 0, 3)
	for x in [-3.3, 3.3]:
		g.box(p + Vector3(x, 3.1, 0), Vector3(.25, .23, 5.6), "8b7556", false, 0, 3)
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var points = [
		Vector3(-4.5, 3.35, -3.8),
		Vector3(4.5, 3.35, -3.8),
		Vector3(4.5, 3.35, 3.8),
		Vector3(-4.5, 3.35, 3.8),
		Vector3(-1.6, 4.9, 0),
		Vector3(1.6, 4.9, 0)
	]
	for i in [0, 1, 5, 0, 5, 4, 1, 2, 5, 2, 3, 4, 2, 4, 5, 3, 0, 4]:
		st.add_vertex(p + points[i])
	st.generate_normals()
	g.mesh(st.commit(), "657b6a", true)
	var underside = SurfaceTool.new()
	underside.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in [5, 1, 0, 4, 5, 0, 5, 2, 1, 4, 3, 2, 5, 4, 2, 4, 0, 3]:
		underside.add_vertex(p + points[i] - Vector3(0, .08, 0))
	underside.generate_normals()
	g.mesh(underside.commit(), "a8956e", true, 3)
	for x in [-2.7, 0., 2.7]:
		g.box(p + Vector3(x, 3.26, 0), Vector3(.12, .16, 7.2), "8c7858", false, 0, 3)
	for i in range(37):
		var x = -4.5 + i * .25
		var ridge_x = clampf(x, -1.6, 1.6)
		for side in [-1, 1]:
			g.beam(p + Vector3(x, 3.39, side * 3.8), p + Vector3(ridge_x, 4.94, 0), .045, "7b8d75")
	for z in [-3.8, 3.8]:
		g.box(p + Vector3(0, 3.34, z), Vector3(9.2, .16, .16), "556d60")
	g.beam(p + Vector3(-1.8, 4.98, 0), p + Vector3(1.8, 4.98, 0), .11, "89957b")
	for x in [-3., 3.]:
		_bench(p + Vector3(x, 0, 0), PI * .5 if x < 0 else -PI * .5)
	for z in [-1.3, 1.3]:
		g.add("cylinder", p + Vector3(0, .37, z), Vector3(.28, .74, .28), "879582")
		g.add("cylinder", p + Vector3(0, .76, z), Vector3(1.1, .08, 1.1), "b3a47d", Vector3.ZERO, true)
	g.box(p + Vector3(0, 2.9, 2.8), Vector3(2.7, .5, .08), "697d6b")
	g.label("AFTERNOON PAVILION", p + Vector3(0, 2.91, 2.85), 2.3, "e2d8b4")


func _deck() -> void:
	var p = Vector3(-1, 1.32, -23)
	g.box(p - Vector3(0, .12, 0), Vector3(7, .24, 6), "7a735b", true)
	for i in range(28):
		g.box(p + Vector3(-3.375 + i * .25, .012, 0), Vector3(.225, .035, 6), "a79773", false, 0, 3)
	# The eastern entrance meets a gradual boardwalk back to the pond loop.
	g.ribbon([Vector3(2.5, 1.34, -23), map.point(8, -23, .05)], 2.6, "a79773", 3, true, false)
	for x in [-3.45, 3.45]:
		for z in [-3., 3.]:
			g.box(p + Vector3(x, .48, z), Vector3(.12, .96, .12), "73816b", true)
	for z in [-3., 3.]:
		g.beam(p + Vector3(-3.45, .92, z), p + Vector3(3.45, .92, z), .055, "73816b")
		g.beam(p + Vector3(-3.45, .46, z), p + Vector3(3.45, .46, z), .028, "73816b")
	g.beam(p + Vector3(-3.45, .92, -3), p + Vector3(-3.45, .92, 3), .055, "73816b")
	CozyCollision.box(g.body, p + Vector3(-3.45, .5, 0), Vector3(.14, 1, 6))
	for z in [-3., 3.]:
		CozyCollision.box(g.body, p + Vector3(0, .5, z), Vector3(7, 1, .12))
