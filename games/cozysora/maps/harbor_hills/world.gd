extends CozyMap
const ATMOSPHERE = preload("res://maps/harbor_hills/atmosphere.tres")
## One fictional 360 m waterfront district. All district coordinates are metres.
const Geometry = preload("res://maps/harbor_hills/geometry.gd")
const Architecture = preload("res://maps/harbor_hills/neighborhood.gd")
const Nature = preload("res://maps/harbor_hills/nature.gd")
const Transit = preload("res://maps/harbor_hills/transit.gd")
const STREETS_X = [-76.0, 8.0, 90.0]
const STREETS_Z = [-102.0, -32.0, 46.0, 106.0]
var static_content: Node3D
var geo
var rng = RandomNumberGenerator.new()
var transit: Node3D
var fog_banks: Array = []
var time = 0.0
var terrace_cells: Dictionary = {}
var street_ends: Array = []


func build() -> void:
	generation_signature = CozySceneCache.signature("res://maps/harbor_hills")
	street_ends = road_ends()
	for plot in Architecture.plots():
		var turn = Basis(Vector3.UP, plot.yaw)
		var front = Vector3(plot.x, 0, plot.z) + turn * Vector3(0, 0, plot.d * .5 + 2)
		var depth = 2.4 if absf(cos(plot.yaw)) > .5 else 3.8
		var pad = {
			"center": Vector2(plot.x, plot.z),
			"yaw": plot.yaw,
			"half_width": plot.w * .5 + .13,
			"back": -plot.d * .5,
			"front": plot.d * .5 + depth,
			"level": terrain_height(front.x, front.z) + .15
		}
		for cell_x in range(floori((plot.x - 15) / 16), floori((plot.x + 15) / 16) + 1):
			for cell_z in range(floori((plot.z - 15) / 16), floori((plot.z + 15) / 16) + 1):
				var cell = Vector2i(cell_x, cell_z)
				if not terrace_cells.has(cell):
					terrace_cells[cell] = []
				terrace_cells[cell].append(pad)
	supports_surface_traversal = true
	flight_bounds = AABB(Vector3(-178, -1, -178), Vector3(356, 157, 356))
	ambience = {
		"wind_gain": .16,
		"wave_base": .032,
		"wave_swell": .014,
		"cicada_frequencies": Vector2(3200, 3600),
		"cicada_gain": 0.0,
		"birds": true
	}
	scenic_views = {
		"waterfront": [-36.0, -111.0, 4.0, -.78, .04],
		"commercial": [8.0, -68.0, 5.0, 1.57, .02],
		"residential": [77.0, 39.7, 29.0, 1.57, -.04],
		"park": [-105.0, 96.0, 58.0, -.2, -.19],
		"cable_car": [16.0, -98.0, 32.0, 1.32, -.02],
		"stairs": [-39.0, 49.0, 38.0, 3.14, .23],
		"garden": [-34.0, -68.0, 29.0, 1.75, -.03],
		"rooftops": [51.0, -10.0, 45.0, 1.8, -.28],
		"flight": [-48.0, 105.0, 88.0, -.25, -.52],
		"street_end": [94.0, 125.0, 0.0, 3.14, -.1],
		"top": [0.0, 5.0, 305.0, 0.0, -1.57]
	}
	for key in ["commercial", "residential", "park", "cable_car", "stairs", "garden", "street_end"]:
		var v = scenic_views[key]
		v[2] = (
			height_at(v[0], v[1])
			+ (2.0 if key == "park" else .0 if key in ["residential", "garden", "cable_car"] else 1.0)
		)
	ATMOSPHERE.install(self)
	load_progress.emit("Finding the way to Harbor Hills…", .08)
	await get_tree().process_frame
	var cache = "user://harbor_hills_" + generation_signature + ".scn"
	if FileAccess.file_exists(cache):
		var packed = load(cache) as PackedScene
		static_content = packed.instantiate()
		add_child(static_content)
		print("Harbor Hills static cache restored: ", cache)
	else:
		static_content = Node3D.new()
		static_content.name = "Harbor Hills district"
		add_child(static_content)
		geo = Geometry.new(static_content)
		geo.ground_height = height_at
		geo.plant_clearance = road_end_contains
		rng.seed = 1947
		_terrain()
		_backdrop_land()
		load_progress.emit("Paving streets above the bay…", .22)
		await get_tree().process_frame
		_streets()
		var architecture = Architecture.new()
		await architecture.build(self, geo)
		load_progress.emit("Growing the cypress gardens…", .72)
		await get_tree().process_frame
		var nature = Nature.new()
		nature.build(self, geo)
		var details = preload("res://maps/harbor_hills/details.gd").new()
		details.build(self, geo)
		geo.finish()
		CozySceneCache.save(static_content, cache)
		print("Harbor Hills district generated: ", cache)
		geo = null
	load_progress.emit("Ringing the last departure bell…", .92)
	await get_tree().process_frame
	transit = Transit.new()
	add_child(transit)
	transit.build(self)
	_fog_and_birds()
	_summer_air()
	ATMOSPHERE.install_post(self)
	load_progress.emit("The bay is waiting.", 1.0)


