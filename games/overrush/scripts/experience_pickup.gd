class_name ExperiencePickup
extends Node3D

signal collected(value: int)
signal integrity_collected(value: float)

const EXPERIENCE := &"experience"
const INTEGRITY := &"integrity"

const COLLECTION_RADIUS := 3.2
const MAGNET_BASE_SPEED := 96.0
const MAGNET_SPEED_MARGIN := 72.0
const RECOVERY_DELAY := 8.0
const RECOVERY_DISTANCE_ACCELERATION := 0.35
const RECOVERY_SPEED_BONUS_LIMIT := 260.0

var target: CharacterBody3D
var value := 1
var magnet_radius := 30.0
var pickup_kind: StringName = EXPERIENCE
var _phase := 0.0
var _age := 0.0
var _hover_origin_y := 0.0
var _magnetized := false
var _collected := false


func configure(
	new_target: CharacterBody3D,
	new_value: int,
	new_magnet_radius: float,
	new_pickup_kind: StringName = EXPERIENCE
) -> void:
	target = new_target
	value = maxi(1, new_value)
	magnet_radius = new_magnet_radius
	pickup_kind = new_pickup_kind if new_pickup_kind in [EXPERIENCE, INTEGRITY] else EXPERIENCE
	_hover_origin_y = global_position.y
	_build_visual()


func _physics_process(delta: float) -> void:
	if not is_instance_valid(target):
		return
	_age += delta
	_phase += delta
	rotation.y += delta * 3.2
	var offset := target.global_position - global_position
	var distance := offset.length()
	if pickup_kind == INTEGRITY and not _target_needs_integrity():
		_magnetized = false
		global_position.y = _hover_origin_y + sin(_phase * 3.2) * 0.18
		return
	if distance <= COLLECTION_RADIUS:
		_collect()
		return
	if not _magnetized and (distance <= magnet_radius or _age >= RECOVERY_DELAY):
		_magnetized = true
	if not _magnetized:
		global_position.y = _hover_origin_y + sin(_phase * 4.0) * 0.14
		return
	var target_speed := Vector2(target.velocity.x, target.velocity.z).length()
	var pursuit_speed := maxf(MAGNET_BASE_SPEED, target_speed + MAGNET_SPEED_MARGIN)
	if _age >= RECOVERY_DELAY:
		pursuit_speed += minf(distance * RECOVERY_DISTANCE_ACCELERATION, RECOVERY_SPEED_BONUS_LIMIT)
	var travel_distance := pursuit_speed * delta
	if travel_distance + COLLECTION_RADIUS >= distance:
		_collect()
		return
	global_position += offset / distance * travel_distance


func is_magnetized() -> bool:
	return _magnetized


func get_visual_tier() -> int:
	if pickup_kind == INTEGRITY:
		return 0
	if value >= 15:
		return 2
	if value >= 5:
		return 1
	return 0


func is_integrity_pickup() -> bool:
	return pickup_kind == INTEGRITY


func _collect() -> void:
	if _collected:
		return
	if pickup_kind == INTEGRITY and not _target_needs_integrity():
		return
	_collected = true
	if pickup_kind == INTEGRITY:
		integrity_collected.emit(float(value))
	else:
		collected.emit(value)
	queue_free()


func _target_needs_integrity() -> bool:
	if not is_instance_valid(target) or not target.has_method("repair_integrity"):
		return true
	return float(target.get("integrity")) < float(target.get("maximum_integrity")) - 0.01


func _build_visual() -> void:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = _create_crystal_mesh()
	var tier := get_visual_tier()
	var tier_scale: float = [1.0, 1.22, 1.48][tier]
	mesh_instance.scale = (Vector3(1.02, 0.92, 1.02) if pickup_kind == INTEGRITY else Vector3(0.72, 1.2, 0.72)) * tier_scale
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var tier_colors: Array[Color] = [
		Color(0.18, 1.0, 0.46),
		Color(0.08, 0.88, 1.0),
		Color(1.0, 0.72, 0.1),
	]
	var pickup_color := Color(1.0, 0.16, 0.42) if pickup_kind == INTEGRITY else tier_colors[tier]
	material.albedo_color = pickup_color
	material.emission_enabled = true
	material.emission = pickup_color * 0.88
	material.emission_energy_multiplier = 4.6
	mesh_instance.material_override = material
	add_child(mesh_instance)
	var ring_count := 2 if pickup_kind == INTEGRITY else tier + 1
	for ring_index in range(ring_count):
		var ring := MeshInstance3D.new()
		var ring_mesh := TorusMesh.new()
		ring_mesh.inner_radius = 0.82 + ring_index * 0.18
		ring_mesh.outer_radius = 0.94 + ring_index * 0.18
		ring_mesh.rings = 18
		ring_mesh.ring_segments = 6
		ring.mesh = ring_mesh
		ring.rotation_degrees = Vector3(18.0 + ring_index * 42.0, ring_index * 31.0, 0.0)
		ring.material_override = material
		add_child(ring)
	if pickup_kind == INTEGRITY:
		_add_integrity_satellites(material)


func _add_integrity_satellites(material: StandardMaterial3D) -> void:
	for direction in [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK]:
		var satellite := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.22
		sphere.height = 0.44
		sphere.radial_segments = 10
		sphere.rings = 6
		satellite.mesh = sphere
		satellite.position = direction * 1.18
		satellite.material_override = material
		add_child(satellite)


func _create_crystal_mesh() -> ArrayMesh:
	const SIDES := 6
	var vertices := PackedVector3Array()
	var top := Vector3(0.0, 0.95, 0.0)
	var bottom := Vector3(0.0, -0.95, 0.0)
	for side_index in range(SIDES):
		var angle := TAU * float(side_index) / float(SIDES)
		var next_angle := TAU * float(side_index + 1) / float(SIDES)
		var current := Vector3(cos(angle) * 0.72, 0.0, sin(angle) * 0.72)
		var next := Vector3(cos(next_angle) * 0.72, 0.0, sin(next_angle) * 0.72)
		vertices.append_array(PackedVector3Array([top, current, next, bottom, next, current]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
