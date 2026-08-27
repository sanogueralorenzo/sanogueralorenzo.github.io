class_name EnemyAgent
extends Node3D

signal defeated(enemy: EnemyAgent, experience_value: int)
signal damaged(enemy: EnemyAgent, amount: float, source_id: StringName)
signal health_changed(enemy: EnemyAgent, current: float, maximum: float)
signal attack_telegraphed(enemy: EnemyAgent, attack_kind: StringName)
signal reinforcements_requested(enemy: EnemyAgent, count: int)
signal apex_enraged(enemy: EnemyAgent)

enum AttackState { CHASE, TELEGRAPH, CHARGE, RECOVER }

const CONTACT_DISTANCE_PADDING := 1.8
const HEIGHT_SMOOTHING := 12.0
const TELEGRAPH_ALPHA := 0.34
const RIFT_PREDICTION_SECONDS := 0.9
const ApexCatalogModel = preload("res://scripts/apex_catalog.gd")

var target: CharacterBody3D
var world: Node3D
var archetype := &"pursuer"
var is_elite := false
var is_apex := false
var health := 20.0
var maximum_health := 20.0
var movement_speed := 52.0
var contact_damage := 10.0
var experience_value := 3
var body_radius := 2.2

var _contact_cooldown := 0.0
var _special_cooldown := 1.5
var _hit_flash := 0.0
var _attack_state := AttackState.CHASE
var _attack_kind := &""
var _state_timer := 0.0
var _state_duration := 1.0
var _charge_direction := Vector3.FORWARD
var _charge_connected := false
var _attack_center := Vector3.ZERO
var _special_sequence := 0
var _body_material: StandardMaterial3D
var _body_mesh: MeshInstance3D
var _core_mesh: MeshInstance3D
var _telegraph_mesh: MeshInstance3D
var _telegraph_material: StandardMaterial3D
var _telegraph_outline_mesh: MeshInstance3D
var _telegraph_outline_material: StandardMaterial3D
var _reduced_motion := false
var _high_contrast_telegraphs := false
var _apex_enraged := false


func _enter_tree() -> void:
	add_to_group("overrush_enemies")


func configure(
	new_target: CharacterBody3D,
	new_world: Node3D,
	new_archetype: StringName,
	difficulty: float,
	rank: StringName = &"standard"
) -> void:
	target = new_target
	world = new_world
	archetype = new_archetype
	is_elite = rank == &"elite"
	is_apex = rank == &"apex"
	if is_apex:
		if not ApexCatalogModel.is_valid(archetype):
			archetype = ApexCatalogModel.VELOCITY_REAVER
		var definition := ApexCatalogModel.get_definition(archetype)
		maximum_health = float(definition.maximum_health)
		movement_speed = float(definition.movement_speed)
		contact_damage = float(definition.contact_damage)
		experience_value = 0
		body_radius = float(definition.body_radius)
	else:
		_configure_archetype(difficulty)
		if is_elite:
			maximum_health *= 4.5
			movement_speed *= 0.96
			contact_damage *= 1.3
			experience_value *= 5
			body_radius *= 1.38
	health = maximum_health
	_special_cooldown = 1.0 if is_apex else 1.5
	_build_visuals()


func _physics_process(delta: float) -> void:
	if not is_instance_valid(target) or not is_instance_valid(world):
		return
	_contact_cooldown = maxf(0.0, _contact_cooldown - delta)
	_special_cooldown = maxf(0.0, _special_cooldown - delta)
	_hit_flash = maxf(0.0, _hit_flash - delta)
	_update_material()

	var offset := target.global_position - global_position
	var planar_offset := Vector3(offset.x, 0.0, offset.z)
	var distance := planar_offset.length()
	match _attack_state:
		AttackState.CHASE:
			_update_chase(planar_offset, distance, delta)
		AttackState.TELEGRAPH:
			_update_telegraph(delta)
		AttackState.CHARGE:
			_update_charge(distance, delta)
		AttackState.RECOVER:
			_update_recovery(planar_offset, distance, delta)

	var desired_height: float = world.get_surface_height(global_position.x, global_position.z) + body_radius * 0.72
	global_position.y = lerpf(global_position.y, desired_height, 1.0 - exp(-HEIGHT_SMOOTHING * delta))
	_body_mesh.rotation.y += delta * (3.8 if archetype == &"skimmer" else 1.8)