func terrain_height(x: float, z: float) -> float:
	if z < -119:
		return -3.5
	var t = clampf((z + 105) / 205.0, 0, 1)
	var rise = 44 * t * t * (3 - 2 * t)
	var hill = 12 * exp(-pow((x + 90) / 75, 2) - pow((z - 69) / 70, 2)) * smoothstep(-90, 0, z)
	return 3.0 + rise + hill


func height_at(x: float, z: float) -> float:
	for stair_x in [-38.0, -104.0]:
		if absf(x - stair_x) < 2.6 and z >= 47 and z <= 91:
			var landing = terrain_height(-110, 99) if stair_x == -104.0 else terrain_height(x, 91)
			return lerpf(terrain_height(x, 47), landing, (z - 47) / 44.0)
	var public_way = false
	for street in STREETS_X:
		if absf(x - street) < 8.3:
			public_way = true
	for street in STREETS_Z:
		if absf(z - street) < 8.3:
			public_way = true
	# Each building and its forecourt share a graded pad, preventing uphill soil
	# from swallowing café tables and downhill foundations from floating.
	for pad in [] if public_way else terrace_cells.get(Vector2i(floori(x / 16), floori(z / 16)), []):
		if absf(x - pad.center.x) > 15 or absf(z - pad.center.y) > 15:
			continue
		var local = (Vector2(x, z) - pad.center).rotated(pad.yaw)
		var edge = maxf(absf(local.x) - pad.half_width, maxf(pad.back - local.y, local.y - pad.front))
		if edge < .75:
			return minf(terrain_height(x, z), lerpf(pad.level, terrain_height(x, z), smoothstep(0, .75, edge)))
	# Small graded terraces keep occupied courtyards level within the larger hill.
	var ground = terrain_height(x, z)
	for court_x in [-40.0, 52.0]:
		for court_z in [-68.0, 7.0]:
			var radius = Vector2(x - court_x, z - court_z - 1).length()
			if radius < 5.5:
				return lerpf(terrain_height(court_x, court_z + 1), ground, smoothstep(3.4, 5.5, radius))
			for side in [-1, 1]:
				var center_x = court_x + side * 14
				var edge = maxf(absf(x - center_x) - 4.1, absf(z - court_z) - 7.0)
				if edge < 2:
					return lerpf(terrain_height(center_x, court_z), ground, smoothstep(0, 2, edge))
	var overlook = Vector2((x + 110) / 10.5, (z - 99) / 8.5).length()
	if overlook < 1.3:
		return lerpf(terrain_height(-110, 99), ground, smoothstep(1, 1.3, overlook))
	if x > -120 and x < -108 and z < -119 and z > -163:
		return 2.65
	return terrain_height(x, z)


func walkable(x: float, z: float) -> bool:
	if x > -119.5 and x < -108.5 and z > -162 and z < -116:
		return true
	return absf(x) < 171 and z > -116.5 and z < 170


func set_paused(value: bool) -> void:
	if is_instance_valid(transit):
		transit.set_paused(value)


func point(x: float, z: float, offset: float = 0) -> Vector3:
	return Vector3(x, height_at(x, z) + offset, z)


