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
@onready var event_banner: Label = $HUD/EventBanner
@onready var apex_bar: ProgressBar = $HUD/ApexBar
@onready var apex_label: Label = $HUD/ApexLabel
@onready var level_up_overlay: Control = $HUD/LevelUpOverlay
@onready var level_up_title: Label = $HUD/LevelUpOverlay/ChoicePanel/Choices/Title
@onready var level_up_prompt: Label = $HUD/LevelUpOverlay/ChoicePanel/Choices/Prompt
@onready var level_up_buttons: Array[Button] = [
	$HUD/LevelUpOverlay/ChoicePanel/Choices/Option1,
	$HUD/LevelUpOverlay/ChoicePanel/Choices/Option2,
	$HUD/LevelUpOverlay/ChoicePanel/Choices/Option3,
]
@onready var game_over_overlay: Control = $HUD/GameOverOverlay
@onready var game_over_message: Label = $HUD/GameOverOverlay/Message
@onready var victory_overlay: Control = $HUD/VictoryOverlay
@onready var victory_message: Label = $HUD/VictoryOverlay/Message

var _current_upgrade_options: Array[StringName] = []
var _phase_name := "BREAKAWAY"
var _event_tween: Tween


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	ball.respawn(world.get_spawn_position())
	ball.dash_state_changed.connect(camera.set_dash_active)
	ball.integrity_changed.connect(_on_integrity_changed)
	ball.defeated.connect(_on_runner_defeated)
	combat.build_changed.connect(_on_build_changed)
	combat.level_up_requested.connect(_on_level_up_requested)
	combat.phase_changed.connect(_on_phase_changed)
	combat.event_announced.connect(_on_event_announced)
	combat.apex_health_changed.connect(_on_apex_health_changed)
	combat.run_victory.connect(_on_run_victory)
	combat.run_failed.connect(_on_run_failed)
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
	run_stats.text = "%s  •  %s\n%d HOSTILES  •  %d CLEARED\nSEED %s" % [
		combat.get_formatted_time(),
		_phase_name,
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
	level_label.text = "LEVEL %d" % build.level if build.core_path.is_empty() else "LEVEL %d  •  %s" % [build.level, build.get_build_name()]


func _on_level_up_requested(options: Array[StringName]) -> void:
	_current_upgrade_options = options
	if is_instance_valid(_event_tween):
		_event_tween.kill()
	event_banner.visible = false
	level_up_overlay.visible = true
	if combat.build.core_path.is_empty():
		level_up_title.text = "CHOOSE YOUR ENGINE"
		level_up_prompt.text = "Commit to a combat geometry for this run"
	else:
		level_up_title.text = "%s EVOLVES" % combat.build.get_build_name()
		level_up_prompt.text = "Deepen this build without collapsing into another path"
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
	game_over_message.text = "RUN ENDED\n\n%s  •  LEVEL %d  •  %d CLEARED\n\nPRESS R TO BREAK THROUGH AGAIN" % [
		combat.get_formatted_time(),
		combat.build.level,
		combat.enemies_defeated,
	]
	game_over_overlay.visible = true
	get_tree().paused = true


func _on_phase_changed(_phase_id: StringName, phase_name: String) -> void:
	_phase_name = phase_name


func _on_event_announced(title: String, subtitle: String) -> void:
	if is_instance_valid(_event_tween):
		_event_tween.kill()
	event_banner.text = "%s\n%s" % [title, subtitle]
	event_banner.visible = true
	event_banner.modulate = Color(1.0, 1.0, 1.0, 0.0)
	event_banner.scale = Vector2(0.94, 0.94)
	event_banner.pivot_offset = event_banner.size * 0.5
	_event_tween = create_tween()
	_event_tween.tween_property(event_banner, "modulate:a", 1.0, 0.22)
	_event_tween.parallel().tween_property(event_banner, "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_event_tween.tween_interval(2.2)
	_event_tween.tween_property(event_banner, "modulate:a", 0.0, 0.5)
	_event_tween.tween_callback(func() -> void: event_banner.visible = false)


func _on_apex_health_changed(current: float, maximum: float) -> void:
	apex_bar.max_value = maximum
	apex_bar.value = current
	apex_bar.visible = current > 0.0
	apex_label.visible = current > 0.0
	apex_label.text = "THE APEX  •  %d%%" % roundi(current / maxf(maximum, 1.0) * 100.0)


func _on_run_victory() -> void:
	victory_message.text = "APEX BROKEN\n\n%s  •  LEVEL %d  •  %d CLEARED\n\nPRESS R TO OVERRUN AGAIN" % [
		combat.get_formatted_time(),
		combat.build.level,
		combat.enemies_defeated,
	]
	victory_overlay.visible = true
	get_tree().paused = true


func _on_run_failed(reason: String) -> void:
	game_over_message.text = "%s\n\n20:00  •  LEVEL %d  •  %d CLEARED\n\nPRESS R TO BREAK THROUGH AGAIN" % [
		reason,
		combat.build.level,
		combat.enemies_defeated,
	]
	game_over_overlay.visible = true
	get_tree().paused = true
