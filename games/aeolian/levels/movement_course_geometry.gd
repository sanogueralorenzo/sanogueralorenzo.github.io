class_name MovementCourseGeometry
extends Node3D

const COURSE_END_D := 486.0
const FINISH_TRIGGER_D := 483.0
const FINISH_MIN_X := 2.0
const FINISH_MAX_X := 14.0
const GAP_START_D := 316.0
const GAP_END_D := 324.0
const CROSS_INTERVALS := 16

var snow_material := StandardMaterial3D.new()
var marker_material := StandardMaterial3D.new()
var hazard_material := StandardMaterial3D.new()
var finish_material := StandardMaterial3D.new()


func _ready() -> void:
	snow_material.albedo_color = Color(0.72, 0.84, 0.9)
	snow_material.roughness = 0.82
	snow_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	marker_material.albedo_color = Color(0.96, 0.38, 0.12)
	marker_material.roughness = 0.65
	hazard_material.albedo_color = Color(0.88, 0.08, 0.04)
	hazard_material.emission_enabled = true
	hazard_material.emission = Color(0.4, 0.015, 0.005)
	finish_material.albedo_color = Color(0.12, 0.84, 0.72)
	finish_material.roughness = 0.4
	finish_material.emission_enabled = true
	finish_material.emission = Color(0.015, 0.34, 0.24)
	_build_surface(&"UpperCourse", _upper_rows())
	_build_surface(&"LowerCourse", _lower_rows())
	_build_station_markers()
	_build_fatal_wall()
	_build_finish_gate()


func surface_height(x: float, d: float) -> float:
	var y := _center_height(d) + x * tan(_bank_roll_radians(d))
	if d >= 238.0 and d <= 286.0:
		var u := d - 238.0
		var fade := _smoothstep(0.0, 4.0, u) * (1.0 - _smoothstep(44.0, 48.0, u))
		y += 0.10 * fade * sin(TAU * u / 14.0) \
			* (0.70 + 0.30 * cos(TAU * x / 8.0))
	if d >= 463.0 and d <= 466.0:
		var along := sin(PI * inverse_lerp(463.0, 466.0, d))
		var across := 1.0 - _smoothstep(1.0, 1.5, absf(x))
		y += 0.18 * along * along * across
	return y


func surface_normal(x: float, d: float) -> Vector3:
	var epsilon := 0.05
	var dy_dx := (surface_height(x + epsilon, d) - surface_height(x - epsilon, d)) \
		/ (2.0 * epsilon)
	var dy_dd := (surface_height(x, d + epsilon) - surface_height(x, d - epsilon)) \
		/ (2.0 * epsilon)
	return Vector3(-dy_dx, 1.0, dy_dd).normalized()


func surface_transform(x: float, d: float, support_height := 0.86) -> Transform3D:
	var normal := surface_normal(x, d)
	var forward := Vector3(0.0, -normal.z, -normal.y).slide(normal).normalized()
	if forward.dot(Vector3.FORWARD) < 0.0:
		forward = -forward
	var right := forward.cross(normal).normalized()
	var basis := Basis(right, normal, -forward).orthonormalized()
	return Transform3D(basis, Vector3(x, surface_height(x, d), -d) + normal * support_height)


func half_width(d: float) -> float:
	if d <= 306.0:
		return 12.0
	if d < GAP_END_D:
		return lerpf(12.0, 15.0, _smoothstep(306.0, GAP_END_D, d))
	return 15.0


func _build_surface(node_name: StringName, rows: PackedFloat32Array) -> void:
	var surface_tool := SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface_tool.set_material(snow_material)
	for row_index in rows.size() - 1:
		var d0 := float(rows[row_index])
		var d1 := float(rows[row_index + 1])
		for column in CROSS_INTERVALS:
			var t0 := float(column) / float(CROSS_INTERVALS)
			var t1 := float(column + 1) / float(CROSS_INTERVALS)
			var a := _surface_vertex(lerpf(-half_width(d0), half_width(d0), t0), d0)
			var b := _surface_vertex(lerpf(-half_width(d0), half_width(d0), t1), d0)
			var c := _surface_vertex(lerpf(-half_width(d1), half_width(d1), t0), d1)
			var next := _surface_vertex(lerpf(-half_width(d1), half_width(d1), t1), d1)
			_add_triangle(surface_tool, a, b, c)
			_add_triangle(surface_tool, b, next, c)
	surface_tool.generate_normals()
	var mesh := surface_tool.commit()
	var body := StaticBody3D.new()
	body.name = node_name
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Mesh"
	mesh_instance.mesh = mesh
	body.add_child(mesh_instance)
	var collision := CollisionShape3D.new()
	collision.name = "Collision"
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.data = mesh.get_faces()
	collision.shape = shape
	body.add_child(collision)


