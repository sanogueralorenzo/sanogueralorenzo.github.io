class_name EnemyAgent
extends Node3D

signal defeated(enemy: EnemyAgent, experience_value: int)

const CONTACT_DISTANCE_PADDING := 1.8
const HEIGHT_SMOOTHING := 12.0

var target: CharacterBody3D
var world: Node3D
var archetype := &"pursuer"
var health := 20.0
var maximum_health := 20.0
var movement_speed := 52.0
var contact_damage := 10.0
var experience_value := 3
var body_radius := 2.2

var _attack_cooldown := 0.0
var _hit_flash := 0.0
var _body_material: StandardMaterial3D
var _body_mesh: MeshInstance3D
var _core_mesh: MeshInstance3D


func configure(
	new_target: CharacterBody3D,
	new_world: Node3D,
	new_archetype: StringName,
	difficulty: float
) -> void:
	target = new_target
	world = new_world
	archetype = new_archetype
	match archetype:
		&"skimmer":
			maximum_health = 12.0 * difficulty
			movement_speed = 76.0 + difficulty * 2.0
			contact_damage = 7.0 * sqrt(difficulty)
			experience_value = 2
			body_radius = 1.55
		&"bulwark":
			maximum_health = 58.0 * difficulty
			movement_speed = 39.0 + difficulty
			contact_damage = 18.0 * sqrt(difficulty)
			experience_value = 7
			body_radius = 3.5
		_:
			maximum_health = 24.0 * difficulty
			movement_speed = 56.0 + difficulty * 1.5
			contact_damage = 10.0 * sqrt(difficulty)
			experience_value = 3
			body_radius = 2.2
	health = maximum_health
	_build_visuals()


func _physics_process(delta: float) -> void:
	if not is_instance_valid(target) or not is_instance_valid(world):
		return
	_attack_cooldown = maxf(0.0, _attack_cooldown - delta)
	_hit_flash = maxf(0.0, _hit_flash - delta)
	_update_material()

	var offset := target.global_position - global_position
	var planar_offset := Vector3(offset.x, 0.0, offset.z)
	var distance := planar_offset.length()
	if distance > 0.01:
		var direction := planar_offset / distance
		global_position += direction * movement_speed * delta
		_body_mesh.rotation.y += delta * (3.8 if archetype == &"skimmer" else 1.8)

	var desired_height: float = world.get_surface_height(global_position.x, global_position.z) + body_radius * 0.72
	global_position.y = lerpf(global_position.y, desired_height, 1.0 - exp(-HEIGHT_SMOOTHING * delta))
	if distance <= body_radius + CONTACT_DISTANCE_PADDING and _attack_cooldown <= 0.0:
		target.take_damage(contact_damage)
		_attack_cooldown = 0.85 if archetype != &"skimmer" else 1.15


func take_damage(amount: float) -> void:
	if amount <= 0.0 or health <= 0.0:
		return
	health -= amount
	_hit_flash = 0.09
	if health <= 0.0:
		defeated.emit(self, experience_value)
		queue_free()


func _build_visuals() -> void:
	_body_material = StandardMaterial3D.new()
	_body_material.metallic = 0.35
	_body_material.roughness = 0.28
	_body_material.emission_enabled = true

	_body_mesh = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = body_radius
	sphere.height = body_radius * 2.0
	sphere.radial_segments = 16
	sphere.rings = 8
	_body_mesh.mesh = sphere
	_body_mesh.material_override = _body_material
	if archetype == &"skimmer":
		_body_mesh.scale = Vector3(1.0, 0.52, 1.45)
	elif archetype == &"bulwark":
		_body_mesh.scale = Vector3(1.2, 0.85, 1.2)
	add_child(_body_mesh)

	_core_mesh = MeshInstance3D.new()
	var core := SphereMesh.new()
	core.radius = body_radius * 0.38
	core.height = body_radius * 0.76
	core.radial_segments = 12
	core.rings = 6
	_core_mesh.mesh = core
	var core_material := StandardMaterial3D.new()
	core_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	core_material.albedo_color = Color(1.0, 0.82, 0.18)
	core_material.emission_enabled = true
	core_material.emission = Color(1.0, 0.28, 0.025)
	core_material.emission_energy_multiplier = 4.0
	_core_mesh.material_override = core_material
	add_child(_core_mesh)
	_update_material()


func _update_material() -> void:
	if not is_instance_valid(_body_material):
		return
	var base_color := Color(0.75, 0.04, 0.22)
	if archetype == &"skimmer":
		base_color = Color(0.78, 0.08, 0.72)
	elif archetype == &"bulwark":
		base_color = Color(0.92, 0.22, 0.035)
	if _hit_flash > 0.0:
		base_color = Color(1.0, 0.95, 0.65)
	_body_material.albedo_color = base_color
	_body_material.emission = base_color * 0.72
	_body_material.emission_energy_multiplier = 2.8 if _hit_flash > 0.0 else 1.2
