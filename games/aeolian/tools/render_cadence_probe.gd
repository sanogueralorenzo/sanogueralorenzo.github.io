extends Node

const REPORT_DIRECTORY := "res://reports/cadence"


func run(game_app: Node) -> void:
	var cap := _argument_value("--cadence-cap=", "unknown")
	var directory := ProjectSettings.globalize_path(REPORT_DIRECTORY)
	if DirAccess.make_dir_recursive_absolute(directory) != OK:
		get_tree().quit(21)
		return
	game_app.start_foundation_course()
	await get_tree().physics_frame
	var course := game_app.get_node("SessionRoot").get_child(0)
	var player := course.get_node("Windboard") as WindboardController
	var geometry := course.get_node("CourseGeometry") as MovementCourseGeometry
	player.set_input_provider(_neutral_intent, true)
	var scenarios := []
	scenarios.append(await _run_scenario(player, geometry, &"crest", 0.0, 66.0, 28.0, 120))
	scenarios.append(await _run_scenario(player, geometry, &"bank", 0.0, 160.0, 25.0, 210))
	scenarios.append(await _run_scenario(player, geometry, &"jump", 0.0, 288.0, 26.0, 150))
	scenarios.append(await _run_scenario(player, geometry, &"wall", -7.0, 462.0, 42.0, 60))
	var report := {
		"cap": cap,
		"physics_hz": Engine.physics_ticks_per_second,
		"measured_render_fps": Performance.get_monitor(Performance.TIME_FPS),
		"rendering_method": RenderingServer.get_current_rendering_method(),
		"rendering_driver": RenderingServer.get_current_rendering_driver_name(),
		"video_adapter": RenderingServer.get_video_adapter_name(),
		"scenarios": scenarios,
	}
	var path := "%s/cap-%s.json" % [REPORT_DIRECTORY, cap]
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		get_tree().quit(22)
		return
	file.store_string(JSON.stringify(report, "  "))
	file.close()
	game_app.return_to_title()
	# Let queued session deletion and the dummy audio backend finish teardown.
	await get_tree().create_timer(0.10).timeout
	AppLog.info(&"cadence", "Native cadence probe complete", {"cap": cap, "path": path})
	get_tree().quit(0)


func _run_scenario(
		player: WindboardController,
		geometry: MovementCourseGeometry,
		name: StringName,
		x: float,
		d: float,
		speed_mps: float,
		ticks: int
	) -> Dictionary:
	var normal := geometry.surface_normal(x, d)
	var heading := Vector3.FORWARD.slide(normal).normalized()
	var origin := Vector3(x, geometry.surface_height(x, d), -d) + Vector3.UP * 0.86
	player.place_for_test(Transform3D(Basis.IDENTITY, origin), heading, speed_mps, normal)
	player.event_history.clear()
	for tick in ticks:
		await get_tree().physics_frame
	var events: Array[String] = []
	for event: Dictionary in player.event_history:
		var label := String(event.kind)
		if event.kind == &"state":
			label += ":%s>%s:%s" % [event.data.from, event.data.to, event.data.reason]
		elif event.kind == &"crash":
			label += ":%s" % event.data.cause
		events.append(label)
	return {
		"name": name,
		"position": [player.global_position.x, player.global_position.y, player.global_position.z],
		"speed_mps": player.motion_model.velocity.length(),
		"state": WindboardController.state_label(player.motion_state),
		"crash_cause": player.crash_cause,
		"events": events,
	}


func _neutral_intent(_tick: int) -> InputIntent:
	return InputIntent.new()


func _argument_value(prefix: String, fallback: String) -> String:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with(prefix):
			return argument.trim_prefix(prefix)
	return fallback
