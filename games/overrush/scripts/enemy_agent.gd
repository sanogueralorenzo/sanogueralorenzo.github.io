class_name EnemyAgent
extends Node3D

signal defeated(enemy: EnemyAgent, experience_value: int)
signal health_changed(enemy: EnemyAgent, current: float, maximum: float)
signal attack_telegraphed(enemy: EnemyAgent, attack_kind: StringName)

enum AttackState { CHASE, TELEGRAPH, CHARGE, RECOVER }

const CONTACT_DISTANCE_PADDING := 1.8
const HEIGHT_SMOOTHING := 12.0
const TELEGRAPH_ALPHA := 0.34

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
		archetype = &"apex"
		maximum_health = 1800.0
		movement_speed = 62.0
		contact_damage = 24.0
		experience_value = 0
		body_radius = 6.2
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


func take_damage(amount: float) -> void:
	if amount <= 0.0 or health <= 0.0:
		return
	health = maxf(0.0, health - amount)
	_hit_flash = 0.09
	health_changed.emit(self, health, maximum_health)
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
	if _attack_kind == &"bulwark_pulse" or _attack_kind == &"apex_pulse":
		_resolve_pulse()
		_begin_recovery()
	else:
		_attack_state = AttackState.CHARGE
		_state_duration = 0.82 if is_apex else 0.52
		_state_timer = _state_duration
		_charge_connected = false


func _update_charge(distance: float, delta: float) -> void:
	_state_timer -= delta
	var charge_speed := 112.0 if is_apex else 128.0
	global_position += _charge_direction * charge_speed * delta
	if not _charge_connected and distance <= body_radius + CONTACT_DISTANCE_PADDING + 1.6:
		target.take_damage(contact_damage * (1.35 if is_apex else 1.15))
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


func _try_contact_damage(distance: float) -> void:
	if distance <= body_radius + CONTACT_DISTANCE_PADDING and _contact_cooldown <= 0.0:
		target.take_damage(contact_damage)
		_contact_cooldown = 0.85 if archetype != &"skimmer" else 1.15


func _can_begin_special(distance: float) -> bool:
	if _special_cooldown > 0.0:
		return false
	if is_apex:
		return distance <= 92.0
	if archetype == &"skimmer":
		return distance >= 16.0 and distance <= 66.0
	if archetype == &"bulwark":
		return distance <= (38.0 if is_elite else 30.0)
	return is_elite and distance <= 58.0


func _begin_special(planar_offset: Vector3) -> void:
	_special_sequence += 1
	if is_apex and _special_sequence % 3 == 0:
		_attack_kind = &"apex_pulse"
	elif archetype == &"bulwark" or (is_elite and archetype == &"pursuer"):
		_attack_kind = &"bulwark_pulse"
	else:
		_attack_kind = &"apex_charge" if is_apex else &"skimmer_charge"
	var predicted_target := target.global_position + target.velocity * (0.3 if is_apex else 0.18)
	_charge_direction = Vector3(
		predicted_target.x - global_position.x,
		0.0,
		predicted_target.z - global_position.z
	).normalized()
	if _charge_direction.length_squared() < 0.1:
		_charge_direction = planar_offset.normalized()
	_attack_state = AttackState.TELEGRAPH
	_state_duration = 0.82 if is_apex else (0.9 if _attack_kind == &"bulwark_pulse" else 0.58)
	_state_timer = _state_duration
	_telegraph_mesh.visible = true
	_telegraph_outline_mesh.visible = true
	var initial_radius := _get_attack_radius() if _reduced_motion else 0.3
	_telegraph_mesh.scale = Vector3(initial_radius * 0.94, 1.0, initial_radius * 0.94)
	_telegraph_outline_mesh.scale = Vector3(initial_radius, 1.0, initial_radius)
	var warning_alpha := _get_telegraph_alpha()
	var warning_color: Color
	if is_apex:
		warning_color = Color(0.18, 0.95, 1.0, warning_alpha)
	elif _high_contrast_telegraphs:
		warning_color = Color(1.0, 0.86, 0.06, warning_alpha)
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
	var planar_distance := Vector2(
		target.global_position.x - global_position.x,
		target.global_position.z - global_position.z
	).length()
	if planar_distance <= _get_attack_radius():
		target.take_damage(contact_damage * (1.25 if is_apex else 0.9))


func _begin_recovery() -> void:
	_attack_state = AttackState.RECOVER
	_state_duration = 0.38 if is_apex else 0.5
	_state_timer = _state_duration
	_special_cooldown = 2.35 if is_apex and health <= maximum_health * 0.5 else (2.9 if is_apex else 3.4)
	_telegraph_mesh.visible = false
	_telegraph_outline_mesh.visible = false
	_core_mesh.scale = Vector3.ONE


func _get_attack_radius() -> float:
	if _attack_kind == &"apex_pulse":
		return 34.0
	if _attack_kind == &"bulwark_pulse":
		return 27.0 if is_elite else 21.0
	return body_radius * (2.4 if is_apex else 2.0)


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
	sphere.radial_segments = 20 if is_apex else 16
	sphere.rings = 10 if is_apex else 8
	_body_mesh.mesh = sphere
	_body_mesh.material_override = _body_material
	if archetype == &"skimmer":
		_body_mesh.scale = Vector3(1.0, 0.52, 1.45)
	elif archetype == &"bulwark":
		_body_mesh.scale = Vector3(1.2, 0.85, 1.2)
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
	core_material.albedo_color = Color(0.72, 0.96, 1.0) if is_apex else Color(1.0, 0.82, 0.18)
	core_material.emission_enabled = true
	core_material.emission = Color(0.08, 0.78, 1.0) if is_apex else Color(1.0, 0.28, 0.025)
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

	if is_elite or is_apex:
		_build_rank_shell()
	_update_material()


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
	shell_material.albedo_color = Color(0.1, 0.82, 1.0, 0.18) if is_apex else Color(1.0, 0.62, 0.08, 0.17)
	shell_material.emission_enabled = true
	shell_material.emission = Color(0.05, 0.7, 1.0) if is_apex else Color(1.0, 0.28, 0.03)
	shell_material.emission_energy_multiplier = 2.8
	shell.material_override = shell_material
	add_child(shell)
	var light := OmniLight3D.new()
	light.light_color = Color(0.08, 0.72, 1.0) if is_apex else Color(1.0, 0.28, 0.05)
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
	elif is_apex:
		base_color = Color(0.025, 0.32, 0.62)
	if is_elite:
		base_color = base_color.lerp(Color(1.0, 0.42, 0.04), 0.42)
	if _hit_flash > 0.0:
		base_color = Color(1.0, 0.95, 0.65)
	_body_material.albedo_color = base_color
	_body_material.emission = base_color * 0.72
	_body_material.emission_energy_multiplier = 2.8 if _hit_flash > 0.0 else (2.0 if is_apex or is_elite else 1.2)
