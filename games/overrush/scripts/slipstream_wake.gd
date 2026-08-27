class_name SlipstreamWake
extends Node3D

const DAMAGE_SCAN_INTERVAL := 0.1
const WakeShader = preload("res://shaders/slipstream_wake.gdshader")

var radius := 10.0
var damage := 8.0
var lifetime := 1.5

var _total_lifetime := 1.5
var _scan_timer := 0.0
var _hit_enemy_ids: Dictionary = {}
var _disc: MeshInstance3D


func configure(new_radius: float, new_damage: float, new_lifetime: float) -> void:
	radius = new_radius
	damage = new_damage
	lifetime = new_lifetime
	_total_lifetime = new_lifetime
	_build_visual()


func _physics_process(delta: float) -> void:
	lifetime -= delta
	if lifetime <= 0.0:
		queue_free()
		return
	_scan_timer -= delta
	if _scan_timer <= 0.0:
		_scan_timer = DAMAGE_SCAN_INTERVAL
		_damage_new_crossings()
	var life_ratio := clampf(lifetime / maxf(_total_lifetime, 0.001), 0.0, 1.0)
	_disc.transparency = 1.0 - minf(0.22, life_ratio) / 0.22


func _damage_new_crossings() -> void:
	for node in get_tree().get_nodes_in_group("overrush_enemies"):
		if not is_instance_valid(node) or node.is_queued_for_deletion():
			continue
		var enemy := node as EnemyAgent
		if enemy == null or _hit_enemy_ids.has(enemy.get_instance_id()):
			continue
		var planar_distance := Vector2(
			enemy.global_position.x - global_position.x,
			enemy.global_position.z - global_position.z
		).length()
		if planar_distance <= radius:
			_hit_enemy_ids[enemy.get_instance_id()] = true
			enemy.take_damage(damage)


func _build_visual() -> void:
	_disc = MeshInstance3D.new()
	var mesh := QuadMesh.new()
	mesh.size = Vector2(2.0, 2.0)
	_disc.mesh = mesh
	_disc.rotation_degrees.x = -90.0
	_disc.scale = Vector3(radius, radius, 1.0)
	var material := ShaderMaterial.new()
	material.shader = WakeShader
	_disc.material_override = material
	add_child(_disc)
