extends Node3D

@onready var desert: ProceduralDesert = $Desert
@onready var rider: Sandboarder = $Sandboarder
@onready var follow_camera: Camera3D = $FollowCamera
@onready var audio_director: OverrushAudioDirector = $AudioDirector
@onready var stats_label: Label = $HUD/Stats
@onready var boost_label: Label = $HUD/BoostStatus
@onready var controls_label: Label = $HUD/Controls
@onready var start_overlay: Control = $HUD/StartOverlay
@onready var launch_button: Button = $HUD/StartOverlay/LaunchPanel/Content/Launch
@onready var pause_overlay: Control = $HUD/PauseOverlay
@onready var resume_button: Button = $HUD/PauseOverlay/PausePanel/Content/Resume
@onready var restart_button: Button = $HUD/PauseOverlay/PausePanel/Content/Restart

var run_active := false
var elapsed_time := 0.0
var start_height := 0.0
var _using_gamepad := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	OverrushInputBindings.ensure_actions()
	rider.air_boost_state_changed.connect(_on_air_boost_state_changed)
	rider.air_boost_used.connect(_on_air_boost_used)
	launch_button.pressed.connect(begin_run)
	resume_button.pressed.connect(resume_run)
	restart_button.pressed.connect(restart_run)
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
	start_overlay.visible = false
	pause_overlay.visible = false
	get_tree().paused = false
	follow_camera.set_controls_enabled(true)


func pause_run() -> void:
	if not run_active:
		return
	get_tree().paused = true
	pause_overlay.visible = true
	follow_camera.set_controls_enabled(false)
	resume_button.grab_focus()


func resume_run() -> void:
	pause_overlay.visible = false
	get_tree().paused = false
	follow_camera.set_controls_enabled(true)


func restart_run() -> void:
	elapsed_time = 0.0
	desert.begin_new_run()
	rider.respawn()
	follow_camera.snap_to_target()
	start_height = desert.get_world_position(rider.global_position).y
	resume_run()


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