func take_damage(amount: float, source_id: StringName = &"unattributed") -> void:
	if amount <= 0.0 or health <= 0.0:
		return
	var previous_health := health
	health = maxf(0.0, health - amount)
	_hit_flash = 0.09
	damaged.emit(self, previous_health - health, source_id)
	health_changed.emit(self, health, maximum_health)
	if is_apex and not _apex_enraged and health > 0.0 and health <= maximum_health * 0.5:
		_apex_enraged = true
		movement_speed *= 1.12
		apex_enraged.emit(self)
	if health <= 0.0:
		defeated.emit(self, experience_value)
		queue_free()


func apply_health_multiplier(multiplier: float) -> void:
	var safe_multiplier := maxf(0.1, multiplier)
	maximum_health *= safe_multiplier
	health *= safe_multiplier


func apply_accessibility(reduced_motion: bool, high_contrast_telegraphs: bool) -> void:
	_reduced_motion = reduced_motion
	_high_contrast_telegraphs = high_contrast_telegraphs


func get_attack_state() -> AttackState:
	return _attack_state


func is_apex_enraged() -> bool:
	return _apex_enraged


func _configure_archetype(difficulty: float) -> void:
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
		&"rift_weaver":
			maximum_health = 34.0 * difficulty
			movement_speed = 48.0 + difficulty
			contact_damage = 13.0 * sqrt(difficulty)
			experience_value = 5
			body_radius = 2.6
		&"swarm_foundry":
			maximum_health = 72.0 * difficulty
			movement_speed = 35.0 + difficulty * 0.7
			contact_damage = 9.0 * sqrt(difficulty)
			experience_value = 9
			body_radius = 3.8
		&"drone":
			maximum_health = 9.0 * difficulty
			movement_speed = 84.0 + difficulty * 2.0
			contact_damage = 5.0 * sqrt(difficulty)
			experience_value = 0
			body_radius = 1.25
		&"rift_spawn":
			maximum_health = 12.0 * difficulty
			movement_speed = 90.0 + difficulty * 2.0
			contact_damage = 6.0 * sqrt(difficulty)
			experience_value = 0
			body_radius = 1.3
		_:
			maximum_health = 24.0 * difficulty
			movement_speed = 56.0 + difficulty * 1.5
			contact_damage = 10.0 * sqrt(difficulty)
			experience_value = 3
			body_radius = 2.2


func _update_chase(planar_offset: Vector3, distance: float, delta: float) -> void:
	if _can_begin_special(distance):
		_begin_special(planar_offset)
		return
	if archetype == ApexCatalogModel.RIFT_MATRIARCH:
		_move_at_standoff(planar_offset, distance, 68.0, 112.0, delta)
	elif archetype == &"rift_weaver":
		_move_at_standoff(planar_offset, distance, 54.0, 88.0, delta)
	elif archetype == &"swarm_foundry":
		_move_at_standoff(planar_offset, distance, 62.0, 96.0, delta)
	else:
		_move_toward(planar_offset, distance, movement_speed, delta)
	_try_contact_damage(distance)


