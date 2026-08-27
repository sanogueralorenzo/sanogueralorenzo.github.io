extends Node3D

@onready var world = $World
@onready var ball = $RunnerBall
@onready var camera = $Camera3D
@onready var combat: CombatDirector = $CombatDirector
@onready var boundary: WorldBoundary = $WorldBoundary
@onready var info: Label = $HUD/Info
@onready var run_stats: Label = $HUD/RunStats
@onready var integrity_bar: ProgressBar = $HUD/IntegrityBar
@onready var experience_bar: ProgressBar = $HUD/ExperienceBar
@onready var level_label: Label = $HUD/LevelLabel
@onready var boundary_warning: Label = $HUD/BoundaryWarning
@onready var level_up_overlay: Control = $HUD/LevelUpOverlay
@onready var level_up_buttons: Array[Button] = [
	$HUD/LevelUpOverlay/ChoicePanel/Choices/Option1,
	$HUD/LevelUpOverlay/ChoicePanel/Choices/Option2,
	$HUD/LevelUpOverlay/ChoicePanel/Choices/Option3,
]
@onready var game_over_overlay: Control = $HUD/GameOverOverlay

var _current_upgrade_options: Array[StringName] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	ball.respawn(world.get_spawn_position())
	ball.dash_state_changed.connect(camera.set_dash_active)
	ball.integrity_changed.connect(_on_integrity_changed)
	ball.defeated.connect(_on_runner_defeated)
	combat.build_changed.connect(_on_build_changed)
	combat.level_up_requested.connect(_on_level_up_requested)
	for index in range(level_up_buttons.size()):
		level_up_buttons[index].pressed.connect(_choose_upgrade.bind(index))
	_on_integrity_changed(ball.integrity, ball.maximum_integrity)
	_on_build_changed(combat.build)
	camera.snap_to_target()


func _process(_delta: float) -> void:
	info.text = "OVER RUSH  •  %s\n%03d m/s  •  %s" % [
		world.get_region_name(ball.global_position.z),
		roundi(ball.get_horizontal_speed()),
		ball.get_dash_status(),
	]
	run_stats.text = "%s\n%d HOSTILES  •  %d CLEARED\nSEED %s" % [
		combat.get_formatted_time(),
		combat.get_enemy_count(),
		combat.enemies_defeated,
		str(world.generated_seed),
	]
	var warning_text := boundary.get_warning_text()
	boundary_warning.visible = not warning_text.is_empty()
	if boundary_warning.visible:
		boundary_warning.text = warning_text
		boundary_warning.modulate = Color(1.0, 1.0, 1.0, lerpf(0.68, 1.0, boundary.pressure))
		boundary_warning.add_theme_color_override(
			"font_color",
			Color(1.0, 0.58, 0.16) if boundary.pressure > 0.72 else Color(0.9, 1.0, 1.0)
		)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.keycode == KEY_R:
		get_tree().paused = false
		get_tree().reload_current_scene()
		return
	if level_up_overlay.visible and event.keycode >= KEY_1 and event.keycode <= KEY_3:
		_choose_upgrade(event.keycode - KEY_1)


func _on_integrity_changed(current: float, maximum: float) -> void:
	integrity_bar.max_value = maximum
	integrity_bar.value = current
	integrity_bar.tooltip_text = "Integrity: %d / %d" % [roundi(current), roundi(maximum)]


func _on_build_changed(build: RunBuild) -> void:
	experience_bar.max_value = build.experience_to_next
	experience_bar.value = build.experience
	level_label.text = "LEVEL %d" % build.level


func _on_level_up_requested(options: Array[StringName]) -> void:
	_current_upgrade_options = options
	level_up_overlay.visible = true
	for index in range(level_up_buttons.size()):
		var upgrade_id := options[index]
		var next_rank := combat.build.get_upgrade_rank(upgrade_id) + 1
		level_up_buttons[index].text = "%d   %s  •  RANK %d\n%s" % [
			index + 1,
			combat.build.get_upgrade_name(upgrade_id),
			next_rank,
			combat.build.get_upgrade_description(upgrade_id),
		]
	level_up_buttons[0].grab_focus()


func _choose_upgrade(index: int) -> void:
	if not level_up_overlay.visible or index < 0 or index >= _current_upgrade_options.size():
		return
	level_up_overlay.visible = false
	combat.choose_upgrade(index)


func _on_runner_defeated() -> void:
	combat.stop_run()
	game_over_overlay.visible = true
	get_tree().paused = true
