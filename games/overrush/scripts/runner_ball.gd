extends CharacterBody3D

signal dash_state_changed(active: bool)
signal integrity_changed(current: float, maximum: float)
signal defeated
signal damaged(amount: float, source_direction: Vector3, integrity_ratio: float, source_id: StringName)

const DashStateMachine = preload("res://scripts/dash_state.gd")
const InputBindings = preload("res://scripts/input_bindings.gd")
const AIRFRAME_COMMIT_TIME := 0.14
const BASE_DASH_IMMUNITY_SECONDS := 0.14
const VISUAL_TURN_RESPONSE := 12.0
const VISUAL_BANK_RADIANS := 0.3

@export var cruise_speed: float = 58.0
@export var boost_speed: float = 88.0
@export var brake_speed: float = 24.0
@export var ground_acceleration: float = 52.0
@export var air_control: float = 0.28
@export var ground_traction: float = 11.0
@export var air_traction: float = 3.2
@export var turn_speed: float = 1.75
@export var jump_velocity: float = 17.0
@export var dash_speed: float = 126.0
@export var dash_exit_speed: float = 78.0
@export var dash_minimum_duration: float = 0.08
@export var dash_maximum_duration: float = 0.24
@export var dash_cooldown: float = 0.14
@export var maximum_integrity: float = 100.0
@export var damage_invulnerability: float = 0.42

@onready var ball_mesh: MeshInstance3D = $BallMesh
@onready var dash_trail: GPUParticles3D = $DashTrail
@onready var dash_light: OmniLight3D = $DashLight

var heading := Vector3.FORWARD
var spawn_position := Vector3.ZERO
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _dash_state: DashStateMachine
var _dash_heading := Vector3.FORWARD
var _dash_was_pressed := false
var _ball_material: StandardMaterial3D
var integrity: float
var _damage_invulnerability_remaining := 0.0
var _damage_flash_remaining := 0.0
var _dash_visual_active := false
var _reduced_motion := false
var _airborne_time := 0.0
var _runner_frame: Node3D
var _dash_ring: MeshInstance3D
var _directional_fins: Array[MeshInstance3D] = []
var _roll_bands: Array[MeshInstance3D] = []
var _dash_ring_material: StandardMaterial3D


func _ready() -> void:
	_dash_state = DashStateMachine.new(dash_minimum_duration, dash_maximum_duration, dash_cooldown)
	_ball_material = ball_mesh.get_active_material(0).duplicate()
	ball_mesh.material_override = _ball_material
	_build_runner_visuals()
	integrity = maximum_integrity
	integrity_changed.emit(integrity, maximum_integrity)


func _physics_process(delta: float) -> void:
	_damage_invulnerability_remaining = maxf(0.0, _damage_invulnerability_remaining - delta)
	_damage_flash_remaining = maxf(0.0, _damage_flash_remaining - delta)
	_update_ball_material()
	var grounded := is_on_floor()
	_airborne_time = 0.0 if grounded else _airborne_time + delta
	var dash_pressed := _is_dash_pressed()
	var dash_event := _dash_state.step(delta, dash_pressed, dash_pressed and not _dash_was_pressed, grounded)
	_dash_was_pressed = dash_pressed
	if dash_event == DashStateMachine.Event.STARTED:
		_begin_dash()
	elif dash_event == DashStateMachine.Event.ENDED:
		_end_dash()

	var steering := Input.get_action_strength(InputBindings.MOVE_LEFT) - Input.get_action_strength(InputBindings.MOVE_RIGHT)
	if not _dash_state.is_active:
		heading = heading.rotated(Vector3.UP, steering * turn_speed * delta).normalized()

	if _dash_state.is_active:
		velocity.x = _dash_heading.x * dash_speed
		velocity.z = _dash_heading.z * dash_speed
		if _dash_state.started_in_air:
			velocity.y = 0.0
		var intended_dash_velocity := Vector3(velocity.x, 0.0, velocity.z)
		move_and_slide()
		_preserve_collision_momentum(intended_dash_velocity)
		_roll_visual(delta)
		_update_runner_frame(delta, steering)
		_check_fall()
		return

	var target_speed := cruise_speed
	var boost_strength := Input.get_action_strength(InputBindings.BOOST)
	var brake_strength := Input.get_action_strength(InputBindings.BRAKE)
	if boost_strength > brake_strength and boost_strength > 0.15:
		target_speed = boost_speed
	elif brake_strength > 0.15:
		target_speed = brake_speed

	var horizontal_velocity := Vector3(velocity.x, 0.0, velocity.z)
	var acceleration := ground_acceleration if is_on_floor() else ground_acceleration * air_control
	var current_speed := horizontal_velocity.length()
	var adjusted_speed := move_toward(current_speed, target_speed, acceleration * delta)
	var travel_direction := heading
	if current_speed > 0.01:
		var traction := ground_traction if is_on_floor() else air_traction
		travel_direction = horizontal_velocity.normalized().slerp(
			heading,
			1.0 - exp(-traction * delta)
		).normalized()
	horizontal_velocity = travel_direction * adjusted_speed
	velocity.x = horizontal_velocity.x
	velocity.z = horizontal_velocity.z

	if is_on_floor():
		if velocity.y < 0.0:
			velocity.y = -1.5
		if Input.is_action_pressed(InputBindings.HOP):
			velocity.y = jump_velocity
	else:
		velocity.y -= _gravity * 2.35 * delta

	var intended_horizontal_velocity := Vector3(velocity.x, 0.0, velocity.z)
	move_and_slide()
	_preserve_collision_momentum(intended_horizontal_velocity)
	_roll_visual(delta)
	_update_runner_frame(delta, steering)
	_check_fall()