func _update_telegraph(delta: float) -> void:
	_state_timer -= delta
	var progress := 1.0 - clampf(_state_timer / maxf(_state_duration, 0.001), 0.0, 1.0)
	var radius := _get_attack_radius()
	var warning_scale := radius if _reduced_motion else lerpf(0.3, radius, progress)
	_telegraph_mesh.scale = Vector3.ONE * warning_scale * 0.94
	_telegraph_mesh.scale.y = 1.0
	_telegraph_outline_mesh.scale = Vector3.ONE * warning_scale
	_telegraph_outline_mesh.scale.y = 1.0
	_telegraph_material.albedo_color.a = lerpf(0.06 if _high_contrast_telegraphs else 0.12, _get_telegraph_alpha(), progress)
	_telegraph_outline_material.albedo_color.a = lerpf(0.48, 0.94 if _high_contrast_telegraphs else 0.72, progress)
	_core_mesh.scale = Vector3.ONE if _reduced_motion else Vector3.ONE * lerpf(1.0, 1.55, progress)
	if _state_timer > 0.0:
		return
	_telegraph_mesh.visible = false
	_telegraph_outline_mesh.visible = false
	_core_mesh.scale = Vector3.ONE
	match _attack_kind:
		&"bulwark_pulse", &"apex_pulse", &"rift_blast", &"apex_rift":
			_resolve_pulse()
			_begin_recovery()
		&"foundry_bloom", &"apex_bloom":
			var reinforcement_count := 4 if _attack_kind == &"apex_bloom" and _apex_enraged else (3 if is_elite or is_apex else 2)
			reinforcements_requested.emit(self, reinforcement_count)
			_begin_recovery()
		_:
			_attack_state = AttackState.CHARGE
			_state_duration = 0.82 if is_apex else 0.52
			_state_timer = _state_duration
			_charge_connected = false


func _update_charge(distance: float, delta: float) -> void:
	_state_timer -= delta
	var charge_speed := 112.0 if is_apex else 128.0
	global_position += _charge_direction * charge_speed * delta
	if not _charge_connected and distance <= body_radius + CONTACT_DISTANCE_PADDING + 1.6:
		target.take_damage(contact_damage * (1.35 if is_apex else 1.15), global_position)
		_charge_connected = true
	if _state_timer <= 0.0:
		_begin_recovery()


func _update_recovery(planar_offset: Vector3, distance: float, delta: float) -> void:
	_state_timer -= delta
	_move_toward(planar_offset, distance, movement_speed * 0.38, delta)
	if _state_timer <= 0.0:
		_attack_state = AttackState.CHASE


func _move_toward(planar_offset: Vector3, distance: float, speed: float, delta: float) -> void:
	if distance > 0.01:
		global_position += planar_offset / distance * speed * delta


func _move_at_standoff(planar_offset: Vector3, distance: float, near_distance: float, far_distance: float, delta: float) -> void:
	if distance <= 0.01:
		return
	var direction := planar_offset / distance
	if distance > far_distance:
		global_position += direction * movement_speed * delta
	elif distance < near_distance:
		global_position -= direction * movement_speed * 0.82 * delta
	else:
		var side := Vector3(-direction.z, 0.0, direction.x)
		var strafe_sign := -1.0 if _special_sequence % 2 == 0 else 1.0
		global_position += side * movement_speed * 0.34 * strafe_sign * delta


func _try_contact_damage(distance: float) -> void:
	if distance <= body_radius + CONTACT_DISTANCE_PADDING and _contact_cooldown <= 0.0:
		target.take_damage(contact_damage, global_position)
		_contact_cooldown = 0.85 if archetype != &"skimmer" else 1.15


func _can_begin_special(distance: float) -> bool:
	if _special_cooldown > 0.0:
		return false
	if is_apex:
		return distance <= (138.0 if archetype == ApexCatalogModel.RIFT_MATRIARCH else 92.0)
	if archetype == &"skimmer":
		return distance >= 16.0 and distance <= 66.0
	if archetype == &"bulwark":
		return distance <= (38.0 if is_elite else 30.0)
	if archetype == &"rift_weaver":
		return distance >= 28.0 and distance <= 112.0
	if archetype == &"swarm_foundry":
		return distance <= 118.0
	if archetype in [&"drone", &"rift_spawn"]:
		return false
	return is_elite and distance <= 58.0


