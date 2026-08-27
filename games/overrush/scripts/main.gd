extends Node3D

const ProgressProfileModel = preload("res://scripts/progress_profile.gd")
const RunProtocolCatalog = preload("res://scripts/run_protocols.gd")
const RunOnboardingModel = preload("res://scripts/run_onboarding.gd")

@onready var world = $World
@onready var ball = $RunnerBall
@onready var camera = $Camera3D
@onready var combat: CombatDirector = $CombatDirector
@onready var audio: OverrushAudioDirector = $AudioDirector
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
@onready var start_overlay: Control = $HUD/StartOverlay
@onready var profile_summary: Label = $HUD/StartOverlay/LaunchPanel/Content/ProfileSummary
@onready var protocol_name: Label = $HUD/StartOverlay/LaunchPanel/Content/ProtocolName
@onready var protocol_description: Label = $HUD/StartOverlay/LaunchPanel/Content/ProtocolDescription
@onready var protocol_reward: Label = $HUD/StartOverlay/LaunchPanel/Content/ProtocolReward
@onready var next_unlock: Label = $HUD/StartOverlay/LaunchPanel/Content/NextUnlock
@onready var previous_protocol: Button = $HUD/StartOverlay/LaunchPanel/Content/ProtocolControls/Previous
@onready var next_protocol: Button = $HUD/StartOverlay/LaunchPanel/Content/ProtocolControls/Next
@onready var launch_button: Button = $HUD/StartOverlay/LaunchPanel/Content/Launch
@onready var accessibility_button: Button = $HUD/StartOverlay/LaunchPanel/Content/Accessibility
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


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = true
	_persistence_enabled = DisplayServer.get_name() != "headless" and not has_meta("overrush_disable_persistence")
	ball.respawn(world.get_spawn_position())
	ball.dash_state_changed.connect(camera.set_dash_active)
	ball.dash_state_changed.connect(audio.play_dash)
	ball.integrity_changed.connect(_on_integrity_changed)
	ball.damaged.connect(audio.play_hurt)
	ball.defeated.connect(_on_runner_defeated)
	combat.build_changed.connect(_on_build_changed)
	combat.level_up_requested.connect(_on_level_up_requested)
	combat.phase_changed.connect(_on_phase_changed)
	combat.event_announced.connect(_on_event_announced)
	combat.apex_health_changed.connect(_on_apex_health_changed)
	combat.run_victory.connect(_on_run_victory)
	combat.run_failed.connect(_on_run_failed)
	combat.enemy_defeated_feedback.connect(audio.play_enemy_defeat)
	combat.enemy_hit_feedback.connect(audio.play_enemy_hit)
	combat.experience_collected_feedback.connect(audio.play_pickup)
	combat.attack_warning_feedback.connect(audio.play_attack_warning)
	for index in range(level_up_buttons.size()):
		level_up_buttons[index].pressed.connect(_choose_upgrade.bind(index))
	previous_protocol.pressed.connect(_cycle_protocol.bind(-1))
	next_protocol.pressed.connect(_cycle_protocol.bind(1))
	launch_button.pressed.connect(begin_run)
	accessibility_button.pressed.connect(_open_settings)
	settings_back_button.pressed.connect(_close_settings)
	reduced_motion_toggle.toggled.connect(_on_visual_accessibility_changed)
	high_contrast_toggle.toggled.connect(_on_visual_accessibility_changed)
	guidance_toggle.toggled.connect(_on_guidance_toggled)
	replay_guidance_button.pressed.connect(_replay_guidance)
	master_volume_slider.value_changed.connect(_on_audio_levels_changed)
	music_volume_slider.value_changed.connect(_on_audio_levels_changed)
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
	if DisplayServer.get_name() == "headless" and not has_meta("overrush_manual_start"):
		call_deferred("begin_run", RunProtocolCatalog.STANDARD)


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
	_update_onboarding(_delta)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if settings_overlay.visible:
		if event.keycode == KEY_ESCAPE:
			_close_settings()
		return
	if start_overlay.visible:
		if event.keycode == KEY_LEFT or event.keycode == KEY_A:
			_cycle_protocol(-1)
		elif event.keycode == KEY_RIGHT or event.keycode == KEY_D:
			_cycle_protocol(1)
		elif event.keycode == KEY_ENTER or event.keycode == KEY_SPACE:
			begin_run()
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
	audio.play_level_up()
	_current_upgrade_options = options
	if is_instance_valid(_event_tween):
		_event_tween.kill()
	event_banner.visible = false
	level_up_overlay.visible = true
	var offers_evolution := false
	for upgrade_id in options:
		if combat.build.is_evolution_upgrade(upgrade_id):
			offers_evolution = true
			break
	if combat.build.core_path.is_empty():
		level_up_title.text = "CHOOSE YOUR ENGINE"
		level_up_prompt.text = "Commit to a combat geometry for this run"
	elif offers_evolution:
		level_up_title.text = "EVOLVE %s" % combat.build.get_build_name()
		level_up_prompt.text = "Choose one exclusive geometry, or defer the fork with a standard upgrade"
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
	audio.play_defeat()
	combat.stop_run()
	var result := _record_run_progress(false)
	game_over_message.text = _format_run_recap("RUN ENDED", result, "PRESS R TO BREAK THROUGH AGAIN")
	game_over_overlay.visible = true
	get_tree().paused = true


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
	apex_label.text = "THE APEX  •  %d%%" % roundi(current / maxf(maximum, 1.0) * 100.0)