func respawn(at_position: Vector3) -> void:
	spawn_position = at_position
	global_position = at_position
	velocity = heading * cruise_speed * 0.35
	if is_instance_valid(_dash_state):
		_dash_state.reset()
		_set_dash_visuals(false)
	_airborne_time = 0.0


func get_horizontal_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()


func apply_boundary_heading(guided_heading: Vector3) -> void:
	heading = Vector3(guided_heading.x, 0.0, guided_heading.z).normalized()
	if is_instance_valid(_dash_state) and _dash_state.is_active:
		_dash_heading = heading


func grant_damage_immunity(duration: float) -> void:
	_damage_invulnerability_remaining = maxf(_damage_invulnerability_remaining, duration)


func take_damage(amount: float, source_position: Vector3 = Vector3.INF, source_id: StringName = &"unattributed") -> void:
	if amount <= 0.0 or integrity <= 0.0 or _damage_invulnerability_remaining > 0.0:
		return
	var previous_integrity := integrity
	integrity = maxf(0.0, integrity - amount)
	_damage_invulnerability_remaining = damage_invulnerability
	_damage_flash_remaining = 0.13
	var source_direction := Vector3.ZERO
	if source_position.is_finite():
		source_direction = source_position - global_position
		source_direction.y = 0.0
		if source_direction.length_squared() > 0.001:
			source_direction = source_direction.normalized()
	damaged.emit(
		previous_integrity - integrity,
		source_direction,
		integrity / maxf(maximum_integrity, 1.0),
		source_id
	)
	integrity_changed.emit(integrity, maximum_integrity)
	if integrity <= 0.0:
		defeated.emit()


func increase_maximum_integrity(amount: float, repair_amount: float) -> void:
	maximum_integrity += maxf(0.0, amount)
	integrity = minf(maximum_integrity, integrity + maxf(0.0, repair_amount))
	integrity_changed.emit(integrity, maximum_integrity)


func repair_integrity(amount: float) -> float:
	if amount <= 0.0 or integrity <= 0.0:
		return 0.0
	var previous_integrity := integrity
	integrity = minf(maximum_integrity, integrity + amount)
	var applied := integrity - previous_integrity
	if applied > 0.0:
		integrity_changed.emit(integrity, maximum_integrity)
	return applied


func apply_integrity_multiplier(multiplier: float) -> void:
	maximum_integrity = maxf(1.0, maximum_integrity * maxf(0.1, multiplier))
	integrity = minf(integrity, maximum_integrity)
	integrity_changed.emit(integrity, maximum_integrity)


func set_reduced_motion(enabled: bool) -> void:
	_reduced_motion = enabled
	_set_dash_visuals(_dash_visual_active)


func is_dashing() -> bool:
	return _dash_state != null and _dash_state.is_active


func is_airborne_attack_window() -> bool:
	return _airborne_time >= AIRFRAME_COMMIT_TIME


func get_dash_status() -> String:
	if _dash_state == null:
		return "DASH READY"
	if _dash_state.is_active:
		return "DASHING"
	if not is_on_floor() and not _dash_state.air_dash_available:
		return "AIR DASH SPENT"
	return "DASH READY"


func _begin_dash() -> void:
	_dash_heading = heading.normalized()
	grant_damage_immunity(BASE_DASH_IMMUNITY_SECONDS)
	if _dash_state.started_in_air:
		velocity.y = 0.0
	_set_dash_visuals(true)
	dash_state_changed.emit(true)


func _end_dash() -> void:
	var horizontal_velocity := Vector3(velocity.x, 0.0, velocity.z)
	if horizontal_velocity.length() > dash_exit_speed:
		horizontal_velocity = horizontal_velocity.normalized() * dash_exit_speed
		velocity.x = horizontal_velocity.x
		velocity.z = horizontal_velocity.z
	_set_dash_visuals(false)
	dash_state_changed.emit(false)


