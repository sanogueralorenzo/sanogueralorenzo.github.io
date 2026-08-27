extends Node3D

const ProgressProfileModel = preload("res://scripts/progress_profile.gd")
const RunProtocolCatalog = preload("res://scripts/run_protocols.gd")
const RunOnboardingModel = preload("res://scripts/run_onboarding.gd")
const ApexCatalogModel = preload("res://scripts/apex_catalog.gd")
const InputBindings = preload("res://scripts/input_bindings.gd")

@onready var world = $World
@onready var ball = $RunnerBall
@onready var camera = $Camera3D
@onready var combat: CombatDirector = $CombatDirector
@onready var audio: OverrushAudioDirector = $AudioDirector
@onready var boundary: WorldBoundary = $WorldBoundary
@onready var info: Label = $HUD/Info
@onready var run_stats: Label = $HUD/RunStats
@onready var controls: Label = $HUD/Controls
@onready var integrity_bar: ProgressBar = $HUD/IntegrityBar
@onready var integrity_label: Label = $HUD/IntegrityLabel
@onready var damage_vignette: ColorRect = $HUD/DamageVignette
@onready var damage_direction: Label = $HUD/DamageDirection
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
@onready var reroll_button: Button = $HUD/LevelUpOverlay/ChoicePanel/Choices/DraftControls/Reroll
@onready var banish_button: Button = $HUD/LevelUpOverlay/ChoicePanel/Choices/DraftControls/Banish
@onready var game_over_overlay: Control = $HUD/GameOverOverlay
@onready var game_over_message: Label = $HUD/GameOverOverlay/Message
@onready var game_over_retry: Button = $HUD/GameOverOverlay/Retry
@onready var game_over_copy_report: Button = $HUD/GameOverOverlay/CopyReport
@onready var game_over_feedback_prompt: Label = $HUD/GameOverOverlay/FeedbackPrompt
@onready var game_over_feedback_buttons: Array[Button] = [
	$HUD/GameOverOverlay/FeedbackChoices/No,
	$HUD/GameOverOverlay/FeedbackChoices/Maybe,
	$HUD/GameOverOverlay/FeedbackChoices/Yes,
]
@onready var victory_overlay: Control = $HUD/VictoryOverlay
@onready var victory_message: Label = $HUD/VictoryOverlay/Message
@onready var victory_retry: Button = $HUD/VictoryOverlay/Retry
@onready var victory_copy_report: Button = $HUD/VictoryOverlay/CopyReport
@onready var victory_feedback_prompt: Label = $HUD/VictoryOverlay/FeedbackPrompt
@onready var victory_feedback_buttons: Array[Button] = [
	$HUD/VictoryOverlay/FeedbackChoices/No,
	$HUD/VictoryOverlay/FeedbackChoices/Maybe,
	$HUD/VictoryOverlay/FeedbackChoices/Yes,
]
@onready var start_overlay: Control = $HUD/StartOverlay
@onready var profile_summary: Label = $HUD/StartOverlay/LaunchPanel/Content/ProfileSummary
@onready var mastery_summary: Label = $HUD/StartOverlay/LaunchPanel/Content/MasterySummary
@onready var protocol_name: Label = $HUD/StartOverlay/LaunchPanel/Content/ProtocolName
@onready var protocol_description: Label = $HUD/StartOverlay/LaunchPanel/Content/ProtocolDescription
@onready var protocol_reward: Label = $HUD/StartOverlay/LaunchPanel/Content/ProtocolReward
@onready var next_unlock: Label = $HUD/StartOverlay/LaunchPanel/Content/NextUnlock
@onready var previous_protocol: Button = $HUD/StartOverlay/LaunchPanel/Content/ProtocolControls/Previous
@onready var select_hint: Label = $HUD/StartOverlay/LaunchPanel/Content/ProtocolControls/SelectHint
@onready var next_protocol: Button = $HUD/StartOverlay/LaunchPanel/Content/ProtocolControls/Next
@onready var launch_button: Button = $HUD/StartOverlay/LaunchPanel/Content/Launch
@onready var launch_hint: Label = $HUD/StartOverlay/LaunchPanel/Content/LaunchHint
@onready var accessibility_button: Button = $HUD/StartOverlay/LaunchPanel/Content/Accessibility
@onready var pause_overlay: Control = $HUD/PauseOverlay
@onready var pause_summary: Label = $HUD/PauseOverlay/PausePanel/Content/Summary
@onready var pause_loadout: Label = $HUD/PauseOverlay/PausePanel/Content/Loadout
@onready var pause_resume_button: Button = $HUD/PauseOverlay/PausePanel/Content/Resume
@onready var pause_settings_button: Button = $HUD/PauseOverlay/PausePanel/Content/Settings
@onready var pause_restart_button: Button = $HUD/PauseOverlay/PausePanel/Content/Restart
@onready var pause_restart_warning: Label = $HUD/PauseOverlay/PausePanel/Content/RestartWarning
@onready var pause_hint: Label = $HUD/PauseOverlay/PausePanel/Content/Hint
@onready var settings_overlay: Control = $HUD/SettingsOverlay
@onready var reduced_motion_toggle: CheckButton = $HUD/SettingsOverlay/SettingsPanel/Content/ReducedMotion
@onready var high_contrast_toggle: CheckButton = $HUD/SettingsOverlay/SettingsPanel/Content/HighContrast
@onready var guidance_toggle: CheckButton = $HUD/SettingsOverlay/SettingsPanel/Content/Guidance
@onready var replay_guidance_button: Button = $HUD/SettingsOverlay/SettingsPanel/Content/ReplayGuidance
@onready var settings_back_button: Button = $HUD/SettingsOverlay/SettingsPanel/Content/Back
@onready var tutorial_card: Label = $HUD/TutorialCard
@onready var master_volume_slider: HSlider = $HUD/SettingsOverlay/SettingsPanel/Content/MasterAudio/Slider
@onready var master_volume_label: Label = $HUD/SettingsOverlay/SettingsPanel/Content/MasterAudio/Value
@onready var music_volume_slider: HSlider = $HUD/SettingsOverlay/SettingsPanel/Content/MusicAudio/Slider
@onready var music_volume_label: Label = $HUD/SettingsOverlay/SettingsPanel/Content/MusicAudio/Value
@onready var effects_volume_slider: HSlider = $HUD/SettingsOverlay/SettingsPanel/Content/EffectsAudio/Slider
@onready var effects_volume_label: Label = $HUD/SettingsOverlay/SettingsPanel/Content/EffectsAudio/Value