func _terrain() -> void:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for iz in range(360):
		for ix in range(360):
			var x = -180 + ix * 1.0
			var z = -180 + iz * 1.0
			var a = point(x, z)
			var b = point(x + 1, z)
			var c = point(x + 1, z + 1)
			var d = point(x, z + 1)
			for v in [a, b, c, a, c, d]:
				st.add_vertex(v)
	st.generate_normals()
	var mesh = st.commit()
	var n = MeshInstance3D.new()
	n.mesh = mesh
	var mat = ShaderMaterial.new()
	mat.shader = load("res://maps/harbor_hills/ground.gdshader")
	n.material_override = mat
	static_content.add_child(n)
	CozyCollision.mesh(geo.collision, mesh)
	# Seawall face, coping and broad waterfront promenade.
	geo.box(Vector3(0, .0, -119), Vector3(352, 6.4, 2.2), "7c827b", true, 0, "brick")
	geo.box(Vector3(0, 3.18, -119), Vector3(352, .28, 2.6), "d0c7ac", false)
	var path = []
	for x in range(-174, 175, 2):
		path.append(point(x, -113, .09))
	geo.ribbon(path, 9, "c3bda6", true)
	# Western ridge and eastern perimeter paths close the playable district naturally.
	for x in [-147.0, 151.0]:
		path = []
		for z in range(-104, 165, 2):
			path.append(point(x + sin(z * .018) * 9, z, .05))
		geo.ribbon(path, 3.4, "bcad8e", true)


func _backdrop_land() -> void:
	# Non-playable surrounding hills keep the district attached to the fictional city.
	for rect in [Rect2(-620, -119, 440, 739), Rect2(180, -119, 440, 739), Rect2(-180, 180, 360, 440)]:
		var st = SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for iz in range(ceili(rect.size.y / 4)):
			for ix in range(ceili(rect.size.x / 4)):
				var x = rect.position.x + ix * 4
				var z = rect.position.y + iz * 4
				var positions = []
				for p in [Vector2(x, z), Vector2(x + 4, z), Vector2(x + 4, z + 4), Vector2(x, z + 4)]:
					var outside = maxf(absf(p.x) - 180, p.y - 180)
					positions.append(
						Vector3(
							p.x,
							(
								terrain_height(p.x, p.y)
								+ (smoothstep(0, 110, outside) * (12 + 11 * sin(p.x * .009) * sin(p.y * .012)))
							),
							p.y
						)
					)
				for i in [0, 1, 2, 0, 2, 3]:
					st.add_vertex(positions[i])
		st.generate_normals()
		var n = MeshInstance3D.new()
		n.mesh = st.commit()
		n.material_override = geo.material("71866d")
		static_content.add_child(n)
	# Suggest adjoining neighborhoods behind the playable streets without copied buildings.
	for i in range(42):
		var x = -157 + i * 8.0
		var z = 199 + (i % 3) * 14
		var y = terrain_height(x, z)
		var h = 7 + (i % 5) * 1.6
		geo.box(Vector3(x, y + h * .5, z), Vector3(7, h, 10), ["929e90", "a2a38e", "91a5a3", "b1a393"][i % 4])
		geo.box(Vector3(x, y + h + .2, z), Vector3(7.5, .4, 10.5), "77897f")
		for row in range(2):
			for col in range(3):
				geo.box(Vector3(x - 2 + col * 2, y + 2 + row * 3, z - 5.03), Vector3(.9, 1.2, .04), "607d7e")


func _streets() -> void:
	for x in STREETS_X:
		var path = []
		for z in range(-108, 135, 2):
			path.append(point(x, z, .025))
		geo.ribbon(path, 10.8, "5c5e5a", false, true, "asphalt")
		for side in [-1, 1]:
			_sidewalk(x + side * 6.8, true, -108, 134, STREETS_Z)
			path = []
			for z in range(-108, 135, 2):
				path.append(point(x + side * 5.45, z, .13))
			geo.ribbon(path, .2, "ddd4bd")
		# Broken centre lines keep the carriageway quiet and human-scaled.
		for z in range(-93, 130, 9):
			var crossing = false
			for cross in STREETS_Z:
				if absf(z - cross) < 7:
					crossing = true
			if not crossing:
				for dx in [-.15, .15]:
					geo.ribbon([point(x + dx, z, .04), point(x + dx, z + 3, .04)], .09, "d4b563")
	for z in STREETS_Z:
		var path = []
		for x in range(-119, 129):
			path.append(point(x, z, .032))
		geo.ribbon(path, 10.8, "5c5e5a", false, true, "asphalt")
		for side in [-1, 1]:
			_sidewalk(z + side * 6.8, false, -119, 128, STREETS_X)
		for street_x in STREETS_X:
			for side in [-1, 1]:
				for stripe in range(-4, 5):
					geo.ribbon(
						[
							point(street_x + stripe, z + side * 6 - .9, .051),
							point(street_x + stripe, z + side * 6 + .9, .051)
						],
						.5,
						"e3dcc5"
					)
	# Semicircular ends continue both pavements around the carriageway.
	for end in street_ends:
		_round_street_end(end[0], end[1])
	# Cable rails and cable slot follow the full main grade into the turning circle.
	for dx in [-.76, .76, 0]:
		var path = []
		for z in range(-103, 93):
			path.append(point(8 + dx, z, .052))
		geo.ribbon(path, .065 if dx != 0 else .1, "a2a6a0" if dx != 0 else "303c40")
	var circle = []
	for i in range(65):
		var angle = TAU * i / 64
		circle.append(point(8 + sin(angle) * 5, 96 + cos(angle) * 5, .075))
	geo.ribbon(circle, .08, "abb0a6")
	geo.add("cylinder", point(8, 96, .015), Vector3(9.7, .09, 9.7), "635e50")