func _set_dash_visuals(active: bool) -> void:
	if not is_instance_valid(_ball_material):
		return
	_dash_visual_active = active
	_update_ball_material()
	dash_trail.emitting = active and not _reduced_motion
	dash_light.light_energy = (1.2 if _reduced_motion else 3.2) if active else 0.0
	_update_dash_ring(1.0)


func _update_ball_material() -> void:
	if not is_instance_valid(_ball_material):
		return
	if _damage_flash_remaining > 0.0:
		if _reduced_motion:
			_ball_material.albedo_color = Color(1.0, 0.3, 0.08, 1.0)
			_ball_material.emission = Color(0.8, 0.035, 0.006, 1.0)
			_ball_material.emission_energy_multiplier = 1.8
		else:
			_ball_material.albedo_color = Color(1.0, 0.95, 0.72, 1.0)
			_ball_material.emission = Color(1.0, 0.42, 0.06, 1.0)
			_ball_material.emission_energy_multiplier = 5.2
	elif _dash_visual_active:
		_ball_material.albedo_color = Color(0.12, 0.9, 1.0, 1.0)
		_ball_material.emission = Color(0.02, 0.65, 1.0, 1.0)
		_ball_material.emission_energy_multiplier = 4.2
	else:
		_ball_material.albedo_color = Color(1.0, 0.17, 0.055, 1.0)
		_ball_material.emission = Color(0.8, 0.035, 0.006, 1.0)
		_ball_material.emission_energy_multiplier = 1.35


func _is_dash_pressed() -> bool:
	return Input.is_action_pressed(InputBindings.DASH)


func _check_fall() -> void:
	if global_position.y < -180.0:
		respawn(spawn_position)


func _roll_visual(delta: float) -> void:
	if _reduced_motion:
		return
	var horizontal_velocity := Vector3(velocity.x, 0.0, velocity.z)
	if horizontal_velocity.length_squared() < 0.01:
		return
	var roll_axis := horizontal_velocity.normalized().cross(Vector3.UP)
	ball_mesh.rotate(roll_axis, horizontal_velocity.length() * delta / 1.2)


func _build_runner_visuals() -> void:
	var shell_material := StandardMaterial3D.new()
	shell_material.albedo_color = Color(0.14, 0.88, 1.0, 1.0)
	shell_material.metallic = 0.72
	shell_material.roughness = 0.18
	shell_material.emission_enabled = true
	shell_material.emission = Color(0.02, 0.48, 0.78, 1.0)
	shell_material.emission_energy_multiplier = 1.7
	shell_material.no_depth_test = true

	var band_mesh := TorusMesh.new()
	band_mesh.inner_radius = 0.93
	band_mesh.outer_radius = 1.1
	band_mesh.rings = 18
	band_mesh.ring_segments = 8
	for rotation_degrees in [Vector3(90.0, 0.0, 0.0), Vector3(56.0, 0.0, 58.0)]:
		var band := MeshInstance3D.new()
		band.name = "GyroBand%d" % (_roll_bands.size() + 1)
		band.mesh = band_mesh
		band.material_override = shell_material
		band.rotation_degrees = rotation_degrees
		ball_mesh.add_child(band)
		_roll_bands.append(band)

	_runner_frame = Node3D.new()
	_runner_frame.name = "RunnerFrame"
	add_child(_runner_frame)

	var nose_mesh := CylinderMesh.new()
	nose_mesh.top_radius = 0.0
	nose_mesh.bottom_radius = 0.34
	nose_mesh.height = 0.72
	nose_mesh.radial_segments = 12
	var nose := MeshInstance3D.new()
	nose.name = "DirectionNeedle"
	nose.mesh = nose_mesh
	nose.material_override = shell_material
	nose.position = Vector3(0.0, 0.0, -1.18)
	nose.rotation_degrees.x = -90.0
	_runner_frame.add_child(nose)

	var fin_mesh := BoxMesh.new()
	fin_mesh.size = Vector3(0.18, 0.28, 1.1)
	for side in [-1.0, 1.0]:
		var fin := MeshInstance3D.new()
		fin.name = "LeftVectorFin" if side < 0.0 else "RightVectorFin"
		fin.mesh = fin_mesh
		fin.material_override = shell_material
		fin.position = Vector3(side * 1.03, 0.0, 0.16)
		fin.rotation_degrees.z = side * -12.0
		_runner_frame.add_child(fin)
		_directional_fins.append(fin)

	_dash_ring_material = StandardMaterial3D.new()
	_dash_ring_material.albedo_color = Color(0.12, 0.82, 1.0, 1.0)
	_dash_ring_material.metallic = 0.45
	_dash_ring_material.roughness = 0.16
	_dash_ring_material.emission_enabled = true
	_dash_ring_material.emission = Color(0.02, 0.48, 0.9, 1.0)
	_dash_ring_material.emission_energy_multiplier = 1.8
	_dash_ring_material.no_depth_test = true
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 1.2
	ring_mesh.outer_radius = 1.38
	ring_mesh.rings = 24
	ring_mesh.ring_segments = 8
	_dash_ring = MeshInstance3D.new()
	_dash_ring.name = "DashChargeRing"
	_dash_ring.mesh = ring_mesh
	_dash_ring.material_override = _dash_ring_material
	_dash_ring.position = Vector3(0.0, 0.0, 0.44)
	_dash_ring.rotation_degrees.x = 90.0
	_runner_frame.add_child(_dash_ring)
	_update_runner_frame(1.0, 0.0)


