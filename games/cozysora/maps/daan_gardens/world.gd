extends CozyMap
const Geometry = preload("res://maps/daan_gardens/geometry.gd")
const Planting = preload("res://maps/daan_gardens/planting.gd")
const Neighborhood = preload("res://maps/daan_gardens/neighborhood.gd")
const Furnishings = preload("res://maps/daan_gardens/furnishings.gd")
const POND = Vector2(-31, -17)
const ISLAND = Vector2(-38, -19)
var paths: Array = []
var path_segments: Array = []
var path_grid: Dictionary = {}
var static_content: Node3D
var birds: Array = []
var flyers: Array = []
var elapsed := 0.0


func build() -> void:
	supports_surface_traversal = true
	flight_bounds = AABB(Vector3(-124, .35, -111), Vector3(251, 95, 223))
	ambience = {
		"wind_gain": .105,
		"wave_base": .002,
		"wave_swell": .001,
		"cicada_frequencies": Vector2(3600, 4050),
		"cicada_gain": .001,
		"birds": true
	}
	_make_paths()
	scenic_views = {
		"entrance": [58., -57., height_at(58, -57), 1.0, -.03],
		"pond": [-6., -44., height_at(-6, -44) + .3, 2.39, -.07],
		"deck": [-1., -23., 1.32, 1.65, -.08],
		"cafe_door": [98., -58., 1.2, -1.57, .01],
		"pavilion_seat": [-50.5, 57.5, height_at(-50.5, 57.5), .2, .13],
		"habitat": [-44., -25., height_at(-44, -25), -.78, -.04],
		"island": [-48., 10., height_at(-48, 10) + .6, -.33, -.04],
		"banyan": [5., 34., height_at(5, 34), PI, .08],
		"pavilion": [-35., 40., height_at(-35, 40), 2.33, -.03],
		"grove": [-73., 39., height_at(-73, 39), 2.5, -.04],
		"lawn": [36., 22., height_at(36, 22), .1, -.04],
		"cafes": [80., -46., 1.2, -1.57, -.02],
		"lane": [92., 12., 1.2, 3.14, -.02],
		"flight": [45., 80., 67., .3, -.55],
		"top": [0., 2., 190., 0., -1.57]
	}
	preload("res://maps/daan_gardens/atmosphere.tres").install(self)
	for child in get_children():
		if child is WorldEnvironment:
			child.environment.ssr_enabled = true
			child.environment.ssr_max_steps = 48
	load_progress.emit("Opening the park gates…", .08)
	await get_tree().process_frame
	generation_signature = CozySceneCache.signature("res://maps/daan_gardens")
	var cache = "user://daan_gardens_" + generation_signature + ".scn"
	static_content = Node3D.new()
	static_content.name = "Daan Gardens"
	add_child(static_content)
	if CozySceneCache.restore_children(static_content, cache):
		print("Daan Gardens cache restored: ", cache)
	else:
		var g = Geometry.new(static_content)
		g.ground_height = height_at
		_terrain(g)
		_paving(g)
		load_progress.emit("Opening the café shutters…", .25)
		await get_tree().process_frame
		Neighborhood.new().build(self, g)
		Furnishings.new().build(self, g)
		load_progress.emit("Spreading the banyan shade…", .5)
		await get_tree().process_frame
		await Planting.new().build(self, g)
		g.finish()
		CozySceneCache.save(static_content, cache)
		print("Daan Gardens generated: ", cache)
	_bird_life()
	for at in [Vector2(5, 42), Vector2(-70, 44), Vector2(47, -45)]:
		preload("res://maps/daan_gardens/air.tres").install(self, point(at.x, at.y, 3))
	preload("res://maps/daan_gardens/atmosphere.tres").install_post(self)
	load_progress.emit("A quiet afternoon is waiting.", 1.)