func road_ends() -> Array:
	var ends = []
	for x in STREETS_X:
		ends.append([Vector2(x, 134), Vector2(0, 1)])
	for z in STREETS_Z:
		ends.append([Vector2(-119, z), Vector2(-1, 0)])
		ends.append([Vector2(128, z), Vector2(1, 0)])
	return ends


func road_end_contains(x: float, z: float, margin: float = 0.0) -> bool:
	# Includes the sidewalk arc. The inward half already belongs to the street.
	for end in street_ends:
		var delta = Vector2(x, z) - end[0]
		if delta.dot(end[1]) >= -margin and delta.length_squared() < pow(8.2 + margin, 2):
			return true
	return false


func _round_street_end(center: Vector2, forward: Vector2) -> void:
	geo.semicircle(center, forward, 0, 5.4, .032, "5c5e5a", false, "asphalt")
	geo.semicircle(center, forward, 5.4, 8.2, .172, "b9b7a5", true, "paving")
	geo.semicircle(center, forward, 5.35, 5.55, .18, "ddd4bd")


func _sidewalk(fixed: float, vertical: bool, start: int, end: int, crossings: Array) -> void:
	var path = []
	for coordinate in range(start, end + 1):
		var distance = 1000.0
		for cross in crossings:
			distance = minf(distance, absf(coordinate - cross))
		var stair_crossing = (
			not vertical
			and absf(fixed - 52.8) < .1
			and (absf(coordinate + 104) < 2.6 or absf(coordinate + 38) < 2.6 or absf(coordinate + 56) < 1.5)
		)
		if distance < 5.2 or stair_crossing:
			if path.size() > 1:
				geo.ribbon(path, 2.8, "b9b7a5", true, true, "paving")
			path = []
			continue
		var lift = .032 + .14 * smoothstep(8.2, 10.5, distance)
		path.append(point(fixed, coordinate, lift) if vertical else point(coordinate, fixed, lift))
	if path.size() > 1:
		geo.ribbon(path, 2.8, "b9b7a5", true, true, "paving")


func _fog_and_birds() -> void:
	for i in range(9):
		var fog = MeshInstance3D.new()
		var mesh = QuadMesh.new()
		mesh.size = Vector2(150 + i * 9, 20 + i * 2)
		fog.mesh = mesh
		var material = ShaderMaterial.new()
		material.shader = load("res://maps/harbor_hills/fog.gdshader")
		material.set_shader_parameter("phase", i * 1.7)
		fog.material_override = material
		fog.position = Vector3(-260 + i * 72, 6 + i % 3 * 4, -170 - i % 3 * 75)
		fog.rotation.x = -.13
		fog.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(fog)
		fog_banks.append(fog)


func _process(delta: float) -> void:
	time += delta
	for i in fog_banks.size():
		fog_banks[i].position.x = -260 + i * 72 + sin(time * .013 + i) * 33


func _summer_air() -> void:
	# Sparse moving seed heads catch the sunlight around planted gathering places.
	for at in [Vector2(-53, 106), Vector2(-108, 78), Vector2(-40, -68), Vector2(52, 7)]:
		preload("res://maps/harbor_hills/air.tres").install(self, point(at.x, at.y, 1.5))
