extends CanvasLayer

@onready var panel: Control = %Panel
@onready var readout: Label = %Readout

var _time_until_refresh := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not OS.is_debug_build():
		queue_free()
		return
	panel.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"toggle_debug") and not event.is_echo():
		panel.visible = not panel.visible
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not panel.visible:
		return
	_time_until_refresh -= delta
	if _time_until_refresh > 0.0:
		return
	_time_until_refresh = 0.25
	readout.text = "FPS %d\nFrame %.2f ms\nPhysics %.2f ms\nDraw calls %d\nNodes %d\nInput %s" % [
		int(Performance.get_monitor(Performance.TIME_FPS)),
		float(Performance.get_monitor(Performance.TIME_PROCESS)) * 1000.0,
		float(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)) * 1000.0,
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		InputService.device_label(),
	]
	var players := get_tree().get_nodes_in_group(&"windboard_player")
	if not players.is_empty() and players[0] is WindboardController:
		var telemetry: Dictionary = players[0].get_telemetry()
		readout.text += "\n\nState %s · tick %d\nSpeed %.1f m/s · %.0f km/h\nTangent %.1f · lateral %.1f · slip %.2f\nStability %.2f · terrain stress %.3f · slope %.1f°\nFloor %s · casts %s/%s\nCoyote %.2f · recontact %.2f\nSurface %s · crash %s" % [
			telemetry.state,
			telemetry.physics_tick,
			telemetry.speed_mps,
			telemetry.speed_mps * 3.6,
			telemetry.tangent_speed_mps,
			telemetry.lateral_speed_mps,
			telemetry.slip_ratio,
			telemetry.stability,
			telemetry.last_terrain_stress_damage,
			telemetry.slope_degrees,
			telemetry.is_on_floor,
			telemetry.support_now,
			telemetry.support_ahead,
			telemetry.coyote_seconds,
			telemetry.recontact_seconds,
			telemetry.surface,
			telemetry.crash_cause,
		]
