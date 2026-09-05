extends RefCounted
## Seabreeze plant geometry. The caller supplies its existing random stream.
var _rng: SeabreezeRandom


func _init(random: SeabreezeRandom) -> void:
	_rng = random


func unit() -> Vector3:
	return Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1)).normalized()


func tree_mesh(seed_value: int, tall: bool) -> Dictionary:
	var saved: int = _rng.state
	_rng.seed = seed_value
	var h: float = _rng.randf_range(7, 11) if tall else _rng.randf_range(4.5, 7.5)
	var radii := Vector3(_rng.randf_range(2.4, 4.2), _rng.randf_range(2, 3.4), _rng.randf_range(2.4, 4.2))
	var center := Vector3(0, h + radii.y * 0.35, 0)
	var leaves := canopy(
		center,
		radii,
		_rng.randi_range(6, 9),
		_rng.randi_range(52, 69),
		7,
		_rng.randf_range(1.2, 1.6),
		_rng.randf_range(0.9, 1.3),
		h * 0.5,
		h + radii.y * 1.6
	)
	var trunk := SurfaceTool.new()
	trunk.begin(Mesh.PRIMITIVE_TRIANGLES)
	var trunk_h: float = h + radii.y * 0.2
	var radius: float = _rng.randf_range(0.22, 0.36)
	tapered_branch(trunk, Vector3.ZERO, Vector3(0, trunk_h, 0), radius, radius * 0.55, 9)
	for j in range(4):
		var end := Vector3(
			_rng.randf_range(-0.6, 0.6) * radii.x,
			h + radii.y * _rng.randf_range(0.1, 0.7),
			_rng.randf_range(-0.6, 0.6) * radii.z
		)
		tapered_branch(trunk, Vector3(0, trunk_h, 0), end, radius * 0.36, radius * 0.16, 6)
	trunk.generate_normals()
	var result := {"leaves": leaves, "trunk": trunk.commit(), "radius": maxf(radii.x, radii.z) + 1}
	_rng.state = saved
	return result


func bush_mesh(kind: int) -> Dictionary:
	var saved: int = _rng.state
	_rng.seed = [21, 22, 23, 31, 41, 42, 43][kind]
	var radii := (
		Vector3(_rng.randf_range(1.2, 2.4), _rng.randf_range(0.9, 1.7), _rng.randf_range(1.2, 2.4))
		if kind < 3
		else Vector3.ONE
	)
	var clusters: int = 0
	var size: float = 0
	if kind == 3:
		radii = Vector3(1.6, 1.5, 1.6)
		clusters = 40
		size = 0.75
	elif kind >= 4:
		radii = [Vector3(2.6, 1.9, 2.4), Vector3(2.2, 2.3, 2.2), Vector3(3, 1.6, 2.6)][kind - 4]
		clusters = [70, 64, 76][kind - 4]
		size = [0.78, 0.72, 0.8][kind - 4]
	var lobes: int = _rng.randi_range(5, 7)
	if kind < 3:
		clusters = _rng.randi_range(18, 27)
		size = _rng.randf_range(0.85, 1.15)
	var leaves := canopy(
		Vector3(0, radii.y * 0.75, 0),
		radii,
		lobes,
		clusters,
		6,
		size,
		_rng.randf_range(0.55, 0.85),
		0,
		radii.y * 2,
		"gold" if kind in [2, 5] else ("cool" if kind == 3 else "green")
	)
	_rng.state = saved
	return {"leaves": leaves, "radius": maxf(radii.x, radii.z)}


func canopy(
	center: Vector3,
	radii: Vector3,
	lobes: int,
	clusters: int,
	cards: int,
	card_size: float,
	cluster_radius: float,
	sway_base: float,
	sway_top: float,
	tint_kind: String = "green"
) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var centers: Array[Vector3] = []
	for i in range(lobes):
		var phi: float = _rng.randf() * TAU
		var y: float = _rng.randf_range(-1, 1)
		centers.append(
			(
				center
				+ Vector3(sqrt(1 - y * y) * cos(phi), y, sqrt(1 - y * y) * sin(phi)) * radii * 0.7
				+ Vector3(0, radii.y * 0.1, 0)
			)
		)
	for i in range(clusters):
		var cluster: Vector3 = (
			centers[_rng.randi_range(0, centers.size() - 1)] + unit() * pow(_rng.randf(), 0.6) * cluster_radius * 1.6
		)
		var tint: Color
		if tint_kind == "gold":
			tint = Color(_rng.randf_range(1.1, 1.6), _rng.randf_range(1, 1.25), _rng.randf_range(0.45, 0.75))
		elif tint_kind == "cool":
			tint = Color(_rng.randf_range(0.7, 1), _rng.randf_range(0.85, 1.1), _rng.randf_range(0.85, 1.15))
		else:
			tint = Color(_rng.randf_range(0.85, 1.3), _rng.randf_range(0.9, 1.15), _rng.randf_range(0.75, 1.05))
		var shade: float = (0.72 + 0.28 * minf(1, ((cluster - center) / radii).length())) * _rng.randf_range(0.62, 1.34)
		var color: Color = tint * shade
		for j in range(cards):
			var p: Vector3 = cluster + unit() * pow(_rng.randf(), 0.7) * cluster_radius
			var radial: Vector3 = ((p - center) / (radii * radii)).normalized()
			var outward: Vector3 = (p - cluster).normalized().lerp(radial, 0.72).normalized()
			var normal: Vector3 = (
				(
					outward
					+ Vector3(_rng.randf_range(-0.6, 0.6), _rng.randf_range(-0.6, 0.6), _rng.randf_range(-0.6, 0.6))
				)
				. normalized()
			)
			if _rng.randf() < 0.25:
				normal = unit()
			var basis := Basis(Quaternion(Vector3.BACK, normal)).rotated(normal, _rng.randf() * TAU)
			var size: float = card_size * _rng.randf_range(0.75, 1.25)
			var points := [Vector3(-0.5, -0.5, 0), Vector3(0.5, -0.5, 0), Vector3(0.5, 0.5, 0), Vector3(-0.5, 0.5, 0)]
			var uvs := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
			var weights: Array[float] = []
			for corner in range(4):
				weights.append(clampf((p.y - sway_base) / (sway_top - sway_base), 0, 1) * _rng.randf_range(0.6, 1))
			for k in [0, 2, 1, 0, 3, 2]:
				var vertex: Vector3 = p + basis * points[k] * size
				st.set_uv(uvs[k])
				st.set_normal(outward.lerp(((vertex - center) / (radii * radii)).normalized(), 0.35).normalized())
				color.a = weights[k]
				st.set_color(color)
				st.add_vertex(vertex)
	return st.commit()


