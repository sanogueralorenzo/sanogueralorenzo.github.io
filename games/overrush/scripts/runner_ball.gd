extends CharacterBody3D

@export var cruise_speed: float = 58.0
@export var boost_speed: float = 88.0
@export var brake_speed: float = 24.0
@export var ground_acceleration: float = 52.0
@export var air_control: float = 0.28
@export var turn_speed: float = 1.75
@export var jump_velocity: float = 17.0

@onready var ball_mesh: MeshInstance3D = $BallMesh

var heading := Vector3.FORWARD
var spawn_position := Vector3.ZERO
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")


func _physics_process(delta: float) -> void:
	var steering := 0.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		steering += 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		steering -= 1.0
	heading = heading.rotated(Vector3.UP, steering * turn_speed * delta).normalized()

	var target_speed := cruise_speed
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		target_speed = boost_speed
	elif Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		target_speed = brake_speed

	var horizontal_velocity := Vector3(velocity.x, 0.0, velocity.z)
	var acceleration := ground_acceleration if is_on_floor() else ground_acceleration * air_control
	horizontal_velocity = horizontal_velocity.move_toward(heading * target_speed, acceleration * delta)
	velocity.x = horizontal_velocity.x
	velocity.z = horizontal_velocity.z

	if is_on_floor():
		if velocity.y < 0.0:
			velocity.y = -1.5
		if Input.is_key_pressed(KEY_SPACE):
			velocity.y = jump_velocity
	else:
		velocity.y -= _gravity * 2.35 * delta

	move_and_slide()
	_roll_visual(delta)
	if global_position.y < -180.0:
		respawn(spawn_position)


func respawn(at_position: Vector3) -> void:
	spawn_position = at_position
	global_position = at_position
	velocity = heading * cruise_speed * 0.35


func get_horizontal_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()


func _roll_visual(delta: float) -> void:
	var horizontal_velocity := Vector3(velocity.x, 0.0, velocity.z)
	if horizontal_velocity.length_squared() < 0.01:
		return
	var roll_axis := horizontal_velocity.normalized().cross(Vector3.UP)
	ball_mesh.rotate(roll_axis, horizontal_velocity.length() * delta / 1.2)