func pond_radius(x: float, z: float) -> float:
	var p = (Vector2(x, z) - POND) / Vector2(30, 23)
	return p.length() / (1. + .065 * sin(atan2(p.y, p.x) * 3.) + .035 * cos(atan2(p.y, p.x) * 5.))


func island_radius(x: float, z: float) -> float:
	var p = (Vector2(x, z) - ISLAND) / Vector2(8.3, 6.4)
	var a = atan2(p.y, p.x)
	return p.length() / (1. + .11 * sin(a * 3.) + .045 * cos(a * 7.))


func height_at(x: float, z: float) -> float:
	var d = pond_radius(x, z)
	if d < 1.09:
		var water = lerpf(.44, 1.2, smoothstep(.97, 1.09, d))
		return maxf(water, lerpf(1.18, .44, smoothstep(.76, 1.15, island_radius(x, z))))
	if x > 70:
		return 1.2
	return 1.2 + .26 * sin(x * .035) * sin(z * .04) * smoothstep(1.1, 1.4, d)


func walkable(x: float, z: float) -> bool:
	if x < -109 or x > 120 or absf(z) > 101:
		return false
	if deck_footprint(x, z):
		return true
	return pond_radius(x, z) > 1.025 or island_radius(x, z) < .98


func deck_footprint(x: float, z: float, margin: float = 0) -> bool:
	return (
		(x >= -4.5 - margin and x <= 2.5 + margin and absf(z + 23) <= 3 + margin)
		or (x >= 2.5 - margin and x <= 8 + margin and absf(z + 23) <= 1.3 + margin)
	)


func point(x: float, z: float, lift: float = 0) -> Vector3:
	return Vector3(x, height_at(x, z) + lift, z)


