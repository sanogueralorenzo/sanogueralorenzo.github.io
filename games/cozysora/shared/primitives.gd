class_name CozyPrimitives
extends RefCounted
## Geometry resources and instances. Dimensions and tessellation belong to callers.


static func box_mesh(size: Vector3 = Vector3.ONE) -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = size
	return mesh


static func cylinder_mesh(bottom: float, top: float, height: float, segments: int = 10) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.bottom_radius = bottom
	mesh.top_radius = top
	mesh.height = height
	mesh.radial_segments = segments
	return mesh


static func sphere_mesh(radius: float = 0.5, height: float = 1.0, segments: int = 10, rings: int = 5) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = height
	mesh.radial_segments = segments
	mesh.rings = rings
	return mesh


static func instance(
	parent: Node3D, mesh: Mesh, position: Vector3, material: Material, size: Vector3 = Vector3.ONE
) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material
	node.position = position
	node.scale = size
	parent.add_child(node)
	return node


static func box(
	parent: Node3D, position: Vector3, size: Vector3, material: Material, solid: bool = false
) -> MeshInstance3D:
	var node := instance(parent, box_mesh(size), position, material)
	if solid:
		CozyCollision.static_box(parent, position, size)
	return node


static func cylinder(
	parent: Node3D, position: Vector3, bottom: float, top: float, height: float, material: Material
) -> MeshInstance3D:
	return instance(parent, cylinder_mesh(bottom, top, height), position, material)


static func sphere(parent: Node3D, position: Vector3, size: Vector3, material: Material) -> MeshInstance3D:
	return instance(parent, sphere_mesh(1, 2), position, material, size)


static func beam(parent: Node3D, start: Vector3, end: Vector3, radius: float, material: Material) -> MeshInstance3D:
	var node := cylinder(parent, (start + end) / 2, radius, radius, start.distance_to(end), material)
	node.quaternion = Quaternion(Vector3.UP, (end - start).normalized())
	return node