func _on_run_victory() -> void:
	audio.play_victory()
	var result := _record_run_progress(true)
	victory_message.text = _format_run_recap("APEX BROKEN", result, "PRESS R TO OVERRUN AGAIN")
	victory_overlay.visible = true
	get_tree().paused = true


func _on_run_failed(reason: String) -> void:
	audio.play_defeat()
	var result := _record_run_progress(false)
	game_over_message.text = _format_run_recap(reason, result, "PRESS R TO BREAK THROUGH AGAIN")
	game_over_overlay.visible = true
	get_tree().paused = true


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
	start_overlay.visible = false
	_run_started = true
	_onboarding.reset(_profile.onboarding_completed or not _profile.guidance_enabled)
	tutorial_card.text = _onboarding.get_message()
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
	protocol_name.text = str(definition.name)
	protocol_description.text = str(definition.description)
	protocol_reward.text = "MOMENTUM REWARD  ×%.2f" % float(definition.reward_multiplier)
	var upcoming := RunProtocolCatalog.get_next_unlock(_profile.momentum)
	next_unlock.text = "ALL PROTOCOLS UNLOCKED" if upcoming.is_empty() else "NEXT UNLOCK  •  %s AT %d MOMENTUM" % [upcoming.name, upcoming.required]
	previous_protocol.disabled = _available_protocols.size() <= 1
	next_protocol.disabled = _available_protocols.size() <= 1


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


func _format_run_recap(headline: String, result: Dictionary, retry_text: String) -> String:
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
	return "%s\n\n%s  •  LEVEL %d  •  %d UPGRADES\n%02d:%02d  •  %d CLEARED  •  %d ELITES  •  %s\n%d DAMAGE  •  %d TAKEN\n%s\n%.1f KM TRAVERSED  •  %d M/S PEAK  •  %d DASHES\n\n%s\n%s\n\n%s" % [
		headline,
		str(summary.get("build_name", "UNCOMMITTED")),
		int(summary.get("level", 1)),
		upgrade_count,
		elapsed_seconds / 60,
		elapsed_seconds % 60,
		int(summary.get("enemies_defeated", 0)),
		int(summary.get("elite_defeats", 0)),
		phase_name,
		roundi(float(summary.get("damage_dealt", 0.0))),
		roundi(float(summary.get("damage_taken", 0.0))),
		combat.run_stats.get_damage_breakdown_text(),
		float(summary.get("distance_meters", 0.0)) / 1000.0,
		roundi(float(summary.get("maximum_speed", 0.0))),
		int(summary.get("dash_count", 0)),
		progress_text,
		record_text,
		retry_text,
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
	audio.set_levels(_profile.master_volume, _profile.music_volume)


func _open_settings() -> void:
	settings_overlay.visible = true
	reduced_motion_toggle.grab_focus()


func _close_settings() -> void:
	settings_overlay.visible = false
	accessibility_button.grab_focus()


func _refresh_settings() -> void:
	reduced_motion_toggle.set_pressed_no_signal(_profile.reduced_motion)
	high_contrast_toggle.set_pressed_no_signal(_profile.high_contrast_telegraphs)
	guidance_toggle.set_pressed_no_signal(_profile.guidance_enabled)
	replay_guidance_button.disabled = not _profile.onboarding_completed
	master_volume_slider.set_value_no_signal(_profile.master_volume * 100.0)
	music_volume_slider.set_value_no_signal(_profile.music_volume * 100.0)
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
	_apply_audio_levels()
	_refresh_audio_labels()
	_save_profile()


func _refresh_audio_labels() -> void:
	master_volume_label.text = "%d%%" % roundi(_profile.master_volume * 100.0)
	music_volume_label.text = "%d%%" % roundi(_profile.music_volume * 100.0)


func _update_onboarding(delta: float) -> void:
	if not _run_started or _onboarding.is_complete() or get_tree().paused:
		return
	var steering: bool = Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_RIGHT)
	var hopping: bool = not ball.is_on_floor() and ball.velocity.y > 2.0
	if not _onboarding.update(delta, steering, ball.is_dashing(), hopping):
		return
	if _onboarding.is_complete():
		tutorial_card.visible = false
		_profile.onboarding_completed = true
		_save_profile()
	else:
		tutorial_card.text = _onboarding.get_message()


func _save_profile() -> void:
	if _persistence_enabled and not _profile.save():
		push_warning("Overrush could not save the current profile.")