func _begin_special(planar_offset: Vector3) -> void:
	_special_sequence += 1
	if archetype == ApexCatalogModel.RIFT_MATRIARCH:
		_attack_kind = &"apex_bloom" if _special_sequence % 3 == 0 else &"apex_rift"
	elif is_apex and _special_sequence % 3 == 0:
		_attack_kind = &"apex_pulse"
	elif archetype == &"rift_weaver":
		_attack_kind = &"rift_blast"
	elif archetype == &"swarm_foundry":
		_attack_kind = &"foundry_bloom"
	elif archetype == &"bulwark" or (is_elite and archetype == &"pursuer"):
		_attack_kind = &"bulwark_pulse"
	else:
		_attack_kind = &"apex_charge" if is_apex else &"skimmer_charge"
	var predicted_target := target.global_position + target.velocity * (0.3 if is_apex else 0.18)
	if _attack_kind in [&"rift_blast", &"apex_rift"]:
		var prediction_seconds := RIFT_PREDICTION_SECONDS
		if _attack_kind == &"apex_rift":
			prediction_seconds = 0.74 if _apex_enraged else 0.68
		predicted_target = target.global_position + target.velocity * prediction_seconds
		_attack_center = Vector3(
			predicted_target.x,
			world.get_surface_height(predicted_target.x, predicted_target.z) + 0.16,
			predicted_target.z
		)
		_place_remote_telegraph(_attack_center)
	else:
		_place_local_telegraph()
		_charge_direction = Vector3(
			predicted_target.x - global_position.x,
			0.0,
			predicted_target.z - global_position.z
		).normalized()
		if _charge_direction.length_squared() < 0.1:
			_charge_direction = planar_offset.normalized()
	_attack_state = AttackState.TELEGRAPH
	if _attack_kind == &"rift_blast":
		_state_duration = 1.05
	elif _attack_kind == &"apex_rift":
		_state_duration = 0.82 if _apex_enraged else 0.92
	elif _attack_kind == &"apex_bloom":
		_state_duration = 0.72 if _apex_enraged else 0.9
	elif _attack_kind == &"foundry_bloom":
		_state_duration = 0.88
	else:
		_state_duration = 0.82 if is_apex else (0.9 if _attack_kind == &"bulwark_pulse" else 0.58)
	_state_timer = _state_duration
	_telegraph_mesh.visible = true
	_telegraph_outline_mesh.visible = true
	var initial_radius := _get_attack_radius() if _reduced_motion else 0.3
	_telegraph_mesh.scale = Vector3(initial_radius * 0.94, 1.0, initial_radius * 0.94)
	_telegraph_outline_mesh.scale = Vector3(initial_radius, 1.0, initial_radius)
	var warning_alpha := _get_telegraph_alpha()
	var warning_color: Color
	if archetype == ApexCatalogModel.RIFT_MATRIARCH:
		warning_color = Color(0.72, 0.18, 1.0, warning_alpha) if _attack_kind == &"apex_rift" else Color(0.34, 1.0, 0.62, warning_alpha)
	elif is_apex:
		warning_color = Color(0.18, 0.95, 1.0, warning_alpha)
	elif _high_contrast_telegraphs:
		warning_color = Color(1.0, 0.86, 0.06, warning_alpha)
	elif _attack_kind == &"rift_blast":
		warning_color = Color(0.72, 0.16, 1.0, warning_alpha)
	elif _attack_kind == &"foundry_bloom":
		warning_color = Color(0.35, 1.0, 0.18, warning_alpha)
	else:
		warning_color = Color(1.0, 0.16, 0.05, warning_alpha)
	_telegraph_material.albedo_color = warning_color
	_telegraph_material.emission = Color(warning_color.r, warning_color.g, warning_color.b)
	_telegraph_material.emission_energy_multiplier = 1.0 if _high_contrast_telegraphs else 4.0
	var outline_color := Color.WHITE if _high_contrast_telegraphs else Color(warning_color.r, warning_color.g, warning_color.b)
	_telegraph_outline_material.albedo_color = Color(outline_color.r, outline_color.g, outline_color.b, 0.94 if _high_contrast_telegraphs else 0.72)
	_telegraph_outline_material.emission = outline_color
	attack_telegraphed.emit(self, _attack_kind)


