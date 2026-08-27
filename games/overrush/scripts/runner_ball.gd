extends CharacterBody3D

signal dash_state_changed(active: bool)
signal integrity_changed(current: float, maximum: float)
signal defeated

const DashStateMachine = preload("res://scripts/dash_state.gd")

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


func _ready() -> void:
	_dash_state = DashStateMachine.new(dash_minimum_duration, dash_maximum_duration, dash_cooldown)
	_ball_material = ball_mesh.get_active_material(0).duplicate()
	ball_mesh.material_override = _ball_material
	integrity = maximum_integrity
	integrity_changed.emit(integrity, maximum_integrity)


func _physics_process(delta: float) -> void:
	_damage_invulnerability_remaining = maxf(0.0, _damage_invulnerability_remaining - delta)
	_damage_flash_remaining = maxf(0.0, _damage_flash_remaining - delta)
	_update_ball_material()
	var grounded := is_on_floor()
	var dash_pressed := _is_dash_pressed()
	var dash_event := _dash_state.step(delta, dash_pressed, dash_pressed and not _dash_was_pressed, grounded)
	_dash_was_pressed = dash_pressed
	if dash_event == DashStateMachine.Event.STARTED:
		_begin_dash()
	elif dash_event == DashStateMachine.Event.ENDED:
		_end_dash()

	var steering := 0.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		steering += 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		steering -= 1.0
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
		_check_fall()
		return

	var target_speed := cruise_speed
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		target_speed = boost_speed
	elif Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
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
		if Input.is_key_pressed(KEY_SPACE):
			velocity.y = jump_velocity
	else:
		velocity.y -= _gravity * 2.35 * delta

	var intended_horizontal_velocity := Vector3(velocity.x, 0.0, velocity.z)
	move_and_slide()
	_preserve_collision_momentum(intended_horizontal_velocity)
	_roll_visual(delta)
	_check_fall()


func respawn(at_position: Vector3) -> void:
	spawn_position = at_position
	global_position = at_position
	velocity = heading * cruise_speed * 0.35
	if is_instance_valid(_dash_state):
		_dash_state.reset()
		_set_dash_visuals(false)


func get_horizontal_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()


func apply_boundary_heading(guided_heading: Vector3) -> void:
	heading = Vector3(guided_heading.x, 0.0, guided_heading.z).normalized()
	if is_instance_valid(_dash_state) and _dash_state.is_active:
		_dash_heading = heading


func grant_damage_immunity(duration: float) -> void:
	_damage_invulnerability_remaining = maxf(_damage_invulnerability_remaining, duration)


func take_damage(amount: float) -> void:
	if amount <= 0.0 or integrity <= 0.0 or _damage_invulnerability_remaining > 0.0:
		return
	integrity = maxf(0.0, integrity - amount)
	_damage_invulnerability_remaining = damage_invulnerability
	_damage_flash_remaining = 0.13
	integrity_changed.emit(integrity, maximum_integrity)
	if integrity <= 0.0:
		defeated.emit()


func increase_maximum_integrity(amount: float, repair_amount: float) -> void:
	maximum_integrity += maxf(0.0, amount)
	integrity = minf(maximum_integrity, integrity + maxf(0.0, repair_amount))
	integrity_changed.emit(integrity, maximum_integrity)


func apply_integrity_multiplier(multiplier: float) -> void:
	maximum_integrity = maxf(1.0, maximum_integrity * maxf(0.1, multiplier))
	integrity = minf(integrity, maximum_integrity)
	integrity_changed.emit(integrity, maximum_integrity)


func is_dashing() -> bool:
	return _dash_state != null and _dash_state.is_active


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
	dash_trail.emitting = active
	dash_light.light_energy = 3.2 if active else 0.0


func _update_ball_material() -> void:
	if not is_instance_valid(_ball_material):
		return
	if _damage_flash_remaining > 0.0:
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
	return Input.is_key_pressed(KEY_SHIFT) or Input.is_key_pressed(KEY_ALT)


func _check_fall() -> void:
	if global_position.y < -180.0:
		respawn(spawn_position)


func _roll_visual(delta: float) -> void:
	var horizontal_velocity := Vector3(velocity.x, 0.0, velocity.z)
	if horizontal_velocity.length_squared() < 0.01:
		return
	var roll_axis := horizontal_velocity.normalized().cross(Vector3.UP)
	ball_mesh.rotate(roll_axis, horizontal_velocity.length() * delta / 1.2)


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