func tapered_branch(st: SurfaceTool, start: Vector3, end: Vector3, radius: float, tip: float, segments: int) -> void:
	var direction: Vector3 = (end - start).normalized()
	var side: Vector3 = direction.cross(Vector3.FORWARD).normalized()
	if side.length() < 0.1:
		side = Vector3.RIGHT
	var other: Vector3 = direction.cross(side).normalized()
	for i in range(segments):
		var a: float = float(i) / segments * TAU
		var b: float = float(i + 1) / segments * TAU
		var radial_a: Vector3 = side * cos(a) + other * sin(a)
		var radial_b: Vector3 = side * cos(b) + other * sin(b)
		var points := [start + radial_a * radius, start + radial_b * radius, end + radial_b * tip, end + radial_a * tip]
		for k in [0, 2, 1, 0, 3, 2]:
			st.set_uv(Vector2(float(i) / segments, 0 if k < 2 else 1))
			st.add_vertex(points[k])


func grass_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for blade in range(3):
		var angle: float = blade * TAU / 3 + _rng.randf() * 0.8
		var basis := Basis(Vector3.UP, angle)
		var width: float = _rng.randf_range(0.1, 0.15)
		var bend: float = _rng.randf_range(0.2, 0.6)
		var offset := Vector3(_rng.randf_range(-0.06, 0.06), 0, _rng.randf_range(-0.06, 0.06))
		for segment in range(4):
			for k in [0, 2, 1, 1, 2, 3]:
				var t: float = float(segment + k / 2) / 4
				var sign_x: float = -1 if k % 2 == 0 else 1
				st.set_uv(Vector2(0 if sign_x < 0 else 1, t))
				st.set_normal(basis * Vector3(0, 0.3, 1).normalized())
				st.set_color(Color.WHITE)
				st.add_vertex(offset + basis * Vector3(sign_x * width * (1 - t * t) * 0.5, t, bend * t * t))
	return st.commit()


func pine_tier(center: Vector3, radius: float, tree_height: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(ceili(radius * radius * 7) + 12):
		var angle: float = _rng.randf() * TAU
		var distance: float = sqrt(_rng.randf()) * radius
		var fraction: float = distance / radius
		var p := (
			center
			+ Vector3(
				cos(angle) * distance,
				0.14 * radius * (1 - fraction * fraction) + _rng.randf_range(-0.2, 0.2),
				sin(angle) * distance
			)
		)
		var size: float = _rng.randf_range(1, 1.5)
		var pitch: float = 0.35 + fraction * 0.55 + _rng.randf_range(-0.2, 0.2)
		var basis := (
			Basis(Vector3.UP, PI * 0.5 - angle)
			* Basis(Vector3.RIGHT, -(PI * 0.5 - pitch))
			* Basis(Vector3.BACK, _rng.randf_range(-0.4, 0.4))
		)
		var normal := Vector3(cos(angle) * 0.6, 1, sin(angle) * 0.6).normalized()
		var shade: float = _rng.randf_range(0.72, 1.12) * (0.78 + 0.22 * fraction)
		var color := Color(shade * 0.9, shade, shade * 0.95, 0.3 + center.y / tree_height * 0.35 + 0.25 * fraction)
		for k in [0, 2, 1, 0, 3, 2]:
			var uv: Vector2 = [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)][k]
			st.set_uv(uv)
			st.set_normal(normal)
			st.set_color(color)
			st.add_vertex(p + basis * Vector3((uv.x - 0.5) * size, (0.5 - uv.y) * size * 0.8, 0))
	return st.commit()