func _resolve_pulse() -> void:
	var center := _attack_center if _attack_kind in [&"rift_blast", &"apex_rift"] else global_position
	var planar_distance := Vector2(
		target.global_position.x - center.x,
		target.global_position.z - center.z
	).length()
	if planar_distance <= _get_attack_radius():
		var damage_multiplier := 1.1 if _attack_kind == &"rift_blast" else (1.18 if _attack_kind == &"apex_rift" else (1.25 if is_apex else 0.9))
		target.take_damage(contact_damage * damage_multiplier, center)


func _begin_recovery() -> void:
	_attack_state = AttackState.RECOVER
	_state_duration = 0.38 if is_apex else 0.5
	_state_timer = _state_duration
	if archetype == ApexCatalogModel.RIFT_MATRIARCH:
		_special_cooldown = 1.85 if _apex_enraged else 2.55
	elif is_apex:
		_special_cooldown = 2.35 if health <= maximum_health * 0.5 else 2.9
	elif archetype == &"swarm_foundry":
		_special_cooldown = 5.6
	elif archetype == &"rift_weaver":
		_special_cooldown = 4.2
	else:
		_special_cooldown = 3.4
	_telegraph_mesh.visible = false
	_telegraph_outline_mesh.visible = false
	_core_mesh.scale = Vector3.ONE


func _get_attack_radius() -> float:
	if _attack_kind == &"apex_rift":
		return 22.0 if _apex_enraged else 18.0
	if _attack_kind == &"apex_bloom":
		return 24.0
	if _attack_kind == &"apex_pulse":
		return 34.0
	if _attack_kind == &"bulwark_pulse":
		return 27.0 if is_elite else 21.0
	if _attack_kind == &"rift_blast":
		return 14.0 if is_elite else 12.0
	if _attack_kind == &"foundry_bloom":
		return 18.0
	return body_radius * (2.4 if is_apex else 2.0)


func _place_remote_telegraph(center: Vector3) -> void:
	_telegraph_mesh.global_position = center + Vector3.UP * 0.04
	_telegraph_outline_mesh.global_position = center


func _place_local_telegraph() -> void:
	if not _telegraph_mesh.top_level:
		return
	var center := global_position + Vector3.DOWN * body_radius * 0.7
	_telegraph_mesh.global_position = center + Vector3.UP * 0.16
	_telegraph_outline_mesh.global_position = center + Vector3.UP * 0.12


func _get_telegraph_alpha() -> float:
	return 0.22 if _high_contrast_telegraphs else TELEGRAPH_ALPHA


