class_name ExperiencePickup
extends Node3D

signal collected(value: int)

const COLLECTION_RADIUS := 3.2
const MAGNET_SPEED := 82.0

var target: CharacterBody3D
var value := 1
var magnet_radius := 30.0
var _phase := 0.0


func configure(new_target: CharacterBody3D, new_value: int, new_magnet_radius: float) -> void:
	target = new_target
	value = new_value
	magnet_radius = new_magnet_radius
	_build_visual()


func _physics_process(delta: float) -> void:
	if not is_instance_valid(target):
		return
	_phase += delta
	rotation.y += delta * 3.2
	var offset := target.global_position - global_position
	var distance := offset.length()
	if distance <= COLLECTION_RADIUS:
		collected.emit(value)
		queue_free()
		return
	if distance <= magnet_radius:
		var pull_strength := lerpf(0.35, 1.0, 1.0 - distance / magnet_radius)
		global_position += offset.normalized() * MAGNET_SPEED * pull_strength * delta
	else:
		global_position.y += sin(_phase * 4.0) * 0.006


func _build_visual() -> void:
	var mesh_instance := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.72
	mesh.height = 1.44
	mesh.radial_segments = 10
	mesh.rings = 5
	mesh_instance.mesh = mesh
	mesh_instance.scale = Vector3(0.7, 1.25, 0.7)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.2, 1.0, 0.48)
	material.emission_enabled = true
	material.emission = Color(0.05, 0.9, 0.25)
	material.emission_energy_multiplier = 4.0
	mesh_instance.material_override = material
	add_child(mesh_instance)