func _update_runner_frame(delta: float, steering: float) -> void:
	if not is_instance_valid(_runner_frame):
		return
	var horizontal_velocity := Vector3(velocity.x, 0.0, velocity.z)
	var travel_direction := heading
	if horizontal_velocity.length_squared() > 1.0:
		travel_direction = horizontal_velocity.normalized()
	var target_yaw := atan2(-travel_direction.x, -travel_direction.z)
	var response := 1.0 - exp(-VISUAL_TURN_RESPONSE * maxf(delta, 0.0))
	_runner_frame.rotation.y = lerp_angle(_runner_frame.rotation.y, target_yaw, response)
	var target_bank := 0.0 if _reduced_motion else steering * VISUAL_BANK_RADIANS
	_runner_frame.rotation.z = lerpf(_runner_frame.rotation.z, target_bank, response)
	var speed_ratio := clampf(horizontal_velocity.length() / maxf(dash_speed, 1.0), 0.0, 1.0)
	var fin_length := 1.0 if _reduced_motion else lerpf(0.88, 1.18, speed_ratio)
	for fin in _directional_fins:
		fin.scale.z = lerpf(fin.scale.z, fin_length, response)
	_update_dash_ring(response)


func _update_dash_ring(response: float) -> void:
	if not is_instance_valid(_dash_ring) or not is_instance_valid(_dash_ring_material):
		return
	var charge := _get_dash_visual_charge()
	var active_scale := 1.08 if _reduced_motion else 1.22
	var target_scale := active_scale if _dash_visual_active else lerpf(0.82, 1.0, charge)
	_dash_ring.scale = _dash_ring.scale.lerp(Vector3.ONE * target_scale, clampf(response, 0.0, 1.0))
	if _dash_visual_active:
		_dash_ring_material.albedo_color = Color(0.72, 0.98, 1.0, 1.0)
		_dash_ring_material.emission = Color(0.06, 0.72, 1.0, 1.0)
		_dash_ring_material.emission_energy_multiplier = 4.8 if not _reduced_motion else 2.2
	else:
		_dash_ring_material.albedo_color = Color(0.06, 0.22, 0.32, 1.0).lerp(Color(0.12, 0.82, 1.0, 1.0), charge)
		_dash_ring_material.emission = Color(0.01, 0.06, 0.12, 1.0).lerp(Color(0.02, 0.48, 0.9, 1.0), charge)
		_dash_ring_material.emission_energy_multiplier = lerpf(0.3, 1.8, charge)


func _get_dash_visual_charge() -> float:
	if not is_instance_valid(_dash_state) or _dash_state.is_active:
		return 1.0
	if not is_on_floor() and not _dash_state.air_dash_available:
		return 0.0
	if _dash_state.cooldown <= 0.0:
		return 1.0
	return 1.0 - clampf(_dash_state.cooldown_remaining / _dash_state.cooldown, 0.0, 1.0)


func _preserve_collision_momentum(intended_velocity: Vector3) -> void:
	var intended_speed := intended_velocity.length()
	if intended_speed < 1.0 or get_horizontal_speed() >= intended_speed * 0.74:
		return
	var blocking_normal := Vector3.ZERO
	for index in range(get_slide_collision_count()):
		var normal: Vector3 = get_slide_collision(index).get_normal()
		var planar_normal := Vector3(normal.x, 0.0, normal.z)
		if planar_normal.length_squared() > blocking_normal.length_squared():
			blocking_normal = planar_normal
	if blocking_normal.length_squared() < 0.16:
		return
	blocking_normal = blocking_normal.normalized()
	var deflected := intended_velocity.slide(blocking_normal)
	if deflected.length_squared() < intended_speed * intended_speed * 0.08:
		deflected = blocking_normal.cross(Vector3.UP)
		if deflected.dot(intended_velocity) < 0.0:
			deflected = -deflected
	deflected = deflected.normalized()
	var preserved_speed := intended_speed * 0.9
	velocity.x = deflected.x * preserved_speed
	velocity.z = deflected.z * preserved_speed
	heading = heading.slerp(deflected, 0.42).normalized()
	if is_instance_valid(_dash_state) and _dash_state.is_active:
		_dash_heading = heading