func _build_visuals() -> void:
	_body_material = StandardMaterial3D.new()
	_body_material.metallic = 0.35
	_body_material.roughness = 0.28
	_body_material.emission_enabled = true

	_body_mesh = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = body_radius
	sphere.height = body_radius * 2.0
	sphere.radial_segments = 24 if is_apex else 16
	sphere.rings = 12 if is_apex else 8
	_body_mesh.mesh = sphere
	_body_mesh.material_override = _body_material
	if archetype == &"skimmer":
		_body_mesh.scale = Vector3(1.0, 0.52, 1.45)
	elif archetype == &"bulwark":
		_body_mesh.scale = Vector3(1.2, 0.85, 1.2)
	elif archetype == &"rift_weaver":
		_body_mesh.scale = Vector3(0.72, 1.18, 0.72)
	elif archetype == &"swarm_foundry":
		_body_mesh.scale = Vector3(1.22, 0.8, 1.22)
	elif archetype == &"drone":
		_body_mesh.scale = Vector3(0.62, 0.62, 1.5)
	elif archetype == &"rift_spawn":
		_body_mesh.scale = Vector3(0.7, 0.7, 1.42)
	elif archetype == ApexCatalogModel.RIFT_MATRIARCH:
		_body_mesh.scale = Vector3(0.9, 1.28, 0.9)
	elif is_apex:
		_body_mesh.scale = Vector3(1.18, 0.78, 1.45)
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
	if archetype == ApexCatalogModel.RIFT_MATRIARCH:
		core_material.albedo_color = Color(0.96, 0.72, 1.0)
	elif is_apex:
		core_material.albedo_color = Color(0.72, 0.96, 1.0)
	elif archetype == &"rift_weaver":
		core_material.albedo_color = Color(0.88, 0.58, 1.0)
	elif archetype == &"rift_spawn":
		core_material.albedo_color = Color(0.92, 0.58, 1.0)
	elif archetype == &"swarm_foundry" or archetype == &"drone":
		core_material.albedo_color = Color(0.62, 1.0, 0.28)
	else:
		core_material.albedo_color = Color(1.0, 0.82, 0.18)
	core_material.emission_enabled = true
	if archetype == ApexCatalogModel.RIFT_MATRIARCH:
		core_material.emission = Color(0.68, 0.08, 1.0)
	elif is_apex:
		core_material.emission = Color(0.08, 0.78, 1.0)
	elif archetype == &"rift_weaver":
		core_material.emission = Color(0.54, 0.05, 1.0)
	elif archetype == &"rift_spawn":
		core_material.emission = Color(0.64, 0.08, 1.0)
	elif archetype == &"swarm_foundry" or archetype == &"drone":
		core_material.emission = Color(0.16, 0.82, 0.04)
	else:
		core_material.emission = Color(1.0, 0.28, 0.025)
	core_material.emission_energy_multiplier = 5.0 if is_apex else 4.0
	_core_mesh.material_override = core_material
	add_child(_core_mesh)

	_telegraph_mesh = MeshInstance3D.new()
	var telegraph_disc := CylinderMesh.new()
	telegraph_disc.top_radius = 1.0
	telegraph_disc.bottom_radius = 1.0
	telegraph_disc.height = 0.06
	telegraph_disc.radial_segments = 48
	_telegraph_mesh.mesh = telegraph_disc
	_telegraph_mesh.position.y = -body_radius * 0.7 + 0.12
	_telegraph_mesh.visible = false
	_telegraph_material = StandardMaterial3D.new()
	_telegraph_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_telegraph_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_telegraph_material.emission_enabled = true
	_telegraph_material.emission_energy_multiplier = 4.0
	_telegraph_mesh.material_override = _telegraph_material
	add_child(_telegraph_mesh)
	if archetype in [&"rift_weaver", ApexCatalogModel.RIFT_MATRIARCH]:
		_telegraph_mesh.top_level = true

	_telegraph_outline_mesh = MeshInstance3D.new()
	_telegraph_outline_mesh.mesh = _create_warning_ring_mesh()
	_telegraph_outline_mesh.position = _telegraph_mesh.position
	_telegraph_mesh.position += Vector3.UP * 0.04
	_telegraph_outline_mesh.visible = false
	_telegraph_outline_material = StandardMaterial3D.new()
	_telegraph_outline_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_telegraph_outline_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_telegraph_outline_material.emission_enabled = true
	_telegraph_outline_material.emission_energy_multiplier = 5.0
	_telegraph_outline_mesh.material_override = _telegraph_outline_material
	add_child(_telegraph_outline_mesh)
	if archetype in [&"rift_weaver", ApexCatalogModel.RIFT_MATRIARCH]:
		_telegraph_outline_mesh.top_level = true

	_build_role_silhouette()

	if is_elite or is_apex:
		_build_rank_shell()
	_update_material()


