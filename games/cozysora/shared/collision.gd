class_name CozyCollision
extends RefCounted
## Shapes may belong to a shared static/animatable body or an individual prop.


static func box(
	body: PhysicsBody3D, position: Vector3, size: Vector3, rotation: Vector3 = Vector3.ZERO
) -> CollisionShape3D:
	var shape := CollisionShape3D.new()
	var primitive := BoxShape3D.new()
	primitive.size = size
	shape.shape = primitive
	shape.position = position
	shape.rotation = rotation
	body.add_child(shape)
	return shape


static func static_box(parent: Node3D, position: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = position
	box(body, Vector3.ZERO, size)
	parent.add_child(body)
	return body


static func mesh(body: PhysicsBody3D, geometry: Mesh) -> CollisionShape3D:
	var shape := CollisionShape3D.new()
	shape.shape = geometry.create_trimesh_shape()
	body.add_child(shape)
	return shape
