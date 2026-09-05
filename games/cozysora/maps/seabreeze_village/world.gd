extends CozyMap
const ATMOSPHERE = preload("res://maps/seabreeze_village/atmosphere.tres")
## Coordinate system, deterministic height field and shared primitive construction.
## World dimensions and authored placements for Cozy Sora.

var roads: Array = []
var rail_points: Array[Vector2] = []
var _segments: Array = []
var _road_grid: Dictionary = {}
var palette := CozySolidMaterials.new()
const SCENIC_VIEWS = {
	"coast": [-8.0, -9.3, 1.05, -1.2, -0.06],
	"paddy": [55.2, -2.6, 0.25, -2.31, 0.29],
	"farm": [53.6, 60.2, 3.0, 2.98, 0.1],
	"rail": [19.2, 80.0, 2.7, -3.02, 0.41],
	"village": [-4.6, 74.7, 2.55, 1.32, 0.0],
	"alley": [-26.4, 77.9, 2.65, 3.55, 0.2],
	"vending": [-61.65, 26.2, 1.22, 1.571, 0.16],
	"viaduct": [-64.3, 58.6, 2.9, -1.95, 0.52],
	"shrine": [-0.7, 8.0, 5.7, -3.16, 0.48],
	"top": [0.0, 30.0, 140.0, 0.0, -1.5],
}
const ZONES := {
	"paddy": Rect2(63, -8, 39, 52),
	"paddy_in": Rect2(42, 0, 10, 30),
	"farm": Rect2(28, 42, 36, 34),
	"yard": Rect2(36, 50, 18, 14),
	"village": Rect2(-36, 56, 50, 32),
	"street": Rect2(-34, 71, 46, 8),
	"vending": Rect2(-74, 8, 18, 34),
	"pave": Rect2(-70, 12, 10, 26),
	"gully": Rect2(10, 88, 36, 18),
	"bed": Rect2(14, 91, 30, 10)
}


func build() -> void:
	generation_signature = CozySceneCache.signature("res://maps/seabreeze_village")
	scenic_views = SCENIC_VIEWS
	ambience = {
		"wind_gain": .12,
		"wave_base": .022,
		"wave_swell": .018,
		"cicada_frequencies": Vector2(3820, 4075),
		"cicada_gain": .0018,
		"birds": true
	}
	load_progress.emit("Tracing the coastal lanes…", .08)
	await get_tree().process_frame
	_build_roads()
	ATMOSPHERE.install(self)
	load_progress.emit("Shaping fields and shoreline…", .14)
	await get_tree().process_frame
	await _build_terrain()
	_build_coast_props()
	load_progress.emit("Opening the village…", .38)
	await get_tree().process_frame
	var settlement = load("res://maps/seabreeze_village/settlements.gd").new()
	add_child(settlement)
	await settlement.build(self)
	load_progress.emit("Growing the summer gardens…", .60)
	await get_tree().process_frame
	var vegetation = load("res://maps/seabreeze_village/vegetation.gd").new()
	add_child(vegetation)
	await vegetation.build(self)
	var life = load("res://maps/seabreeze_village/summer_life.gd").new()
	add_child(life)
	life.build(self)
	ATMOSPHERE.install_post(self)
	load_progress.emit("The coast is ready.", .98)


static func curve(x: float) -> float:
	return -.0022 * x * x + .00001 * x * x * x


static func smooth(a: float, b: float, value: float) -> float:
	var t := clampf((value - a) / (b - a), 0, 1)
	return t * t * (3 - 2 * t)


static func hash2(x: float, z: float) -> float:
	return fposmod(sin(x * 127.1 + z * 311.7) * 43758.5453, 1)


static func noise2(x: float, z: float) -> float:
	var ix := floorf(x)
	var iz := floorf(z)
	var fx := smooth(0, 1, x - ix)
	var fz := smooth(0, 1, z - iz)
	return lerpf(lerpf(hash2(ix, iz), hash2(ix + 1, iz), fx), lerpf(hash2(ix, iz + 1), hash2(ix + 1, iz + 1), fx), fz)


