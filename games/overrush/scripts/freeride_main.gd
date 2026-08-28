extends Node3D

const SETTINGS_PATH := "user://overrush_settings.cfg"
const SETTINGS_SECTION := "accessibility"

@onready var desert: ProceduralDesert = $Desert
@onready var rider: Sandboarder = $Sandboarder
@onready var follow_camera: Camera3D = $FollowCamera
@onready var audio_director: OverrushAudioDirector = $AudioDirector
@onready var stats_label: Label = $HUD/Stats
@onready var boost_label: Label = $HUD/BoostStatus
@onready var landing_label: Label = $HUD/LandingFeedback
@onready var controls_label: Label = $HUD/Controls
@onready var start_overlay: Control = $HUD/StartOverlay
@onready var launch_button: Button = $HUD/StartOverlay/LaunchPanel/Content/Launch
@onready var pause_overlay: Control = $HUD/PauseOverlay
@onready var pause_title: Label = $HUD/PauseOverlay/PausePanel/Content/Title
@onready var resume_button: Button = $HUD/PauseOverlay/PausePanel/Content/Resume
@onready var restart_button: Button = $HUD/PauseOverlay/PausePanel/Content/Restart
@onready var start_reduced_motion: CheckButton = $HUD/StartOverlay/LaunchPanel/Content/ReducedMotion
@onready var start_look_sensitivity: HSlider = $HUD/StartOverlay/LaunchPanel/Content/LookSensitivity/Slider
@onready var start_master_volume: HSlider = $HUD/StartOverlay/LaunchPanel/Content/MasterVolume/Slider
@onready var pause_reduced_motion: CheckButton = $HUD/PauseOverlay/PausePanel/Content/ReducedMotion
@onready var pause_look_sensitivity: HSlider = $HUD/PauseOverlay/PausePanel/Content/LookSensitivity/Slider
@onready var pause_master_volume: HSlider = $HUD/PauseOverlay/PausePanel/Content/MasterVolume/Slider

var run_active := false
var elapsed_time := 0.0
var start_height := 0.0
var _using_gamepad := false
var _landing_feedback_time := 0.0
var _run_crashed := false
var _reduced_motion := false
var _look_sensitivity := 1.0
var _master_volume := 0.8


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	OverrushInputBindings.ensure_actions()
	rider.air_boost_state_changed.connect(_on_air_boost_state_changed)
	rider.air_boost_used.connect(_on_air_boost_used)
	rider.landing_scored.connect(_on_landing_scored)
	rider.jumped.connect(_on_jumped)
	rider.crashed.connect(_on_rider_crashed)
	launch_button.pressed.connect(begin_run)
	resume_button.pressed.connect(resume_run)
	restart_button.pressed.connect(restart_run)
	_connect_settings_controls()
	if DisplayServer.get_name() != "headless":
		load_settings()
	else:
		_apply_settings_to_runtime()
	_sync_settings_controls()
	rider.respawn()
	follow_camera.snap_to_target()
	start_height = desert.get_world_position(rider.global_position).y
	_update_control_prompt()
	_update_boost_status(true, false)
	if DisplayServer.get_name() == "headless" and not get_meta(&"overrush_manual_start", false):
		begin_run()
	else:
		get_tree().paused = true
		follow_camera.set_controls_enabled(false)
		launch_button.grab_focus()


func _process(delta: float) -> void:
	if run_active and not get_tree().paused:
		elapsed_time += delta
		_update_stats()
		_landing_feedback_time = maxf(0.0, _landing_feedback_time - delta)
		landing_label.modulate.a = clampf(_landing_feedback_time / 0.35, 0.0, 1.0)


func _unhandled_input(event: InputEvent) -> void:
	if OverrushInputBindings.is_gamepad_event(event):
		_using_gamepad = true
		_update_control_prompt()
	elif OverrushInputBindings.is_keyboard_or_mouse_event(event):
		_using_gamepad = false
		_update_control_prompt()
	if event.is_action_pressed(OverrushInputBindings.PAUSE) and run_active:
		if get_tree().paused:
			resume_run()
		else:
			pause_run()
		get_viewport().set_input_as_handled()


func begin_run() -> void:
	run_active = true
	_run_crashed = false
	_configure_pause_overlay()
	start_overlay.visible = false
	pause_overlay.visible = false
	get_tree().paused = false
	follow_camera.set_controls_enabled(true)


func pause_run() -> void:
	if not run_active:
		return
	get_tree().paused = true
	_configure_pause_overlay()
	pause_overlay.visible = true
	follow_camera.set_controls_enabled(false)
	resume_button.grab_focus()


func resume_run() -> void:
	if _run_crashed:
		return
	pause_overlay.visible = false
	get_tree().paused = false
	follow_camera.set_controls_enabled(true)


func restart_run() -> void:
	elapsed_time = 0.0
	_landing_feedback_time = 0.0
	landing_label.modulate.a = 0.0
	_run_crashed = false
	run_active = true
	_configure_pause_overlay()
	desert.begin_new_run()
	rider.respawn()
	follow_camera.snap_to_target()
	start_height = desert.get_world_position(rider.global_position).y
	resume_run()


func set_accessibility_settings(
	reduced_motion: bool,
	look_sensitivity: float,
	master_volume: float,
	persist := true,
) -> void:
	_reduced_motion = reduced_motion
	_look_sensitivity = clampf(look_sensitivity, 0.5, 2.0)
	_master_volume = clampf(master_volume, 0.0, 1.0)
	_apply_settings_to_runtime()
	_sync_settings_controls()
	if persist:
		save_settings()