func _surface_vertex(x: float, d: float) -> Vector3:
	return Vector3(x, surface_height(x, d), -d)


func _add_triangle(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	tool.add_vertex(a)
	tool.add_vertex(b)
	tool.add_vertex(c)


func _upper_rows() -> PackedFloat32Array:
	var rows := PackedFloat32Array()
	_append_range(rows, 0.0, 72.0, 1.0)
	_append_range(rows, 72.0, 96.0, 0.5)
	_append_range(rows, 96.0, 142.0, 1.0)
	_append_range(rows, 142.0, 286.0, 0.5)
	_append_range(rows, 286.0, 306.0, 0.5)
	_append_range(rows, 306.0, GAP_START_D, 0.25)
	return rows


func _lower_rows() -> PackedFloat32Array:
	var rows := PackedFloat32Array()
	_append_range(rows, GAP_END_D, 370.0, 0.5)
	_append_range(rows, 370.0, 450.0, 1.0)
	_append_range(rows, 450.0, COURSE_END_D, 0.25)
	return rows


func _append_range(rows: PackedFloat32Array, start: float, finish: float, step: float) -> void:
	if rows.is_empty() or not is_equal_approx(rows[rows.size() - 1], start):
		rows.append(start)
	var value := start + step
	while value < finish - 0.0001:
		rows.append(value)
		value += step
	if not is_equal_approx(rows[rows.size() - 1], finish):
		rows.append(finish)


func _center_height(d: float) -> float:
	var y12 := 45.0
	var y72 := y12 - 60.0 * tan(deg_to_rad(8.0))
	var y96 := y72 + 24.0 * (-tan(deg_to_rad(8.0)) - tan(deg_to_rad(24.0))) * 0.5
	var y142 := y96 - 46.0 * tan(deg_to_rad(24.0))
	var y158 := y142 + 16.0 * (-tan(deg_to_rad(24.0)) - tan(deg_to_rad(12.0))) * 0.5
	var y238 := y158 - 80.0 * tan(deg_to_rad(12.0))
	var y286 := y238 - 48.0 * tan(deg_to_rad(10.0))
	var y306 := y286 - 20.0 * tan(deg_to_rad(14.0))
	var y316 := y306 + 10.0 * (-tan(deg_to_rad(14.0)) + tan(deg_to_rad(6.0))) * 0.5
	var y324 := y316 - 0.82
	var y370 := y324 - 46.0 * tan(deg_to_rad(16.0))
	var y450 := y370 - 80.0 * tan(deg_to_rad(22.0))
	if d <= 12.0:
		return y12
	if d <= 72.0:
		return y12 - (d - 12.0) * tan(deg_to_rad(8.0))
	if d <= 96.0:
		return _hermite(d, 72.0, 96.0, y72, y96, -tan(deg_to_rad(8.0)), -tan(deg_to_rad(24.0)))
	if d <= 142.0:
		return y96 - (d - 96.0) * tan(deg_to_rad(24.0))
	if d <= 158.0:
		return _hermite(d, 142.0, 158.0, y142, y158, -tan(deg_to_rad(24.0)), -tan(deg_to_rad(12.0)))
	if d <= 238.0:
		return y158 - (d - 158.0) * tan(deg_to_rad(12.0))
	if d <= 286.0:
		return y238 - (d - 238.0) * tan(deg_to_rad(10.0))
	if d <= 306.0:
		return y286 - (d - 286.0) * tan(deg_to_rad(14.0))
	if d <= GAP_START_D:
		return _hermite(d, 306.0, GAP_START_D, y306, y316, -tan(deg_to_rad(14.0)), tan(deg_to_rad(6.0)))
	if d < GAP_END_D:
		return lerpf(y316, y324, inverse_lerp(GAP_START_D, GAP_END_D, d))
	if d <= 370.0:
		return y324 - (d - GAP_END_D) * tan(deg_to_rad(16.0))
	if d <= 450.0:
		return y370 - (d - 370.0) * tan(deg_to_rad(22.0))
	return y450 - (d - 450.0) * tan(deg_to_rad(6.0))


func _bank_roll_radians(d: float) -> float:
	var stations := PackedFloat32Array([158.0, 168.0, 183.0, 203.0, 218.0, 228.0, 238.0])
	var degrees := PackedFloat32Array([0.0, 18.0, 18.0, -18.0, -18.0, 0.0, 0.0])
	if d <= stations[0] or d >= stations[stations.size() - 1]:
		return 0.0
	for index in stations.size() - 1:
		if d <= stations[index + 1]:
			var amount := _smoothstep(stations[index], stations[index + 1], d)
			return deg_to_rad(lerpf(degrees[index], degrees[index + 1], amount))
	return 0.0


func _hermite(value: float, start: float, finish: float, start_height: float, finish_height: float, start_derivative: float, finish_derivative: float) -> float:
	var length := finish - start
	var t := clampf((value - start) / length, 0.0, 1.0)
	var t2 := t * t
	var t3 := t2 * t
	return (2.0 * t3 - 3.0 * t2 + 1.0) * start_height \
		+ (t3 - 2.0 * t2 + t) * length * start_derivative \
		+ (-2.0 * t3 + 3.0 * t2) * finish_height \
		+ (t3 - t2) * length * finish_derivative


func _smoothstep(edge0: float, edge1: float, value: float) -> float:
	var t := clampf(inverse_lerp(edge0, edge1, value), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


func _build_station_markers() -> void:
	var stations := PackedFloat32Array([12.0, 72.0, 96.0, 142.0, 158.0, 238.0, 286.0, 306.0, 324.0, 370.0, 450.0])
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.06
	mesh.bottom_radius = 0.14
	mesh.height = 2.4
	mesh.material = marker_material
	for station: float in stations:
		for side: float in [-1.0, 1.0]:
			var marker := MeshInstance3D.new()
			marker.mesh = mesh
			var x: float = side * (half_width(station) - 0.65)
			marker.position = Vector3(x, surface_height(x, station) + 1.2, -station)
			add_child(marker)


func _build_fatal_wall() -> void:
	var body := StaticBody3D.new()
	body.name = "FatalWall"
	body.position = Vector3(-7.0, surface_height(-7.0, 477.0) + 1.25, -477.0)
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)
	var size := Vector3(6.0, 2.5, 1.0)
	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = hazard_material
	mesh_instance.mesh = mesh
	body.add_child(mesh_instance)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)