func _build_role_silhouette() -> void:
	if archetype == ApexCatalogModel.VELOCITY_REAVER:
		for side in [-1.0, 1.0]:
			var curved_blade := MeshInstance3D.new()
			var blade_mesh := CapsuleMesh.new()
			blade_mesh.radius = body_radius * 0.22
			blade_mesh.height = body_radius * 1.95
			blade_mesh.radial_segments = 14
			blade_mesh.rings = 5
			curved_blade.mesh = blade_mesh
			curved_blade.position = Vector3(side * body_radius * 0.78, 0.0, body_radius * 0.08)
			curved_blade.rotation_degrees = Vector3(18.0, side * 12.0, side * 68.0)
			curved_blade.material_override = _create_role_material(Color(0.04, 0.82, 1.0))
			add_child(curved_blade)
		var drive_ring := MeshInstance3D.new()
		var drive_torus := TorusMesh.new()
		drive_torus.inner_radius = body_radius * 0.62
		drive_torus.outer_radius = body_radius * 0.83
		drive_torus.rings = 28
		drive_torus.ring_segments = 10
		drive_ring.mesh = drive_torus
		drive_ring.rotation_degrees = Vector3(90.0, 0.0, 0.0)
		drive_ring.position = Vector3(0.0, 0.0, body_radius * 0.72)
		drive_ring.material_override = _create_role_material(Color(0.1, 0.9, 1.0))
		add_child(drive_ring)
	elif archetype == ApexCatalogModel.RIFT_MATRIARCH:
		for tilt in [-58.0, 0.0, 58.0]:
			var crown_ring := MeshInstance3D.new()
			var crown_torus := TorusMesh.new()
			crown_torus.inner_radius = body_radius * 0.78
			crown_torus.outer_radius = body_radius * 0.98
			crown_torus.rings = 28
			crown_torus.ring_segments = 10
			crown_ring.mesh = crown_torus
			crown_ring.rotation_degrees = Vector3(tilt, 18.0 + tilt * 0.22, 28.0)
			crown_ring.material_override = _create_role_material(Color(0.66, 0.08, 1.0))
			add_child(crown_ring)
		for index in range(4):
			var brood_core := MeshInstance3D.new()
			var brood_mesh := SphereMesh.new()
			brood_mesh.radius = body_radius * 0.2
			brood_mesh.height = body_radius * 0.4
			brood_mesh.radial_segments = 12
			brood_mesh.rings = 6
			brood_core.mesh = brood_mesh
			var angle := TAU * float(index) / 4.0
			brood_core.position = Vector3(cos(angle), 0.12, sin(angle)) * body_radius * 1.18
			brood_core.material_override = _create_role_material(Color(0.28, 1.0, 0.58))
			add_child(brood_core)
	elif archetype == &"rift_weaver":
		for tilt in [-52.0, 52.0]:
			var ring := MeshInstance3D.new()
			var torus := TorusMesh.new()
			torus.inner_radius = body_radius * 0.7
			torus.outer_radius = body_radius * 0.94
			torus.rings = 20
			torus.ring_segments = 8
			ring.mesh = torus
			ring.rotation_degrees = Vector3(tilt, 0.0, 18.0)
			ring.material_override = _create_role_material(Color(0.56, 0.08, 1.0))
			add_child(ring)
	elif archetype == &"swarm_foundry":
		for tilt in [-24.0, 24.0]:
			var foundry_ring := MeshInstance3D.new()
			var foundry_torus := TorusMesh.new()
			foundry_torus.inner_radius = body_radius * 0.86
			foundry_torus.outer_radius = body_radius * 1.08
			foundry_torus.rings = 20
			foundry_torus.ring_segments = 8
			foundry_ring.mesh = foundry_torus
			foundry_ring.rotation_degrees = Vector3(tilt, 0.0, 0.0)
			foundry_ring.material_override = _create_role_material(Color(0.58, 0.92, 0.06))
			add_child(foundry_ring)
		for index in range(3):
			var pod := MeshInstance3D.new()
			var pod_mesh := SphereMesh.new()
			pod_mesh.radius = body_radius * 0.24
			pod_mesh.height = body_radius * 0.48
			pod_mesh.radial_segments = 10
			pod_mesh.rings = 5
			pod.mesh = pod_mesh
			var angle := TAU * float(index) / 3.0
			pod.position = Vector3(cos(angle), 0.18, sin(angle)) * body_radius * 0.82
			pod.material_override = _create_role_material(Color(0.24, 0.9, 0.08))
			add_child(pod)