func save_settings(path := SETTINGS_PATH) -> Error:
	var config := ConfigFile.new()
	config.set_value(SETTINGS_SECTION, "reduced_motion", _reduced_motion)
	config.set_value(SETTINGS_SECTION, "look_sensitivity", _look_sensitivity)
	config.set_value(SETTINGS_SECTION, "master_volume", _master_volume)
	return config.save(path)


func load_settings(path := SETTINGS_PATH) -> bool:
	var config := ConfigFile.new()
	if config.load(path) != OK:
		_apply_settings_to_runtime()
		return false
	_reduced_motion = bool(config.get_value(SETTINGS_SECTION, "reduced_motion", false))
	_look_sensitivity = clampf(float(config.get_value(SETTINGS_SECTION, "look_sensitivity", 1.0)), 0.5, 2.0)
	_master_volume = clampf(float(config.get_value(SETTINGS_SECTION, "master_volume", 0.8)), 0.0, 1.0)
	_apply_settings_to_runtime()
	_sync_settings_controls()
	return true


func _connect_settings_controls() -> void:
	for toggle in [start_reduced_motion, pause_reduced_motion]:
		toggle.toggled.connect(_on_reduced_motion_toggled)
	for slider in [start_look_sensitivity, pause_look_sensitivity]:
		slider.value_changed.connect(_on_look_sensitivity_changed)
	for slider in [start_master_volume, pause_master_volume]:
		slider.value_changed.connect(_on_master_volume_changed)


func _apply_settings_to_runtime() -> void:
	follow_camera.set_reduced_motion(_reduced_motion)
	follow_camera.set_look_sensitivity_multiplier(_look_sensitivity)
	audio_director.set_levels(_master_volume, audio_director.music_level, audio_director.effects_level)


func _sync_settings_controls() -> void:
	for toggle in [start_reduced_motion, pause_reduced_motion]:
		toggle.set_pressed_no_signal(_reduced_motion)
	for slider in [start_look_sensitivity, pause_look_sensitivity]:
		slider.set_value_no_signal(_look_sensitivity)
	for slider in [start_master_volume, pause_master_volume]:
		slider.set_value_no_signal(_master_volume)


func _on_reduced_motion_toggled(enabled: bool) -> void:
	set_accessibility_settings(enabled, _look_sensitivity, _master_volume, DisplayServer.get_name() != "headless")


func _on_look_sensitivity_changed(value: float) -> void:
	set_accessibility_settings(_reduced_motion, value, _master_volume, DisplayServer.get_name() != "headless")


func _on_master_volume_changed(value: float) -> void:
	set_accessibility_settings(_reduced_motion, _look_sensitivity, value, DisplayServer.get_name() != "headless")


func _update_stats() -> void:
	var minutes := int(elapsed_time) / 60
	var seconds := int(elapsed_time) % 60
	var descent := maxf(0.0, start_height - desert.get_world_position(rider.global_position).y)
	stats_label.text = "%02d:%02d\n%03d km/h\n%.0f m descent\n%.2f km ridden" % [
		minutes,
		seconds,
		roundi(rider.get_horizontal_speed() * 3.6),
		descent,
		rider.distance_traveled / 1000.0,
	]


func _update_control_prompt() -> void:
	controls_label.text = (
		"LEFT STICK  CARVE   •   RIGHT STICK  LOOK\nA  JUMP   •   LB  AIR BOOST   •   MENU  PAUSE"
		if _using_gamepad
		else "WASD  CARVE   •   MOUSE  LOOK\nSPACE  JUMP   •   SHIFT  AIR BOOST   •   ESC  PAUSE"
	)


func _on_air_boost_state_changed(available: bool, airborne: bool) -> void:
	_update_boost_status(available, airborne)


func _update_boost_status(available: bool, airborne: bool) -> void:
	if available:
		boost_label.text = "AIR BOOST  •  READY" if airborne else "AIR BOOST  •  CHARGED"
		boost_label.modulate = Color("#fff2bd")
	else:
		boost_label.text = "AIR BOOST  •  SPENT"
		boost_label.modulate = Color("#8a7869")


func _on_air_boost_used() -> void:
	audio_director.play_air_boost()
	follow_camera.set_speed_burst_active(true)
	get_tree().create_timer(0.22).timeout.connect(func() -> void: follow_camera.set_speed_burst_active(false))


func _on_jumped() -> void:
	audio_director.play_jump()


func _on_rider_crashed(obstacle_kind: StringName, impact_speed: float) -> void:
	_run_crashed = true
	run_active = false
	get_tree().paused = true
	pause_overlay.visible = true
	pause_title.text = "%s IMPACT\n%03d KM/H" % [String(obstacle_kind).to_upper(), roundi(impact_speed * 3.6)]
	resume_button.visible = false
	restart_button.text = "DROP AGAIN"
	follow_camera.set_controls_enabled(false)
	restart_button.grab_focus()
	audio_director.play_landing(SandboardMotion.LANDING_ROUGH)


func _configure_pause_overlay() -> void:
	pause_title.text = "PAUSED"
	resume_button.visible = true
	restart_button.text = "RETURN TO SUMMIT"


func _on_landing_scored(rating: StringName, _score: float, _impact_speed: float) -> void:
	_landing_feedback_time = 1.35
	match rating:
		SandboardMotion.LANDING_CLEAN:
			landing_label.text = "CLEAN LANDING  •  MOMENTUM HELD"
			landing_label.modulate = Color("#fff0ad")
		SandboardMotion.LANDING_SOLID:
			landing_label.text = "SOLID LANDING"
			landing_label.modulate = Color("#e9bf72")
		_:
			landing_label.text = "ROUGH LANDING  •  RECOVER"
			landing_label.modulate = Color("#d88962")
	audio_director.play_landing(rating)