func _build_finish_gate() -> void:
	var gate := Node3D.new()
	gate.name = "FinishGate"
	add_child(gate)
	var gate_d := FINISH_TRIGGER_D
	var gate_center_x := (FINISH_MIN_X + FINISH_MAX_X) * 0.5
	var gate_width := FINISH_MAX_X - FINISH_MIN_X
	var gate_y := surface_height(gate_center_x, gate_d)
	for x: float in [FINISH_MIN_X, FINISH_MAX_X]:
		var post := MeshInstance3D.new()
		var post_mesh := BoxMesh.new()
		post_mesh.size = Vector3(0.24, 3.5, 0.24)
		post_mesh.material = finish_material
		post.mesh = post_mesh
		post.position = Vector3(x, surface_height(x, gate_d) + 1.75, -gate_d)
		gate.add_child(post)
	var crossbar := MeshInstance3D.new()
	var crossbar_mesh := BoxMesh.new()
	crossbar_mesh.size = Vector3(gate_width + 0.24, 0.24, 0.24)
	crossbar_mesh.material = finish_material
	crossbar.mesh = crossbar_mesh
	crossbar.position = Vector3(gate_center_x, gate_y + 3.38, -gate_d)
	gate.add_child(crossbar)
	var finish_strip := MeshInstance3D.new()
	var strip_mesh := BoxMesh.new()
	strip_mesh.size = Vector3(gate_width, 0.025, 0.55)
	strip_mesh.material = finish_material
	finish_strip.mesh = strip_mesh
	finish_strip.position = Vector3(gate_center_x, gate_y + 0.025, -gate_d)
	gate.add_child(finish_strip)
