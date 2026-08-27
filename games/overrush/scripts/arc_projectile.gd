class_name ArcProjectile
extends Node3D

const SPEED := 145.0
const HIT_RADIUS := 3.4
const MAX_LIFETIME := 1.15
const TURN_RESPONSE := 14.0

var target: EnemyAgent
var damage := 10.0
var _lifetime := MAX_LIFETIME
var _direction := Vector3.FORWARD


func configure(new_target: EnemyAgent, new_damage: float, initial_direction: Vector3) -> void:
	target = new_target
	damage = new_damage
	_direction = initial_direction.normalized()
	_build_visual()


func _physics_process(delta: float) -> void:
	_lifetime -= delta
	if _lifetime <= 0.0 or not is_instance_valid(target):
		queue_free()
		return
	var to_target := target.global_position - global_position
	if to_target.length() <= HIT_RADIUS:
		target.take_damage(damage)
		queue_free()
		return
	var desired_direction := to_target.normalized()
	_direction = _direction.slerp(desired_direction, 1.0 - exp(-TURN_RESPONSE * delta)).normalized()
	global_position += _direction * SPEED * delta


func _build_visual() -> void:
	var mesh_instance := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.52
	mesh.height = 1.04
	mesh.radial_segments = 12
	mesh.rings = 6
	mesh_instance.mesh = mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.18, 0.95, 1.0)
	material.emission_enabled = true
	material.emission = Color(0.02, 0.72, 1.0)
	material.emission_energy_multiplier = 5.0
	mesh_instance.material_override = material
	add_child(mesh_instance)
	var light := OmniLight3D.new()
	light.light_color = Color(0.06, 0.75, 1.0)
	light.light_energy = 2.2
	light.omni_range = 6.0
	add_child(light)