var _current_upgrade_options: Array[StringName] = []
var _phase_name := "BREAKAWAY"
var _event_tween: Tween
var _profile: ProgressProfile = ProgressProfileModel.new()
var _available_protocols: Array[StringName] = []
var _protocol_index := 0
var _persistence_enabled := true
var _run_started := false
var _run_recorded := false
var _run_result: Dictionary = {}
var _onboarding: RunOnboarding = RunOnboardingModel.new()
var _draft_prompt := ""
var _banish_mode := false
var _using_gamepad := false
var _settings_return_to_pause := false
var _restart_armed := false
var _damage_feedback_tween: Tween
var _feedback_stage := &"intent"
var _feedback_tag_options: Array[String] = []


func _enter_tree() -> void:
	InputBindings.ensure_actions()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = true
	_persistence_enabled = DisplayServer.get_name() != "headless" and not has_meta("overrush_disable_persistence")
	ball.respawn(world.get_spawn_position())
	ball.dash_state_changed.connect(camera.set_dash_active)
	ball.dash_state_changed.connect(audio.play_dash)
	ball.integrity_changed.connect(_on_integrity_changed)
	ball.damaged.connect(_on_runner_damaged)
	ball.defeated.connect(_on_runner_defeated)
	combat.build_changed.connect(_on_build_changed)
	combat.level_up_requested.connect(_on_level_up_requested)
	combat.upgrade_options_refreshed.connect(_on_upgrade_options_refreshed)
	combat.phase_changed.connect(_on_phase_changed)
	combat.event_announced.connect(_on_event_announced)
	combat.apex_health_changed.connect(_on_apex_health_changed)
	combat.run_victory.connect(_on_run_victory)
	combat.run_failed.connect(_on_run_failed)
	combat.enemy_defeated_feedback.connect(audio.play_enemy_defeat)
	combat.enemy_hit_feedback.connect(audio.play_enemy_hit)
	combat.experience_collected_feedback.connect(audio.play_pickup)
	combat.integrity_collected_feedback.connect(audio.play_repair)
	combat.attack_warning_feedback.connect(audio.play_attack_warning)
	for index in range(level_up_buttons.size()):
		level_up_buttons[index].pressed.connect(_choose_upgrade.bind(index))
	reroll_button.pressed.connect(_reroll_upgrade_options)
	banish_button.pressed.connect(_toggle_banish_mode)
	previous_protocol.pressed.connect(_cycle_protocol.bind(-1))
	next_protocol.pressed.connect(_cycle_protocol.bind(1))
	launch_button.pressed.connect(begin_run)
	accessibility_button.pressed.connect(_open_settings.bind(false))
	pause_resume_button.pressed.connect(_resume_run)
	pause_settings_button.pressed.connect(_open_settings.bind(true))
	pause_restart_button.pressed.connect(_request_restart)
	game_over_retry.pressed.connect(_restart_scene)
	victory_retry.pressed.connect(_restart_scene)
	game_over_copy_report.pressed.connect(_copy_latest_playtest_report.bind(game_over_copy_report))
	victory_copy_report.pressed.connect(_copy_latest_playtest_report.bind(victory_copy_report))
	for index in range(ProgressProfileModel.REPLAY_INTENTS.size()):
		game_over_feedback_buttons[index].pressed.connect(_on_feedback_choice.bind(index))
		victory_feedback_buttons[index].pressed.connect(_on_feedback_choice.bind(index))
	settings_back_button.pressed.connect(_close_settings)
	reduced_motion_toggle.toggled.connect(_on_visual_accessibility_changed)
	high_contrast_toggle.toggled.connect(_on_visual_accessibility_changed)
	guidance_toggle.toggled.connect(_on_guidance_toggled)
	replay_guidance_button.pressed.connect(_replay_guidance)
	master_volume_slider.value_changed.connect(_on_audio_levels_changed)
	music_volume_slider.value_changed.connect(_on_audio_levels_changed)
	effects_volume_slider.value_changed.connect(_on_audio_levels_changed)
	_on_integrity_changed(ball.integrity, ball.maximum_integrity)
	_on_build_changed(combat.build)
	camera.snap_to_target()
	if _persistence_enabled:
		_profile.load()
	_apply_accessibility()
	_apply_audio_levels()
	_refresh_settings()
	_available_protocols = _profile.get_unlocked_protocols()
	_protocol_index = maxi(0, _available_protocols.find(_profile.selected_protocol))
	_refresh_launch_screen()
	_refresh_input_prompts()
	launch_button.grab_focus()
	if DisplayServer.get_name() == "headless" and not has_meta("overrush_manual_start"):
		call_deferred("begin_run", RunProtocolCatalog.STANDARD)