func _create_role_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.metallic = 0.42
	material.roughness = 0.24
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color * 0.72
	material.emission_energy_multiplier = 2.2
	return material


func _create_warning_ring_mesh() -> ArrayMesh:
	const SEGMENTS := 48
	const INNER_RADIUS := 0.9
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	for segment in range(SEGMENTS + 1):
		var angle := TAU * float(segment) / float(SEGMENTS)
		var direction := Vector3(cos(angle), 0.0, sin(angle))
		vertices.append(direction)
		vertices.append(direction * INNER_RADIUS)
	for segment in range(SEGMENTS):
		var outer_current := segment * 2
		var inner_current := outer_current + 1
		var outer_next := outer_current + 2
		var inner_next := outer_current + 3
		indices.append_array(PackedInt32Array([
			outer_current,
			outer_next,
			inner_current,
			outer_next,
			inner_next,
			inner_current,
		]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _build_rank_shell() -> void:
	var shell := MeshInstance3D.new()
	var shell_mesh := SphereMesh.new()
	shell_mesh.radius = body_radius * 1.16
	shell_mesh.height = body_radius * 2.32
	shell_mesh.radial_segments = 18
	shell_mesh.rings = 9
	shell.mesh = shell_mesh
	var shell_material := StandardMaterial3D.new()
	shell_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shell_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var apex_color := Color(0.68, 0.08, 1.0) if archetype == ApexCatalogModel.RIFT_MATRIARCH else Color(0.05, 0.7, 1.0)
	shell_material.albedo_color = Color(apex_color.r, apex_color.g, apex_color.b, 0.18) if is_apex else Color(1.0, 0.62, 0.08, 0.17)
	shell_material.emission_enabled = true
	shell_material.emission = apex_color if is_apex else Color(1.0, 0.28, 0.03)
	shell_material.emission_energy_multiplier = 2.8
	shell.material_override = shell_material
	add_child(shell)
	var light := OmniLight3D.new()
	light.light_color = apex_color if is_apex else Color(1.0, 0.28, 0.05)
	light.light_energy = 4.5 if is_apex else 2.4
	light.omni_range = body_radius * 4.0
	add_child(light)


func _update_material() -> void:
	if not is_instance_valid(_body_material):
		return
	var base_color := Color(0.75, 0.04, 0.22)
	if archetype == &"skimmer":
		base_color = Color(0.78, 0.08, 0.72)
	elif archetype == &"bulwark":
		base_color = Color(0.92, 0.22, 0.035)
	elif archetype == &"rift_weaver":
		base_color = Color(0.42, 0.035, 0.78)
	elif archetype == &"swarm_foundry":
		base_color = Color(0.14, 0.5, 0.045)
	elif archetype == &"drone":
		base_color = Color(0.32, 0.74, 0.06)
	elif archetype == &"rift_spawn":
		base_color = Color(0.48, 0.04, 0.72)
	elif is_apex:
		base_color = Color(0.34, 0.02, 0.56) if archetype == ApexCatalogModel.RIFT_MATRIARCH else Color(0.025, 0.32, 0.62)
	if is_elite:
		base_color = base_color.lerp(Color(1.0, 0.42, 0.04), 0.42)
	if _hit_flash > 0.0:
		base_color = Color(1.0, 0.95, 0.65)
	_body_material.albedo_color = base_color
	_body_material.emission = base_color * 0.72
	_body_material.emission_energy_multiplier = 2.8 if _hit_flash > 0.0 else (2.0 if is_apex or is_elite else 1.2)
