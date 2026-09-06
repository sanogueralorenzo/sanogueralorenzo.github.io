extends MeshInstance3D
## Sloping sea floor with no visible slab edge inside the boating area.
func build(region: int) -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var width := 80
	var rows := 85
	var step := 5.0
	for z in range(rows):
		for x in range(width):
			var origin := Vector2((x - width / 2.0) * step, (z - 8) * step)
			var a := _point(origin)
			var b := _point(origin + Vector2(step, 0))
			var c := _point(origin + Vector2(0, step))
			var d := _point(origin + Vector2(step, step))
			for point: Vector3 in [a, b, c, b, d, c]:
				surface.set_normal(Vector3.UP)
				surface.add_vertex(point)
	mesh = surface.commit()
	var material := ShaderMaterial.new()
	material.shader = load("res://shaders/seabed.gdshader")
	if region == 1:
		material.set_shader_parameter("sand", Color("708a66"))
		material.set_shader_parameter("depths", Color("103b43"))
	elif region == 2:
		material.set_shader_parameter("sand", Color("758177"))
		material.set_shader_parameter("depths", Color("102e43"))
	material_override = material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _point(p: Vector2) -> Vector3:
	var offshore := maxf(0.0, p.y + sin(p.x * .18) * 2.5)
	var depth := 1.1 + minf(17.0, pow(offshore * .13, 1.3))
	var relief := sin(p.x * .61 + p.y * .24) * sin(p.y * .47) * .18
	return Vector3(p.x, -depth + relief, p.y)
