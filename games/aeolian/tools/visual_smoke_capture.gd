extends Node

const REPORT_DIRECTORY := "res://reports/visual-smoke"


func run(game_app: Node) -> void:
	var absolute_report_directory := ProjectSettings.globalize_path(REPORT_DIRECTORY)
	var error := DirAccess.make_dir_recursive_absolute(absolute_report_directory)
	if error != OK:
		AppLog.error(&"visual_smoke", "Could not create capture directory", {"error": error})
		get_tree().quit(5)
		return
	await _settle_frames(3)
	if get_viewport().gui_get_focus_owner() == null \
			or get_viewport().gui_get_focus_owner().name != &"StartButton":
		AppLog.error(&"visual_smoke", "Title primary action did not receive focus")
		get_tree().quit(9)
		return
	if await _capture("title.png") != OK:
		get_tree().quit(6)
		return
	await _press_action(&"ui_accept")
	await _settle_frames(3)
	if game_app.get_node("TitleScreen").visible or game_app.get_node("SessionRoot").get_child_count() != 1:
		AppLog.error(&"visual_smoke", "Focused title action did not start the course")
		get_tree().quit(10)
		return
	if await _capture("course.png") != OK:
		get_tree().quit(7)
		return
	var course := game_app.get_node("SessionRoot").get_child(0)
	var player := course.get_node("Windboard") as WindboardController
	var geometry := course.get_node("CourseGeometry") as MovementCourseGeometry
	var normal := geometry.surface_normal(0.0, 102.0)
	var heading := Vector3.FORWARD.slide(normal).normalized()
	var origin := Vector3(0.0, geometry.surface_height(0.0, 102.0), -102.0) \
		+ Vector3.UP * 0.86
	player.place_for_test(Transform3D(Basis.IDENTITY, origin), heading, 28.0, normal)
	course.get_node("CameraRig")._snap_to_target()
	await _settle_frames(8)
	if await _capture("course-speed.png") != OK:
		get_tree().quit(13)
		return
	player.motion_model.stability = 0.55
	var recovery_prompt := course.get_node("CourseHud/HudRoot/RecoveryPrompt") as Control
	if not await _wait_for_visibility(recovery_prompt, true, 8):
		AppLog.error(&"visual_smoke", "Low stability did not show recovery guidance")
		get_tree().quit(14)
		return
	await _settle_frames(3)
	if await _capture("recovery.png") != OK:
		get_tree().quit(15)
		return
	player.motion_model.stability = 1.0
	await _settle_frames(2)
	await _press_action(&"pause")
	await _settle_frames(2)
	if not game_app.get_node("PauseMenu").visible \
			or get_viewport().gui_get_focus_owner() == null \
			or get_viewport().gui_get_focus_owner().name != &"ResumeButton":
		AppLog.error(&"visual_smoke", "Pause action or pause-menu focus failed")
		get_tree().quit(11)
		return
	if await _capture("pause.png") != OK:
		get_tree().quit(8)
		return
	await _press_action(&"ui_accept")
	await _settle_frames(2)
	if game_app.get_node("PauseMenu").visible or get_tree().paused:
		AppLog.error(&"visual_smoke", "Focused resume action did not resume")
		get_tree().quit(12)
		return
	var fatal_d := 462.0
	var fatal_normal := geometry.surface_normal(-7.0, fatal_d)
	var fatal_heading := Vector3.FORWARD.slide(fatal_normal).normalized()
	var fatal_origin := Vector3(
		-7.0, geometry.surface_height(-7.0, fatal_d), -fatal_d
	) + Vector3.UP * 0.86
	player.place_for_test(
		Transform3D(Basis.IDENTITY, fatal_origin), fatal_heading, 30.0, fatal_normal
	)
	for frame in 60:
		await get_tree().physics_frame
		if player.motion_state == WindboardController.MotionState.CRASHED:
			break
	if player.motion_state != WindboardController.MotionState.CRASHED \
			or not course.get_node("CourseHud/HudRoot/CrashCenter").visible:
		AppLog.error(&"visual_smoke", "Fatal impact did not show restart guidance")
		get_tree().quit(16)
		return
	# The native renderer can lag the scene tree by more than one frame after a
	# hidden full-screen container becomes visible. Capture only after the layout
	# and render thread have both settled.
	await _settle_frames(8)
	if await _capture("crash.png") != OK:
		get_tree().quit(17)
		return
	await _press_action(&"restart_run")
	await get_tree().physics_frame
	if player.motion_state != WindboardController.MotionState.GROUNDED \
			or course.get_node("CourseHud/HudRoot/CrashCenter").visible:
		AppLog.error(&"visual_smoke", "Restart did not clear crash guidance")
		get_tree().quit(18)
		return
	game_app.return_to_title()
	await _settle_frames(3)
	AppLog.info(&"visual_smoke", "Rendered smoke frames captured", {
		"directory": REPORT_DIRECTORY,
	})
	get_tree().quit(0)


func _capture(file_name: String) -> Error:
	# Native rendering can have multiple submitted frames in flight. Waiting for
	# three completed draws prevents the archived texture from preceding a recent
	# visibility/layout transition even when process frames run much faster.
	for frame in 3:
		await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := "%s/%s" % [REPORT_DIRECTORY, file_name]
	var error := image.save_png(path)
	if error != OK:
		AppLog.error(&"visual_smoke", "Could not save rendered smoke frame", {
			"file": file_name,
			"error": error,
		})
	return error


func _settle_frames(count: int) -> void:
	for index in count:
		await get_tree().process_frame


func _wait_for_visibility(control: Control, expected: bool, maximum_frames: int) -> bool:
	for frame in maximum_frames:
		await get_tree().process_frame
		if control.visible == expected:
			return true
	return false


func _press_action(action: StringName) -> void:
	var pressed := InputEventAction.new()
	pressed.action = action
	pressed.pressed = true
	Input.parse_input_event(pressed)
	await get_tree().process_frame
	var released := InputEventAction.new()
	released.action = action
	released.pressed = false
	Input.parse_input_event(released)