func _process(_delta: float) -> void:
	var catalyst_status := combat.get_catalyst_status()
	var catalyst_line := "" if catalyst_status.is_empty() else "\n%s" % catalyst_status
	info.text = "OVER RUSH  •  %s\n%03d m/s  •  %s%s" % [
		world.get_region_name(ball.global_position.z),
		roundi(ball.get_horizontal_speed()),
		ball.get_dash_status(),
		catalyst_line,
	]
	run_stats.text = "%s  •  %s\n%s\n%d HOSTILES  •  %d CLEARED" % [
		combat.get_formatted_time(),
		_phase_name,
		combat.get_objective_status(),
		combat.get_enemy_count(),
		combat.enemies_defeated,
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
	_update_onboarding(_delta)


func _input(event: InputEvent) -> void:
	if InputBindings.is_gamepad_event(event) and not _using_gamepad:
		_using_gamepad = true
		_refresh_input_prompts()
	elif InputBindings.is_keyboard_or_mouse_event(event) and _using_gamepad:
		_using_gamepad = false
		_refresh_input_prompts()
	if start_overlay.visible and event.is_action_pressed(InputBindings.MENU_LEFT):
		_cycle_protocol(-1)
		get_viewport().set_input_as_handled()
	elif start_overlay.visible and event.is_action_pressed(InputBindings.MENU_RIGHT):
		_cycle_protocol(1)
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if settings_overlay.visible:
		if event.is_action_pressed(InputBindings.PAUSE):
			_close_settings()
			get_viewport().set_input_as_handled()
		return
	if pause_overlay.visible:
		if event.is_action_pressed(InputBindings.PAUSE):
			_resume_run()
			get_viewport().set_input_as_handled()
		return
	if game_over_overlay.visible or victory_overlay.visible:
		if event.is_action_pressed(InputBindings.RETRY):
			_restart_scene()
			get_viewport().set_input_as_handled()
		return
	if start_overlay.visible:
		if event.is_action_pressed(InputBindings.CONFIRM):
			begin_run()
			get_viewport().set_input_as_handled()
		return
	if level_up_overlay.visible:
		if event.is_action_pressed(InputBindings.REROLL):
			_reroll_upgrade_options()
		elif event.is_action_pressed(InputBindings.BANISH):
			_toggle_banish_mode()
		elif event.is_action_pressed(InputBindings.PAUSE) and _banish_mode:
			_toggle_banish_mode()
		elif event is InputEventKey and event.pressed and not event.echo and event.keycode >= KEY_1 and event.keycode <= KEY_3:
			_choose_upgrade(event.keycode - KEY_1)
		return
	if _run_started and event.is_action_pressed(InputBindings.PAUSE):
		_pause_run()
		get_viewport().set_input_as_handled()


func _on_integrity_changed(current: float, maximum: float) -> void:
	integrity_bar.max_value = maximum
	integrity_bar.value = current
	integrity_bar.tooltip_text = "Integrity: %d / %d" % [roundi(current), roundi(maximum)]
	integrity_label.text = "INTEGRITY  %d / %d" % [roundi(current), roundi(maximum)]
	var ratio := current / maxf(maximum, 1.0)
	if ratio <= 0.25:
		integrity_label.add_theme_color_override("font_color", Color(1.0, 0.32, 0.2))
	elif ratio <= 0.5:
		integrity_label.add_theme_color_override("font_color", Color(1.0, 0.78, 0.24))
	else:
		integrity_label.add_theme_color_override("font_color", Color(0.76, 1.0, 0.96))


func _on_runner_damaged(amount: float, source_direction: Vector3, integrity_ratio: float, _source_id: StringName) -> void:
	audio.play_hurt(amount)
	_show_damage_feedback(amount, source_direction, integrity_ratio)


func _show_damage_feedback(amount: float, source_direction: Vector3, integrity_ratio: float) -> void:
	if is_instance_valid(_damage_feedback_tween):
		_damage_feedback_tween.kill()
	var forward := Vector3(ball.heading.x, 0.0, ball.heading.z).normalized()
	if forward.length_squared() < 0.1:
		forward = Vector3.FORWARD
	var right := Vector3(-forward.z, 0.0, forward.x)
	var screen_direction := Vector2(source_direction.dot(right), -source_direction.dot(forward))
	if screen_direction.length_squared() < 0.01:
		screen_direction = Vector2.UP
	else:
		screen_direction = screen_direction.normalized()
	var screen_center := get_viewport().get_visible_rect().size * 0.5
	damage_direction.position = screen_center + screen_direction * 170.0 - damage_direction.size * 0.5
	damage_direction.text = "%s\n-%d" % [_get_damage_arrow(screen_direction), roundi(amount)]
	damage_direction.visible = true
	damage_direction.modulate = Color.WHITE
	damage_direction.scale = Vector2.ONE if _profile.reduced_motion else Vector2.ONE * 0.82
	damage_vignette.visible = true
	var severity := clampf(amount / maxf(ball.maximum_integrity * 0.25, 1.0), 0.25, 1.0)
	var danger := 1.0 - clampf(integrity_ratio, 0.0, 1.0)
	var minimum_alpha := 0.025 if _profile.reduced_motion else 0.07
	var maximum_alpha := 0.065 if _profile.reduced_motion else 0.17
	damage_vignette.color = Color(0.82, 0.015, 0.025, lerpf(minimum_alpha, maximum_alpha, maxf(severity, danger)))
	_damage_feedback_tween = create_tween().set_parallel(true)
	_damage_feedback_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	if not _profile.reduced_motion:
		_damage_feedback_tween.tween_property(damage_direction, "scale", Vector2.ONE, 0.1).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_damage_feedback_tween.tween_property(damage_direction, "modulate:a", 0.0, 0.48).set_delay(0.16)
	_damage_feedback_tween.tween_property(damage_vignette, "color:a", 0.0, 0.5).set_delay(0.1)
	_damage_feedback_tween.chain().tween_callback(_hide_damage_feedback)


func _hide_damage_feedback() -> void:
	damage_direction.visible = false
	damage_vignette.visible = false


func _get_damage_arrow(screen_direction: Vector2) -> String:
	var sector := wrapi(roundi(screen_direction.angle() / (PI / 4.0)), 0, 8)
	return ["→", "↘", "↓", "↙", "←", "↖", "↑", "↗"][sector]


func _on_build_changed(build: RunBuild) -> void:
	experience_bar.max_value = build.experience_to_next
	experience_bar.value = build.experience
	level_label.text = "LEVEL %d" % build.level if build.core_path.is_empty() else "LEVEL %d  •  %s" % [build.level, build.get_build_name()]


func _on_level_up_requested(options: Array[StringName]) -> void:
	audio.play_level_up()
	if is_instance_valid(_event_tween):
		_event_tween.kill()
	event_banner.visible = false
	tutorial_card.visible = false
	level_up_overlay.visible = true
	var offers_evolution := false
	var offers_catalyst := false
	var offers_arsenal := false
	for upgrade_id in options:
		if combat.build.is_evolution_upgrade(upgrade_id):
			offers_evolution = true
		if combat.build.is_catalyst_upgrade(upgrade_id):
			offers_catalyst = true
		if combat.build.is_arsenal_upgrade(upgrade_id):
			offers_arsenal = true
	if combat.build.core_path.is_empty():
		level_up_title.text = "CHOOSE YOUR ENGINE"
		_draft_prompt = "Commit to a combat geometry for this run"
	elif offers_evolution:
		level_up_title.text = "EVOLVE %s" % combat.build.get_build_name()
		_draft_prompt = "Choose one exclusive geometry, or defer the fork with a standard upgrade"
	elif offers_arsenal:
		level_up_title.text = "CHOOSE YOUR ARSENAL"
		_draft_prompt = "Lock one independent weapon that combines with your engine and Drive"
	elif offers_catalyst:
		level_up_title.text = "TUNE YOUR DRIVE"
		_draft_prompt = "Choose one movement rhythm  •  Every catalyst has a real downside"
	else:
		level_up_title.text = "%s EVOLVES" % combat.build.get_build_name()
		_draft_prompt = "Deepen this build without collapsing into another path"
	_banish_mode = false
	_render_upgrade_options(options)


func _on_upgrade_options_refreshed(options: Array[StringName]) -> void:
	_banish_mode = false
	audio.play_pickup(1)
	_render_upgrade_options(options)


func _render_upgrade_options(options: Array[StringName]) -> void:
	_current_upgrade_options = options
	level_up_prompt.text = _draft_prompt
	for index in range(level_up_buttons.size()):
		var button := level_up_buttons[index]
		var has_option := index < options.size()
		button.visible = has_option
		button.disabled = not has_option
		if not has_option:
			continue
		var upgrade_id := options[index]
		var next_rank := combat.build.get_upgrade_rank(upgrade_id) + 1
		var rank_label := "RANK %d" % next_rank
		if combat.build.core_path.is_empty():
			rank_label = "COMMIT"
		elif combat.build.is_evolution_upgrade(upgrade_id) or combat.build.is_catalyst_upgrade(upgrade_id) or combat.build.is_arsenal_upgrade(upgrade_id):
			rank_label = "EXCLUSIVE"
		button.text = "%d   %s  •  %s\n%s  •  %s\n%s" % [
			index + 1,
			combat.build.get_upgrade_name(upgrade_id),
			rank_label,
			combat.build.get_upgrade_kind_label(upgrade_id),
			combat.build.get_upgrade_effect_preview(upgrade_id),
			combat.build.get_upgrade_description(upgrade_id),
		]
		var accent := _get_upgrade_accent(combat.build.get_upgrade_family(upgrade_id))
		button.add_theme_color_override("font_color", accent)
		button.add_theme_color_override("font_hover_color", accent.lightened(0.16))
		button.add_theme_color_override("font_focus_color", accent.lightened(0.16))
	_refresh_draft_controls()
	if not options.is_empty():
		level_up_buttons[0].grab_focus()


func _refresh_draft_controls() -> void:
	var can_reroll := (
		combat.rerolls_remaining > 0
		and combat.build.has_alternative_upgrade_options(_current_upgrade_options)
	)
	var reroll_key := "Y" if _using_gamepad else "Q"
	var banish_key := "X" if _using_gamepad else "B"
	reroll_button.text = "%s  REROLL  •  %d" % [reroll_key, combat.rerolls_remaining]
	reroll_button.disabled = not can_reroll
	var can_banish := false
	for upgrade_id in _current_upgrade_options:
		if combat.build.can_banish_upgrade(upgrade_id):
			can_banish = true
			break
	banish_button.text = "%s  CANCEL BANISH" % banish_key if _banish_mode else "%s  BANISH  •  %d" % [banish_key, combat.banishes_remaining]
	banish_button.disabled = combat.banishes_remaining <= 0 or not can_banish


func _reroll_upgrade_options() -> void:
	if reroll_button.disabled:
		level_up_prompt.text = "No alternate draft is available from this pool"
		return
	_banish_mode = false
	if not combat.reroll_upgrade_options():
		level_up_prompt.text = "No alternate draft is available from this pool"
	_refresh_draft_controls()


func _toggle_banish_mode() -> void:
	if banish_button.disabled:
		return
	_banish_mode = not _banish_mode
	level_up_prompt.text = "BANISH ACTIVE  •  Choose one standard upgrade to remove for this run" if _banish_mode else _draft_prompt
	_refresh_draft_controls()
	if not _current_upgrade_options.is_empty():
		level_up_buttons[0].grab_focus()


func _choose_upgrade(index: int) -> void:
	if not level_up_overlay.visible or index < 0 or index >= _current_upgrade_options.size():
		return
	if _banish_mode:
		var upgrade_id := _current_upgrade_options[index]
		if combat.build.is_evolution_upgrade(upgrade_id):
			level_up_prompt.text = "Evolution forks cannot be banished"
			return
		if not combat.banish_upgrade_option(index):
			level_up_prompt.text = "Keep at least three standard upgrades in the active pool"
		_refresh_draft_controls()
		return
	level_up_overlay.visible = false
	combat.choose_upgrade(index)
	tutorial_card.visible = not _onboarding.is_complete()


func _on_runner_defeated() -> void:
	audio.play_defeat()
	combat.stop_run()
	level_up_overlay.visible = false
	var result := _record_run_progress(false)
	game_over_message.text = _format_run_recap("RUN ENDED", result)
	game_over_overlay.visible = true
	get_tree().paused = true
	game_over_retry.grab_focus()


func _on_phase_changed(_phase_id: StringName, phase_name: String) -> void:
	_phase_name = phase_name
	audio.set_phase(_phase_id)


func _on_event_announced(title: String, subtitle: String) -> void:
	audio.play_phase_event()
	if is_instance_valid(_event_tween):
		_event_tween.kill()
	event_banner.text = "%s\n%s" % [title, subtitle]
	event_banner.visible = true
	event_banner.modulate = Color(1.0, 1.0, 1.0, 0.0)
	event_banner.scale = Vector2.ONE if _profile.reduced_motion else Vector2(0.94, 0.94)
	event_banner.pivot_offset = event_banner.size * 0.5
	_event_tween = create_tween()
	_event_tween.tween_property(event_banner, "modulate:a", 1.0, 0.22)
	if not _profile.reduced_motion:
		_event_tween.parallel().tween_property(event_banner, "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_event_tween.tween_interval(2.2)
	_event_tween.tween_property(event_banner, "modulate:a", 0.0, 0.5)
	_event_tween.tween_callback(func() -> void: event_banner.visible = false)


func _on_apex_health_changed(current: float, maximum: float) -> void:
	apex_bar.max_value = maximum
	apex_bar.value = current
	apex_bar.visible = current > 0.0
	apex_label.visible = current > 0.0
	apex_label.text = "%s  •  %d%%" % [
		combat.get_active_apex_title(),
		roundi(current / maxf(maximum, 1.0) * 100.0),
	]


func _on_run_victory() -> void:
	audio.play_victory()
	level_up_overlay.visible = false
	var result := _record_run_progress(true)
	victory_message.text = _format_run_recap("APEX BROKEN", result)
	_reset_replay_feedback(victory_feedback_prompt, victory_feedback_buttons)
	victory_overlay.visible = true
	get_tree().paused = true
	victory_retry.grab_focus()


func _on_run_failed(reason: String) -> void:
	audio.play_defeat()
	level_up_overlay.visible = false
	var result := _record_run_progress(false)
	game_over_message.text = _format_run_recap(reason, result)
	_reset_replay_feedback(game_over_feedback_prompt, game_over_feedback_buttons)
	game_over_overlay.visible = true
	get_tree().paused = true
	game_over_retry.grab_focus()


func begin_run(protocol_id: StringName = &"") -> void:
	if _run_started:
		return
	var chosen_protocol := protocol_id
	if chosen_protocol.is_empty():
		chosen_protocol = _available_protocols[_protocol_index]
	if not _profile.select_protocol(chosen_protocol):
		chosen_protocol = RunProtocolCatalog.STANDARD
		_profile.select_protocol(chosen_protocol)
	_save_profile()
	settings_overlay.visible = false
	pause_overlay.visible = false
	start_overlay.visible = false
	_run_started = true
	_settings_return_to_pause = false
	_cancel_restart_confirmation()
	_onboarding.reset(_profile.onboarding_completed or not _profile.guidance_enabled)
	tutorial_card.text = _onboarding.get_message(_using_gamepad)
	tutorial_card.visible = not _onboarding.is_complete()
	combat.start_run(chosen_protocol)
	get_tree().paused = false


func _cycle_protocol(direction: int) -> void:
	if _available_protocols.is_empty():
		return
	_protocol_index = posmod(_protocol_index + direction, _available_protocols.size())
	_refresh_launch_screen()


func _refresh_launch_screen() -> void:
	if _available_protocols.is_empty():
		_available_protocols = [RunProtocolCatalog.STANDARD]
	var protocol_id := _available_protocols[_protocol_index]
	var definition := RunProtocolCatalog.get_definition(protocol_id)
	var best_total_seconds := floori(_profile.best_time_seconds)
	profile_summary.text = "MOMENTUM %d   •   RUNS %d   •   WINS %d   •   SURVIVAL %02d:%02d   •   CLEARS %d" % [
		_profile.momentum,
		_profile.completed_runs,
		_profile.victories,
		best_total_seconds / 60,
		best_total_seconds % 60,
		_profile.best_clear_count,
	]
	var recent_count := _profile.get_recent_run_count()
	var recent_text := "NO RECORDED RUNS" if recent_count == 0 else "RECENT  •  %d / %d WINS" % [_profile.get_recent_win_count(), recent_count]
	var feedback_count := _profile.get_recent_replay_feedback_count()
	if feedback_count > 0:
		recent_text += "  •  REPLAY YES %d / %d" % [_profile.get_recent_replay_yes_count(), feedback_count]
	var top_playtest_tag := _profile.get_top_recent_playtest_tag()
	if not top_playtest_tag.is_empty():
		recent_text += "  •  TOP NOTE %s %d / %d" % [
			str(ProgressProfileModel.PLAYTEST_TAG_NAMES[top_playtest_tag]),
			_profile.get_recent_playtest_tag_frequency(top_playtest_tag),
			_profile.get_recent_playtest_tag_count(),
		]
	mastery_summary.text = "BUILD MASTERY  •  %d / %d   •   %s\nNEXT CLEAR  •  %s" % [
		_profile.get_mastery_count(),
		ProgressProfileModel.MASTERY_IDS.size(),
		recent_text,
		_profile.get_next_mastery_goal(),
	]
	protocol_name.text = str(definition.name)
	protocol_description.text = str(definition.description)
	protocol_reward.text = "MOMENTUM REWARD  ×%.2f" % float(definition.reward_multiplier)
	var upcoming := RunProtocolCatalog.get_next_unlock(_profile.momentum)
	next_unlock.text = "ALL PROTOCOLS UNLOCKED" if upcoming.is_empty() else "NEXT UNLOCK  •  %s AT %d MOMENTUM" % [upcoming.name, upcoming.required]
	previous_protocol.disabled = _available_protocols.size() <= 1
	next_protocol.disabled = _available_protocols.size() <= 1


func _on_feedback_choice(index: int) -> void:
	if index < 0 or index >= ProgressProfileModel.REPLAY_INTENTS.size():
		return
	if _feedback_stage == &"intent":
		_record_replay_intent(ProgressProfileModel.REPLAY_INTENTS[index])
	elif _feedback_stage == &"tag" and index < _feedback_tag_options.size():
		_record_playtest_tag(_feedback_tag_options[index])


func _record_replay_intent(intent: String) -> void:
	if not _profile.record_latest_replay_intent(intent):
		return
	_save_profile()
	_feedback_stage = &"tag"
	_feedback_tag_options = (
		ProgressProfileModel.POSITIVE_PLAYTEST_TAGS.duplicate()
		if intent == "yes"
		else ProgressProfileModel.ISSUE_PLAYTEST_TAGS.duplicate()
	)
	_show_playtest_tags(game_over_feedback_prompt, game_over_feedback_buttons)
	_show_playtest_tags(victory_feedback_prompt, victory_feedback_buttons)


func _record_playtest_tag(tag: String) -> void:
	if not _profile.record_latest_playtest_tag(tag):
		return
	_save_profile()
	_feedback_stage = &"complete"
	_apply_playtest_tag_feedback(game_over_feedback_prompt, game_over_feedback_buttons, tag)
	_apply_playtest_tag_feedback(victory_feedback_prompt, victory_feedback_buttons, tag)


func _reset_replay_feedback(prompt: Label, buttons: Array[Button]) -> void:
	_feedback_stage = &"intent"
	_feedback_tag_options.clear()
	prompt.text = "PLAYTEST  •  WOULD YOU RUN AGAIN?"
	for index in range(buttons.size()):
		buttons[index].text = ProgressProfileModel.REPLAY_INTENTS[index].to_upper()
		buttons[index].disabled = false


func _copy_latest_playtest_report(button: Button) -> void:
	var report_json := _profile.get_latest_playtest_report_json()
	if report_json.is_empty():
		return
	DisplayServer.clipboard_set(report_json)
	button.text = "✓ REPORT COPIED"


func _show_playtest_tags(prompt: Label, buttons: Array[Button]) -> void:
	prompt.text = "PLAYTEST  •  WHAT STOOD OUT?  •  OPTIONAL"
	for index in range(buttons.size()):
		var tag := _feedback_tag_options[index]
		buttons[index].text = str(ProgressProfileModel.PLAYTEST_TAG_NAMES[tag])
		buttons[index].disabled = false


func _apply_playtest_tag_feedback(prompt: Label, buttons: Array[Button], selected_tag: String) -> void:
	prompt.text = "PLAYTEST LOGGED  •  THANK YOU"
	for index in range(buttons.size()):
		var tag := _feedback_tag_options[index]
		buttons[index].text = "%s%s" % ["✓  " if tag == selected_tag else "", str(ProgressProfileModel.PLAYTEST_TAG_NAMES[tag])]
		buttons[index].disabled = true


func _record_run_progress(victory: bool) -> Dictionary:
	if _run_recorded:
		return _run_result
	_run_recorded = true
	var summary := combat.run_stats.snapshot(combat.elapsed_time, combat.enemies_defeated, combat.build)
	summary["victory"] = victory
	summary["protocol_id"] = str(combat.selected_protocol)
	summary["world_seed"] = int(world.generated_seed)
	_run_result = _profile.record_run(combat.elapsed_time, combat.enemies_defeated, victory, summary)
	_run_result["summary"] = summary
	_save_profile()
	return _run_result


func _format_run_recap(headline: String, result: Dictionary) -> String:
	var summary: Dictionary = result.get("summary", {})
	var elapsed_seconds := floori(float(summary.get("elapsed_seconds", 0.0)))
	var phase_name := _get_recap_phase_name(StringName(str(summary.get("phase_reached", "breakaway"))))
	var upgrade_count := (summary.get("upgrade_history", []) as Array).size()
	var progress_text := "+%d MOMENTUM  •  TOTAL %d" % [
		int(result.get("momentum_earned", 0)),
		int(result.get("momentum_total", 0)),
	]
	var unlock_names: Array[String] = []
	for protocol_id in result.get("new_unlocks", []):
		unlock_names.append(str(RunProtocolCatalog.get_definition(StringName(protocol_id)).name))
	if not unlock_names.is_empty():
		progress_text += "  •  UNLOCKED %s" % ", ".join(unlock_names)
	var mastery_names: Array[String] = []
	for mastery_id in result.get("new_masteries", []):
		mastery_names.append(combat.build.get_upgrade_name(StringName(mastery_id)))
	if not mastery_names.is_empty():
		progress_text += "\nNEW MASTERY  •  %s" % " / ".join(mastery_names)
	var record_names: Array[String] = []
	for record_id in result.get("new_records", []):
		match StringName(record_id):
			&"survival":
				record_names.append("SURVIVAL")
			&"clears":
				record_names.append("CLEARS")
			&"damage":
				record_names.append("DAMAGE")
			&"distance":
				record_names.append("DISTANCE")
	var record_text := "RUN LOGGED  •  CHASE THE NEXT RECORD" if record_names.is_empty() else "NEW BEST  •  %s" % " / ".join(record_names)
	var banishes_used := int(summary.get("banishes_used", 0))
	var banish_label := "BANISH" if banishes_used == 1 else "BANISHES"
	var apex_id := StringName(str(summary.get("apex_id", "")))
	var apex_text := "APEX  •  NOT REACHED"
	if ApexCatalogModel.is_valid(apex_id):
		apex_text = "APEX  •  %s  •  %s" % [
			ApexCatalogModel.get_title(apex_id),
			"BROKEN" if bool(summary.get("victory", false)) else "UNBROKEN",
		]
	var catalyst_id := StringName(str(summary.get("catalyst_id", "")))
	var drive_text := "DRIVE  •  NOT TUNED"
	if catalyst_id in RunBuild.CATALYST_IDS:
		drive_text = "DRIVE  •  %s  •  %d%% HOT" % [
			combat.build.get_upgrade_name(catalyst_id),
			roundi(float(summary.get("catalyst_uptime", 0.0)) * 100.0),
		]
	var arsenal_id := StringName(str(summary.get("arsenal_id", "")))
	var arsenal_text := "ARSENAL  •  NOT CHOSEN"
	if arsenal_id in RunBuild.ARSENAL_IDS:
		arsenal_text = "ARSENAL  •  %s" % combat.build.get_upgrade_name(arsenal_id)
	drive_text = "%s\n%s" % [arsenal_text, drive_text]
	return "%s\n\n%s  •  LEVEL %d\n%s\nDRAFT  •  %d UPGRADES  •  %d REROLLS  •  %d %s\n%s\n%02d:%02d  •  %d CLEARED  •  %d ELITES  •  %s\n%s\n%d DAMAGE  •  %d TAKEN  •  %d REPAIRED / %d CORES\n%s\n%s\n%.1f KM TRAVERSED  •  %d M/S PEAK  •  %d DASHES\n\n%s\n%s" % [
		headline,
		str(summary.get("build_name", "UNCOMMITTED")),
		int(summary.get("level", 1)),
		drive_text,
		upgrade_count,
		int(summary.get("rerolls_used", 0)),
		banishes_used,
		banish_label,
		combat.run_stats.get_build_cadence_text(),
		elapsed_seconds / 60,
		elapsed_seconds % 60,
		int(summary.get("enemies_defeated", 0)),
		int(summary.get("elite_defeats", 0)),
		phase_name,
		apex_text,
		roundi(float(summary.get("damage_dealt", 0.0))),
		roundi(float(summary.get("damage_taken", 0.0))),
		roundi(float(summary.get("integrity_recovered", 0.0))),
		int(summary.get("recovery_pickups", 0)),
		combat.run_stats.get_damage_breakdown_text(),
		combat.run_stats.get_damage_taken_breakdown_text(),
		float(summary.get("distance_meters", 0.0)) / 1000.0,
		roundi(float(summary.get("maximum_speed", 0.0))),
		int(summary.get("dash_count", 0)),
		progress_text,
		record_text,
	]


func _get_recap_phase_name(phase_id: StringName) -> String:
	match phase_id:
		&"pressure":
			return "PRESSURE"
		&"redline":
			return "REDLINE"
		&"overrun":
			return "OVERRUN"
		&"apex":
			return "THE APEX"
		_:
			return "BREAKAWAY"


func _apply_accessibility() -> void:
	camera.set_reduced_motion(_profile.reduced_motion)
	ball.set_reduced_motion(_profile.reduced_motion)
	combat.set_accessibility(_profile.reduced_motion, _profile.high_contrast_telegraphs)


func _apply_audio_levels() -> void:
	audio.set_levels(_profile.master_volume, _profile.music_volume, _profile.effects_volume)


func _pause_run() -> void:
	if not _run_started or game_over_overlay.visible or victory_overlay.visible or level_up_overlay.visible:
		return
	pause_summary.text = "%s  •  %s\n%s\nLEVEL %d  •  %d CLEARED  •  %d M/S  •  SEED %s" % [
		combat.get_formatted_time(),
		_phase_name,
		combat.get_objective_status(),
		combat.build.level,
		combat.enemies_defeated,
		roundi(ball.get_horizontal_speed()),
		str(world.generated_seed),
	]
	pause_loadout.text = combat.build.get_loadout_summary()
	_cancel_restart_confirmation()
	pause_overlay.visible = true
	get_tree().paused = true
	pause_resume_button.grab_focus()


func _resume_run() -> void:
	settings_overlay.visible = false
	pause_overlay.visible = false
	_settings_return_to_pause = false
	_cancel_restart_confirmation()
	get_tree().paused = false


func _request_restart() -> void:
	if not _restart_armed:
		_restart_armed = true
		pause_restart_button.text = "CONFIRM RESTART"
		pause_restart_warning.text = "Press again to abandon this run. Progress from it will not be recorded."
		pause_restart_warning.add_theme_color_override("font_color", Color(1.0, 0.48, 0.3))
		pause_restart_button.grab_focus()
		return
	_restart_scene()


func _cancel_restart_confirmation() -> void:
	_restart_armed = false
	if not is_instance_valid(pause_restart_button):
		return
	pause_restart_button.text = "RESTART RUN"
	pause_restart_warning.text = "Restart requires confirmation. The current run will not be recorded."
	pause_restart_warning.add_theme_color_override("font_color", Color(0.72, 0.58, 0.58))


func _restart_scene() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()


func _open_settings(from_pause: bool = false) -> void:
	_settings_return_to_pause = from_pause
	if from_pause:
		pause_overlay.visible = false
	settings_overlay.visible = true
	settings_back_button.text = "BACK TO PAUSE" if from_pause else "BACK TO LAUNCH"
	master_volume_slider.grab_focus()


func _close_settings() -> void:
	settings_overlay.visible = false
	if _settings_return_to_pause:
		pause_overlay.visible = true
		_settings_return_to_pause = false
		pause_resume_button.grab_focus()
	else:
		accessibility_button.grab_focus()


func _refresh_input_prompts() -> void:
	if _using_gamepad:
		controls.text = "LEFT STICK steer / boost / brake   •   A hop   •   LB / RB dash   •   START pause"
		select_hint.text = "D-PAD TO SELECT"
		launch_hint.text = "A TO LAUNCH   •   SURVIVE 20:00 AND BREAK THE APEX"
		game_over_retry.text = "RUN AGAIN  •  A"
		victory_retry.text = "RUN AGAIN  •  A"
		pause_hint.text = "START TO RESUME  •  A TO SELECT"
	else:
		controls.text = "A / D steer   •   W boost   •   S brake   •   Space hop   •   Shift / Alt dash   •   Esc pause"
		select_hint.text = "A / D OR ARROW KEYS"
		launch_hint.text = "ENTER / SPACE TO LAUNCH   •   SURVIVE 20:00 AND BREAK THE APEX"
		game_over_retry.text = "RUN AGAIN  •  R"
		victory_retry.text = "RUN AGAIN  •  R"
		pause_hint.text = "ESC TO RESUME  •  ENTER TO SELECT"
	if level_up_overlay.visible:
		_refresh_draft_controls()
	if tutorial_card.visible:
		tutorial_card.text = _onboarding.get_message(_using_gamepad)


func _get_upgrade_accent(family: StringName) -> Color:
	match family:
		RunBuild.DASHBREAKER:
			return Color(1.0, 0.55, 0.24)
		RunBuild.STORMTRAIL:
			return Color(0.22, 1.0, 0.62)
		RunBuild.ARCSTORM:
			return Color(0.32, 0.82, 1.0)
		&"catalyst":
			return Color(1.0, 0.76, 0.22)
		&"arsenal":
			return Color(0.96, 0.38, 1.0)
		_:
			return Color(0.92, 0.78, 1.0)


func _refresh_settings() -> void:
	reduced_motion_toggle.set_pressed_no_signal(_profile.reduced_motion)
	high_contrast_toggle.set_pressed_no_signal(_profile.high_contrast_telegraphs)
	guidance_toggle.set_pressed_no_signal(_profile.guidance_enabled)
	replay_guidance_button.disabled = not _profile.onboarding_completed
	master_volume_slider.set_value_no_signal(_profile.master_volume * 100.0)
	music_volume_slider.set_value_no_signal(_profile.music_volume * 100.0)
	effects_volume_slider.set_value_no_signal(_profile.effects_volume * 100.0)
	_refresh_audio_labels()


func _on_visual_accessibility_changed(_enabled: bool) -> void:
	_profile.reduced_motion = reduced_motion_toggle.button_pressed
	_profile.high_contrast_telegraphs = high_contrast_toggle.button_pressed
	_apply_accessibility()
	_save_profile()


func _on_guidance_toggled(enabled: bool) -> void:
	_profile.guidance_enabled = enabled
	if enabled:
		_profile.onboarding_completed = false
	replay_guidance_button.disabled = not _profile.onboarding_completed
	_save_profile()


func _replay_guidance() -> void:
	_profile.guidance_enabled = true
	_profile.onboarding_completed = false
	_refresh_settings()
	_save_profile()


func _on_audio_levels_changed(_value: float) -> void:
	_profile.master_volume = float(master_volume_slider.value) / 100.0
	_profile.music_volume = float(music_volume_slider.value) / 100.0
	_profile.effects_volume = float(effects_volume_slider.value) / 100.0
	_apply_audio_levels()
	_refresh_audio_labels()
	_save_profile()


func _refresh_audio_labels() -> void:
	master_volume_label.text = "%d%%" % roundi(_profile.master_volume * 100.0)
	music_volume_label.text = "%d%%" % roundi(_profile.music_volume * 100.0)
	effects_volume_label.text = "%d%%" % roundi(_profile.effects_volume * 100.0)


func _update_onboarding(delta: float) -> void:
	if not _run_started or _onboarding.is_complete() or get_tree().paused:
		return
	var steering := (
		Input.get_action_strength(InputBindings.MOVE_LEFT) > 0.2
		or Input.get_action_strength(InputBindings.MOVE_RIGHT) > 0.2
	)
	var hopping: bool = not ball.is_on_floor() and ball.velocity.y > 2.0
	if not _onboarding.update(delta, steering, ball.is_dashing(), hopping):
		return
	if _onboarding.is_complete():
		tutorial_card.visible = false
		_profile.onboarding_completed = true
		_save_profile()
	else:
		tutorial_card.text = _onboarding.get_message(_using_gamepad)


func _save_profile() -> void:
	if _persistence_enabled and not _profile.save():
		push_warning("Overrush could not save the current profile.")
