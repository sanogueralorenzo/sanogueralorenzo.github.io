extends Node3D

@onready var world = $World
@onready var ball = $RunnerBall
@onready var camera = $Camera3D
@onready var info: Label = $HUD/Info


func _ready() -> void:
	ball.respawn(world.get_spawn_position())
	camera.snap_to_target()


func _process(_delta: float) -> void:
	info.text = "OVER RUSH  •  SEED %s\n%03d m/s  •  3.2 km PROCEDURAL WORLD" % [
		str(world.generated_seed),
		roundi(ball.get_horizontal_speed()),
	]


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_R:
		get_tree().reload_current_scene()
