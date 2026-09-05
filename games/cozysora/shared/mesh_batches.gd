class_name CozyMeshBatches
extends RefCounted
## Spatial cells preserve insertion order and rebase transforms for local bounds.


static func cells(transforms: Array, cell_size: float) -> Dictionary:
	var result: Dictionary = {}
	for transform: Transform3D in transforms:
		var cell := Vector2i(floori(transform.origin.x / cell_size), floori(transform.origin.z / cell_size))
		if not result.has(cell):
			result[cell] = []
		result[cell].append(transform)
	return result


static func instances(
	parent: Node3D,
	mesh: Mesh,
	material: Material,
	transforms: Array,
	origin: Vector3,
	label: String,
	range_end: float = 0,
	margin: float = 0,
	shadows: int = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
) -> MultiMeshInstance3D:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = transforms.size()
	for i in transforms.size():
		var transform: Transform3D = transforms[i]
		transform.origin -= origin
		multimesh.set_instance_transform(i, transform)
	var node := MultiMeshInstance3D.new()
	node.name = label
	node.multimesh = multimesh
	node.material_override = material
	node.position = origin
	node.visibility_range_end = range_end
	node.visibility_range_end_margin = margin
	node.cast_shadow = shadows
	parent.add_child(node)
	return node


static func spatial(
	parent: Node3D,
	mesh: Mesh,
	material: Material,
	transforms: Array,
	label: String,
	cell_size: float,
	range_end: float = 0,
	margin: float = 0,
	shadows: int = GeometryInstance3D.SHADOW_CASTING_SETTING_ON,
	shadow_range: float = 0,
	shadow_margin: float = 0
) -> int:
	var groups := cells(transforms, cell_size)
	for cell: Vector2i in groups:
		var origin := Vector3(cell.x * cell_size + cell_size / 2, 0, cell.y * cell_size + cell_size / 2)
		var node := instances(parent, mesh, material, groups[cell], origin, label, range_end, margin, shadows)
		if shadow_range > 0:
			var shadow := MultiMeshInstance3D.new()
			shadow.name = "Nearby grass shadows"
			shadow.multimesh = node.multimesh
			shadow.material_override = material
			shadow.position = origin
			shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
			shadow.visibility_range_end = shadow_range
			shadow.visibility_range_end_margin = shadow_margin
			parent.add_child(shadow)
	return groups.size()


static func merge_static(parent: Node3D, excluded: Array, cell_size: float = 32) -> void:
	var buckets: Dictionary = {}
	_collect_static(parent, Transform3D.IDENTITY, excluded, cell_size, buckets)
	for entry: Dictionary in buckets.values():
		var node := MeshInstance3D.new()
		node.name = "SettlementBatch"
		var surface: SurfaceTool = entry.surface
		node.mesh = surface.commit()
		node.material_override = entry.material
		parent.add_child(node)


static func _collect_static(
	node: Node3D, relative: Transform3D, excluded: Array, cell_size: float, buckets: Dictionary
) -> void:
	for child: Node in node.get_children():
		if not child is Node3D or excluded.has(child):
			continue
		var transform: Transform3D = relative * child.transform
		if child is MeshInstance3D and child.mesh != null:
			var material: Material = child.material_override
			if material == null:
				continue
			var cell := Vector2i(floori(transform.origin.x / cell_size), floori(transform.origin.z / cell_size))
			var key := str(material.get_instance_id()) + ":" + str(cell)
			if not buckets.has(key):
				var surface := SurfaceTool.new()
				surface.begin(Mesh.PRIMITIVE_TRIANGLES)
				buckets[key] = {"surface": surface, "material": material}
			var surface: SurfaceTool = buckets[key].surface
			for i in child.mesh.get_surface_count():
				surface.append_from(child.mesh, i, transform)
			# Collision shapes are siblings; labels and animation roots are retained.
			child.queue_free()
		else:
			_collect_static(child, transform, excluded, cell_size, buckets)