func _curve(points: Array, closed: bool, width: float) -> void:
	var curve: Array = []
	var count = points.size()
	for i in range(count if closed else count - 1):
		var p0: Vector2 = points[posmod(i - 1, count) if closed else maxi(0, i - 1)]
		var p1: Vector2 = points[i]
		var p2: Vector2 = points[(i + 1) % count]
		var p3: Vector2 = points[(i + 2) % count if closed else mini(count - 1, i + 2)]
		for j in range(16):
			var t = j / 16.
			curve.append(
				(
					.5
					* (
						2 * p1
						+ (-p0 + p2) * t
						+ (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t
						+ (-p0 + 3 * p1 - 3 * p2 + p3) * t * t * t
					)
				)
			)
	curve.append(curve[0] if closed else points[-1])
	paths.append({"points": curve, "width": width})
	for i in range(curve.size() - 1):
		var a: Vector2 = curve[i]
		var b: Vector2 = curve[i + 1]
		var id = path_segments.size()
		path_segments.append([a, b, width])
		for ix in range(floori((minf(a.x, b.x) - width) / 8), floori((maxf(a.x, b.x) + width) / 8) + 1):
			for iz in range(floori((minf(a.y, b.y) - width) / 8), floori((maxf(a.y, b.y) + width) / 8) + 1):
				var key = Vector2i(ix, iz)
				if not path_grid.has(key):
					path_grid[key] = []
				path_grid[key].append(id)


func _make_paths() -> void:
	_curve(
		[
			Vector2(62, -62),
			Vector2(26, -76),
			Vector2(-36, -71),
			Vector2(-79, -49),
			Vector2(-83, 6),
			Vector2(-76, 48),
			Vector2(-52, 77),
			Vector2(3, 78),
			Vector2(43, 61),
			Vector2(63, 26),
			Vector2(63, -24)
		],
		true,
		4.8
	)
	var ring = []
	for i in range(12):
		ring.append(POND + Vector2(cos(i * TAU / 12) * 40, sin(i * TAU / 12) * 32))
	_curve(ring, true, 3.6)
	_curve(
		[
			Vector2(88, -60),
			Vector2(64, -60),
			Vector2(37, -45),
			Vector2(17, -24),
			Vector2(15, 5),
			Vector2(5, 38),
			Vector2(-12, 54),
			Vector2(-52, 56)
		],
		false,
		4.4
	)
	_curve(
		[Vector2(-83, 20), Vector2(-48, 18), Vector2(-4, 17), Vector2(35, 19), Vector2(63, 28), Vector2(88, 30)],
		false,
		3.8
	)
	_curve([Vector2(-75, -45), Vector2(-62, -51), Vector2(-36, -49)], false, 2.2)
	_curve([Vector2(-72, 42), Vector2(-59, 39), Vector2(-45, 47), Vector2(-52, 56)], false, 2.1)
	_curve([Vector2(7, 44), Vector2(27, 49), Vector2(45, 62)], false, 2.0)


func path_distance(x: float, z: float) -> float:
	var p = Vector2(x, z)
	var best = 99.
	for id in path_grid.get(Vector2i(floori(x / 8), floori(z / 8)), []):
		var s = path_segments[id]
		var a: Vector2 = s[0]
		var v: Vector2 = s[1] - a
		best = minf(best, p.distance_to(a + v * clampf((p - a).dot(v) / v.length_squared(), 0, 1)) - s[2] * .5)
	return best


func planted_clear(x: float, z: float, margin: float = 0) -> bool:
	if deck_footprint(x, z, margin + .3):
		return false
	if x > 72 or absf(z) > 94 or x < -103:
		return false
	if path_distance(x, z) < margin or pond_radius(x, z) < 1.12:
		return false
	for plaza in [Vector3(5, 42, 11.5), Vector3(-52, 56, 9.5), Vector3(62, -60, 9)]:
		if Vector2(x - plaza.x, z - plaza.y).length() < plaza.z + margin:
			return false
	return true


func _terrain(g) -> void:
	# Continuous city ground carries the entire visible skyline beyond the play boundary.
	g.box(Vector3(0, .1, 0), Vector3(2400, .1, 2400), "8c9b8b")
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for iz in range(260):
		for ix in range(300):
			var x = ix - 145.
			var z = iz - 130.
			for at in [
				point(x, z), point(x + 1, z), point(x + 1, z + 1), point(x, z), point(x + 1, z + 1), point(x, z + 1)
			]:
				st.add_vertex(at)
	st.generate_normals()
	var terrain = g.mesh(st.commit(), "7c9252", true)
	var mat = ShaderMaterial.new()
	mat.shader = preload("res://maps/daan_gardens/ground.gdshader")
	terrain.material_override = mat
	var water = SurfaceTool.new()
	water.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(128):
		for angle in [i * TAU / 128, (i + 1) * TAU / 128]:
			if angle == i * TAU / 128:
				water.add_vertex(Vector3(POND.x, .51, POND.y))
			var r = 1. + .065 * sin(angle * 3) + .035 * cos(angle * 5)
			water.add_vertex(Vector3(POND.x + cos(angle) * 30 * r, .51, POND.y + sin(angle) * 23 * r))
	water.generate_normals()
	var pond = CozyPrimitives.instance(static_content, water.commit(), Vector3.ZERO, null)
	mat = ShaderMaterial.new()
	mat.shader = preload("res://maps/daan_gardens/pond.gdshader")
	pond.material_override = mat


func _paving(g) -> void:
	for path in paths:
		var points = []
		for p in path.points:
			points.append(point(p.x, p.y, .04))
		g.ribbon(points, path.width + .3, "a6a58e", 0)
		for i in range(points.size()):
			points[i].y += .008
		g.ribbon(points, path.width, "bfb9a2", 1)
	for at in [Vector2(5, 42), Vector2(-52, 56), Vector2(62, -60)]:
		g.disc(point(at.x, at.y, .065), 11 if at.x == 5 else 9, "b6ae96")
	g.box(Vector3(85.5, 1.23, 0), Vector3(11, .06, 290), "646b65", false)
	g.box(Vector3(76.8, 1.23, 0), Vector3(6.4, .06, 290), "bcb7a3", false, 0, 1)
	g.box(Vector3(95.1, 1.23, 0), Vector3(8.2, .06, 290), "b6b5a4", false, 0, 1)
	for z in [-121., 121.]:
		g.box(Vector3(14, 1.23, z), Vector3(290, .06, 10), "646b65")
		for side in [-1, 1]:
			g.box(Vector3(14, 1.23, z + side * 6.5), Vector3(290, .06, 3), "b6b5a4", false, 0, 1)
	for z in range(-137, 140, 8):
		g.box(Vector3(85.5, 1.27, z), Vector3(.12, .02, 3.5), "d1be75")
	for z in [-60, 30]:
		for x in range(81, 91, 2):
			g.box(Vector3(x, 1.28, z), Vector3(1.1, .025, 3.5), "e8dfc1")


func _bird_life() -> void:
	var palette = CozySolidMaterials.new()
	for i in range(4):
		var bird = Node3D.new()
		add_child(bird)
		CozyPrimitives.sphere(bird, Vector3.ZERO, Vector3(.12, .13, .32), palette.color("ece8d3"))
		CozyPrimitives.sphere(bird, Vector3(0, .09, .34), Vector3(.075, .07, .08), palette.color("ece8d3"))
		CozyPrimitives.beam(bird, Vector3(0, .06, .18), Vector3(0, .09, .34), .04, palette.color("ece8d3"))
		CozyPrimitives.beam(bird, Vector3(0, .09, .38), Vector3(0, .085, .53), .018, palette.color("77816b"))
		var wings = []
		for side in [-1, 1]:
			var wing = Node3D.new()
			bird.add_child(wing)
			CozyPrimitives.sphere(wing, Vector3(side * .36, 0, -.04), Vector3(.46, .035, .19), palette.color("eee9d4"))
			CozyPrimitives.sphere(wing, Vector3(side * .65, 0, -.14), Vector3(.24, .022, .13), palette.color("d3d8c5"))
			wings.append(wing)
		flyers.append({"node": bird, "wings": wings, "phase": i * 1.73})
	for i in range(16):
		var n = Node3D.new()
		add_child(n)
		CozyPrimitives.sphere(n, Vector3(0, .14, 0), Vector3(.13, .2, .28), palette.color("efe9d6"))
		CozyPrimitives.beam(n, Vector3(0, .22, -.08), Vector3(0, .55, .07), .04, palette.color("efe9d6"))
		CozyPrimitives.sphere(n, Vector3(0, .57, .08), Vector3(.065, .065, .07), palette.color("eee8d7"))
		CozyPrimitives.beam(n, Vector3(0, .57, .1), Vector3(0, .55, .28), .02, palette.color("4c5953"))
		for side in [-1, 1]:
			CozyPrimitives.beam(
				n, Vector3(side * .045, 0, 0), Vector3(side * .045, .18, 0), .012, palette.color("59604e")
			)
		var angle = i * 2.399
		var radius = .35 + .6 * fmod(i * .618, 1.)
		var p = ISLAND + Vector2(cos(angle), sin(angle)) * Vector2(7.5, 5.8) * radius
		n.position = point(p.x, p.y)
		birds.append({"node": n, "phase": angle})


func _process(delta: float) -> void:
	elapsed += delta
	for bird in flyers:
		var a = elapsed * .085 + bird.phase
		bird.node.position = Vector3(POND.x + cos(a) * 27, 6 + sin(a * 1.8 + bird.phase) * 1.4, POND.y + sin(a) * 22)
		bird.node.rotation.y = atan2(-sin(a) * 27, cos(a) * 22)
		bird.node.rotation.z = sin(a) * .10
		for i in range(2):
			bird.wings[i].rotation.z = (1 if i == 0 else -1) * sin(elapsed * 3.2 + bird.phase) * .3
	for bird in birds:
		bird.node.rotation.y = bird.phase + sin(elapsed * .22 + bird.phase) * .35