func spline(points: Array, closed: bool, subdivisions: int) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var count := points.size()
	for i in range(count if closed else count - 1):
		var p0: Vector2 = points[posmod(i - 1, count) if closed else maxi(0, i - 1)]
		var p1: Vector2 = points[i]
		var p2: Vector2 = points[(i + 1) % count]
		var p3: Vector2 = points[(i + 2) % count if closed else mini(count - 1, i + 2)]
		for j in subdivisions:
			var t := float(j) / subdivisions
			out.append(
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
	if not closed:
		out.append(points[-1])
	return out


func _build_roads() -> void:
	var loop: Array = []
	for x in range(-38, 39, 4):
		loop.append(Vector2(x, -12.5 + curve(x)))
	for p in [
		[50, -8],
		[56, 4],
		[57, 20],
		[55, 36],
		[50, 50],
		[40, 60],
		[26, 66],
		[10, 68],
		[-10, 68],
		[-26, 66],
		[-40, 60],
		[-50, 50],
		[-55, 36],
		[-57, 20],
		[-56, 4],
		[-50, -8]
	]:
		loop.append(Vector2(p[0], p[1]))
	var coast: Array = []
	for x in range(-100, 131, 5):
		coast.append(Vector2(x, -12.5 + curve(x)))
	roads = [spline(loop, true, 6), spline(coast, false, 4)]
	for ri in roads.size():
		var pts: Array = roads[ri]
		var along := 0.0
		for i in range(pts.size() if ri == 0 else pts.size() - 1):
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[(i + 1) % pts.size()]
			var length := a.distance_to(b)
			var id := _segments.size()
			_segments.append([a, b, length, along, ri])
			along += length
			for gz in range(floori((minf(a.y, b.y) - 14) / 8), floori((maxf(a.y, b.y) + 14) / 8) + 1):
				for gx in range(floori((minf(a.x, b.x) - 14) / 8), floori((maxf(a.x, b.x) + 14) / 8) + 1):
					var key := Vector2i(gx, gz)
					if not _road_grid.has(key):
						_road_grid[key] = []
					_road_grid[key].append(id)
	var rails: Array = []
	for p in [[-80, 36], [-52, 54], [-44, 68], [-40, 84], [-20, 96], [60, 96], [108, 70]]:
		rails.append(Vector2(p[0], p[1]))
	rail_points = spline(rails, false, 8)


func road_info(x: float, z: float) -> Dictionary:
	var out := {"d": 99.0, "s": 0.0, "tx": 1.0, "tz": 0.0, "side": 1.0, "road": -1}
	var point := Vector2(x, z)
	var best := 9801.0
	for id in _road_grid.get(Vector2i(floori(x / 8), floori(z / 8)), []):
		var seg: Array = _segments[id]
		var a: Vector2 = seg[0]
		var v: Vector2 = seg[1] - a
		var t := clampf((point - a).dot(v) / v.length_squared(), 0, 1)
		var delta := point - (a + v * t)
		var ds := delta.length_squared()
		if ds < best:
			best = ds
			out.s = seg[3] + t * seg[2]
			out.tx = v.x / seg[2]
			out.tz = v.y / seg[2]
			out.side = 1.0 if v.cross(delta) >= 0 else -1.0
			out.road = seg[4]
	out.d = sqrt(best)
	return out


func rail_distance(x: float, z: float) -> float:
	var best := 1000000.0
	var point := Vector2(x, z)
	for i in rail_points.size() - 1:
		var a := rail_points[i]
		var v := rail_points[i + 1] - a
		best = minf(best, (point - a - v * clampf((point - a).dot(v) / v.length_squared(), 0, 1)).length_squared())
	return sqrt(best)


func zone_weight(zone: Rect2, x: float, z: float, margin: float) -> float:
	var d := Vector2(
		maxf(maxf(zone.position.x - x, x - zone.end.x), 0), maxf(maxf(zone.position.y - z, z - zone.end.y), 0)
	)
	return 1 - smooth(0, margin, d.length())


func road_height(_x: float, z: float) -> float:
	return clampf(.045 * (z + 12), 0, 3)


func height_at(x: float, z: float) -> float:
	var zr := z - curve(x)
	var rough := (noise2(x * .08 + 3.1, z * .08 + 7.7) - .5) * 1.4 + (noise2(x * .35, z * .35) - .5) * .25
	var h := road_height(x, z) + rough
	h += smooth(-74, -125, x) * 20 * (1 + .25 * noise2(x * .03, z * .03))
	h += smooth(88, 135, z) * 25 * (1 + .25 * noise2(x * .03 + 5, z * .03))
	h += smooth(104, 145, x) * 12 * (1 + .25 * noise2(x * .03 + 9, z * .03 + 2))
	var radius := Vector2(x, z - 30).length()
	h += 8 * (1 - smooth(8, 27, radius)) * (1 + .08 * noise2(x * .2, z * .2))
	if radius < 8:
		h -= rough * .8
	for pair in [["paddy", .4], ["paddy_in", .4], ["farm", 2.6], ["village", 3.0]]:
		h = lerpf(h, pair[1], zone_weight(ZONES[pair[0]], x, z, 6))
	h = lerpf(h, road_height(x, z), zone_weight(ZONES.vending, x, z, 6))
	h -= 5.5 * zone_weight(ZONES.bed, x, z, 7) * (1 - .3 * noise2(x * .3, z * .3))
	h = lerpf(h, road_height(x, z), 1 - smooth(4.6, 9.5, road_info(x, z).d))
	var lay := smooth(-12, -8, x) * (1 - smooth(-4.8, .2, x)) * (1 - smooth(6, 11, zr)) * smooth(-11.5, -8.5, zr)
	h = lerpf(h, 0, lay) + lay * (noise2(x * .6, z * .6) - .5) * .12
	if z < -4:
		h -= smooth(17, 26, -zr) * 34
	return maxf(h, -34)


func walkable(x: float, z: float) -> bool:
	return (
		absf(x) <= 118 and z <= 100 and z >= -40 and not (z < -4 and z - curve(x) < -19.2) and height_at(x, z) >= -1.5
	)


func excluded(x: float, z: float, margin: float = 1.5) -> bool:
	if road_info(x, z).d < 4 + margin:
		return true
	for pair in [["paddy", 1], ["paddy_in", 1], ["yard", 1], ["street", 4], ["pave", 2], ["gully", 2]]:
		if (ZONES[pair[0]] as Rect2).grow(pair[1]).has_point(Vector2(x, z)):
			return true
	return (
		(z > 30 and rail_distance(x, z) < 4)
		or Vector2(x, z - 30).length() < 8
		or (x > -11 and x < 11 and z > 5 and z < 23)
	)


func _build_terrain() -> void:
	var signature: String = generation_signature
	var terrain_cache: String = "user://terrain_" + signature + ".res"
	var layout_cache: String = "user://layout_" + signature + ".res"
	if FileAccess.file_exists(terrain_cache) and FileAccess.file_exists(layout_cache):
		_install_terrain(load(terrain_cache), load(layout_cache))
		return
	var image := Image.create(1024, 1024, false, Image.FORMAT_RGBA8)
	for j in 1024:
		if j % 64 == 0:
			load_progress.emit("Shaping fields and shoreline…", .14 + .12 * j / 1024.0)
			await get_tree().process_frame
		var z := -180 + (j + .5) * 360 / 1024
		for i in 1024:
			var x := -180 + (i + .5) * 360 / 1024
			var ri := road_info(x, z)
			var zone := 0.0
			var point := Vector2(x, z)
			if ZONES.paddy.has_point(point) or ZONES.paddy_in.has_point(point):
				zone = .2
			elif ZONES.street.has_point(point) or ZONES.pave.has_point(point):
				zone = .4
			elif ZONES.yard.has_point(point):
				zone = .6
			elif (
				ZONES.bed.has_point(point) or (z > 40 and z < 110 and x > -90 and x < 120 and rail_distance(x, z) < 3.5)
			):
				zone = .8
			image.set_pixel(i, j, Color(minf(ri.d, 16) / 16, fposmod(ri.s, 8) / 8, zone, 1))
	var layout := ImageTexture.create_from_image(image)
	ResourceSaver.save(layout, layout_cache)
	# Sample the 360m terrain at .818m intervals.
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uv := PackedVector2Array()
	var indices := PackedInt32Array()
	const N := 440
	for j in N + 1:
		var z: float = -180.0 + 360.0 * j / N
		for i in N + 1:
			var x: float = -180.0 + 360.0 * i / N
			verts.append(Vector3(x, height_at(x, z), z))
			normals.append(Vector3.UP)
			uv.append(Vector2((x + 180) / 360, (z + 180) / 360))
	for j in range(1, N):
		for i in range(1, N):
			var k := j * (N + 1) + i
			normals[k] = (
				Vector3(verts[k - 1].y - verts[k + 1].y, 720.0 / N, verts[k - N - 1].y - verts[k + N + 1].y)
				. normalized()
			)
	for j in N:
		for i in N:
			var a := j * (N + 1) + i
			indices.append_array([a, a + 1, a + N + 1, a + 1, a + N + 2, a + N + 1])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	ResourceSaver.save(mesh, terrain_cache)
	_install_terrain(mesh, layout)


func _install_terrain(mesh: ArrayMesh, layout: Texture2D) -> void:
	var terrain_mat := ShaderMaterial.new()
	terrain_mat.shader = load("res://maps/seabreeze_village/terrain.gdshader")
	terrain_mat.set_shader_parameter("layout_map", layout)
	var node := MeshInstance3D.new()
	node.name = "ProceduralTerrain"
	node.mesh = mesh
	node.material_override = terrain_mat
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	# Terrain collision covers the full playable area. Camera rays use the same surface.
	node.create_trimesh_collision()


func _wire(a: Vector3, b: Vector3, sag: float) -> void:
	var previous := a
	for i in range(1, 21):
		var t := i / 20.0
		var point := a.lerp(b, t) - Vector3.UP * sin(t * PI) * sag
		CozyPrimitives.beam(self, previous, point, .021, palette.color("5c636a"))
		previous = point


func _guardrail(points: Array[Vector2]) -> void:
	var previous := Vector3.ZERO
	for i in points.size():
		var p := Vector3(points[i].x, height_at(points[i].x, points[i].y), points[i].y)
		CozyPrimitives.box(self, p + Vector3(0, .5, 0), Vector3(.12, 1, .12), palette.color("828986"), true)
		if i > 0:
			var a := previous + Vector3.UP * .7
			var b := p + Vector3.UP * .7
			var n := CozyPrimitives.box(self, (a + b) / 2, Vector3(.1, .25, a.distance_to(b)), palette.color("a3a9a4"))
			n.look_at_from_position((a + b) / 2, b)
			# The low guardrail has a matching collision ribbon.
			CozyCollision.static_box(n, Vector3.ZERO, Vector3(.14, .7, a.distance_to(b)))
		previous = p


func _sign(pos: Vector3, text: String, color: String, size: Vector2 = Vector2(.8, .5), yaw: float = 0) -> void:
	var sign_root := Node3D.new()
	add_child(sign_root)
	sign_root.position = pos
	sign_root.rotation.y = yaw
	CozyPrimitives.cylinder(sign_root, Vector3(0, .65, 0), .035, .035, 1.3, palette.color("828986"))
	CozyPrimitives.box(sign_root, Vector3(0, 1.3, 0), Vector3(size.x, size.y, .045), palette.color(color))
	if text == ">>":
		for dx in [-size.x * .22, size.x * .19]:
			for side in [-1, 1]:
				var bar := CozyPrimitives.box(
					sign_root,
					Vector3(dx, 1.3 + side * size.y * .14, .028),
					Vector3(size.x * .29, .055, .008),
					palette.color("343b3c")
				)
				bar.rotation.z = -side * .65
	else:
		var label := Label3D.new()
		label.text = text
		label.font_size = 64
		label.pixel_size = .005
		label.modulate = Color("343b3c")
		label.position = Vector3(0, 1.3, .03)
		sign_root.add_child(label)


func _build_coast_props() -> void:
	var points: Array[Vector2] = []
	for i in 7:
		points.append(Vector2(-9.35, 6.5 - i * 2))
	for i in 13:
		var x: float = -10.2 - i * 3
		points.append(Vector2(x, -7.5 + curve(x)))
	_guardrail(points)
	points = []
	for x in range(-60, 37, 3):
		points.append(Vector2(x, -17.5 + curve(x)))
	_guardrail(points)
	var tops: Array[Vector3] = []
	for p in [
		Vector2(-34, -6.3 + curve(-34)),
		Vector2(-10.5, -17.3 + curve(-10.5)),
		Vector2(16, -17.3 + curve(16)),
		Vector2(42, -17.3 + curve(42)),
		Vector2(64, -17.3 + curve(64))
	]:
		var y := height_at(p.x, p.y)
		CozyPrimitives.cylinder(self, Vector3(p.x, y + 5, p.y), .19, .12, 10.5, palette.color("9c9478"))
		CozyPrimitives.box(self, Vector3(p.x, y + 9, p.y), Vector3(2, .12, .18), palette.color("5c6358"))
		for dx in [-.85, 0, .85]:
			CozyPrimitives.cylinder(self, Vector3(p.x + dx, y + 9.2, p.y), .085, .08, .3, palette.color("d9d9c8"))
		tops.append(Vector3(p.x, y + 9.35, p.y))
		CozyCollision.static_box(self, Vector3(p.x, y + 5, p.y), Vector3(.35, 10, .35))
	for i in tops.size() - 1:
		for dx in [-.85, 0, .85]:
			_wire(tops[i] + Vector3(dx, 0, 0), tops[i + 1] + Vector3(dx, 0, 0), 1)
		_wire(tops[i] - Vector3.UP * 2, tops[i + 1] - Vector3.UP * 2, 1.2)
	var gantry_z: float = -18 + curve(8)
	var base := height_at(8, gantry_z)
	for x in [7.4, 8.6]:
		CozyPrimitives.cylinder(self, Vector3(x, base + 5.1, gantry_z), .16, .13, 10.5, palette.color("9c9478"))
	for y in [6.9, 9.8]:
		CozyPrimitives.box(self, Vector3(8, base + y, gantry_z), Vector3(1.4, .12, .16), palette.color("5c6358"))
	CozyPrimitives.box(self, Vector3(8, base + 6.5, gantry_z), Vector3(.85, .9, .14), palette.color("dadac8"))
	for x in [7.4, 8.6]:
		_wire(Vector3(x, base + 10, gantry_z), tops[2], .3)
	_sign(Vector3(-8.75, height_at(-8.75, 3.2), 3.2), ">>", "ddd879", Vector2(.5, .38))
	_sign(Vector3(-1, height_at(-1, -17.05), -17.05), ">>", "e5d478", Vector2(.85, .58), -.95)
	_sign(Vector3(40, height_at(40, -17.1 + curve(40)), -17.1 + curve(40)), ">>", "e5d478", Vector2(.8, .55), -1.35)
	_sign(Vector3(-12.5, height_at(-12.5, -17.2 + curve(-12.5)), -17.2 + curve(-12.5)), "↗", "e5c063", Vector2(.7, .7))
	_sign(Vector3(24, height_at(24, -17.2 + curve(24)), -17.2 + curve(24)), "40", "efe5d6", Vector2(.8, .8))
	# Parked olive kei car, 4.6m length, with distinct dark roof and glass cabin.
	var car := Node3D.new()
	add_child(car)
	car.position = Vector3(21.5, height_at(21.5, -14.2 + curve(21.5)), -14.2 + curve(21.5))
	car.rotation.y = .08
	CozyPrimitives.box(car, Vector3(0, .62, 0), Vector3(4.6, .62, 1.65), palette.color("70867e"), true)
	CozyPrimitives.box(car, Vector3(0, 1.2, 0), Vector3(2.55, .65, 1.5), palette.color("26394a"))
	CozyPrimitives.box(car, Vector3(0, 1.56, 0), Vector3(2.7, .12, 1.65), palette.color("3a3d44"))
	for x in [-1.5, 1.5]:
		for z in [-.82, .82]:
			var wheel := CozyPrimitives.cylinder(car, Vector3(x, .37, z), .36, .36, .2, palette.color("1c1c1c"))
			wheel.rotation.x = PI / 2
	for z in [-.56, .56]:
		CozyPrimitives.box(car, Vector3(-2.31, .74, z), Vector3(.045, .2, .32), palette.color("c83332"))


func surface_at(x: float, z: float) -> String:
	var relative_z := z - curve(x)
	if x > -9 and x < -3.8 and relative_z > -8.5 and relative_z < 7:
		return "dirt"
	if road_info(x, z).d < 4.3:
		return "road"
	if relative_z < -27 and z < -4:
		return "sea"
	var p := Vector2(x, z)
	if ZONES.paddy.has_point(p) or ZONES.paddy_in.has_point(p):
		return "paddy"
	if ZONES.street.has_point(p) or ZONES.pave.has_point(p):
		return "concrete"
	if ZONES.yard.has_point(p):
		return "hardpack"
	if ZONES.bed.has_point(p) or (z > 40 and rail_distance(x, z) < 3.5):
		return "gravel"
	return "grass"
